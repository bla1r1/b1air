import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../Ui"
import "../Services"

// =============================================================================
// Notifications Mini View (Control Center Subpage)
//
// Was the one subpage of five that did not use MiniView: it hand-rolled the
// same header, with a different back-arrow glyph and a bordered button where
// the other four use a hover tone, and it was the only mini view with no way
// through to its own full settings page. Same frame as its siblings now.
// =============================================================================

MiniView {
    id: root

    title: "Notifications"
    icon: "\u{f009a}"
    tone: Design.lavender
    footerLabel: "Notification Settings…"

    // While this list is on screen, a toast repeating one of its lines is
    // noise — and toasts used to be drawn on top of it, because both surfaces
    // sat on the overlay layer and this one was created first.
    Component.onCompleted: Notifications.acquireList()
    Component.onDestruction: Notifications.releaseList()

    trailing: ActionButton {
        visible: Notifications.history.count > 0
        icon: "\u{f0156}"
        label: "Clear"
        onActivated: Notifications.clearAllHistory()
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Design.s(Design.space.md)

        // ── DND toggle ───────────────────────────────────────────────────────
        Card {
            Layout.fillWidth: true

            Toggle {
                label: "Do Not Disturb"
                subtitle: "Silence popups and store them in history"
                checked: Notifications.dnd
                onToggled: Notifications.toggleDnd()
            }
        }

        // ── History ──────────────────────────────────────────────────────────
        ListView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: Design.s(Design.space.xs)
            model: Notifications.history

            delegate: Rectangle {
                id: notifItem
                required property var model
                required property int index

                width: ListView.view ? ListView.view.width : 0
                implicitHeight: itemRow.implicitHeight + Design.s(Design.space.sm)
                radius: Design.s(Design.radius.card)
                color: Design.glassCard
                border.color: Design.glassBorder
                border.width: 1

                RowLayout {
                    id: itemRow
                    anchors.fill: parent
                    anchors.margins: Design.s(Design.space.sm)
                    spacing: Design.s(Design.space.sm)

                    Rectangle {
                        width: Design.s(32)
                        height: width
                        radius: Design.s(Design.radius.ctl)
                        color: Design.sunken
                        Layout.alignment: Qt.AlignTop

                        // The icon the notification came with (an image URL,
                        // Services/Notifications.qml), else the bell.
                        Image {
                            id: historyIcon
                            anchors.centerIn: parent
                            width: Design.s(18)
                            height: width
                            sourceSize: Qt.size(64, 64)
                            source: String(notifItem.model.icon || "").indexOf("://") >= 0 ? notifItem.model.icon : ""
                            visible: status === Image.Ready
                            fillMode: Image.PreserveAspectFit
                        }
                        Icon {
                            anchors.centerIn: parent
                            visible: !historyIcon.visible
                            text: "\u{f009a}"
                            role: "caption"
                            color: Design.sapphire
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        RowLayout {
                            Layout.fillWidth: true
                            Label {
                                text: notifItem.model.appName
                                role: "caption"
                                dim: true
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }
                            Label {
                                text: notifItem.model.time
                                role: "caption"
                                dim: true
                            }
                        }

                        Label {
                            text: notifItem.model.summary
                            weight: Design.weight.semibold
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        Label {
                            visible: notifItem.model.body !== ""
                            text: notifItem.model.body
                            role: "caption"
                            dim: true
                            maximumLineCount: 2
                            wrapMode: Text.WordWrap
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }

                    IconButton {
                        icon: "\u{f0156}"
                        role: "caption"
                        Layout.alignment: Qt.AlignTop
                        onClicked: Notifications.dismissHistoryItem(notifItem.index)
                    }
                }
            }

            // Empty state
            Label {
                anchors.centerIn: parent
                visible: Notifications.history.count === 0
                text: "No notifications"
                role: "body"
                dim: true
            }
        }
    }
}
