import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../Ui"
import "../../Services"

// =============================================================================
// Native Quickshell Top Bar Settings
// =============================================================================

ColumnLayout {
    id: section

    Layout.fillWidth: true
    spacing: Design.s(Design.space.lg)

    // ── Clock ────────────────────────────────────────────────────────────────
    SettingsGroup {
        title: I18n.tr("Clock")

        SwitchRow {
            label: I18n.tr("24-hour time")
            note: Settings.barClock24h ? "14:30" : I18n.tr("2:30 PM")
            checked: Settings.barClock24h
            onToggled: Settings.set("barClock24h", !Settings.barClock24h)
        }
    }

    // ── Workspaces ───────────────────────────────────────────────────────────
    SettingsGroup {
        title: I18n.tr("Workspaces")

        SettingsRow {
            label: I18n.tr("Workspace count")

            Stepper {
                valueText: Settings.workspaceCount.toString()
                onDecrement: Settings.set("workspaceCount", Math.max(1, Settings.workspaceCount - 1))
                onIncrement: Settings.set("workspaceCount", Math.min(20, Settings.workspaceCount + 1))
            }
        }
    }

    // ── Multiple Monitors ────────────────────────────────────────────────────
    SettingsGroup {
        visible: Quickshell.screens && Quickshell.screens.length > 1
        title: I18n.tr("Multiple Displays")

        SwitchRow {
            label: I18n.tr("Shorter bars on other screens")
            note: I18n.tr("The weather, the media title, the tray and the CPU island stay on the main screen; the others keep their workspaces, the clock and the system controls")
            checked: Settings.barSecondaryReduced
            onToggled: Settings.set("barSecondaryReduced", !Settings.barSecondaryReduced)
        }

        SettingsRow {
            label: I18n.tr("Main screen")
            note: I18n.tr("The same choice as Main display in Displays: it also gets workspace 1 and the focus at login. Automatic uses the first screen the compositor reports; naming one keeps it across replugs.")

            Select {
                Layout.preferredWidth: Design.s(Design.width.control)
                model: [{ id: "", label: I18n.tr("Automatic") }].concat(
                    (Quickshell.screens || []).map(s => ({ id: s.name, label: s.name }))
                )
                current: Settings.barPrimaryOutput || ""
                onPicked: id => Settings.set("barPrimaryOutput", id)
            }
        }
    }
}
