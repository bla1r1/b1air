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

    // ── 1. Position & Layout ─────────────────────────────────────────────────
    // The module switches that were here are on the Widgets page now,
    // alongside the four bar modules that had none and the Control Center
    // and calendar parts. Three of one list here and four of it there is
    // how two lists of the same thing drift apart. This page keeps how the
    // bar behaves — where it sits, how it tells the time; the other keeps
    // what it shows.

    // Used to live alone on its own "Interface Scale" page, back when it sat
    // next to a UI scale slider — that slider is gone (scale now follows the
    // display's own scale, set from Displays), leaving a page with nothing
    // but this one control. It's a bar setting; it belongs with the rest.
    // The bar has always read barClock24h and nothing on any page could set
    // it, so a 12-hour clock needed a hand edit of settings.json.
    Card {
        title: I18n.tr("Clock")
        subtitle: I18n.tr("How the time in the bar is written")
        icon: "\u{f0954}"
        accentColor: Design.blue

        Toggle {
            label: I18n.tr("24-hour time")
            subtitle: Settings.barClock24h ? "14:30" : I18n.tr("2:30 PM")
            checked: Settings.barClock24h
            onToggled: Settings.set("barClock24h", !Settings.barClock24h)
        }
    }

    Card {
        title: I18n.tr("Workspaces")
        subtitle: I18n.tr("How many workspace numbers the bar shows")
        icon: "\u{f0b60}"
        accentColor: Design.blue

        Stepper {
            label: I18n.tr("Workspace count")
            valueText: Settings.workspaceCount.toString()
            onDecrement: Settings.set("workspaceCount", Math.max(1, Settings.workspaceCount - 1))
            onIncrement: Settings.set("workspaceCount", Math.min(20, Settings.workspaceCount + 1))
        }
    }

    // ── Multiple monitors ────────────────────────────────────────────────────
    //
    // Absent on a single-screen desktop, where every control in it would be a
    // question about a situation that does not exist.
    Card {
        visible: Quickshell.screens && Quickshell.screens.length > 1
        title: I18n.tr("Multiple Monitors")
        subtitle: I18n.tr("Which screen carries the full bar, and what the others show")
        icon: "\u{f0379}"
        accentColor: Design.blue

        RowLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.md)

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Design.s(2)
                Label { Layout.fillWidth: true; text: I18n.tr("Shorter bars on other screens"); weight: Design.weight.semibold }
                Label {
                    Layout.fillWidth: true
                    text: I18n.tr("The weather, the media title, the tray and the CPU island stay on the main screen; the others keep their workspaces, the clock and the system controls")
                    role: "caption"; dim: true; wrapMode: Text.WordWrap
                }
            }

            Toggle {
                checked: Settings.barSecondaryReduced
                onToggled: Settings.set("barSecondaryReduced", !Settings.barSecondaryReduced)
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.xs)

            Label { text: I18n.tr("Main screen"); weight: Design.weight.semibold }

            Flow {
                Layout.fillWidth: true
                spacing: Design.s(Design.space.xs)

                Pill {
                    label: I18n.tr("Automatic")
                    active: Settings.barPrimaryOutput === ""
                    onClicked: Settings.set("barPrimaryOutput", "")
                }

                Repeater {
                    model: Quickshell.screens
                    delegate: Pill {
                        required property var modelData
                        label: modelData.name
                        active: Settings.barPrimaryOutput === modelData.name
                        onClicked: Settings.set("barPrimaryOutput", modelData.name)
                    }
                }
            }

            Label {
                Layout.fillWidth: true
                text: I18n.tr("The same choice as Main display in Displays: it also gets workspace 1 and the focus at login. Automatic uses the first screen the compositor reports; naming one keeps it across replugs.")
                role: "caption"; dim: true; wrapMode: Text.WordWrap
            }
        }
    }
}
