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
        if (window.checking) return "Checking for updates…";
        if (!window.repoFound) return "Dotfiles repository not found";
        if (window.behind > 0)
            return window.behind === 1 ? "1 new change" : window.behind + " new changes";
        return window.fetchOk ? "Up to date" : "Could not check";
    }
    readonly property string desktopDetail: {
        if (window.checking) return "Asking " + (window.remoteRef || "the remote") + " what is new";
        if (!window.repoFound) return "Run install.sh from your clone once, so the desktop knows where it is.";
        if (!window.fetchOk) return "The remote could not be reached (offline, or it needs a password). "
                                    + "This is what was known at the last successful check.";
        let s = "On " + window.branch + " at " + window.localHash;
        if (window.ahead > 0) s += " · " + window.ahead + " local commit" + (window.ahead === 1 ? "" : "s") + " not on " + window.remoteRef;
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
            default:       return "your package manager";
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
            Label { text: "Updates"; role: "subhead"; weight: Design.weight.bold }
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
                label: window.behind > 0 ? "Desktop · " + window.behind : "Desktop"
                icon: "󰚰"
                active: window.currentTab === "dotfiles"
                onClicked: window.currentTab = "dotfiles"
            }
            Pill {
                label: (window.sysCount + window.aurCount) > 0
                       ? "System · " + (window.sysCount + window.aurCount) : "System"
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
                title: window.fetchOk ? "Nothing new" : "Offline"
                hint: window.fetchOk ? "You have the latest desktop." : "Try again when the network is back."
            }
            Item { Layout.fillHeight: true; visible: window.checking }

            // Why the button is off, when it is.
            Label {
                Layout.fillWidth: true
                visible: !window.checking && window.behind > 0 && !window.canUpdate
                text: window.dirty
                      ? "You have uncommitted edits in " + window.repoDir + ". Commit or stash them first — the update would refuse to overwrite them."
                      : "This checkout has commits that " + window.remoteRef + " does not, so it cannot simply move forward. Merge or rebase it yourself."
                role: "caption"
                color: Design.warn
                wrapMode: Text.WordWrap
            }

            ActionButton {
                Layout.fillWidth: true
                icon: "\u{f06b0}"
                label: window.canUpdate ? "Update now" : "Up to date"
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
                text: window.sysChecking ? "Checking packages…"
                      : (window.sysCount + window.aurCount) === 0 ? "All packages up to date"
                      : (window.sysCount + window.aurCount) + " package updates"
                role: "title"
                weight: Design.weight.semibold
                color: (window.sysCount + window.aurCount) > 0 ? Design.ok : Design.text
            }
            Label {
                Layout.fillWidth: true
                text: window.aurCount > 0
                      ? window.sysCount + " from the repositories, " + window.aurCount + " from the AUR"
                      : "Managed by " + window.managerName
                role: "caption"
                dim: true
            }

            Item { Layout.fillHeight: true }

            Label {
                Layout.fillWidth: true
                text: "The upgrade runs in a terminal, so you can see what changes and enter your password."
                role: "caption"
                dim: true
                wrapMode: Text.WordWrap
            }

            ActionButton {
                Layout.fillWidth: true
                icon: "\u{f04e6}"
                label: "Upgrade with " + window.managerName
                tone: Design.accent
                onActivated: {
                    Daemon.dotfilesSys();
                    window.close();
                }
            }
        }
    }
}
