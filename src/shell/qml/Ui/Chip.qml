import QtQuick
import QtQuick.Layouts

// =============================================================================
// Filter chip component.
//
// Capsule shape for filtering, multi-choice chips, or category tagging.
// Supports active/selected state, keyboard focus, and FocusRing.
// =============================================================================

Rectangle {
    id: root

    property string label: ""
    property string text: ""
    readonly property string _effectiveLabel: label !== "" ? label : text
    property string icon: ""
    property bool active: false
    property alias checked: root.active
    property color activeColor: Design.accent
    property string size: "sm" // "xs" (24) | "sm" (28)

    signal clicked()
    signal activated()

    readonly property real _targetHeight: size === "xs" ? Design.s(Design.size.xs) : Design.s(Design.size.sm)
    implicitHeight: _targetHeight
    Layout.preferredHeight: _targetHeight

    readonly property real _pad: Design.s(Design.space.md)
    implicitWidth: (glyph.visible ? glyph.implicitWidth + contentRow.spacing : 0)
                   + labelText.implicitWidth + _pad * 2

    radius: height / 2
    opacity: enabled ? 1.0 : Design.opacity.disabled

    color: root.active ? Design.tint(root.activeColor, mouseArea.containsMouse ? 0.30 : 0.22)
                       : (mouseArea.pressed ? Design.veilBold
                          : mouseArea.containsMouse ? Design.glassHover : Design.glassCard)

    border.width: 1
    border.color: root.active ? Design.tint(root.activeColor, 0.40) : Design.glassBorder

    Behavior on color { ColorAnimation { duration: Design.duration.fast } }
    Behavior on border.color { ColorAnimation { duration: Design.duration.fast } }

    activeFocusOnTab: enabled
    Accessible.role: Accessible.Button
    Accessible.name: root._effectiveLabel
    Accessible.focusable: enabled

    Row {
        id: contentRow
        anchors.centerIn: parent
        spacing: Design.s(Design.space.xs)

        Icon {
            id: glyph
            visible: root.icon !== ""
            text: root.icon
            role: "caption"
            anchors.verticalCenter: parent.verticalCenter
            color: root.active ? root.activeColor : Design.textDim
        }

        Label {
            id: labelText
            anchors.verticalCenter: parent.verticalCenter
            text: root._effectiveLabel
            role: root.size === "xs" ? "caption" : "footnote"
            weight: root.active ? Design.weight.semibold : Design.weight.regular
            color: root.active ? root.activeColor : Design.text
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
            if (root.enabled) {
                root.forceActiveFocus(Qt.MouseFocusReason);
                root.activated();
                root.clicked();
            }
        }
    }

    Keys.onReturnPressed: function(event) {
        if (root.enabled) {
            root.activated();
            root.clicked();
            event.accepted = true;
        }
    }

    Keys.onSpacePressed: function(event) {
        if (root.enabled) {
            root.activated();
            root.clicked();
            event.accepted = true;
        }
    }

    FocusRing {
        target: root
        cornerRadius: root.radius + Design.s(Design.space.xxs)
    }
}
