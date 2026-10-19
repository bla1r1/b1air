import QtQuick
import QtQuick.Layouts

// The top of an app window. Not a bar: it has the window's own colour and no
// rule under it, so the content starts at the top edge and the controls float
// as Buttons in rows. An earlier header strip — app icon, app name, a line —
// was dropped for saying nothing the window manager does not already say;
// this keeps the controls and loses the strip.
Item {
    id: root
    default property alias content: row.data
    // Content is scrolled under it (bind to its Ui/ScrollEdge's
    // scrolledUnder): the glass on it takes a body then — bends what is
    // under, casts a shadow — and is a light film of the window otherwise.
    property bool over: false
    readonly property bool isAppToolbar: true
    property alias spacing: row.spacing
    implicitHeight: Design.s(Design.size.rowTall)

    // The hairline under it, matching the one over AppStatusBar: the
    // toolbar is chrome, and where it ends should show.
    property bool rule: true
    Rectangle {
        visible: root.rule
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Design.border
        color: Design.separator
    }
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
