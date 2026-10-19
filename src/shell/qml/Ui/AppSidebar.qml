import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// The left column of an app window, the Air way: a pane of its own, rounded
// and set in from the window's edges, beside the content rather than a strip
// of the window behind a hairline. Files and Settings each drew their own
// with different widths, margins and headings; then it was a full-height
// square column, which beside the round rows, fields and buttons was the one
// square thing in the window — on a solid window (no blur) most of all.
//
// With blur it is the sidebar glass; without, a solid card one step up from
// the window, with the same hairline rim, so the shape is the same either
// way.
Item {
    id: root
    default property alias content: col.data
    property alias spacing: col.spacing
    // How far the pane sits in from the window's edges.
    readonly property real inset: Design.s(Design.space.sm)
    implicitWidth: Design.s(Design.width.sidebar) + inset

    Rectangle {
        id: pane
        anchors.fill: parent
        anchors.leftMargin: root.inset
        anchors.topMargin: root.inset
        anchors.bottomMargin: root.inset
        // Concentric with the window it is set into.
        radius: Design.s(Design.concentric(Design.radius.window, Design.space.sm))
        color: Design.translucent ? Design.glassSidebar : Design.raised
        border.width: Design.border
        border.color: Design.glassBorder

        // Scrolls when what it holds is taller than the window (Files' places,
        // devices, bookmarks and tags), with the same bar as the rest.
        Flickable {
            id: flick
            anchors.fill: parent
            anchors.topMargin: Design.s(Design.space.sm)
            anchors.bottomMargin: Design.s(Design.space.sm)
            anchors.leftMargin: Design.s(Design.space.xs)
            anchors.rightMargin: Design.s(Design.space.xs)
            contentWidth: width
            contentHeight: col.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            interactive: contentHeight > height
            ScrollBar.vertical: OverflowBar { id: bar }

            // Narrower by the bar when there is one, so it runs beside the
            // rows rather than over them.
            ColumnLayout {
                id: col
                width: flick.width - (bar.visible ? bar.width + Design.s(Design.space.xxs) : 0)
                spacing: Design.s(Design.space.xxs)
            }
        }
    }
}
