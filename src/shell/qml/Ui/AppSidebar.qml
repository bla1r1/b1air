import QtQuick
import QtQuick.Layouts

// The left column of an app window: sunken, behind a hairline. Files and
// Settings each drew their own with different widths, margins and headings.
Rectangle {
    id: root
    default property alias content: col.data
    property alias spacing: col.spacing
    implicitWidth: Design.s(224)
    color: Design.sunken
    Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Design.line }
    ColumnLayout {
        id: col
        anchors.fill: parent
        anchors.topMargin: Design.s(Design.space.md)
        anchors.bottomMargin: Design.s(Design.space.md)
        anchors.leftMargin: Design.s(Design.space.sm)
        anchors.rightMargin: Design.s(Design.space.sm) + 1
        spacing: Design.s(2)
    }
}
