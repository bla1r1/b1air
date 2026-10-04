import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../Ui"
import "../../Services"

// =============================================================================
// Night Light & Eye Care
//
// Colour temperature through b1air-gamma, started by the daemon
// (`b1air-daemon night-light on <K> --schedule …`), which also puts it back
// at login. A new value while it runs is a fade, not a restart. The schedule
// (always, between two times, or sunset to sunrise) is followed by
// b1air-gamma itself.
//
// The page reads and writes Settings only: copies of its own stopped
// following Settings the first time it wrote them, so a change from the
// Control Center tile afterwards did not show here.
// =============================================================================

ColumnLayout {
    id: section

    Layout.fillWidth: true
    spacing: Design.s(Design.space.lg)

    readonly property bool nightLightEnabled: Settings.nightLightEnabled
    // While the slider moves, the number follows the finger; the screen is
    // told once it settles.
    property int dragTemp: -1
    readonly property int tempK: section.dragTemp >= 0 ? section.dragTemp : Settings.nightLightTemp

    readonly property string schedule: Settings.nightLightSchedule || "always"

    function applyTemp(enabled, temp) {
        section.applyAll({ nightLightEnabled: enabled, nightLightTemp: temp });
    }

    // One apply() instead of several set() calls. Two set() calls in a single
    // handler lose one of the two: each set() writes the file, and a write
    // started mid-handler clobbers the change that follows it — measured on
    // a live shell, five sets in one tick kept only the 1st, 3rd and 5th,
    // in memory as well as on disk. apply() mutates the adapter for every
    // key first and writes once, which is the shape that survives.
    //
    // The daemon is handed every value rather than reading them back from
    // the file, which may not have been written yet when it looks.
    function applyAll(changes) {
        const v = {
            nightLightEnabled: Settings.nightLightEnabled,
            nightLightTemp: Settings.nightLightTemp,
            nightLightSchedule: section.schedule,
            nightLightFrom: Settings.nightLightFrom || "20:00",
            nightLightTo: Settings.nightLightTo || "07:00",
            nightLightLocation: Settings.nightLightLocation || ""
        };
        for (const k in changes)
            v[k] = changes[k];
        Settings.apply(v);
        Quickshell.execDetached(v.nightLightEnabled
            ? ["b1air-daemon", "night-light", "on", String(v.nightLightTemp), "--quiet",
               "--schedule", v.nightLightSchedule, "--from", v.nightLightFrom, "--to", v.nightLightTo,
               "--location", v.nightLightLocation]
            : ["b1air-daemon", "night-light", "off", "--quiet"]);
        preview.refresh();
    }

    /** "HH:MM" moved by `delta` minutes, round the clock. */
    function shiftTime(hhmm, delta) {
        const parts = String(hhmm).split(":");
        let m = (parseInt(parts[0]) || 0) * 60 + (parseInt(parts[1]) || 0) + delta;
        m = ((m % 1440) + 1440) % 1440;
        const pad = n => (n < 10 ? "0" : "") + n;
        return pad(Math.floor(m / 60)) + ":" + pad(m % 60);
    }

    // What b1air-gamma would do with these settings, now: tonight's hours
    // and where it thinks the sun is. Asked of the program itself, so the
    // page shows the same sunset the screen will follow.
    QtObject {
        id: preview
        property string night: ""
        property string location: ""
        function refresh() {
            const loc = String(Settings.nightLightLocation || "").split(",").map(x => x.trim());
            const args = ["b1air-gamma", "--print", "--mode", section.schedule,
                          "--from", Settings.nightLightFrom || "20:00", "--to", Settings.nightLightTo || "07:00"];
            if (loc.length === 2 && loc[0] !== "" && loc[1] !== "")
                args.push("--lat", loc[0], "--lon", loc[1]);
            previewProc.command = args;
            previewProc.running = false;
            previewProc.running = true;
        }
    }

    Process {
        id: previewProc
        stdout: StdioCollector {
            onStreamFinished: {
                let night = "", location = "";
                for (const line of this.text.split("\n")) {
                    if (line.startsWith("night=")) night = line.slice(6);
                    else if (line.startsWith("location=")) location = line.slice(9);
                }
                preview.night = night;
                preview.location = location;
            }
        }
    }

    Component.onCompleted: preview.refresh()
    onVisibleChanged: if (visible) preview.refresh()

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
        title: I18n.tr("Night Light")
        subtitle: section.nightLightEnabled
            ? I18n.tr("Active at %1K color temperature", section.tempK)
            : I18n.tr("Reduce blue light in evening hours to protect sleep")
        icon: "\u{f0599}"
        accentColor: Design.yellow

        Toggle {
            label: I18n.tr("Night Light")
            subtitle: I18n.tr("Shift the screen towards warm colours to go easier on the eyes at night")
            checked: section.nightLightEnabled
            onToggled: section.applyTemp(!section.nightLightEnabled, section.tempK)
        }
    }

    // ── 2. Color Temperature Slider & Presets ────────────────────────────────
    Card {
        visible: section.nightLightEnabled
        title: I18n.tr("Color Temperature")
        subtitle: I18n.tr("Lower values produce warmer, amber tones with less blue light")
        icon: "\u{f0590}"
        accentColor: Design.yellow

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.md)

            RowLayout {
                Layout.fillWidth: true
                Label { text: I18n.tr("Color Warmth"); weight: Design.weight.semibold }
                Item { Layout.fillWidth: true }
                Label { text: section.tempK + " K"; role: "caption"; isMono: true; color: Design.yellow }
            }

            // Slider: 1900K (a candle flame, as warm as f.lux and gammastep
            // go) to 6500K, mapped to 0..100.
            Slider {
                Layout.fillWidth: true
                Layout.preferredHeight: Design.s(Design.size.ctl)
                value: Math.round(((section.tempK - 1900) / 4600) * 100)
                tone: Design.yellow
                icon: "\u{f0590}"
                onMoved: pct => {
                    section.dragTemp = Math.round((1900 + (pct / 100) * 4600) / 100) * 100;
                    dragSettle.restart();
                }
            }

            Label { text: I18n.tr("Quick Warmth Presets"); role: "caption"; dim: true }

            Flow {
                Layout.fillWidth: true
                spacing: Design.s(Design.space.xs)

                Pill {
                    label: I18n.tr("Candle (1900K)")
                    active: section.tempK === 1900
                    onClicked: section.applyTemp(true, 1900)
                }

                Pill {
                    label: I18n.tr("Incandescent (2700K)")
                    active: section.tempK === 2700
                    onClicked: section.applyTemp(true, 2700)
                }

                Pill {
                    label: I18n.tr("Halogen (3400K)")
                    active: section.tempK === 3400
                    onClicked: section.applyTemp(true, 3400)
                }

                Pill {
                    label: I18n.tr("Sunset (4500K)")
                    active: section.tempK === 4500
                    onClicked: section.applyTemp(true, 4500)
                }

                Pill {
                    label: I18n.tr("Daylight (6500K)")
                    active: section.tempK === 6500
                    onClicked: section.applyTemp(true, 6500)
                }
            }
        }
    }

    // ── 3. Schedule ──────────────────────────────────────────────────────────
    Card {
        visible: section.nightLightEnabled
        title: I18n.tr("Schedule")
        subtitle: section.schedule === "always"
            ? I18n.tr("Warm all the time while Night Light is on")
            : preview.night === "none" ? I18n.tr("The sun does not set here today")
            : preview.night === "all" ? I18n.tr("The sun does not rise here today")
            : preview.night === "unknown" ? I18n.tr("No location: enter one below")
            : preview.night !== "" ? I18n.tr("Warm from %1 to %2", preview.night.split("-")[0], preview.night.split("-")[1])
            : ""
        icon: "\u{f0150}"
        accentColor: Design.yellow

        Flow {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.xs)

            Pill {
                label: I18n.tr("Always")
                active: section.schedule === "always"
                onClicked: section.applyAll({ nightLightSchedule: "always" })
            }
            Pill {
                label: I18n.tr("Set hours")
                active: section.schedule === "hours"
                onClicked: section.applyAll({ nightLightSchedule: "hours" })
            }
            Pill {
                label: I18n.tr("Sunset to sunrise")
                active: section.schedule === "sun"
                onClicked: section.applyAll({ nightLightSchedule: "sun" })
            }
        }

        Stepper {
            visible: section.schedule === "hours"
            label: I18n.tr("From")
            valueText: Settings.nightLightFrom || "20:00"
            onDecrement: section.applyAll({ nightLightFrom: section.shiftTime(Settings.nightLightFrom || "20:00", -15) })
            onIncrement: section.applyAll({ nightLightFrom: section.shiftTime(Settings.nightLightFrom || "20:00", 15) })
        }

        Stepper {
            visible: section.schedule === "hours"
            label: I18n.tr("Until")
            valueText: Settings.nightLightTo || "07:00"
            onDecrement: section.applyAll({ nightLightTo: section.shiftTime(Settings.nightLightTo || "07:00", -15) })
            onIncrement: section.applyAll({ nightLightTo: section.shiftTime(Settings.nightLightTo || "07:00", 15) })
        }

        Label {
            visible: section.schedule === "sun"
            Layout.fillWidth: true
            text: Settings.nightLightLocation
                ? I18n.tr("Sun times for %1.", Settings.nightLightLocation)
                : preview.location !== ""
                    ? I18n.tr("Sun times for your time zone (%1). For a closer match, enter your location.",
                              preview.location.split(" ").slice(1).join(" ") || preview.location)
                    : I18n.tr("Your time zone has no known location. Enter yours to follow the sun.")
            role: "caption"
            dim: true
            wrapMode: Text.WordWrap
        }

        Field {
            visible: section.schedule === "sun"
            Layout.fillWidth: true
            mono: true
            text: Settings.nightLightLocation || ""
            placeholder: I18n.tr("Latitude, longitude — e.g. 50.45, 30.52. Empty: from the time zone")
            validator: RegularExpressionValidator { regularExpression: /^\s*(-?[0-9]{1,2}(\.[0-9]+)?\s*,\s*-?[0-9]{1,3}(\.[0-9]+)?)?\s*$/ }
            onCommitted: v => {
                const t = v.trim();
                if (t === (Settings.nightLightLocation || "")) return;
                section.applyAll({ nightLightLocation: t });
            }
        }

        Label {
            Layout.fillWidth: true
            visible: section.schedule !== "always"
            text: I18n.tr("Colours change over half an hour at each end.")
            role: "caption"
            dim: true
            wrapMode: Text.WordWrap
        }
    }
}
