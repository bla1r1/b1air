import QtQuick
import QtQuick.Layouts

// =============================================================================
// A row of buttons, right-aligned and as wide as their labels.
//
//   ButtonRow {
//       ActionButton { label: "View Backups" }
//       ActionButton { label: "Update now"; tone: Design.ok }
//   }
//
// ActionButton fills its row by default, which suits the power row in the
// Control Center and nothing in Settings: there a lone "Create Restore Point"
// became a 700 px bar with a word in the middle, and two buttons split a card
// in half whatever they said. Here the buttons keep their own width and sit
// at the end of the row, where a dialog puts its actions.
// =============================================================================

RowLayout {
    id: root

    Layout.fillWidth: true
    spacing: Design.s(Design.space.sm)

    // Declared first, so the caller's buttons come after it.
    Item { Layout.fillWidth: true }

    Component.onCompleted: {
        for (let i = 0; i < root.children.length; ++i) {
            const c = root.children[i];
            if (c.label !== undefined && c.activated !== undefined)
                c.Layout.fillWidth = false;
        }
    }
}
