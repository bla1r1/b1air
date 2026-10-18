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
    SettingsGroup {
        visible: section.part === "updates"
        title: I18n.tr("Desktop Updates")
        subtitle: section.dotRemote ? I18n.tr("This desktop's own code and configuration, from %1", section.dotRemote)
                                     : I18n.tr("This desktop's own code and configuration")
        icon: "\u{f021}"

        // The state is the row; Update now is offered only when there is
        // something to update, rather than drawn disabled as "Nothing to update".
        SettingsRow {
            label: section.dotChecking ? I18n.tr("Checking…")
                  : !section.dotFound ? I18n.tr("Repository not found — run install.sh from your clone once")
                  : section.dotBehind > 0 ? I18n.trn("%1 new change", "%1 new changes", section.dotBehind)
                  : section.dotFetchOk ? I18n.tr("Up to date") : I18n.tr("Could not reach the remote")
            note: (!section.dotChecking && section.dotFound)
                  ? I18n.tr("On %1 at %2", section.dotBranch, section.dotHash)
                    + (section.dotAhead > 0 ? " · " + I18n.trn("%1 local commit not pushed", "%1 local commits not pushed", section.dotAhead) : "")
                  : ""

            Button {
                label: I18n.tr("Check")
                icon: "\u{f021}"
                onClicked: section.checkNow()
            }
            Button {
                visible: section.dotCanUpdate
                variant: "primary"
                icon: "\u{f06b0}"
                label: I18n.tr("Update now")
                onActivated: section.runDotfilesUpdate()
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

        SettingsRow {
            label: I18n.tr("Backups")
            Button {
                icon: "\u{f07c}"
                label: I18n.tr("View Backups")
                onActivated: section.viewBackups()
            }
        }
    }

    // ── Moving this configuration to another machine ─────────────────────────
    // Each command a row: what it does on the left, its button on the right.
    // They hung as a bar of buttons under a paragraph.
    SettingsGroup {
        visible: section.part === ""
        title: I18n.tr("Settings Backup & Transfer")
        subtitle: I18n.tr("One file holding this desktop's settings, themes, pinned apps and bookmarks")
        icon: "\u{f0193}"

        SettingsRow {
            label: I18n.tr("Export to Home Folder")
            note: I18n.tr("Display layout, the main-screen choice and disabled sound devices stay behind: they name hardware, and on another machine they describe screens and cards that are not there. The weather API key is not included either — it lives in the secret store, and a credential does not belong in a file meant to be copied.")
            Button {
                icon: "\u{f0552}"
                label: I18n.tr("Export")
                onActivated: section.exportConfig()
            }
        }

        SettingsRow {
            label: I18n.tr("Import from Home Folder")
            note: section.transferStatus
            Button {
                icon: "\u{f0552}"
                label: I18n.tr("Import")
                onActivated: section.importConfig()
            }
        }
    }

    // ── 2. System Packages Updates ───────────────────────────────────────────
    SettingsGroup {
        visible: section.part === "updates"
        title: I18n.tr("System Packages")
        subtitle: I18n.tr("Kernel, drivers and applications, managed by %1", section.managerName)
        icon: "\u{f0187}"

        // The three actions on this page and the next remove packages, wipe
        // caches or start a full system upgrade, and each was a single click
        // in a page people scroll through: each arms first, then confirms.
        SettingsRow {
            label: section.statusText
            Button {
                label: I18n.tr("Check")
                icon: "\u{f021}"
                onClicked: section.checkNow()
            }
            Button {
                icon: "\u{f0187}"
                label: section.updateCount > 0 ? I18n.trn("Upgrade %1 Package", "Upgrade %1 Packages", section.updateCount) : I18n.tr("Run Full System Upgrade")
                destructive: true
                confirmText: I18n.tr("Start upgrade?")
                onActivated: section.runSystemUpdate()
            }
        }
    }

    // ── Edition ──────────────────────────────────────────────────────────────
    // packages/editions/ in the repository this desktop was installed from,
    // and the one installed (/etc/b1air/edition). Switching runs
    // update-dotfiles.sh --edition in a terminal: the package manager asks,
    // and what it installs is shown. Nothing is removed going to a smaller one.
    property string editionRepo: ""
    property string editionNow: ""
    property var editions: []      // [{ name, desc, parent }], each after its parent

    Process {
        id: editionProbe
        running: section.part === "updates" && section.visible
        command: ["sh", "-c",
            "repo=$(cat \"${XDG_STATE_HOME:-$HOME/.local/state}/b1air/dotfiles-repo\" 2>/dev/null); "
            + "echo \"repo=$repo\"; echo \"now=$(cat /etc/b1air/edition 2>/dev/null)\"; "
            + "for d in \"$repo\"/packages/editions/*/; do [ -f \"$d/parent\" ] || continue; "
            + "printf 'ed=%s|%s|%s\\n' \"$(basename \"$d\")\" \"$(head -n1 \"$d/description\" 2>/dev/null)\" \"$(head -n1 \"$d/parent\")\"; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                const eds = [{ name: "minimal", desc: "The desktop and its apps, nothing more", parent: "" }];
                for (const line of this.text.split("\n")) {
                    if (line.indexOf("repo=") === 0) section.editionRepo = line.slice(5);
                    else if (line.indexOf("now=") === 0) section.editionNow = line.slice(4) || "default";
                    else if (line.indexOf("ed=") === 0) {
                        const f = line.slice(3).split("|");
                        eds.push({ name: f[0], desc: f[1] || "", parent: f[2] || "minimal" });
                    }
                }
                // Each after the one it adds to.
                const depth = n => { let d = 0, e = eds.find(x => x.name === n); while (e && e.parent) { d++; e = eds.find(x => x.name === e.parent); } return d; };
                eds.sort((a, b) => depth(a.name) - depth(b.name));
                section.editions = eds;
            }
        }
    }

    // Is `a` part of `b` (b adds to a, directly or not)?
    function editionWithin(a, b) {
        let e = section.editions.find(x => x.name === b);
        while (e) {
            if (e.name === a) return true;
            e = section.editions.find(x => x.name === e.parent);
        }
        return false;
    }

    SettingsGroup {
        visible: section.part === "updates" && section.editionRepo !== ""
        title: I18n.tr("Edition")
        subtitle: I18n.tr("Each one is the one before it plus what it adds")
        icon: "\u{f03d3}"

        Repeater {
            model: section.editions

            SettingsRow {
                id: edRow
                required property var modelData
                readonly property bool current: edRow.modelData.name === section.editionNow
                readonly property bool smaller: !edRow.current && section.editionWithin(edRow.modelData.name, section.editionNow)
                label: edRow.modelData.name.charAt(0).toUpperCase() + edRow.modelData.name.slice(1)
                note: I18n.tr(edRow.modelData.desc)
                    + (edRow.smaller ? " · " + I18n.tr("What the current one installed stays installed") : "")

                Label {
                    visible: edRow.current
                    text: I18n.tr("Installed")
                    role: "caption"
                    dim: true
                }
                Button {
                    visible: !edRow.current
                    label: I18n.tr("Switch")
                    confirmText: I18n.tr("Switch to %1?", edRow.label)
                    onActivated: Quickshell.execDetached(["b1air-term", "--hold", "-e", "bash",
                        section.editionRepo + "/update-dotfiles.sh", "--packages-only",
                        "--edition", edRow.modelData.name, "--repo-dir", section.editionRepo])
                }
            }
        }
    }

    // ── 3. Disk Sweeper & Cache Maintenance (M4) ─────────────────────────────
    SettingsGroup {
        visible: section.part === ""
        title: I18n.tr("Disk Sweeper & Storage Maintenance")
        icon: "\u{f014}"

        SettingsRow {
            label: I18n.tr("Clean All Caches & Logs")
            note: I18n.tr("Free up storage by clearing the package cache, systemd journals, and thumbnail cache")
            Button {
                icon: "\u{f014}"
                label: I18n.tr("Delete")
                destructive: true
                confirmText: I18n.tr("Delete them?")
                onActivated: Daemon.sweeperClean()
            }
        }

        SettingsRow {
            label: I18n.tr("Remove Orphan Packages")
            Button {
                icon: "\u{f128}"
                label: I18n.tr("Remove")
                destructive: true
                confirmText: I18n.tr("Uninstall them?")
                onActivated: section.cleanOrphanPackages()
            }
        }
    }

    // ── 4. System Restore Points & Snapshots (M4) ─────────────────────────────
    // Which snapshot tool exists, so the button is not offered where it can
    // only fail ("timeshift" first: the daemon tries it first too).
    readonly property string snapshotTool: Sys.commandExists("timeshift") ? "timeshift"
                                         : Sys.commandExists("snapper") ? "snapper" : ""

    SettingsGroup {
        visible: section.part === ""
        title: I18n.tr("Restore Points")
        icon: "\u{f0c7}"

        SettingsRow {
            label: I18n.tr("Create Restore Point")
            note: section.snapshotTool !== ""
                  ? I18n.tr("Snapshot the system with %1 before a big update", section.snapshotTool)
                  : I18n.tr("Snapshots need timeshift, or snapper on a Btrfs root — neither is installed")
            Button {
                icon: "\u{f0c7}"
                label: I18n.tr("Create")
                enabled: section.snapshotTool !== ""
                onActivated: Cmd.run(["b1air-daemon", "snapshot", "create", "Manual user snapshot"], "Create snapshot")
            }
        }
    }

    // ── 5. Encrypted Vaults Manager (M4) ──────────────────────────────────────
    // One row, so no title over it saying the same.
    SettingsGroup {
        visible: section.part === ""

        SettingsRow {
            icon: "\u{f023}"
            label: I18n.tr("Encrypted Security Vaults")
            note: "~/.vaults"
            Button {
                icon: "\u{f07c}"
                label: I18n.tr("Open")
                onActivated: {
                    Sys.makeDir("~/.vaults");
                    Quickshell.execDetached(["xdg-open", Quickshell.env("HOME") + "/.vaults"]);
                }
            }
        }
    }

    // The desktop itself: reload it, or put every setting back. These were
    // on About, a page otherwise only about what this computer is.
    SettingsGroup {
        visible: section.part === ""
        title: I18n.tr("Desktop")
        icon: "\u{f0493}"

        SettingsRow {
            label: I18n.tr("Reload Sway & Quickshell")
            Button {
                icon: "\u{f0709}"
                label: I18n.tr("Reload")
                onActivated: { Sway.command("reload"); Quickshell.execDetached(["b1air-shell", "forceReload"]); }
            }
        }

        SettingsRow {
            label: I18n.tr("Reset Defaults")
            Button {
                icon: "\u{f0450}"
                label: I18n.tr("Reset")
                destructive: true
                onActivated: Settings.resetDefaults()
            }
        }
    }
}
