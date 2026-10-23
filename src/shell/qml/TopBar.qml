import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Qt.labs.folderlistmodel
import Quickshell.Wayland
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import "./Ui"
import B1air.Daemon
import Quickshell.Services.Pipewire
import "./Services"

PanelWindow {
    // A bar island under the pointer: a faint wash over the same glass and
    // rim, not a lighter pane with a bright rim of its own colour.
    component HoverWash: Box {
        property bool shown: false
        anchors.fill: parent
        radius: parent.radius
        color: Design.tint(Design.text, 0.06)
        opacity: shown ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Design.duration.fast } }
    }

    id: topBar

    // sway itself is reached through B1air.Daemon's Sway, which finds its
    // socket and follows it across a sway restart.

    // ── Which screen this bar is on ──────────────────────────────────────────
    //
    // The bar has been on every screen since Main.qml started instantiating it
    // through Variants — but nothing in here ever asked *which* screen it was
    // on, so two monitors got two identical bars: the same tray, the same
    // clock, and the same workspace strip with the same pill lit, because
    // `focused` is global to the session rather than to an output.
    readonly property string outputName: topBar.screen ? topBar.screen.name : ""

    // ── Privacy and Caps Lock ────────────────────────────────────────────────
    //
    // The microphone is answered by PipeWire directly: a capture stream is a
    // node that is a stream and is not a sink, so anything recording shows up
    // without asking anyone. The camera has no such thing — V4L2 exposes no
    // in-use attribute and the lamp beside the lens is wired to the hardware —
    // so the daemon walks /proc for an open /dev/video* and pushes the answer
    // over the bus when it changes.
    readonly property bool micInUse: {
        const nodes = Pipewire.nodes ? Pipewire.nodes.values : [];
        for (const n of nodes)
            if (n && n.isStream && !n.isSink)
                return true;
        return false;
    }

    readonly property bool cameraInUse: Daemon.cameraInUse

    // Caps Lock, read off the LED the kernel already keeps. sway's IPC does not
    // report lock state and there is no protocol for it, so this is the file
    // the keyboard driver writes. The directory is listed rather than a path
    // guessed, because the input number differs per machine and per boot.
    property string capsLedPath: ""
    property bool capsOn: false

    FolderListModel {
        id: ledDir
        folder: "file:///sys/class/leds"
        nameFilters: ["*capslock*"]
        showFiles: true
        showDirs: true
        onCountChanged: {
            topBar.capsLedPath = ledDir.count > 0
                ? String(ledDir.get(0, "filePath")) + "/brightness" : "";
        }
    }

    FileView {
        id: capsLed
        path: topBar.capsLedPath
        printErrors: false
        onLoaded: topBar.capsOn = parseInt(capsLed.text()) > 0
        onLoadFailed: topBar.capsOn = false
    }

    // A keypress is not a file change sysfs will tell anyone about, so this is
    // read on a timer — one file, no process, and only while a lock LED was
    // actually found. Fast enough that the pill appears with the keystroke.
    Timer {
        interval: 250
        repeat: true
        running: topBar.capsLedPath !== ""
        onTriggered: capsLed.reload()
    }

    // The main display (Settings → Displays). If the chosen one is unplugged,
    // the first screen sway reports takes over, rather than no bar at all
    // being the full one. Always true with a single screen.
    readonly property bool isPrimary: Screens.primaryName === "" || topBar.outputName === Screens.primaryName

    /** A second or third bar carries less unless told otherwise. */
    readonly property bool reduced: !topBar.isPrimary && Settings.barSecondaryReduced

    /**
     * The workspace strip: 1..Settings.workspaceCount, plus anything sway has
     * outside that range.
     *
     * The bar used to draw only the workspaces sway currently reports, so
     * "Workspace count" in Settings → Native Top Bar — which says in as many
     * words "how many workspace numbers the bar shows" — changed nothing at
     * all. Showing the empty ones is also what makes them reachable: a
     * workspace you have never visited has no pill to click.
     */
    readonly property var workspaceSlots: {
        // Only the workspaces that live on this output. sway names the output
        // on every workspace it reports, and without this a three-monitor
        // desktop drew the same ten pills three times, each highlighting the
        // workspace focused somewhere else.
        const mine = {};
        for (const w of topBar.workspacesList) {
            // Called up over the others (Mod+S), never a pill of its own.
            if (w.name === "special")
                continue;
            if (!topBar.isPrimary && w.output !== undefined && topBar.outputName !== ""
                    && w.output !== topBar.outputName)
                continue;
            mine[String(w.name !== undefined ? w.name : w.num)] = w;
        }

        const out = [];
        // The unused numbers are offered by the primary bar only. Three bars
        // each offering to create workspace 7 is three answers to one
        // question — and sway puts a new workspace on the focused output
        // whichever of them was clicked.
        const count = topBar.isPrimary ? Math.max(1, Settings.workspaceCount || 10) : 0;
        for (let i = 1; i <= count; ++i) {
            const key = String(i);
            const w = mine[key];
            // Lit only when the focus is on *this* output. The primary offers
            // the whole numbered range, so without this the workspace focused
            // on the second monitor was highlighted on both bars — the same
            // pill lit twice, which is the thing this was meant to stop.
            const here = w && (w.output === undefined || topBar.outputName === ""
                               || w.output === topBar.outputName);
            out.push({ name: key, focused: !!(w && w.focused && here), exists: !!w });
            delete mine[key];
        }
        // Named or out-of-range workspaces still have to be reachable.
        for (const key in mine)
            out.push({ name: key, focused: !!mine[key].focused, exists: true });
        return out;
    }

    // The Game Mode page has offered "Hide Waybar — automatically hide top
    // status bar during gaming sessions" since it was written. There is no
    // waybar in this project (the native bar below replaced it, and the
    // .config/waybar the README's tree claims does not exist), and nothing
    // read the setting, so the toggle stored a value and the bar never moved.
    // Hiding the PanelWindow also releases its exclusive zone, so tiled windows
    // reclaim the strip.
    visible: !(Settings.gameModeEnabled && Settings.gameModeHideBar)
    
    signal requestCommand(string cmd, bool notify)

    property bool menuOpen: false

    // Wayland Layer-Shell configuration: Top layer so fullscreen covers it,
    // dynamically elevated to Overlay when application menu/launchpad is open.
    WlrLayershell.namespace: "b1air-topbar"
    WlrLayershell.layer: WlrLayer.Top
    onMenuOpenChanged: {
        topBar.WlrLayershell.layer = menuOpen ? WlrLayer.Overlay : WlrLayer.Top;
    }
    // The bar reserves its own height and no more.
    //
    // This briefly reserved height + Design.space.sm, to guarantee a gap under
    // the bar. It was the wrong fix for a problem that was not there: the
    // windows in the screenshots that prompted it were flush against the bar
    // because the session had `smart_gaps on` left over from a settings test,
    // not because the bar reserved too little. sway's own `gaps outer` — 20 in
    // conf.d/look-and-feel.conf — is what puts space under the bar, and it
    // already did.
    //
    // The extra reservation also looked wrong on its own terms. This bar draws
    // floating islands on a transparent surface: the islands end at 25 of a
    // 27-pixel surface, so reserving beyond the surface exposes a band of bare
    // desktop under them and the bar reads as cut off rather than as floating.
    WlrLayershell.exclusiveZone: Design.s(Design.size.barZone)
    
    // Settings → Native Top Bar has a Top/Bottom control; nothing read it, so
    // the bar was anchored to the top whatever it said.
    anchors.top: Settings.barPosition !== "bottom"
    anchors.bottom: Settings.barPosition === "bottom"
    anchors.left: true
    anchors.right: true
    implicitHeight: Design.s(Design.size.bar)

    // Transparent: the bar is its islands, floating over the desktop.
    //
    // A translucent strip was tried here to stop the bar reading as a black
    // band on a plain background. It was the wrong half of that problem — the
    // band was the outer gap opening a strip of bare desktop between the bar
    // and the first window, and `gaps top 0` in conf.d/look-and-feel.conf
    // closes it. With the window starting immediately below, the islands have
    // nothing to be mistaken for.
    color: "transparent"

    // The bar had its own colour names (colBlue, colFgDim…), aliases of the
    // Design roles kept from a hand-rolled palette. It uses the roles now.
    readonly property string fontMain: Design.font.sans

    function safePinnedCommand(cmd) {
        const value = (cmd || "").trim();
        const forbidden = [";", "&", "|", "`", "$", "<", ">", "\\", "\n", "\r", "(", ")", "{", "}", "[", "]", "*", "?", "!", "~"];
        if (!value || value.length > 512 || forbidden.some(c => value.includes(c))) return false;
        Sway.command("exec " + value);
        return true;
    }

    // ── State Trackers ──────────────────────────────────────────────────────
    property string clockTime: "00:00"
    property string clockDate: ""
    property string cpuUsage: "0%"
    property string memUsage: "0.0G"
    property string kbdLayout: "US"
    property var workspacesList: [ { num: 1, name: "1", focused: true } ]
    property var runningApps: []

    function refreshRunningApps() {
        Sway.query("tree", tree => {
            if (!tree)
                return;
            let apps = [];
            topBar.collectSwayNodes([tree], apps, "");
            topBar.runningApps = apps;
        });
    }

    function refreshWorkspaces() {
        Sway.query("workspaces", ws => {
            if (Array.isArray(ws) && ws.length > 0)
                topBar.workspacesList = ws;
        });
    }

    Component.onCompleted: {
        refreshRunningApps();
        refreshWorkspaces();
        // Once, at startup. After this the layout is only re-read when sway
        // reports an input change.
        refreshLayout();
    }

    function collectSwayNodes(nodes, result, workspaceName) {
        for (let node of (nodes || [])) {
            let currentWorkspace = node.type === "workspace" ? (node.name || workspaceName) : workspaceName;
            let appId = node.app_id || (node.window_properties ? node.window_properties.class : "") || "";
            let title = node.name || appId;
            let children = (node.nodes || []).concat(node.floating_nodes || []);
            if (appId && node.pid && appId !== "b1air-topbar" && appId !== "waybar" && node.type !== "workspace") {
                result.push({ id: node.id, appId: appId, title: title, workspace: currentWorkspace, focused: !!node.focused });
            } else if (children.length > 0) {
                collectSwayNodes(children, result, currentWorkspace);
            }
        }
    }

    function appIcon(appId) {
        // The desktop entry first: it knows the icon, and it resolves through
        // whatever theme the desktop is set to, so a window in the bar looks
        // like the same window in the switcher and the launcher. The chain
        // below pinned seven of our own app-ids to AdwaitaLegacy PNGs and gave
        // every other application on the machine the same grey executable box.
        const fromEntry = Apps.iconFor(appId);
        if (fromEntry !== "")
            return topBar.iconSource(fromEntry);

        const id = (appId || "").toLowerCase();
        // Our own apps by their own icons, when no entry answered for them.
        const ours = id.match(/b1air-(term|files|monitor|settings|notes|text|git|view)/);
        if (ours) return topBar.iconSource("b1air-" + ours[1]);
        if (id.includes("firefox") || id.includes("browser")) return "file:///usr/share/icons/AdwaitaLegacy/48x48/legacy/web-browser.png";
        // Never pass an unknown app-id to image://icon: that produces the
        // red/purple missing-icon tile. Use a real system fallback instead.
        return "file:///usr/share/icons/AdwaitaLegacy/48x48/mimetypes/application-x-executable.png";
    }

    function iconSource(icon) {
        // A string or a url (an entry's icon may come back resolved already):
        // a url has no trim(), and our own apps' icons failed on it.
        const value = String(icon || "application-x-executable").trim();
        if (value.startsWith("/") || value.startsWith("file://")) return Paths.fileUrl(value);
        // The suite's own icons, by file, from the copy `make install` puts
        // beside this QML. They used to be read from ~/.local/share/icons,
        // where a system-wide install never put them.
        if (value.startsWith("b1air-")) return Qt.resolvedUrl("icons/apps/" + value + ".svg");
        const legacy = {
            "utilities-terminal": "utilities-terminal.png",
            "system-file-manager": "system-file-manager.png",
            "utilities-system-monitor": "utilities-system-monitor.png",
            "preferences-system": "preferences-system.png",
            "web-browser": "web-browser.png",
            "network-wired": "network-wired.png",
            "application-x-executable": "../mimetypes/application-x-executable.png"
        };
        if (legacy[value]) return "file:///usr/share/icons/AdwaitaLegacy/48x48/legacy/" + legacy[value];
        return "image://icon/" + value;
    }

    // Clock Timer (ticks every 1s)
    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            let now = new Date();
            // Settings → Native Top Bar offers a 24-hour toggle. Nothing read
            // it: the bar formatted "hh:mm" unconditionally, so the switch
            // stored a value and the clock never changed.
            topBar.clockTime = I18n.locale.toString(now, Settings.barClock24h ? "hh:mm" : "h:mm AP");
            topBar.clockDate = I18n.date(now, "dddd, d MMMM yyyy");
        }
    }

    // ── CPU, memory and keyboard layout ──────────────────────────────────────
    //
    // This was one `bash -c` loop running for the life of the session, and
    // every two seconds it did three things: read /proc/stat, run `cut` over
    // /proc/loadavg, and launch `b1air-daemon layout`. That last one is a
    // 2.3 MB binary linking SQLite, systemd and OpenSSL, started thirty times
    // a minute — forty-three thousand times a day — to print the two letters
    // "US", which change about as often as the user changes keyboard.
    //
    // The two files are read here directly, so the CPU and load figures cost
    // one file read each and no process at all. The layout comes from sway's
    // own input events, which is the only moment it can possibly have changed.
    //
    // This is the same trade Services/Audio and Services/Power already made:
    // "60 process spawns a minute became none", "40 became 4".

    property real _prevIdle: 0
    property real _prevTotal: 0

    FileView {
        id: procStat
        path: "/proc/stat"
        printErrors: false
        onLoaded: {
            // The first line is the aggregate: cpu user nice system idle
            // iowait irq softirq steal …
            const first = text().split("\n")[0];
            const f = first.trim().split(/\s+/);
            if (f.length < 9 || f[0] !== "cpu")
                return;

            const n = f.slice(1, 9).map(Number);
            const idleAll = n[3] + n[4];
            const total = n.reduce((a, b) => a + b, 0);

            const dIdle = idleAll - topBar._prevIdle;
            const dTotal = total - topBar._prevTotal;
            // The first sample has nothing to subtract from, and a counter
            // that has not moved would divide by zero.
            if (topBar._prevTotal > 0 && dTotal > 0)
                topBar.cpuUsage = Math.round(100 * (dTotal - dIdle) / dTotal) + "%";

            topBar._prevIdle = idleAll;
            topBar._prevTotal = total;
        }
    }

    // Memory in use across the whole system. This pill had a memory-chip icon
    // over the one-minute load average — "0.64" beside a RAM symbol, which
    // reads as nothing — so the bar never showed memory at all.
    //
    // Used is MemTotal − MemAvailable, the figure `free` puts in its "used"
    // column less the reclaimable cache: MemFree alone counts the page cache
    // as used, and a machine that has been up a while would sit near 100%.
    FileView {
        id: procMem
        path: "/proc/meminfo"
        printErrors: false
        onLoaded: {
            let total = 0, avail = -1;
            for (const line of text().split("\n")) {
                if (line.startsWith("MemTotal:")) total = parseInt(line.split(/\s+/)[1]);
                else if (line.startsWith("MemAvailable:")) avail = parseInt(line.split(/\s+/)[1]);
                if (total > 0 && avail >= 0) break;
            }
            // In gigabytes, the whole machine's: every process, not the
            // shell's own share. /proc/meminfo counts in KiB.
            if (total > 0 && avail >= 0)
                topBar.memUsage = ((total - avail) / 1048576).toFixed(1) + "G";
        }
    }

    // Only while the bar shows the figures (the stats tile's own condition):
    // /proc was read every two seconds with the tile turned off.
    Timer {
        interval: 2000
        repeat: true
        running: Settings.barShowStats && !topBar.reduced
        triggeredOnStart: true
        onTriggered: {
            procStat.reload();
            procMem.reload();
        }
    }

    // Read once at startup and then only when sway says the layout changed.
    function applyLayout(inputs) {
        if (!Array.isArray(inputs))
            return;
        for (const dev of inputs) {
            const name = dev.xkb_active_layout_name;
            if (!name)
                continue;
            // The layout's own code, by position: sway's layouts
            // are the ones Settings -> Keyboard wrote, in order.
            // Cutting the name down gave "UK" for Ukrainian, "GE"
            // for German and "PO" for Polish, though the comment
            // here promised "UA".
            const codes = Settings.swayLayouts;
            const idx = Number(dev.xkb_active_layout_index);
            if (idx >= 0 && idx < codes.length && codes.length === (dev.xkb_layout_names || []).length) {
                topBar.kbdLayout = codes[idx].slice(0, 3).toUpperCase();
                return;
            }
            // "English (US)" -> "US".
            const paren = name.match(/\(([^)]+)\)/);
            topBar.kbdLayout = (paren ? paren[1] : name).slice(0, 2).toUpperCase();
            return;
        }
    }

    function refreshLayout() {
        Sway.query("inputs", inputs => topBar.applyLayout(inputs));
    }

    Timer {
        id: layoutCoalesce
        interval: 200
        onTriggered: topBar.refreshLayout()
    }


    // Sway pushes window/workspace events, so there is nothing to poll for.
    // Bursts are coalesced: dragging a window emits a stream of events, and
    // one refresh each would ask for the tree dozens of times a second.
    Connections {
        target: Sway
        function onWindowEvent(e) { swayCoalesce.restart(); }
        function onWorkspaceEvent(e) { swayCoalesce.restart(); }
        function onInputEvent(e) {
            if (e && e.change === "xkb_layout")
                layoutCoalesce.restart();
        }
        // Which order sway has the layouts in depends on it (Sway.keysFromUs).
        function onVersionChanged() { layoutCoalesce.restart(); }
        // A restarted sway is a new session's worth of state.
        function onReconnected() {
            topBar.refreshRunningApps();
            topBar.refreshWorkspaces();
            topBar.refreshLayout();
        }
    }

    Timer {
        id: swayCoalesce
        interval: 120
        onTriggered: {
            topBar.refreshRunningApps();
            topBar.refreshWorkspaces();
        }
    }

    // ── Bar Content Layout ──────────────────────────────────────────────────
    Item {
        anchors.fill: parent
        anchors.leftMargin: Design.s(Design.space.sm)
        anchors.rightMargin: Design.s(Design.space.sm)
        anchors.topMargin: Design.s(Design.space.xs)
        anchors.bottomMargin: Design.s(Design.space.xs)

        // ══════════════════════════════════════════════════════════════════════
        // LEFT ISLANDS: APPS, Dynamic Pinned Apps, Workspaces
        // ══════════════════════════════════════════════════════════════════════
        Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Design.s(Design.space.xs)

            // 1. APPS Island (Launchpad on Left Click, Spotlight on Right Click)
            Surface {
                kind: "glass"
                id: appMenuBtn
                visible: Settings.barShowApps
                width: appRow.implicitWidth + Design.s(Design.space.md * 2)
                height: Design.s(Design.size.island)
                radius: Design.s(Design.radius.ctl)
                // The same glass and rim as the islands beside it. Hovered it
                // turned a lighter pane with a bright 22% rim — a colour none
                // of the rest of the bar has, and the pointer rests in this
                // corner often (the hot corner), so it looked so most of the
                // time. Now a faint wash (HoverWash), as every island has.
                HoverWash { shown: appMenuArea.containsMouse }

                Row {
                    id: appRow
                    anchors.centerIn: parent
                    spacing: Design.s(Design.space.xs)
                    Label {
                        text: "󰍜"
                        isMono: true
                        color: Design.text
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Label {
                        // Sentence case and the medium cut, as every other
                        // label on the bar: it was the one word in capitals
                        // and bold, the loudest thing on the left.
                        text: I18n.tr("Apps")
                        family: topBar.fontMain
                        size: Design.s(Design.font.body)
                        weight: Design.weight.medium
                        color: Design.text
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                PointerArea {
                    id: appMenuArea
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    cursorShape: Qt.PointingHandCursor
                    onClicked: (mouse) => {
                        if (mouse.button === Qt.RightButton) {
                            topBar.requestCommand("toggle:spotlight:", true);
                        } else {
                            topBar.requestCommand("toggle:launchpad:", true);
                        }
                    }
                }
            }

            // 2. User-Configured Pinned Apps Island
            Surface {
                kind: "glass"
                height: Design.s(Design.size.island)
                width: pinnedRow.implicitWidth + Design.s(Design.space.sm * 2)
                radius: Design.s(Design.radius.ctl)
                visible: Settings.barShowPinned && PinnedApps.pinnedList.length > 0

                Row {
                    id: pinnedRow
                    anchors.centerIn: parent
                    spacing: Design.s(Design.space.xs)

                    Repeater {
                        model: PinnedApps.pinnedList
                        delegate: Box {
                            id: pinPill
                            width: Design.s(Design.size.xs)
                            height: Design.s(Design.size.xs)
                            radius: Design.s(Design.radius.sm)
                            color: pinArea.containsMouse ? Design.stateHover : "transparent"

                            // The app's own icon, from its desktop entry, the
                            // way running windows already get theirs. Pins
                            // stored a generic name — Firefox was the
                            // AdwaitaLegacy "web-browser" globe — so the pinned
                            // row never looked like the apps it launches.
                            // The stored icon is kept for pins no entry answers.
                            AppIcon {
                                anchors.centerIn: parent
                                width: Design.s(Design.size.micro)
                                height: Design.s(Design.size.micro)
                                source: Apps.iconFor(modelData.id) !== ""
                                    ? topBar.appIcon(modelData.id)
                                    : topBar.iconSource(modelData.icon)
                                mipmap: true
                            }

                            PointerArea {
                                id: pinArea
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                cursorShape: Qt.PointingHandCursor
                                onClicked: (mouse) => {
                                    if (mouse.button === Qt.RightButton) {
                                        // Unpin immediately on right click!
                                        PinnedApps.togglePin(modelData);
                                    } else {
                                        let cmd = modelData.cmd || "";
                                        if (cmd.startsWith("toggle:")) {
                                            topBar.requestCommand(cmd, true);
                                        } else if (cmd.startsWith("open:")) {
                                            topBar.requestCommand(cmd, true);
                                        } else {
                                            topBar.safePinnedCommand(cmd);
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Add Pinned App '+' Button
                    Box {
                        width: Design.s(Design.size.mini)
                        height: Design.s(Design.size.mini)
                        radius: Design.s(Design.radius.sm)
                        color: addPinArea.containsMouse ? Design.stateHover : "transparent"
                        anchors.verticalCenter: parent.verticalCenter

                        Label {
                            anchors.centerIn: parent
                            text: "󰐕"
                            isMono: true
                            role: "caption"
                            color: addPinArea.containsMouse ? Design.text : Design.textDim
                        }

                        PointerArea {
                            id: addPinArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: topBar.requestCommand("toggle:launchpad:", true)
                        }
                    }
                }
            }

            // 3. Workspaces Island
            Surface {
                kind: "glass"
                id: workspacesIsland
                visible: Settings.barShowWorkspaces
                height: Design.s(Design.size.island)
                width: workspacesRow.implicitWidth + Design.s(Design.space.md)
                radius: Design.s(Design.radius.ctl)
                Row {
                    id: workspacesRow
                    anchors.centerIn: parent
                    spacing: Design.s(Design.space.xs)

                    Repeater {
                        model: topBar.workspaceSlots
                        delegate: Box {
                            id: wsPill
                            required property var modelData

                            width: wsText.implicitWidth + Design.s(Design.space.sm * 2)
                            height: Design.s(Design.size.xs)
                            radius: Design.s(Design.radius.sm)
                            color: wsPill.modelData.focused ? Design.accent
                                 : (wsMouseArea.containsMouse ? Design.stateSelected : Design.glassTile)
                            border.color: wsPill.modelData.focused ? "transparent" : Design.line
                            border.width: Design.border
                            // An empty slot is a place you can go, not a place
                            // you are; it says so by being fainter rather than
                            // by being missing.
                            opacity: wsPill.modelData.exists || wsPill.modelData.focused ? 1.0 : 0.45

                            Label {
                                id: wsText
                                anchors.centerIn: parent
                                text: wsPill.modelData.name
                                family: topBar.fontMain
                                size: Design.s(Design.font.caption)
                                weight: Design.weight.semibold
                                color: wsPill.modelData.focused ? Design.accentText
                                     : (wsMouseArea.containsMouse ? Design.text : Design.textDim)
                            }

                            PointerArea {
                                id: wsMouseArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    const workspace = String(wsPill.modelData.name);
                                    Sway.command("workspace " + Sway.quote(workspace));
                                }
                            }
                        }
                    }
                }

                PointerArea {
                    anchors.fill: parent
                    z: -1
                    onWheel: (wheel) => {
                        if (wheel.angleDelta.y > 0) {
                            Sway.command("workspace prev");
                        } else if (wheel.angleDelta.y < 0) {
                            Sway.command("workspace next");
                        }
                    }
                }
            }

            // Old Waybar placed the taskbar after workspaces on the left.
            // Keep that topology, but render compact native icons.
            Row {
                id: runningAppsRow
                anchors.verticalCenter: parent.verticalCenter
                spacing: Design.s(Design.space.xxs)
                visible: topBar.runningApps.length > 0

                Repeater {
                    model: topBar.runningApps
                    delegate: Box {
                        width: Design.s(Design.size.sm)
                        height: Design.s(Design.size.sm)
                        radius: Design.s(Design.radius.ctl)
                        color: modelData.focused ? Design.stateSelected : Design.glassBg
                        border.color: modelData.focused ? Design.accent : Design.glassBorder
                        border.width: Design.border
                        AppIcon {
                            anchors.centerIn: parent
                            width: Design.s(Design.size.micro)
                            height: Design.s(Design.size.micro)
                            source: topBar.iconSource(topBar.appIcon(modelData.appId))
                            mipmap: true
                        }

                        PointerArea {
                            id: runningArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Sway.command("[con_id=" + Number(modelData.id) + "] focus")
                        }

                        // No ToolTip, for the reason given at the Control
                        // Center button: in a bar-high window it lands on top
                        // of the button and takes the click meant to focus the
                        // window.
                    }
                }
            }
        }

        // ══════════════════════════════════════════════════════════════════════
        // CENTER ISLAND: Floating Clock Pill (Calendar, Focus Time, Updater)
        // ══════════════════════════════════════════════════════════════════════
        Surface {
            kind: "glass"
            id: clockPill
            anchors.centerIn: parent
            width: clockText.implicitWidth + Design.s(Design.space.xl + Design.space.md)
            height: Design.s(Design.size.sm)
            radius: Design.s(Design.radius.pill)
            // Glass like the islands beside it: a solid accent pill was the
            // loudest thing on the screen, for the one thing glanced at most.
            HoverWash { shown: clockArea.containsMouse }
            Behavior on color { ColorAnimation { duration: Design.duration.fast } }

            Label {
                id: clockText
                anchors.centerIn: parent
                text: topBar.clockTime
                font.features: Design.tabular
                family: topBar.fontMain
                size: Design.s(Design.font.body)
                weight: Design.weight.semibold
                color: Design.text
            }

            PointerArea {
                id: clockArea
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onClicked: (mouse) => {
                    if (mouse.button === Qt.MiddleButton) {
                        topBar.requestCommand("toggle:focustime:", true);
                    } else if (mouse.button === Qt.RightButton) {
                        topBar.requestCommand("toggle:updater:", true);
                    } else {
                        topBar.requestCommand("toggle:calendar:", true);
                    }
                }
            }
        }

        // ══════════════════════════════════════════════════════════════════════
        // FOCUS TIMER PILL — only while a focus interval is running
        // ══════════════════════════════════════════════════════════════════════
        //
        // A timer you cannot see is not much of a timer, and its own window is
        // a full screen-time dashboard. Left of the clock, present only when
        // there is something to show; click to pause or resume, middle-click
        // for the dashboard.
        Box {
            id: focusPill
            visible: Focus.active
            anchors.right: clockPill.left
            anchors.rightMargin: Design.s(Design.space.xs)
            anchors.verticalCenter: parent.verticalCenter
            width: focusRow.implicitWidth + Design.s(Design.space.md * 2)
            height: Design.s(Design.size.sm)
            radius: Design.s(Design.radius.pill)
            readonly property color tone: Focus.onBreak ? Design.ok : Design.accent
            color: focusArea.containsMouse ? Qt.alpha(tone, 0.32) : Qt.alpha(tone, 0.18)
            border.width: Design.border
            border.color: Qt.alpha(tone, Focus.running ? 0.55 : 0.28)

            Behavior on color { ColorAnimation { duration: Design.duration.fast } }

            Row {
                id: focusRow
                anchors.centerIn: parent
                spacing: Design.s(Design.space.xs)

                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    // Paused shows the play glyph: it is what the click does.
                    text: Focus.running ? "\u{f0520}" : "\u{f040a}"
                    role: "footnote"
                    color: focusPill.tone
                }

                Label {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Focus.remainingText
                    family: topBar.fontMain
                    size: Design.s(Design.font.footnote)
                    weight: Design.weight.semibold
                    color: focusPill.tone
                    opacity: Focus.running ? 1.0 : 0.65
                }
            }

            PointerArea {
                id: focusArea
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                cursorShape: Qt.PointingHandCursor
                onClicked: (mouse) => {
                    if (mouse.button === Qt.MiddleButton)
                        topBar.requestCommand("toggle:focustime:", true);
                    else
                        Focus.toggle();
                }
            }
        }

        // ══════════════════════════════════════════════════════════════════════
        // RIGHT ISLANDS: Stats, System Status
        // ══════════════════════════════════════════════════════════════════════
        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Design.s(Design.space.xs)

            // 0. Media title and weather.
            //
            // Settings → Native Top Bar has offered "Media Player Title —
            // display currently playing track name and artist" and "Weather
            // Status — show temperature and weather condition badge" since it
            // was written, and the bar had neither module: the two switches
            // stored a value nothing read. Both services already exist and are
            // used by the Control Center, so this is wiring, not new plumbing.

            Surface {
                kind: "glass"
                height: Design.s(Design.size.island)
                width: mediaRow.implicitWidth + Design.s(Design.space.md * 2)
                radius: Design.s(Design.radius.ctl)
                HoverWash { shown: mediaArea.containsMouse }
                anchors.verticalCenter: parent.verticalCenter

                // Only when asked for, and only when there is something to say.
                visible: Settings.barShowMedia && Media.hasPlayer && !topBar.reduced
                         && String(Media.track.title || "") !== ""

                Row {
                    id: mediaRow
                    anchors.centerIn: parent
                    spacing: Design.s(Design.space.xs)

                    Icon {
                        text: Media.playing ? "\u{f040a}" : "\u{f03e4}"
                        role: "footnote"
                        color: Design.textDim
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Label {
                        // Elided rather than allowed to push the clock off
                        // centre: a track title is arbitrarily long.
                        width: Math.min(implicitWidth, Design.s(Design.width.control))
                        elide: Text.ElideRight
                        text: (Media.track.artist ? Media.track.artist + " — " : "")
                              + (Media.track.title || "")
                        family: topBar.fontMain
                        size: Design.s(Design.font.caption)
                        color: Design.textDim
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                PointerArea {
                    id: mediaArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: topBar.requestCommand("toggle:music:", true)
                }
            }

            Surface {
                kind: "glass"
                height: Design.s(Design.size.island)
                width: weatherRow.implicitWidth + Design.s(Design.space.md * 2)
                radius: Design.s(Design.radius.ctl)
                HoverWash { shown: weatherArea.containsMouse }
                anchors.verticalCenter: parent.verticalCenter

                visible: Settings.barShowWeather && Weather.loaded && !topBar.reduced

                Row {
                    id: weatherRow
                    anchors.centerIn: parent
                    spacing: Design.s(Design.space.xs)

                    Icon {
                        text: Weather.icon
                        role: "footnote"
                        color: Design.textDim
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Label {
                        text: Weather.temp
                        family: topBar.fontMain
                        size: Design.s(Design.font.caption)
                        weight: Design.weight.semibold
                        color: Design.textDim
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                PointerArea {
                    id: weatherArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: topBar.requestCommand("toggle:calendar:", true)
                }
            }

            // 0b. System tray.
            //
            // The third switch on that page with nothing behind it. Quickshell
            // ships the StatusNotifierItem host; the bar simply never used it,
            // so background applets — Telegram, Steam, the ones the setting
            // names — had nowhere to appear on this desktop at all.
            Surface {
                kind: "glass"
                height: Design.s(Design.size.island)
                width: trayRow.implicitWidth + Design.s(Design.space.md * 2)
                radius: Design.s(Design.radius.ctl)
                anchors.verticalCenter: parent.verticalCenter

                // No applets means no empty pill sitting in the bar.
                visible: Settings.barShowTray && SystemTray.items.values.length > 0 && !topBar.reduced

                Row {
                    id: trayRow
                    anchors.centerIn: parent
                    spacing: Design.s(Design.space.sm)

                    Repeater {
                        model: SystemTray.items

                        delegate: Item {
                            id: trayItem
                            required property var modelData
                            width: Design.s(Design.size.micro)
                            height: Design.s(Design.size.micro)
                            anchors.verticalCenter: parent.verticalCenter

                            // An applet that names an icon the theme does not
                            // have got Quickshell's magenta-and-black
                            // "missing" square, the loudest thing on the bar.
                            // Asked first, and a plain glyph instead.
                            readonly property string iconName: {
                                const src = String(modelData.icon || "");
                                if (!src.startsWith("image://icon/")) return "";
                                return decodeURIComponent(src.slice(13).split("?")[0]);
                            }
                            readonly property bool missing: String(modelData.icon || "") === ""
                                || (iconName !== "" && !iconName.startsWith("/") && Quickshell.iconPath(iconName, true) === "")

                            AppIcon {
                                anchors.fill: parent
                                visible: !trayItem.missing
                                source: trayItem.missing ? "" : trayItem.modelData.icon
                                asynchronous: true
                            }
                            Label {
                                anchors.centerIn: parent
                                visible: trayItem.missing
                                text: "\u{f003b}"   // apps
                                family: topBar.fontMain
                                size: Design.s(Design.font.glyphSm)
                                color: Design.textDim
                            }

                            PointerArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                                cursorShape: Qt.PointingHandCursor
                                // The three gestures a tray icon is expected to
                                // answer, rather than only the first one.
                                onClicked: mouse => {
                                    const item = parent.modelData;
                                    if (mouse.button === Qt.MiddleButton)
                                        item.secondaryActivate();
                                    else if (mouse.button === Qt.RightButton)
                                        item.display(topBar, 0, Design.s(Design.size.island + Design.space.xs));
                                    else
                                        item.activate();
                                }
                            }
                        }
                    }
                }
            }

            // 1. Stats Island (CPU + memory)
            Surface {
                kind: "glass"
                height: Design.s(Design.size.island)
                width: statsRow.implicitWidth + Design.s(Design.space.md * 2)
                visible: Settings.barShowStats && !topBar.reduced
                radius: Design.s(Design.radius.ctl)
                HoverWash { shown: statsArea.containsMouse }
                Row {
                    id: statsRow
                    anchors.centerIn: parent
                    spacing: Design.s(Design.space.sm)

                    Row {
                        spacing: Design.s(Design.space.xs)
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            text: ""
                            family: topBar.fontMain
                            size: Design.s(Design.font.footnote)
                            color: Design.textDim
                        }
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            text: topBar.cpuUsage
                            font.features: Design.tabular
                            family: topBar.fontMain
                            size: Design.s(Design.font.caption)
                            weight: Design.weight.semibold
                            color: Design.text
                        }
                    }

                    Row {
                        spacing: Design.s(Design.space.xs)
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "󰍛"
                            family: topBar.fontMain
                            size: Design.s(Design.font.footnote)
                            color: Design.textDim
                        }
                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            text: topBar.memUsage
                            font.features: Design.tabular
                            family: topBar.fontMain
                            size: Design.s(Design.font.caption)
                            weight: Design.weight.semibold
                            color: Design.text
                        }
                    }
                }

                PointerArea {
                    id: statsArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Quickshell.execDetached(["b1air-monitor"])
                }
            }

            // 2. System Status Island (Layout, Volume, Battery, Bell, Power)
            Surface {
                kind: "glass"
                height: Design.s(Design.size.island)
                width: systemRow.implicitWidth + Design.s(Design.space.md * 2)
                radius: Design.s(Design.radius.ctl)
                Row {
                    id: systemRow
                    anchors.centerIn: parent
                    spacing: Design.s(Design.space.sm)

                    // Privacy dots. Present only while something is using the
                    // device, because an indicator that is always there is one
                    // nobody looks at.
                    // No ToolTips on them, for the reason at the Control Center
                    // button below: a ToolTip in a bar-high window lands on top
                    // of the bar and takes the clicks meant for its neighbours.
                    Box {
                        visible: topBar.micInUse
                        anchors.verticalCenter: parent.verticalCenter
                        width: Design.s(Design.size.micro); height: Design.s(Design.size.micro)
                        radius: width / 2
                        color: Design.tint(Design.danger, 0.22)
                        Icon {
                            anchors.centerIn: parent
                            text: "\u{f036c}"
                            role: "caption"
                            color: Design.danger
                        }
                    }

                    Box {
                        visible: topBar.cameraInUse
                        anchors.verticalCenter: parent.verticalCenter
                        width: Design.s(Design.size.micro); height: Design.s(Design.size.micro)
                        radius: width / 2
                        color: Design.tint(Design.warn, 0.22)
                        Icon {
                            anchors.centerIn: parent
                            text: "\u{f0567}"
                            role: "caption"
                            color: Design.warn
                        }
                    }

                    // Remote desktop: shown while our VNC server listens, and
                    // whenever someone is connected — by VNC or RustDesk (whose
                    // service listens always, so only a session shows) — red
                    // then. A click ends it: the VNC server stops, which drops
                    // every viewer, and a RustDesk session is let go.
                    Box {
                        visible: Remote.running || Remote.rustdeskSession
                        readonly property bool watched: Remote.viewers > 0
                        readonly property color tone: watched ? Design.danger : Design.accent
                        anchors.verticalCenter: parent.verticalCenter
                        width: Design.s(Design.size.micro); height: Design.s(Design.size.micro)
                        radius: width / 2
                        color: Design.tint(tone, remoteDotHover.containsMouse ? 0.4 : 0.22)
                        Icon {
                            anchors.centerIn: parent
                            text: "\u{f0379}"
                            role: "caption"
                            color: parent.tone
                        }
                        PointerArea {
                            id: remoteDotHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (Remote.rustdeskSession) Remote.stopRustdesk();
                                if (Remote.running) Remote.stop();
                            }
                        }
                    }

                    // Caps Lock, shown only while it is on — which is the only
                    // time anyone wants to know.
                    Box {
                        visible: topBar.capsOn
                        anchors.verticalCenter: parent.verticalCenter
                        width: capsText.implicitWidth + Design.s(Design.space.md)
                        height: Design.s(Design.size.mini)
                        radius: Design.s(Design.radius.sm)
                        color: Design.tint(Design.warn, 0.20)
                        Label {
                            id: capsText
                            anchors.centerIn: parent
                            text: I18n.tr("CAPS")
                            family: topBar.fontMain
                            size: Design.s(Design.font.caption)
                            weight: Design.weight.semibold
                            color: Design.warn
                        }
                    }

                    // Keyboard Layout Pill
                    Box {
                        anchors.verticalCenter: parent.verticalCenter
                        width: kbdText.implicitWidth + Design.s(Design.space.md)
                        height: Design.s(Design.size.mini)
                        radius: Design.s(Design.radius.sm)
                        color: kbdArea.containsMouse ? Design.stateHover : "transparent"
                        Label {
                            id: kbdText
                            anchors.centerIn: parent
                            text: topBar.kbdLayout
                            family: topBar.fontMain
                            size: Design.s(Design.font.caption)
                            weight: Design.weight.semibold
                            color: Design.text
                        }
                        PointerArea {
                            id: kbdArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                Sway.command("input type:keyboard xkb_switch_layout next");
                                Quickshell.execDetached(["b1air-daemon", "layout"]);
                            }
                        }
                    }

                    // Network: the cable when it is plugged in, otherwise the
                    // Wi-Fi signal and the network's name. The bar had no sign
                    // of the network at all. A click opens the Wi-Fi list.
                    Item {
                        id: netPill
                        visible: Network.hasWifi || Network.wiredUp
                        width: netRow.implicitWidth
                        height: Design.s(Design.size.mini)
                        anchors.verticalCenter: parent.verticalCenter
                        readonly property bool wifiOn: Network.wifi.power === "on"
                        Row {
                            id: netRow
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Design.s(Design.space.xs)
                            Label {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Network.wiredUp ? "\u{f0200}"
                                    : Network.activeWifi ? Network._wifiIcon(Network.activeWifiSignal)
                                    : netPill.wifiOn ? "\u{f092e}" : "\u{f05aa}"
                                family: topBar.fontMain
                                size: Design.s(Design.font.body)
                                color: (Network.wiredUp || Network.activeWifi) ? Design.textDim : Design.warn
                            }
                            Label {
                                visible: !Network.wiredUp && Network.activeWifi !== null
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.min(implicitWidth, Design.s(Design.width.segmentSm))
                                elide: Text.ElideRight
                                text: Network.activeWifi ? Network.activeWifi.name : ""
                                family: topBar.fontMain
                                size: Design.s(Design.font.caption)
                                weight: Design.weight.semibold
                                color: Design.text
                            }
                        }
                        PointerArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: topBar.requestCommand("toggle:wifimenu:", true)
                        }
                    }

                    // Volume Pill
                    Item {
                        width: volRow.implicitWidth
                        height: Design.s(Design.size.mini)
                        anchors.verticalCenter: parent.verticalCenter
                        Row {
                            id: volRow
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Design.s(Design.space.xs)
                            Label {
                                anchors.verticalCenter: parent.verticalCenter
                                text: (Audio.defaultSink && Audio.defaultSink.audio && Audio.defaultSink.audio.muted) ? "󰖁" : "󰕾"
                                family: topBar.fontMain
                                size: Design.s(Design.font.body)
                                color: (Audio.defaultSink && Audio.defaultSink.audio && Audio.defaultSink.audio.muted) ? Design.textFaint : Design.textDim
                            }
                            Label {
                                anchors.verticalCenter: parent.verticalCenter
                                text: (Audio.defaultSink && Audio.defaultSink.audio) ? Math.round(Audio.defaultSink.audio.volume * 100) + "%" : "65%"
                                family: topBar.fontMain
                                size: Design.s(Design.font.caption)
                                weight: Design.weight.semibold
                                color: Design.text
                            }
                        }
                        PointerArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            // Straight to the sound page. It opened the
                            // Control Center's front page, which was the only
                            // way into the Control Center from the bar at all;
                            // that has its own button now, beside the bell.
                            onClicked: topBar.requestCommand("toggle:soundmenu:", true)
                            onWheel: (wheel) => {
                                if (wheel.angleDelta.y > 0) {
                                    Daemon.volumeUp(5);
                                } else if (wheel.angleDelta.y < 0) {
                                    Daemon.volumeDown(5);
                                }
                            }
                        }
                    }

                    // Battery Pill (if present)
                    Item {
                        visible: Power.hasBattery
                        width: batRow.implicitWidth
                        height: Design.s(Design.size.mini)
                        anchors.verticalCenter: parent.verticalCenter
                        Row {
                            id: batRow
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Design.s(Design.space.xs)
                            Label {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Power.charging ? "󰂄" : "󰁹"
                                family: topBar.fontMain
                                size: Design.s(Design.font.body)
                                color: Power.charging ? Design.ok : Design.textDim
                            }
                            Label {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Power.capacity + "%"
                                family: topBar.fontMain
                                size: Design.s(Design.font.caption)
                                weight: Design.weight.semibold
                                color: Design.text
                            }
                        }
                        PointerArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: topBar.requestCommand("toggle:batterymenu:", true)
                        }
                    }

                    // Control Center. It had no button: the only way in from
                    // the bar was clicking the volume percentage, which is not
                    // somewhere anyone looks for a panel of switches.
                    Box {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Design.s(Design.size.mini); height: Design.s(Design.size.mini); radius: Design.s(Design.radius.sm)
                        color: ccArea.containsMouse ? Design.stateHover : "transparent"
                        Label {
                            anchors.centerIn: parent
                            text: "\u{f062e}"   // sliders — the same glyph as the panel's own header
                            family: topBar.fontMain
                            size: Design.s(Design.font.body)
                            color: ccArea.containsMouse ? Design.text : Design.textDim
                        }
                        PointerArea {
                            id: ccArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: topBar.requestCommand("toggle:control:", true)
                        }
                        // No ToolTip. The bar's window is only as tall as the
                        // bar, so a ToolTip has nowhere to go but on top of the
                        // button it describes — and a ToolTip is a Popup, which
                        // takes the click. It appeared on hover and the button
                        // underneath could no longer be pressed.
                    }

                    // Notification bell — opens the notification centre.
                    //
                    // It opened the Control Center's main page: the tile grid,
                    // with the notifications one tap further in. A bell that
                    // does not go to the notifications is the wrong bell.
                    // `toggle:notifications:` opens the same window straight
                    // on that list.
                    //
                    // It also carried no count, while the service has always
                    // published one — so the only sign that anything had
                    // arrived was a toast you had to catch before it faded.
                    Box {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Design.s(Design.size.mini); height: Design.s(Design.size.mini); radius: Design.s(Design.radius.sm)
                        color: bellArea.containsMouse ? Design.stateHover : "transparent"
                        Icon {
                            anchors.centerIn: parent
                            // A focus mode on: its own glyph (the moon, the bed…).
                            text: Notifications.modeInfo ? Notifications.modeInfo.glyph
                                : (Notifications.unreadCount > 0 ? "󰂞" : "󰂚")
                            role: "body"
                            color: Notifications.dnd ? Design.textDim
                                 : (Notifications.unreadCount > 0 ? Design.accent : Design.textDim)
                        }

                        // A dot rather than a number: at this size a count of
                        // more than one digit is unreadable, and "something is
                        // waiting" is all the bar needs to say.
                        Box {
                            visible: Notifications.unreadCount > 0 && !Notifications.dnd
                            width: Design.s(Design.size.dot); height: Design.s(Design.size.dot)
                            radius: width / 2
                            color: Design.accent
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.rightMargin: -Design.s(Design.border)
                            anchors.topMargin: -Design.s(Design.border)
                            border.width: Design.border
                            border.color: Design.glassBg
                        }

                        PointerArea {
                            id: bellArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: (mouse) => {
                                if (mouse.button === Qt.RightButton)
                                    Notifications.toggleDnd();
                                else
                                    topBar.requestCommand("toggle:notifications:", true);
                            }
                        }
                    }

                    // Power Button (opens Session Menu)
                    Box {
                        id: powerBtn
                        anchors.verticalCenter: parent.verticalCenter
                        width: Design.s(Design.size.xs); height: Design.s(Design.size.xs); radius: Design.s(Design.radius.sm)
                        // Opening a menu is not a danger: the glyph in the
                        // bar's own colour. Red is kept for the menu's armed
                        // Reboot and Shut Down, where it means something.
                        color: powerArea.containsMouse ? Design.stateHover : "transparent"

                        Label {
                            anchors.centerIn: parent
                            text: "⏻"
                            family: topBar.fontMain
                            size: Design.s(Design.font.body)
                            weight: Design.weight.semibold
                            color: powerArea.containsMouse ? Design.text : Design.textDim
                        }

                        PointerArea {
                            id: powerArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: topBar.requestCommand("toggle:session:", true)
                        }
                    }
                }
            }
        }
    }
}
