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
        visible: row.label !== ""
        text: row.label
        Layout.fillWidth: row.label !== ""
        elide: Text.ElideRight
    }

    component StepButton: Rectangle {
        id: step
        property string glyph: ""
        signal activated()

        Layout.preferredWidth: Design.s(Design.size.md)
        Layout.preferredHeight: Design.s(Design.size.md)
        radius: Design.s(Design.radius.ctl)

        color: Design.translucent
               ? (stepArea.pressed ? Design.tint(Design.text, 0.20) : (stepArea.containsMouse ? Design.veilBold : Design.well))
               : (stepArea.pressed ? Design.active : Design.raised)
        border.color: stepArea.containsMouse ? Design.accent : "transparent"
        border.width: Design.border

        Behavior on color { ColorAnimation { duration: Design.duration.fast } }
        Behavior on border.color { ColorAnimation { duration: Design.duration.fast } }

        Label {
            anchors.centerIn: parent
            text: step.glyph
            role: "subhead"
            weight: Design.weight.semibold
        }

        Clickable { id: stepArea; keyboard: false; onClicked: step.activated() }

        activeFocusOnTab: true
        Accessible.role: Accessible.Button
        Accessible.name: step.glyph
        Keys.onReturnPressed: event => { step.activated(); event.accepted = true; }
        Keys.onSpacePressed: event => { step.activated(); event.accepted = true; }
        FocusRing { target: step }
    }

    StepButton {
        glyph: "−"           // minus sign, not a hyphen
        onActivated: row.decrement()
    }

    Label {
        text: row.valueText
        // In the text colour: the accent marks what is chosen or in focus,
        // and a number in a stepper is neither.
        weight: Design.weight.medium
        tabular: true
        horizontalAlignment: Text.AlignHCenter
        Layout.minimumWidth: Design.s(Design.size.md + Design.space.md)
    }

    StepButton {
        glyph: "+"
        onActivated: row.increment()
    }
}
