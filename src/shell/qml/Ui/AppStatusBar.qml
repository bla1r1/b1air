import QtQuick
import QtQuick.Layouts

// The strip along the bottom of an app window: counts, hints, what just
// happened. One height and one text size for all of them.
Rectangle {
    id: root
    default property alias content: row.data
    implicitHeight: Design.s(32)
    // The window's own colour shows through, rounded corners and all.
    color: "transparent"
    Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: Design.line }
    RowLayout {
        id: row
        anchors.fill: parent
        anchors.leftMargin: Design.s(Design.space.lg)
        anchors.rightMargin: Design.s(Design.space.md)
        spacing: Design.s(Design.space.md)
    }
}
