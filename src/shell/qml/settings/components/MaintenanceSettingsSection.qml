import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../Ui"
import "../../Services"
import B1air.Daemon

// =============================================================================
// System Maintenance & Package Updates
// =============================================================================

ColumnLayout {
    id: section

    // "updates": the Updates page (this desktop's and the system's).
    // "": Storage & Backup (backups, cleanup, restore points, vaults, reset).
    property string part: ""

    Layout.fillWidth: true
    spacing: Design.s(Design.space.lg)

    property int updateCount: 0
    property string statusText: I18n.tr("Checking for updates…")
    property string manager: ""
    property string transferStatus: ""

    // The daemon does the work; both buttons name the same file in the home
    // folder, because a settings page has no file dialog and the point is to
    // have something to copy to a USB stick or scp across.
    readonly property string transferFile: Quickshell.env("HOME") + "/b1air-config.json"

    function exportConfig() {
        transferProc.command = ["b1air-daemon", "config", "export", section.transferFile];
        section.transferStatus = I18n.tr("Exporting…");
        transferProc.running = false;
        transferProc.running = true;
    }

    function importConfig() {
        transferProc.command = ["b1air-daemon", "config", "import", section.transferFile];
        section.transferStatus = I18n.tr("Importing…");
        transferProc.running = false;
        transferProc.running = true;
    }

    Process {
        id: transferProc
        stdout: StdioCollector {
            onStreamFinished: section.transferStatus = this.text.trim() || "Done."
        }
        stderr: StdioCollector {
            onStreamFinished: if (this.text.trim()) section.transferStatus = this.text.trim()
        }
    }
    property bool isChecking: false

    // Desktop (this repository) — the same fields the Updates popup reads.
    property bool dotChecking: true
    property bool dotFound: true
    property bool dotFetchOk: true
    property bool dotDirty: false
    property int dotBehind: 0
    property int dotAhead: 0
    property string dotBranch: ""
    property string dotHash: ""
    property string dotRemote: ""
    property var dotIncoming: []
    readonly property bool dotfilesUpdateAvail: !dotChecking && dotBehind > 0
    readonly property bool dotCanUpdate: dotfilesUpdateAvail && !dotDirty && dotAhead === 0
    readonly property string managerName: {
        switch (section.manager) {
            case "pacman": return "pacman / AUR";
            case "apt":    return "APT";
            case "dnf":    return "DNF";
            case "zypper": return "zypper";
            default:       return I18n.tr("the package manager");
        }
    }

    Process {
        id: updateChecker
        // The daemon knows every package manager (pacman, apt, dnf, zypper)
        // plus the AUR; this used to call Arch's checkupdates directly.
        command: ["b1air-daemon", "updates"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                section.isChecking = false;
                let count = 0;
                try {
                    const d = JSON.parse(this.text.trim());
                    count = parseInt(d.alt, 10) || 0;
                    section.manager = d.manager || "";
                } catch (e) {}
                section.updateCount = count;
                section.statusText = count > 0 ? I18n.trn("%1 package update available", "%1 package updates available", count) : I18n.tr("System packages are up to date");
            }
        }
    }

    Process {
        id: dotfilesChecker
        command: ["b1air-daemon", "dotfiles", "status"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                section.dotChecking = false;
                let data;
                try { data = JSON.parse(this.text.trim()); } catch (e) { data = { ok: false }; }
                section.dotFound = !!data.ok;
                if (!data.ok) return;
                section.dotFetchOk = data.fetch_ok !== false;
                section.dotDirty = !!data.dirty;
                section.dotBehind = data.behind || 0;
                section.dotAhead = data.ahead || 0;
                section.dotBranch = data.branch || "";
                section.dotHash = data.local_hash || "";
                section.dotRemote = data.remote_ref || "";
                section.dotIncoming = data.incoming || [];
            }
        }
    }

    function checkNow() {
        section.isChecking = true;
        section.statusText = I18n.tr("Checking for updates…");
        section.dotChecking = true;
        updateChecker.running = true;
        dotfilesChecker.running = true;
    }

    function runSystemUpdate() {
        Daemon.dotfilesSys();
    }

    function runDotfilesUpdate() {
        Daemon.dotfilesSync();
    }

    function viewBackups() {
        Quickshell.execDetached(["xdg-open", Quickshell.env("HOME") + "/.dotfiles-backups"]);
    }

    // The daemon picks the package manager and opens a terminal that stays
    // on what it printed.
    function cleanPackageCache() {
        Quickshell.execDetached(["b1air-daemon", "packages", "clean-cache"]);
    }

    function cleanOrphanPackages() {
        Quickshell.execDetached(["b1air-daemon", "packages", "clean-orphans"]);
    }

    // ── 1. Desktop Environment Updates ───────────────────────────────────────
    //
    // It said "Desktop environment is up to date" from the moment the page
    // opened, beside "Local: ... • Remote: ..." that had not been read yet, and
    // "Sync UI & Packages" ran an update that did not pull. It now says what
    // the check found once it has, lists what an update would bring, and the
    // button pulls (and says why it cannot, when it cannot).
    Card {
        visible: section.part === "updates"
        title: I18n.tr("Desktop Updates")
        subtitle: section.dotRemote ? I18n.tr("This desktop's own code and configuration, from %1", section.dotRemote)
                                     : I18n.tr("This desktop's own code and configuration")
        icon: "\u{f021}"
        accentColor: section.dotfilesUpdateAvail ? Design.ok : Design.sapphire

        RowLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.md)

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Design.s(2)
                Label {
                    text: section.dotChecking ? I18n.tr("Checking…")
                          : !section.dotFound ? I18n.tr("Repository not found — run install.sh from your clone once")
                          : section.dotBehind > 0 ? I18n.trn("%1 new change", "%1 new changes", section.dotBehind)
                          : section.dotFetchOk ? I18n.tr("Up to date") : I18n.tr("Could not reach the remote")
                    weight: Design.weight.semibold
                    color: section.dotfilesUpdateAvail ? Design.ok : Design.text
                }
                Label {
                    visible: !section.dotChecking && section.dotFound
                    text: I18n.tr("On %1 at %2", section.dotBranch, section.dotHash)
                          + (section.dotAhead > 0 ? " · " + I18n.trn("%1 local commit not pushed", "%1 local commits not pushed", section.dotAhead) : "")
                    role: "caption"
                    dim: true
                }
            }

            Pill {
                label: I18n.tr("Check")
                icon: "\u{f021}"
                onClicked: section.checkNow()
            }
        }

        // The first few incoming changes; the Updates popup lists them all.
        Repeater {
            model: section.dotIncoming.slice(0, 5)
            delegate: RowLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: Design.s(Design.space.sm)
                Label { text: modelData.hash; role: "caption"; isMono: true; dim: true }
                Label { Layout.fillWidth: true; text: modelData.subject; role: "caption"; elide: Text.ElideRight }
            }
        }
        Label {
            visible: section.dotIncoming.length > 5
            text: I18n.tr("…and %1 more", (section.dotIncoming.length - 5))
            role: "caption"
            dim: true
        }

        Label {
            Layout.fillWidth: true
            visible: section.dotfilesUpdateAvail && !section.dotCanUpdate
            text: section.dotDirty
                  ? I18n.tr("You have uncommitted edits in the dotfiles clone. Commit or stash them first — the update will not overwrite them.")
                  : I18n.tr("Your clone has commits the remote does not, so it cannot simply move forward. Merge or rebase it yourself.")
            role: "caption"
            color: Design.warn
            wrapMode: Text.WordWrap
        }

        ButtonRow {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.sm)

            ActionButton {
                icon: "\u{f06b0}"
                label: section.dotCanUpdate ? I18n.tr("Update now") : I18n.tr("Nothing to update")
                tone: section.dotCanUpdate ? Design.ok : Design.textDim
                enabled: section.dotCanUpdate
                onActivated: section.runDotfilesUpdate()
            }

            ActionButton {
                icon: "\u{f07c}"
                label: I18n.tr("View Backups")
                tone: Design.textDim
                onActivated: section.viewBackups()
            }
        }
    }

    // ── Moving this configuration to another machine ─────────────────────────
    Card {
        visible: section.part === ""
        title: I18n.tr("Settings Backup & Transfer")
        subtitle: I18n.tr("One file holding this desktop's settings, themes, pinned apps and bookmarks")
        icon: "\u{f0193}"
        accentColor: Design.teal

        Label {
            Layout.fillWidth: true
            text: I18n.tr("Display layout, the main-screen choice and disabled sound devices stay behind: they name hardware, and on another machine they describe screens and cards that are not there. The weather API key is not included either — it lives in the secret store, and a credential does not belong in a file meant to be copied.")
            role: "caption"
            dim: true
            wrapMode: Text.WordWrap
        }

        Label {
            Layout.fillWidth: true
            text: section.transferStatus
            role: "caption"
            color: Design.accent
            visible: section.transferStatus !== ""
            wrapMode: Text.WordWrap
        }

        ButtonRow {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.sm)

            ActionButton {
                icon: "\u{f0552}"
                label: I18n.tr("Export to Home Folder")
                tone: Design.teal
                onActivated: section.exportConfig()
            }

            ActionButton {
                icon: "\u{f0552}"
                label: I18n.tr("Import from Home Folder")
                tone: Design.sapphire
                onActivated: section.importConfig()
            }
        }
    }

    // ── 2. System Packages Updates ───────────────────────────────────────────
    Card {
        visible: section.part === "updates"
        title: I18n.tr("System Packages")
        subtitle: I18n.tr("Kernel, drivers and applications, managed by %1", section.managerName)
        icon: "\u{f0187}"
        accentColor: section.updateCount > 0 ? Design.peach : Design.green

        RowLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.md)

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Design.s(2)
                Label { text: I18n.tr("Update Status") }
            }

            Pill {
                label: I18n.tr("Check")
                icon: "\u{f021}"
                onClicked: section.checkNow()
            }
        }

        ButtonRow {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.sm)

            // The three actions on this page and the next remove packages, wipe
            // caches or start a full system upgrade, and each was a single
            // click in a page people scroll through. ActionButton already has
            // the arm-then-confirm step — "Reset Defaults" in About and the
            // power row in the Control Center use it — and these deserve it at
            // least as much.
            ActionButton {
                icon: "\u{f0187}"
                label: section.updateCount > 0 ? I18n.trn("Upgrade %1 Package", "Upgrade %1 Packages", section.updateCount) : I18n.tr("Run Full System Upgrade")
                tone: section.updateCount > 0 ? Design.peach : Design.green
                destructive: true
                confirmLabel: I18n.tr("Start upgrade?")
                onActivated: section.runSystemUpdate()
            }
        }
    }

    // ── 3. Disk Sweeper & Cache Maintenance (M4) ─────────────────────────────
    Card {
        visible: section.part === ""
        title: I18n.tr("Disk Sweeper & Storage Maintenance")
        subtitle: I18n.tr("Free up storage by clearing the package cache, systemd journals, and thumbnail cache")
        icon: "\u{f014}"
        accentColor: Design.mauve

        ButtonRow {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.sm)

            ActionButton {
                icon: "\u{f014}"
                label: I18n.tr("Clean All Caches & Logs")
                tone: Design.sapphire
                destructive: true
                confirmLabel: I18n.tr("Delete them?")
                onActivated: Daemon.sweeperClean()
            }

            ActionButton {
                icon: "\u{f128}"
                label: I18n.tr("Remove Orphan Packages")
                tone: Design.mauve
                destructive: true
                confirmLabel: I18n.tr("Uninstall them?")
                onActivated: section.cleanOrphanPackages()
            }
        }
    }

    // ── 4. System Restore Points & Snapshots (M4) ─────────────────────────────
    // Which snapshot tool exists, so the button is not offered where it can
    // only fail ("timeshift" first: the daemon tries it first too).
    readonly property string snapshotTool: Sys.commandExists("timeshift") ? "timeshift"
                                         : Sys.commandExists("snapper") ? "snapper" : ""

    Card {
        visible: section.part === ""
        title: I18n.tr("Restore Points")
        subtitle: section.snapshotTool !== ""
                  ? I18n.tr("Snapshot the system with %1 before a big update", section.snapshotTool)
                  : I18n.tr("Snapshots need timeshift, or snapper on a Btrfs root — neither is installed")
        icon: "\u{f0c7}"
        accentColor: Design.teal

        ButtonRow {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.sm)

            ActionButton {
                icon: "\u{f0c7}"
                label: I18n.tr("Create Restore Point")
                tone: Design.teal
                enabled: section.snapshotTool !== ""
                onActivated: Cmd.run(["b1air-daemon", "snapshot", "create", "Manual user snapshot"], "Create snapshot")
            }
        }
    }

    // ── 5. Encrypted Vaults Manager (M4) ──────────────────────────────────────
    Card {
        visible: section.part === ""
        title: I18n.tr("Encrypted Security Vaults")
        subtitle: I18n.tr("Mount and secure confidential directories using client-side encryption")
        icon: "\u{f023}"
        accentColor: Design.peach

        ButtonRow {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.sm)

            ActionButton {
                icon: "\u{f07c}"
                label: I18n.tr("Open Secure Vaults Location")
                tone: Design.peach
                onActivated: {
                    Sys.makeDir("~/.vaults");
                    Quickshell.execDetached(["xdg-open", Quickshell.env("HOME") + "/.vaults"]);
                }
            }
        }
    }

    // The desktop itself: reload it, or put every setting back. These were
    // on About, a page otherwise only about what this computer is.
    Card {
        visible: section.part === ""
        title: I18n.tr("Desktop")
        subtitle: I18n.tr("Reload the desktop, or put every setting back to its default")
        icon: "\u{f0493}"
        accentColor: Design.mauve

        ButtonRow {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.sm)

            ActionButton {
                icon: "\u{f0709}"
                label: I18n.tr("Reload Sway & Quickshell")
                onActivated: { Sway.command("reload"); Quickshell.execDetached(["b1air-shell", "forceReload"]); }
            }

            ActionButton {
                icon: "\u{f0450}"
                label: I18n.tr("Reset Defaults")
                destructive: true
                onActivated: Settings.resetDefaults()
            }
        }
    }
}
