import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC

// =============================================================================
// Unified Popover component for overlays, dropdowns, and flyout menus.
//
// Positions relative to anchorItem, respects window margins, closes on Esc or
// click outside, and applies unified panel radius and border styling.
// =============================================================================

QQC.Popup {
    id: root

    property Item anchorItem: parent
    property real cornerRadius: Design.s(Design.radius.panel)
    property color backgroundColor: Design.raised
    property color borderColor: Design.line

    default property alias content: contentSlot.data

    parent: anchorItem || undefined
    padding: Design.s(Design.space.sm)
    margins: Design.s(Design.space.sm)

    closePolicy: QQC.Popup.CloseOnEscape | QQC.Popup.CloseOnPressOutsideParent

    // Calculate vertical position relative to anchor
    function updatePosition() {
        if (!anchorItem) return;
        const bottom = anchorItem.mapToItem(null, 0, anchorItem.height).y;
        const winHeight = (anchorItem.Window && anchorItem.Window.height) ? anchorItem.Window.height : 800;
        const roomBelow = winHeight - bottom - Design.s(Design.space.md);
        const popHeight = (root.contentHeight > 0 ? root.contentHeight : root.implicitHeight) + root.padding * 2;

        root.y = roomBelow >= popHeight
                 ? anchorItem.height + Design.s(Design.space.xs)
                 : -popHeight - Design.s(Design.space.xs);
    }

    onAboutToShow: updatePosition()

    background: Rectangle {
        radius: root.cornerRadius
        color: root.backgroundColor
        border.color: root.borderColor
        border.width: 1

        Rectangle {
            anchors.fill: parent
            anchors.margins: 1
            radius: Math.max(1, root.cornerRadius - 1)
            color: "transparent"
            border.color: Design.glassEdge
            border.width: 1
            visible: Design.translucent
        }
    }

    contentItem: Item {
        implicitWidth: contentSlot.implicitWidth
        implicitHeight: contentSlot.implicitHeight

        ColumnLayout {
            id: contentSlot
            anchors.fill: parent
            spacing: Design.s(Design.space.xs)
        }
    }
}
