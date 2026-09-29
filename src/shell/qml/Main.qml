import QtQuick
import QtQuick.Window
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import B1air.Daemon
import "./Ui"
import "./Services"
import "WindowRegistry.js" as Registry

Scope {
    id: rootScope

    // Quickshell puts a white "Config reloaded — run qs log …" box over the
    // desktop after every reload, and every update reloads: it is a developer
    // notice, not something a user can act on. A failed reload still shows
    // its box, which is the one worth seeing.
    Connections {
        target: Quickshell
        function onReloadCompleted() { Quickshell.inhibitReloadPopup(); }
    }

    // Translucent panels only where the compositor blurs behind them: swayFX
    // with blur on. Plain sway shows the wallpaper sharp through a
    // translucent panel, and over a busy picture the text is unreadable.
    readonly property bool compositorBlurs: Sway.swayfx
    Binding {
        target: Design
        property: "translucent"
        value: rootScope.compositorBlurs && (!Settings.loaded || Settings.blurEnabled)
    }

    // Ui/Design cannot read Services/Settings itself — the standalone apps load
    // Ui without a Quickshell runtime — so the shell is what joins the two. The
    // accent picker in Appearance had no effect on anything before this.
    Binding {
        target: Design
        property: "accentName"
        value: Settings.accentName
    }

    // Services/Theme is a singleton, and a QML singleton is not created until
    // something refers to it — so without this the theme was only applied once
    // the Appearance page happened to be opened, and never at login.
    // Only once Settings has actually read the file. Applying eagerly here
    // used the schema default instead of the saved choice, and since applying
    // publishes the palette, that overwrote the active theme with the default
    // on every login — the picked theme survived in settings.json and was
    // undone on disk a moment later.
    Component.onCompleted: {
        if (Settings.loaded && Settings.themeName)
            Theme.apply(Settings.themeName, false);

        // Warm the focused-screen lookup, so the first toast or OSD is placed
        // correctly instead of appearing on screen one and hopping across once
        // the answer arrives. The singleton is created lazily otherwise — at
        // the moment something first asks it a question.
        Screens.refresh();

        // Start the clipboard monitor with the shell.
        //
        // Clipboard is a singleton too, and the only thing that referred to it
        // was ClipboardPopup — which is built lazily, when the popup is first
        // opened. So the monitor did not exist until the user went looking at
        // the history, and the history it then showed was everything copied
        // since that moment: on a fresh login, nothing. Measured with an empty
        // store: copy three times, open the popup, zero records.
        Clipboard.items.count;

        // Same reason: a focus timer that only exists while its window is open
        // is not a timer.
        Focus.phase;
    }

    // "Open Guide on Login" in Startup settings, which wrote
    // `openGuideAtStartup` and was read by nothing — the guide never appeared,
    // whatever the toggle said.
    //
    // On the Settings signal rather than in Component.onCompleted, because at
    // that point Settings has not read the file yet and the schema default
    // (off) is what would be seen. The delay is for the bar and the popups to
    // be up first: a guide that opens into a half-built shell lands behind it.
    Connections {
        target: Settings
        function onLoadedChanged() {
            if (Settings.loaded && Settings.openGuideAtStartup)
                guideDelay.start();
        }
    }

    Timer {
        id: guideDelay
        interval: 2000
        onTriggered: masterWindow.handleIpcCommand("toggle:guide:", true)
    }

    Connections {
        target: Settings
        function onLoadedChanged() {
            if (Settings.loaded && Settings.themeName)
                Theme.apply(Settings.themeName, false);
        }
    }

    // The daemon asking for a panel, over the bus.
    //
    // `b1air-shell toggle control` calls org.b1air.Shell.Toggle on the daemon,
    // and the daemon used to answer by launching a whole `quickshell` process
    // — a second QML host, started and torn down for each keystroke — to hand
    // one string to this instance. It emits a signal now, and this is what
    // catches it. Same commands, same handler, no process.
    Connections {
        target: Daemon

        function onPanelRequested(action, panel, arg) {
            switch (action) {
            case "toggle":
                masterWindow.handleIpcCommand("toggle:" + panel + ":" + (arg || ""), true);
                break;
            case "open":
                masterWindow.handleIpcCommand("open:" + panel + ":" + (arg || ""), true);
                break;
            case "close":
                masterWindow.handleIpcCommand("close", true);
                break;
            case "forceReload":
                Quickshell.reload(true);
                break;
            }
        }
    }

    // Turns B1air.Daemon call failures into notifications.
    DaemonErrors {}

    // ── Recycling ────────────────────────────────────────────────────────────
    // The shell grows with use and does not shrink. Measured on this desktop:
    // 135 MB when it starts, 190 MB after every popup has been opened once, and
    // 330 MB after twelve hours of ordinary use. Almost none of that is
    // reclaimable from inside — freeing the heap gave back nothing, Qt's cache
    // calls about 10 MB — because it is live: services started by the popups,
    // their device and network lists, compiled QML.
    //
    // A fresh process is the only thing that returns it, so the shell starts
    // one when nobody can see it happen: long idle, which by then means the
    // screen is off (swayidle blanks it at 10 minutes), and only when all of
    // this holds —
    //   · it has actually grown (a fresh shell is not restarted for nothing),
    //   · it has been up an hour — otherwise a shell that starts large would
    //     be restarted every fifteen minutes through a night of idle,
    //   · the daemon's supervisor started it and will start the next one,
    //   · nothing is open, no toast is showing, and no focus timer is running,
    //     since that timer lives only in memory.
    // Notification history and the clipboard are on disk and come back.
    IdleMonitor {
        id: recycleIdle
        timeout: 15 * 60
        // A video playing or anything else inhibiting idle is someone watching.
        respectInhibitors: true
        onIsIdleChanged: if (isIdle) rootScope.maybeRecycle()
    }

    readonly property int recycleAboveMB: 260
    readonly property real startedAt: Date.now()

    function maybeRecycle() {
        // memoryMB and supervised arrived with this change, in the plugin —
        // which install.sh copies with sudo and `make install` does not. A
        // shell running new QML against the old plugin skips this rather than
        // throwing on every idle.
        if (typeof Daemon.memoryMB !== "function" || typeof Daemon.supervised !== "function") return;
        if (Date.now() - rootScope.startedAt < 60 * 60 * 1000) return;
        const mb = Daemon.memoryMB();
        if (mb < rootScope.recycleAboveMB) return;
        if (!Daemon.supervised()) return;
        if (masterWindow.isVisible || Notifications.activeToasts.count > 0 || Focus.active) return;
        console.log("[b1air-shell] recycling after idle at " + mb + " MB");
        Qt.quit();
    }

    // One bar per screen.
    //
    // TopBar was instantiated once, and a PanelWindow with no screen set lands
    // on the first one — so on a two-monitor desktop the second monitor had no
    // bar at all: no clock, no workspaces, no tray, nothing. Confirmed on a
    // live session with two outputs, where the bar covered x 0..1920 of a
    // 3840-wide desktop and the rest was bare.
    //
    // Odd, given how much of this project is about multiple monitors: a
    // Displays page, a persisted layout, per-output brightness.
    Variants {
        model: Quickshell.screens

        delegate: TopBar {
            required property var modelData
            screen: modelData
            onRequestCommand: (cmd, notify) => masterWindow.handleIpcCommand(cmd, notify)
        }
    }

    PanelWindow {
        id: masterWindow
        color: "transparent"
    
    IpcHandler {
        id: shellIpc
        target: "main"
    
        function forceReload() {
            Quickshell.reload(true) 
        }

        function close() {
            masterWindow.handleIpcCommand("close", true)
        }

        function open(targetWidget: string, arg: string) {
            masterWindow.handleIpcCommand("open:" + targetWidget + ":" + (arg || ""), true)
        }

        function toggle(targetWidget: string, arg: string) {
            masterWindow.handleIpcCommand("toggle:" + targetWidget + ":" + (arg || ""), true)
        }

        function toggleControl() { masterWindow.handleIpcCommand("toggle:control:", true) }
        // The notification centre: the same window, opened straight on the
        // list rather than on the tile grid. It was reachable only as
        // `toggle notifications`, with no named function beside its siblings
        // and no key binding.
        function toggleNotifications() { masterWindow.handleIpcCommand("toggle:notifications:", true) }
        function toggleBattery() { masterWindow.handleIpcCommand("toggle:battery:", true) }
        function toggleVolume() { masterWindow.handleIpcCommand("toggle:volume:", true) }
        function toggleMusic() { masterWindow.handleIpcCommand("toggle:music:", true) }
        function toggleMonitors() { masterWindow.handleIpcCommand("toggle:monitors:", true) }
        function toggleGuide() { masterWindow.handleIpcCommand("toggle:guide:", true) }
        function togglePollKit() { masterWindow.handleIpcCommand("toggle:pollkit:", true) }
        function toggleSettings() { masterWindow.handleIpcCommand("toggle:settings:", true) }
        function toggleCalendar() { masterWindow.handleIpcCommand("toggle:calendar:", true) }
        function toggleClipboard() { masterWindow.handleIpcCommand("toggle:clipboard:", true) }
        function toggleFocusTime() { masterWindow.handleIpcCommand("toggle:focustime:", true) }

        // The focus timer, for a key binding or a script. Its window is a
        // screen-time dashboard that happens to hold the controls; starting a
        // 25-minute interval should not require opening it.
        function focusStart() { Focus.start() }
        function focusPause() { Focus.pause() }
        function focusToggleTimer() { Focus.toggle() }
        function focusSkip() { Focus.skip() }
        function focusStop() { Focus.stop() }
        function focusState(): string {
            return Focus.phase + " " + (Focus.running ? "running" : "paused")
                 + " " + Focus.remaining + "s left, " + Focus.completedWork + " done";
        }
        function toggleNetworkWifi() { masterWindow.handleIpcCommand("toggle:network:wifi", true) }
        function toggleNetworkBt() { masterWindow.handleIpcCommand("toggle:network:bt", true) }
        function toggleNetwork() { masterWindow.handleIpcCommand("toggle:network:bt", true) }
        function openAudioFull() { masterWindow.handleIpcCommand("open:audioFull:", true) }
        function openPowerFull() { masterWindow.handleIpcCommand("open:powerFull:", true) }
        function openNetFull() { masterWindow.handleIpcCommand("open:netFull:", true) }
        function openMediaFull() { masterWindow.handleIpcCommand("open:mediaFull:", true) }
        function openSession() { masterWindow.handleIpcCommand("open:session:", true) }
        function toggleSession() { masterWindow.handleIpcCommand("toggle:session:", true) }
        function openKeyboard() { masterWindow.handleIpcCommand("open:keyboard:", true) }
        function toggleKeyboard() { masterWindow.handleIpcCommand("toggle:keyboard:", true) }
        function openLauncher() { masterWindow.handleIpcCommand("open:launcher:", true) }
        function toggleLauncher() { masterWindow.handleIpcCommand("toggle:launcher:", true) }
        function openSpotlight() { masterWindow.handleIpcCommand("open:spotlight:", true) }
        function toggleSpotlight() { masterWindow.handleIpcCommand("toggle:spotlight:", true) }
        function openLaunchpad() { masterWindow.handleIpcCommand("open:launchpad:", true) }
        function toggleLaunchpad() { masterWindow.handleIpcCommand("toggle:launchpad:", true) }
        function openMenu() { masterWindow.handleIpcCommand("open:menu:", true) }
        function toggleMenu() { masterWindow.handleIpcCommand("toggle:menu:", true) }
        // No switcher: Alt+Tab is sway's own `focus next` again (keybinds.conf).
        function openEmoji() { masterWindow.handleIpcCommand("open:emoji:", true) }
        function toggleEmoji() { masterWindow.handleIpcCommand("toggle:emoji:", true) }
        function openZones() { masterWindow.handleIpcCommand("open:zones:", true) }
        function toggleZones() { masterWindow.handleIpcCommand("toggle:zones:", true) }
        function openRuler() { masterWindow.handleIpcCommand("open:ruler:", true) }
        function toggleRuler() { masterWindow.handleIpcCommand("toggle:ruler:", true) }
        function openShelf() { masterWindow.handleIpcCommand("open:shelf:", true) }
        function toggleShelf() { masterWindow.handleIpcCommand("toggle:shelf:", true) }
        function openQuickLook(file: string) { masterWindow.handleIpcCommand("open:quicklook:" + (file || ""), true) }
        function toggleQuickLook(file: string) { masterWindow.handleIpcCommand("toggle:quicklook:" + (file || ""), true) }
    }

    WlrLayershell.namespace: "qs-master"
    WlrLayershell.layer: WlrLayer.Overlay
    
    exclusionMode: ExclusionMode.Ignore
    focusable: isVisible

    // Quickshell deprecated setting width/height on a PanelWindow; it wants the
    // implicit pair and warned about both on every start.
    implicitWidth: Screen.width
    implicitHeight: Screen.height

    visible: isVisible
    readonly property string scriptDir: Quickshell.env("QS_SCRIPT_DIR") || (Quickshell.env("HOME") + "/.config/sway/scripts")

    // Without a mask this layer-shell surface claims pointer input across the
    // whole screen — including the transparent strip over the TopBar — even
    // though nothing is drawn there. That silently ate every click meant for
    // TopBar's own surface underneath whenever a popup was open. Masking to
    // just the below-the-bar MouseArea lets clicks over the bar fall through.
    mask: Region {
        item: masterWindow.isVisible ? clickCatcher : null
    }

    Item {
        id: topBarHole
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: 42
    }

    MouseArea {
        id: clickCatcher
        anchors.top: topBarHole.bottom
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        enabled: masterWindow.isVisible
        onClicked: masterWindow.switchWidget("hidden", "")
    }

    Component.onCompleted: {
        // State is now strictly in memory; no need to write to /tmp on startup.
    }

    property string currentActive: "hidden"

    property bool isVisible: false
    property string activeArg: ""
    property bool disableMorph: false 
    property int morphDuration: 120
    property int exitDuration: 90 // Controls how fast the outgoing widget disappears
    property bool firstOpen: false

    property real animW: 1
    property real animH: 1
    property real animX: 0
    property real animY: 0
    
    property real targetW: 1
    property real targetH: 1

    // Was fed by its own jq subprocess reading settings.json; now one typed
    // read from the store, which is watching the file anyway.
    readonly property real globalUiScale: Design.uiScale

    // NOT the real Wayland output scale (Screen.devicePixelRatio) — Qt Quick
    // already renders every window, layer-shell surfaces included, at the
    // compositor's real scale on its own; nothing here has to ask for that.
    // Binding this to devicePixelRatio doubled it: the surface was already
    // being drawn at (say) 1.5x by Qt, and then every Design.s() size in it
    // got multiplied by another 1.5x on top, so the bar rendered enormous at
    // any scale other than 1.0. uiScale is a separate, purely cosmetic
    // "make the shell chrome bigger/smaller" preference on top of whatever
    // the real display scale already is — which is exactly why it used to be
    // a manual setting instead of derived from anything.
    Binding { target: Design; property: "uiScale"; value: 1.0 }
    property string lastIpcCommand: ""
    property string loadedWidget: ""

    // Permanent notification history placeholder. The Sway port keeps this
    // passive so Main.qml does not conflict with any existing notification daemon.
    ListModel {
        id: globalNotificationHistory
    }

    property var notifModel: globalNotificationHistory

    onGlobalUiScaleChanged: {
        handleNativeScreenChange();
    }

    function getLayout(name) {
        return Registry.getLayout(name, 0, 0, Screen.width, Screen.height, masterWindow.globalUiScale,
                                  Settings.barPosition === "bottom");
    }

    Connections {
        target: Screen
        function onWidthChanged() { masterWindow.handleNativeScreenChange(); }
        function onHeightChanged() { masterWindow.handleNativeScreenChange(); }
    }

    Connections {
        target: (typeof Bridge !== "undefined") ? Bridge : null
        function onIpcTriggered(action, target, arg) {
            masterWindow.handleIpcCommand(action + ":" + target + ":" + (arg || ""), true);
        }
    }

    // Shrink the window to what the surface actually needs.
    //
    // A popup's size came only from WindowRegistry, so a Control Center with
    // half its widgets switched off opened at the height of a full one and put
    // the rest of it on screen as empty panel. A surface that knows its own
    // content height says so through a `contentHeight` property; the registry
    // figure becomes the ceiling, because a surface with more content than that
    // is meant to scroll rather than grow off the screen. Surfaces that do not
    // declare one — the launcher and Spotlight among them, where a window that
    // resizes as you type would be worse than one that does not — are left
    // exactly as they were.
    function refitHeight() {
        const item = widgetStack.currentItem;
        if (!item) return;
        const t = getLayout(masterWindow.currentActive);
        if (!t) return;

        // Width too, for a panel built of cards side by side: take one away and
        // what is left over is dead panel rather than a narrower one. And a
        // popup that changes width has to be put back where it was anchored —
        // the registry's x was computed from the registry's width, so a
        // centred panel that shrinks without this drifts left and a
        // right-hand one crawls away from the edge it belongs to.
        if (item.contentWidth !== undefined && item.contentWidth > 0) {
            const wRoom = Screen.width - Design.s(Design.space.md) * 2;
            const fittedW = Math.max(Design.s(200), Math.min(wRoom, item.contentWidth));
            const centred = Math.abs(t.rx - (Screen.width - t.w) / 2) <= 2;
            masterWindow.animX = centred ? Math.floor((Screen.width - fittedW) / 2)
                                         : (t.rx + t.w - fittedW);
            masterWindow.targetW = fittedW;
            masterWindow.animW = fittedW;
        }

        if (item.contentHeight === undefined || item.contentHeight <= 0)
            return;
        // Both directions. The registry figure was being used as a ceiling, so
        // a panel with less in it shrank and a panel with more in it stayed put
        // and scrolled. The only real ceiling is the screen: whatever is left
        // between the bar and the bottom edge, less a margin so a full-height
        // panel does not sit flush against it.
        const room = Screen.height - t.ry - Design.s(Design.space.md);
        const fitted = Math.max(Design.s(120), Math.min(room, item.contentHeight));
        // Both, and this is the whole of it: targetH sizes the content and
        // animH sizes the surface it sits in. Setting only the first left the
        // window at its full height with the shrunken panel centred inside,
        // which read as the panel having drifted down the screen rather than
        // having got smaller.
        masterWindow.targetH = fitted;
        masterWindow.animH = fitted;
    }

    function handleNativeScreenChange() {
        if (masterWindow.currentActive === "hidden") return;
        
        let t = getLayout(masterWindow.currentActive);
        if (t) {
            masterWindow.animX = t.rx;
            masterWindow.animY = t.ry;
            masterWindow.animW = t.w;
            masterWindow.animH = t.h;
            masterWindow.targetW = t.w;
            masterWindow.targetH = t.h;
        }
    }

    // `requestActivate()` is not a method on a layer-shell window — this threw
    // a TypeError every single time a popup opened, aborting the handler.
    // Pre-existing, and only visible once the shell was actually run.
    // Keyboard focus comes from `focusable: isVisible` above; nothing else is
    // needed.

    Item {
        x: masterWindow.animX
        y: masterWindow.animY
        width: masterWindow.animW
        height: masterWindow.animH
        clip: true 

        // Smoother easing type: OutExpo makes animations feel snappy yet perfectly fluid
        Behavior on x { enabled: !masterWindow.disableMorph; NumberAnimation { duration: masterWindow.morphDuration; easing.type: Easing.OutExpo } }
        Behavior on y { enabled: !masterWindow.disableMorph; NumberAnimation { duration: masterWindow.morphDuration; easing.type: Easing.OutExpo } }
        Behavior on width { enabled: !masterWindow.disableMorph; NumberAnimation { duration: masterWindow.morphDuration; easing.type: Easing.OutExpo } }
        Behavior on height { enabled: !masterWindow.disableMorph; NumberAnimation { duration: masterWindow.morphDuration; easing.type: Easing.OutExpo } }

        opacity: masterWindow.isVisible ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: masterWindow.morphDuration; easing.type: Easing.InOutSine } }

        MouseArea {
            anchors.fill: parent
        }

        Item {
            anchors.centerIn: parent
            width: masterWindow.targetW
            height: masterWindow.targetH

            StackView {
                id: widgetStack
                anchors.fill: parent
                focus: true
                
                Keys.onEscapePressed: {
                    switchWidget("hidden", "");
                    event.accepted = true;
                }

                onCurrentItemChanged: {
                    if (currentItem) currentItem.forceActiveFocus();
                    masterWindow.refitHeight();
                }

                // The height is not settled when the surface first appears —
                // a card that has not loaded its data yet, or a widget switched
                // off while the panel is open, changes it afterwards. Follow it.
                Connections {
                    target: widgetStack.currentItem
                    ignoreUnknownSignals: true
                    function onContentHeightChanged() { masterWindow.refitHeight(); }
                    function onContentWidthChanged() { masterWindow.refitHeight(); }
                }

                replaceEnter: Transition {
                    ParallelAnimation {
                        NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: 120; easing.type: Easing.OutExpo }
                        NumberAnimation { property: "scale"; from: 0.98; to: 1.0; duration: 120; easing.type: Easing.OutCubic }
                    }
                }
                replaceExit: Transition {
                    ParallelAnimation {
                        // Uses the dynamically set exitDuration
                        NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; duration: masterWindow.exitDuration; easing.type: Easing.InCubic }
                        NumberAnimation { property: "scale"; from: 1.0; to: 1.01; duration: masterWindow.exitDuration; easing.type: Easing.InCubic }
                    }
                }
            }
        }
    }

    function switchWidget(newWidget, arg) {
        // REMOVED: Quickshell.execDetached file writing. State is strictly in memory now.

        prepTimer.stop();
        delayedClear.stop();

        if (newWidget === "hidden") {
            if (currentActive !== "hidden") {
                masterWindow.morphDuration = 120;
                masterWindow.exitDuration = 90;
                masterWindow.disableMorph = false;
                
                masterWindow.animW = 1;
                masterWindow.animH = 1;
                masterWindow.isVisible = false; 
                
                delayedClear.start();
            }
        } else {
            if (currentActive === "hidden") {
                masterWindow.morphDuration = 80;
                masterWindow.exitDuration = 60;
                masterWindow.disableMorph = true;
                masterWindow.firstOpen = true;
                
                let t = getLayout(newWidget);
                if (!t) return;
                masterWindow.animX = t.rx;
                masterWindow.animY = t.ry;
                masterWindow.animW = t.w;
                masterWindow.animH = t.h;
                masterWindow.targetW = t.w;
                masterWindow.targetH = t.h;

                executeSwitch(newWidget, arg, true);
                masterWindow.isVisible = true;
            } else {
                // Morphing directly between widgets
                masterWindow.morphDuration = 120;
                masterWindow.disableMorph = false;
                masterWindow.exitDuration = 90;
                
                executeSwitch(newWidget, arg, false);
            }
        }
    }

    Timer {
        id: prepTimer
        interval: 0
        property string newWidget: ""
        property string newArg: ""
        onTriggered: executeSwitch(newWidget, newArg, false)
    }

    // Which page inside a multi-page surface a widget name means. Used both when
    // the surface is created and when it is already on screen.
    function pageFor(w, a) {
        if (w === "wifi") return "wifi";
        if (w === "bluetooth") return "bluetooth";
        if (w === "sound" || w === "volume") return "sound";
        if (w === "power" || w === "battery") return "power";
        if (w === "network") return (a === "bt" || a === "bluetooth") ? "bluetooth" : "wifi";
        if (w === "control") return a || "main";
        if (w === "notifications") return "notifications";
        // The guide is the keybinding sheet, not the About page. "Open Guide
        // on Login" promises "the keybinding and tips modal" and this opened
        // System Specifications and a memory reading; About is still one page
        // away, and still reachable directly as `toggle settings about`.
        if (w === "guide") return "shortcuts";
        if (w === "focus") return "focus";
        // Registry entries that open the Settings window on one page. None of
        // these were listed here, so every one of them opened Settings on
        // whatever page it happened to be on — Displays, from a fresh start.
        // The Night Light tile's arrow, the Wallpaper and Displays entries and
        // the three "…Full" shortcuts all landed on the monitor layout.
        const settingsPage = {
            "nightlight": "nightlight", "wallpaper": "wallpaper", "appearance": "appearance",
            "input": "input", "monitors": "monitors", "audioFull": "audio",
            "powerFull": "power", "netFull": "network"
        };
        if (settingsPage[w] !== undefined) return settingsPage[w];
        if (w === "settings") {
            if (a === "wifi") return "network";
            if (a === "sound" || a === "volume") return "audio";
            if (a === "battery") return "power";
            return a || "";
        }
        return "";
    }

    function executeSwitch(newWidget, arg, immediate) {
        masterWindow.currentActive = newWidget;
        masterWindow.activeArg = arg;
        
        let t = getLayout(newWidget);
        if (!t) {
            return;
        }
        masterWindow.animX = t.rx;
        masterWindow.animY = t.ry;
        masterWindow.animW = t.w;
        masterWindow.animH = t.h;
        masterWindow.targetW = t.w;
        masterWindow.targetH = t.h;

        const sameComponent = masterWindow.loadedWidget !== ""
            && getLayout(masterWindow.loadedWidget)
            && getLayout(masterWindow.loadedWidget).comp === t.comp;

        if (sameComponent && widgetStack.currentItem) {
            const target = pageFor(newWidget, arg);
            if (target && widgetStack.currentItem.page !== undefined)
                widgetStack.currentItem.page = target;
            if (newWidget === "quicklook" && widgetStack.currentItem.filePath !== undefined)
                widgetStack.currentItem.filePath = arg;
            if (newWidget === "settings" && arg && !target && widgetStack.currentItem.searchQuery !== undefined)
                widgetStack.currentItem.searchQuery = arg;
            masterWindow.isVisible = true;
            masterWindow.firstOpen = false;
            masterWindow.disableMorph = false;
            widgetStack.currentItem.forceActiveFocus();
            return;
        }
        
        let props = {};
        if (newWidget === "control")
            props["notifModel"] = masterWindow.notifModel;
        const page = pageFor(newWidget, arg);
        if (page)
            props["page"] = page;
        if (newWidget === "quicklook" && arg)
            props["filePath"] = arg;
        if ((newWidget === "spotlight" || newWidget === "launchpad") && arg)
            props["query"] = arg;
        if (newWidget === "settings" && arg && !page)
            props["searchQuery"] = arg;

        if (immediate || masterWindow.firstOpen) {
            widgetStack.replace(t.comp, props, StackView.Immediate);
            masterWindow.firstOpen = false;
            masterWindow.disableMorph = false;
        } else {
            widgetStack.replace(t.comp, props);
        }
        masterWindow.loadedWidget = newWidget;
        
        masterWindow.isVisible = true;
    }

    // =========================================================
    // --- IPC: EVENT-DRIVEN WATCHER
    // =========================================================
    function handleIpcCommand(rawCmd, force) {
        rawCmd = rawCmd.trim();
        if (rawCmd === "" || (!force && rawCmd === masterWindow.lastIpcCommand)) return;

        masterWindow.lastIpcCommand = rawCmd;
        rawCmd = rawCmd.split("|")[0];

        let parts = rawCmd.split(":");
        let cmd = parts[0];

        if (cmd === "close") {
            switchWidget("hidden", "");
        } else if (cmd === "toggle" || cmd === "open") {
            let targetWidget = parts.length > 1 ? parts[1] : "";
            let arg = parts.length > 2 ? parts.slice(2).join(":") : "";

            delayedClear.stop();

            if (targetWidget === masterWindow.currentActive) {
                let currentItem = widgetStack.currentItem;

                // 1. Same surface, different page: hand it over instead of
                // reloading. Only `activeMode` was handled here, which the
                // page-based surfaces do not have — so asking for a specific
                // settings page while settings was open did nothing at all.
                const wantPage = arg !== "" ? pageFor(targetWidget, arg) : "";

                if (wantPage !== "" && currentItem && currentItem.page !== undefined
                    && currentItem.page !== wantPage) {
                    currentItem.page = wantPage;
                }
                else if (arg !== "" && currentItem && currentItem.activeMode !== undefined && currentItem.activeMode !== arg) {
                    currentItem.activeMode = arg;
                }
                // 2. If it's a toggle command and the tab matches (or no subtarget given), close it
                else if (cmd === "toggle") {
                    switchWidget("hidden", "");
                }
                // 3. If "open" and already on the correct tab, do nothing (stays open).

            } else if (getLayout(targetWidget)) {
                switchWidget(targetWidget, arg);
            }
        } else if (getLayout(cmd)) {
            // Fallback for old formatting
            let arg = parts.length > 1 ? parts.slice(1).join(":") : "";
            delayedClear.stop();

            if (cmd === masterWindow.currentActive) {
                let currentItem = widgetStack.currentItem;
                if (arg !== "" && currentItem && currentItem.activeMode !== undefined && currentItem.activeMode !== arg) {
                    currentItem.activeMode = arg;
                } else {
                    switchWidget("hidden", "");
                }
            } else {
                switchWidget(cmd, arg);
            }
        }
    }

    Timer {
        id: delayedClear
        interval: masterWindow.morphDuration 
        onTriggered: {
            masterWindow.currentActive = "hidden";
            masterWindow.disableMorph = false;
            // Retain cached widget in widgetStack for zero-latency, zero-CPU reopening
        }
    }

    // Free widget tree if idle for 5 minutes
    Timer {
        id: idleMemoryCleanup
        interval: 300000 // 5 minutes
        running: !masterWindow.isVisible && widgetStack.depth > 0
        repeat: false
        onTriggered: {
            if (!masterWindow.isVisible) {
                widgetStack.clear();
                masterWindow.loadedWidget = "";
                // What Qt can release once the surface is gone; see
                // B1airDaemon::trimMemory for what that is and is not.
                if (typeof Daemon.trimMemory === "function")
                    Qt.callLater(() => Daemon.trimMemory());
            }
        }
    }

    Loader {
        active: true
        source: "notifications/NotificationToasts.qml"
    }

    Loader {
        active: true
        source: "osd/OsdOverlay.qml"
    }
}
}
