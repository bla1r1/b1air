import QtQuick
import B1air.Daemon
import QtQuick.Layouts

// =============================================================================
// A group of toolbar buttons on a capsule of liquid glass, as a Mac's toolbar
// has them (HIG: Toolbars): related controls together, floating over the
// content that scrolls under the bar (Ui/ScrollEdge). The same inset on every
// side, and the buttons inside take the capsule's radius less it (Shape), so
// they are concentric with it.
//
// `backdrop` is what scrolls under the toolbar, an item the group is not
// inside of. Without a GPU, or with Reduce Transparency, a plain capsule.
//
//   ToolbarGroup {
//       backdrop: content
//       Button { variant: "ghost"; iconOnly: true; icon: "…" }
//   }
// =============================================================================

ToolbarGlass {
    id: group

    default property alias buttons: row.data
    property alias spacing: row.spacing
    readonly property real inset: Design.s(Design.space.xxs)
    Shape.inset: group.inset

    implicitWidth: row.implicitWidth + 2 * group.inset
    implicitHeight: row.implicitHeight + 2 * group.inset
    Layout.preferredWidth: implicitWidth
    Layout.preferredHeight: implicitHeight

    RowLayout {
        id: row
        x: group.inset
        y: group.inset
        spacing: Design.s(Design.space.xxs)
    }
}
