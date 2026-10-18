import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../Ui"
import "../../Services"
import B1air.Daemon

// =============================================================================
// Screenshots & Screen Capture Settings
// =============================================================================

ColumnLayout {
    id: section

    Layout.fillWidth: true
    spacing: Design.s(Design.space.lg)

    property string screenshotDir: Settings.screenshotDir || (Quickshell.env("HOME") + "/Pictures/Screenshots")
    property string screenshotFormat: Settings.screenshotFormat || "png"
    property bool screenshotCopyToClipboard: Settings.screenshotCopyToClipboard !== undefined ? Settings.screenshotCopyToClipboard : true
    property bool screenshotSaveToFile: Settings.screenshotSaveToFile !== undefined ? Settings.screenshotSaveToFile : true
    property int screenshotDelay: Settings.screenshotDelay !== undefined ? Settings.screenshotDelay : 0

    function takeScreenshot(mode) {
        Daemon.captureWithGeometry(mode);
    }

    // ── 1. Storage & Output ──────────────────────────────────────────────────
    SettingsGroup {
        title: I18n.tr("Screenshot Destination & Format")
        icon: "\u{f016d}"

        SettingsRow {
            label: I18n.tr("Save Folder")
            note: section.screenshotDir
            Button {
                label: I18n.tr("Open Folder")
                icon: "\u{f07b}"
                onActivated: Quickshell.execDetached(["xdg-open", section.screenshotDir])
            }
        }

        SettingsRow {
            label: I18n.tr("Image Format")
            SegmentedControl {
                size: "sm"
                Layout.preferredWidth: Design.s(Design.width.segment)
                model: [
                    { id: "png",  label: "PNG" },
                    { id: "jpg",  label: "JPG" },
                    { id: "webp", label: "WEBP" }
                ]
                current: section.screenshotFormat
                onPicked: function(id) {
                    section.screenshotFormat = id;
                    Settings.set("screenshotFormat", id);
                }
            }
        }

        SwitchRow {
            label: I18n.tr("Save File to Disk")
            checked: section.screenshotSaveToFile
            onToggled: {
                const next = !section.screenshotSaveToFile;
                section.screenshotSaveToFile = next;
                Settings.set("screenshotSaveToFile", next);
            }
        }

        SwitchRow {
            label: I18n.tr("Copy to Clipboard")
            checked: section.screenshotCopyToClipboard
            onToggled: {
                const next = !section.screenshotCopyToClipboard;
                section.screenshotCopyToClipboard = next;
                Settings.set("screenshotCopyToClipboard", next);
            }
        }
    }

    // ── 2. Quick Capture & Timing ────────────────────────────────────────────
    SettingsGroup {
        title: I18n.tr("Capture Actions & Delay")
        icon: "\u{f002}"

        SettingsRow {
            label: I18n.tr("Capture Delay")
            Stepper {
                valueText: section.screenshotDelay === 0 ? I18n.tr("Instant") : I18n.tr("%1 sec", section.screenshotDelay)
                onDecrement: {
                    const next = Math.max(0, section.screenshotDelay - 1);
                    section.screenshotDelay = next;
                    Settings.set("screenshotDelay", next);
                }
                onIncrement: {
                    const next = Math.min(10, section.screenshotDelay + 1);
                    section.screenshotDelay = next;
                    Settings.set("screenshotDelay", next);
                }
            }
        }

        // Commands, not settings: a row of their own, under the delay
        // they use.
        SettingsRow {
            label: I18n.tr("Take a screenshot")
            Button {
                icon: "\u{f0b2}"
                label: I18n.tr("Area")
                onActivated: section.takeScreenshot("area")
            }
            Button {
                icon: "\u{f065}"
                label: I18n.tr("Full Screen")
                onActivated: section.takeScreenshot("full")
            }
        }
    }
}
