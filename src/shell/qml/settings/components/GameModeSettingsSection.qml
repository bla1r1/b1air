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
    SettingsGroup {
        SwitchRow {
            label: I18n.tr("Enable Game Mode")
            checked: section.gameModeEnabled
            onToggled: section.toggleGameMode(!section.gameModeEnabled)
        }
    }

    // ── 2. Display & Desktop Options ─────────────────────────────────────────
    SettingsGroup {
        title: I18n.tr("Display & Desktop Overlays")
        icon: "\u{f108}"

        SwitchRow {
            label: I18n.tr("Adaptive Sync (VRR)")
            note: I18n.tr("Enable Variable Refresh Rate on supported gaming monitors")
            checked: section.gameModeAdaptiveSync
            onToggled: Settings.set("gameModeAdaptiveSync", !section.gameModeAdaptiveSync)
        }
        SwitchRow {
            label: I18n.tr("Hide Top Bar")
            note: I18n.tr("Automatically hide top status bar during gaming sessions")
            checked: section.gameModeHideBar
            onToggled: Settings.set("gameModeHideBar", !section.gameModeHideBar)
        }
        SwitchRow {
            label: I18n.tr("Do Not Disturb (DND)")
            note: I18n.tr("Mute all popups and toast notifications while in game")
            checked: section.gameModeDND
            onToggled: Settings.set("gameModeDND", !section.gameModeDND)
        }
    }
}
