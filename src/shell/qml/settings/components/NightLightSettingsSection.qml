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
    SettingsGroup {
        title: I18n.tr("Night Light")
        description: section.nightLightEnabled
            ? I18n.tr("Active at %1K color temperature", section.tempK)
            : I18n.tr("Reduce blue light in evening hours to protect sleep")

        SwitchRow {
            title: I18n.tr("Night Light")
            note: I18n.tr("Shift the screen towards warm colours to go easier on the eyes at night")
            checked: section.nightLightEnabled
            onToggled: section.applyTemp(!section.nightLightEnabled, section.tempK)
        }
    }

    // ── 2. Color Temperature Slider & Presets ────────────────────────────────
    SettingsGroup {
        visible: section.nightLightEnabled
        title: I18n.tr("Color Temperature")
        description: I18n.tr("Lower values produce warmer, amber tones with less blue light")

        Item {
            Layout.fillWidth: true
            Layout.leftMargin: Design.s(Design.space.rowPaddingX)
            Layout.rightMargin: Design.s(Design.space.rowPaddingX)
            Layout.topMargin: Design.s(Design.space.xs)
            Layout.bottomMargin: Design.s(Design.space.xs)
            implicitHeight: tempCol.implicitHeight

            ColumnLayout {
                id: tempCol
                anchors.fill: parent
                spacing: Design.s(Design.space.sm)

                RowLayout {
                    Layout.fillWidth: true
                    Label { text: I18n.tr("Color Warmth"); weight: Design.weight.semibold }
                    Item { Layout.fillWidth: true }
                    Label { text: section.tempK + " K"; role: "caption"; isMono: true; color: Design.textDim }
                }

                // Slider: 1900K to 6500K
                Slider {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Design.s(Design.size.md)
                    value: Math.round(((section.tempK - 1900) / 4600) * 100)
                    icon: "\u{f0590}"
                    onMoved: pct => {
                        section.dragTemp = Math.round((1900 + (pct / 100) * 4600) / 100) * 100;
                        dragSettle.restart();
                    }
                }
            }
        }

        SettingsRow {
            title: I18n.tr("Quick Warmth Presets")

            SegmentedControl {
                size: "sm"
                model: [
                    { id: "1900", label: "1900K" },
                    { id: "2700", label: "2700K" },
                    { id: "3400", label: "3400K" },
                    { id: "4500", label: "4500K" },
                    { id: "6500", label: "6500K" }
                ]
                current: String(section.tempK)
                onPicked: id => section.applyTemp(true, parseInt(id))
            }
        }
    }

    // ── 3. Schedule ──────────────────────────────────────────────────────────
    SettingsGroup {
        visible: section.nightLightEnabled
        title: I18n.tr("Schedule")
        description: section.schedule === "always"
            ? I18n.tr("Warm all the time while Night Light is on")
            : preview.night === "none" ? I18n.tr("The sun does not set here today")
            : preview.night === "all" ? I18n.tr("The sun does not rise here today")
            : preview.night === "unknown" ? I18n.tr("No location: enter one below")
            : preview.night !== "" ? I18n.tr("Warm from %1 to %2", preview.night.split("-")[0], preview.night.split("-")[1])
            : ""

        SettingsRow {
            title: I18n.tr("Mode")

            SegmentedControl {
                size: "sm"
                model: [
                    { id: "always", label: I18n.tr("Always") },
                    { id: "hours",  label: I18n.tr("Set hours") },
                    { id: "sun",    label: I18n.tr("Sunset to sunrise") }
                ]
                current: section.schedule
                onPicked: id => section.applyAll({ nightLightSchedule: id })
            }
        }

        SettingsRow {
            visible: section.schedule === "hours"
            title: I18n.tr("Active hours")

            RowLayout {
                spacing: Design.s(Design.space.md)

                SettingsRow {
                    label: I18n.tr("From")
                    Stepper {
                        valueText: Settings.nightLightFrom || "20:00"
                        onDecrement: section.applyAll({ nightLightFrom: section.shiftTime(Settings.nightLightFrom || "20:00", -15) })
                        onIncrement: section.applyAll({ nightLightFrom: section.shiftTime(Settings.nightLightFrom || "20:00", 15) })
                    }
                }

                SettingsRow {
                    label: I18n.tr("Until")
                    Stepper {
                        valueText: Settings.nightLightTo || "07:00"
                        onDecrement: section.applyAll({ nightLightTo: section.shiftTime(Settings.nightLightTo || "07:00", -15) })
                        onIncrement: section.applyAll({ nightLightTo: section.shiftTime(Settings.nightLightTo || "07:00", 15) })
                    }
                }
            }
        }

        Item {
            visible: section.schedule === "sun"
            Layout.fillWidth: true
            Layout.leftMargin: Design.s(Design.space.rowPaddingX)
            Layout.rightMargin: Design.s(Design.space.rowPaddingX)
            Layout.topMargin: Design.s(Design.space.xs)
            Layout.bottomMargin: Design.s(Design.space.xs)
            implicitHeight: sunCol.implicitHeight

            ColumnLayout {
                id: sunCol
                anchors.fill: parent
                spacing: Design.s(Design.space.xs)

                Label {
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
            }
        }

        Item {
            visible: section.schedule !== "always"
            Layout.fillWidth: true
            Layout.leftMargin: Design.s(Design.space.rowPaddingX)
            Layout.bottomMargin: Design.s(Design.space.xs)
            implicitHeight: noteLbl.implicitHeight

            Label {
                id: noteLbl
                anchors.fill: parent
                text: I18n.tr("Colours change over half an hour at each end.")
                role: "caption"
                dim: true
                wrapMode: Text.WordWrap
            }
        }
    }
}
