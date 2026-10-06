import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtCore
import Quickshell
import Quickshell.Io
import "../Ui"
import "../Services"
// Aliased, and separately, because this file imports QtCore, which exports a
// `Settings` type of its own that shadows the singleton in Services. The
// shadowing is silent: the binding does not fail to compile, it throws
// "Property 'isWidgetHidden' of object QtCore/Settings is not a function" when
// it runs, and a `visible` binding that throws keeps its default — so every
// switched-off card in here stayed on screen and nothing said why until the
// shell's own log was read. The unaliased import stays for Weather and Design.
import "../Services" as Svc

// =============================================================================
// Calendar & Weather Dashboard — macOS-inspired Unified 2-Column Suite
// Perfectly proportioned 860x480 for desktop and compact displays.
// =============================================================================

PopupShell {
    id: window

    padding: Design.space.md
    background: Design.glassBg
    borderColor: Design.glassBorder
    cornerRadius: Design.radius.panel

    property var currentTime: new Date()

    // Calendar state
    property int currentYear: currentTime.getFullYear()
    property int currentMonth: currentTime.getMonth() // 0-indexed
    property int viewYear: currentYear
    property int viewMonth: currentMonth
    property int selectedDay: currentTime.getDate()

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: window.currentTime = new Date()
    }

    // The forecast comes from Services/Weather, which is the one thing in the
    // shell that fetches it. This window used to run its own
    // `b1air-daemon weather json` while the bar ran its own curl against
    // wttr.in — two fetches, two caches, two refresh schedules, and two
    // different temperatures on screen at the same moment.
    property var weatherData: Weather.forecast.length > 0 ? ({ forecast: Weather.forecast }) : null

    readonly property var monthNames: [
        "January", "February", "March", "April", "May", "June",
        "July", "August", "September", "October", "November", "December"
    ].map(m => I18n.tr(m))

    readonly property var weekDayNames: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"].map(d => I18n.tr(d))

    function prevMonth() {
        if (viewMonth === 0) {
            viewMonth = 11;
            viewYear--;
        } else {
            viewMonth--;
        }
    }

    function nextMonth() {
        if (viewMonth === 11) {
            viewMonth = 0;
            viewYear++;
        } else {
            viewMonth++;
        }
    }

    function resetToToday() {
        viewYear = currentYear;
        viewMonth = currentMonth;
        selectedDay = currentTime.getDate();
    }

    // Compute 42 calendar grid cells (6 rows x 7 days)
    readonly property var calendarGrid: {
        let cells = [];
        let firstDayIndex = (new Date(viewYear, viewMonth, 1).getDay() + 6) % 7;
        let daysInCurrentMonth = new Date(viewYear, viewMonth + 1, 0).getDate();
        let daysInPrevMonth = new Date(viewYear, viewMonth, 0).getDate();

        // Prev month padding
        for (let i = firstDayIndex - 1; i >= 0; i--) {
            cells.push({
                day: daysInPrevMonth - i,
                isCurrentMonth: false,
                isToday: false,
                year: viewMonth === 0 ? viewYear - 1 : viewYear,
                month: viewMonth === 0 ? 11 : viewMonth - 1
            });
        }

        // Current month days
        let todayDay = currentTime.getDate();
        let isCurrentMonthViewing = (viewYear === currentYear && viewMonth === currentMonth);
        for (let d = 1; d <= daysInCurrentMonth; d++) {
            cells.push({
                day: d,
                isCurrentMonth: true,
                isToday: isCurrentMonthViewing && (d === todayDay),
                year: viewYear,
                month: viewMonth
            });
        }

        // Next month padding to fill 42 cells (6 rows)
        let remaining = 42 - cells.length;
        for (let n = 1; n <= remaining; n++) {
            cells.push({
                day: n,
                isCurrentMonth: false,
                isToday: false,
                year: viewMonth === 11 ? viewYear + 1 : viewYear,
                month: viewMonth === 11 ? 0 : viewMonth + 1
            });
        }

        return cells;
    }

    // The forecast array is 5 days starting today (index 0 = today), so the
    // selected calendar day maps onto it by how many days out it is. Used to
    // just show forecast[0] no matter which day was clicked — clicking a
    // date changed nothing but which cell was highlighted.
    readonly property int selectedDayOffset: {
        const today = new Date(window.currentYear, window.currentMonth, window.currentTime.getDate());
        const sel = new Date(window.viewYear, window.viewMonth, window.selectedDay);
        return Math.round((sel - today) / 86400000);
    }

    readonly property var todayForecast: (window.weatherData && window.weatherData.forecast
        && window.selectedDayOffset >= 0 && window.selectedDayOffset < window.weatherData.forecast.length)
        ? window.weatherData.forecast[window.selectedDayOffset] : null

    // Off by default and never saved: a mode you are in for a few seconds.
    property bool editing: false

    readonly property var calIds: ["calendar", "weather", "metrics", "forecast"]

    // Both dimensions, because this panel is two cards side by side: take the
    // month away and the width left over is dead panel, not a narrower one.
    // Zero while arranging — every part is on screen then, including the ones
    // switched off, and a window resizing under the badge you are aiming at is
    // a window that moves the target.
    function calShown(id) {
        return !Svc.Settings.isWidgetHidden(Svc.Settings.calHiddenCards, id);
    }

    // The dashboard card is there while any of its three parts is. It went
    // with "weather" alone, so hiding the clock also took the pills and the
    // forecast with it while their switches still said they were on.
    readonly property bool dashShown: window.calShown("weather") || window.calShown("metrics")
                                      || window.calShown("forecast")

    readonly property int shownCount: window.calIds.filter(id => window.calShown(id)).length

    // ── Arranging ────────────────────────────────────────────────────────────
    //
    // The order lives in calCardLayout, which has always been an ordered list
    // and was only ever read for sizes. Two things can move: the month and the
    // dashboard swap sides, and the dashboard's three rows — clock, pills,
    // forecast — swap with each other.
    readonly property var calOrder: Svc.Settings.tileArrangement(Svc.Settings.calCardLayout, window.calIds, "medium").order
    readonly property var dashIds: ["weather", "metrics", "forecast"]
    readonly property bool monthFirst: {
        const o = window.calOrder;
        const c = o.indexOf("calendar");
        return window.dashIds.every(id => c < o.indexOf(id));
    }
    function dashRow(id) {
        return window.calOrder.filter(x => window.dashIds.indexOf(x) >= 0).indexOf(id);
    }

    property string dragOver: ""

    function partAt(fromId, scenePos) {
        const parts = { "calendar": monthCard, "weather": weatherPart, "metrics": metricsPart, "forecast": forecastPart };
        const hit = it => {
            if (!it || !it.visible) return false;
            const l = it.mapFromItem(null, scenePos);
            return l.x >= 0 && l.y >= 0 && l.x <= it.width && l.y <= it.height;
        };
        // The month dragged anywhere over the dashboard means "swap sides".
        if (fromId === "calendar")
            return hit(dashCard) ? "dash" : "";
        for (const id of window.dashIds)
            if (id !== fromId && hit(parts[id]))
                return id;
        return hit(monthCard) ? "calendar" : "";
    }

    function dropPart(fromId, scenePos) {
        const to = window.partAt(fromId, scenePos);
        if (to === "")
            return;
        const arr = Svc.Settings.tileArrangement(Svc.Settings.calCardLayout, window.calIds, "medium");
        if (to === "dash" || to === "calendar") {
            // Sides: the month goes to the other end of the list.
            const rest = arr.order.filter(x => x !== "calendar");
            arr.order = window.monthFirst ? rest.concat("calendar") : ["calendar"].concat(rest);
        } else {
            const a = arr.order.indexOf(fromId);
            const b = arr.order.indexOf(to);
            arr.order[a] = to;
            arr.order[b] = fromId;
        }
        Svc.Settings.setTileArrangement("calCardLayout", arr.order, arr.spans);
    }

    readonly property var partTitles: ({
        "calendar": ["Month", "\u{f00ed}"], "weather": ["Clock & Weather", "\u{f0590}"],
        "metrics": ["Weather Details", "\u{f059d}"], "forecast": ["Forecast", "\u{f0595}"]
    })
    readonly property var trayItems: window.calIds.filter(id => !window.calShown(id))
        .map(id => ({ id: id, title: I18n.tr(window.partTitles[id][0]), icon: window.partTitles[id][1] }))

    readonly property real monthWidth: Design.s(window.calSize("calendar") === "small" ? 260
                                      : (window.calSize("calendar") === "large" ? 390 : 310))

    // How wide the dashboard wants to be, from what is left in it: the clock
    // and its badge need far less than four metric pills and a week of days.
    // With the pills and the days gone the dashboard is a clock and a badge, and
    // how wide that is depends on the words in it — "Feels 18°", "Partly
    // cloudy". A number picked to fit today's weather clips tomorrow's, so it
    // is measured: the row is not a fillWidth child of anything that would make
    // its implicit width a minimum.
    readonly property real dashWidth: (window.calShown("metrics") || window.calShown("forecast"))
        ? Design.s(520)
        : Math.max(Design.s(320), clockRow.implicitWidth + 2 * Design.s(14))

    // Added up from the parts, not read off the layout.
    //
    // The obvious version — the RowLayout's own implicitWidth — is circular:
    // the dashboard is a fillWidth child, so its implicit width is its
    // *minimum*, and a window sized to that squeezes the dashboard, which
    // lowers the minimum again. Hiding the month collapsed the panel to the
    // clock alone and squeezed the weather badge out of existence.
    // Worked out while arranging as well now. It used to drop to zero, which
    // meant the registry's fixed 860x480 — a different window from the one
    // being arranged. Removed parts are in the tray instead of ghosted in
    // place, so the panel no longer needs room for things that are not there.
    readonly property real contentWidth: {
        let w = 0;
        if (window.calShown("calendar"))
            w += window.monthWidth;
        if (window.dashShown)
            w += window.dashWidth;
        if (window.calShown("calendar") && window.dashShown)
            w += Design.s(Design.space.md);
        return w > 0 ? w + 2 * Design.s(window.padding) : 0;
    }

    // The same trap as the width, one axis over: both cards are fillHeight
    // children of the row, so the row's implicitHeight is their *minimum* and a
    // window sized to it squeezed the month grid into a band of unreadable
    // glyphs. The inner columns are not fillHeight, so their implicit heights
    // are honest — the taller of the two, plus the card's own margins.
    readonly property real contentHeight: {
        let h = 0;
        if (window.calShown("calendar"))
            h = Math.max(h, monthColumn.implicitHeight + 2 * Design.s(12));
        if (window.dashShown)
            h = Math.max(h, dashColumn.implicitHeight + 2 * Design.s(14));
        if (window.editing)
            h += partTray.implicitHeight + Design.s(Design.space.md);
        return h > 0 ? h + 2 * Design.s(window.padding) : 0;
    }

    /**
     * The size of one part, as a name.
     *
     * Three sizes that each mean something different here, because the parts
     * are not interchangeable cells: on the month it is how wide the grid is,
     * on the metric pills how tall they stand, on the forecast how many days
     * there is room for, and on the dashboard how large the clock reads. A
     * single "scale" would have been one mechanism pretending to be four.
     */
    function calSize(id) {
        return Svc.Settings.tileSizeName(
            Svc.Settings.tileArrangement(Svc.Settings.calCardLayout, window.calIds, "medium").spans[id]);
    }

    function cycleCalSize(id) {
        const arr = Svc.Settings.tileArrangement(Svc.Settings.calCardLayout, window.calIds, "medium");
        const now = Svc.Settings.tileSizeName(arr.spans[id]);
        arr.spans[id] = now === "small" ? "medium" : (now === "medium" ? "large" : "small");
        Svc.Settings.setTileArrangement("calCardLayout", arr.order, arr.spans);
    }

    // The frame each part wears while arranging (Ui/EditFrame): drag to move,
    // S/M/L, remove. The size chip and the remove badge used to be laid out
    // *inside* each part as extra cells, so arrange mode reshaped the thing
    // being arranged — the four weather pills were pushed into the last two
    // columns of their own grid.
    component PartFrame: EditFrame {
        property string partId: ""
        readonly property string size: window.calSize(partId)
        active: window.editing
        sizeLabel: size === "small" ? "S" : (size === "large" ? "L" : "M")
        // The last part cannot go: an empty panel has no header left to
        // switch arrange mode on from.
        removable: window.shownCount > 1
        dropTarget: window.dragOver !== "" && (window.dragOver === partId
                                                || (window.dragOver === "dash" && partId === "weather"))
        onRemove: Svc.Settings.setWidgetHidden("calHiddenCards", partId, true)
        onCycleSize: window.cycleCalSize(partId)
        onDragMoved: p => window.dragOver = window.partAt(partId, p)
        onDropped: p => {
            window.dropPart(partId, p);
            window.dragOver = "";
        }
    }

    // Arrange on / off. It lived only in the month's header, so hiding the
    // month hid the one way back into arrange mode — and with it every way
    // to put anything back.
    component EditToggle: Rectangle {
        width: Design.s(26); height: Design.s(26)
        radius: Design.s(Design.radius.ctl)
        color: toggleMa.containsMouse ? Design.glassHover : Design.glassCard
        border.color: window.editing ? Design.accent : Design.line
        border.width: 1

        Icon {
            anchors.centerIn: parent
            text: window.editing ? "\u{f012c}" : "\u{f03eb}"
            role: "caption"
            color: window.editing ? Design.accent : Design.text
        }
        Clickable {
            id: toggleMa
            hoverEnabled: true
            onClicked: window.editing = !window.editing
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Design.s(Design.space.md)

    // One row, two cells; a GridLayout so each card can be told its column.
    GridLayout {
        id: row
        Layout.fillWidth: true
        Layout.fillHeight: true
        rows: 1
        columnSpacing: Design.s(Design.space.md)

        // ═════════════════════════════════════════════════════════════════════
        // LEFT: CALENDAR CARD (310px)
        // ═════════════════════════════════════════════════════════════════════
        Rectangle {
            // Small, medium, large: a tighter month, the shipped one, or one
            // with room for the day numbers to breathe. The dashboard beside it
            // fills whatever is left, so this one number sets both.
            id: monthCard
            Layout.preferredWidth: window.monthWidth
            Layout.column: window.monthFirst ? 0 : 1
            visible: window.calShown("calendar")
            Layout.fillHeight: true
            radius: Design.s(Design.radius.card)
            color: Design.glassCard
            border.color: Design.glassBorder
            border.width: 1

            PartFrame {
                anchors.fill: parent
                partId: "calendar"
            }

            // Arranging starts here, in front of the panel being arranged.
            // The month arrows step aside while it is on: paging the calendar
            // is not what you came to do.
            EditToggle {
                id: monthToggle
                z: 40
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: Design.s(12)
            }

            ColumnLayout {
                id: monthColumn
                anchors.fill: parent
                anchors.margins: Design.s(12)
                spacing: Design.s(8)

                // Month / Year Navigation Header
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Design.s(4)

                    Label {
                        text: window.editing ? I18n.tr("Arrange") : (window.monthNames[window.viewMonth] + " " + window.viewYear)
                        weight: Design.weight.bold
                        role: "body"
                        color: window.editing ? Design.accent : Design.text
                        Layout.fillWidth: true
                    }


                    Rectangle {
                        visible: !window.editing
                        width: Design.s(26); height: Design.s(26)
                        radius: Design.s(Design.radius.ctl)
                        color: prevMa.containsMouse ? Design.glassHover : Design.glassCard
                        border.color: Design.line; border.width: 1

                        Icon {
                            anchors.centerIn: parent
                            text: "\u{f053}"
                            role: "caption"
                            color: Design.text
                        }
                        Clickable {
                            id: prevMa
                            hoverEnabled: true
                            onClicked: window.prevMonth()
                        }
                    }

                    Rectangle {
                        visible: !window.editing
                        width: Design.s(26); height: Design.s(26)
                        radius: Design.s(Design.radius.ctl)
                        color: todayMa.containsMouse ? Design.glassHover : Design.glassCard
                        border.color: Design.line; border.width: 1

                        Icon {
                            anchors.centerIn: parent
                            text: "\u{f017}"
                            role: "caption"
                            color: Design.accent
                        }
                        Clickable {
                            id: todayMa
                            hoverEnabled: true
                            onClicked: window.resetToToday()
                        }
                    }

                    Rectangle {
                        visible: !window.editing
                        width: Design.s(26); height: Design.s(26)
                        radius: Design.s(Design.radius.ctl)
                        color: nextMa.containsMouse ? Design.glassHover : Design.glassCard
                        border.color: Design.line; border.width: 1

                        Icon {
                            anchors.centerIn: parent
                            text: "\u{f054}"
                            role: "caption"
                            color: Design.text
                        }
                        Clickable {
                            id: nextMa
                            hoverEnabled: true
                            onClicked: window.nextMonth()
                        }
                    }

                    // Room for the arrange toggle, which is not in this row:
                    // it is a child of the card so that it can sit above the
                    // arrange frame and stay clickable (see monthToggle).
                    Item { width: Design.s(26); height: Design.s(26) }
                }

                // Days of week header (Mo Tu We Th Fr Sa Su)
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    Repeater {
                        model: window.weekDayNames
                        Label {
                            Layout.fillWidth: true
                            text: modelData
                            horizontalAlignment: Text.AlignHCenter
                            role: "caption"
                            weight: Design.weight.bold
                            color: (index >= 5) ? Design.accent : Design.textDim
                        }
                    }
                }

                // 7x6 Calendar Cells Grid
                GridLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    columns: 7
                    rowSpacing: Design.s(2)
                    columnSpacing: Design.s(2)

                    Repeater {
                        model: window.calendarGrid

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            // A floor for the row. The cells asked for no
                            // height at all, so the month was only as tall as
                            // the dashboard beside it made the window: take
                            // the forecast away and six weeks were squeezed
                            // into a band where the numbers overlapped.
                            Layout.minimumHeight: Design.s(window.calSize("calendar") === "small" ? 24
                                                  : (window.calSize("calendar") === "large" ? 36 : 28))
                            radius: Design.s(Design.radius.ctl)

                            readonly property bool isSel: modelData.isCurrentMonth && (modelData.day === window.selectedDay)
                            readonly property bool isTod: modelData.isToday

                            color: isTod ? Design.accent : (isSel ? Design.tint(Design.accent, 0.2) : (cellMa.containsMouse ? Design.glassHover : "transparent"))
                            border.color: isSel && !isTod ? Design.accent : "transparent"
                            border.width: 1

                            Label {
                                anchors.centerIn: parent
                                text: modelData.day.toString()
                                role: "caption"
                                weight: (isTod || isSel) ? Design.weight.bold : Design.weight.regular
                                isMono: true
                                color: isTod ? Design.surface : (modelData.isCurrentMonth ? Design.text : Design.textDim)
                                opacity: modelData.isCurrentMonth ? 1.0 : 0.35
                            }

                            Clickable {
                                id: cellMa
                                hoverEnabled: true
                                onClicked: {
                                    if (modelData.isCurrentMonth) {
                                        window.selectedDay = modelData.day;
                                    } else {
                                        window.viewYear = modelData.year;
                                        window.viewMonth = modelData.month;
                                        window.selectedDay = modelData.day;
                                    }
                                }
                            }
                        }
                    }
                }

                // Bottom Date Stamp
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Design.s(28)
                    radius: Design.s(Design.radius.ctl)
                    color: Design.well

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Design.s(8)
                        anchors.rightMargin: Design.s(8)
                        spacing: Design.s(Design.space.xs)

                        Icon {
                            text: "\u{f073}"
                            role: "caption"
                            color: Design.accent
                        }

                        Label {
                            text: I18n.date(window.currentTime, "dddd, MMMM d, yyyy")
                            role: "caption"
                            weight: Design.weight.medium
                            color: Design.textDim
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }

        // ═════════════════════════════════════════════════════════════════════
        // RIGHT: WEATHER & TIME DASHBOARD (Fill remaining width)
        // ═════════════════════════════════════════════════════════════════════
        Rectangle {
            id: dashCard
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.column: window.monthFirst ? 1 : 0
            visible: window.dashShown
            radius: Design.s(Design.radius.card)
            color: Design.glassCard
            border.color: Design.glassBorder
            border.width: 1

            // The arrange toggle's second home, for when the month is hidden.
            EditToggle {
                z: 40
                visible: !window.calShown("calendar")
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                anchors.margins: Design.s(10)
            }

            // Three rows in the saved order. A one-column GridLayout because a
            // grid takes an explicit row per child.
            GridLayout {
                id: dashColumn
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Design.s(14)
                columns: 1
                // Wider while arranging, for the toolbars on each row's edge.
                rowSpacing: Design.s(window.editing ? 20 : 10)

                // ── Clock & Current Weather Badge ────────────────────────────
                Item {
                    id: weatherPart
                    Layout.fillWidth: true
                    Layout.row: window.dashRow("weather")
                    visible: window.calShown("weather")
                    implicitHeight: clockRow.implicitHeight

                    PartFrame {
                        anchors.fill: parent
                        anchors.margins: -Design.s(6)
                        partId: "weather"
                    }

                RowLayout {
                    id: clockRow
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    spacing: Design.s(Design.space.md)

                    // Big Clean Clock
                    ColumnLayout {
                        spacing: 0
                        Label {
                            text: Qt.formatTime(window.currentTime, "HH:mm")
                            font.pixelSize: Design.s(48)
                            font.family: Design.font.mono
                            font.weight: Design.weight.bold
                            color: Design.text
                        }
                        Label {
                            text: I18n.date(window.currentTime, "dddd • d MMMM")
                            role: "caption"
                            weight: Design.weight.semibold
                            color: Design.accent
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // Weather Hero Card
                    Rectangle {
                        Layout.preferredWidth: Design.s(240)
                        Layout.preferredHeight: Design.s(68)
                        radius: Design.s(Design.radius.ctl)
                        color: Design.well
                        border.color: Design.glassBorder; border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: Design.s(8)
                            spacing: Design.s(10)

                            // Weather Icon
                            Rectangle {
                                width: Design.s(44); height: Design.s(44)
                                radius: Design.s(10)
                                color: Design.glassCard

                                Icon {
                                    anchors.centerIn: parent
                                    text: window.todayForecast ? (window.todayForecast.icon || "\u{f0c2}") : "\u{f0c2}"
                                    font.pixelSize: Design.s(24)
                                    color: window.todayForecast ? (window.todayForecast.hex || Design.accent) : Design.accent
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                RowLayout {
                                    spacing: Design.s(Design.space.xs)
                                    // The temperature now, not today's high.
                                    //
                                    // This read `todayForecast.max` and set it
                                    // in 20px bold beside the clock, where it
                                    // is plainly meant as the current reading.
                                    // So the panel said 21°C while the bar,
                                    // fetching separately, said +18°C — two
                                    // numbers for the same thing, both on
                                    // screen at once. The daily range is still
                                    // shown below, under "Range", which is
                                    // where a high belongs.
                                    Label {
                                        text: window.selectedDayOffset === 0 && Weather.loaded
                                              ? Weather.temp
                                              : (window.todayForecast ? (window.todayForecast.max + "°" + Weather.unit) : "--°")
                                        font.pixelSize: Design.s(20)
                                        font.family: Design.font.mono
                                        font.weight: Design.weight.bold
                                        color: Design.text
                                    }
                                    Label {
                                        text: window.todayForecast ? I18n.tr("Feels %1°", window.todayForecast.feels_like) : ""
                                        role: "caption"
                                        color: Design.textDim
                                    }
                                }
                                Label {
                                    text: window.todayForecast ? I18n.tr(window.todayForecast.desc) : I18n.tr("Fetching weather...")
                                    role: "caption"
                                    weight: Design.weight.semibold
                                    color: Design.text
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }
                            }
                        }
                    }
                }
                }

                // ── Weather Metrics Pills ────────────────────────────────────
                //
                // The size changes what is here, not how big it is drawn —
                // which is the point of having three of them, and how the same
                // widget behaves at three sizes on the two desktops this is
                // measured against. Small keeps the two that answer "what is it
                // like outside" and drops the rest; medium is all four in a
                // row; large is all four two by two, with room for the numbers
                // to be read across the room.
                Item {
                    id: metricsPart
                    Layout.fillWidth: true
                    Layout.row: window.dashRow("metrics")
                    visible: window.calShown("metrics")
                    implicitHeight: metricsGrid.implicitHeight

                    PartFrame {
                        anchors.fill: parent
                        anchors.margins: -Design.s(6)
                        partId: "metrics"
                    }

                GridLayout {
                    id: metricsGrid
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    columns: window.calSize("metrics") === "large" ? 2 : 4
                    rowSpacing: Design.s(Design.space.xs)
                    columnSpacing: Design.s(Design.space.xs)

                    // Wind
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Design.s(window.calSize("metrics") === "small" ? 30
                                              : (window.calSize("metrics") === "large" ? 54 : 40))
                        radius: Design.s(Design.radius.ctl)
                        color: Design.well
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: Design.s(6)
                            spacing: Design.s(6)
                            Icon { text: "\u{f0590}"; role: "caption"; color: Design.teal }
                            ColumnLayout {
                                spacing: 0
                                Label { text: I18n.tr("Wind"); role: "caption"; color: Design.textDim; font.pixelSize: Design.s(10) }
                                Label { text: window.todayForecast ? (window.todayForecast.wind + (Weather.unit === "F" ? " " + I18n.tr("mph") : " " + I18n.tr("km/h"))) : "--"; role: "caption"; weight: Design.weight.bold; color: Design.text }
                            }
                        }
                    }

                    // Humidity
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Design.s(window.calSize("metrics") === "small" ? 30
                                              : (window.calSize("metrics") === "large" ? 54 : 40))
                        radius: Design.s(Design.radius.ctl)
                        color: Design.well
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: Design.s(6)
                            spacing: Design.s(6)
                            Icon { text: "\u{f043}"; role: "caption"; color: Design.sapphire }
                            ColumnLayout {
                                spacing: 0
                                Label { text: I18n.tr("Humidity"); role: "caption"; color: Design.textDim; font.pixelSize: Design.s(10) }
                                Label { text: window.todayForecast ? (window.todayForecast.humidity + "%") : "--"; role: "caption"; weight: Design.weight.bold; color: Design.text }
                            }
                        }
                    }

                    // Rain / Precip
                    Rectangle {
                        Layout.fillWidth: true
                        visible: window.calSize("metrics") !== "small"
                        Layout.preferredHeight: Design.s(window.calSize("metrics") === "small" ? 30
                                              : (window.calSize("metrics") === "large" ? 54 : 40))
                        radius: Design.s(Design.radius.ctl)
                        color: Design.well
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: Design.s(6)
                            spacing: Design.s(6)
                            Icon { text: "\u{f0597}"; role: "caption"; color: Design.blue }
                            ColumnLayout {
                                spacing: 0
                                Label { text: I18n.tr("Rain"); role: "caption"; color: Design.textDim; font.pixelSize: Design.s(10) }
                                Label { text: (window.todayForecast && window.todayForecast.rain_chance !== undefined) ? (window.todayForecast.rain_chance + "%") : "0%"; role: "caption"; weight: Design.weight.bold; color: Design.text }
                            }
                        }
                    }

                    // Range Min/Max
                    Rectangle {
                        Layout.fillWidth: true
                        visible: window.calSize("metrics") !== "small"
                        Layout.preferredHeight: Design.s(window.calSize("metrics") === "small" ? 30
                                              : (window.calSize("metrics") === "large" ? 54 : 40))
                        radius: Design.s(Design.radius.ctl)
                        color: Design.well
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: Design.s(6)
                            spacing: Design.s(6)
                            Icon { text: "\u{f2c9}"; role: "caption"; color: Design.peach }
                            ColumnLayout {
                                spacing: 0
                                Label { text: I18n.tr("Range"); role: "caption"; color: Design.textDim; font.pixelSize: Design.s(10) }
                                Label { text: window.todayForecast ? (window.todayForecast.min + "° - " + window.todayForecast.max + "°") : "--"; role: "caption"; weight: Design.weight.bold; color: Design.text }
                            }
                        }
                    }
                }
                }

                // ── 5-Day Forecast Row ───────────────────────────────────────
                Item {
                    id: forecastPart
                    Layout.fillWidth: true
                    Layout.row: window.dashRow("forecast")
                    visible: window.calShown("forecast")
                    implicitHeight: forecastRow.implicitHeight

                    PartFrame {
                        anchors.fill: parent
                        anchors.margins: -Design.s(6)
                        partId: "forecast"
                    }

                RowLayout {
                    id: forecastRow
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    spacing: Design.s(Design.space.xs)

                    Repeater {
                        // Three days, five, or as many as the reply carries.
                        model: (window.weatherData && window.weatherData.forecast)
                            ? window.weatherData.forecast.slice(0, window.calSize("forecast") === "small" ? 3
                                                              : (window.calSize("forecast") === "large" ? 7 : 5))
                            : []

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: Design.s(68)
                            radius: Design.s(Design.radius.ctl)
                            color: Design.well
                            border.color: Design.glassBorder; border.width: 1

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: Design.s(6)
                                spacing: Design.s(2)

                                Label {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: I18n.tr(modelData.day || "")
                                    role: "caption"
                                    weight: Design.weight.bold
                                    color: (index === 0) ? Design.accent : Design.text
                                }

                                Icon {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: modelData.icon || "\u{f0c2}"
                                    role: "caption"
                                    color: modelData.hex || Design.accent
                                }

                                Label {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: (modelData.min || "-") + "° / " + (modelData.max || "-") + "°"
                                    role: "caption"
                                    font.pixelSize: Design.s(10)
                                    color: Design.textDim
                                    isMono: true
                                }
                            }
                        }
                    }
                }
                }
            }
        }
    }

    // Everything taken out of the panel, to put back.
    WidgetTray {
        id: partTray
        Layout.fillWidth: true
        active: window.editing
        items: window.trayItems
        onAdd: id => Svc.Settings.setWidgetHidden("calHiddenCards", id, false)
    }
    }
}
