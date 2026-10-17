import QtQuick

// =============================================================================
// Standalone macOS-style pill toggle switch.
// =============================================================================

Rectangle {
    id: root

    property bool checked: false
    property color activeColor: Design.accent
    signal toggled()

    implicitWidth: Design.s(42)
    implicitHeight: Design.s(24)
    radius: height / 2

    color: root.checked ? root.activeColor : Design.sunken
    border.color: root.checked ? root.activeColor : Design.glassBorder
    border.width: 1

    Behavior on color { ColorAnimation { duration: Design.duration.fast } }
    Behavior on border.color { ColorAnimation { duration: Design.duration.fast } }

    Rectangle {
        id: knob
        width: parent.height - Design.s(6)
        height: width
        radius: width / 2
        color: root.checked ? Design.accentText : Design.textDim
        y: Design.s(3)
        x: root.checked ? parent.width - width - Design.s(3) : Design.s(3)

        Behavior on x { NumberAnimation { duration: Design.duration.fast; easing.type: Design.easing } }
        Behavior on color { ColorAnimation { duration: Design.duration.fast } }
    }

    Clickable {
        anchors.fill: parent
        onClicked: root.toggled()
    }
}
