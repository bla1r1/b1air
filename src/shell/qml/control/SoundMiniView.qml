import QtQuick
import QtQuick.Layouts
import "../Ui"
import "../Services"
import B1air.Daemon
import "."

// =============================================================================
// Sound mini-settings.
//
// Three fixes worth naming: the invented "MacBook Pro Speakers" list is gone,
// the volume slider now calls Audio with the (type, id) signature it actually
// has — before, it resolved no node and moving it did nothing — and the input
// device is here, because a sound page that cannot mute the microphone sends you
// to the full settings for the one thing you opened it for.
// =============================================================================

MiniView {
    id: root

    title: I18n.tr("Sound")
    icon: "\u{f057f}"
    tone: Design.sapphire
    footerLabel: I18n.tr("Sound Settings…")

    readonly property var sink: Audio.defaultSink
    readonly property var source: Audio.defaultSource

    ColumnLayout {
        anchors.fill: parent
        spacing: Design.s(Design.space.sm)

        // ── Output ───────────────────────────────────────────────────────────
        SectionLabel {
            text: I18n.tr("Output volume")
            visible: root.sink !== null
        }

        Slider {
            visible: root.sink !== null
            Layout.fillWidth: true
            Layout.preferredHeight: Design.s(Design.size.ctl)
            value: root.sink ? root.sink.volume : 0
            muted: root.sink ? root.sink.mute : false
            tone: Design.sapphire
            icon: (root.sink && root.sink.mute) ? "\u{f075f}" : "\u{f057f}"
            label: root.sink ? (root.sink.description || root.sink.name) : ""
            iconClickable: true
            onIconClicked: if (root.sink) Audio.toggleMute("sink", root.sink.id)
            onMoved: pct => Audio.applyVolume("sink", root.sink, pct)
        }

        SectionLabel {
            text: I18n.tr("Output device")
            Layout.topMargin: Design.s(Design.space.xs)
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            EmptyState {
                anchors.centerIn: parent
                width: parent.width
                visible: Audio.outputs.count === 0
                icon: "\u{f075f}"
                title: I18n.tr("No output devices")
                hint: I18n.tr("Nothing is registered with PipeWire right now.")
            }

            ListView {
                id: outList
                anchors.fill: parent
                visible: Audio.outputs.count > 0
                clip: true
                spacing: Design.s(Design.space.xs)
                model: Audio.outputs

                delegate: Rectangle {
                    id: dev
                    required property var model

                    width: outList.width
                    height: Design.s(Design.size.row)
                    radius: Design.s(Design.radius.ctl)

                    readonly property bool isDefault: dev.model.is_default

                    color: isDefault ? Design.tint(Design.sapphire, 0.15)
                                     : (rowMa.containsMouse ? Design.glassHover : "transparent")
                    border.color: isDefault ? Design.tint(Design.sapphire, 0.35) : "transparent"
                    border.width: Design.border

                    Behavior on color { ColorAnimation { duration: Design.duration.fast } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Design.s(Design.space.sm)
                        anchors.rightMargin: Design.s(Design.space.sm)
                        spacing: Design.s(Design.space.sm)

                        Icon {
                            text: dev.model.icon || "\u{f057e}"
                            role: "body"
                            color: dev.isDefault ? Design.sapphire : Design.textDim
                        }

                        Label {
                            text: dev.model.description || dev.model.name
                            role: "body"
                            weight: dev.isDefault ? Design.weight.semibold : Design.weight.regular
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }

                        Label {
                            text: dev.isDefault ? "" : (rowMa.containsMouse ? I18n.tr("Use this") : "")
                            role: "caption"
                            color: Design.sapphire
                        }

                        Icon {
                            visible: dev.isDefault
                            text: "\u{f012c}"
                            role: "caption"
                            color: Design.sapphire
                        }
                    }

                    Clickable {
                        id: rowMa
                        enabled: !dev.isDefault
                        // setDefault takes the node name; setDefaultSink() never
                        // existed and threw on every click.
                        onClicked: Audio.setDefault("sink", dev.model.name)
                    }
                }
            }
        }

        // ── Input ────────────────────────────────────────────────────────────
        SectionLabel {
            text: I18n.tr("Microphone")
            visible: root.source !== null
        }

        Slider {
            visible: root.source !== null
            Layout.fillWidth: true
            Layout.preferredHeight: Design.s(Design.size.ctl)
            value: root.source ? root.source.volume : 0
            muted: root.source ? root.source.mute : false
            tone: Design.teal
            icon: (root.source && root.source.mute) ? "\u{f036d}" : "\u{f036c}"
            label: root.source ? (root.source.description || root.source.name) : ""
            iconClickable: true
            onIconClicked: if (root.source) Audio.toggleMute("source", root.source.id)
            onMoved: pct => Audio.applyVolume("source", root.source, pct)
        }

        // AI Noise Suppression (RNNoise)
        RowLayout {
            visible: root.source !== null
            Layout.fillWidth: true
            spacing: Design.s(Design.space.sm)

            Icon {
                text: "\u{f05a9}"
                role: "caption"
                color: Design.teal
            }

            Label {
                text: I18n.tr("AI Noise Suppression (RNNoise)")
                role: "caption"
                weight: Design.weight.medium
                Layout.fillWidth: true
            }

            ActionButton {
                icon: "\u{f021}"
                label: I18n.tr("Toggle Filter")
                onActivated: Daemon.micRnnoiseToggle()
            }
        }

        // ── Per-Application Stream Volume Mixer ───────────────────────────────
        SectionLabel {
            text: I18n.tr("Application Mixer")
            visible: Audio.apps.count > 0
        }

        ListView {
            id: appsList
            visible: Audio.apps.count > 0
            Layout.fillWidth: true
            Layout.preferredHeight: Math.min(Design.s(120), Audio.apps.count * Design.s(36))
            clip: true
            spacing: Design.s(Design.space.xs)
            model: Audio.apps

            delegate: RowLayout {
                id: appStreamRow
                required property var model
                width: appsList.width
                spacing: Design.s(Design.space.xs)

                Icon {
                    text: "\u{f001}"
                    role: "caption"
                    color: Design.sapphire
                }

                Label {
                    text: appStreamRow.model.description || appStreamRow.model.name || I18n.tr("App")
                    role: "caption"
                    elide: Text.ElideRight
                    Layout.preferredWidth: Design.s(100)
                }

                Slider {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Design.s(28)
                    value: appStreamRow.model.volume
                    muted: appStreamRow.model.mute
                    tone: Design.sapphire
                    onMoved: pct => Audio.applyVolume("sink-input", appStreamRow.model, pct)
                }
            }
        }
    }
}
