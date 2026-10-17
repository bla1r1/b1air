import QtQuick

// =============================================================================
// Unified Switch component.
//
// Standalone pill toggle switch with accent color, keyboard focus,
// accessible properties, and smooth animation.
// =============================================================================

Rectangle {
    id: root

    property bool checked: false
    property color activeColor: Design.accent
    property string accessibleName: ""

    signal toggled()

    implicitWidth: Design.s(Design.size.md + Design.space.sm)
    implicitHeight: Design.s(Design.size.xs)
    radius: height / 2

    color: root.checked ? root.activeColor : Design.hover
    border.color: root.checked ? root.activeColor : Design.glassBorder
    border.width: 1
    opacity: enabled ? 1.0 : Design.opacity.disabled

    Behavior on color { ColorAnimation { duration: Design.duration.base } }
    Behavior on border.color { ColorAnimation { duration: Design.duration.base } }

    Rectangle {
        id: knob
        // Three quarters of the track, centred in it: the inset follows the
        // track's height instead of being a number of its own.
        width: Math.round(parent.height * 0.75)
        height: width
        radius: width / 2
        color: root.checked ? Design.accentText : Design.ground
        y: (parent.height - height) / 2
        x: root.checked ? parent.width - width - y : y

        Behavior on x { NumberAnimation { duration: Design.duration.base; easing.type: Design.easing } }
        Behavior on color { ColorAnimation { duration: Design.duration.base } }
    }

    Accessible.role: Accessible.CheckBox
    Accessible.name: root.accessibleName
    Accessible.checked: root.checked
    Accessible.focusable: enabled
    activeFocusOnTab: enabled

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
            if (root.enabled) {
                root.forceActiveFocus(Qt.MouseFocusReason);
                root.toggled();
            }
        }
    }

    Keys.onReturnPressed: function(event) {
        if (root.enabled) {
            root.toggled();
            event.accepted = true;
        }
    }

    Keys.onSpacePressed: function(event) {
        if (root.enabled) {
            root.toggled();
            event.accepted = true;
        }
    }

    FocusRing {
        target: root
        cornerRadius: root.radius + Design.s(Design.space.xxs)
    }
}
