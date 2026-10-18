import QtQuick
import QtQuick.Layouts

// =============================================================================
// The one place an app says there is nothing here, it is still loading, or
// something went wrong: centred in the content, the toolbar and sidebar left
// where they are so it is clear where you are. Each app drew these by hand,
// each its own way, and most showed no loading or error at all.
//
//   AppState {
//       anchors.fill: parent
//       mode: model.error ? "error" : model.busy ? "loading" : model.count === 0 ? "empty" : ""
//       icon: "\u{f024b}"; title: I18n.tr("Folder is empty")
//       hint: I18n.tr("Drop files here or create a folder.")
//       actionText: I18n.tr("Retry"); onAction: model.reload()
//   }
//
// Nothing is drawn while `mode` is "". Loading shows only after 300 ms, so a
// fast answer does not flash a spinner.
// =============================================================================

Item {
    id: root

    property string mode: ""            // "" | "empty" | "loading" | "error"
    property string icon: ""
    property string title: ""
    property string hint: ""
    // A command that fixes it ("Retry", "Open folder…"): the error's way out,
    // or an empty state's first step.
    property string actionText: ""
    signal action()

    readonly property bool _shown: root.mode === "loading" ? delay.passed : root.mode !== ""
    visible: _shown

    Timer {
        id: delay
        property bool passed: false
        interval: 300
        running: root.mode === "loading"
        onRunningChanged: if (running) passed = false
        onTriggered: passed = true
    }

    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(parent.width - Design.s(Design.space.xl) * 2, Design.s(Design.width.dialog))
        spacing: Design.s(Design.space.sm)

        InlineStatus {
            visible: root.mode === "loading"
            Layout.alignment: Qt.AlignHCenter
            Layout.fillWidth: false
            status: "loading"
            message: root.title !== "" ? root.title : I18n.tr("Loading…")
            showRetry: false
        }

        EmptyState {
            visible: root.mode === "empty" || root.mode === "error"
            icon: root.mode === "error" && root.icon === "" ? "\u{f0028}" : root.icon
            title: root.title
            hint: root.hint
        }

        Button {
            visible: root.actionText !== "" && root.mode !== "loading"
            Layout.alignment: Qt.AlignHCenter
            text: root.actionText
            onClicked: root.action()
        }
    }
}
