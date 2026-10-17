import QtQuick
import QtQuick.Layouts
import Quickshell
import B1air.Daemon
import "../../Ui"
import "../../Services"

// =============================================================================
// Animations & Effects
// =============================================================================

ColumnLayout {
    id: section

    Layout.fillWidth: true
    spacing: Design.s(Design.space.lg)

    readonly property bool off: Settings.animationDuration === 0

    // ── Motion ───────────────────────────────────────────────────────────────
    SettingsGroup {
        title: I18n.tr("Motion")
        description: section.off ? I18n.tr("Animations are off") : ""

        SwitchRow {
            label: I18n.tr("Animations")
            note: I18n.tr("Off makes every change instant: windows, workspaces, the swipe")
            checked: !section.off
            onToggled: Settings.set("animationDuration", section.off ? 200 : 0)
        }

        SettingsRow {
            visible: !section.off
            label: I18n.tr("Duration")
            note: I18n.tr("%1 ms", Settings.animationDuration)

            Slider {
                Layout.preferredWidth: Design.s(Design.width.control)
                minimum: 80
                maximum: 600
                value: Math.max(80, Settings.animationDuration)
                onMoved: pct => Settings.set("animationDuration", Math.round(pct))
            }
        }
    }

    // ── Workspaces ───────────────────────────────────────────────────────────
    SettingsGroup {
        title: I18n.tr("Workspaces")

        SettingsRow {
            label: I18n.tr("Transition")
            note: Settings.workspaceAnimation === "fade"
                ? I18n.tr("The old workspace fades into the new one")
                : I18n.tr("Both slide sideways; the touchpad swipe moves them with your fingers")

            SegmentedControl {
                size: "sm"
                Layout.preferredWidth: Design.s(Design.width.control)
                model: [
                    { id: "slide", label: I18n.tr("Slide") },
                    { id: "fade",  label: I18n.tr("Fade") }
                ]
                current: Settings.workspaceAnimation
                onPicked: id => Settings.set("workspaceAnimation", id)
            }
        }
    }

    // ── Windows ──────────────────────────────────────────────────────────────
    SettingsGroup {
        title: I18n.tr("Windows")

        SettingsRow {
            label: I18n.tr("Opening animation")
            note: ({
                popin: I18n.tr("Grows from the middle while fading in, and shrinks away"),
                fade: I18n.tr("Fades in and out where it stands"),
                slide: I18n.tr("Comes in from the nearest edge of the workspace, and leaves by it"),
                none: I18n.tr("Appears and vanishes at once; moving and resizing still animate")
            })[Settings.windowAnimation] || ""

            SegmentedControl {
                size: "sm"
                Layout.preferredWidth: Design.s(Design.width.select)
                model: [
                    { id: "popin", label: I18n.tr("Pop in") },
                    { id: "fade",  label: I18n.tr("Fade") },
                    { id: "slide", label: I18n.tr("Slide") },
                    { id: "none",  label: I18n.tr("None") }
                ]
                current: Settings.windowAnimation
                onPicked: id => Settings.set("windowAnimation", id)
            }
        }

        SettingsRow {
            visible: Settings.windowAnimation === "popin"
            label: I18n.tr("Grows from")
            note: I18n.tr("%1%", Settings.popinPercent)

            Slider {
                Layout.preferredWidth: Design.s(Design.width.control)
                minimum: 40
                maximum: 95
                showPercent: false
                value: Settings.popinPercent
                onMoved: pct => Settings.set("popinPercent", Math.round(pct))
            }
        }
    }

    InlineStatus {
        visible: !Sway.swayfx
        status: "warning"
        text: I18n.tr("The compositor running now is plain sway: these settings take effect with b1air's own swayFX.")
    }
}
