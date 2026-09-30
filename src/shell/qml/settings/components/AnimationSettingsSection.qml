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
// long that takes, how faded unfocused windows are, and the special
// workspace on Mod+S. Each control writes settings.json; the daemon sees the
// change and sends it to sway over IPC at once (apply_compositor_extras), so
// nothing here needs a reload. These are our swayfx's (src/swayfx/patches);
// any other sway refuses them and keeps its own behaviour.
// =============================================================================

ColumnLayout {
    id: section

    Layout.fillWidth: true
    spacing: Design.s(Design.space.lg)

    readonly property bool off: Settings.animationDuration === 0

    Card {
        title: "Motion"
        subtitle: section.off ? "Animations are off" : "How long every animation takes"
        icon: "\u{f0e1e}"
        accentColor: Design.mauve

        Toggle {
            label: "Animations"
            subtitle: "Off makes every change instant: windows, workspaces, the swipe"
            checked: !section.off
            onToggled: Settings.set("animationDuration", section.off ? 200 : 0)
        }

        Slider {
            Layout.fillWidth: true
            visible: !section.off
            label: "Duration"
            showPercent: false
            minimum: 80
            maximum: 600
            value: Math.max(80, Settings.animationDuration)
            tone: Design.mauve
            onMoved: pct => Settings.set("animationDuration", pct)
        }
        Label {
            visible: !section.off
            text: Settings.animationDuration + " ms"
            role: "caption"; dim: true
        }
    }

    Card {
        title: "Workspaces"
        subtitle: "Switching from one workspace to another"
        icon: "\u{f0570}"
        accentColor: Design.sapphire

        Flow {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.xs)
            Repeater {
                model: [
                    { id: "slide", label: "Slide" },
                    { id: "fade",  label: "Fade" }
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
                ? "The old workspace fades into the new one"
                : "Both slide sideways, the new one in from the side it lies on; the touchpad swipe moves them with your fingers"
            role: "caption"; dim: true; wrapMode: Text.WordWrap
        }
    }

    Card {
        title: "Windows"
        subtitle: "Opening and closing a window"
        icon: "\u{f05b6}"
        accentColor: Design.teal

        Flow {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.xs)
            Repeater {
                model: [
                    { id: "popin", label: "Pop in" },
                    { id: "fade",  label: "Fade" },
                    { id: "slide", label: "Slide" },
                    { id: "none",  label: "None" }
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
                popin: "Grows from the middle while fading in, and shrinks away",
                fade: "Fades in and out where it stands",
                slide: "Comes in from the nearest edge of the workspace, and leaves by it",
                none: "Appears and vanishes at once; moving and resizing still animate"
            })[Settings.windowAnimation] || ""
            role: "caption"; dim: true; wrapMode: Text.WordWrap
        }

        Slider {
            Layout.fillWidth: true
            visible: Settings.windowAnimation === "popin"
            label: "Grows from"
            minimum: 40
            maximum: 95
            value: Settings.popinPercent
            tone: Design.teal
            onMoved: pct => Settings.set("popinPercent", pct)
        }
    }

    Card {
        title: "Unfocused windows"
        subtitle: Settings.inactiveOpacityPercent >= 100
            ? "Drawn like the focused one"
            : "Drawn at " + Settings.inactiveOpacityPercent + "% opacity, so the focused one stands out"
        icon: "\u{f0208}"
        accentColor: Design.blue

        Toggle {
            label: "Fade unfocused windows"
            checked: Settings.inactiveOpacityPercent < 100
            onToggled: Settings.set("inactiveOpacityPercent", Settings.inactiveOpacityPercent < 100 ? 100 : 50)
        }
        Slider {
            Layout.fillWidth: true
            visible: Settings.inactiveOpacityPercent < 100
            label: "Opacity"
            minimum: 20
            maximum: 95
            value: Settings.inactiveOpacityPercent
            tone: Design.blue
            onMoved: pct => Settings.set("inactiveOpacityPercent", pct)
        }
    }

    Card {
        title: "Special workspace"
        subtitle: "A workspace of its own, called up over the one in front of you"
        icon: "\u{f0bc8}"
        accentColor: Design.peach

        Toggle {
            label: "Mod+S calls up the special workspace"
            subtitle: Settings.specialWorkspace
                ? "Mod+S shows and hides it; Mod+Ctrl+Shift+S sends the focused window there"
                : "Mod+S shows the scratchpad instead"
            checked: Settings.specialWorkspace
            onToggled: Settings.set("specialWorkspace", !Settings.specialWorkspace)
        }
    }

    Label {
        Layout.fillWidth: true
        visible: !Sway.swayfx
        text: "The compositor running now is plain sway: these settings take effect with b1air's own swayFX."
        role: "caption"; color: Design.peach; wrapMode: Text.WordWrap
    }
}
