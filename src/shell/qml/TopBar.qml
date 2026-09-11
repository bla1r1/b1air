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
import Qt.labs.folderlistmodel
import "./Services"

PanelWindow {
    id: topBar

    // The sway IPC socket, resolved once and kept current.
    //
    // Every swaymsg call below used to open a shell purely to run
    //     SWAYSOCK=$(ls -t /run/user/$(id -u)/sway-ipc.*.sock | head -n1)
    // because a shell that outlives a sway restart would otherwise inherit a
    // dead socket. The concern is real, the per-call glob is not: listing the
    // directory here follows a restart by itself, and the value is handed to
    // each process through its environment instead of through `bash -c`.
    readonly property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || "/run/user/1000"

    property string swaySock: Quickshell.env("SWAYSOCK") || ""

    FolderListModel {
        id: swaySockets
        folder: "file://" + topBar.runtimeDir
        showDirs: false
        showFiles: true
        showDotAndDotDot: false
        sortField: FolderListModel.Time
        onCountChanged: {
            // nameFilters matches files, and these are sockets, so the newest
            // sway-ipc.*.sock is picked out by hand.
            for (let i = 0; i < count; ++i) {
                const n = String(get(i, "fileName"));
                if (n.startsWith("sway-ipc.") && n.endsWith(".sock")) {
                    topBar.swaySock = topBar.runtimeDir + "/" + n;
                    return;
                }
            }
        }
    }

    readonly property var swayEnv: ({ "SWAYSOCK": topBar.swaySock })

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

    readonly property bool isPrimary: {
        const pinned = Settings.barPrimaryOutput || "";
        if (pinned !== "")
            return topBar.outputName === pinned;
        // Nothing pinned: the first screen the compositor reports. Also true
        // when there is only one, which is what keeps a single-monitor desktop
        // exactly as it was.
        const all = Quickshell.screens;
        return !all || all.length === 0 || !all[0] || all[0].name === topBar.outputName;
    }

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

    // Wayland Layer-Shell configuration
    WlrLayershell.namespace: "b1air-topbar"
    WlrLayershell.layer: WlrLayer.Overlay
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
    WlrLayershell.exclusiveZone: Design.s(40)
    
    // Settings → Native Top Bar has a Top/Bottom control; nothing read it, so
    // the bar was anchored to the top whatever it said.
    anchors.top: Settings.barPosition !== "bottom"
    anchors.bottom: Settings.barPosition === "bottom"
    anchors.left: true
    anchors.right: true
    implicitHeight: Design.s(38)

    // Transparent: the bar is its islands, floating over the desktop.
    //
    // A translucent strip was tried here to stop the bar reading as a black
    // band on a plain background. It was the wrong half of that problem — the
    // band was the outer gap opening a strip of bare desktop between the bar
    // and the first window, and `gaps top 0` in conf.d/look-and-feel.conf
    // closes it. With the window starting immediately below, the islands have
    // nothing to be mistaken for.
    color: "transparent"

    // ── Design Tokens ───────────────────────────────────────────────────────
    // These were a second, hand-rolled Tokyo Night palette living alongside the
    // Catppuccin one in Ui/Design.qml, so the bar never followed the theme. The
    // names stay — they are used throughout this file — but each now resolves
    // to a design-system role.
    readonly property color colBg: Design.glassBg
    readonly property color colBorder: Design.glassBorder
    readonly property color colBlue: Design.accent
    readonly property color colPurple: Design.mauve
    readonly property color colCyan: Design.sapphire
    readonly property color colGreen: Design.ok
    readonly property color colOrange: Design.warn
    readonly property color colRed: Design.danger
    readonly property color colFg: Design.text
    readonly property color colFgDim: Design.textDim
    readonly property color colWrkBg: Design.glassTile
    readonly property color colWrkBorder: Design.line
    readonly property string fontMain: Design.font.sans

    function safePinnedCommand(cmd) {
        const value = (cmd || "").trim();
        const forbidden = [";", "&", "|", "`", "$", "<", ">", "\\", "\n", "\r", "(", ")", "{", "}", "[", "]", "*", "?", "!", "~"];
        if (!value || value.length > 512 || forbidden.some(c => value.includes(c))) return false;
        Quickshell.execDetached(["bash", "-c", value]);
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
        runningAppsProcess.running = false;
        runningAppsProcess.running = true;
    }

    function refreshWorkspaces() {
        workspacesProcess.running = false;
        workspacesProcess.running = true;
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
        const value = (icon || "application-x-executable").trim();
        if (value.startsWith("/") || value.startsWith("file://")) return value.startsWith("file://") ? value : "file://" + value;
        // The suite's own icons, by file: they live in ~/.local/share/icons,
        // which not every icon theme lookup searches.
        if (value.startsWith("b1air-")) return "file://" + Quickshell.env("HOME") + "/.local/share/icons/hicolor/scalable/apps/" + value + ".svg";
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
            topBar.clockTime = Qt.formatTime(now, Settings.barClock24h ? "hh:mm" : "h:mm AP");
            topBar.clockDate = Qt.formatDate(now, "dddd, d MMMM yyyy");
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

    Timer {
        interval: 2000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            procStat.reload();
            procMem.reload();
        }
    }

    // Read once at startup and then only when sway says the layout changed.
    Process {
        id: layoutProbe
        command: ["swaymsg", "-t", "get_inputs"]
        environment: topBar.swayEnv
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const inputs = JSON.parse(this.text);
                    for (const dev of inputs) {
                        const name = dev.xkb_active_layout_name;
                        if (!name)
                            continue;
                        // The layout's own code, by position: sway's layouts
                        // are the ones Settings -> Keyboard wrote, in order.
                        // Cutting the name down gave "UK" for Ukrainian, "GE"
                        // for German and "PO" for Polish, though the comment
                        // here promised "UA".
                        const codes = String(Settings.language || "").split(",")
                            .map(x => x.trim()).filter(x => x !== "");
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
                } catch (e) {}
            }
        }
    }

    function refreshLayout() {
        layoutProbe.running = false;
        layoutProbe.running = true;
    }

    Timer {
        id: layoutCoalesce
        interval: 200
        onTriggered: topBar.refreshLayout()
    }

    Process {
        id: workspacesProcess
        command: ["swaymsg", "-t", "get_workspaces"]
        environment: topBar.swayEnv
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let ws = JSON.parse(this.text);
                    if (Array.isArray(ws) && ws.length > 0) topBar.workspacesList = ws;
                } catch (e) {}
            }
        }
    }

    Process {
        id: runningAppsProcess
        // Resolve the current socket on every refresh: Sway assigns a new
        // socket after a restart, so inheriting an old SWAYSOCK hides windows.
        command: ["swaymsg", "-t", "get_tree"]
        environment: topBar.swayEnv
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let tree = JSON.parse(this.text);
                    let apps = [];
                    topBar.collectSwayNodes([tree], apps, "");
                    topBar.runningApps = apps;
                } catch (e) {
                    topBar.runningApps = [];
                }
            }
        }
    }

    // Sway pushes window/workspace events, so there is nothing to poll for:
    // one long-lived subscription replaces a get_tree spawn every second.
    Process {
        id: swayEvents
        running: true
        command: [
            "bash", "-c",
            // SWAYSOCK arrives through `environment` below; the shell is still
            // needed here only for the pgrep/kill reap loop.
            // swaymsg blocks on the sway socket and never notices its stdout closing,
            // so it outlives the shell instead of dying with it. Reap the previous
            // one here: at most one stale subscription can ever exist.
            "for p in $(pgrep -f 'swaymsg -t subscribe -m' 2>/dev/null); do " +
            "  [ \"$p\" != \"$$\" ] && kill \"$p\" 2>/dev/null; done; " +
            "exec swaymsg -t subscribe -m '[\"window\",\"workspace\",\"input\"]'"
        ]
        environment: topBar.swayEnv
        stdout: SplitParser {
            // Coalesce bursts: dragging a window emits a stream of events, and one
            // refresh per event would spawn more processes than the old polling did.
            //
            // sway pretty-prints its replies, so an input event arrives as many
            // lines and one of them is `"change": "xkb_layout"`. Matching that
            // line is safe in a way that matching a substring of the whole
            // document is not — which is the trap six features in this project
            // fell into.
            onRead: (line) => {
                const text = ("" + line).trim();
                if (!text)
                    return;
                if (text.includes("xkb_layout"))
                    layoutCoalesce.restart();
                else
                    swayCoalesce.restart();
            }
        }
        // Sway restarts hand out a new socket; reconnect instead of going stale.
        onExited: swayResubscribe.restart()
    }

    Timer {
        id: swayCoalesce
        interval: 120
        onTriggered: {
            topBar.refreshRunningApps();
            topBar.refreshWorkspaces();
        }
    }

    Timer {
        id: swayResubscribe
        interval: 2000
        onTriggered: {
            topBar.refreshRunningApps();
            topBar.refreshWorkspaces();
            topBar.refreshLayout();
            swayEvents.running = true;
        }
    }

    // ── Bar Content Layout ──────────────────────────────────────────────────
    Item {
        anchors.fill: parent
        anchors.leftMargin: Design.s(8)
        anchors.rightMargin: Design.s(8)
        anchors.topMargin: Design.s(4)
        anchors.bottomMargin: Design.s(4)

        // ══════════════════════════════════════════════════════════════════════
        // LEFT ISLANDS: APPS, Dynamic Pinned Apps, Workspaces
        // ══════════════════════════════════════════════════════════════════════
        Row {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Design.s(6)

            // 1. APPS Island (Launchpad on Left Click, Spotlight on Right Click)
            Rectangle {
                id: appMenuBtn
                visible: Settings.barShowApps
                width: appRow.implicitWidth + Design.s(20)
                height: Design.s(30)
                radius: Design.s(10)
                color: appMenuArea.containsMouse ? Design.tint(Design.accent, 0.25) : topBar.colBg
                border.color: appMenuArea.containsMouse ? topBar.colBlue : topBar.colBorder
                border.width: 1

                Behavior on color { ColorAnimation { duration: 150 } }
                Behavior on border.color { ColorAnimation { duration: 150 } }

                Row {
                    id: appRow
                    anchors.centerIn: parent
                    spacing: Design.s(6)
                    Text {
                        text: "󰍜"
                        font.family: Design.font.mono
                        font.pixelSize: Design.s(13)
                        color: topBar.colBlue
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: "APPS"
                        font.family: topBar.fontMain
                        font.pixelSize: Design.s(12)
                        font.bold: true
                        color: appMenuArea.containsMouse ? "#ffffff" : topBar.colBlue
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                MouseArea {
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
            Rectangle {
                height: Design.s(30)
                width: pinnedRow.implicitWidth + Design.s(14)
                radius: Design.s(10)
                color: topBar.colBg
                border.color: topBar.colBorder
                border.width: 1
                visible: Settings.barShowPinned && PinnedApps.pinnedList.length > 0

                Row {
                    id: pinnedRow
                    anchors.centerIn: parent
                    spacing: Design.s(4)

                    Repeater {
                        model: PinnedApps.pinnedList
                        delegate: Rectangle {
                            id: pinPill
                            width: Design.s(24)
                            height: Design.s(24)
                            radius: Design.s(6)
                            color: pinArea.containsMouse ? Design.tint(Design.accent, 0.22) : "transparent"

                            IconImage {
                                anchors.centerIn: parent
                                width: Design.s(17)
                                height: Design.s(17)
                                source: topBar.iconSource(modelData.icon)
                                mipmap: true
                            }

                            MouseArea {
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
                    Rectangle {
                        width: Design.s(20)
                        height: Design.s(20)
                        radius: Design.s(5)
                        color: addPinArea.containsMouse ? Design.tint(Design.accent, 0.25) : "transparent"
                        anchors.verticalCenter: parent.verticalCenter

                        Text {
                            anchors.centerIn: parent
                            text: "󰐕"
                            font.family: Design.font.mono
                            font.pixelSize: Design.s(11)
                            color: addPinArea.containsMouse ? topBar.colBlue : topBar.colFgDim
                        }

                        MouseArea {
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
            Rectangle {
                id: workspacesIsland
                visible: Settings.barShowWorkspaces
                height: Design.s(30)
                width: workspacesRow.implicitWidth + Design.s(12)
                radius: Design.s(10)
                color: topBar.colBg
                border.color: topBar.colBorder
                border.width: 1

                Row {
                    id: workspacesRow
                    anchors.centerIn: parent
                    spacing: Design.s(4)

                    Repeater {
                        model: topBar.workspaceSlots
                        delegate: Rectangle {
                            id: wsPill
                            required property var modelData

                            width: wsText.implicitWidth + Design.s(14)
                            height: Design.s(22)
                            radius: Design.s(6)
                            color: wsPill.modelData.focused ? topBar.colBlue
                                 : (wsMouseArea.containsMouse ? Design.tint(Design.accent, 0.20) : topBar.colWrkBg)
                            border.color: wsPill.modelData.focused ? "transparent" : topBar.colWrkBorder
                            border.width: 1

                            // An empty slot is a place you can go, not a place
                            // you are; it says so by being fainter rather than
                            // by being missing.
                            opacity: wsPill.modelData.exists || wsPill.modelData.focused ? 1.0 : 0.45

                            Text {
                                id: wsText
                                anchors.centerIn: parent
                                text: wsPill.modelData.name
                                font.family: topBar.fontMain
                                font.pixelSize: Design.s(11)
                                font.bold: true
                                color: wsPill.modelData.focused ? Design.accentText
                                     : (wsMouseArea.containsMouse ? topBar.colBlue : topBar.colFgDim)
                            }

                            MouseArea {
                                id: wsMouseArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    const workspace = String(wsPill.modelData.name);
                                    if (/^[A-Za-z0-9_.-]+$/.test(workspace))
                                        Quickshell.execDetached(["swaymsg", "workspace", workspace]);
                                }
                            }
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    z: -1
                    onWheel: (wheel) => {
                        if (wheel.angleDelta.y > 0) {
                            Quickshell.execDetached({ command: ["swaymsg", "workspace", "prev"], environment: topBar.swayEnv });
                        } else if (wheel.angleDelta.y < 0) {
                            Quickshell.execDetached({ command: ["swaymsg", "workspace", "next"], environment: topBar.swayEnv });
                        }
                    }
                }
            }

            // Old Waybar placed the taskbar after workspaces on the left.
            // Keep that topology, but render compact native icons.
            Row {
                id: runningAppsRow
                anchors.verticalCenter: parent.verticalCenter
                spacing: Design.s(3)
                visible: topBar.runningApps.length > 0

                Repeater {
                    model: topBar.runningApps
                    delegate: Rectangle {
                        width: Design.s(28)
                        height: Design.s(28)
                        radius: Design.s(7)
                        color: modelData.focused ? Design.tint(Design.accent, 0.22) : topBar.colBg
                        border.color: modelData.focused ? topBar.colBlue : topBar.colBorder
                        border.width: 1

                        IconImage {
                            anchors.centerIn: parent
                            width: Design.s(18)
                            height: Design.s(18)
                            source: topBar.iconSource(topBar.appIcon(modelData.appId))
                            mipmap: true
                        }

                        MouseArea {
                            id: runningArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Quickshell.execDetached({
                                command: ["swaymsg", "[con_id=" + String(modelData.id) + "] focus"],
                                environment: topBar.swayEnv
                            })
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
        Rectangle {
            id: clockPill
            anchors.centerIn: parent
            width: clockText.implicitWidth + Design.s(36)
            height: Design.s(28)
            radius: 999
            color: clockArea.containsMouse ? Qt.lighter(topBar.colBlue, 1.25) : topBar.colBlue

            Behavior on color { ColorAnimation { duration: 150 } }

            Text {
                id: clockText
                anchors.centerIn: parent
                text: topBar.clockTime
                font.family: topBar.fontMain
                font.pixelSize: Design.s(13)
                font.bold: true
                color: topBar.colFg
            }

            MouseArea {
                id: clockArea
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                cursorShape: Qt.PointingHandCursor
                onClicked: (mouse) => {
                    if (mouse.button === Qt.MiddleButton) {
                        topBar.requestCommand("toggle:focustime:", true);
                    } else if (mouse.button === Qt.RightButton) {
                        topBar.requestCommand("toggle:pollkit:", true);
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
        Rectangle {
            id: focusPill
            visible: Focus.active
            anchors.right: clockPill.left
            anchors.rightMargin: Design.s(6)
            anchors.verticalCenter: parent.verticalCenter
            width: focusRow.implicitWidth + Design.s(22)
            height: Design.s(28)
            radius: 999

            readonly property color tone: Focus.onBreak ? Design.green : Design.sapphire
            color: focusArea.containsMouse ? Qt.alpha(tone, 0.32) : Qt.alpha(tone, 0.18)
            border.width: 1
            border.color: Qt.alpha(tone, Focus.running ? 0.55 : 0.28)

            Behavior on color { ColorAnimation { duration: 150 } }

            Row {
                id: focusRow
                anchors.centerIn: parent
                spacing: Design.s(6)

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    // Paused shows the play glyph: it is what the click does.
                    text: Focus.running ? "\u{f0520}" : "\u{f040a}"
                    font.family: Design.font.icon
                    font.pixelSize: Design.s(12)
                    color: focusPill.tone
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: Focus.remainingText
                    font.family: topBar.fontMain
                    font.pixelSize: Design.s(12)
                    font.bold: true
                    color: focusPill.tone
                    opacity: Focus.running ? 1.0 : 0.65
                }
            }

            MouseArea {
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
            spacing: Design.s(6)

            // 0. Media title and weather.
            //
            // Settings → Native Top Bar has offered "Media Player Title —
            // display currently playing track name and artist" and "Weather
            // Status — show temperature and weather condition badge" since it
            // was written, and the bar had neither module: the two switches
            // stored a value nothing read. Both services already exist and are
            // used by the Control Center, so this is wiring, not new plumbing.

            Rectangle {
                height: Design.s(30)
                width: mediaRow.implicitWidth + Design.s(20)
                radius: Design.s(10)
                color: mediaArea.containsMouse ? Design.tint(Design.mauve, 0.15) : topBar.colBg
                border.color: mediaArea.containsMouse ? Design.tint(Design.mauve, 0.35) : topBar.colBorder
                border.width: 1
                anchors.verticalCenter: parent.verticalCenter

                // Only when asked for, and only when there is something to say.
                visible: Settings.barShowMedia && Media.hasPlayer && !topBar.reduced
                         && String(Media.track.title || "") !== ""

                Row {
                    id: mediaRow
                    anchors.centerIn: parent
                    spacing: Design.s(6)

                    Text {
                        text: Media.playing ? "\u{f040a}" : "\u{f03e4}"
                        font.family: Design.font.icon
                        font.pixelSize: Design.s(12)
                        color: topBar.colBlue
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        // Elided rather than allowed to push the clock off
                        // centre: a track title is arbitrarily long.
                        width: Math.min(implicitWidth, Design.s(220))
                        elide: Text.ElideRight
                        text: (Media.track.artist ? Media.track.artist + " — " : "")
                              + (Media.track.title || "")
                        font.family: topBar.fontMain
                        font.pixelSize: Design.s(11)
                        color: topBar.colFgDim
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                MouseArea {
                    id: mediaArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: topBar.requestCommand("toggle:music:", true)
                }
            }

            Rectangle {
                height: Design.s(30)
                width: weatherRow.implicitWidth + Design.s(20)
                radius: Design.s(10)
                color: weatherArea.containsMouse ? Design.tint(Design.sapphire, 0.15) : topBar.colBg
                border.color: weatherArea.containsMouse ? Design.tint(Design.sapphire, 0.35) : topBar.colBorder
                border.width: 1
                anchors.verticalCenter: parent.verticalCenter

                visible: Settings.barShowWeather && Weather.loaded && !topBar.reduced

                Row {
                    id: weatherRow
                    anchors.centerIn: parent
                    spacing: Design.s(6)

                    Text {
                        text: Weather.icon
                        font.family: Design.font.icon
                        font.pixelSize: Design.s(12)
                        color: topBar.colCyan
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Text {
                        text: Weather.temp
                        font.family: topBar.fontMain
                        font.pixelSize: Design.s(11)
                        font.bold: true
                        color: topBar.colFgDim
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                MouseArea {
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
            Rectangle {
                height: Design.s(30)
                width: trayRow.implicitWidth + Design.s(20)
                radius: Design.s(10)
                color: topBar.colBg
                border.color: topBar.colBorder
                border.width: 1
                anchors.verticalCenter: parent.verticalCenter

                // No applets means no empty pill sitting in the bar.
                visible: Settings.barShowTray && SystemTray.items.values.length > 0 && !topBar.reduced

                Row {
                    id: trayRow
                    anchors.centerIn: parent
                    spacing: Design.s(8)

                    Repeater {
                        model: SystemTray.items

                        delegate: Item {
                            required property var modelData
                            width: Design.s(16)
                            height: Design.s(16)
                            anchors.verticalCenter: parent.verticalCenter

                            IconImage {
                                anchors.fill: parent
                                source: parent.modelData.icon
                                asynchronous: true
                            }

                            MouseArea {
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
                                        item.display(topBar, 0, Design.s(34));
                                    else
                                        item.activate();
                                }
                            }
                        }
                    }
                }
            }

            // 1. Stats Island (CPU + memory)
            Rectangle {
                height: Design.s(30)
                width: statsRow.implicitWidth + Design.s(20)
                visible: Settings.barShowStats && !topBar.reduced
                radius: Design.s(10)
                color: statsArea.containsMouse ? Design.tint(Design.accent, 0.15) : topBar.colBg
                border.color: statsArea.containsMouse ? Design.tint(Design.accent, 0.35) : topBar.colBorder
                border.width: 1

                Row {
                    id: statsRow
                    anchors.centerIn: parent
                    spacing: Design.s(10)

                    Row {
                        spacing: Design.s(4)
                        Text { anchors.verticalCenter: parent.verticalCenter; text: ""; font.family: topBar.fontMain; font.pixelSize: Design.s(12); color: topBar.colCyan }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: topBar.cpuUsage; font.family: topBar.fontMain; font.pixelSize: Design.s(11); font.bold: true; color: topBar.colFg }
                    }

                    Row {
                        spacing: Design.s(4)
                        Text { anchors.verticalCenter: parent.verticalCenter; text: "󰍛"; font.family: topBar.fontMain; font.pixelSize: Design.s(12); color: topBar.colPurple }
                        Text { anchors.verticalCenter: parent.verticalCenter; text: topBar.memUsage; font.family: topBar.fontMain; font.pixelSize: Design.s(11); font.bold: true; color: topBar.colFg }
                    }
                }

                MouseArea {
                    id: statsArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Quickshell.execDetached(["b1air-monitor"])
                }
            }

            // 2. System Status Island (Layout, Volume, Battery, Bell, Power)
            Rectangle {
                height: Design.s(30)
                width: systemRow.implicitWidth + Design.s(20)
                radius: Design.s(10)
                color: topBar.colBg
                border.color: topBar.colBorder
                border.width: 1

                Row {
                    id: systemRow
                    anchors.centerIn: parent
                    spacing: Design.s(10)

                    // Privacy dots. Present only while something is using the
                    // device, because an indicator that is always there is one
                    // nobody looks at.
                    Rectangle {
                        visible: topBar.micInUse
                        anchors.verticalCenter: parent.verticalCenter
                        width: Design.s(18); height: Design.s(18)
                        radius: width / 2
                        color: Design.tint(Design.red, 0.22)
                        Icon {
                            anchors.centerIn: parent
                            text: "\u{f036c}"
                            role: "caption"
                            color: Design.red
                        }
                        HoverHandler { id: micDotHover }
                        ToolTip.visible: micDotHover.hovered
                        ToolTip.text: "Microphone in use"
                    }

                    Rectangle {
                        visible: topBar.cameraInUse
                        anchors.verticalCenter: parent.verticalCenter
                        width: Design.s(18); height: Design.s(18)
                        radius: width / 2
                        color: Design.tint(Design.peach, 0.22)
                        Icon {
                            anchors.centerIn: parent
                            text: "\u{f0567}"
                            role: "caption"
                            color: Design.peach
                        }
                        HoverHandler { id: camDotHover }
                        ToolTip.visible: camDotHover.hovered
                        ToolTip.text: "Camera in use"
                    }

                    // Caps Lock, shown only while it is on — which is the only
                    // time anyone wants to know.
                    Rectangle {
                        visible: topBar.capsOn
                        anchors.verticalCenter: parent.verticalCenter
                        width: capsText.implicitWidth + Design.s(10)
                        height: Design.s(20)
                        radius: Design.s(5)
                        color: Design.tint(Design.yellow, 0.20)
                        Text {
                            id: capsText
                            anchors.centerIn: parent
                            text: "CAPS"
                            font.family: topBar.fontMain
                            font.pixelSize: Design.s(10)
                            font.bold: true
                            color: Design.yellow
                        }
                    }

                    // Keyboard Layout Pill
                    Rectangle {
                        width: kbdText.implicitWidth + Design.s(10)
                        height: Design.s(20)
                        radius: Design.s(5)
                        color: kbdArea.containsMouse ? Design.tint(Design.accent, 0.20) : "transparent"
                        Text {
                            id: kbdText
                            anchors.centerIn: parent
                            text: topBar.kbdLayout
                            font.family: topBar.fontMain
                            font.pixelSize: Design.s(11)
                            font.bold: true
                            color: topBar.colFg
                        }
                        MouseArea {
                            id: kbdArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                Quickshell.execDetached({
                                    command: ["swaymsg", "input", "type:keyboard", "xkb_switch_layout", "next"],
                                    environment: topBar.swayEnv
                                });
                                Quickshell.execDetached(["b1air-daemon", "layout"]);
                            }
                        }
                    }

                    // Volume Pill
                    Item {
                        width: volRow.implicitWidth
                        height: Design.s(20)
                        anchors.verticalCenter: parent.verticalCenter
                        Row {
                            id: volRow
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Design.s(4)
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: (Audio.defaultSink && Audio.defaultSink.audio && Audio.defaultSink.audio.muted) ? "󰖁" : "󰕾"
                                font.family: topBar.fontMain
                                font.pixelSize: Design.s(13)
                                color: (Audio.defaultSink && Audio.defaultSink.audio && Audio.defaultSink.audio.muted) ? topBar.colRed : topBar.colFgDim
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: (Audio.defaultSink && Audio.defaultSink.audio) ? Math.round(Audio.defaultSink.audio.volume * 100) + "%" : "65%"
                                font.family: topBar.fontMain
                                font.pixelSize: Design.s(11)
                                font.bold: true
                                color: topBar.colFg
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            // Straight to the sound page. It opened the
                            // Control Center's front page, which was the only
                            // way into the Control Center from the bar at all;
                            // that has its own button now, beside the bell.
                            onClicked: topBar.requestCommand("toggle:sound:", true)
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
                        height: Design.s(20)
                        anchors.verticalCenter: parent.verticalCenter
                        Row {
                            id: batRow
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Design.s(4)
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Power.charging ? "󰂄" : "󰁹"
                                font.family: topBar.fontMain
                                font.pixelSize: Design.s(13)
                                color: Power.charging ? Design.ok : topBar.colFgDim
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: Power.capacity + "%"
                                font.family: topBar.fontMain
                                font.pixelSize: Design.s(11)
                                font.bold: true
                                color: topBar.colFg
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: topBar.requestCommand("toggle:battery:", true)
                        }
                    }

                    // Control Center. It had no button: the only way in from
                    // the bar was clicking the volume percentage, which is not
                    // somewhere anyone looks for a panel of switches.
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Design.s(20); height: Design.s(20); radius: Design.s(5)
                        color: ccArea.containsMouse ? Design.tint(Design.accent, 0.20) : "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: "\u{f062e}"   // sliders — the same glyph as the panel's own header
                            font.family: topBar.fontMain
                            font.pixelSize: Design.s(13)
                            color: ccArea.containsMouse ? topBar.colBlue : topBar.colFgDim
                        }
                        MouseArea {
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
                    Rectangle {
                        width: Design.s(20); height: Design.s(20); radius: Design.s(5)
                        color: bellArea.containsMouse ? Design.tint(Design.accent, 0.20) : "transparent"
                        Text {
                            anchors.centerIn: parent
                            text: Notifications.dnd ? "󰂛"
                                : (Notifications.unreadCount > 0 ? "󰂞" : "󰂚")
                            font.family: topBar.fontMain
                            font.pixelSize: Design.s(13)
                            color: Notifications.dnd ? topBar.colFgDim
                                 : (Notifications.unreadCount > 0 ? topBar.colBlue : topBar.colFgDim)
                        }

                        // A dot rather than a number: at this size a count of
                        // more than one digit is unreadable, and "something is
                        // waiting" is all the bar needs to say.
                        Rectangle {
                            visible: Notifications.unreadCount > 0 && !Notifications.dnd
                            width: Design.s(6); height: Design.s(6)
                            radius: width / 2
                            color: Design.accent
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.rightMargin: -Design.s(1)
                            anchors.topMargin: -Design.s(1)
                            border.width: 1
                            border.color: topBar.colBg
                        }

                        MouseArea {
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
                    Rectangle {
                        id: powerBtn
                        width: Design.s(22); height: Design.s(22); radius: Design.s(6)
                        color: powerArea.containsMouse ? Design.tint(Design.danger, 0.25) : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: "⏻"
                            font.family: topBar.fontMain
                            font.pixelSize: Design.s(13)
                            font.bold: true
                            color: topBar.colRed
                        }

                        MouseArea {
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
