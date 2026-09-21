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
// and wireless tablet secondary display (Sidecar).
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
    Card {
        title: "Remote Desktop (WayVNC)"
        subtitle: section.vncRunning
            ? "Server active on port " + section.vncPort + " — local session only"
            : (section.devMode ? "Development mode: available to the local network" : "Stopped — starts on localhost in production mode")
        icon: "\u{f0379}"
        accentColor: Design.blue

        // Ui/Toggle rather than a hand-built row around a bare Ui/Switch, for
        // the same reason as Appearance: the shared row is what ten other
        // settings pages use, and rolling it by hand produced a smaller switch
        // pinned to the label instead of one at the end of the row.
        Toggle {
            label: "Remote Desktop Server"
            subtitle: section.vncRunning
                ? "Active (Listening on " + (section.devMode ? section.localIp : "127.0.0.1") + ":" + section.vncPort + ")"
                : "Lets a VNC client see and control this desktop"
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

        Item { height: Design.s(Design.space.xs) }

        RowLayout {
            Layout.fillWidth: true
            Label { text: "VNC password"; role: "caption"; dim: true }
            Field {
                Layout.fillWidth: true
                text: section.vncPassword
                echoMode: TextInput.Password
                placeholder: "Required for TLS authentication"
                // On every edit, not only on commit: the switch above is a
                // mouse area and does not take focus, so a password typed and
                // followed straight by a click on it was never committed and
                // the server started with an empty one.
                onEdited: v => section.vncPassword = v
                onCommitted: v => section.vncPassword = v
            }
        }

        // Quick Connect Badge & Copy
        RowLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.sm)
            visible: section.vncRunning

            Pill {
                label: "vnc://" + section.localIp + ":" + section.vncPort
                active: true
            }

            Label {
                visible: section.vncUser !== ""
                text: "sign in as " + section.vncUser
                role: "caption"
                dim: true
            }

            ActionButton {
                label: "Copy Address"
                icon: "\u{f00c5}"
                onActivated: {
                    Quickshell.execDetached(["wl-copy", "vnc://" + section.localIp + ":" + section.vncPort]);
                }
            }
        }
    }

    // ── 2. Unattended Screen Sharing & Permissions ───────────────────────────
    Card {
        title: "Unattended Remote Access & Permissions"
        subtitle: "Eliminate repetitive security dialogs for RustDesk, AnyDesk, and OBS"
        icon: "\u{f016d}"
        accentColor: Design.teal

        // Prompt-Free Screencast Toggle
        Toggle {
            label: "Silent Screencast Sharing"
            subtitle: section.devMode
                ? "Allow trusted remote tools to capture screen without interactive popup confirmation"
                : "Available only in explicit development mode"
            checked: section.promptFree && section.devMode
            enabled: section.devMode
            onToggled: {
                section.promptFree = !section.promptFree;
                Daemon.remotePromptFree(section.promptFree);
            }
        }

        Item { height: Design.s(Design.space.xs) }

        // Kernel Input Emulation (/dev/uinput) Status
        RowLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.md)

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Label { text: "Kernel Input Emulation (/dev/uinput)"; weight: Design.weight.semibold }
                Label {
                    text: section.uinputReady
                        ? "Active: Mouse and keyboard can be controlled unattended on lockscreen and root apps"
                        : "Requires input group permissions (/dev/uinput)"
                    role: "caption"
                    dim: true
                }
            }

            Badge {
                text: section.uinputReady ? "Ready" : "Inactive"
                color: section.uinputReady ? Design.green : Design.red
            }
        }

        // A "RustDesk Background Service — Start Service" button stood here.
        // It ran `sudo systemctl enable --now rustdesk` detached, with no
        // terminal for sudo to ask in, so sudo failed; then a user unit that
        // RustDesk does not ship; then `|| true`. It could not succeed, and
        // RustDesk is not something this desktop installs.
    }

    // ── 3. Wireless Tablet Sidecar Display ────────────────────────────────────
    Card {
        title: "Wireless Tablet Sidecar Display"
        subtitle: "Create a virtual second monitor to stream to an iPad or tablet via VNC"
        icon: "\u{f004b}"
        accentColor: Design.mauve

        RowLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.md)

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Label { text: "Virtual Headless Display"; weight: Design.weight.semibold }
                Label {
                    text: "Creates an extra 1920x1080 workspace that can be viewed on another device"
                    role: "caption"
                    dim: true
                }
            }

            ButtonRow {
                spacing: Design.s(Design.space.sm)

                ActionButton {
                    label: "Create Display"
                    icon: "\u{f0079}"
                    onActivated: {
                        Daemon.sidecarCreate(1920, 1080);
                    }
                }

                ActionButton {
                    label: "Remove"
                    icon: "\u{f00d}"
                    onActivated: {
                        Daemon.sidecarRemove();
                    }
                }
            }
        }
    }

    Timer {
        id: statusTimer
        interval: 1500
        repeat: false
        onTriggered: refreshStatus()
    }
}
