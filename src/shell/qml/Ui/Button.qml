import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as C

// =============================================================================
// Unified Button component.
//
// Variants: "primary", "secondary" (default), "ghost", "danger"
// Sizes: "sm" (28px), "md" (32px, default)
// Corner radius: Design.radius.ctl (8px)
// Supports keyboard focus (Tab, Enter, Space), FocusRing, and 2-step destructive confirmation.
// =============================================================================

Rectangle {
    id: root

    // Content
    property string text: ""
    property string label: "" // alias for text
    property string icon: ""
    property string tip: ""

    // Style variants
    property string variant: "secondary" // "primary" | "secondary" | "ghost" | "danger"
    property string size: "md"           // "sm" (28) | "md" (32)
    property bool checked: false
    property bool destructive: false
    property string confirmText: "Sure?"
    property bool iconOnly: false
    property bool snug: false

    // State
    property bool _armed: false
    readonly property bool hovered: mouseArea.containsMouse
    readonly property bool pressed: mouseArea.pressed || _keyPressed
    property bool _keyPressed: false

    signal clicked()
    signal activated()

    // Aliases
    readonly property string _effectiveText: _armed ? confirmText : (text !== "" ? text : label)

    // Sizing
    readonly property real _targetHeight: size === "sm" ? Design.s(Design.size.sm) : Design.s(Design.size.md)
    implicitHeight: _targetHeight
    Layout.preferredHeight: _targetHeight

    readonly property real _pad: Design.s(snug ? Design.space.sm : (size === "sm" ? Design.space.sm : Design.space.md))
    readonly property real _contentWidth: (icon !== "" ? glyphText.implicitWidth : 0)
        + (_effectiveText !== "" && !iconOnly ? labelText.implicitWidth + (icon !== "" ? Design.s(Design.space.xs + 2) : 0) : 0)
    implicitWidth: iconOnly ? implicitHeight : (_contentWidth + _pad * 2)
    // The width with its label, whatever iconOnly says, at the normal and at
    // the narrow padding: for a row to decide whether its labels fit (the
    // Control Center's power row drops them in Ukrainian and Russian).
    readonly property real _contentFull: (icon !== "" ? glyphText.implicitWidth + Design.s(Design.space.xs + 2) : 0)
                                         + labelText.implicitWidth
    readonly property real fullWidth: _contentFull + Design.s(Design.space.md) * 2
    readonly property real snugWidth: _contentFull + Design.s(Design.space.sm) * 2

    radius: Design.s(Design.radius.ctl)
    opacity: enabled ? 1.0 : Design.opacity.disabled

    // Accessibility
    Accessible.role: Accessible.Button
    Accessible.name: _effectiveText !== "" ? _effectiveText : (tip !== "" ? tip : icon)
    Accessible.focusable: enabled
    activeFocusOnTab: enabled

    // Colors
    readonly property bool _isPrimary: variant === "primary"
    readonly property bool _isDanger: variant === "danger" || (_armed && destructive)
    readonly property bool _isGhost: variant === "ghost"

    color: {
        if (_armed && destructive) return Design.danger;
        if (_isPrimary) {
            return pressed ? Qt.darker(Design.accent, 1.08)
                           : (hovered ? Qt.lighter(Design.accent, 1.08) : Design.accent);
        }
        if (_isDanger) {
            return pressed ? Design.tint(Design.danger, 0.28)
                           : (hovered ? Design.tint(Design.danger, 0.18) : "transparent");
        }
        if (_isGhost) {
            return pressed ? Design.veilStrong
                           : (hovered ? Design.veil : (checked ? Design.selection : "transparent"));
        }
        // secondary: a lighter pane on glass (raised there was a near-black
        // slab on every glass card), the raised surface on an opaque one.
        if (checked) return Design.selection;
        if (Design.translucent)
            return pressed ? Design.tint(Design.text, 0.20) : (hovered ? Design.veilBold : Design.well);
        return pressed ? Design.active : (hovered ? Design.hover : Design.raised);
    }

    border.width: (_isPrimary || (_armed && destructive)) ? 0 : 1
    border.color: {
        if (_isDanger) return Design.tint(Design.danger, 0.35);
        if (_isGhost) return (checked ? Design.tint(Design.accent, 0.35) : "transparent");
        return checked ? Design.tint(Design.accent, 0.35) : Design.glassBorder;
    }

    Behavior on color { ColorAnimation { duration: Design.duration.fast } }
    Behavior on border.color { ColorAnimation { duration: Design.duration.fast } }

    Timer {
        id: disarmTimer
        interval: 3500
        onTriggered: root._armed = false
    }

    function trigger() {
        if (!root.enabled) return;
        if (root.destructive && !root._armed) {
            root._armed = true;
            disarmTimer.restart();
            return;
        }
        root._armed = false;
        disarmTimer.stop();
        root.activated();
        root.clicked();
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Design.s(Design.space.xs + 2)

        Text {
            id: glyphText
            visible: root.icon !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: root.icon
            font.family: Design.font.icon
            font.pixelSize: Design.s(root.size === "sm" ? Design.font.glyphSm : Design.font.glyph)
            color: {
                if (root._armed && root.destructive) return Design.accentText;
                if (root._isPrimary) return Design.accentText;
                if (root._isDanger) return Design.danger;
                if (root.checked) return Design.accent;
                return Design.text;
            }
            horizontalAlignment: Text.AlignHCenter
        }

        Text {
            id: labelText
            visible: root._effectiveText !== "" && !root.iconOnly
            // Squeezed by a layout, the label shortens instead of running
            // past the button's edge.
            width: Math.min(implicitWidth, Math.max(0, root.width - root._pad * 2
                            - (glyphText.visible ? glyphText.implicitWidth + row.spacing : 0)))
            anchors.verticalCenter: parent.verticalCenter
            text: root._effectiveText
            font.family: Design.font.sans
            font.pixelSize: Design.s(root.size === "sm" ? Design.font.footnote : Design.font.body)
            font.weight: (root._isPrimary || root.checked) ? Design.weight.semibold : Design.weight.regular
            color: {
                if (root._armed && root.destructive) return Design.accentText;
                if (root._isPrimary) return Design.accentText;
                if (root._isDanger) return Design.danger;
                if (root.checked) return Design.accent;
                return Design.text;
            }
            elide: Text.ElideRight
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
            root.forceActiveFocus(Qt.MouseFocusReason);
            root.trigger();
        }
    }

    Keys.onReturnPressed: function(event) {
        if (root.enabled) {
            root.trigger();
            event.accepted = true;
        }
    }

    Keys.onSpacePressed: function(event) {
        if (root.enabled) {
            root.trigger();
            event.accepted = true;
        }
    }

    FocusRing {
        target: root
        cornerRadius: root.radius + Design.s(Design.space.xxs)
    }

    // An icon-only button says what it does on hover, as the toolbar buttons
    // it replaces did; a label cut short shows in full.
    C.ToolTip.visible: root.hovered && (root.tip !== "" || labelText.truncated)
    C.ToolTip.delay: 600
    C.ToolTip.text: root.tip !== "" ? root.tip : root._effectiveText
}
