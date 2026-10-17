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
        { id: "lock",     icon: "\u{f023}", label: I18n.tr("Lock"),     key: "1", cmd: ["b1air-daemon", "power", "lock"] },
        { id: "suspend",  icon: "\u{f186}", label: I18n.tr("Sleep"),    key: "2", cmd: ["b1air-daemon", "power", "suspend"] },
        { id: "reboot",   icon: "\u{f021}", label: I18n.tr("Reboot"),   key: "3", cmd: ["b1air-daemon", "power", "reboot"] },
        { id: "poweroff", icon: "\u{f011}", label: I18n.tr("Shut Down"),key: "4", cmd: ["b1air-daemon", "power", "shutdown"] },
        { id: "logout",   icon: "\u{f08b}", label: I18n.tr("Log Out"),  key: "5", cmd: ["b1air-daemon", "power", "logout"] }
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
                weight: Design.weight.semibold
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
                    // One look for every action. Each used to light up in a
                    // colour of its own (sapphire, teal, yellow, red, mauve)
                    // and grow on hover; the colour said nothing about the
                    // action and the red one read as an error.
                    color: tile.isHovered ? Design.tint(Design.accent, 0.22) : Design.sunken
                    border.color: tile.isHovered ? Design.accent : Design.glassBorder
                    border.width: 1

                    Behavior on color { ColorAnimation { duration: Design.duration.fast } }
                    Behavior on border.color { ColorAnimation { duration: Design.duration.fast } }

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: Design.s(Design.space.sm)

                        // Key Number Badge
                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            width: Design.s(22); height: Design.s(22); radius: Design.s(11)
                            color: Design.well

                            Label {
                                anchors.centerIn: parent
                                text: tile.modelData.key
                                role: "caption"
                                tabular: true
                                color: Design.textDim
                            }
                        }

                        // Icon
                        Icon {
                            Layout.alignment: Qt.AlignHCenter
                            text: tile.modelData.icon
                            role: "display"
                            color: tile.isHovered ? Design.accent : Design.text
                        }

                        // Label
                        Label {
                            Layout.alignment: Qt.AlignHCenter
                            text: tile.modelData.label
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

            Button {
                label: I18n.tr("Cancel (Esc)")
                icon: "\u{f00d}"
                onClicked: window.close()
            }
        }
    }
}
