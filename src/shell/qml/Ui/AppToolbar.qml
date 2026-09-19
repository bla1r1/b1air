import QtQuick
import QtQuick.Layouts

// The bar across the top of an app window: one height, one colour, one rule
// under it, for every app. Children go into a row with the usual margins.
Rectangle {
    id: root
    default property alias content: row.data
    property alias spacing: row.spacing
    implicitHeight: Design.s(52)
    color: Design.surface
    Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Design.line }
    RowLayout {
        id: row
        anchors.fill: parent
        anchors.leftMargin: Design.s(Design.space.md)
        anchors.rightMargin: Design.s(Design.space.md)
        spacing: Design.s(Design.space.xs)
    }
}
