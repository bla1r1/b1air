import QtQuick
import QtQuick.Layouts
import "Ui"

// One row of a device's General tab: a label in the left column, aligned to
// the right, and what it is about beside it.
//
//   FilesDeviceRow { label: I18n.tr("Software"); Label { text: "2.0.5" } }
RowLayout {
    id: row
    property string label: ""
    default property alias content: body.data

    Layout.fillWidth: true
    spacing: Design.s(Design.space.lg)

    Label {
        Layout.preferredWidth: Design.s(150)
        Layout.alignment: Qt.AlignTop
        Layout.topMargin: Design.s(2)
        horizontalAlignment: Text.AlignRight
        text: row.label
        weight: Design.weight.semibold
    }
    ColumnLayout {
        id: body
        Layout.fillWidth: true
        spacing: Design.s(Design.space.sm)
    }
}
