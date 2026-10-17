import QtQuick
import QtQuick.Layouts

// One setting as a form lays it out in Windows and KDE: what it is on the
// left, with a line saying what it does, and the control on the right. A
// row too narrow for both puts the control under the text.
//
//   FormRow {
//       title: I18n.tr("Interface language")
//       subtitle: I18n.tr("Menus and apps of this desktop")
//       Dropdown { … }
//   }
GridLayout {
    id: root

    property string title: ""
    property string subtitle: ""
    default property alias content: slot.data
    readonly property bool narrow: width < Design.s(560)

    Layout.fillWidth: true
    columns: root.narrow ? 1 : 2
    columnSpacing: Design.s(Design.space.lg)
    rowSpacing: Design.s(Design.space.xs)

    ColumnLayout {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        Layout.topMargin: root.narrow ? 0 : Design.s(8)
        spacing: Design.s(2)
        Label {
            Layout.fillWidth: true
            text: root.title
            weight: Design.weight.semibold
            wrapMode: Text.WordWrap
        }
        Label {
            Layout.fillWidth: true
            visible: root.subtitle !== ""
            text: root.subtitle
            role: "caption"
            dim: true
            wrapMode: Text.WordWrap
        }
    }

    ColumnLayout {
        id: slot
        Layout.alignment: Qt.AlignTop | (root.narrow ? Qt.AlignLeft : Qt.AlignRight)
        Layout.fillWidth: root.narrow
        spacing: Design.s(Design.space.xs)
    }
}
