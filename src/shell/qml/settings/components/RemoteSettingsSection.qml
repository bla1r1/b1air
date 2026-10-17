import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../../Ui"
import "../../Services"
import B1air.Daemon

// =============================================================================
// Remote Desktop & Screen Sharing Settings Section
//
// Full control over native WayVNC remote server, unattended screencasting
// permissions (RustDesk / AnyDesk / OBS), /dev/uinput kernel input emulation,
// (the tablet as a second screen is on Displays).
// =============================================================================

ColumnLayout {
    id: section

    Layout.fillWidth: true
    spacing: Design.s(Design.space.lg)

    property bool vncRunning: false
    property string localIp: "127.0.0.1"
    property int vncPort: 5900
    property bool promptFree: false
    property bool uinputReady: false
    readonly property bool devMode: Quickshell.env("B1AIR_DEV_MODE") === "1"
    property string vncPassword: ""
    // The login a VNC client asks for beside the password: this account's.
    property string vncUser: ""

    Process {
        id: vncStarter
        stdinEnabled: true
        command: ["b1air-daemon", "remote", "start-stdin", String(section.vncPort)]
        onStarted: {
            write(section.vncPassword + "\n");
            stdinEnabled = false;
        }
    }

    // Daemon.requestRemoteStatus's second argument was never a real Quickshell
    // API — execDetached takes no JS callback, so this silently never ran and
    // vncRunning/localIp never updated after the first paint.
    function refreshStatus() {
        Daemon.requestRemoteStatus();
    }

    Connections {
        target: Daemon
        function onRemoteStatusReady(tag, json) {
            try {
                if (json && json.trim().startsWith("{")) {
                    let parsed = JSON.parse(json.trim());
                    section.vncRunning = parsed.running || false;
                    section.localIp = parsed.ip || "127.0.0.1";
                    section.vncUser = parsed.username || "";
                    section.promptFree = section.devMode && parsed.promptFreeScreencast === true;
                    section.uinputReady = parsed.uinputReady !== undefined ? parsed.uinputReady : true;
                }
            } catch (e) {}
        }
    }

    Component.onCompleted: {
        refreshStatus();
    }

    // ── 1. WayVNC Native Remote Desktop ──────────────────────────────────────
    SettingsGroup {
        title: I18n.tr("Remote Desktop (WayVNC)")
        subtitle: section.vncRunning
            ? I18n.tr("Server active on port %1 — local session only", section.vncPort)
            : (section.devMode ? I18n.tr("Development mode: available to the local network") : I18n.tr("Stopped — starts on localhost in production mode"))
        icon: "\u{f0379}"

        // Ui/Toggle rather than a hand-built row around a bare Ui/Switch, for
        // the same reason as Appearance: the shared row is what ten other
        // settings pages use, and rolling it by hand produced a smaller switch
        // pinned to the label instead of one at the end of the row.
        SwitchRow {
            label: I18n.tr("Remote Desktop Server")
            subtitle: section.vncRunning
                ? I18n.tr("Active (Listening on %1:%2)", (section.devMode ? section.localIp : "127.0.0.1"), section.vncPort)
                : I18n.tr("Lets a VNC client see and control this desktop")
            checked: section.vncRunning
            onToggled: {
                if (!section.vncRunning) {
                    // Never put a VNC password in argv: it is visible through
                    // process listings. Password-backed/TLS mode is enabled
                    // by the daemon's secret-store integration.
                    vncStarter.running = true;
                    section.vncRunning = true;
                } else {
                    Daemon.remoteStop();
                    section.vncRunning = false;
                }
                statusTimer.restart();
            }
        }

        SettingsRow {
            label: I18n.tr("VNC password")
            Field {
                Layout.preferredWidth: Design.s(Design.width.select)
                text: section.vncPassword
                echoMode: TextInput.Password
                placeholder: I18n.tr("Required for TLS authentication")
                // On every edit, not only on commit: the switch above is a
                // mouse area and does not take focus, so a password typed and
                // followed straight by a click on it was never committed and
                // the server started with an empty one.
                onEdited: v => section.vncPassword = v
                onCommitted: v => section.vncPassword = v
            }
        }

        // Where to connect: the address is the row, its command copies it.
        SettingsRow {
            visible: section.vncRunning
            label: "vnc://" + section.localIp + ":" + section.vncPort
            note: section.vncUser !== "" ? I18n.tr("sign in as %1", section.vncUser) : ""
            Button {
                label: I18n.tr("Copy Address")
                icon: "\u{f00c5}"
                onActivated: {
                    Quickshell.execDetached(["b1air-clip", "copy", "--", "vnc://" + section.localIp + ":" + section.vncPort]);
                }
            }
        }
    }

    // ── 2. Unattended Screen Sharing & Permissions ───────────────────────────
    SettingsGroup {
        title: I18n.tr("Unattended Remote Access & Permissions")
        subtitle: I18n.tr("Eliminate repetitive security dialogs for RustDesk, AnyDesk, and OBS")
        icon: "\u{f016d}"

        // Prompt-Free Screencast Toggle
        SwitchRow {
            label: I18n.tr("Silent Screencast Sharing")
            subtitle: section.devMode
                ? I18n.tr("Allow trusted remote tools to capture screen without interactive popup confirmation")
                : I18n.tr("Available only in explicit development mode")
            checked: section.promptFree && section.devMode
            enabled: section.devMode
            onToggled: {
                section.promptFree = !section.promptFree;
                Daemon.remotePromptFree(section.promptFree);
            }
        }

        // Kernel Input Emulation (/dev/uinput) status. Not ready is not a
        // fault — most people never need it — so no red badge for it.
        SettingsRow {
            label: I18n.tr("Kernel Input Emulation (/dev/uinput)")
            note: section.uinputReady
                ? I18n.tr("Active: Mouse and keyboard can be controlled unattended on lockscreen and root apps")
                : I18n.tr("Requires input group permissions (/dev/uinput)")
            Badge {
                text: section.uinputReady ? I18n.tr("Ready") : I18n.tr("Inactive")
                tone: section.uinputReady ? Design.ok : Design.textDim
            }
        }

        // A "RustDesk Background Service — Start Service" button stood here.
        // It ran `sudo systemctl enable --now rustdesk` detached, with no
        // terminal for sudo to ask in, so sudo failed; then a user unit that
        // RustDesk does not ship; then `|| true`. It could not succeed, and
        // RustDesk is not something this desktop installs.
    }


    Timer {
        id: statusTimer
        interval: 1500
        repeat: false
        onTriggered: refreshStatus()
    }
}
