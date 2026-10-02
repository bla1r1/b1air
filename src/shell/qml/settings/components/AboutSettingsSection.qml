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

    property string kernelVer: "…"
    property string osName: "…"
    property string hostName: "…"
    property string memInfo: "…"
    property string uptimeStr: ""
    property string swayVer: "…"
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

    Component.onCompleted: {
        Daemon.requestVersion();
        section.readSystem();
        if (Sway.versionText) section.swayVer = Sway.versionText;
    }

    // Read from the kernel's own files, not from a bash pipeline of uname,
    // grep, cut, tr, free and awk — whose quoting broke the memory line once
    // already, silently.
    function readSystem() {
        section.kernelVer = Sys.readFile("/proc/sys/kernel/osrelease").trim();
        section.hostName = Sys.readFile("/proc/sys/kernel/hostname").trim();
        const os = Sys.readFile("/etc/os-release").match(/^PRETTY_NAME="?([^"\n]*)"?$/m);
        section.osName = os ? os[1] : "Linux";
        // Used is what free(1) counts: total less available.
        const kb = key => {
            const m = Sys.readFile("/proc/meminfo").match(new RegExp("^" + key + ":\\s+(\\d+)", "m"));
            return m ? Number(m[1]) : 0;
        };
        const gib = k => (k / 1048576).toFixed(1) + "Gi";
        const total = kb("MemTotal");
        section.memInfo = total ? gib(total - kb("MemAvailable")) + " / " + gib(total) : "";
    }
    readonly property string swayVerLive: Sway.versionText
    onSwayVerLiveChanged: if (swayVerLive) section.swayVer = swayVerLive

    // (The page title is in the Settings header bar now.)

    // ── 2. System Specifications Card ────────────────────────────────────────
    Card {
        title: I18n.tr("System Specifications")
        subtitle: I18n.tr("%1 on %2", section.osName, section.hostName)
        icon: "\u{f035b}"
        accentColor: Design.sapphire

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.sm)

            RowLayout {
                Layout.fillWidth: true
                Label { text: I18n.tr("Operating System"); role: "caption"; dim: true; Layout.preferredWidth: Design.s(160) }
                Label { text: section.osName; weight: Design.weight.semibold; Layout.fillWidth: true }
            }

            RowLayout {
                Layout.fillWidth: true
                Label { text: I18n.tr("Linux Kernel"); role: "caption"; dim: true; Layout.preferredWidth: Design.s(160) }
                Label { text: section.kernelVer; isMono: true; Layout.fillWidth: true }
            }

            RowLayout {
                Layout.fillWidth: true
                Label { text: I18n.tr("Wayland Compositor"); role: "caption"; dim: true; Layout.preferredWidth: Design.s(160) }
                Label { text: section.swayVer; Layout.fillWidth: true }
            }

            RowLayout {
                Layout.fillWidth: true
                Label { text: I18n.tr("Shell Environment"); role: "caption"; dim: true; Layout.preferredWidth: Design.s(160) }
                Label { text: I18n.tr("Quickshell (Wayland Native)"); weight: Design.weight.semibold; color: Design.accent; Layout.fillWidth: true }
            }

            RowLayout {
                Layout.fillWidth: true
                Label { text: I18n.tr("b1air Suite Version"); role: "caption"; dim: true; Layout.preferredWidth: Design.s(160) }
                Label { text: section.suiteVersionText; isMono: true; weight: Design.weight.semibold; Layout.fillWidth: true }
            }

            RowLayout {
                Layout.fillWidth: true
                Label { text: I18n.tr("Memory Usage"); role: "caption"; dim: true; Layout.preferredWidth: Design.s(160) }
                Label { text: section.memInfo; isMono: true; Layout.fillWidth: true }
            }

            RowLayout {
                Layout.fillWidth: true
                Label { text: I18n.tr("System Uptime"); role: "caption"; dim: true; Layout.preferredWidth: Design.s(160) }
                Label {
                    text: (Power.upHours > 0 ? I18n.trn("%1 hour", "%1 hours", Power.upHours) + ", " : "") + I18n.trn("%1 minute", "%1 minutes", Power.upMins)
                    Layout.fillWidth: true
                }
            }
        }
    }

    // ── 3. Component Health & Diagnostics ────────────────────────────────────
    Card {
        title: I18n.tr("Service Health & Subsystems")
        subtitle: I18n.tr("Live status of background communication daemons")
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
                Label { text: I18n.tr("PipeWire Audio Server"); weight: Design.weight.semibold; Layout.fillWidth: true }
                Badge {
                    text: Audio.defaultSink !== null ? I18n.tr("Connected") : I18n.tr("Inactive")
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
                Label { text: I18n.tr("NetworkManager & Connectivity"); weight: Design.weight.semibold; Layout.fillWidth: true }
                Badge {
                    text: Network.hasWifi || Network.hasBluetooth ? I18n.tr("Active") : I18n.tr("Ready")
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
                Label { text: I18n.tr("UPower Power Management"); weight: Design.weight.semibold; Layout.fillWidth: true }
                Badge {
                    text: Power.hasBattery ? I18n.tr("Battery Active") : I18n.tr("AC Connected")
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
                Label { text: I18n.tr("Freedesktop Notification Daemon"); weight: Design.weight.semibold; Layout.fillWidth: true }
                Badge {
                    text: Notifications.dnd ? I18n.tr("DND Active") : I18n.tr("Running (Native)")
                    tone: Notifications.dnd ? Design.peach : Design.green
                }
            }
        }
    }

    // ── 4. Dotfiles Maintenance ──────────────────────────────────────────────
    Card {
        title: I18n.tr("Dotfiles Maintenance & Actions")
        subtitle: I18n.tr("Quick actions to manage your configuration and check for updates")
        icon: "\u{f0493}"
        accentColor: Design.mauve

        ButtonRow {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.sm)

            ActionButton {
                icon: "\u{f030c}"
                label: I18n.tr("Shortcuts Sheet")
                onActivated: section.navigate("shortcuts")
            }

            ActionButton {
                icon: "\u{f0446}"
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
