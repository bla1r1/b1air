import QtQuick
import QtQuick.Layouts
import Quickshell
import B1air.Daemon
import "../../Ui"
import "../../Services"

// =============================================================================
// Animations & Effects
//
// The compositor's own motion: how workspaces and windows come and go, how
// long that takes, how faded unfocused windows are, the special workspace
// on Mod+S and the overview on Mod+O. Each control writes settings.json; the
// daemon sees the change and sends it to sway over IPC at once
// (apply_compositor_extras), so nothing here needs a reload. These are our swayfx's (src/swayfx/patches);
// any other sway refuses them and keeps its own behaviour.
// =============================================================================

ColumnLayout {
    id: section

    Layout.fillWidth: true
    spacing: Design.s(Design.space.lg)

    readonly property bool off: Settings.animationDuration === 0

    Card {
        title: I18n.tr("Motion")
        subtitle: section.off ? I18n.tr("Animations are off") : I18n.tr("How long every animation takes")
        icon: "\u{f0e1e}"
        accentColor: Design.mauve

        Toggle {
            label: I18n.tr("Animations")
            subtitle: I18n.tr("Off makes every change instant: windows, workspaces, the swipe")
            checked: !section.off
            onToggled: Settings.set("animationDuration", section.off ? 200 : 0)
        }

        Slider {
            Layout.fillWidth: true
            visible: !section.off
            label: I18n.tr("Duration")
            showPercent: false
            minimum: 80
            maximum: 600
            value: Math.max(80, Settings.animationDuration)
            tone: Design.mauve
            onMoved: pct => Settings.set("animationDuration", pct)
        }
        Label {
            visible: !section.off
            text: I18n.tr("%1 ms", Settings.animationDuration)
            role: "caption"; dim: true
        }
    }

    Card {
        title: I18n.tr("Workspaces")
        subtitle: I18n.tr("Switching from one workspace to another")
        icon: "\u{f0570}"
        accentColor: Design.sapphire

        Flow {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.xs)
            Repeater {
                model: [
                    { id: "slide", label: I18n.tr("Slide") },
                    { id: "fade",  label: I18n.tr("Fade") }
                ]
                delegate: Pill {
                    required property var modelData
                    label: modelData.label
                    active: Settings.workspaceAnimation === modelData.id
                    onClicked: Settings.set("workspaceAnimation", modelData.id)
                }
            }
        }
        Label {
            Layout.fillWidth: true
            text: Settings.workspaceAnimation === "fade"
                ? I18n.tr("The old workspace fades into the new one")
                : I18n.tr("Both slide sideways, the new one in from the side it lies on; the touchpad swipe moves them with your fingers")
            role: "caption"; dim: true; wrapMode: Text.WordWrap
        }
    }

    Card {
        title: I18n.tr("Windows")
        subtitle: I18n.tr("Opening and closing a window")
        icon: "\u{f05b6}"
        accentColor: Design.teal

        Flow {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.xs)
            Repeater {
                model: [
                    { id: "popin", label: I18n.tr("Pop in") },
                    { id: "fade",  label: I18n.tr("Fade") },
                    { id: "slide", label: I18n.tr("Slide") },
                    { id: "none",  label: I18n.tr("No animation") }
                ]
                delegate: Pill {
                    required property var modelData
                    label: modelData.label
                    active: Settings.windowAnimation === modelData.id
                    onClicked: Settings.set("windowAnimation", modelData.id)
                }
            }
        }
        Label {
            Layout.fillWidth: true
            text: ({
                popin: I18n.tr("Grows from the middle while fading in, and shrinks away"),
                fade: I18n.tr("Fades in and out where it stands"),
                slide: I18n.tr("Comes in from the nearest edge of the workspace, and leaves by it"),
                none: I18n.tr("Appears and vanishes at once; moving and resizing still animate")
            })[Settings.windowAnimation] || ""
            role: "caption"; dim: true; wrapMode: Text.WordWrap
        }

        Slider {
            Layout.fillWidth: true
            visible: Settings.windowAnimation === "popin"
            label: I18n.tr("Grows from")
            minimum: 40
            maximum: 95
            value: Settings.popinPercent
            tone: Design.teal
            onMoved: pct => Settings.set("popinPercent", pct)
        }
    }

    Label {
        Layout.fillWidth: true
        visible: !Sway.swayfx
        text: I18n.tr("The compositor running now is plain sway: these settings take effect with b1air's own swayFX.")
        role: "caption"; color: Design.peach; wrapMode: Text.WordWrap
    }
}
