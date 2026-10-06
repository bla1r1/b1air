import QtQuick
import QtQuick.Layouts

// =============================================================================
// Titled card on a panel.
//
// Promoted from settings/components/SettingsCard.qml, where it was invisible to
// every popup but the settings one. Lost on the way: a threaded `scaleFactor`
// property and five hardcoded hex colours.
//
//   Card {
//       title: "Раскладка"
//       Toggle { label: "Основной экран"; checked: true }
//   }
// =============================================================================

Rectangle {
    id: card

    property string title: ""
    // Kept for the callers, not drawn: a card is its title and its rows, as
    // a desktop's settings draw a group. The line of explanation under every
    // title and the glyph on a tinted tile beside it said again what the rows
    // say, and made every page read as a brochure.
    property string subtitle: ""
    property string icon: ""
    property color accentColor: "transparent"
    readonly property color tone: card.accentColor.a > 0 ? card.accentColor : Design.accent
    default property alias content: body.data

    Layout.fillWidth: true
    Layout.preferredHeight: contentColumn.implicitHeight + Design.s(Design.space.xl + Design.space.xs)

    radius: Design.s(Design.radius.card)
    color: Design.glassCard
    border.color: Design.glassBorder
    border.width: 1

    ColumnLayout {
        id: contentColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Design.s(Design.space.lg)
        spacing: Design.s(Design.space.md)

        RowLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.md)
            visible: card.title.length > 0

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Design.s(2)

                Label {
                    text: card.title
                    visible: text.length > 0
                    role: "subhead"
                    weight: Design.weight.semibold
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }


            }
        }

        ColumnLayout {
            id: body
            Layout.fillWidth: true
            spacing: Design.s(Design.space.sm)
        }
    }
}
