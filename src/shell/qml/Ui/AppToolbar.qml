import QtQuick
import QtQuick.Layouts

// The top of an app window. Not a bar: it has the window's own colour and no
// rule under it, so the content starts at the top edge and the controls float
// in BarGroup capsules. An earlier header strip — app icon, app name, a line —
// was dropped for saying nothing the window manager does not already say;
// this keeps the controls and loses the strip.
Item {
    id: root
    default property alias content: row.data
    property alias spacing: row.spacing
    implicitHeight: Design.s(50)
    RowLayout {
        id: row
        anchors.fill: parent
        anchors.leftMargin: Design.s(Design.space.md)
        anchors.rightMargin: Design.s(Design.space.md)
        anchors.topMargin: Design.s(Design.space.sm)
        anchors.bottomMargin: Design.s(Design.space.xs)
        spacing: Design.s(Design.space.sm)
    }
}
