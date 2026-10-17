import QtQuick

// =============================================================================
// Status pill: tinted fill, matching border, mono caption.
//
// Popups build this by hand with Qt.rgba(c.r, c.g, c.b, 0.1) for the fill and
// 0.2 for the border, each picking its own alpha. Two alphas, decided once.
//
//   Badge { text: "NEW UPDATE AVAILABLE"; tone: Design.ok }
// =============================================================================

Item {
    id: root

    property alias text: label.text
    property color tone: Design.accent
    property alias color: root.tone

    implicitWidth: bg.implicitWidth
    implicitHeight: bg.implicitHeight

    Rectangle {
        id: bg
        anchors.fill: parent
        implicitWidth: label.implicitWidth + Design.s(Design.space.xl)
        implicitHeight: label.implicitHeight + Design.s(Design.space.md)

        radius: height / 2
        color: Design.tint(root.tone, 0.18)
        border.color: Design.tint(root.tone, 0.40)
        border.width: 1

        Text {
            id: label
            anchors.centerIn: parent
            font.family: Design.font.mono
            font.weight: Design.weight.semibold
            font.pixelSize: Design.s(Design.font.caption)
            color: root.tone
        }
    }
}
