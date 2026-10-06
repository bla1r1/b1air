import QtQuick
import QtQuick.Layouts

// =============================================================================
// Label + minus / value / plus.
//
// Promoted from settings/components/StepperRow.qml. The two buttons were a
// copy-paste pair differing only in glyph and signal; now they are a Repeater
// over the two, so a change to one cannot drift from the other.
// =============================================================================

RowLayout {
    id: row

    property string label: ""
    property string valueText: ""
    signal decrement()
    signal increment()

    Layout.fillWidth: true
    spacing: Design.s(Design.space.md)

    // Like a switch's label: the row's name, in the text colour.
    Label {
        text: row.label
        Layout.fillWidth: true
        elide: Text.ElideRight
    }

    component StepButton: Rectangle {
        id: step
        property string glyph: ""
        signal activated()

        Layout.preferredWidth: Design.s(30)
        Layout.preferredHeight: Design.s(Design.size.field)
        radius: Design.s(Design.radius.ctl)

        color: stepArea.pressed ? Design.active : Design.raised
        border.color: stepArea.containsMouse ? Design.accent : "transparent"
        border.width: Design.border

        Behavior on color { ColorAnimation { duration: Design.duration.fast } }
        Behavior on border.color { ColorAnimation { duration: Design.duration.fast } }

        Label {
            anchors.centerIn: parent
            text: step.glyph
            role: "subhead"
            weight: Design.weight.bold
        }

        Clickable { id: stepArea; onClicked: step.activated() }
    }

    StepButton {
        glyph: "−"           // minus sign, not a hyphen
        onActivated: row.decrement()
    }

    Label {
        text: row.valueText
        weight: Design.weight.bold
        color: Design.accent
        horizontalAlignment: Text.AlignHCenter
        Layout.minimumWidth: Design.s(44)
    }

    StepButton {
        glyph: "+"
        onActivated: row.increment()
    }
}
