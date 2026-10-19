import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Controls
import Ui

Window {
    id: window

    // Colours for every stock control in the window — tooltips, scroll bars,
    // combo boxes, text fields — from the desktop palette. Left to the Basic
    // style they were its own: a pale-yellow tooltip, light-grey bars.
    palette.window: Design.surface
    palette.windowText: Design.text
    palette.base: Design.sunken
    palette.alternateBase: Design.raised
    palette.text: Design.text
    palette.button: Design.raised
    palette.buttonText: Design.text
    palette.brightText: Design.text
    palette.highlight: Design.accent
    palette.highlightedText: Design.accentText
    palette.toolTipBase: Design.raised
    palette.toolTipText: Design.text
    palette.placeholderText: Design.textFaint
    palette.light: Design.active
    palette.midlight: Design.hover
    palette.mid: Design.line
    palette.dark: Design.sunken
    palette.shadow: Design.ground
    title: I18n.tr("System Monitor")
    width: Design.s(Design.window.compactWidth)
    height: Design.s(Design.window.compactHeight)
    minimumWidth: Design.s(Design.window.minWidth)
    minimumHeight: Design.s(Design.window.minHeight)
    visible: true
    color: "transparent"

    onClosing: Qt.quit()

    readonly property bool isNative: typeof MonitorBackend !== "undefined"
    // Opens on Processes.
    //
    // It opened on Overview: four cards and a one-minute chart. That is a
    // glance, not the reason anyone launches a task manager — you open one to
    // find what is eating the machine, and that was behind a tab. Activity
    // Monitor, GNOME System Monitor and KSysGuard all open on the process
    // table; Ctrl+1 is still one keystroke away, and the status bar says so.
    property string currentTab: "processes" // "overview", "processes"

    // ── Metric bindings (Direct C++ in-memory properties when native, 0 JSON) ──
    readonly property real cpuPct: isNative ? MonitorBackend.cpuPercent : 0.0
    readonly property string cpuModelStr: isNative ? MonitorBackend.cpuModel : "CPU"
    readonly property int cpuCores: isNative ? MonitorBackend.cores : 4
    readonly property string loadAvgStr: isNative ? MonitorBackend.loadAvg : "0.0 0.0 0.0"

    readonly property real ramPct: isNative ? MonitorBackend.ramPercent : 0.0
    readonly property real ramUsedMb: isNative ? MonitorBackend.ramUsedMb : 0.0
    readonly property real ramTotalMb: isNative ? MonitorBackend.ramTotalMb : 0.0

    readonly property real swapUsedMb: isNative ? MonitorBackend.swapUsedMb : 0.0
    readonly property real swapTotalMb: isNative ? MonitorBackend.swapTotalMb : 0.0

    readonly property real diskPct: isNative ? MonitorBackend.diskPercent : 0.0
    readonly property real diskFreeGb: isNative ? MonitorBackend.diskFreeGb : 0.0
    readonly property real diskTotalGb: isNative ? MonitorBackend.diskTotalGb : 0.0

    readonly property string uptimeStr: isNative ? MonitorBackend.uptime : "0h 0m"

    /** The chart holds forty samples at 1.5s each — one minute. */
    readonly property bool historyFull:
        isNative && MonitorBackend.cpuHistory && MonitorBackend.cpuHistory.length >= 40

    property string procSearchQuery: ""
    property string procSortBy: "cpu" // "cpu", "mem", "name", "pid"

    Connections {
        target: isNative ? MonitorBackend : null
        function onHistoryChanged() {
            historyChart.requestPaint();
        }
    }

    // ── Global Shortcuts ─────────────────────────────────────────────────────
    Shortcut { sequence: "Escape"; onActivated: window.close() }
    Shortcut { sequence: "Ctrl+F"; onActivated: if (window.currentTab === "processes") searchInput.focusInput() }

    // The two tabs were reachable by mouse only, in a desktop whose whole point
    // is the keyboard.
    Shortcut { sequence: "Ctrl+1"; onActivated: window.currentTab = "overview" }
    Shortcut { sequence: "Ctrl+2"; onActivated: window.currentTab = "processes" }
    Shortcut { sequence: "Ctrl+Tab"; onActivated: window.currentTab = (window.currentTab === "overview" ? "processes" : "overview") }

    // The metric cards are Ui/MetricTile now (moved from here, so the
    // Control Center can draw a reading the same way).

    Shortcut { sequence: "F5"; onActivated: if (isNative) MonitorBackend.refresh() }

    Rectangle {
        id: windowFrame
        anchors.fill: parent
        // No corners or outline of our own: sway draws both, and only sway
        // knows which window has focus. The app drew a fixed 1px line and sway
        // was told `border none` for it, so ours were the only windows on the
        // desktop that did not light up when focused. SwayFX's corner_radius
        // rounds the surface; a 14px radius inside its 10px one left slivers.
        radius: 0
        color: Design.glassBg
        clip: true

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // ═════════════════════════════════════════════════════════════════
            // HEADER BAR (COMPACT TILED TOOLBAR)
            // ═════════════════════════════════════════════════════════════════
            AppToolbar {
                Layout.fillWidth: true

                // Two views of one machine: a segmented control, as everywhere
                // a choice of view is. The filter is the toolbar's search
                // field, on the view it filters.
                SegmentedControl {
                    size: "sm"
                    model: [
                        { id: "overview",  label: I18n.tr("Overview"),  icon: "\u{f0128}" },
                        { id: "processes", label: I18n.tr("Processes"), icon: "\u{f0279}" }
                    ]
                    current: window.currentTab
                    onPicked: id => window.currentTab = id
                }
                Item { Layout.fillWidth: true }
                Field {
                    id: searchInput
                    visible: window.currentTab === "processes"
                    Layout.preferredWidth: Design.s(Design.width.control)
                    placeholder: I18n.tr("Filter processes (Ctrl+F)")
                    onEdited: value => {
                        window.procSearchQuery = value;
                        if (isNative) MonitorBackend.setProcessFilter(value);
                    }
                }
                Button { variant: "ghost"; iconOnly: true; icon: "\u{f0450}"; tip: I18n.tr("Refresh now (F5)"); onClicked: if (isNative) MonitorBackend.refresh() }
            }

        // ═════════════════════════════════════════════════════════════════════
        // TAB 1: OVERVIEW (METRICS, DIALS & LIVE HISTORY GRAPH)
        // ═════════════════════════════════════════════════════════════════════
        ScrollView {
            id: overviewScroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: window.currentTab === "overview"
            clip: true

            ColumnLayout {
                id: overviewCol
                x: Design.s(Design.space.md)
                width: window.width - Design.s(Design.space.md * 2)
                // Without a height the column sizes to its content, so nothing
                // inside it could expand and the Overview tab left roughly 600
                // px of empty black below the chart on a 1080p screen.
                height: Math.max(implicitHeight, overviewScroll.availableHeight - Design.s(Design.space.sm))
                spacing: Design.s(Design.space.md)

                Item { Layout.preferredHeight: Design.s(Design.space.xs) }

                // ── 1. Top metric cards ──────────────────────────────────────
                GridLayout {
                    Layout.fillWidth: true
                    columns: window.width > 900 ? 4 : 2
                    rowSpacing: Design.s(Design.space.sm)
                    columnSpacing: Design.s(Design.space.sm)

                    MetricTile {
                        label: "CPU"
                        value: window.cpuPct.toFixed(1) + "%"
                        sub: I18n.trn("%1 core  ·  load %2", "%1 cores  ·  load %2", window.cpuCores, window.loadAvgStr.split(" ")[0])
                        pct: window.cpuPct
                        tone: Design.sapphire
                    }

                    MetricTile {
                        label: I18n.tr("Memory")
                        value: (window.ramUsedMb / 1024.0).toFixed(1) + " GB"
                        sub: I18n.tr("of %1 GB  ·  %2% used", (window.ramTotalMb / 1024.0).toFixed(1), Math.round(window.ramPct))
                        pct: window.ramPct
                        tone: Design.mauve
                    }

                    // The ring used to read 11% next to "154.9 GB / Free Space",
                    // leaving it ambiguous whether the ring meant used or free.
                    // It is the used share, and the subtitle now says so.
                    MetricTile {
                        label: I18n.tr("Storage")
                        value: I18n.tr("%1 GB free", window.diskFreeGb.toFixed(1))
                        sub: I18n.tr("of %1 GB  ·  %2% used", window.diskTotalGb.toFixed(1), Math.round(window.diskPct))
                        pct: window.diskPct
                        tone: Design.peach
                    }

                    // Uptime is not a percentage, so it gets the glyph rather
                    // than an empty ring pretending to be a gauge. The task
                    // count moved out of here — it has nothing to do with
                    // uptime and already has a home in the status bar.
                    MetricTile {
                        label: I18n.tr("Uptime")
                        value: window.uptimeStr
                        sub: "since last boot"
                        pct: -1
                        glyph: "\u{f0954}"
                        tone: Design.ok
                    }
                }


                // ── 2. Live Performance History Graph ────────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: Design.s(Design.width.control)
                    radius: Design.s(Design.radius.card)
                    color: Design.glassCard
                    border.color: Design.glassBorder
                    border.width: Design.border

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Design.s(Design.space.lg)
                        spacing: Design.s(Design.space.sm)

                        RowLayout {
                            Layout.fillWidth: true

                            Text {
                                // Says so while the minute is still filling,
                                // rather than letting a short trace look like
                                // a machine that was idle and then spiked.
                                text: window.historyFull
                                      ? I18n.tr("Activity, last 60 seconds")
                                      : I18n.tr("Activity (collecting…)")
                                font.family: Design.font.sans
                                font.weight: Design.weight.semibold
                                font.pixelSize: Design.s(Design.font.body)
                                color: Design.text
                            }

                            Item { Layout.fillWidth: true }

                            // Legend
                            RowLayout {
                                spacing: Design.s(Design.space.lg)

                                RowLayout {
                                    spacing: Design.s(Design.space.xs)
                                    Rectangle { width: Design.s(Design.space.sm); height: Design.s(Design.space.sm); radius: 2; color: Design.sapphire }
                                    Text { text: I18n.tr("CPU"); font.family: Design.font.sans; font.pixelSize: Design.s(Design.font.caption); color: Design.textDim }
                                }

                                RowLayout {
                                    spacing: Design.s(Design.space.xs)
                                    Rectangle { width: Design.s(Design.space.sm); height: Design.s(Design.space.sm); radius: 2; color: Design.mauve }
                                    Text { text: I18n.tr("Memory"); font.family: Design.font.sans; font.pixelSize: Design.s(Design.font.caption); color: Design.textDim }
                                }
                            }
                        }

                        Canvas {
                            id: historyChart
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            onPaint: {
                                let ctx = getContext("2d");
                                ctx.clearRect(0, 0, width, height);

                                function css(c, a) {
                                    return "rgba(" + Math.round(c.r * 255) + ","
                                                   + Math.round(c.g * 255) + ","
                                                   + Math.round(c.b * 255) + "," + a + ")";
                                }

                                // The chart used to draw four unlabelled grid
                                // lines, so a line halfway up the card could
                                // have meant 50% or 5% — there was nothing to
                                // read it against. Percentages now sit in a
                                // gutter and the plot starts after it.
                                const gutter = Design.s(Design.size.md);
                                const plotX = gutter;
                                const plotW = Math.max(1, width - gutter);

                                // The axis stops just above the busiest sample
                                // instead of always at 100%. A machine idling at
                                // 1-2% drew its whole history as a flat line
                                // pinned to the bottom pixel of a 700px card:
                                // technically correct, and it showed nothing at
                                // all. The ceiling snaps to a round number and
                                // the labels say which one, so a rescaled chart
                                // still cannot be misread as a busy one.
                                function ceilingFor(a, b) {
                                    let peak = 0;
                                    for (const s of [a, b])
                                        for (const v of (s || []))
                                            if (v > peak) peak = v;
                                    // Every rung divides by four, so the four
                                    // gridlines always land on whole numbers —
                                    // a ceiling of 50 labelled them 38% and
                                    // 13%, which reads like a measurement
                                    // rather than an axis.
                                    for (const c of [8, 20, 40, 60, 80, 100])
                                        if (peak <= c) return c;
                                    return 100;
                                }
                                const ceiling = ceilingFor(
                                    isNative ? MonitorBackend.cpuHistory : [],
                                    isNative ? MonitorBackend.ramHistory : []);

                                ctx.lineWidth = 1;
                                ctx.font = Design.s(Design.space.sm) + "px " + Design.font.mono;
                                ctx.textBaseline = "middle";
                                for (let i = 0; i <= 4; ++i) {
                                    const pctLabel = Math.round(ceiling - i * (ceiling / 4));
                                    const y = Math.round((i / 4) * (height - 10)) + 5;
                                    ctx.strokeStyle = css(Design.text, i === 4 ? 0.16 : 0.06);
                                    ctx.beginPath();
                                    ctx.moveTo(plotX, y);
                                    ctx.lineTo(width, y);
                                    ctx.stroke();
                                    ctx.fillStyle = css(Design.textDim, 0.85);
                                    ctx.fillText(pctLabel + "%", 0, y);
                                }

                                function drawSeries(data, color, fillGrad) {
                                    if (!data || data.length < 2) return;
                                    let step = plotW / (40 - 1);
                                    let offset = plotX + (40 - data.length) * step;

                                    ctx.beginPath();
                                    for (let i = 0; i < data.length; ++i) {
                                        let x = offset + (i * step);
                                        let y = height - ((Math.min(data[i], ceiling) / ceiling) * (height - 10)) - 5;
                                        if (i === 0) ctx.moveTo(x, y);
                                        else ctx.lineTo(x, y);
                                    }
                                    ctx.strokeStyle = color;
                                    ctx.lineWidth = 2;
                                    ctx.stroke();

                                    ctx.lineTo(offset + ((data.length - 1) * step), height);
                                    ctx.lineTo(offset, height);
                                    ctx.closePath();
                                    ctx.fillStyle = fillGrad;
                                    ctx.fill();
                                }

                                let cpuData = isNative ? MonitorBackend.cpuHistory : [];
                                let ramData = isNative ? MonitorBackend.ramHistory : [];

                                // css() is declared with the grid above: Canvas
                                // needs CSS colour strings, and a stringified
                                // QML colour comes out as #AARRGGBB, which
                                // Canvas will not parse.
                                drawSeries(cpuData, css(Design.accent, 1.0), css(Design.accent, 0.15));
                                drawSeries(ramData, css(Design.mauve, 1.0),  css(Design.mauve, 0.10));
                            }
                        }
                    }
                }

                Item { Layout.preferredHeight: Design.s(Design.space.sm) }
            }
        }

        // ═════════════════════════════════════════════════════════════════════
        // TAB 2: PROCESSES (TASK MANAGER TABLE)
        // ═════════════════════════════════════════════════════════════════════
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: window.currentTab === "processes"
            spacing: 0

            // Table Header: sorted by a click on CPU or Memory, the way a
            // list header works, instead of a "Sort by CPU | RAM" pair.
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: Design.s(Design.size.md)
                color: Design.veil

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Design.s(Design.space.md)
                    anchors.rightMargin: Design.s(Design.space.md)
                    spacing: Design.s(Design.space.sm)

                    ColumnHead { label: I18n.tr("PID"); sortable: false; Layout.preferredWidth: Design.s(Design.size.tile) }
                    ColumnHead { label: I18n.tr("Process"); sortable: false; Layout.preferredWidth: Design.s(Design.width.select) }
                    // The name column was the only one with fillWidth, so it
                    // took every spare pixel: on a 1280px window it ran 950px
                    // wide for names that need two hundred, and the numbers
                    // anyone actually reads sat crushed against the far edge
                    // with a void between. The slack carries the reading now.
                    ColumnHead { label: I18n.tr("Load"); sortable: false; Layout.fillWidth: true }
                    ColumnHead { label: I18n.tr("User"); sortable: false; Layout.preferredWidth: Design.s(Design.size.stat) }
                    ColumnHead {
                        label: I18n.tr("CPU"); alignRight: true; ascending: false
                        sorted: window.procSortBy === "cpu"
                        Layout.preferredWidth: Design.s(Design.size.stat)
                        onClicked: { window.procSortBy = "cpu"; if (isNative) MonitorBackend.setProcessSort("cpu"); }
                    }
                    ColumnHead {
                        label: I18n.tr("Memory"); alignRight: true; ascending: false
                        sorted: window.procSortBy === "mem"
                        Layout.preferredWidth: Design.s(Design.size.stat)
                        onClicked: { window.procSortBy = "mem"; if (isNative) MonitorBackend.setProcessSort("mem"); }
                    }
                    Item { Layout.preferredWidth: Design.s(Design.size.stat) }
                }
            }

            // Process Rows List (Direct C++ Model)
            ListView {
                id: procList
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                reuseItems: true
                model: isNative ? MonitorBackend.processes : null

                ScrollBar.vertical: OverflowBar {}

                // Nothing yet, or nothing matches: said in the list's place.
                AppState {
                    parent: procList
                    anchors.fill: parent
                    // Without the backend nothing will ever arrive; waiting
                    // on it showed a spinner forever.
                    mode: !window.isNative ? "error"
                        : procList.count > 0 ? "" : (window.procSearchQuery !== "" ? "empty" : "loading")
                    icon: window.isNative ? "\u{f0349}" : ""
                    title: !window.isNative ? I18n.tr("Process list unavailable")
                         : window.procSearchQuery !== "" ? I18n.tr("No process matches “%1”", window.procSearchQuery)
                                                         : I18n.tr("Reading the process list…")
                }

                delegate: Rectangle {
                    width: procList.width
                    height: Design.s(Design.size.knob)
                    color: rowHover.containsMouse ? Design.tint(Design.text, 0.05) : (index % 2 === 0 ? "transparent" : Design.tint(Design.surface, 0.3))

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Design.s(Design.space.md)
                        anchors.rightMargin: Design.s(Design.space.md)
                        spacing: Design.s(Design.space.sm)

                        Text {
                            text: String(model.pid)
                            font.family: Design.font.mono
                            font.pixelSize: Design.s(Design.font.caption)
                            color: Design.textDim
                            Layout.preferredWidth: Design.s(Design.size.tile)
                        }

                        RowLayout {
                            // Explicitly false: Layout.fillWidth defaults to
                            // true for a nested layout and false for everything
                            // else, so this row went on taking the whole slack
                            // and Layout.preferredWidth alone did nothing — the
                            // bar beside it came out two pixels wide.
                            Layout.fillWidth: false
                            Layout.preferredWidth: Design.s(Design.width.select)
                            spacing: Design.s(Design.space.sm)

                            Text {
                                text: "\u{f108}" // binary icon
                                font.family: Design.font.icon
                                color: Design.textDim
                                font.pixelSize: Design.s(Design.font.footnote)
                            }

                            Text {
                                text: model.name
                                font.family: Design.font.sans
                                font.weight: Design.weight.semibold
                                font.pixelSize: Design.s(Design.font.body)
                                color: Design.text
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                            }
                        }

                        // What the empty middle of the table is for. A column of
                        // numbers has to be read one row at a time; a bar of the
                        // same numbers can be scanned, which is the whole reason
                        // to open a process list. CPU is the filled bar and
                        // memory the outline behind it, both on the same scale,
                        // so a process heavy on one and light on the other says
                        // so at a glance.
                        Item {
                            Layout.fillWidth: true
                            Layout.preferredHeight: Design.s(Design.space.sm)

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width
                                height: Design.s(Design.space.xs)
                                radius: height / 2
                                color: Design.tint(Design.text, 0.06)
                            }

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                // Clamped: a multi-core machine reports well
                                // over 100% for one process, and a bar wider
                                // than its track draws outside the column.
                                width: parent.width * Math.min(1, model.mem / 100)
                                height: Design.s(Design.space.xs)
                                radius: height / 2
                                color: "transparent"
                                border.color: Design.tint(Design.mauve, 0.55)
                                border.width: Design.border
                            }

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width * Math.min(1, model.cpu / 100)
                                height: Design.s(Design.space.xs)
                                radius: height / 2
                                color: model.cpu > 15.0 ? Design.danger
                                     : (model.cpu > 5.0 ? Design.warn : Design.tint(Design.sapphire, 0.75))
                            }
                        }

                        Text {
                            text: model.user
                            font.family: Design.font.sans
                            font.pixelSize: Design.s(Design.font.caption)
                            color: Design.textDim
                            Layout.preferredWidth: Design.s(Design.size.stat)
                        }

                        Text {
                            text: model.cpu.toFixed(1) + "%"
                            font.family: Design.font.mono
                            font.weight: model.cpu > 5.0 ? Design.weight.semibold : Design.weight.regular
                            font.pixelSize: Design.s(Design.font.caption)
                            color: model.cpu > 15.0 ? Design.danger : (model.cpu > 5.0 ? Design.warn : Design.text)
                            Layout.preferredWidth: Design.s(Design.size.stat)
                            horizontalAlignment: Text.AlignRight
                        }

                        Text {
                            text: model.mem.toFixed(1) + "%"
                            font.family: Design.font.mono
                            font.pixelSize: Design.s(Design.font.caption)
                            color: Design.textDim
                            Layout.preferredWidth: Design.s(Design.size.stat)
                            horizontalAlignment: Text.AlignRight
                        }

                        // Kill Action Buttons
                        RowLayout {
                            Layout.preferredWidth: Design.s(Design.size.stat)
                            Layout.alignment: Qt.AlignHCenter
                            spacing: Design.s(Design.space.xs)

                            Rectangle {
                                width: Design.s(Design.size.xs)
                                height: Design.s(Design.size.xs)
                                radius: width / 2
                                color: killHover.containsMouse ? Design.tint(Design.danger, 0.25) : "transparent"

                                Text {
                                    anchors.centerIn: parent
                                    text: "\u{f00d}" // cross
                                    font.family: Design.font.icon
                                    color: killHover.containsMouse ? Design.danger : Design.textDim
                                    font.pixelSize: Design.s(Design.font.caption)
                                }

                                HoverHandler { id: killHover }
                                Clickable {
                                    anchors.fill: parent
                                    onClicked: if (isNative) killConfirm.ask(model.pid, model.name, false)
                                }
                            }

                            Rectangle {
                                width: Design.s(Design.size.xs)
                                height: Design.s(Design.size.xs)
                                radius: width / 2
                                color: forceHover.containsMouse ? Design.danger : "transparent"

                                Text {
                                    anchors.centerIn: parent
                                    text: "\u{f057}" // skull / force kill
                                    font.family: Design.font.icon
                                    color: forceHover.containsMouse ? Design.ground : Design.textDim
                                    font.pixelSize: Design.s(Design.font.caption)
                                }

                                HoverHandler { id: forceHover }
                                Clickable {
                                    anchors.fill: parent
                                    onClicked: if (isNative) killConfirm.ask(model.pid, model.name, true)
                                }
                            }
                        }
                    }

                    HoverHandler { id: rowHover }
                }
            }
        }

        // ═════════════════════════════════════════════════════════════════════
        // BOTTOM STATUS BAR
        // ═════════════════════════════════════════════════════════════════════
        AppStatusBar {
            Layout.fillWidth: true
            Label {
                Layout.fillWidth: true
                text: I18n.trn("%1 process  ·  load %2  ·  up %3", "%1 processes  ·  load %2  ·  up %3", isNative ? MonitorBackend.taskCount : 0, window.loadAvgStr, window.uptimeStr)
                role: "caption"
                dim: true
                elide: Text.ElideRight
            }
            Label { text: I18n.tr("Ctrl+1/2 tabs  ·  Ctrl+F search  ·  F5 refresh  ·  Esc close"); role: "caption"; color: Design.textFaint }
        }
    }
}

    // Ending a process asks first, naming the process and pid as they were
    // when the button was pressed. It killed on the click, and the list
    // re-sorts every refresh, so the row under the pointer could already be
    // another process by the time the button came down.
    AppDialog {
        id: killConfirm
        property int pid: 0
        property string procName: ""
        property bool force: false
        function ask(pid, name, force) {
            killConfirm.pid = pid;
            killConfirm.procName = name;
            killConfirm.force = force;
            open();
        }
        title: I18n.tr(force ? "Force quit %1?" : "End %1?", procName)
        message: force
            ? I18n.tr("Process %1 is stopped at once (SIGKILL). Anything unsaved in it is lost.", pid)
            : I18n.tr("Process %1 is asked to quit (SIGTERM).", pid)
        destructive: true
        standardButtons: Dialog.Cancel | Dialog.Ok
        buttonText: ({ [Dialog.Ok]: I18n.tr("End Process") })
        onAccepted: MonitorBackend.killProcess(pid, force)
    }

    // Why a kill did not happen (another user's process, already gone).
    Connections {
        target: window.isNative ? MonitorBackend : null
        function onKillFailed(message) {
            killError.text = message;
            killErrorTimer.restart();
        }
    }
    Timer { id: killErrorTimer; interval: 4000; onTriggered: killError.text = "" }
    Rectangle {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Design.s(Design.size.row)
        visible: killError.text.length > 0
        width: killError.implicitWidth + Design.s(Design.space.xl)
        height: Design.s(Design.size.md)
        radius: Design.s(Design.radius.ctl)
        color: Design.raised
        border.color: Design.danger
        border.width: Design.border
        Label { id: killError; anchors.centerIn: parent; color: Design.danger }
    }
}
