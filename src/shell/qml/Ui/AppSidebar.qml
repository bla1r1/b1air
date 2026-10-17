import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// The left column of an app window: sunken, behind a hairline. Files and
// Settings each drew their own with different widths, margins and headings.
Rectangle {
    id: root
    default property alias content: col.data
    property alias spacing: col.spacing
    implicitWidth: Design.s(Design.width.sidebar)
    // The same glass as the Settings sidebar: a pane of the window, not a
    // dark slab beside it.
    color: Design.translucent ? Design.glassSidebar : Design.sunken
    Rectangle { anchors.right: parent.right; width: Design.border; height: parent.height; color: Design.separator }
    // Scrolls when what it holds is taller than the window (Files' places,
    // devices, bookmarks and tags), with the same bar as the rest.
    Flickable {
        id: flick
        anchors.fill: parent
        anchors.topMargin: Design.s(Design.space.md)
        anchors.bottomMargin: Design.s(Design.space.md)
        anchors.leftMargin: Design.s(Design.space.sm)
        anchors.rightMargin: Design.s(Design.space.sm) + Design.border
        contentWidth: width
        contentHeight: col.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: contentHeight > height
        ScrollBar.vertical: OverflowBar { view: flick }

        ColumnLayout {
            id: col
            width: flick.width
            spacing: Design.s(Design.space.xxs)
        }
    }
}
