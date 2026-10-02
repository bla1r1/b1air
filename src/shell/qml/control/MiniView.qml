import QtQuick
import QtQuick.Layouts
import "../Ui"

// =============================================================================
// The frame the four mini-settings pages repeat: back button, title, an
// optional trailing control, the page body, and a link into full Settings.
//
// It was written out four times — four back buttons, four hairlines, four
// footer rows, each with its own paddings and its own idea of the row height.
// =============================================================================

Item {
    id: root

    property string title: ""
    property string icon: ""
    property color tone: Design.accent
    property string footerLabel: I18n.tr("Settings…")

    // A switch or a badge that belongs beside the title.
    property alias trailing: trailingSlot.data
    default property alias content: contentSlot.data

    signal backClicked()
    signal openFullSettings()

    ColumnLayout {
        anchors.fill: parent
        spacing: Design.s(Design.space.sm)

        // ── Header ───────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.sm)

            IconButton {
                icon: "\u{f004d}"          // left arrow
                tone: Design.text
                hoverTone: root.tone
                onClicked: root.backClicked()
            }

            Icon {
                visible: root.icon !== ""
                text: root.icon
                role: "subhead"
                color: root.tone
            }

            Label {
                text: root.title
                role: "subhead"
                weight: Design.weight.bold
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            Item {
                id: trailingSlot
                implicitWidth: childrenRect.width
                implicitHeight: childrenRect.height
                Layout.alignment: Qt.AlignVCenter
            }
        }

        // ── Body ─────────────────────────────────────────────────────────────
        Item {
            id: contentSlot
            Layout.fillWidth: true
            Layout.fillHeight: true
        }

        // ── Footer ───────────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Design.border
            color: Design.glassBorder
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Design.s(Design.size.row)
            radius: Design.s(Design.radius.ctl)
            color: setMa.containsMouse ? Design.glassHover : "transparent"
            Behavior on color { ColorAnimation { duration: Design.duration.fast } }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Design.s(Design.space.sm)
                anchors.rightMargin: Design.s(Design.space.sm)
                spacing: Design.s(Design.space.sm)

                Label {
                    text: root.footerLabel
                    role: "body"
                    weight: Design.weight.medium
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                    color: setMa.containsMouse ? Design.accent : Design.text
                    Behavior on color { ColorAnimation { duration: Design.duration.fast } }
                }

                Icon {
                    text: "\u{f0142}"      // right chevron
                    role: "caption"
                    color: setMa.containsMouse ? Design.accent : Design.textDim
                    Behavior on color { ColorAnimation { duration: Design.duration.fast } }
                }
            }

            Clickable { id: setMa; onClicked: root.openFullSettings() }
        }
    }
}
