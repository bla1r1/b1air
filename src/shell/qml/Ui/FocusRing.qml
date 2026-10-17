import QtQuick

// =============================================================================
// Keyboard focus ring.
//
// 2px accent outline offset by 2px from the focused control.
// Shown whenever the control holds active keyboard focus.
// =============================================================================

Rectangle {
    id: root

    property Item target: parent
    property real cornerRadius: target && target.radius !== undefined
                                ? target.radius + Design.s(Design.space.xxs)
                                : Design.s(Design.radius.ctl + 2)
    property real offset: Design.s(Design.space.xxs)
    property bool active: target ? target.activeFocus : false

    anchors.fill: target
    anchors.margins: -root.offset
    z: 99

    color: "transparent"
    border.width: Design.s(Design.focusWidth)
    border.color: Design.focusRing
    radius: root.cornerRadius

    visible: opacity > 0
    opacity: root.active ? 1.0 : 0.0

    Behavior on opacity {
        NumberAnimation { duration: Design.duration.fast }
    }
}
