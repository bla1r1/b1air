import QtQuick
import QtQuick.Layouts
import "../Ui"
import "../Services"
import "."

// =============================================================================
// Battery & power mini-settings.
//
// The three energy-mode rows were the same forty lines three times over, which
// is how they ended up with three different hover colours. One model, one row.
// =============================================================================

MiniView {
    id: root

    title: I18n.tr("Battery & Power")
    icon: "\u{f0079}"
    tone: Design.green
    footerLabel: I18n.tr("Power Settings…")

    trailing: BatteryPill { clickable: false }

    // DDC probing runs ddcutil, so the panel list is only fetched while this
    // view is on screen.
    property bool _held: false
    function _hold(on) {
        if (on === root._held) return;
        root._held = on;
        if (on) Monitors.acquire(); else Monitors.release();
    }
    onVisibleChanged: root._hold(visible)
    Component.onCompleted: root._hold(visible)
    Component.onDestruction: root._hold(false)

    readonly property var modes: [
        {
            id: "performance",
            glyph: "\u{f0e4}",
            title: I18n.tr("Performance"),
            hint: I18n.tr("Maximum speed, shortest battery life"),
            tone: Design.red
        },
        {
            id: "balanced",
            glyph: "\u{f0241}",
            title: I18n.tr("Balanced"),
            hint: I18n.tr("Automatic — speed when you need it, quiet when you do not"),
            tone: Design.sapphire
        },
        {
            id: "power-saver",
            glyph: "\u{f0084}",
            title: I18n.tr("Low Power"),
            hint: I18n.tr("Caps performance to stretch the charge"),
            tone: Design.green
        }
    ]

    ColumnLayout {
        anchors.fill: parent
        spacing: Design.s(Design.space.sm)

        // ── Summary ──────────────────────────────────────────────────────────
        Rectangle {
            visible: Power.hasBattery
            Layout.fillWidth: true
            Layout.preferredHeight: Design.s(Design.size.tile)
            radius: Design.s(Design.radius.card)
            color: Design.glassCard
            border.color: Design.glassBorder
            border.width: Design.border

            RowLayout {
                anchors.fill: parent
                anchors.margins: Design.s(Design.space.md)
                spacing: Design.s(Design.space.md)

                Icon {
                    text: Power.charging ? "\u{f0084}" : "\u{f0079}"
                    role: "title"
                    color: Power.charging ? Design.ok : Design.accent
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    Label {
                        text: Power.charging ? I18n.tr("Running on power adapter") : I18n.tr("Running on battery")
                        role: "body"
                        weight: Design.weight.semibold
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }

                    Label {
                        text: I18n.tr(Power.status) + (Power.timeRemainingText !== ""
                            ? " • " + (Power.charging ? I18n.tr("until full %1", Power.timeRemainingText) : I18n.tr("%1 left", Power.timeRemainingText)) : "")
                        role: "caption"
                        dim: true
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                }
            }
        }

        // ── Per-pack breakdown ───────────────────────────────────────────────
        // The card above is UPower's composite device, which merges every pack
        // into one number. On a two-battery machine that is the whole story
        // hidden: this popup said "99%" while BAT1 was still charging at 73%.
        // Settings → Power already broke it out per pack; the popup people
        // actually open did not, so it is the same rows here.
        SectionLabel {
            visible: Power.hasMultipleBatteries
            text: I18n.tr("Installed packs")
            Layout.topMargin: Design.s(Design.space.xs)
        }

        Repeater {
            model: Power.hasMultipleBatteries ? Power.batteries : []

            DeviceRow {
                required property var modelData

                Layout.fillWidth: true
                title: Power.labelOf(modelData) + (modelData.model ? " · " + modelData.model : "")
                subtitle: I18n.tr(Power.stateTextOf(modelData))
                    + (Power.healthOf(modelData) > 0
                        ? " • " + I18n.tr("health %1%", Power.healthOf(modelData))
                        : "")
                value: Power.percentOf(modelData) + "%"
                valueTone: Power.percentOf(modelData) <= 20 ? Design.danger
                    : (Power.healthOf(modelData) > 0 && Power.healthOf(modelData) < 70 ? Design.warn : Design.ok)
            }
        }

        // ── Screen brightness ────────────────────────────────────────────────
        SectionLabel {
            text: I18n.tr("Display")
            visible: Power.hasBacklight || Monitors.hasBrightness
            Layout.topMargin: Design.s(Design.space.xs)
        }

        Slider {
            visible: Power.hasBacklight
            Layout.fillWidth: true
            Layout.preferredHeight: Design.s(Design.size.ctl)
            value: Power.brightness
            tone: Design.yellow
            icon: "\u{f00df}"
            label: I18n.tr("Brightness")
            onMoved: pct => Power.setBrightness(pct)
        }

        // External screens over DDC/CI, one slider each, under the laptop's.
        Repeater {
            model: Monitors.brightness
            delegate: Slider {
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredHeight: Design.s(Design.size.ctl)
                value: modelData.brightness
                tone: Design.yellow
                icon: "\u{f0379}"
                label: modelData.name
                onMoved: pct => Monitors.setBrightness(modelData.id, pct)
            }
        }

        // ── Energy modes ─────────────────────────────────────────────────────
        SectionLabel {
            text: I18n.tr("Energy mode")
            Layout.topMargin: Design.s(Design.space.xs)
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            EmptyState {
                anchors.centerIn: parent
                width: parent.width
                visible: !Power.hasProfiles
                icon: "\u{f0241}"
                title: I18n.tr("No energy modes")
                hint: I18n.tr("power-profiles-daemon is not running, so there is nothing to switch between.")
            }

            ColumnLayout {
                anchors.fill: parent
                visible: Power.hasProfiles
                spacing: Design.s(Design.space.xs)

                Repeater {
                    model: root.modes

                    Rectangle {
                        id: modeRow
                        required property var modelData

                        readonly property bool active: Power.profile === modeRow.modelData.id

                        Layout.fillWidth: true
                        Layout.preferredHeight: Design.s(Design.size.rowTall)
                        radius: Design.s(Design.radius.ctl)

                        color: modeRow.active ? Design.tint(modeRow.modelData.tone, 0.15)
                                              : (modeMa.containsMouse ? Design.glassHover : "transparent")
                        border.color: modeRow.active ? Design.tint(modeRow.modelData.tone, 0.35) : "transparent"
                        border.width: Design.border

                        Behavior on color { ColorAnimation { duration: Design.duration.fast } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Design.s(Design.space.sm)
                            anchors.rightMargin: Design.s(Design.space.sm)
                            spacing: Design.s(Design.space.sm)

                            Icon {
                                text: modeRow.modelData.glyph
                                role: "body"
                                color: modeRow.modelData.tone
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                Label {
                                    text: modeRow.modelData.title
                                    weight: Design.weight.semibold
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }

                                Label {
                                    text: modeRow.modelData.hint
                                    role: "caption"
                                    dim: true
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                }
                            }

                            Icon {
                                visible: modeRow.active
                                text: "\u{f012c}"
                                role: "caption"
                                color: modeRow.modelData.tone
                            }
                        }

                        Clickable {
                            id: modeMa
                            onClicked: Power.setProfile(modeRow.modelData.id)
                        }
                    }
                }

                Item { Layout.fillHeight: true }
            }
        }
    }
}
