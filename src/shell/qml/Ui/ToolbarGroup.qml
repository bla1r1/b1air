import QtQuick
import QtQuick.Layouts

// =============================================================================
// A group of toolbar buttons on a capsule of liquid glass, as a Mac's toolbar
// has them (HIG: Toolbars): related controls together, floating over the
// content that scrolls under the bar (Ui/ScrollEdge). The same inset on every
// side, so a round button inside is concentric with the capsule; give the
// buttons `radius: height / 2`.
//
// `backdrop` is what scrolls under the toolbar, an item the group is not
// inside of. Without a GPU, or with Reduce Transparency, a plain capsule.
//
//   ToolbarGroup {
//       backdrop: content
//       Button { variant: "ghost"; iconOnly: true; radius: height / 2; icon: "…" }
//   }
// =============================================================================

ToolbarGlass {
    id: group

    default property alias buttons: row.data
    property alias spacing: row.spacing
    readonly property real inset: Design.s(Design.space.xxs)

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
