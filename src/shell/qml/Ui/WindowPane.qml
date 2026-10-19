import QtQuick
import B1air.Daemon

// =============================================================================
// A pane at the side of an app window, the Air way: a shape of its own, set
// in from the window's edges and rounded concentric with the window, beside
// the content rather than a strip of the window behind a hairline. A
// sidebar on the left (Ui/AppSidebar), an inspector on the right — Files'
// details — the same shape either side, so a window with both is one thing
// and not a card on one side and a band on the other.
//
// With blur it is the sidebar glass; without, a solid card one step up from
// the window, with the same hairline rim, so the shape is the same either
// way. What is put in it sits `padding` in, and takes its corners from the
// pane (Shape).
//
//   WindowPane { edge: Qt.RightEdge; Layout.fillHeight: true; implicitWidth: …
//       ColumnLayout { anchors.fill: parent; … }
//   }
// =============================================================================

Item {
    id: root
    // The window edge it stands against: Qt.LeftEdge or Qt.RightEdge.
    property int edge: Qt.LeftEdge
    // How far the pane sits in from the window's edges.
    readonly property real inset: Design.s(Design.space.sm)
    // From the pane's edge to what is in it.
    property real padding: Design.s(Design.space.xs)
    // How far in the rows that reach its sides sit, for the corner rule
    // (Shape.inset): the padding, unless the content pads itself — Git's
    // pane holds lists and a commit box laid out edge to edge, their rows
    // set in by their own margins.
    property real rowInset: padding
    // Clip what is in it to the pane (a list scrolled under its ends).
    property alias clipContent: body.clip
    // Its own name, so a pane made into something else (AppSidebar) can
    // have a default slot of its own and still fill this one.
    default property alias paneContent: body.data

    Rectangle {
        id: pane
        anchors.fill: parent
        anchors.leftMargin: root.edge === Qt.LeftEdge ? root.inset : 0
        anchors.rightMargin: root.edge === Qt.RightEdge ? root.inset : 0
        anchors.topMargin: root.inset
        anchors.bottomMargin: root.inset
        // Concentric with the window it is set into.
        radius: Design.s(Design.concentric(Design.radius.window, Design.space.sm))
        // What is in it, padding in from its edge: concentric with it.
        Shape.radius: radius
        Shape.inset: root.rowInset
        color: Design.translucent ? Design.glassSidebar : Design.raised
        border.width: Design.border
        border.color: Design.glassBorder

        Item {
            id: body
            anchors.fill: parent
            anchors.margins: root.padding
        }
    }
}
