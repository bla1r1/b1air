import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import B1air.Daemon
import "../Ui"

// =============================================================================
// FancyZones Visual Window Snapping Grid HUD (Super + Z)
// =============================================================================

PopupShell {
    id: root

    padding: Design.s(Design.space.lg)

    function snapToZone(id) {
        Daemon.zonesApply(id);
        root.close();
    }

    focus: true
    Keys.onEscapePressed: root.close()
    Keys.onDigit1Pressed: snapToZone(1)
    Keys.onDigit2Pressed: snapToZone(2)
    Keys.onDigit3Pressed: snapToZone(3)
    Keys.onDigit4Pressed: snapToZone(4)
    Keys.onDigit5Pressed: snapToZone(5)
    Keys.onDigit6Pressed: snapToZone(6)
    Keys.onDigit7Pressed: snapToZone(7)
    Keys.onDigit8Pressed: snapToZone(8)
    Keys.onDigit9Pressed: snapToZone(9)

    ColumnLayout {
        anchors.fill: parent
        spacing: Design.s(Design.space.md)

        // ── Header ────────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.sm)

            Icon {
                text: "\u{f009}" // th-large / grid
                role: "subhead"
                color: Design.accent
            }

            Label {
                text: I18n.tr("FancyZones Snapping Grid")
                role: "subhead"
                weight: Design.weight.bold
            }

            Item { Layout.fillWidth: true }

            Badge {
                text: I18n.tr("Press 1–9 or Click")
                tone: Design.accent
            }
        }

        // ── Zones Grid ────────────────────────────────────────────────────────
        GridLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            columns: 3
            columnSpacing: Design.s(Design.space.sm)
            rowSpacing: Design.s(Design.space.sm)

            readonly property var zones: [
                { id: 1, name: "Left 1/2", desc: I18n.tr("Half split"), key: "1", icon: "\u{f038}" },
                { id: 2, name: "Right 1/2", desc: I18n.tr("Half split"), key: "2", icon: "\u{f037}" },
                { id: 3, name: "Left 1/3", desc: I18n.tr("Ternary left"), key: "3", icon: "\u{f038}" },
                { id: 4, name: "Mid 1/3", desc: I18n.tr("Ternary center"), key: "4", icon: "\u{f039}" },
                { id: 5, name: "Right 1/3", desc: I18n.tr("Ternary right"), key: "5", icon: "\u{f037}" },
                { id: 6, name: "Left 2/3", desc: I18n.tr("Broad master"), key: "6", icon: "\u{f038}" },
                { id: 7, name: "Right 2/3", desc: I18n.tr("Broad master"), key: "7", icon: "\u{f037}" },
                { id: 8, name: "Top 1/2", desc: I18n.tr("Horizontal top"), key: "8", icon: "\u{f077}" },
                { id: 9, name: "Bottom 1/2", desc: I18n.tr("Horizontal bottom"), key: "9", icon: "\u{f078}" }
            ]

            Repeater {
                model: parent.zones

                delegate: Rectangle {
                    id: zoneTile
                    required property var modelData

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Design.s(Design.radius.card)
                    color: tileHover.containsMouse ? Design.tint(Design.accent, 0.18) : Design.sunken
                    border.color: tileHover.containsMouse ? Design.accent : Design.glassBorder
                    border.width: 1

                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: Design.s(Design.space.xs)

                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: Design.s(Design.space.xs)

                            Badge {
                                text: zoneTile.modelData.key
                                tone: Design.accent
                            }

                            Icon {
                                text: zoneTile.modelData.icon
                                role: "body"
                                color: Design.accent
                            }
                        }

                        Label {
                            text: zoneTile.modelData.name
                            role: "body"
                            weight: Design.weight.bold
                            Layout.alignment: Qt.AlignHCenter
                        }

                        Label {
                            text: zoneTile.modelData.desc
                            role: "caption"
                            dim: true
                            Layout.alignment: Qt.AlignHCenter
                        }
                    }

                    MouseArea {
                        id: tileHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.snapToZone(zoneTile.modelData.id)
                    }
                }
            }
        }
    }
}
