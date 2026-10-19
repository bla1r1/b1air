import QtQuick
import B1air.Daemon

// =============================================================================
// One row of a list or a table, as a Mac's lists have them: the highlight
// is a rounded shape set in from the list's sides, not a band edge to edge,
// its corners by the corner rule (Shape: concentric with what the list sits
// in), its colours the states' (Design.state*). Every app drew its own — a
// zebra in Monitor, a band in Files, a rounded row in Git — and the same
// gesture looked different in each.
//
//   ListView {
//       delegate: ListRow {
//           striped: index % 2 === 1
//           selected: ListView.isCurrentItem
//           onClicked: …
//           RowLayout { anchors.fill: parent; … }   // inside the padding
//       }
//   }
//
// Its width is the list's; the content sits inside `padding` from the
// highlight's edge, so it lines up with a column header padded the same.
// A row that handles the pointer itself (a drag, a drop) says so —
// `handlesMouse: false; hovered: myArea.containsMouse` — and puts its areas
// in `overlay`, which covers the whole row under its content.
// =============================================================================

Item {
    id: root

    property bool selected: false
    // A quiet stripe on alternate rows, for a wide table read across.
    property bool striped: false
    // Something is being dropped on it, or it is picked without the focus.
    property bool highlight: false
    // Off where the row's own areas take the pointer; `hovered` and
    // `pressed` are then bound to them.
    property bool handlesMouse: true
    property bool hovered: handlesMouse && area.containsMouse
    property bool pressed: handlesMouse && area.pressed
    // How far the highlight is set in from the list's sides.
    property real inset: Design.s(Design.space.xs)
    // From the highlight's edge to the content.
    property real padding: Design.s(Design.space.sm)
    default property alias content: body.data
    property alias overlay: overlayItem.data

    signal clicked(var mouse)
    signal doubleClicked(var mouse)
    signal pressAndHold(var mouse)

    width: ListView.view ? ListView.view.width : implicitWidth
    implicitHeight: Design.s(Design.size.row)

    Rectangle {
        id: shape
        anchors.fill: parent
        anchors.leftMargin: root.inset
        anchors.rightMargin: root.inset
        // The corner rule gives the radius for what sits at the container's
        // padding; the highlight is a further `inset` in, so less that.
        radius: Shape.radius >= 0 ? Math.max(Design.s(Design.radius.sm), Shape.radius - root.inset)
                                  : Design.s(Design.radius.ctl)
        color: root.selected ? (root.hovered ? Design.stateSelectedStrong : Design.stateSelected)
             : root.highlight ? Design.stateSelectedSoft
             : root.pressed ? Design.statePressed
             : root.hovered ? Design.stateHover
             : root.striped ? Design.veil
             : "transparent"
        border.width: root.highlight && !root.selected ? Design.border : 0
        border.color: Design.accentLine
        Behavior on color { enabled: !Design.reduceMotion; ColorAnimation { duration: Design.duration.fast } }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        enabled: root.handlesMouse
        visible: root.handlesMouse
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => root.clicked(mouse)
        onDoubleClicked: mouse => root.doubleClicked(mouse)
        onPressAndHold: mouse => root.pressAndHold(mouse)
    }

    // Under the content, so a button in the row takes its own clicks and
    // the row's area gets the rest (labels take none).
    Item { id: overlayItem; anchors.fill: parent }

    Item {
        id: body
        anchors.fill: shape
        anchors.leftMargin: root.padding
        anchors.rightMargin: root.padding
    }
}
