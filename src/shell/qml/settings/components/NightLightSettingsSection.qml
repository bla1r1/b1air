import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../Ui"
import "../../Services"

// =============================================================================
// Night Light & Eye Care
//
// Colour temperature through wlsunset, started by the daemon
// (`b1air-daemon night-light on <K>`), which also puts it back at login.
//
// This page used to start wlsunset itself with -t and -T equal, which wlsunset
// refuses ("high temp must be higher than low") and exits; the fallback,
// gammastep, is not installed. So the toggle said "Active at 4000K" over an
// untinted screen, every time. And the page kept its own copies of the two
// values, which stopped following Settings the first time it wrote them — a
// change from the Control Center tile afterwards did not show here.
// =============================================================================

ColumnLayout {
    id: section

    Layout.fillWidth: true
    spacing: Design.s(Design.space.lg)

    readonly property bool nightLightEnabled: Settings.nightLightEnabled
    // While the slider moves, the number follows the finger; wlsunset is only
    // restarted once it settles (each restart is a visible flash).
    property int dragTemp: -1
    readonly property int tempK: section.dragTemp >= 0 ? section.dragTemp : Settings.nightLightTemp

    function applyTemp(enabled, temp) {
        // One apply() instead of two set() calls. Two set() calls in a single
        // handler lose one of the two: each set() writes the file, and a write
        // started mid-handler clobbers the change that follows it — measured on
        // a live shell, five sets in one tick kept only the 1st, 3rd and 5th,
        // in memory as well as on disk. apply() mutates the adapter for every
        // key first and writes once, which is the shape that survives.
        Settings.apply({ nightLightEnabled: enabled, nightLightTemp: temp });
        Quickshell.execDetached(enabled
            ? ["b1air-daemon", "night-light", "on", String(temp), "--quiet"]
            : ["b1air-daemon", "night-light", "off", "--quiet"]);
    }

    Timer {
        id: dragSettle
        interval: 300
        onTriggered: {
            section.applyTemp(true, section.dragTemp);
            section.dragTemp = -1;
        }
    }

    // ── 1. Master Control ────────────────────────────────────────────────────
    Card {
        title: "Night Light"
        subtitle: section.nightLightEnabled
            ? "Active at " + section.tempK + "K color temperature"
            : "Reduce blue light in evening hours to protect sleep"
        icon: "\u{f0599}"
        accentColor: Design.yellow

        Toggle {
            label: "Night Light"
            subtitle: "Shift the screen towards warm colours to go easier on the eyes at night"
            checked: section.nightLightEnabled
            onToggled: section.applyTemp(!section.nightLightEnabled, section.tempK)
        }
    }

    // ── 2. Color Temperature Slider & Presets ────────────────────────────────
    Card {
        visible: section.nightLightEnabled
        title: "Color Temperature"
        subtitle: "Lower values produce warmer, amber tones with less blue light"
        icon: "\u{f0590}"
        accentColor: Design.yellow

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.md)

            RowLayout {
                Layout.fillWidth: true
                Label { text: "Color Warmth"; weight: Design.weight.semibold }
                Item { Layout.fillWidth: true }
                Label { text: section.tempK + " K"; role: "caption"; isMono: true; color: Design.yellow }
            }

            // Slider: 2500K to 6500K mapped to 0..100
            Slider {
                Layout.fillWidth: true
                Layout.preferredHeight: Design.s(Design.size.ctl)
                value: Math.round(((section.tempK - 2500) / 4000) * 100)
                tone: Design.yellow
                icon: "\u{f0590}"
                onMoved: pct => {
                    section.dragTemp = Math.round((2500 + (pct / 100) * 4000) / 100) * 100;
                    dragSettle.restart();
                }
            }

            Label { text: "Quick Warmth Presets"; role: "caption"; dim: true }

            Flow {
                Layout.fillWidth: true
                spacing: Design.s(Design.space.xs)

                Pill {
                    label: "Candle (2700K)"
                    active: section.tempK === 2700
                    activeColor: Design.yellow
                    onClicked: section.applyTemp(true, 2700)
                }

                Pill {
                    label: "Warm Incandescent (3400K)"
                    active: section.tempK === 3400
                    activeColor: Design.yellow
                    onClicked: section.applyTemp(true, 3400)
                }

                Pill {
                    label: "Sunset (4500K)"
                    active: section.tempK === 4500
                    activeColor: Design.yellow
                    onClicked: section.applyTemp(true, 4500)
                }

                Pill {
                    label: "Daylight (6500K)"
                    active: section.tempK === 6500
                    activeColor: Design.yellow
                    onClicked: section.applyTemp(true, 6500)
                }
            }
        }
    }
}
