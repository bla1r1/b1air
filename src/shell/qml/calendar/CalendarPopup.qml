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
    background: Design.tint(Design.ground, 0.94)
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
    ]

    readonly property var weekDayNames: ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]

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
    readonly property real contentWidth: {
        if (window.editing)
            return 0;
        let w = 0;
        if (window.calShown("calendar"))
            w += window.monthWidth;
        if (window.calShown("weather"))
            w += window.dashWidth;
        if (window.calShown("calendar") && window.calShown("weather"))
            w += Design.s(Design.space.md);
        return w > 0 ? w + 2 * Design.s(window.padding) : 0;
    }

    // The same trap as the width, one axis over: both cards are fillHeight
    // children of the row, so the row's implicitHeight is their *minimum* and a
    // window sized to it squeezed the month grid into a band of unreadable
    // glyphs. The inner columns are not fillHeight, so their implicit heights
    // are honest — the taller of the two, plus the card's own margins.
    readonly property real contentHeight: {
        if (window.editing)
            return 0;
        let h = 0;
        if (window.calShown("calendar"))
            h = Math.max(h, monthColumn.implicitHeight + 2 * Design.s(12));
        if (window.calShown("weather"))
            h = Math.max(h, dashColumn.implicitHeight + 2 * Design.s(14));
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

    /**
     * Steps a part through its sizes, and says which one it is on.
     *
     * A laid-out chip rather than an invisible tap area over the part: every
     * one of the calendar's parts *is* a layout, and an anchored child of a
     * layout is the thing Qt warns about and then positions wrong. It also
     * means the current size is written down instead of being something you
     * discover by clicking.
     */
    component SizeChip: Rectangle {
        id: chip
        property string widgetId: ""
        readonly property string size: window.calSize(chip.widgetId)

        visible: window.editing
        implicitWidth: Design.s(22)
        implicitHeight: Design.s(20)
        radius: Design.s(Design.radius.sm)
        color: chipMa.containsMouse ? Design.tint(Design.accent, 0.35)
                                    : Design.tint(Design.accent, 0.18)
        border.color: Design.tint(Design.accent, 0.45)
        border.width: 1

        Label {
            anchors.centerIn: parent
            text: chip.size === "small" ? "S" : (chip.size === "large" ? "L" : "M")
            role: "caption"
            weight: Design.weight.bold
            color: Design.accent
        }

        Clickable { id: chipMa; hoverEnabled: true; onClicked: window.cycleCalSize(chip.widgetId) }
    }

    // The badge that takes a part out or puts it back.
    component EditBadge: Rectangle {
        id: badge
        property string widgetId: ""
        readonly property bool off: Svc.Settings.isWidgetHidden(Svc.Settings.calHiddenCards,
                                                                badge.widgetId)
        visible: window.editing
        width: Design.s(20)
        height: Design.s(20)
        radius: width / 2
        z: 25
        color: badge.off ? Design.tint(Design.ok, 0.85) : Design.tint(Design.red, 0.85)

        Icon {
            anchors.centerIn: parent
            text: badge.off ? "\u{f0415}" : "\u{f0156}"
            role: "caption"
            color: Design.accentText
        }

        Clickable {
            onClicked: Svc.Settings.setWidgetHidden("calHiddenCards", badge.widgetId, !badge.off)
        }
    }

    RowLayout {
        id: row
        anchors.fill: parent
        spacing: Design.s(Design.space.md)

        // ═════════════════════════════════════════════════════════════════════
        // LEFT: CALENDAR CARD (310px)
        // ═════════════════════════════════════════════════════════════════════
        Rectangle {
            // Small, medium, large: a tighter month, the shipped one, or one
            // with room for the day numbers to breathe. The dashboard beside it
            // fills whatever is left, so this one number sets both.
            Layout.preferredWidth: window.monthWidth
            visible: window.editing || !Svc.Settings.isWidgetHidden(Svc.Settings.calHiddenCards, "calendar")
            opacity: Svc.Settings.isWidgetHidden(Svc.Settings.calHiddenCards, "calendar") ? 0.35 : 1.0
            Layout.fillHeight: true
            radius: Design.s(Design.radius.card)
            color: Design.glassCard
            border.color: Design.glassBorder
            border.width: 1

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
                        text: window.editing ? "Arrange" : (window.monthNames[window.viewMonth] + " " + window.viewYear)
                        weight: Design.weight.bold
                        role: "body"
                        color: window.editing ? Design.accent : Design.text
                        Layout.fillWidth: true
                    }

                    // Arranging happens here, in front of the panel being
                    // arranged. The month arrows step aside while it is on:
                    // paging the calendar is not what you came to do.
                    Rectangle {
                        width: Design.s(26); height: Design.s(26)
                        radius: Design.s(Design.radius.ctl)
                        color: editMa.containsMouse ? Design.glassHover : Design.surface
                        border.color: window.editing ? Design.accent : Design.line
                        border.width: 1

                        Icon {
                            anchors.centerIn: parent
                            text: window.editing ? "\u{f012c}" : "\u{f03eb}"
                            role: "caption"
                            color: window.editing ? Design.accent : Design.text
                        }
                        Clickable {
                            id: editMa
                            hoverEnabled: true
                            onClicked: window.editing = !window.editing
                        }
                    }

                    SizeChip { Layout.alignment: Qt.AlignVCenter; widgetId: "calendar" }

                    EditBadge { Layout.alignment: Qt.AlignVCenter; widgetId: "calendar" }

                    Rectangle {
                        visible: !window.editing
                        width: Design.s(26); height: Design.s(26)
                        radius: Design.s(Design.radius.ctl)
                        color: prevMa.containsMouse ? Design.glassHover : Design.surface
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
                        color: todayMa.containsMouse ? Design.glassHover : Design.surface
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
                        color: nextMa.containsMouse ? Design.glassHover : Design.surface
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
                    color: Design.sunken

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
                            text: Qt.formatDateTime(window.currentTime, "dddd, MMMM d, yyyy")
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
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: window.editing || !Svc.Settings.isWidgetHidden(Svc.Settings.calHiddenCards, "weather")
            opacity: Svc.Settings.isWidgetHidden(Svc.Settings.calHiddenCards, "weather") ? 0.35 : 1.0
            radius: Design.s(Design.radius.card)
            color: Design.glassCard
            border.color: Design.glassBorder
            border.width: 1

            EditBadge {
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: Design.s(Design.space.xs)
                widgetId: "weather"
            }

            ColumnLayout {
                id: dashColumn
                anchors.fill: parent
                anchors.margins: Design.s(14)
                spacing: Design.s(10)

                // ── Top Row: Clock & Current Weather Badge ───────────────────
                RowLayout {
                    id: clockRow
                    Layout.fillWidth: true
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
                            text: Qt.formatDateTime(window.currentTime, "dddd • d MMMM")
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
                        color: Design.sunken
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
                                              : (window.todayForecast ? (window.todayForecast.max + "°C") : "--°C")
                                        font.pixelSize: Design.s(20)
                                        font.family: Design.font.mono
                                        font.weight: Design.weight.bold
                                        color: Design.text
                                    }
                                    Label {
                                        text: window.todayForecast ? ("Feels " + window.todayForecast.feels_like + "°") : ""
                                        role: "caption"
                                        color: Design.textDim
                                    }
                                }
                                Label {
                                    text: window.todayForecast ? window.todayForecast.desc : "Fetching weather..."
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

                // Divider
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 1
                    color: Design.tint(Design.line, 0.4)
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
                GridLayout {
                    Layout.fillWidth: true
                    columns: window.calSize("metrics") === "large" ? 2 : 4
                    rowSpacing: Design.s(Design.space.xs)
                    columnSpacing: Design.s(Design.space.xs)
                    visible: window.editing || !Svc.Settings.isWidgetHidden(Svc.Settings.calHiddenCards, "metrics")
                    opacity: Svc.Settings.isWidgetHidden(Svc.Settings.calHiddenCards, "metrics") ? 0.35 : 1.0

                    // Laid out, not anchored: this row is a Layout child.
                    EditBadge {
                        Layout.alignment: Qt.AlignVCenter
                        widgetId: "metrics"
                    }

                    SizeChip { Layout.alignment: Qt.AlignVCenter; widgetId: "metrics" }

                    // Wind
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Design.s(window.calSize("metrics") === "small" ? 30
                                              : (window.calSize("metrics") === "large" ? 54 : 40))
                        radius: Design.s(Design.radius.ctl)
                        color: Design.sunken
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: Design.s(6)
                            spacing: Design.s(6)
                            Icon { text: "\u{f0590}"; role: "caption"; color: Design.teal }
                            ColumnLayout {
                                spacing: 0
                                Label { text: "Wind"; role: "caption"; color: Design.textDim; font.pixelSize: Design.s(10) }
                                Label { text: window.todayForecast ? (window.todayForecast.wind + " km/h") : "--"; role: "caption"; weight: Design.weight.bold; color: Design.text }
                            }
                        }
                    }

                    // Humidity
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Design.s(window.calSize("metrics") === "small" ? 30
                                              : (window.calSize("metrics") === "large" ? 54 : 40))
                        radius: Design.s(Design.radius.ctl)
                        color: Design.sunken
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: Design.s(6)
                            spacing: Design.s(6)
                            Icon { text: "\u{f043}"; role: "caption"; color: Design.sapphire }
                            ColumnLayout {
                                spacing: 0
                                Label { text: "Humidity"; role: "caption"; color: Design.textDim; font.pixelSize: Design.s(10) }
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
                        color: Design.sunken
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: Design.s(6)
                            spacing: Design.s(6)
                            Icon { text: "\u{f0597}"; role: "caption"; color: Design.blue }
                            ColumnLayout {
                                spacing: 0
                                Label { text: "Rain"; role: "caption"; color: Design.textDim; font.pixelSize: Design.s(10) }
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
                        color: Design.sunken
                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: Design.s(6)
                            spacing: Design.s(6)
                            Icon { text: "\u{f2c9}"; role: "caption"; color: Design.peach }
                            ColumnLayout {
                                spacing: 0
                                Label { text: "Range"; role: "caption"; color: Design.textDim; font.pixelSize: Design.s(10) }
                                Label { text: window.todayForecast ? (window.todayForecast.min + "° - " + window.todayForecast.max + "°") : "--"; role: "caption"; weight: Design.weight.bold; color: Design.text }
                            }
                        }
                    }
                }

                // ── 5-Day Forecast Row ───────────────────────────────────────
                RowLayout {
                    Layout.fillWidth: true
                    visible: window.editing || !Svc.Settings.isWidgetHidden(Svc.Settings.calHiddenCards, "forecast")
                    opacity: Svc.Settings.isWidgetHidden(Svc.Settings.calHiddenCards, "forecast") ? 0.35 : 1.0
                    spacing: Design.s(Design.space.xs)

                    // Laid out, not anchored: this row is a Layout child.
                    EditBadge {
                        Layout.alignment: Qt.AlignVCenter
                        widgetId: "forecast"
                    }

                    SizeChip { Layout.alignment: Qt.AlignVCenter; widgetId: "forecast" }

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
                            color: Design.sunken
                            border.color: Design.glassBorder; border.width: 1

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: Design.s(6)
                                spacing: Design.s(2)

                                Label {
                                    Layout.alignment: Qt.AlignHCenter
                                    text: modelData.day || ""
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
