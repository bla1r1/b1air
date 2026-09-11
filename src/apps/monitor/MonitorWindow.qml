import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Controls
import Ui

Window {
    id: window
    title: "System Monitor"
    width: Design.s(880)
    height: Design.s(580)
    minimumWidth: Design.s(720)
    minimumHeight: Design.s(450)
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
    Shortcut { sequence: "Ctrl+F"; onActivated: if (window.currentTab === "processes") searchInput.forceActiveFocus() }

    // The two tabs were reachable by mouse only, in a desktop whose whole point
    // is the keyboard.
    Shortcut { sequence: "Ctrl+1"; onActivated: window.currentTab = "overview" }
    Shortcut { sequence: "Ctrl+2"; onActivated: window.currentTab = "processes" }
    Shortcut { sequence: "Ctrl+Tab"; onActivated: window.currentTab = (window.currentTab === "overview" ? "processes" : "overview") }

    // One card, four uses. These were four copies of the same sixty lines, and
    // the copies had drifted: the badge set `width`/`height` inside a RowLayout
    // instead of Layout.preferredWidth/Height, which a layout does not honour,
    // so identical-looking code positioned the text differently in each card —
    // CPU's label sat next to its badge while Memory's floated 200 px away.
    component MetricCard: Rectangle {
        id: card

        property string label: ""
        property string value: ""
        property string sub: ""
        property color tone: Design.accent
        // 0..100 draws a progress ring; below 0 draws the glyph instead.
        property real pct: -1
        property string glyph: ""

        Layout.fillWidth: true
        Layout.preferredHeight: Design.s(90)
        radius: Design.s(Design.radius.card)
        color: Design.ground
        border.color: Design.glassBorder
        border.width: 1

        RowLayout {
            anchors.fill: parent
            anchors.margins: Design.s(12)
            spacing: Design.s(12)

            Item {
                Layout.preferredWidth: Design.s(46)
                Layout.preferredHeight: Design.s(46)
                Layout.alignment: Qt.AlignVCenter

                // Track plus arc: the ring now reads as a gauge rather than
                // repeating the number printed beside it.
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: Design.tint(card.tone, 0.12)
                    border.color: Design.tint(card.tone, 0.35)
                    border.width: Design.s(2)
                }

                Canvas {
                    id: ringCanvas
                    anchors.fill: parent
                    visible: card.pct >= 0

                    // Canvas paints once when it is first shown; without these
                    // the arc was drawn before the card had a percentage (or
                    // before it had a size) and then never again, so all four
                    // rings rendered as empty circles.
                    Component.onCompleted: requestPaint()
                    onWidthChanged: requestPaint()
                    onHeightChanged: requestPaint()
                    onVisibleChanged: if (visible) requestPaint()

                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.reset();
                        const r = Math.min(width, height) / 2 - Design.s(1);
                        const cx = width / 2, cy = height / 2;
                        ctx.beginPath();
                        ctx.arc(cx, cy, r, -Math.PI / 2,
                                -Math.PI / 2 + (Math.max(0, Math.min(100, card.pct)) / 100) * 2 * Math.PI);
                        ctx.strokeStyle = card.tone;
                        ctx.lineWidth = Design.s(4);
                        ctx.lineCap = "round";
                        ctx.stroke();
                    }
                    Connections {
                        target: card
                        function onPctChanged() { ringCanvas.requestPaint(); }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: card.pct < 0 && card.glyph !== ""
                    text: card.glyph
                    font.family: Design.font.icon
                    font.pixelSize: Design.s(16)
                    color: card.tone
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: Design.s(2)

                Text {
                    text: card.label
                    font.family: Design.font.mono
                    font.weight: Design.weight.bold
                    font.pixelSize: Design.s(10)
                    color: Design.textDim
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }

                Text {
                    text: card.value
                    font.family: Design.font.sans
                    font.weight: Design.weight.bold
                    font.pixelSize: Design.s(16)
                    color: Design.text
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }

                Text {
                    text: card.sub
                    font.family: Design.font.sans
                    font.pixelSize: Design.s(10)
                    color: Design.textDim
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }
            }
        }
    }

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
        color: Design.base
        clip: true

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // ═════════════════════════════════════════════════════════════════
            // HEADER BAR (COMPACT TILED TOOLBAR)
            // ═════════════════════════════════════════════════════════════════
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: Design.s(36)
                color: Design.crust
                border.color: Design.glassBorder
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Design.s(Design.space.sm)
                    anchors.rightMargin: Design.s(Design.space.sm)
                    spacing: Design.s(Design.space.sm)

                    // No name and no badge. The window is opened by name and is a table of
                    // processes; "System Monitor" beside a bar-chart glyph told nobody
                    // anything, and removing the label left the icon on its own as pure
                    // decoration, so both went. The tabs take the space they were
                    // holding, at the start of the row where the eye already goes,
                    // instead of staying pinned to the far edge of an empty bar.

                // Tab Switcher Pills
                Rectangle {
                    implicitWidth: tabRow.implicitWidth + Design.s(6)
                    implicitHeight: Design.s(26)
                    radius: Design.s(Design.radius.ctl)
                    color: Design.sunken
                    border.color: Design.glassBorder
                    border.width: 1

                    RowLayout {
                        id: tabRow
                        anchors.centerIn: parent
                        spacing: Design.s(2)

                        Rectangle {
                            implicitWidth: Design.s(76)
                            implicitHeight: Design.s(22)
                            radius: Design.s(8)
                            color: window.currentTab === "overview" ? Design.tint(Design.accent, 0.28) : "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: "Overview"
                                font.family: Design.font.sans
                                font.weight: window.currentTab === "overview" ? Design.weight.bold : Design.weight.medium
                                font.pixelSize: Design.s(11)
                                color: window.currentTab === "overview" ? Design.accent : Design.textDim
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: window.currentTab = "overview"
                            }
                        }

                        Rectangle {
                            implicitWidth: Design.s(76)
                            implicitHeight: Design.s(22)
                            radius: Design.s(8)
                            color: window.currentTab === "processes" ? Design.tint(Design.accent, 0.28) : "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: "Processes"
                                font.family: Design.font.sans
                                font.weight: window.currentTab === "processes" ? Design.weight.bold : Design.weight.medium
                                font.pixelSize: Design.s(11)
                                color: window.currentTab === "processes" ? Design.accent : Design.textDim
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: window.currentTab = "processes"
                            }
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                // Refresh Button
                IconButton {
                    icon: "\u{f021}" // refresh
                    bordered: true
                    hoverTone: Design.accent
                    onClicked: if (isNative) MonitorBackend.refresh()
                }
            }
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
                height: Math.max(implicitHeight, overviewScroll.availableHeight - Design.s(8))
                spacing: Design.s(Design.space.md)

                Item { Layout.preferredHeight: Design.s(4) }

                // ── 1. Top metric cards ──────────────────────────────────────
                GridLayout {
                    Layout.fillWidth: true
                    columns: window.width > 900 ? 4 : 2
                    rowSpacing: Design.s(10)
                    columnSpacing: Design.s(10)

                    MetricCard {
                        label: "CPU"
                        value: window.cpuPct.toFixed(1) + "%"
                        sub: window.cpuCores + " cores  ·  load " + window.loadAvgStr.split(" ")[0]
                        pct: window.cpuPct
                        tone: Design.sapphire
                    }

                    MetricCard {
                        label: "MEMORY"
                        value: (window.ramUsedMb / 1024.0).toFixed(1) + " GB"
                        sub: "of " + (window.ramTotalMb / 1024.0).toFixed(1) + " GB  ·  "
                             + Math.round(window.ramPct) + "% used"
                        pct: window.ramPct
                        tone: Design.mauve
                    }

                    // The ring used to read 11% next to "154.9 GB / Free Space",
                    // leaving it ambiguous whether the ring meant used or free.
                    // It is the used share, and the subtitle now says so.
                    MetricCard {
                        label: "STORAGE"
                        value: window.diskFreeGb.toFixed(1) + " GB free"
                        sub: "of " + window.diskTotalGb.toFixed(1) + " GB  ·  "
                             + Math.round(window.diskPct) + "% used"
                        pct: window.diskPct
                        tone: Design.peach
                    }

                    // Uptime is not a percentage, so it gets the glyph rather
                    // than an empty ring pretending to be a gauge. The task
                    // count moved out of here — it has nothing to do with
                    // uptime and already has a home in the status bar.
                    MetricCard {
                        label: "UPTIME"
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
                    Layout.minimumHeight: Design.s(220)
                    radius: Design.s(Design.radius.card)
                    color: Design.ground
                    border.color: Design.glassBorder
                    border.width: 1

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: Design.s(16)
                        spacing: Design.s(8)

                        RowLayout {
                            Layout.fillWidth: true

                            Text {
                                // Says so while the minute is still filling,
                                // rather than letting a short trace look like
                                // a machine that was idle and then spiked.
                                text: window.historyFull
                                      ? "ACTIVITY HISTORY (LAST 60 SECONDS)"
                                      : "ACTIVITY HISTORY (COLLECTING…)"
                                font.family: Design.font.mono
                                font.weight: Design.weight.bold
                                font.pixelSize: Design.s(11)
                                color: Design.textDim
                            }

                            Item { Layout.fillWidth: true }

                            // Legend
                            RowLayout {
                                spacing: Design.s(16)

                                RowLayout {
                                    spacing: Design.s(6)
                                    Rectangle { width: Design.s(10); height: Design.s(10); radius: 2; color: Design.sapphire }
                                    Text { text: "CPU"; font.family: Design.font.sans; font.pixelSize: Design.s(11); color: Design.textDim }
                                }

                                RowLayout {
                                    spacing: Design.s(6)
                                    Rectangle { width: Design.s(10); height: Design.s(10); radius: 2; color: Design.mauve }
                                    Text { text: "Memory"; font.family: Design.font.sans; font.pixelSize: Design.s(11); color: Design.textDim }
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
                                const gutter = Design.s(34);
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
                                ctx.font = Design.s(9) + "px " + Design.font.mono;
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

                Item { Layout.preferredHeight: Design.s(8) }
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

            // Search and Sort Bar
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: Design.s(44)
                color: Design.ground
                border.color: Design.glassBorder
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Design.s(Design.space.md)
                    anchors.rightMargin: Design.s(Design.space.md)
                    spacing: Design.s(Design.space.md)

                    // Search Filter
                    Rectangle {
                        Layout.preferredWidth: Design.s(220)
                        implicitHeight: Design.s(30)
                        radius: Design.s(Design.radius.ctl)
                        color: Design.sunken
                        border.color: searchInput.activeFocus ? Design.accent : Design.glassBorder
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Design.s(8)
                            anchors.rightMargin: Design.s(8)
                            spacing: Design.s(6)

                            Text {
                                text: "\u{f002}" // search
                                font.family: Design.font.icon
                                color: Design.textDim
                                font.pixelSize: Design.s(11)
                            }

                            TextInput {
                                id: searchInput
                                Layout.fillWidth: true
                                font.family: Design.font.sans
                                font.pixelSize: Design.s(11)
                                color: Design.text
                                selectByMouse: true

                                Text {
                                    anchors.fill: parent
                                    text: "Filter processes..."
                                    color: Design.textDim
                                    font: parent.font
                                    visible: !searchInput.text && !searchInput.activeFocus
                                }

                                onTextChanged: {
                                    window.procSearchQuery = text;
                                    if (isNative) MonitorBackend.setProcessFilter(text);
                                }
                            }
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // Sort buttons
                    RowLayout {
                        spacing: Design.s(4)

                        Text {
                            text: "Sort by:"
                            font.family: Design.font.sans
                            font.pixelSize: Design.s(11)
                            color: Design.textDim
                        }

                        Rectangle {
                            implicitWidth: Design.s(54)
                            implicitHeight: Design.s(26)
                            radius: Design.s(8)
                            color: window.procSortBy === "cpu" ? Design.tint(Design.accent, 0.25) : Design.surface

                            Text {
                                anchors.centerIn: parent
                                text: "CPU"
                                font.family: Design.font.sans
                                font.weight: window.procSortBy === "cpu" ? Design.weight.bold : Design.weight.medium
                                font.pixelSize: Design.s(11)
                                color: window.procSortBy === "cpu" ? Design.accent : Design.textDim
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    window.procSortBy = "cpu";
                                    if (isNative) MonitorBackend.setProcessSort("cpu");
                                }
                            }
                        }

                        Rectangle {
                            implicitWidth: Design.s(54)
                            implicitHeight: Design.s(26)
                            radius: Design.s(8)
                            color: window.procSortBy === "mem" ? Design.tint(Design.accent, 0.25) : Design.surface

                            Text {
                                anchors.centerIn: parent
                                text: "RAM"
                                font.family: Design.font.sans
                                font.weight: window.procSortBy === "mem" ? Design.weight.bold : Design.weight.medium
                                font.pixelSize: Design.s(11)
                                color: window.procSortBy === "mem" ? Design.accent : Design.textDim
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    window.procSortBy = "mem";
                                    if (isNative) MonitorBackend.setProcessSort("mem");
                                }
                            }
                        }
                    }
                }
            }

            // Table Header
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: Design.s(30)
                color: Design.crust

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Design.s(Design.space.md)
                    anchors.rightMargin: Design.s(Design.space.md)
                    spacing: Design.s(Design.space.sm)

                    Text { text: "PID"; font.family: Design.font.mono; font.weight: Design.weight.bold; font.pixelSize: Design.s(10); color: Design.textDim; Layout.preferredWidth: Design.s(60) }
                    Text { text: "PROCESS NAME"; font.family: Design.font.sans; font.weight: Design.weight.bold; font.pixelSize: Design.s(10); color: Design.textDim; Layout.preferredWidth: Design.s(300) }
                    // The name column was the only one with fillWidth, so it
                    // took every spare pixel: on a 1280px window it ran 950px
                    // wide for names that need two hundred, and the numbers
                    // anyone actually reads sat crushed against the far edge
                    // with a void between. The slack carries the reading now.
                    Text { text: "LOAD"; font.family: Design.font.sans; font.weight: Design.weight.bold; font.pixelSize: Design.s(10); color: Design.textDim; Layout.fillWidth: true }
                    Text { text: "USER"; font.family: Design.font.sans; font.weight: Design.weight.bold; font.pixelSize: Design.s(10); color: Design.textDim; Layout.preferredWidth: Design.s(80) }
                    Text { text: "% CPU"; font.family: Design.font.mono; font.weight: Design.weight.bold; font.pixelSize: Design.s(10); color: Design.textDim; Layout.preferredWidth: Design.s(70); horizontalAlignment: Text.AlignRight }
                    Text { text: "% MEM"; font.family: Design.font.mono; font.weight: Design.weight.bold; font.pixelSize: Design.s(10); color: Design.textDim; Layout.preferredWidth: Design.s(70); horizontalAlignment: Text.AlignRight }
                    Text { text: "ACTIONS"; font.family: Design.font.sans; font.weight: Design.weight.bold; font.pixelSize: Design.s(10); color: Design.textDim; Layout.preferredWidth: Design.s(80); horizontalAlignment: Text.AlignHCenter }
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

                delegate: Rectangle {
                    width: procList.width
                    height: Design.s(36)
                    color: rowHover.containsMouse ? Design.tint(Design.text, 0.05) : (index % 2 === 0 ? "transparent" : Design.tint(Design.surface, 0.3))

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Design.s(Design.space.md)
                        anchors.rightMargin: Design.s(Design.space.md)
                        spacing: Design.s(Design.space.sm)

                        Text {
                            text: String(model.pid)
                            font.family: Design.font.mono
                            font.pixelSize: Design.s(11)
                            color: Design.textDim
                            Layout.preferredWidth: Design.s(60)
                        }

                        RowLayout {
                            // Explicitly false: Layout.fillWidth defaults to
                            // true for a nested layout and false for everything
                            // else, so this row went on taking the whole slack
                            // and Layout.preferredWidth alone did nothing — the
                            // bar beside it came out two pixels wide.
                            Layout.fillWidth: false
                            Layout.preferredWidth: Design.s(300)
                            spacing: Design.s(8)

                            Text {
                                text: "\u{f108}" // binary icon
                                font.family: Design.font.icon
                                color: Design.sapphire
                                font.pixelSize: Design.s(12)
                            }

                            Text {
                                text: model.name
                                font.family: Design.font.sans
                                font.weight: Design.weight.semibold
                                font.pixelSize: Design.s(12)
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
                            Layout.preferredHeight: Design.s(10)

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width
                                height: Design.s(6)
                                radius: height / 2
                                color: Design.tint(Design.text, 0.06)
                            }

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                // Clamped: a multi-core machine reports well
                                // over 100% for one process, and a bar wider
                                // than its track draws outside the column.
                                width: parent.width * Math.min(1, model.mem / 100)
                                height: Design.s(6)
                                radius: height / 2
                                color: "transparent"
                                border.color: Design.tint(Design.mauve, 0.55)
                                border.width: 1
                            }

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width * Math.min(1, model.cpu / 100)
                                height: Design.s(6)
                                radius: height / 2
                                color: model.cpu > 15.0 ? Design.pink
                                     : (model.cpu > 5.0 ? Design.peach : Design.tint(Design.sapphire, 0.75))
                            }
                        }

                        Text {
                            text: model.user
                            font.family: Design.font.sans
                            font.pixelSize: Design.s(11)
                            color: Design.textDim
                            Layout.preferredWidth: Design.s(80)
                        }

                        Text {
                            text: model.cpu.toFixed(1) + "%"
                            font.family: Design.font.mono
                            font.weight: model.cpu > 5.0 ? Design.weight.bold : Design.weight.regular
                            font.pixelSize: Design.s(11)
                            color: model.cpu > 15.0 ? Design.pink : (model.cpu > 5.0 ? Design.peach : Design.text)
                            Layout.preferredWidth: Design.s(70)
                            horizontalAlignment: Text.AlignRight
                        }

                        Text {
                            text: model.mem.toFixed(1) + "%"
                            font.family: Design.font.mono
                            font.pixelSize: Design.s(11)
                            color: Design.textDim
                            Layout.preferredWidth: Design.s(70)
                            horizontalAlignment: Text.AlignRight
                        }

                        // Kill Action Buttons
                        RowLayout {
                            Layout.preferredWidth: Design.s(80)
                            Layout.alignment: Qt.AlignHCenter
                            spacing: Design.s(4)

                            Rectangle {
                                width: Design.s(26)
                                height: Design.s(26)
                                radius: width / 2
                                color: killHover.containsMouse ? Design.tint(Design.pink, 0.25) : "transparent"

                                Text {
                                    anchors.centerIn: parent
                                    text: "\u{f00d}" // cross
                                    font.family: Design.font.icon
                                    color: killHover.containsMouse ? Design.pink : Design.textDim
                                    font.pixelSize: Design.s(11)
                                }

                                HoverHandler { id: killHover }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: if (isNative) MonitorBackend.killProcess(model.pid, false)
                                }
                            }

                            Rectangle {
                                width: Design.s(26)
                                height: Design.s(26)
                                radius: width / 2
                                color: forceHover.containsMouse ? Design.pink : "transparent"

                                Text {
                                    anchors.centerIn: parent
                                    text: "\u{f057}" // skull / force kill
                                    font.family: Design.font.icon
                                    color: forceHover.containsMouse ? Design.crust : Design.textDim
                                    font.pixelSize: Design.s(11)
                                }

                                HoverHandler { id: forceHover }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: if (isNative) MonitorBackend.killProcess(model.pid, true)
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
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: Design.s(28)
            color: Design.crust
            border.color: Design.glassBorder
            border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Design.s(Design.space.md)
                anchors.rightMargin: Design.s(Design.space.md)

                Text {
                    text: (isNative && MonitorBackend.processes ? MonitorBackend.processes.rowCount() : 0) + " Total Tasks  |  Load: " + window.loadAvgStr + "  |  Uptime: " + window.uptimeStr
                    font.family: Design.font.sans
                    font.pixelSize: Design.s(10)
                    color: Design.textDim
                    font.weight: Design.weight.medium
                    Layout.fillWidth: true
                }

                Text {
                    text: "Ctrl+1/2: Tabs  |  Ctrl+F: Search  |  F5: Refresh  |  Escape: Close"
                    font.family: Design.font.sans
                    font.pixelSize: Design.s(10)
                    color: Design.textDim
                    font.weight: Design.weight.medium
                }
            }
        }
    }
}
}
