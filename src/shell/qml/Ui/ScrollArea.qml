import QtQuick
import QtQuick.Controls

// =============================================================================
// ScrollView with the shell's scrollbar, in a bordered well.
//
// Every scrolling popup restyles ScrollBar.contentItem inline — same thin
// rounded bar, a different width and opacity each time.
//
//   ScrollArea {
//       Text { width: parent.width; text: "..."; wrapMode: Text.WordWrap }
//   }
// =============================================================================

Rectangle {
    id: root

    default property alias content: view.contentData
    readonly property real availableWidth: view.availableWidth

    property bool framed: true

    color: "transparent"
    border.color: root.framed ? Design.tint(Design.active, 0.4) : "transparent"
    border.width: root.framed ? Design.border : 0
    radius: Design.s(Design.radius.card)
    clip: true

    ScrollView {
        id: view
        anchors.fill: parent
        anchors.margins: Design.s(Design.space.lg)
        clip: true

        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
        // The suite's one bar (OverflowBar): this one was 3px at half
        // opacity, there to be seen and hard to take hold of.
        ScrollBar.vertical: OverflowBar {}
    }
}
