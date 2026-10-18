import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
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

    // ── 3. Games ─────────────────────────────────────────────────────────────
    // Feral GameMode and MangoHud, which the gaming edition installs. What is
    // there is asked each time the page shows.
    property bool hasGamemode: false
    property bool hasMangohud: false
    property bool mangohudOn: false
    readonly property string gamingEnv: Quickshell.env("HOME") + "/.config/b1air/gaming.env"

    Process {
        running: section.visible
        command: ["sh", "-c", "command -v gamemoded >/dev/null && echo gamemode; command -v mangohud >/dev/null && echo mangohud; "
                 + "grep -qx 'MANGOHUD=1' \"$1\" 2>/dev/null && echo mangohud-on; true", "sh", section.gamingEnv]
        stdout: StdioCollector {
            onStreamFinished: {
                const words = this.text.split("\n");
                section.hasGamemode = words.indexOf("gamemode") >= 0;
                section.hasMangohud = words.indexOf("mangohud") >= 0;
                section.mangohudOn = words.indexOf("mangohud-on") >= 0;
            }
        }
    }

    SettingsGroup {
        visible: section.hasGamemode || section.hasMangohud
        title: I18n.tr("Games")

        SettingsRow {
            visible: section.hasGamemode
            label: I18n.tr("Turns on by itself")
            note: I18n.tr("A game that asks for GameMode turns this on, and off again when it quits. In Steam: add gamemoderun %command% to a game's launch options; Heroic and Lutris have a GameMode switch.")
        }

        SwitchRow {
            visible: section.hasMangohud
            label: I18n.tr("Performance overlay")
            note: I18n.tr("MangoHud in every game: frame rate, frame time, CPU and GPU. Right Shift+F12 hides it. From the next login.")
            checked: section.mangohudOn
            onToggled: {
                const on = !section.mangohudOn;
                section.mangohudOn = on;
                Quickshell.execDetached(["sh", "-c",
                    on ? "mkdir -p \"$(dirname \"$1\")\" && { grep -vx 'MANGOHUD=1' \"$1\" 2>/dev/null; echo MANGOHUD=1; } > \"$1.new\" && mv \"$1.new\" \"$1\""
                       : "[ -f \"$1\" ] && grep -vx 'MANGOHUD=1' \"$1\" > \"$1.new\"; mv \"$1.new\" \"$1\" 2>/dev/null; true",
                    "sh", section.gamingEnv]);
            }
        }
    }
}
