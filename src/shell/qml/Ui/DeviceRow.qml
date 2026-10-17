import QtQuick
import QtQuick.Layouts

// =============================================================================
// Name / detail / value row for a device list.
//
// Promoted from settings/components/DeviceRow.qml. Its 9px subtitle went up to
// the caption step — below 11 the mono face stops being legible, which is why
// it kept being special-cased.
// =============================================================================

Rectangle {
    id: row

    property string title: ""
    property string subtitle: ""
    property string value: ""
    property color valueTone: Design.accent

    Layout.fillWidth: true
    Layout.preferredHeight: Design.s(Design.size.rowTall)

    radius: Design.s(Design.radius.ctl)
    color: Design.sunken
    border.color: Design.line
    border.width: Design.border

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Design.s(Design.space.md)
        anchors.rightMargin: Design.s(Design.space.md)
        spacing: Design.s(Design.space.md)

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            Label {
                text: row.title
                role: "caption"
                weight: Design.weight.semibold
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            Label {
                text: row.subtitle
                visible: text.length > 0
                role: "caption"
                dim: true
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
        }

        Label {
            text: row.value
            role: "caption"
            weight: Design.weight.semibold
            color: row.valueTone
        }
    }
}
