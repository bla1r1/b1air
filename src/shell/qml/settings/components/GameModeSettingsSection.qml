import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../Ui"
import "../../Services"

// =============================================================================
// Game Mode Settings (C++20 b1air-daemon backed)
// =============================================================================

ColumnLayout {
    id: section

    Layout.fillWidth: true
    spacing: Design.s(Design.space.lg)

    // Read-only views of Settings. These were writable copies that each
    // handler assigned to, which cut them loose from Settings: once toggled
    // here, Game Mode switched on from the Control Center or Mod+Shift+G no
    // longer showed on this page.
    readonly property bool gameModeEnabled: Settings.gameModeEnabled
    readonly property bool gameModeAdaptiveSync: Settings.gameModeAdaptiveSync
    readonly property bool gameModeHideBar: Settings.gameModeHideBar
    readonly property bool gameModeDND: Settings.gameModeDND

    function toggleGameMode(val) {
        Settings.set("gameModeEnabled", val);
        const daemonCmd = "b1air-daemon";
        Quickshell.execDetached([daemonCmd, "game-mode", val ? "on" : "off"]);
    }

    // ── 1. Master Switch ─────────────────────────────────────────────────────
    Card {
        title: I18n.tr("Game Mode Performance")
        subtitle: I18n.tr("Optimize system responsiveness, disable desktop overhead, and maximize FPS")
        icon: "\u{f11b}"
        accentColor: Design.danger

        RowLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.md)

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Design.s(2)
                Label { text: I18n.tr("Enable Game Mode") }
            }

            Toggle {
                checked: section.gameModeEnabled
                onToggled: section.toggleGameMode(!section.gameModeEnabled)
            }
        }
    }

    // ── 2. Display & Desktop Options ─────────────────────────────────────────
    Card {
        title: I18n.tr("Display & Desktop Overlays")
        subtitle: I18n.tr("Configurable behaviors applied when Game Mode is active")
        icon: "\u{f108}"
        accentColor: Design.sapphire

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.md)

            RowLayout {
                Layout.fillWidth: true
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Design.s(2)
                    Label { text: I18n.tr("Adaptive Sync (VRR)"); weight: Design.weight.medium }
                    Label { text: I18n.tr("Enable Variable Refresh Rate on supported gaming monitors"); role: "caption"; dim: true }
                }
                Toggle {
                    checked: section.gameModeAdaptiveSync
                    onToggled: {
                        Settings.set("gameModeAdaptiveSync", !section.gameModeAdaptiveSync);
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Design.s(1)
                color: Design.line
            }

            RowLayout {
                Layout.fillWidth: true
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Design.s(2)
                    Label { text: I18n.tr("Hide Top Bar"); weight: Design.weight.medium }
                    Label { text: I18n.tr("Automatically hide top status bar during gaming sessions"); role: "caption"; dim: true }
                }
                Toggle {
                    checked: section.gameModeHideBar
                    onToggled: {
                        Settings.set("gameModeHideBar", !section.gameModeHideBar);
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Design.s(1)
                color: Design.line
            }

            RowLayout {
                Layout.fillWidth: true
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Design.s(2)
                    Label { text: I18n.tr("Do Not Disturb (DND)"); weight: Design.weight.medium }
                    Label { text: I18n.tr("Mute all popups and toast notifications while in game"); role: "caption"; dim: true }
                }
                Toggle {
                    checked: section.gameModeDND
                    onToggled: {
                        Settings.set("gameModeDND", !section.gameModeDND);
                    }
                }
            }
        }
    }
}
