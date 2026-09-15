import QtQuick
import QtQuick.Layouts
import "../../Ui"
import "../../Services"
import B1air.Daemon

// =============================================================================
// Audio — the parts that did not fit on the Control Center's Sound page.
//
// The Control Center answers "make it louder" and "which speakers". This page
// answers "why is one app blaring" and "set that device's own level", which is
// what VolumePopup's 768 lines were for.
// =============================================================================

ColumnLayout {
    id: section

    Layout.fillWidth: true
    spacing: Design.s(Design.space.lg)

    property bool _held: false
    function _hold(on) {
        if (on === section._held)
            return;
        section._held = on;
        if (on) Audio.acquire();
        else Audio.release();
    }
    Component.onCompleted: section._hold(visible)
    onVisibleChanged: section._hold(visible)
    Component.onDestruction: section._hold(false)

    // A device or stream row: name, its own slider, mute, test button, and disable toggle.
    component MixerRow: ColumnLayout {
        id: line

        property string type: "sink"
        property var row: null
        property color tone: Design.sapphire
        property bool selectable: false
        property bool isDevice: false

        Layout.fillWidth: true
        spacing: Design.s(Design.space.xs)

        RowLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.sm)

            Icon {
                text: line.row ? (line.row.icon || "\u{f057e}") : "\u{f057e}"
                role: "body"
                color: (line.row && line.row.is_default) ? line.tone : Design.textDim
            }

            Label {
                text: line.row ? (line.row.description || line.row.name) : ""
                Layout.fillWidth: true
                elide: Text.ElideRight
                weight: (line.row && line.row.is_default) ? Design.weight.semibold : Design.weight.regular
                color: (line.row && line.row.disabled) ? Design.textFaint : Design.text
            }

            Label {
                visible: line.row && line.row.is_default
                text: "default"
                role: "caption"
                isMono: true
                color: line.tone
            }

            Pill {
                visible: line.isDevice && line.type === "sink" && line.row && !line.row.disabled
                label: "Test"
                icon: "\u{f0025}"
                onClicked: Audio.testAudio(line.row.id)
            }

            Pill {
                visible: line.selectable && line.row && !line.row.is_default && !line.row.disabled
                label: "Use this"
                onClicked: Audio.setDefault(line.type, line.row.name)
            }

            Pill {
                visible: line.isDevice && line.row
                label: line.row && line.row.disabled ? "Enable" : "Disable"
                active: line.row && line.row.disabled
                activeColor: Design.danger
                onClicked: if (line.row) Audio.toggleDeviceDisabled(line.row.name)
            }
        }

        Slider {
            visible: !(line.row && line.row.disabled)
            Layout.fillWidth: true
            Layout.preferredHeight: Design.s(Design.size.ctl)
            value: line.row ? line.row.volume : 0
            muted: line.row ? line.row.mute : false
            tone: line.tone
            icon: (line.row && line.row.mute) ? "\u{f075f}" : "\u{f057f}"
            iconClickable: true
            onIconClicked: if (line.row) Audio.toggleMute(line.type, line.row.id)
            onMoved: pct => { if (line.row) Audio.applyVolume(line.type, line.row, pct); }
        }
    }

    Card {
        title: "Application volume"
        subtitle: "Each stream keeps its own level. Turning one down here does not touch the master."
        icon: "\u{f075a}"
        accentColor: Design.mauve

        Repeater {
            model: Audio.apps
            MixerRow {
                required property var model
                type: "sink-input"
                row: model
                tone: Design.mauve
                isDevice: false
            }
        }

        EmptyState {
            Layout.fillWidth: true
            visible: Audio.apps.count === 0
            icon: "\u{f075a}"
            title: "Nothing is playing"
            hint: "Applications appear here while they hold an audio stream."
        }
    }

    Card {
        title: "Sound"
        subtitle: "The master switch for everything this computer plays"
        icon: Audio.masterMute ? "\u{f075f}" : "\u{f057e}"
        accentColor: Design.teal

        // One Toggle row, as everywhere else — this was a hand-built row
        // around a bare Toggle, with "Enabled" under the label repeating what
        // the switch already shows.
        Toggle {
            label: "Sound output"
            subtitle: Audio.masterMute ? "Muted — the volume levels below are kept" : "Off mutes everything; volume levels are kept"
            checked: !Audio.masterMute
            onToggled: Audio.toggleMasterMute()
        }
    }

    Card {
        title: "Output devices"
        subtitle: "Per-device level, independent of the master slider"
        icon: "\u{f057e}"
        accentColor: Design.sapphire

        Repeater {
            model: Audio.outputs
            MixerRow {
                required property var model
                type: "sink"
                row: model
                tone: Design.sapphire
                selectable: true
                isDevice: true
            }
        }

        EmptyState {
            Layout.fillWidth: true
            visible: Audio.outputs.count === 0
            icon: "\u{f075f}"
            title: "No output devices"
            hint: "Nothing is registered with PipeWire right now."
        }
    }

    Card {
        title: "Input devices"
        subtitle: "Microphones and capture sources"
        icon: "\u{f036c}"
        accentColor: Design.teal

        Repeater {
            model: Audio.inputs
            MixerRow {
                required property var model
                type: "source"
                row: model
                tone: Design.teal
                selectable: true
                isDevice: true
            }
        }

        // The Control Center's Sound page has had this since it was written and
        // the full page never did — the same way brightness lived only in the
        // battery popup. This file's own header says it holds "the parts that
        // did not fit" in the mini view, so the popup being strictly more
        // capable is backwards.
        RowLayout {
            visible: Audio.inputs.count > 0
            Layout.fillWidth: true
            Layout.topMargin: Design.s(Design.space.sm)
            spacing: Design.s(Design.space.sm)

            Icon {
                text: "\u{f05a9}"
                role: "caption"
                color: Design.teal
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                Label {
                    text: "AI noise suppression (RNNoise)"
                    weight: Design.weight.semibold
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }

                Label {
                    text: "Filters keyboard clatter and room noise out of the microphone"
                    role: "caption"
                    dim: true
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }
            }

            ActionButton {
                icon: "\u{f021}"
                label: "Toggle Filter"
                onActivated: Daemon.micRnnoiseToggle()
            }
        }

        EmptyState {
            Layout.fillWidth: true
            visible: Audio.inputs.count === 0
            icon: "\u{f036d}"
            title: "No inputs"
            hint: "No microphone or capture device is registered."
        }
    }

    Card {
        title: "Audio Feedback & Sound Effects"
        subtitle: "Acoustic feedback for volume changes, screenshot capture, and peripheral plug events"
        icon: "\u{f0028}"
        accentColor: Design.cyan

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.md)

            RowLayout {
                Layout.fillWidth: true
                spacing: Design.s(Design.space.md)

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Label { text: "Volume Step Feedback Click"; weight: Design.weight.semibold }
                    Label { text: "Play a subtle audio tick when adjusting volume level with keys"; role: "caption"; dim: true }
                }

                Toggle {
                    checked: Settings.soundVolumeFeedback !== undefined ? Settings.soundVolumeFeedback : true
                    onToggled: Settings.set("soundVolumeFeedback", !Settings.soundVolumeFeedback)
                }
            }

            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Design.tint(Design.line, 0.4) }

            RowLayout {
                Layout.fillWidth: true
                spacing: Design.s(Design.space.md)

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Label { text: "Screenshot Shutter Sound"; weight: Design.weight.semibold }
                    Label { text: "Play a camera shutter sound when saving or copying a screenshot"; role: "caption"; dim: true }
                }

                Toggle {
                    checked: Settings.soundScreenshotFeedback !== undefined ? Settings.soundScreenshotFeedback : true
                    onToggled: Settings.set("soundScreenshotFeedback", !Settings.soundScreenshotFeedback)
                }
            }

            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Design.tint(Design.line, 0.4) }

            RowLayout {
                Layout.fillWidth: true
                spacing: Design.s(Design.space.md)

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Label { text: "Peripheral & Device Connect Chime"; weight: Design.weight.semibold }
                    Label { text: "Play a chime when a headset, USB audio interface, dock or Bluetooth audio device connects"; role: "caption"; dim: true }
                }

                Toggle {
                    checked: Settings.soundDeviceFeedback !== undefined ? Settings.soundDeviceFeedback : true
                    onToggled: Settings.set("soundDeviceFeedback", !Settings.soundDeviceFeedback)
                }
            }
        }
    }

    Card {
        title: "Audio preferences"
        subtitle: "Key step size and volume change feedback"
        icon: "\u{f04c3}"
        accentColor: Design.peach

        Stepper {
            label: "Volume step"
            valueText: Settings.audioStep + "%"
            onDecrement: Settings.set("audioStep", Math.max(1, Settings.audioStep - 1))
            onIncrement: Settings.set("audioStep", Math.min(25, Settings.audioStep + 1))
        }

        Toggle {
            label: "Volume notifications"
            subtitle: "Show the volume popup when media keys are pressed"
            checked: Settings.audioNotifications
            onToggled: Settings.set("audioNotifications", !Settings.audioNotifications)
        }
    }
}
