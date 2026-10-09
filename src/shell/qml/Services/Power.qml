pragma Singleton

import QtQuick
import "../Ui"
import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower
import Qt.labs.folderlistmodel
import B1air.Daemon

// =============================================================================
// Owner of battery, power profile, uptime and laptop backlight.
//
// Lifted out of BatteryPopup's inline sysPoller so the Control Center pages can
// share one reading instead of each starting their own. Same combined bash
// call as before — one process per tick, not one per value.
//
// Refcounted like Services/Audio: a singleton polling unconditionally would run
// for the whole session, where the popup's poller only lived while it was open.
//
//   Component.onCompleted: Power.acquire()
//   Component.onDestruction: Power.release()
// =============================================================================

Singleton {
    id: root

    // ── Battery ──────────────────────────────────────────────────────────────
    // From UPower rather than catting /sys/class/power_supply/BAT*/ in a bash
    // poller. UPower is already a daemon watching this hardware; asking it costs
    // a D-Bus property read, and it pushes changes instead of being asked.
    readonly property var _bat: UPower.displayDevice

    // FolderListModel instead of `bash -c "ls -d /sys/class/power_supply/BAT*"`.
    // Resolving a glob is exactly what this type does, and doing it here costs
    // no fork, no shell and no dependency on ls being on PATH — the previous
    // form spawned a shell at startup purely to answer "is there a battery".
    property bool hasBatterySys: false

    FolderListModel {
        id: batteryNodes
        folder: "file:///sys/class/power_supply"
        showFiles: true
        showDirs: true
        showDotAndDotDot: false

        // The names are matched here rather than with nameFilters: the sysfs
        // entries are directories, and FolderListModel applies nameFilters to
        // files only — measured, "BAT*" returned all five nodes including AC
        // and the two USB-C supplies. Left as a filter this would have called
        // every desktop with a power supply a laptop.
        onCountChanged: {
            let found = false;
            for (let i = 0; i < count; ++i) {
                const n = String(get(i, "fileName"));
                if (n.startsWith("BAT") || n.startsWith("battery")) {
                    found = true;
                    break;
                }
            }
            root.hasBatterySys = found;
        }
    }

    // `_bat !== null` does not catch undefined, which is what
    // UPower.displayDevice is before the service is ready — so the right-hand
    // side evaluated to undefined and the whole binding did, giving
    // "Unable to assign [undefined] to bool" in the shell log on every start.
    // Coerced explicitly so the property is always a real boolean.
    readonly property bool hasBattery: root.hasBatterySys
        || (!!root._bat && root._bat.isPresent === true && root._bat.isRechargeable === true)

    // Every physical pack, not just the composite. UPower.displayDevice merges
    // them into one synthetic device, which is the right thing for the top-bar
    // pill but hides the whole story on a machine with two: this ThinkPad's
    // BAT0 sits at 99% fully-charged while BAT1 is still taking charge at 73%,
    // and BAT0 has aged down to 65% of its design capacity. The composite
    // reports one number and no health at all (displayDevice.healthPercentage
    // is 0), so anything per-pack has to come from here.
    readonly property var batteries: {
        const out = [];
        if (!UPower.devices)
            return out;
        for (const d of UPower.devices.values) {
            if (d && d.isLaptopBattery && d.isPresent)
                out.push(d);
        }
        return out;
    }

    readonly property int batteryCount: root.batteries.length

    // Only worth showing a per-pack breakdown when there is more than one pack.
    readonly property bool hasMultipleBatteries: root.batteryCount > 1

    // 0..100, or 0 when UPower has no design-capacity data for the pack.
    function healthOf(dev) { return dev && dev.healthPercentage > 0 ? Math.round(dev.healthPercentage) : 0; }
    function percentOf(dev) { return dev ? Math.round(dev.percentage * 100) : 0; }

    function stateTextOf(dev) {
        if (!dev) return "Unknown";
        switch (dev.state) {
        case UPowerDeviceState.Charging:     return "Charging";
        case UPowerDeviceState.FullyCharged: return "Full";
        case UPowerDeviceState.Discharging:  return "Discharging";
        case UPowerDeviceState.Empty:        return "Empty";
        default:                             return "Idle";
        }
    }

    // "BAT0" reads better than the full sysfs path and matches what every other
    // tool on the machine calls it.
    function labelOf(dev) {
        if (!dev) return "";
        const np = dev.nativePath || "";
        return np !== "" ? np : (dev.model || "Battery");
    }

    // Scale settled by reading it off a running Quickshell 0.3.1 rather than
    // guessing: UPowerDevice.percentage is normalised to 0..1 (0.99 for a
    // battery upower(1) reports as 99%), unlike UPower's own D-Bus Percentage
    // which is 0..100. healthPercentage is NOT normalised — it stays 0..100.
    readonly property int capacity: root._bat ? Math.round(root._bat.percentage * 100) : 0
    readonly property bool charging: root._bat
        ? (root._bat.state === UPowerDeviceState.Charging
           || root._bat.state === UPowerDeviceState.FullyCharged)
        : false
    // On the charger, charging or not. A pack held below a charge limit, or
    // the second of two waiting for the first, reports pending-charge while
    // the cable is in, which `charging` does not count.
    readonly property bool pluggedIn: root.charging || UPower.onBattery === false
    // ── Low battery ──────────────────────────────────────────────────────────
    //
    // Nothing in this desktop looked at the charge. Not a threshold, not
    // UPower's own WarningLevel, no notification and no emergency suspend —
    // the battery simply ran to zero and the machine went off mid-sentence.
    // The only thing that ever acted on power was the idle timer, and it counts
    // idleness, not charge.
    //
    // Two thresholds, both configurable on the Power page. The warning is a
    // notification; the critical one suspends, because a suspend with a few
    // percent left keeps the session and a flat battery does not.
    readonly property int lowThreshold: {
        const n = Number(Settings.batteryLowPercent);
        return (isFinite(n) && n > 0) ? Math.round(n) : 15;
    }
    readonly property int criticalThreshold: {
        const n = Number(Settings.batteryCriticalPercent);
        return (isFinite(n) && n > 0) ? Math.round(n) : 5;
    }

    // Latched so a battery hovering on the threshold does not notify on every
    // UPower update. Cleared once the charge recovers past the threshold, or
    // as soon as the cable goes in. Nothing is said while it is in.
    property bool _warnedLow: false
    property bool _warnedCritical: false

    onCapacityChanged: root._checkCharge()
    onPluggedInChanged: root._checkCharge()

    function _checkCharge() {
        if (!root.hasBattery)
            return;

        if (root.pluggedIn) {
            root._warnedLow = false;
            root._warnedCritical = false;
            return;
        }

        // A percentage of 0 is what UPower reports before it has read the
        // hardware, and treating that as an empty battery would suspend the
        // machine seconds after login.
        if (root.capacity <= 0)
            return;

        if (root.capacity > root.lowThreshold)
            root._warnedLow = false;
        if (root.capacity > root.criticalThreshold)
            root._warnedCritical = false;

        if (Settings.batteryCriticalAction !== "none"
                && root.capacity <= root.criticalThreshold && !root._warnedCritical) {
            root._warnedCritical = true;
            root._warnedLow = true;
            Sys.notify("Power", I18n.tr("Battery critical — %1%", root.capacity),
                       I18n.tr("Suspending now to save the session."), "battery-caution", "critical");
            // A moment for the notification to be drawn and for anything
            // mid-write to finish before the machine goes down.
            criticalDelay.start();
            return;
        }

        if (Settings.batteryLowWarning !== false
                && root.capacity <= root.lowThreshold && !root._warnedLow) {
            root._warnedLow = true;
            Sys.notify("Power", I18n.tr("Battery low — %1%", root.capacity),
                       I18n.tr("Plug in, or the machine will suspend at %1%.", root.criticalThreshold),
                       "battery-low", "critical");
        }
    }

    Timer {
        id: criticalDelay
        interval: 5000
        onTriggered: {
            // Checked again: five seconds is long enough for someone to plug
            // in after reading the notification, and suspending anyway would
            // be the wrong answer to that.
            if (!root.pluggedIn)
                Quickshell.execDetached(["b1air-daemon", "power", "suspend"]);
        }
    }

    readonly property string status: {
        if (!root._bat) return "Unknown";
        switch (root._bat.state) {
        case UPowerDeviceState.Charging:      return "Charging";
        case UPowerDeviceState.FullyCharged:  return "Full";
        case UPowerDeviceState.Discharging:   return "Discharging";
        case UPowerDeviceState.Empty:         return "Empty";
        default:                              return "Unknown";
        }
    }

    // Real battery estimate from UPower, not system uptime — the Control
    // Center used to pair "Discharging"/"Charging" with the uptime clock
    // (from /proc/uptime, meant for the power-profile row), which reads
    // exactly like a time-to-empty/full estimate but has nothing to do with
    // the battery and just climbs for as long as the machine has been on.
    readonly property string timeRemainingText: {
        if (!root._bat) return "";
        const secs = root.charging ? root._bat.timeToFull : root._bat.timeToEmpty;
        if (!secs || secs <= 0) return "";
        const h = Math.floor(secs / 3600);
        const m = Math.floor((secs % 3600) / 60);
        return h + "h " + m + "m";
    }

    // ── Profile ──────────────────────────────────────────────────────────────
    property string profile: "balanced"
    // Whether power-profiles-daemon answers, asked of the daemon, which talks
    // to it over D-Bus. This looked for the powerprofilesctl program instead,
    // which nothing here runs any more: with the service up and that Python
    // script not installed, every page said there were no energy modes.
    property bool hasProfiles: false
    Process {
        id: profilesProbe
        running: true
        command: ["b1air-daemon", "power-profile", "available"]
        onExited: code => root.hasProfiles = code === 0
    }

    // ── Charge control ───────────────────────────────────────────────────────
    // The charge limit and charging behaviour, as KDE's power applet has them.
    // Read through the daemon rather than from sysfs directly: the values live
    // in one file per pack, this machine has two, and charge_behaviour reads as
    // a menu ("[auto] inhibit-charge force-discharge") rather than a value.
    property bool hasChargeLimit: false
    property bool hasChargeBehaviour: false
    property int chargeLimit: 100
    property string chargeBehaviour: "auto"
    property var chargeBehaviourOptions: []
    // False when the udev rule is not in place, so the page can say why a
    // change would ask for a password instead of letting it fail quietly.
    property bool chargeWritable: false

    Process {
        id: chargeReader
        command: ["b1air-daemon", "battery", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                let d = {};
                try { d = JSON.parse(this.text); } catch (e) { return; }
                root.hasChargeLimit = d.hasLimit === true;
                root.hasChargeBehaviour = d.hasBehaviour === true;
                const packs = d.batteries || [];
                if (packs.length === 0) return;
                // Every pack is set together, so the first one that reports a
                // value describes the machine.
                for (const p of packs) {
                    if (p.limit !== undefined) {
                        root.chargeLimit = p.limit;
                        root.chargeWritable = p.limitWritable === true;
                        break;
                    }
                }
                for (const p of packs) {
                    if (p.behaviour !== undefined && p.behaviour !== "") {
                        root.chargeBehaviour = p.behaviour;
                        root.chargeBehaviourOptions = p.behaviourOptions || [];
                        break;
                    }
                }
            }
        }
    }

    function refreshCharge() { chargeReader.running = true; }

    function setChargeLimit(pct) {
        root.chargeLimit = pct;                    // optimistic; the read confirms
        Settings.set("chargeLimit", pct);
        Quickshell.execDetached(["b1air-daemon", "battery", "limit", String(pct)]);
        chargeConfirm.restart();
    }

    function setChargeBehaviour(name) {
        root.chargeBehaviour = name;
        Settings.set("chargeBehaviour", name);
        Quickshell.execDetached(["b1air-daemon", "battery", "behaviour", name]);
        chargeConfirm.restart();
    }

    // sysfs does not settle under the write instantly, and a read fired in the
    // same tick reports the old value and snaps the control back.
    Timer {
        id: chargeConfirm
        interval: 600
        onTriggered: root.refreshCharge()
    }

    // ── Uptime ───────────────────────────────────────────────────────────────
    property int upHours: 0
    property int upMins: 0

    // ── Backlight ────────────────────────────────────────────────────────────
    // The laptop panel. External monitors are a different device on a different
    // protocol (DDC) and stay with MonitorPopup.
    //
    // Split on purpose: READ from sysfs, WRITE through the daemon.
    //
    // Reading natively takes brightness out of the 1.5s poll loop entirely —
    // sysfs emits inotify on change, so FileView sees a keypress immediately
    // instead of up to a second and a half later.
    //
    // Writing goes to the daemon (daemon/backlight.cpp): through logind, so no
    // root is needed, with the keys stepping along a perceptual curve and a
    // floor that keeps the panel from going fully dark.
    property int brightness: 0
    property int brightnessRaw: 0
    property int brightnessMax: 0

    // What is left in the poller is the power profile and uptime. Battery moved
    // to UPower, brightness to inotify — neither is asked for any more. 40
    // process spawns a minute became 4.
    property int pollInterval: 15000

    // ── Consumers ────────────────────────────────────────────────────────────

    property int _users: 0
    function acquire() {
        root._users++;
        if (root._users === 1) root.refreshCharge();
    }
    function release() { if (root._users > 0) root._users--; }

    // ── Writes ───────────────────────────────────────────────────────────────

    function setProfile(name) {
        root.profile = name;                       // optimistic, poller confirms
        Daemon.powerProfileSet(name);
    }

    function setBrightness(pct) {
        // Linear (the daemon's BrightnessSet): the slider reads back a plain
        // raw/max off sysfs, and through the perceptual curve dragging to
        // what looks like 80% landed the hardware near 40%.
        root.brightness = pct;   // optimistic; the FileView confirms
        Daemon.brightnessSet(pct);
    }

    // Through the daemon's perceptual curve, as the brightness keys step.
    function stepBrightness(delta) {
        if (delta >= 0)
            Daemon.brightnessUp(delta);
        else
            Daemon.brightnessDown(-delta);
    }

    function refresh() { poller.running = true; }

    // ── Drag protection ──────────────────────────────────────────────────────
    // Held while a brightness slider is under the pointer, so the 1.5s poller
    // cannot yank it back mid-drag.
    property bool brightnessHeld: false

    // ── Polling ──────────────────────────────────────────────────────────────

    // The profile from the daemon; the uptime straight from /proc.
    Process {
        id: poller
        command: ["b1air-daemon", "power-profile", "get"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.profile = this.text.trim() || "balanced";
                const seconds = parseFloat(Sys.readFile("/proc/uptime")) || 0;
                root.upHours = Math.floor(seconds / 3600);
                root.upMins = Math.floor((seconds % 3600) / 60);
            }
        }
    }

    Timer {
        interval: root.pollInterval
        repeat: true
        triggeredOnStart: true
        running: root._users > 0
        onTriggered: poller.running = true
    }

    // ── Backlight, event-driven ──────────────────────────────────────────────
    // One process for the whole session to find the device, then nothing.
    // The glob has to be resolved once because FileView needs a concrete path.

    property string _backlightDir: ""
    readonly property bool hasBacklight: root._backlightDir !== "" && root.brightnessMax > 0

    // Same again: the backlight device is whatever directory is in
    // /sys/class/backlight, which is a listing, not a job for a shell.
    FolderListModel {
        id: backlightNodes
        folder: "file:///sys/class/backlight"
        showFiles: true
        showDirs: true
        showDotAndDotDot: false
        onCountChanged: {
            if (count > 0)
                root._backlightDir = "/sys/class/backlight/" + String(get(0, "fileName"));
        }
    }

    FileView {
        path: root._backlightDir === "" ? "" : root._backlightDir + "/max_brightness"
        printErrors: false
        onLoaded: root.brightnessMax = parseInt(text()) || 0
    }

    FileView {
        path: root._backlightDir === "" ? "" : root._backlightDir + "/brightness"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            // A write to this sysfs file can fire more than one inotify
            // event, and a reload triggered mid-write sometimes reads back
            // empty. parseInt("") is NaN, and `|| 0` turned that into a
            // literal 0 — which then instantly overwrote the displayed
            // brightness with 0% for a frame before the next good read
            // landed. An unparseable read means "try again next event", not
            // "brightness is now zero" — keep the last known value instead.
            const parsed = parseInt(text());
            if (isNaN(parsed)) return;
            root.brightnessRaw = parsed;
            if (!root.brightnessHeld && root.brightnessMax > 0)
                root.brightness = Math.round(root.brightnessRaw * 100 / root.brightnessMax);
        }
    }
}
