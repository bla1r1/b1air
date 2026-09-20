import QtQuick

// =============================================================================
// Small pill button, optionally part of a mutually exclusive group.
//
// Promoted from settings/components/PillButton.qml, plus the `active` state it
// never had — tab strips and option groups need it, and without it every caller
// would rebuild the same selected look by hand.
// =============================================================================

Rectangle {
    id: button

    property string label: ""
    property string icon: ""
    property bool active: false
    // The selected state: a soft tint of this colour, and the label in it.
    // Leave it on the accent unless the colour means something (danger, ok).
    property color activeColor: Design.accent
    signal clicked()

    // Same capsule as BarButton and ActionButton; field height, so a row of
    // options beside a text field lines up with it.
    // From the parts, not from contentRow: the label's width depends on the
    // button's, so going through the Row would loop back to zero.
    implicitWidth: (glyph.visible ? glyph.implicitWidth + contentRow.spacing : 0)
                   + text.implicitWidth + Design.s(Design.space.lg) * 2
    implicitHeight: Design.s(Design.size.field)
    radius: height / 2

    color: button.active ? Design.tint(button.activeColor, area.containsMouse ? 0.32 : 0.24)
                         : (area.containsMouse ? Design.glassHover : Design.glassCard)
    Behavior on color { ColorAnimation { duration: Design.duration.fast } }

    scale: area.pressed ? 0.96 : 1.0
    Behavior on scale { NumberAnimation { duration: Design.duration.fast; easing.type: Design.easing } }

    Row {
        id: contentRow
        anchors.centerIn: parent
        spacing: Design.s(Design.space.xs + 2)

        Icon {
            id: glyph
            visible: button.icon !== ""
            text: button.icon
            role: "body"
            anchors.verticalCenter: parent.verticalCenter
            color: button.active ? button.activeColor : Design.textDim
        }

        Label {
            id: text
            // Stretched or squeezed by a layout, the label shortens instead
            // of running past the capsule.
            width: Math.min(implicitWidth, Math.max(0, button.width - Design.s(Design.space.lg) * 2
                                                    - (glyph.visible ? glyph.implicitWidth + contentRow.spacing : 0)))
            elide: Text.ElideRight
            text: button.label
            anchors.verticalCenter: parent.verticalCenter
            weight: button.active ? Design.weight.semibold : Design.weight.regular
            color: button.active ? button.activeColor : Design.text
        }
    }

    Clickable { id: area; onClicked: button.clicked() }
}
