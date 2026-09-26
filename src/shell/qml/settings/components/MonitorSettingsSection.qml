import QtQuick
import QtQuick.Layouts
import Quickshell
import B1air.Daemon
import Quickshell.Io
import "../../Ui"
import "../../Services"

// =============================================================================
// Displays — MonitorPopup's working parts, arranged the way everyone already
// knows from Windows.
//
// Kept from the popup: the drag-and-snap canvas, the resolution cards, the
// detented refresh-rate slider, and the Apply that closes sub-pixel gaps
// between neighbours and re-anchors the layout at 0,0 (sway will not place an
// output at a negative coordinate).
//
// Rearranged: screens on top, click one to work on it, that screen's settings
// underneath. The popup's side-by-side split and its Brightness tab are gone —
// brightness lives on the bar next to the backlight slider, not on a settings
// page you have to go looking for.
// =============================================================================

ColumnLayout {
    id: section

    Layout.fillWidth: true
    spacing: Design.s(Design.space.lg)

    // Virtual mapping: 1920 physical px -> 192 canvas units.
    readonly property real uiScale: 0.10

    property int activeEditIndex: 0
    property bool dirty: false

    property color selectedResAccent: Design.accentAlt
    property color selectedRateAccent: Design.accent

    ListModel { id: monitorsModel }

    readonly property var activeMonitor: (monitorsModel.count > 0
        && section.activeEditIndex < monitorsModel.count)
        ? monitorsModel.get(section.activeEditIndex) : null

    // Plain, unambiguously-reactive mirror of the active row's scale. The
    // Scale stepper used to read straight off ListModel.get(index).sysScale
    // (via `activeMonitor` and then directly) and never once visibly moved
    // on click — the model row was updating, but nothing was actually
    // re-evaluating the display from it. Driving the label off a real QML
    // property instead of ListModel/get() indirection sidesteps that
    // entirely, whatever its exact cause.
    property real currentSysScale: 1.0
    function setSysScale(v) {
        const clamped = Math.max(0.5, Math.min(3.0, Math.round(v * 100) / 100));
        section.currentSysScale = clamped;
        if (section.activeMonitor) monitorsModel.setProperty(section.activeEditIndex, "sysScale", clamped);
        section.markDirty();
    }

    // ── Service plumbing ─────────────────────────────────────────────────────
    property bool _held: false
    function _hold(on) {
        if (on === section._held)
            return;
        section._held = on;
        if (on) Monitors.acquire();
        else Monitors.release();
    }

    Component.onCompleted: {
        profileReader.running = true;
        section._hold(visible);
        section.reload();
    }
    onVisibleChanged: section._hold(visible)
    Component.onDestruction: section._hold(false)

    Connections {
        target: Monitors
        function onOutputsChanged() {
            // Never overwrite an edit in progress — that is how you lose the
            // arrangement you just dragged.
            if (!section.dirty)
                section.reload();
        }
    }

    function reload() {
        const list = Monitors.outputs;
        monitorsModel.clear();

        let minX = 999999, minY = 999999;
        for (const o of list) {
            minX = Math.min(minX, o.x);
            minY = Math.min(minY, o.y);
        }
        if (list.length === 0) { minX = 0; minY = 0; }

        for (let i = 0; i < list.length; i++) {
            const o = list[i];
            monitorsModel.append({
                name: o.name,
                make: o.make,
                model: o.model,
                resW: o.resW,
                resH: o.resH,
                sysScale: o.sysScale,
                rate: String(o.rate),
                uiX: (o.x - minX) * section.uiScale,
                uiY: (o.y - minY) * section.uiScale
            });
            if (o.focused)
                section.activeEditIndex = i;
        }
        if (section.activeEditIndex >= monitorsModel.count)
            section.activeEditIndex = 0;
        section.dirty = false;
        section.currentSysScale = monitorsModel.count > 0
            ? monitorsModel.get(section.activeEditIndex).sysScale : 1.0;
    }

    onActiveEditIndexChanged: {
        if (monitorsModel.count > 0 && section.activeEditIndex < monitorsModel.count)
            section.currentSysScale = monitorsModel.get(section.activeEditIndex).sysScale;
    }

    function markDirty() { section.dirty = true; }

    // ── Layout maths, carried over from the popup ────────────────────────────
    function isOverlapping(ax, ay, aw, ah, bx, by, bw, bh) {
        return ax < bx + bw && ax + aw > bx && ay < by + bh && ay + ah > by;
    }

    function isOverlappingAny(x, y, w, h, skipIdx) {
        for (let i = 0; i < monitorsModel.count; i++) {
            if (i === skipIdx) continue;
            const m = monitorsModel.get(i);
            const mw = (m.resW / m.sysScale) * section.uiScale;
            const mh = (m.resH / m.sysScale) * section.uiScale;
            if (section.isOverlapping(x, y, w, h, m.uiX, m.uiY, mw, mh))
                return true;
        }
        return false;
    }

    // Snap a dragged screen onto the perimeter of another one: edge to edge, or
    // centre lines aligned.
    function getPerimeterSnap(pX, pY, sX, sY, sW, sH, mW, mH, snapT) {
        let cx = pX, cy = pY;

        if (Math.abs(cx - (sX - mW)) < snapT) cx = sX - mW;
        else if (Math.abs(cx - (sX + sW)) < snapT) cx = sX + sW;
        else if (Math.abs(cx - sX) < snapT) cx = sX;
        else if (Math.abs(cx - (sX + sW - mW)) < snapT) cx = sX + sW - mW;
        else if (Math.abs(cx - (sX + sW / 2 - mW / 2)) < snapT) cx = sX + sW / 2 - mW / 2;

        if (Math.abs(cy - (sY - mH)) < snapT) cy = sY - mH;
        else if (Math.abs(cy - (sY + sH)) < snapT) cy = sY + sH;
        else if (Math.abs(cy - sY) < snapT) cy = sY;
        else if (Math.abs(cy - (sY + sH - mH)) < snapT) cy = sY + sH - mH;
        else if (Math.abs(cy - (sY + sH / 2 - mH / 2)) < snapT) cy = sY + sH / 2 - mH / 2;

        return { x: cx, y: cy };
    }

    // =========================================================================
    // 1. THE SCREENS
    // =========================================================================
    Card {
        title: "Displays"
        subtitle: monitorsModel.count > 1
            ? "Select a screen to change its settings. Drag it to rearrange."
            : "Select a screen to change its settings."
        icon: "\u{f0379}"
        accentColor: section.selectedResAccent

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Design.s(260)
            radius: Design.s(Design.radius.card)
            color: Design.sunken
            border.color: Design.tint(Design.line, 0.5)
            border.width: Design.border
            clip: true

            Grid {
                anchors.centerIn: parent
                rows: 25
                columns: 40
                spacing: Design.s(18)
                Repeater {
                    model: 1000
                    Rectangle { width: Design.s(2); height: Design.s(2); radius: Design.s(1); color: Design.tint(Design.text, 0.08) }
                }
            }

            Item {
                id: canvas
                anchors.fill: parent

                // Fit whatever the arrangement spans into the canvas, one screen
                // or five.
                readonly property real spanScale: {
                    if (monitorsModel.count === 0) return 1.0;
                    let minX = 999999, minY = 999999, maxX = -999999, maxY = -999999;

                    for (let i = 0; i < monitorsModel.count; i++) {
                        const m = monitorsModel.get(i);
                        const w = (m.resW / m.sysScale) * section.uiScale;
                        const h = (m.resH / m.sysScale) * section.uiScale;
                        minX = Math.min(minX, m.uiX);
                        minY = Math.min(minY, m.uiY);
                        maxX = Math.max(maxX, m.uiX + w);
                        maxY = Math.max(maxY, m.uiY + h);
                    }

                    const requiredW = (maxX - minX) + 60;
                    const requiredH = (maxY - minY) + 60;
                    return Math.min(2.2, Math.min(canvas.width / requiredW, canvas.height / requiredH));
                }

                readonly property real offsetX: {
                    if (monitorsModel.count === 0) return 0;
                    let minX = 999999, maxX = -999999;
                    for (let i = 0; i < monitorsModel.count; i++) {
                        const m = monitorsModel.get(i);
                        const w = (m.resW / m.sysScale) * section.uiScale;
                        minX = Math.min(minX, m.uiX);
                        maxX = Math.max(maxX, m.uiX + w);
                    }
                    return (canvas.width / 2) - ((minX + (maxX - minX) / 2) * spanScale);
                }

                readonly property real offsetY: {
                    if (monitorsModel.count === 0) return 0;
                    let minY = 999999, maxY = -999999;
                    for (let i = 0; i < monitorsModel.count; i++) {
                        const m = monitorsModel.get(i);
                        const h = (m.resH / m.sysScale) * section.uiScale;
                        minY = Math.min(minY, m.uiY);
                        maxY = Math.max(maxY, m.uiY + h);
                    }
                    return (canvas.height / 2) - ((minY + (maxY - minY) / 2) * spanScale);
                }

                Item {
                    id: transformNode
                    x: canvas.offsetX
                    y: canvas.offsetY
                    scale: canvas.spanScale
                    transformOrigin: Item.TopLeft

                    Behavior on x { NumberAnimation { duration: Design.duration.slow; easing.type: Easing.OutQuint } }
                    Behavior on y { NumberAnimation { duration: Design.duration.slow; easing.type: Easing.OutQuint } }
                    Behavior on scale { NumberAnimation { duration: Design.duration.slow; easing.type: Easing.OutQuint } }

                    Repeater {
                        model: monitorsModel

                        Item {
                            id: monitorNode
                            required property int index
                            required property string name
                            required property int resW
                            required property int resH
                            required property real sysScale
                            required property string rate
                            required property real uiX
                            required property real uiY

                            readonly property bool isActive: section.activeEditIndex === monitorNode.index

                            Rectangle {
                                id: monitorCard
                                x: monitorNode.uiX
                                y: monitorNode.uiY
                                width: (monitorNode.resW / monitorNode.sysScale) * section.uiScale
                                height: (monitorNode.resH / monitorNode.sysScale) * section.uiScale

                                radius: Design.s(8)
                                color: monitorNode.isActive ? Design.tint(section.selectedResAccent, 0.18) : Design.ground
                                border.color: monitorNode.isActive ? section.selectedResAccent : Design.active
                                border.width: monitorNode.isActive ? 2 : 1
                                z: monitorNode.isActive ? 5 : 0

                                Behavior on x { NumberAnimation { duration: Design.duration.base; easing.type: Easing.OutQuint } }
                                Behavior on y { NumberAnimation { duration: Design.duration.base; easing.type: Easing.OutQuint } }
                                Behavior on color { ColorAnimation { duration: Design.duration.base } }
                                Behavior on border.color { ColorAnimation { duration: Design.duration.base } }
                                Behavior on width { NumberAnimation { duration: Design.duration.slow; easing.type: Easing.OutQuint } }
                                Behavior on height { NumberAnimation { duration: Design.duration.slow; easing.type: Easing.OutQuint } }

                                // The label block keeps a readable size whatever
                                // the canvas zoom is.
                                Item {
                                    anchors.centerIn: parent
                                    width: 120
                                    height: 76

                                    property real idealScale: Math.min(1.2, parent.width / 120, parent.height / 76) / transformNode.scale
                                    property real maxPhysicalScale: Math.min((parent.width * 0.92) / width, (parent.height * 0.92) / height)
                                    scale: Math.min(idealScale, maxPhysicalScale)

                                    ColumnLayout {
                                        anchors.centerIn: parent
                                        spacing: 1

                                        Text {
                                            Layout.alignment: Qt.AlignHCenter
                                            font.family: Design.font.mono
                                            font.weight: Font.Bold
                                            font.pixelSize: 34
                                            color: monitorNode.isActive ? section.selectedResAccent : Design.textDim
                                            text: monitorNode.index + 1
                                            Behavior on color { ColorAnimation { duration: Design.duration.base } }
                                        }
                                        Text {
                                            Layout.alignment: Qt.AlignHCenter
                                            font.family: Design.font.mono
                                            font.weight: Font.DemiBold
                                            font.pixelSize: 12
                                            color: Design.text
                                            text: monitorNode.name
                                        }
                                        Text {
                                            Layout.alignment: Qt.AlignHCenter
                                            font.family: Design.font.mono
                                            font.pixelSize: 10
                                            color: Design.textDim
                                            text: monitorNode.resW + "×" + monitorNode.resH
                                                + " @ " + monitorNode.rate + "Hz"
                                        }
                                    }
                                }
                            }

                            // Invisible dragger: the card animates to the snapped
                            // position, this one follows the pointer.
                            Item {
                                id: ghostDrag
                                x: monitorNode.uiX
                                y: monitorNode.uiY
                                width: monitorCard.width
                                height: monitorCard.height
                                z: monitorNode.isActive ? 10 : 1

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: monitorsModel.count > 1 ? Qt.SizeAllCursor : Qt.PointingHandCursor
                                    drag.target: monitorsModel.count > 1 ? ghostDrag : null
                                    drag.axis: Drag.XAndYAxis

                                    onPressed: {
                                        section.activeEditIndex = monitorNode.index;
                                        ghostDrag.x = monitorNode.uiX;
                                        ghostDrag.y = monitorNode.uiY;
                                    }

                                    onPositionChanged: {
                                        if (!drag.active || monitorsModel.count < 2)
                                            return;

                                        const mW = monitorCard.width;
                                        const mH = monitorCard.height;
                                        const padding = 40;

                                        let boundMinX = 999999, boundMinY = 999999;
                                        let boundMaxX = -999999, boundMaxY = -999999;

                                        for (let j = 0; j < monitorsModel.count; j++) {
                                            if (j === monitorNode.index) continue;
                                            const sModel = monitorsModel.get(j);
                                            const sW = (sModel.resW / sModel.sysScale) * section.uiScale;
                                            const sH = (sModel.resH / sModel.sysScale) * section.uiScale;

                                            boundMinX = Math.min(boundMinX, sModel.uiX - mW - padding);
                                            boundMinY = Math.min(boundMinY, sModel.uiY - mH - padding);
                                            boundMaxX = Math.max(boundMaxX, sModel.uiX + sW + padding);
                                            boundMaxY = Math.max(boundMaxY, sModel.uiY + sH + padding);
                                        }

                                        ghostDrag.x = Math.max(boundMinX, Math.min(ghostDrag.x, boundMaxX));
                                        ghostDrag.y = Math.max(boundMinY, Math.min(ghostDrag.y, boundMaxY));

                                        let bestX = ghostDrag.x, bestY = ghostDrag.y, bestDist = 999999;

                                        for (let j = 0; j < monitorsModel.count; j++) {
                                            if (j === monitorNode.index) continue;
                                            const sModel = monitorsModel.get(j);
                                            const sW = (sModel.resW / sModel.sysScale) * section.uiScale;
                                            const sH = (sModel.resH / sModel.sysScale) * section.uiScale;

                                            const snapped = section.getPerimeterSnap(
                                                ghostDrag.x, ghostDrag.y,
                                                sModel.uiX, sModel.uiY,
                                                sW, sH, mW, mH, 20);

                                            const dist = Math.hypot(ghostDrag.x - snapped.x, ghostDrag.y - snapped.y);
                                            if (dist < bestDist) {
                                                bestDist = dist;
                                                bestX = snapped.x;
                                                bestY = snapped.y;
                                            }
                                        }

                                        if (!section.isOverlappingAny(bestX, bestY, mW, mH, monitorNode.index)) {
                                            monitorsModel.setProperty(monitorNode.index, "uiX", bestX);
                                            monitorsModel.setProperty(monitorNode.index, "uiY", bestY);
                                            section.markDirty();
                                        }
                                    }

                                    onReleased: {
                                        ghostDrag.x = monitorNode.model.uiX;
                                        ghostDrag.y = monitorNode.model.uiY;
                                    }
                                }
                            }
                        }
                    }
                }

                EmptyState {
                    anchors.centerIn: parent
                    width: parent.width
                    visible: monitorsModel.count === 0
                    icon: "\u{f0379}"
                    title: "No displays reported"
                    hint: "sway returned an empty output list."
                }
            }
        }
        // ── Actions & Identify Bar ──────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.sm)

            Pill {
                label: "Identify Displays"
                icon: "\u{f0379}"
                onClicked: Monitors.identify()
            }

            Item { Layout.fillWidth: true }

            Label {
                text: monitorsModel.count + " display" + (monitorsModel.count === 1 ? "" : "s") + " connected"
                role: "caption"
                dim: true
            }
        }
    }

    // =========================================================================
    // REMEMBERED LAYOUTS
    // Every applied layout is kept for the set of screens it was made for, and
    // the daemon puts it back when that set is plugged in again (dock in the
    // morning, laptop alone in the evening). This is where they are seen and
    // dropped.
    // =========================================================================
    property var profiles: []
    Process {
        id: profileReader
        command: ["b1air-daemon", "monitors", "profiles"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { section.profiles = JSON.parse(this.text.trim() || "[]"); }
                catch (e) { section.profiles = []; }
            }
        }
    }
    Process { id: profileForget; onExited: profileReader.running = true }
    Timer { id: profileRecheck; interval: 1500; onTriggered: profileReader.running = true }

    Card {
        title: "Remembered layouts"
        subtitle: section.profiles.length === 0
            ? "Apply a layout and it is kept for this set of screens"
            : "Put back automatically whenever the same screens are connected"
        icon: "\u{f0379}"
        accentColor: Design.teal

        Repeater {
            model: section.profiles
            delegate: RowLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: Design.s(Design.space.sm)
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Label {
                        Layout.fillWidth: true
                        text: modelData.key
                        weight: Design.weight.semibold
                        elide: Text.ElideRight
                    }
                    Label {
                        text: modelData.screens + (modelData.screens === 1 ? " screen" : " screens")
                              + (modelData.current ? " · connected now" : "")
                        role: "caption"
                        color: modelData.current ? Design.accent : Design.textDim
                    }
                }
                ActionButton {
                    Layout.fillWidth: false
                    icon: "\u{f0a7a}"
                    label: "Forget"
                    onActivated: {
                        profileForget.command = ["b1air-daemon", "monitors", "forget", modelData.key];
                        profileForget.running = true;
                    }
                }
            }
        }
    }

    // =========================================================================
    // EXTERNAL BRIGHTNESS
    // The daemon has spoken DDC/CI for a long time (it dims external panels
    // on idle) and Monitors.brightness has listed the panels that answer it;
    // nothing ever showed them. A laptop's own backlight is on Power & Battery.
    // =========================================================================
    Card {
        title: "Brightness"
        subtitle: Monitors.hasBrightness
            ? "External screens that take brightness over DDC/CI"
            : "No external screen answered over DDC/CI"
        icon: "\u{f00df}"
        accentColor: Design.yellow

        Repeater {
            model: Monitors.brightness
            delegate: Slider {
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredHeight: Design.s(Design.size.ctl)
                value: modelData.brightness
                tone: Design.yellow
                icon: "\u{f00df}"
                label: modelData.name
                onMoved: pct => Monitors.setBrightness(modelData.id, pct)
            }
        }

        Label {
            visible: !Monitors.hasBrightness
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            role: "caption"
            dim: true
            text: "Most monitors do, over the same cable as the picture. It needs ddcutil and the i2c-dev module; some panels have DDC/CI switched off in their own menu."
        }

        ButtonRow {
            ActionButton {
                icon: "\u{f0450}"
                label: "Detect again"
                onActivated: Monitors.redetect()
            }
        }
    }

    // =========================================================================
    // 2. THE SELECTED SCREEN
    // =========================================================================
    Card {
        visible: section.activeMonitor !== null
        title: section.activeMonitor
            ? (section.activeEditIndex + 1) + ". " + section.activeMonitor.name : ""
        subtitle: section.activeMonitor
            ? ([section.activeMonitor.make, section.activeMonitor.model].filter(t => t).join(" ")
               || "Settings for the selected screen")
            : ""
        icon: "\u{f0379}"
        accentColor: section.selectedRateAccent

        // Display power / state toggle
        Toggle {
            label: "Enable display"
            subtitle: "Turn this video output on or off in Sway"
            checked: section.activeMonitor ? (section.activeMonitor.active !== false) : true
            onToggled: {
                if (!section.activeMonitor) return;
                Monitors.setEnabled(section.activeMonitor.name, !section.activeMonitor.active);
            }
        }

        SectionLabel { text: "Resolution" }

        GridLayout {
            Layout.fillWidth: true
            columns: 3
            columnSpacing: Design.s(Design.space.sm)
            rowSpacing: Design.s(Design.space.sm)

            Repeater {
                model: [
                    { resW: 3840, resH: 2160, label: "4K" },
                    { resW: 2560, resH: 1440, label: "QHD" },
                    { resW: 1920, resH: 1080, label: "FHD" },
                    { resW: 1600, resH: 900,  label: "HD+" },
                    { resW: 1366, resH: 768,  label: "WXGA" },
                    { resW: 1280, resH: 720,  label: "HD" },
                    { resW: 1024, resH: 768,  label: "XGA" },
                    { resW: 800,  resH: 600,  label: "SVGA" }
                ]

                Rectangle {
                    id: resCard
                    required property var modelData

                    Layout.fillWidth: true
                    Layout.preferredHeight: Design.s(44)
                    radius: Design.s(Design.radius.ctl)

                    readonly property bool isSel: section.activeMonitor
                        && section.activeMonitor.resW === resCard.modelData.resW
                        && section.activeMonitor.resH === resCard.modelData.resH
                    readonly property color accentColor: Design.accent

                    // Selected the way a Pill is: an accent tint, no outline.
                    color: resCard.isSel ? Design.tint(resCard.accentColor, 0.24)
                                         : (resMa.containsMouse ? Design.glassHover : Design.glassCard)

                    Behavior on color { ColorAnimation { duration: Design.duration.base } }

                    scale: resMa.pressed ? 0.96 : 1.0
                    Behavior on scale { NumberAnimation { duration: Design.duration.fast; easing.type: Easing.OutSine } }

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 0

                        Label {
                            Layout.alignment: Qt.AlignHCenter
                            weight: Design.weight.semibold
                            color: resCard.isSel ? resCard.accentColor : Design.text
                            text: resCard.modelData.label
                            Behavior on color { ColorAnimation { duration: Design.duration.base } }
                        }

                        Label {
                            Layout.alignment: Qt.AlignHCenter
                            role: "caption"
                            isMono: true
                            color: resCard.isSel ? Design.text : Design.textFaint
                            text: resCard.modelData.resW + "×" + resCard.modelData.resH
                            Behavior on color { ColorAnimation { duration: Design.duration.base } }
                        }
                    }

                    Clickable {
                        id: resMa
                        enabled: section.activeMonitor !== null
                        onClicked: {
                            section.selectedResAccent = resCard.accentColor;
                            monitorsModel.setProperty(section.activeEditIndex, "resW", resCard.modelData.resW);
                            monitorsModel.setProperty(section.activeEditIndex, "resH", resCard.modelData.resH);
                            section.markDirty();
                        }
                    }
                }
            }
        }

        SectionLabel {
            text: "Refresh rate"
            Layout.topMargin: Design.s(Design.space.sm)
        }

        Item {
            id: sliderContainer
            Layout.fillWidth: true
            Layout.preferredHeight: Design.s(56)
            Layout.leftMargin: Design.s(Design.space.md)
            Layout.rightMargin: Design.s(Design.space.md)

            readonly property var rates: [60, 75, 100, 120, 144, 165, 180, 240, 360]
            readonly property var rateColors: [Design.danger, Design.accentAlt, Design.accent,
                                               Design.accentSoft, Design.ok, Design.accentAlt,
                                               Design.warn, Design.ok, Design.warn]

            readonly property int currentIndex: {
                if (!section.activeMonitor) return 0;
                const currentVal = parseInt(section.activeMonitor.rate) || 60;
                let closestIdx = 0, minDiff = 9999;
                for (let i = 0; i < rates.length; i++) {
                    const diff = Math.abs(rates[i] - currentVal);
                    if (diff < minDiff) { minDiff = diff; closestIdx = i; }
                }
                return closestIdx;
            }

            property real visualPct: currentIndex / (rates.length - 1)
            onCurrentIndexChanged: if (!sliderMa.pressed) visualPct = currentIndex / (rates.length - 1)

            Rectangle {
                id: track
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.topMargin: Design.s(Design.space.sm)
                height: Design.s(12)
                radius: Design.s(6)
                color: Design.sunken
                border.color: Design.ground
                border.width: Design.border

                Rectangle {
                    width: Math.max(knob.width, knob.x + knob.width / 2)
                    height: parent.height
                    radius: parent.radius
                    color: section.selectedRateAccent
                    Behavior on color { ColorAnimation { duration: Design.duration.base } }
                }
            }

            Repeater {
                model: sliderContainer.rates.length

                Item {
                    id: tick
                    required property int index
                    x: (tick.index / (sliderContainer.rates.length - 1)) * track.width
                    y: track.y + Design.s(22)

                    Label {
                        anchors.horizontalCenter: parent.horizontalCenter
                        role: "caption"
                        text: sliderContainer.rates[tick.index]
                        weight: sliderContainer.currentIndex === tick.index ? Design.weight.semibold : Design.weight.regular
                        color: sliderContainer.currentIndex === tick.index ? section.selectedRateAccent : Design.textFaint
                        Behavior on color { ColorAnimation { duration: Design.duration.base } }
                    }
                }
            }

            Rectangle {
                id: knob
                width: Design.s(24)
                height: Design.s(24)
                radius: width / 2
                color: sliderMa.containsPress ? section.selectedRateAccent : Design.text
                anchors.verticalCenter: track.verticalCenter
                x: (sliderContainer.visualPct * track.width) - width / 2

                Behavior on x {
                    enabled: !sliderMa.pressed
                    NumberAnimation { duration: Design.duration.base; easing.type: Easing.OutCubic }
                }
                Behavior on color { ColorAnimation { duration: Design.duration.fast } }

                border.width: sliderMa.containsMouse ? 4 : 0
                border.color: Design.tint(section.selectedRateAccent, 0.3)
                Behavior on border.width { NumberAnimation { duration: Design.duration.fast } }
            }

            Clickable {
                id: sliderMa
                anchors.margins: Design.s(-15)
                enabled: section.activeMonitor !== null

                function updateSelection(mouseX, snapToGrid) {
                    if (!section.activeMonitor) return;
                    let pct = (mouseX - track.x) / track.width;
                    pct = Math.max(0, Math.min(1, pct));
                    const idx = Math.round(pct * (sliderContainer.rates.length - 1));

                    sliderContainer.visualPct = snapToGrid ? idx / (sliderContainer.rates.length - 1) : pct;

                    monitorsModel.setProperty(section.activeEditIndex, "rate", sliderContainer.rates[idx].toString());
                    section.selectedRateAccent = sliderContainer.rateColors[idx];
                    section.markDirty();
                }

                onPressed: mouse => updateSelection(mouse.x, false)
                onPositionChanged: mouse => { if (pressed) updateSelection(mouse.x, false) }
                onReleased: mouse => updateSelection(mouse.x, true)
                onCanceled: sliderContainer.visualPct = sliderContainer.currentIndex / (sliderContainer.rates.length - 1)
            }
        }

        // Scale stepper
        Stepper {
            label: "Scale"
            valueText: (Math.round(section.currentSysScale * 100) / 100) + "×"
            onDecrement: section.setSysScale(section.currentSysScale - 0.25)
            onIncrement: section.setSysScale(section.currentSysScale + 0.25)
        }

        // Orientation row
        RowLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.sm)

            Label {
                text: "Orientation"
                Layout.fillWidth: true
            }

            Repeater {
                model: [
                    { id: "normal", label: "0°", tip: "Landscape" },
                    { id: "90",     label: "90°", tip: "Portrait" },
                    { id: "180",    label: "180°", tip: "Flipped" },
                    { id: "270",    label: "270°", tip: "Portrait (Flipped)" }
                ]

                Pill {
                    required property var modelData
                    label: modelData.label
                    active: section.activeMonitor && (section.activeMonitor.transform || "normal") === modelData.id
                    onClicked: {
                        if (!section.activeMonitor) return;
                        Monitors.setTransform(section.activeMonitor.name, modelData.id);
                        monitorsModel.setProperty(section.activeEditIndex, "transform", modelData.id);
                    }
                }
            }
        }

        Label {
            visible: section.activeMonitor !== null
            // "Desktop area" used to read close enough to "Resolution" (the
            // section right above) that changing Scale looked like it was
            // changing the actual output resolution — it wasn't; this number
            // is the logical/effective area after scaling, and the physical
            // mode sway actually applies is spelled out here now too.
            text: section.activeMonitor
                ? "Scaled to " + Math.round(section.activeMonitor.resW / section.currentSysScale)
                  + "×" + Math.round(section.activeMonitor.resH / section.currentSysScale)
                  + " — physical output stays " + section.activeMonitor.resW + "×" + section.activeMonitor.resH
                : ""
            role: "caption"
            color: Design.textFaint
            Layout.fillWidth: true
        }

        // ── Apply ────────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.topMargin: Design.s(Design.space.sm)
            spacing: Design.s(Design.space.sm)

            Label {
                text: section.dirty ? "Unapplied changes" : "Matches what sway is running"
                role: "caption"
                dim: !section.dirty
                color: section.dirty ? Design.peach : Design.textDim
                Layout.fillWidth: true
            }

            Pill {
                label: "Reset"
                enabled: section.dirty
                opacity: section.dirty ? Design.opacity.full : Design.opacity.disabled
                onClicked: section.reload()
            }

            Pill {
                label: monitorsModel.count > 1 ? "Apply All" : "Apply"
                icon: "\u{f012c}"
                active: section.dirty
                enabled: section.dirty
                opacity: section.dirty ? Design.opacity.full : Design.opacity.disabled
                onClicked: section.applyLayout()
            }
        }
    }

    // Carried over from the popup, including the two fixes that are easy to
    // lose: a tight-snap pass that closes sub-pixel gaps between neighbours,
    // and re-anchoring the whole layout at 0,0.
    function applyLayout() {
        if (monitorsModel.count === 0)
            return;
        profileRecheck.restart();     // the daemon saves it as a profile

        if (monitorsModel.count === 1) {
            const mon = monitorsModel.get(0);
            Monitors.apply([{
                name: mon.name, resW: mon.resW, resH: mon.resH,
                rate: mon.rate, sysScale: mon.sysScale, x: 0, y: 0
            }]);
            Sys.notify("Displays", "Display Update",
                       "Applied: " + mon.resW + "x" + mon.resH + " @ " + mon.rate + "Hz");
            section.dirty = false;
            return;
        }

        let rects = [];
        for (let i = 0; i < monitorsModel.count; i++) {
            const m = monitorsModel.get(i);
            rects.push({
                x: m.uiX / section.uiScale,
                y: m.uiY / section.uiScale,
                w: Math.round(m.resW / m.sysScale),
                h: Math.round(m.resH / m.sysScale),
                resW: m.resW, resH: m.resH, name: m.name,
                rate: m.rate, sysScale: m.sysScale
            });
        }

        for (let i = 1; i < rects.length; i++) {
            let bestX = rects[i].x, bestY = rects[i].y, bestDist = 999999;
            for (let j = 0; j < i; j++) {
                const r0 = rects[j];
                const snapped = section.getPerimeterSnap(rects[i].x, rects[i].y,
                                                         r0.x, r0.y, r0.w, r0.h,
                                                         rects[i].w, rects[i].h, 25);
                const dist = Math.hypot(rects[i].x - snapped.x, rects[i].y - snapped.y);
                if (dist < bestDist) {
                    bestDist = dist;
                    bestX = Math.round(snapped.x);
                    bestY = Math.round(snapped.y);
                }
            }
            rects[i].x = bestX;
            rects[i].y = bestY;
        }

        let minX = 999999, minY = 999999;
        for (const r of rects) {
            minX = Math.min(minX, r.x);
            minY = Math.min(minY, r.y);
        }

        const layout = rects.map(r => ({
            name: r.name, resW: r.resW, resH: r.resH,
            rate: r.rate, sysScale: r.sysScale,
            x: Math.round(r.x - minX), y: Math.round(r.y - minY)
        }));

        Monitors.apply(layout);
        Sys.notify("Displays", "Display Update", "Applied layout for: " + layout.map(r => r.name).join(" "));
        section.dirty = false;
    }
}
