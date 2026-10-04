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
            visible: card.title.length > 0 || card.subtitle.length > 0

            // The icon on a soft tile of its colour, as the system settings of
            // macOS and GNOME draw a section. It was a bare glyph beside a
            // coloured bar down the card's edge.
            Rectangle {
                visible: card.icon !== ""
                Layout.preferredWidth: Design.s(32)
                Layout.preferredHeight: Design.s(32)
                radius: Design.s(9)
                color: Design.tint(card.tone, 0.16)

                Icon {
                    anchors.centerIn: parent
                    text: card.icon
                    role: "body"
                    color: card.tone
                }
            }

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

                Label {
                    text: card.subtitle
                    visible: text.length > 0
                    role: "caption"
                    dim: true
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
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
