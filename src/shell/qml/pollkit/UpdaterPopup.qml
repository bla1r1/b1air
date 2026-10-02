import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../Ui"
import B1air.Daemon

// =============================================================================
// Updates — the desktop itself (this repository) and the system's packages.
//
// What it says is what the check found, in words: "Checking…", "Up to date",
// "3 new changes" with the changes listed, or why it could not tell. It used to
// open on "ENVIRONMENT UP TO DATE" before anything had been checked, show the
// newest commit's subject typed out letter by letter as if it were the whole
// update, centre a branch@hash string wider than the window (clipped at both
// ends), and ask for a 1.2 s press-and-hold on a button that then did not pull.
// =============================================================================
PopupShell {
    id: window

    property string currentTab: "dotfiles" // "dotfiles" | "system"

    // ── Desktop (dotfiles) state ─────────────────────────────────────────────
    property bool checking: true
    property bool repoFound: true
    property bool fetchOk: true
    property bool dirty: false
    property int behind: 0
    property int ahead: 0
    property string branch: ""
    property string localHash: ""
    property string remoteRef: ""
    property string repoDir: ""
    property var incoming: []

    // ── System packages state ────────────────────────────────────────────────
    property bool sysChecking: true
    property int sysCount: 0
    property int aurCount: 0
    property string manager: ""

    function checkNow() {
        window.checking = true;
        Daemon.requestDotfilesStatus();
        window.sysChecking = true;
        sysCheck.running = true;
    }

    Connections {
        target: Daemon
        function onDotfilesStatusReady(tag, json) {
            window.checking = false;
            let data;
            try { data = JSON.parse(json); } catch (e) { data = { ok: false }; }
            window.repoFound = !!data.ok;
            if (!data.ok) return;
            window.fetchOk = data.fetch_ok !== false;
            window.dirty = !!data.dirty;
            window.behind = data.behind || 0;
            window.ahead = data.ahead || 0;
            window.branch = data.branch || "";
            window.localHash = data.local_hash || "";
            window.remoteRef = data.remote_ref || "";
            window.repoDir = data.repo_dir || "";
            window.incoming = data.incoming || [];
        }
    }

    Process {
        id: sysCheck
        command: ["b1air-daemon", "updates"]
        stdout: StdioCollector {
            onStreamFinished: {
                window.sysChecking = false;
                try {
                    const d = JSON.parse(this.text.trim());
                    window.sysCount = d.system || 0;
                    window.aurCount = d.aur || 0;
                    window.manager = d.manager || "";
                } catch (e) {
                    window.sysCount = 0;
                    window.aurCount = 0;
                }
            }
        }
    }

    Component.onCompleted: window.checkNow()

    // ── Wording ──────────────────────────────────────────────────────────────
    readonly property string desktopTitle: {
        if (window.checking) return I18n.tr("Checking for updates…");
        if (!window.repoFound) return I18n.tr("Dotfiles repository not found");
        if (window.behind > 0)
            return I18n.trn("%1 new change", "%1 new changes", window.behind);
        return window.fetchOk ? I18n.tr("Up to date") : I18n.tr("Could not check");
    }
    readonly property string desktopDetail: {
        if (window.checking) return I18n.tr("Asking %1 what is new", window.remoteRef || I18n.tr("the remote"));
        if (!window.repoFound) return I18n.tr("Run install.sh from your clone once, so the desktop knows where it is.");
        if (!window.fetchOk) return I18n.tr("The remote could not be reached (offline, or it needs a password). This is what was known at the last successful check.");
        let s = I18n.tr("On %1 at %2", window.branch, window.localHash);
        if (window.ahead > 0) s += " · " + I18n.trn("%1 local commit not on %2", "%1 local commits not on %2", window.ahead, window.remoteRef);
        return s;
    }
    readonly property bool canUpdate: !window.checking && window.repoFound && window.behind > 0
                                      && !window.dirty && window.ahead === 0

    readonly property string managerName: {
        switch (window.manager) {
            case "pacman": return "pacman" + (window.aurCount > 0 ? " + AUR" : "");
            case "apt":    return "APT";
            case "dnf":    return "DNF";
            case "zypper": return "zypper";
            default:       return I18n.tr("your package manager");
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Design.s(Design.space.md)

        // ── Header ────────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.sm)

            Icon { text: "\u{f06b0}"; role: "subhead"; color: Design.accent }
            Label { text: I18n.tr("Updates"); role: "subhead"; weight: Design.weight.bold }
            Item { Layout.fillWidth: true }
            IconButton {
                icon: "\u{f0450}" // refresh
                enabled: !window.checking
                onClicked: window.checkNow()
            }
        }

        // ── Tabs ─────────────────────────────────────────────────────────────
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Design.s(Design.space.sm)

            Pill {
                label: window.behind > 0 ? I18n.tr("Desktop · %1", window.behind) : I18n.tr("Desktop")
                icon: "󰚰"
                active: window.currentTab === "dotfiles"
                onClicked: window.currentTab = "dotfiles"
            }
            Pill {
                label: (window.sysCount + window.aurCount) > 0
                       ? I18n.tr("System") + " · " + (window.sysCount + window.aurCount) : I18n.tr("System")
                icon: "󰏗"
                active: window.currentTab === "system"
                onClicked: window.currentTab = "system"
            }
        }

        // ── Desktop ──────────────────────────────────────────────────────────
        ColumnLayout {
            visible: window.currentTab === "dotfiles"
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Design.s(Design.space.sm)

            Label {
                Layout.fillWidth: true
                text: window.desktopTitle
                role: "title"
                weight: Design.weight.semibold
                color: window.behind > 0 ? Design.ok : Design.text
                elide: Text.ElideRight
            }
            Label {
                Layout.fillWidth: true
                text: window.desktopDetail
                role: "caption"
                dim: true
                wrapMode: Text.WordWrap
            }

            // What the update brings, newest first.
            ScrollArea {
                id: changes
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: window.incoming.length > 0

                Column {
                    width: changes.availableWidth
                    spacing: Design.s(Design.space.xs)

                    Repeater {
                        model: window.incoming
                        delegate: RowLayout {
                            required property var modelData
                            width: parent.width
                            spacing: Design.s(Design.space.sm)
                            Label {
                                text: modelData.hash
                                role: "caption"
                                isMono: true
                                dim: true
                                Layout.alignment: Qt.AlignTop
                            }
                            Label {
                                Layout.fillWidth: true
                                text: modelData.subject
                                role: "caption"
                                wrapMode: Text.WordWrap
                            }
                        }
                    }
                }
            }

            EmptyState {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: !window.checking && window.incoming.length === 0
                icon: window.fetchOk ? "\u{f012c}" : "\u{f0b9b}"
                title: window.fetchOk ? I18n.tr("Nothing new") : I18n.tr("Offline")
                hint: window.fetchOk ? I18n.tr("You have the latest desktop.") : I18n.tr("Try again when the network is back.")
            }
            Item { Layout.fillHeight: true; visible: window.checking }

            // Why the button is off, when it is.
            Label {
                Layout.fillWidth: true
                visible: !window.checking && window.behind > 0 && !window.canUpdate
                text: window.dirty
                      ? I18n.tr("You have uncommitted edits in %1. Commit or stash them first — the update would refuse to overwrite them.", window.repoDir)
                      : I18n.tr("This checkout has commits that %1 does not, so it cannot simply move forward. Merge or rebase it yourself.", window.remoteRef)
                role: "caption"
                color: Design.warn
                wrapMode: Text.WordWrap
            }

            ActionButton {
                Layout.fillWidth: true
                icon: "\u{f06b0}"
                label: window.canUpdate ? I18n.tr("Update now") : I18n.tr("Up to date")
                tone: window.canUpdate ? Design.ok : Design.textDim
                enabled: window.canUpdate
                onActivated: {
                    // Opens a terminal that shows each step and asks for sudo
                    // where the rebuild needs it.
                    Daemon.dotfilesSync();
                    window.close();
                }
            }
        }

        // ── System packages ──────────────────────────────────────────────────
        ColumnLayout {
            visible: window.currentTab === "system"
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Design.s(Design.space.sm)

            Label {
                Layout.fillWidth: true
                text: window.sysChecking ? I18n.tr("Checking packages…")
                      : (window.sysCount + window.aurCount) === 0 ? I18n.tr("All packages up to date")
                      : I18n.trn("%1 package update", "%1 package updates", window.sysCount + window.aurCount)
                role: "title"
                weight: Design.weight.semibold
                color: (window.sysCount + window.aurCount) > 0 ? Design.ok : Design.text
            }
            Label {
                Layout.fillWidth: true
                text: window.aurCount > 0
                      ? I18n.tr("%1 from the repositories, %2 from the AUR", window.sysCount, window.aurCount)
                      : I18n.tr("Managed by %1", window.managerName)
                role: "caption"
                dim: true
            }

            Item { Layout.fillHeight: true }

            Label {
                Layout.fillWidth: true
                text: I18n.tr("The upgrade runs in a terminal, so you can see what changes and enter your password.")
                role: "caption"
                dim: true
                wrapMode: Text.WordWrap
            }

            ActionButton {
                Layout.fillWidth: true
                icon: "\u{f04e6}"
                label: I18n.tr("Upgrade with %1", window.managerName)
                tone: Design.accent
                onActivated: {
                    Daemon.dotfilesSys();
                    window.close();
                }
            }
        }
    }
}
