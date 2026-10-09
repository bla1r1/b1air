import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../Ui"
import "../../Services"

// =============================================================================
// Privacy: what the desktop keeps about you, in one place, and how to stop
// it or wipe it. Each of these lived somewhere else or nowhere — the screen
// time recorder was a switch in "Focus Automation", the clipboard history
// could only be cleared from its popup, the trash kept for 30 days unless
// Files' own menu said otherwise, and a weather city or a night-light
// position, once typed in, stayed with no sign that they were stored.
// =============================================================================

ColumnLayout {
    id: section

    Layout.fillWidth: true
    spacing: Design.s(Design.space.lg)

    // ── Screen time ──────────────────────────────────────────────────────────
    property string forgetStatus: ""
    Process {
        id: forgetStats
        command: ["b1air-daemon", "stats", "forget"]
        onExited: code => section.forgetStatus = code === 0 ? I18n.tr("Screen time history deleted")
                                                             : I18n.tr("Could not delete the screen time history")
    }

    Card {
        title: I18n.tr("Screen time")
        subtitle: I18n.tr("Which app was in front and for how long, kept on this computer only")
        icon: "\u{f051e}"
        accentColor: Design.teal

        Toggle {
            label: I18n.tr("Record screen time")
            subtitle: I18n.tr("Off: nothing is recorded from the next login, and Screen Time & Focus stays empty")
            checked: Settings.focusDaemonAutoStart !== false
            onToggled: Settings.set("focusDaemonAutoStart", !(Settings.focusDaemonAutoStart !== false))
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.md)
            Label {
                Layout.fillWidth: true
                text: section.forgetStatus !== "" ? section.forgetStatus : I18n.tr("Everything recorded so far, every day")
                role: "caption"
                dim: section.forgetStatus === ""
                wrapMode: Text.WordWrap
            }
            ActionButton {
                Layout.fillWidth: false
                icon: "\u{f0a7a}"
                label: I18n.tr("Delete history")
                destructive: true
                confirmLabel: I18n.tr("Delete?")
                onActivated: forgetStats.running = true
            }
        }
    }

    // ── Clipboard ────────────────────────────────────────────────────────────
    property bool clipCleared: false

    Card {
        title: I18n.tr("Clipboard history")
        subtitle: I18n.tr("What was copied, kept so it can be pasted again (Mod+Ctrl+V)")
        icon: "\u{f014c}"
        accentColor: Design.sapphire

        RowLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.md)
            Label {
                Layout.fillWidth: true
                text: section.clipCleared ? I18n.tr("Cleared. Pinned entries were kept.")
                                          : I18n.tr("Pinned entries stay; everything else goes")
                role: "caption"
                dim: !section.clipCleared
                wrapMode: Text.WordWrap
            }
            ActionButton {
                Layout.fillWidth: false
                icon: "\u{f0a7a}"
                label: I18n.tr("Clear history")
                destructive: true
                confirmLabel: I18n.tr("Clear?")
                onActivated: { Clipboard.clearHistory(); section.clipCleared = true; }
            }
        }
    }

    // ── Trash ────────────────────────────────────────────────────────────────
    // Files' own preference (~/.config/b1air/files_prefs.json, trashPurgeDays):
    // read and written here as the whole file, so Files' other choices stay.
    property var filesPrefs: ({})
    readonly property int trashDays: section.filesPrefs.trashPurgeDays !== undefined
        ? section.filesPrefs.trashPurgeDays : 30
    readonly property var trashSteps: [0, 1, 7, 14, 30, 60, 90, 180, 365]

    FileView {
        id: filesPrefsFile
        path: Quickshell.env("HOME") + "/.config/b1air/files_prefs.json"
        printErrors: false
        watchChanges: true
        onLoaded: {
            try { section.filesPrefs = JSON.parse(text() || "{}") || {}; } catch (e) { section.filesPrefs = {}; }
        }
        onFileChanged: reload()
    }

    function setTrashDays(days) {
        const p = Object.assign({}, section.filesPrefs);
        p.trashPurgeDays = days;
        section.filesPrefs = p;
        filesPrefsFile.setText(JSON.stringify(p, null, 2));
    }
    function stepTrash(dir) {
        const steps = section.trashSteps;
        let i = steps.indexOf(section.trashDays);
        if (i < 0) i = steps.findIndex(s => s > section.trashDays);
        if (i < 0) i = steps.length - 1;
        section.setTrashDays(steps[Math.max(0, Math.min(steps.length - 1, i + dir))]);
    }

    // The names of the files in the home folder, for Spotlight
    // (daemon/file_index): kept in ~/.cache/b1air/files-index.db.
    Card {
        title: I18n.tr("File search")
        Toggle {
            label: I18n.tr("Index file names for Spotlight")
            subtitle: I18n.tr("Names only, not what is in the files; hidden folders and network drives are left out")
            checked: Settings.fileIndex !== false
            onToggled: Settings.set("fileIndex", !(Settings.fileIndex !== false))
        }
    }

    Card {
        title: I18n.tr("Trash")
        subtitle: I18n.tr("Deleted files are kept this long, then removed for good at login")
        icon: "\u{f0a7a}"
        accentColor: Design.peach

        Stepper {
            label: I18n.tr("Keep deleted files for")
            valueText: section.trashDays === 0 ? I18n.tr("Forever") : I18n.trn("%1 day", "%1 days", section.trashDays)
            onDecrement: section.stepTrash(-1)
            onIncrement: section.stepTrash(1)
        }
    }

    // ── Location ─────────────────────────────────────────────────────────────
    Card {
        title: I18n.tr("Location")
        subtitle: I18n.tr("Places typed into Settings, used for the weather and for sunset and sunrise")
        icon: "\u{f034e}"
        accentColor: Design.green

        RowLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.md)
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Label { text: I18n.tr("Weather"); weight: Design.weight.semibold }
                Label {
                    Layout.fillWidth: true
                    text: Settings.weatherCityId ? Settings.weatherCityId : I18n.tr("Not set")
                    role: "caption"; dim: true; elide: Text.ElideRight
                }
            }
            ActionButton {
                Layout.fillWidth: false
                visible: !!Settings.weatherCityId
                icon: "\u{f0156}"
                label: I18n.tr("Forget")
                onActivated: Settings.set("weatherCityId", "")
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.md)
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Label { text: I18n.tr("Night Light"); weight: Design.weight.semibold }
                Label {
                    Layout.fillWidth: true
                    text: Settings.nightLightLocation ? Settings.nightLightLocation : I18n.tr("Not set")
                    role: "caption"; dim: true; elide: Text.ElideRight
                }
            }
            ActionButton {
                Layout.fillWidth: false
                visible: !!Settings.nightLightLocation
                icon: "\u{f0156}"
                label: I18n.tr("Forget")
                onActivated: Settings.set("nightLightLocation", "")
            }
        }
    }

    // ── Camera and microphone ────────────────────────────────────────────────
    // Only words, nothing to set: not drawn (the dots in the bar say it).
    Card {
        visible: false
        title: I18n.tr("Camera and microphone")
        subtitle: I18n.tr("The top bar shows a red dot while the microphone records and an orange one while the camera does — always, so it cannot be missed")
        icon: "\u{f036c}"
        accentColor: Design.red
    }
}
