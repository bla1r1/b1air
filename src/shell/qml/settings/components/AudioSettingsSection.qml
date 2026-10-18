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
        property color tone: Design.accent
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

            Button {
                visible: line.isDevice && line.type === "sink" && line.row && !line.row.disabled
                size: "sm"
                text: I18n.tr("Test")
                icon: "\u{f0025}"
                onClicked: Audio.testAudio(line.row.id)
            }

            Button {
                visible: line.selectable && line.row && !line.row.is_default && !line.row.disabled
                size: "sm"
                variant: "ghost"
                text: I18n.tr("Use this")
                onClicked: Audio.setDefault(line.type, line.row.name)
            }

            Button {
                visible: line.isDevice && line.row
                size: "sm"
                variant: line.row && line.row.disabled ? "secondary" : "ghost"
                text: line.row && line.row.disabled ? I18n.tr("Enable") : I18n.tr("Disable")
                onClicked: if (line.row) Audio.toggleDeviceDisabled(line.row.name)
            }
        }

        Slider {
            visible: !(line.row && line.row.disabled)
            Layout.fillWidth: true
            Layout.preferredHeight: Design.s(Design.size.md)
            value: line.row ? line.row.volume : 0
            muted: line.row ? line.row.mute : false
            tone: line.tone
            icon: (line.row && line.row.mute) ? "\u{f075f}" : "\u{f057f}"
            iconClickable: true
            onIconClicked: if (line.row) Audio.toggleMute(line.type, line.row.id)
            onMoved: pct => { if (line.row) Audio.applyVolume(line.type, line.row, pct); }
        }
    }

    SettingsGroup {
        title: I18n.tr("Sound")

        SwitchRow {
            label: I18n.tr("Sound output")
            note: Audio.masterMute ? I18n.tr("Muted — volume levels below are kept") : I18n.tr("Off mutes everything; volume levels are kept")
            checked: !Audio.masterMute
            onToggled: Audio.toggleMasterMute()
        }
    }

    SettingsGroup {
        title: I18n.tr("Output devices")

        Repeater {
            model: Audio.outputs
            MixerRow {
                required property var model
                type: "sink"
                row: model
                selectable: true
                isDevice: true
            }
        }

        EmptyState {
            Layout.fillWidth: true
            visible: Audio.outputs.count === 0
            icon: "\u{f075f}"
            title: I18n.tr("No output devices")
            hint: I18n.tr("Nothing is registered with PipeWire right now.")
        }
    }

    SettingsGroup {
        title: I18n.tr("Input devices")

        Repeater {
            model: Audio.inputs
            MixerRow {
                required property var model
                type: "source"
                row: model
                selectable: true
                isDevice: true
            }
        }

        RowLayout {
            visible: Audio.inputs.count > 0
            Layout.fillWidth: true
            Layout.topMargin: Design.s(Design.space.sm)
            Layout.bottomMargin: Design.s(Design.space.xs)
            Layout.leftMargin: Design.s(Design.space.rowPaddingX)
            Layout.rightMargin: Design.s(Design.space.rowPaddingX)
            spacing: Design.s(Design.space.sm)

            Icon {
                text: "\u{f05a9}"
                role: "caption"
                color: Design.textDim
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                Label {
                    text: I18n.tr("AI noise suppression (RNNoise)")
                    weight: Design.weight.semibold
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }

                Label {
                    text: I18n.tr("Filters keyboard clatter and room noise out of the microphone")
                    role: "footnote"
                    dim: true
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }
            }

            Button {
                size: "sm"
                icon: "\u{f021}"
                text: I18n.tr("Toggle Filter")
                onClicked: Daemon.micRnnoiseToggle()
            }
        }

        EmptyState {
            Layout.fillWidth: true
            visible: Audio.inputs.count === 0
            icon: "\u{f036d}"
            title: I18n.tr("No inputs")
            hint: I18n.tr("No microphone or capture device is registered.")
        }
    }

    SettingsGroup {
        title: I18n.tr("Application volume")

        Repeater {
            model: Audio.apps
            MixerRow {
                required property var model
                type: "sink-input"
                row: model
                isDevice: false
            }
        }

        EmptyState {
            Layout.fillWidth: true
            visible: Audio.apps.count === 0
            icon: "\u{f075a}"
            title: I18n.tr("Nothing is playing")
            hint: I18n.tr("Applications appear here while they hold an audio stream.")
        }
    }

    SettingsGroup {
        title: I18n.tr("Volume keys")

        SettingsRow {
            label: I18n.tr("Volume step")
            Stepper {
                valueText: Settings.audioStep + "%"
                onDecrement: Settings.set("audioStep", Math.max(1, Settings.audioStep - 1))
                onIncrement: Settings.set("audioStep", Math.min(25, Settings.audioStep + 1))
            }
        }

        SwitchRow {
            label: I18n.tr("Volume notifications")
            note: I18n.tr("Show popup overlay when media keys are pressed")
            checked: Settings.audioNotifications
            onToggled: Settings.set("audioNotifications", !Settings.audioNotifications)
        }

        SwitchRow {
            label: I18n.tr("Volume feedback click")
            note: I18n.tr("Play an audio tick when adjusting volume level with keys")
            checked: Settings.soundVolumeFeedback !== false
            onToggled: Settings.set("soundVolumeFeedback", !(Settings.soundVolumeFeedback !== false))
        }
    }

    SettingsGroup {
        title: I18n.tr("System sounds")

        SwitchRow {
            label: I18n.tr("Screenshot sound")
            note: I18n.tr("Play a shutter sound when capturing screenshot")
            checked: Settings.soundScreenshotFeedback !== false
            onToggled: Settings.set("soundScreenshotFeedback", !(Settings.soundScreenshotFeedback !== false))
        }

        SwitchRow {
            label: I18n.tr("Device connect chime")
            note: I18n.tr("Play chime when headset, dock or Bluetooth device connects")
            checked: Settings.soundDeviceFeedback !== false
            onToggled: Settings.set("soundDeviceFeedback", !(Settings.soundDeviceFeedback !== false))
        }
    }
}
