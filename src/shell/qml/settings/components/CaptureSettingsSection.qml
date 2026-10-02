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
    Card {
        title: I18n.tr("Screenshot Destination & Format")
        subtitle: I18n.tr("Configure where captured images are stored and their file formats")
        icon: "\u{f016d}"
        accentColor: Design.pink

        RowLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.md)

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Design.s(2)
                Label { text: I18n.tr("Save Folder"); weight: Design.weight.semibold }
                Label { text: section.screenshotDir; role: "caption"; dim: true }
            }

            Pill {
                label: I18n.tr("Open Folder")
                icon: "\u{f07b}"
                onClicked: Quickshell.execDetached(["xdg-open", section.screenshotDir])
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.md)

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Design.s(2)
                Label { text: I18n.tr("Image Format"); weight: Design.weight.semibold }
                Label { text: I18n.tr("File encoding type for saved captures"); role: "caption"; dim: true }
            }

            RowLayout {
                spacing: Design.s(Design.space.xs)
                Repeater {
                    model: ["png", "jpg", "webp"]
                    delegate: Pill {
                        label: modelData.toUpperCase()
                        active: section.screenshotFormat === modelData
                        onClicked: {
                            section.screenshotFormat = modelData;
                            Settings.set("screenshotFormat", modelData);
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.md)

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Design.s(2)
                Label { text: I18n.tr("Save File to Disk"); weight: Design.weight.semibold }
                Label { text: I18n.tr("Automatically write image file to the screenshots directory"); role: "caption"; dim: true }
            }

            Toggle {
                checked: section.screenshotSaveToFile
                onToggled: {
                    const next = !section.screenshotSaveToFile;
                    section.screenshotSaveToFile = next;
                    Settings.set("screenshotSaveToFile", next);
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.md)

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Design.s(2)
                Label { text: I18n.tr("Copy to Clipboard"); weight: Design.weight.semibold }
                Label { text: I18n.tr("Copy image directly into Wayland clipboard buffer"); role: "caption"; dim: true }
            }

            Toggle {
                checked: section.screenshotCopyToClipboard
                onToggled: {
                    const next = !section.screenshotCopyToClipboard;
                    section.screenshotCopyToClipboard = next;
                    Settings.set("screenshotCopyToClipboard", next);
                }
            }
        }
    }

    // ── 2. Quick Capture & Timing ────────────────────────────────────────────
    Card {
        title: I18n.tr("Capture Actions & Delay")
        subtitle: I18n.tr("Test capture triggers or adjust delay for dropdown menus")
        icon: "\u{f002}"
        accentColor: Design.teal

        Stepper {
            label: I18n.tr("Capture Delay")
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

        ButtonRow {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.sm)

            ActionButton {
                icon: "\u{f0b2}"
                label: I18n.tr("Capture Area")
                tone: Design.pink
                onActivated: section.takeScreenshot("area")
            }

            ActionButton {
                icon: "\u{f065}"
                label: I18n.tr("Capture Full Screen")
                tone: Design.teal
                onActivated: section.takeScreenshot("full")
            }
        }
    }
}
