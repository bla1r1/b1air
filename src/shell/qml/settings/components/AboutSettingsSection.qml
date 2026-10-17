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
    SettingsGroup {
        title: I18n.tr("System Specifications")
        subtitle: I18n.tr("%1 on %2", section.osName, section.hostName)
        icon: "\u{f035b}"

        // Name and value, as every other row: the value on the right in the
        // text colour (it is not a choice, so not the accent).
        SettingsRow {
            label: I18n.tr("Operating System")
            Label { text: section.osName; dim: true }
        }
        SettingsRow {
            label: I18n.tr("Linux Kernel")
            Label { text: section.kernelVer; dim: true; isMono: true }
        }
        SettingsRow {
            label: I18n.tr("Wayland Compositor")
            Label { text: section.swayVer; dim: true }
        }
        SettingsRow {
            label: I18n.tr("Shell Environment")
            Label { text: I18n.tr("Quickshell (Wayland Native)"); dim: true }
        }
        SettingsRow {
            label: I18n.tr("b1air Suite Version")
            Label { text: section.suiteVersionText; dim: true; isMono: true }
        }
        SettingsRow {
            label: I18n.tr("Memory Usage")
            Label { text: section.memInfo; dim: true; isMono: true }
        }
        SettingsRow {
            label: I18n.tr("System Uptime")
            Label { text: (Power.upHours > 0 ? I18n.trn("%1 hour", "%1 hours", Power.upHours) + ", " : "") + I18n.trn("%1 minute", "%1 minutes", Power.upMins); dim: true }
        }
    }

    // ── 3. Component Health & Diagnostics ────────────────────────────────────
    SettingsGroup {
        title: I18n.tr("Service Health & Subsystems")
        icon: "\u{f02ce}"

        // One row per service, its state a badge coloured by meaning: a dot
        // beside each said the same thing a second time.
        SettingsRow {
            label: I18n.tr("PipeWire Audio Server")
            Badge {
                text: Audio.defaultSink !== null ? I18n.tr("Connected") : I18n.tr("Inactive")
                tone: Audio.defaultSink !== null ? Design.ok : Design.danger
            }
        }
        SettingsRow {
            label: I18n.tr("NetworkManager & Connectivity")
            Badge {
                text: Network.hasWifi || Network.hasBluetooth ? I18n.tr("Active") : I18n.tr("Ready")
                tone: Design.ok
            }
        }
        SettingsRow {
            label: I18n.tr("UPower Power Management")
            Badge {
                text: Power.hasBattery ? I18n.tr("Battery Active") : I18n.tr("AC Connected")
                tone: Design.ok
            }
        }
        SettingsRow {
            label: I18n.tr("Freedesktop Notification Daemon")
            Badge {
                text: Notifications.dnd ? I18n.tr("DND Active") : I18n.tr("Running (Native)")
                tone: Notifications.dnd ? Design.warn : Design.ok
            }
        }
    }

}
