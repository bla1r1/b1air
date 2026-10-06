import QtQuick
import QtQuick.Layouts

// =============================================================================
// Horizontal fill slider — volume, brightness, anything 0..100.
// Supports modern capsule styling with embedded leading icon, label, and % value.
// =============================================================================

Item {
    id: root

    // ── In ───────────────────────────────────────────────────────────────────
    property int value: 0                    // from the poller, clamped to the range
    property color tone: Design.accent       // gradient base
    property bool muted: false

    property string icon: ""
    property bool iconClickable: false
    property string label: ""
    property bool showPercent: true

    // ── Out ──────────────────────────────────────────────────────────────────
    signal moved(int pct)
    signal iconClicked()

    readonly property bool active: _dragging || settle.running
    readonly property int shown: root.active ? _local : Math.max(root.minimum, Math.min(root.maximum, root.value))

    // ── Tuning ───────────────────────────────────────────────────────────────
    property int minimum: 0
    property int maximum: 100

    property int throttleInterval: 50   // process spawn rate ceiling
    property int settleDelay: 600       // poller round-trip allowance
    property int cornerRadius: Design.radius.ctl

    implicitHeight: Design.s(Design.size.ctl)

    // ── Internals ────────────────────────────────────────────────────────────
    property int _local: 0
    property bool _dragging: false

    Timer {
        id: throttle
        interval: root.throttleInterval
        property int pending: -1
        onTriggered: {
            if (pending >= 0) {
                root.moved(pending);
                pending = -1;
            }
        }
    }

    Timer { id: settle; interval: root.settleDelay }

    function _emit(pct) {
        throttle.pending = pct;
        if (!throttle.running)
            throttle.start();
    }

    Rectangle {
        id: track
        anchors.fill: parent
        radius: Design.s(root.cornerRadius)
        // A groove in the glass rather than a black well cut into it.
        color: Design.translucent ? Design.tint(Design.text, 0.10) : Design.sunken
        border.color: ma.containsMouse ? Design.glassBorder : Design.tint(Design.line, 0.5)
        border.width: 1
        clip: true

        Behavior on border.color { ColorAnimation { duration: Design.duration.fast } }

        // Active fill
        Rectangle {
            id: fill
            height: parent.height
            // At zero the rounded stub sat under the leading icon and sliced it
            // in half. Nothing set means nothing filled.
            width: root.shown <= root.minimum
                ? 0
                : Math.max(parent.height * 0.4, parent.width * (root.shown / root.maximum))
            radius: Design.s(root.cornerRadius)

            opacity: root.muted ? Design.opacity.disabled : (ma.containsMouse ? 0.95 : 0.85)
            Behavior on opacity { NumberAnimation { duration: Design.duration.base } }

            Behavior on width {
                enabled: !root._dragging
                NumberAnimation { duration: Design.duration.base; easing.type: Design.easing }
            }

            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop {
                    position: 0.0
                    color: root.muted ? Design.active : root.tone
                }
                GradientStop {
                    position: 1.0
                    color: root.muted ? Qt.lighter(Design.active, 1.15) : Qt.lighter(root.tone, 1.20)
                }
            }
        }

        // Overlay content: icon, label, percentage
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Design.s(Design.space.md)
            anchors.rightMargin: Design.s(Design.space.md)
            spacing: Design.s(Design.space.sm)

            Icon {
                visible: root.icon !== ""
                text: root.icon
                role: "subhead"
                color: root.muted ? Design.textFaint : (fill.width > parent.width * 0.25 ? Design.accentText : Design.text)
                Behavior on color { ColorAnimation { duration: Design.duration.fast } }
            }

            Label {
                visible: root.label !== ""
                text: root.label
                role: "body"
                weight: Design.weight.medium
                Layout.fillWidth: true
                elide: Text.ElideRight
                color: fill.width > parent.width * 0.5 ? Design.accentText : Design.text
                Behavior on color { ColorAnimation { duration: Design.duration.fast } }
            }

            Item {
                visible: root.label === ""
                Layout.fillWidth: true
            }

            Label {
                visible: root.showPercent
                text: root.shown + "%"
                role: "caption"
                isMono: true
                weight: Design.weight.semibold
                color: fill.width > parent.width * 0.85 ? Design.accentText : Design.textDim
                Behavior on color { ColorAnimation { duration: Design.duration.fast } }
            }
        }
    }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor

        property bool _startedOnIcon: false

        function at(mx) {
            const pct = Math.round((mx / width) * root.maximum);
            return Math.max(root.minimum, Math.min(root.maximum, pct));
        }

        onPressed: mouse => {
            _startedOnIcon = (root.iconClickable && mouse.x <= height);
            if (!_startedOnIcon) {
                settle.stop();
                root._dragging = true;
                root._local = at(mouse.x);
                root._emit(root._local);
            }
        }

        onPositionChanged: mouse => {
            if (_startedOnIcon && Math.abs(mouse.x - height / 2) > 10) {
                _startedOnIcon = false;
                settle.stop();
                root._dragging = true;
            }
            if (root._dragging) {
                root._local = at(mouse.x);
                root._emit(root._local);
            }
        }

        onReleased: {
            if (_startedOnIcon) {
                root.iconClicked();
                _startedOnIcon = false;
                return;
            }
            root._dragging = false;
            throttle.stop();
            if (throttle.pending >= 0) {
                root.moved(throttle.pending);
                throttle.pending = -1;
            }
            settle.restart();
        }
    }
}

