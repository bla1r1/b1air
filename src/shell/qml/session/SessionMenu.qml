import QtQuick
import QtQuick.Layouts
import Quickshell
import "../Ui"

// =============================================================================
// Session / Power Menu
// =============================================================================

PopupShell {
    id: window

    padding: Design.space.xl

    property int selectedIndex: 0

    readonly property var actions: [
        { id: "lock",     icon: "\u{f023}", label: I18n.tr("Lock"),     key: "1", color: Design.sapphire, cmd: ["b1air-daemon", "power", "lock"] },
        { id: "suspend",  icon: "\u{f186}", label: I18n.tr("Sleep"),    key: "2", color: Design.teal,     cmd: ["b1air-daemon", "power", "suspend"] },
        { id: "reboot",   icon: "\u{f021}", label: I18n.tr("Restart"),  key: "3", color: Design.yellow,   cmd: ["b1air-daemon", "power", "reboot"] },
        { id: "poweroff", icon: "\u{f011}", label: I18n.tr("Shut Down"),key: "4", color: Design.red,      cmd: ["b1air-daemon", "power", "shutdown"] },
        { id: "logout",   icon: "\u{f08b}", label: I18n.tr("Log Out"),  key: "5", color: Design.mauve,    cmd: ["b1air-daemon", "power", "logout"] }
    ]

    function executeAction(idx) {
        if (idx >= 0 && idx < actions.length) {
            const item = actions[idx];
            window.close();
            Quickshell.execDetached(item.cmd);
        }
    }

    // Keyboard navigation
    Shortcut { sequence: "1"; onActivated: window.executeAction(0) }
    Shortcut { sequence: "2"; onActivated: window.executeAction(1) }
    Shortcut { sequence: "3"; onActivated: window.executeAction(2) }
    Shortcut { sequence: "4"; onActivated: window.executeAction(3) }
    Shortcut { sequence: "5"; onActivated: window.executeAction(4) }

    Shortcut { sequence: "Left"; onActivated: window.selectedIndex = Math.max(0, window.selectedIndex - 1) }
    Shortcut { sequence: "Right"; onActivated: window.selectedIndex = Math.min(window.actions.length - 1, window.selectedIndex + 1) }
    Shortcut { sequence: "Return"; onActivated: window.executeAction(window.selectedIndex) }

    ColumnLayout {
        anchors.fill: parent
        spacing: Design.s(Design.space.xl)

        // Header
        ColumnLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Design.s(4)

            Label {
                Layout.alignment: Qt.AlignHCenter
                text: I18n.tr("Power & Session")
                role: "title"
                weight: Design.weight.bold
            }

            Label {
                Layout.alignment: Qt.AlignHCenter
                text: I18n.tr("Choose a power action or press 1–5")
                role: "caption"
                dim: true
            }
        }

        // Action Tiles Row
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Design.s(Design.space.md)

            Repeater {
                model: window.actions

                delegate: Rectangle {
                    id: tile
                    required property var modelData
                    required property int index

                    Layout.preferredWidth: Design.s(105)
                    Layout.preferredHeight: Design.s(120)
                    radius: Design.s(Design.radius.card)

                    readonly property bool isHovered: tileMa.containsMouse || window.selectedIndex === tile.index
                    color: tile.isHovered ? Design.tint(tile.modelData.color, 0.18) : Design.sunken
                    border.color: tile.isHovered ? tile.modelData.color : Design.raised
                    border.width: tile.isHovered ? 2 : 1
                    scale: tile.isHovered ? 1.04 : 1.0

                    Behavior on color { ColorAnimation { duration: Design.duration.fast } }
                    Behavior on border.color { ColorAnimation { duration: Design.duration.fast } }
                    Behavior on scale { NumberAnimation { duration: Design.duration.fast; easing.type: Easing.OutBack } }

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: Design.s(Design.space.sm)

                        // Key Number Badge
                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            width: Design.s(22); height: Design.s(22); radius: Design.s(11)
                            color: tile.isHovered ? tile.modelData.color : Design.raised

                            Label {
                                anchors.centerIn: parent
                                text: tile.modelData.key
                                role: "caption"
                                weight: Design.weight.bold
                                color: tile.isHovered ? Design.surface : Design.textDim
                            }
                        }

                        // Icon
                        Icon {
                            Layout.alignment: Qt.AlignHCenter
                            text: tile.modelData.icon
                            role: "hero"
                            color: tile.isHovered ? tile.modelData.color : Design.text
                        }

                        // Label
                        Label {
                            Layout.alignment: Qt.AlignHCenter
                            text: tile.modelData.label
                            weight: Design.weight.semibold
                            color: tile.isHovered ? Design.text : Design.textDim
                        }
                    }

                    Clickable {
                        id: tileMa
                        hoverEnabled: true
                        onClicked: window.executeAction(tile.index)
                    }
                }
            }
        }

        // Cancel Button Footer
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Design.s(Design.space.sm)

            Pill {
                label: I18n.tr("Cancel (Esc)")
                icon: "\u{f00d}"
                onClicked: window.close()
            }
        }
    }
}
