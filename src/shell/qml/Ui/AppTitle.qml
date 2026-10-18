import QtQuick
import QtQuick.Layouts

// =============================================================================
// The title in an app's toolbar: what is open, and one line under it saying
// where or what it is (a path, a branch, a size). Text and View each built
// this by hand, two labels in a column with their own sizes.
//
//   AppTitle { title: "notes.md"; subtitle: "~/Documents" }
// =============================================================================

ColumnLayout {
    id: root

    property string title: ""
    property string subtitle: ""
    // Unsaved changes: a dot after the name, as editors mark them.
    property bool modified: false

    Layout.fillWidth: true
    Layout.minimumWidth: 0
    spacing: 0

    Label {
        Layout.fillWidth: true
        text: root.title + (root.modified ? "  •" : "")
        weight: Design.weight.semibold
        elide: Text.ElideMiddle
    }
    Label {
        Layout.fillWidth: true
        visible: root.subtitle !== ""
        text: root.subtitle
        role: "caption"
        color: Design.textFaint
        elide: Text.ElideMiddle
    }
}
