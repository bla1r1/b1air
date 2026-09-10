import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import B1air.Daemon
import "../../Ui"
import "../../Services"

// =============================================================================
// About & System Diagnostics Section
//
// System specs, kernel, compositor, quickshell version, service diagnostics,
// and dotfiles health overview. Replaces the legacy GuidePopup.
// =============================================================================

ColumnLayout {
    id: section

    // "Shortcuts Sheet" used to do `Settings.set("activeSection", "keyboard")`
    // — a key that is not in the schema, so set() warned and returned and the
    // button did nothing at all. Navigation is not a stored setting; it is a
    // request to the page host.
    signal navigate(string page)
    spacing: Design.s(Design.space.lg)

    property string kernelVer: "Linux"
    property string osName: "Arch Linux"
    property string hostName: "hostname"
    property string memInfo: "Loading..."
    property string uptimeStr: ""
    property string swayVer: "Sway"
    property string suiteVersion: "…"

    // The version comes over D-Bus, and when that call fails — the daemon not
    // on the session bus, which is exactly what happens if it was started
    // outside the user session — nothing replaced the placeholder, so this row
    // read "v…" for good: indistinguishable from still loading. The CLI knows
    // the same answer and does not need the bus, so it answers when the call
    // does not.
    Connections {
        target: Daemon
        function onVersionReady(tag, version) {
            if (version && String(version).trim() !== "")
                section.suiteVersion = String(version).trim();
        }
        function onFailed(op, message) {
            if (op === "GetVersion")
                versionFallback.running = true;
        }
    }

    Process {
        id: versionFallback
        command: ["b1air-daemon", "version"]
        stdout: StdioCollector {
            onStreamFinished: {
                // "b1air-daemon v0.3.1" -> "0.3.1"
                const m = /v?([0-9][0-9A-Za-z.\-]*)\s*$/.exec((this.text || "").trim());
                section.suiteVersion = m ? m[1] : "unknown";
            }
        }
    }

    // Nothing sensible to prefix an unknown with.
    readonly property string suiteVersionText:
        section.suiteVersion === "…" ? "…"
        : (section.suiteVersion === "unknown" ? "unknown" : "v" + section.suiteVersion)

    Component.onCompleted: Daemon.requestVersion()

    Process {
        running: true
        // awk's separator comes from -v OFS, not from quotes inside the
        // program. It used to be `print $3 \" / \" $2`, and by the time that
        // string had been through QML escaping and the shell, awk received
        // literal backslashes and refused the program outright:
        //
        //   awk: cmd. line:1: backslash not last character on line
        //
        // So line four of the output was empty and "Memory Usage" on this page
        // had no value at all. Nothing reported the failure; awk's complaint
        // went to a stderr nobody reads.
        command: ["bash", "-c", "printf '%s\\n' \"$(uname -r)\" \"$(grep '^PRETTY_NAME=' /etc/os-release 2>/dev/null | cut -d= -f2 | tr -d '\"')\" \"$(uname -n)\" \"$(free -h 2>/dev/null | awk -v OFS=' / ' '/^Mem:/ {print $3, $2}')\" \"$(sway --version 2>/dev/null | head -1)\""]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const lines = this.text.trim().split("\n");
                    if (lines.length >= 1) section.kernelVer = lines[0];
                    if (lines.length >= 2) section.osName = lines[1];
                    if (lines.length >= 3) section.hostName = lines[2];
                    if (lines.length >= 4) section.memInfo = lines[3];
                    if (lines.length >= 5) section.swayVer = lines[4];
                } catch (e) {}
            }
        }
    }

    // ── 1. Header ────────────────────────────────────────────────────────────
    SectionLabel {
        text: "About & Diagnostics"
    }

    // ── 2. System Specifications Card ────────────────────────────────────────
    Card {
        title: "System Specifications"
        subtitle: section.osName + " on " + section.hostName
        icon: "\u{f035b}"
        accentColor: Design.sapphire

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.sm)

            RowLayout {
                Layout.fillWidth: true
                Label { text: "Operating System"; role: "caption"; dim: true; Layout.preferredWidth: Design.s(160) }
                Label { text: section.osName; weight: Design.weight.semibold; Layout.fillWidth: true }
            }

            RowLayout {
                Layout.fillWidth: true
                Label { text: "Linux Kernel"; role: "caption"; dim: true; Layout.preferredWidth: Design.s(160) }
                Label { text: section.kernelVer; isMono: true; Layout.fillWidth: true }
            }

            RowLayout {
                Layout.fillWidth: true
                Label { text: "Wayland Compositor"; role: "caption"; dim: true; Layout.preferredWidth: Design.s(160) }
                Label { text: section.swayVer; Layout.fillWidth: true }
            }

            RowLayout {
                Layout.fillWidth: true
                Label { text: "Shell Environment"; role: "caption"; dim: true; Layout.preferredWidth: Design.s(160) }
                Label { text: "Quickshell (Wayland Native)"; weight: Design.weight.semibold; color: Design.accent; Layout.fillWidth: true }
            }

            RowLayout {
                Layout.fillWidth: true
                Label { text: "b1air Suite Version"; role: "caption"; dim: true; Layout.preferredWidth: Design.s(160) }
                Label { text: section.suiteVersionText; isMono: true; weight: Design.weight.semibold; Layout.fillWidth: true }
            }

            RowLayout {
                Layout.fillWidth: true
                Label { text: "Memory Usage"; role: "caption"; dim: true; Layout.preferredWidth: Design.s(160) }
                Label { text: section.memInfo; isMono: true; Layout.fillWidth: true }
            }

            RowLayout {
                Layout.fillWidth: true
                Label { text: "System Uptime"; role: "caption"; dim: true; Layout.preferredWidth: Design.s(160) }
                Label {
                    text: (Power.upHours > 0 ? Power.upHours + " hours, " : "") + Power.upMins + " minutes"
                    Layout.fillWidth: true
                }
            }
        }
    }

    // ── 3. Component Health & Diagnostics ────────────────────────────────────
    Card {
        title: "Service Health & Subsystems"
        subtitle: "Live status of background communication daemons"
        icon: "\u{f02ce}"
        accentColor: Design.teal

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.sm)

            // PipeWire
            RowLayout {
                Layout.fillWidth: true
                spacing: Design.s(Design.space.md)
                Rectangle {
                    width: Design.s(10); height: width; radius: width/2
                    color: Audio.defaultSink !== null ? Design.green : Design.danger
                }
                Label { text: "PipeWire Audio Server"; weight: Design.weight.semibold; Layout.fillWidth: true }
                Badge {
                    text: Audio.defaultSink !== null ? "Connected" : "Inactive"
                    tone: Audio.defaultSink !== null ? Design.green : Design.danger
                }
            }

            // NetworkManager
            RowLayout {
                Layout.fillWidth: true
                spacing: Design.s(Design.space.md)
                Rectangle {
                    width: Design.s(10); height: width; radius: width/2
                    color: Design.green
                }
                Label { text: "NetworkManager & Connectivity"; weight: Design.weight.semibold; Layout.fillWidth: true }
                Badge {
                    text: Network.hasWifi || Network.hasBluetooth ? "Active" : "Ready"
                    tone: Design.green
                }
            }

            // UPower
            RowLayout {
                Layout.fillWidth: true
                spacing: Design.s(Design.space.md)
                Rectangle {
                    width: Design.s(10); height: width; radius: width/2
                    color: Power.hasBattery ? Design.green : Design.sapphire
                }
                Label { text: "UPower Power Management"; weight: Design.weight.semibold; Layout.fillWidth: true }
                Badge {
                    text: Power.hasBattery ? "Battery Active" : "AC Connected"
                    tone: Power.hasBattery ? Design.green : Design.sapphire
                }
            }

            // Notification Server
            RowLayout {
                Layout.fillWidth: true
                spacing: Design.s(Design.space.md)
                Rectangle {
                    width: Design.s(10); height: width; radius: width/2
                    color: Design.green
                }
                Label { text: "Freedesktop Notification Daemon"; weight: Design.weight.semibold; Layout.fillWidth: true }
                Badge {
                    text: Notifications.dnd ? "DND Active" : "Running (Native)"
                    tone: Notifications.dnd ? Design.peach : Design.green
                }
            }
        }
    }

    // ── 4. Dotfiles Maintenance ──────────────────────────────────────────────
    Card {
        title: "Dotfiles Maintenance & Actions"
        subtitle: "Quick actions to manage your configuration and check for updates"
        icon: "\u{f0493}"
        accentColor: Design.mauve

        RowLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.sm)

            ActionButton {
                icon: "\u{f030c}"
                label: "Shortcuts Sheet"
                onActivated: section.navigate("shortcuts")
            }

            ActionButton {
                icon: "\u{f0446}"
                label: "Reload Sway & Quickshell"
                onActivated: Quickshell.execDetached(["bash", "-c", "swaymsg reload; b1air-shell forceReload"])
            }

            ActionButton {
                icon: "\u{f0450}"
                label: "Reset Defaults"
                destructive: true
                onActivated: Settings.resetDefaults()
            }
        }
    }
}
