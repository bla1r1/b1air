import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../Ui"
import "../../Services"

// =============================================================================
// Power Settings — Energy profiles, battery stats, and sleep timeouts.
// =============================================================================

ColumnLayout {
    id: section

    Layout.fillWidth: true

    /**
     * Change an idle setting and make it take effect now.
     *
     * The session's idle thread (src/daemon/idle.cpp) notices the settings
     * file changing on its own; the nudge after the write lands is for the
     * moment the file watch is not there yet. It was swayidle, whose command
     * line was built once at login, so a change here waited for the next.
     */
    function setIdleTimeout(key, value) {
        Settings.set(key, value);
        idleReload.restart();
    }

    Timer {
        id: idleReload
        interval: 300
        onTriggered: Quickshell.execDetached(["b1air-daemon", "power", "idle-reload"])
    }
    spacing: Design.s(Design.space.lg)

    // Services/Power is refcounted — only ControlCenter ever acquired it, so
    // opening this page started no poller and "Balanced" stayed lit no matter
    // which profile was actually active.
    Component.onCompleted: Power.acquire()
    Component.onDestruction: Power.release()

    // ── 1. Energy Profiles Card ──────────────────────────────────────────────
    Card {
        title: I18n.tr("Energy & performance")
        subtitle: I18n.tr("Tune system performance and power consumption")
        icon: "\u{f0084}"
        accentColor: Design.green

        // The mini view in the Control Center has always had this empty state;
        // the full page drew three live-looking tiles that silently did nothing
        // when power-profiles-daemon was not running.
        EmptyState {
            visible: !Power.hasProfiles
            Layout.fillWidth: true
            icon: "\u{f0241}"
            title: I18n.tr("No energy modes")
            hint: I18n.tr("power-profiles-daemon is not running, so there is nothing to switch between.")
        }

        RowLayout {
            visible: Power.hasProfiles
            Layout.fillWidth: true
            spacing: Design.s(Design.space.sm)

            Repeater {
                model: [
                    { id: "performance", label: I18n.tr("Performance"), icon: "\u{f0e4}" },
                    { id: "balanced",    label: I18n.tr("Balanced"),    icon: "\u{f0241}" },
                    { id: "power-saver", label: I18n.tr("Power Saver"), icon: "\u{f0084}" }
                ]

                Pill {
                    required property var modelData
                    Layout.fillWidth: true
                    icon: modelData.icon
                    label: modelData.label
                    active: Power.profile === modelData.id
                    onClicked: Power.setProfile(modelData.id)
                }
            }
        }
    }

    // ── 2. Display brightness ────────────────────────────────────────────────
    // The page advertises "brightness" in its own search tags and had no
    // brightness control on it — the only slider lived in the Control Center
    // mini view, so searching for it landed you on a page without it.
    Card {
        visible: Power.hasBacklight
        title: I18n.tr("Display brightness")
        subtitle: I18n.tr("Backlight level of the built-in panel")
        icon: "\u{f00df}"
        accentColor: Design.yellow

        Slider {
            Layout.fillWidth: true
            Layout.preferredHeight: Design.s(Design.size.ctl)
            value: Power.brightness
            tone: Design.yellow
            icon: "\u{f00df}"
            label: I18n.tr("Brightness")
            onMoved: pct => Power.setBrightness(pct)
        }
    }

    // ── 3. Battery ───────────────────────────────────────────────────────────
    Card {
        visible: Power.hasBattery
        title: I18n.tr("Battery")
        subtitle: Power.charging ? I18n.tr("Currently charging") : I18n.tr("Running on battery power")
        icon: Power.charging ? "\u{f0084}" : "\u{f0079}"
        accentColor: Power.charging ? Design.ok : Design.accent

        RowLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.md)

            Rectangle {
                width: Design.s(44)
                height: width
                radius: width / 2
                color: Design.tint(Power.charging ? Design.ok : (Power.capacity <= 20 ? Design.danger : Design.accent), 0.15)

                Icon {
                    anchors.centerIn: parent
                    text: Power.charging ? "\u{f0084}" : (Power.capacity > 80 ? "\u{f0079}" : (Power.capacity > 30 ? "\u{f007c}" : "\u{f0083}"))
                    role: "subhead"
                    color: Power.charging ? Design.ok : (Power.capacity <= 20 ? Design.danger : Design.accent)
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                Label {
                    text: Power.capacity + "%"
                    role: "subhead"
                    weight: Design.weight.bold
                }

                // The mini view showed the time estimate and the full settings
                // page did not, so the popup was strictly more informative than
                // the page it links to.
                Label {
                    text: I18n.tr(Power.status) + (Power.timeRemainingText !== ""
                        ? " • " + (Power.charging ? I18n.tr("until full %1", Power.timeRemainingText) : I18n.tr("%1 left", Power.timeRemainingText))
                        : "")
                    role: "caption"
                    dim: true
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }
            }
        }

        // ── Per-pack breakdown ───────────────────────────────────────────────
        // Everything above is UPower's composite device. On a two-battery
        // machine that single number hides which pack is doing the work and
        // which one has aged: BAT0 can sit at 99% and fully-charged while BAT1
        // is still charging at 73%, with BAT0 down to 65% of design capacity.
        SectionLabel {
            visible: Power.hasMultipleBatteries
            text: I18n.tr("Installed packs")
            Layout.topMargin: Design.s(Design.space.sm)
        }

        Repeater {
            model: Power.hasMultipleBatteries ? Power.batteries : []

            DeviceRow {
                required property var modelData

                Layout.fillWidth: true
                title: Power.labelOf(modelData) + (modelData.model ? " · " + modelData.model : "")
                subtitle: I18n.tr(Power.stateTextOf(modelData))
                    + (Power.healthOf(modelData) > 0
                        ? " • " + I18n.tr("health %1%", Power.healthOf(modelData))
                        : "")
                value: Power.percentOf(modelData) + "%"
                valueTone: Power.percentOf(modelData) <= 20 ? Design.danger
                    : (Power.healthOf(modelData) > 0 && Power.healthOf(modelData) < 70 ? Design.warn : Design.ok)
            }
        }

        // A single pack still has health worth showing; it just does not need a
        // list to show it in.
        DeviceRow {
            visible: !Power.hasMultipleBatteries && Power.batteryCount === 1
                     && Power.healthOf(Power.batteries[0]) > 0
            Layout.fillWidth: true
            Layout.topMargin: Design.s(Design.space.sm)
            title: I18n.tr("Battery health")
            subtitle: I18n.tr("Capacity now, against what the pack shipped with")
            value: Power.batteryCount === 1 ? Power.healthOf(Power.batteries[0]) + "%" : ""
            valueTone: Power.batteryCount === 1 && Power.healthOf(Power.batteries[0]) < 70 ? Design.warn : Design.ok
        }
    }

    // ── 3.2 Charge control ───────────────────────────────────────────────────
    // A laptop that lives on mains sits at 100% and ages for it. The kernel has
    // had a charge limit and a charge behaviour for this hardware all along —
    // two sysfs files per pack — and nothing in this desktop exposed either, so
    // the only way to use them was to echo into /sys as root.
    Card {
        visible: Power.hasChargeLimit || Power.hasChargeBehaviour
        title: I18n.tr("Charge control")
        subtitle: I18n.tr("Keep the battery off a full charge, so it ages more slowly")
        icon: "\u{f0084}"
        accentColor: Design.teal

        Toggle {
            visible: Power.hasChargeLimit
            label: I18n.tr("Limit the charge")
            subtitle: I18n.tr("Stop charging below full. 100% means no limit.")
            checked: Power.chargeLimit < 100
            onToggled: Power.setChargeLimit(Power.chargeLimit < 100 ? 100 : 80)
        }

        Stepper {
            visible: Power.hasChargeLimit && Power.chargeLimit < 100
            label: I18n.tr("Stop charging at")
            valueText: Power.chargeLimit + "%"
            // Not below 50: the pack would spend its life nearly empty, which
            // trades one kind of wear for another.
            onDecrement: Power.setChargeLimit(Math.max(50, Power.chargeLimit - 5))
            onIncrement: Power.setChargeLimit(Math.min(100, Power.chargeLimit + 5))
        }

        SectionLabel {
            visible: Power.hasChargeBehaviour
            text: I18n.tr("While plugged in")
            Layout.topMargin: Design.s(Design.space.sm)
        }

        RowLayout {
            visible: Power.hasChargeBehaviour
            Layout.fillWidth: true
            spacing: Design.s(Design.space.xs)

            Repeater {
                model: [
                    { id: "auto",            label: I18n.tr("Charge") },
                    { id: "inhibit-charge",  label: I18n.tr("Hold") },
                    { id: "force-discharge", label: I18n.tr("Discharge") }
                ]

                Pill {
                    required property var modelData
                    // Only what this hardware actually offers: the file lists
                    // its own options, and a button for one the kernel would
                    // refuse is a control that does nothing.
                    visible: Power.chargeBehaviourOptions.indexOf(modelData.id) >= 0
                    label: modelData.label
                    active: Power.chargeBehaviour === modelData.id
                    onClicked: Power.setChargeBehaviour(modelData.id)
                }
            }
        }

        Label {
            visible: (Power.hasChargeLimit || Power.hasChargeBehaviour) && !Power.chargeWritable
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            role: "caption"
            dim: true
            text: I18n.tr("These files belong to root on this machine, so a change will ask for a password. Re-running the installer puts you in the `power` group and installs the udev rule that makes it direct.")
        }
    }

    // ── 3.5 Low battery ──────────────────────────────────────────────────────
    Card {
        visible: Power.hasBattery
        title: I18n.tr("Low battery")
        subtitle: I18n.tr("What happens as the charge runs out")
        icon: "\u{f0084}"
        accentColor: Design.warn

        Toggle {
            label: I18n.tr("Warn me when the battery is low")
            subtitle: I18n.tr("A notification at the level below. Nothing warned about the charge before — the machine simply went off.")
            checked: Settings.batteryLowWarning !== false
            onToggled: Settings.set("batteryLowWarning", !(Settings.batteryLowWarning !== false))
        }

        Stepper {
            visible: Settings.batteryLowWarning !== false
            label: I18n.tr("Warn at")
            valueText: Power.lowThreshold + "%"
            onDecrement: Settings.set("batteryLowPercent",
                                      Math.max(Power.criticalThreshold + 5, Power.lowThreshold - 5))
            onIncrement: Settings.set("batteryLowPercent", Math.min(50, Power.lowThreshold + 5))
        }

        Toggle {
            label: I18n.tr("Suspend before the battery dies")
            subtitle: I18n.tr("A suspend with a few percent left keeps the session; a flat battery does not.")
            checked: Settings.batteryCriticalAction !== "none"
            onToggled: Settings.set("batteryCriticalAction",
                                    Settings.batteryCriticalAction === "none" ? "suspend" : "none")
        }

        Stepper {
            visible: Settings.batteryCriticalAction !== "none"
            label: I18n.tr("Suspend at")
            valueText: Power.criticalThreshold + "%"
            onDecrement: Settings.set("batteryCriticalPercent", Math.max(2, Power.criticalThreshold - 1))
            onIncrement: Settings.set("batteryCriticalPercent",
                                      Math.min(Power.lowThreshold - 5, Power.criticalThreshold + 1))
        }
    }

    // ── 4. When idle ─────────────────────────────────────────────────────────
    //
    // Each step on its own, "Never" included, for plugged in and on battery
    // apart — the way KDE's Energy Saving and Windows' power plan set it: the
    // screen can go off without the machine locking, or lock without the
    // screen going off, or neither. The session's idle thread
    // (src/daemon/idle.cpp) follows the profile for the power source now.

    // Which profile the page is showing.
    property string profile: Power.hasBattery && !Power.charging ? "battery" : "ac"
    readonly property bool onBatteryProfile: section.profile === "battery"
    function keyOf(base) { return section.onBatteryProfile ? base + "Battery" : base; }

    // The steps Windows offers, in seconds; 0 is never.
    readonly property var timeoutSteps: [0, 60, 120, 180, 300, 600, 900, 1200, 1500, 1800, 2700, 3600, 7200, 10800, 18000]

    function timeoutText(seconds) {
        if (seconds <= 0) return I18n.tr("Never");
        if (seconds < 3600) return I18n.tr("%1 min", Math.round(seconds / 60));
        return I18n.tr("%1 h", Math.round(seconds / 360) / 10);
    }

    function stepFrom(seconds, dir) {
        const steps = section.timeoutSteps;
        let i = 0;
        while (i < steps.length - 1 && steps[i] < seconds) i++;
        if (dir > 0) return steps[Math.min(steps.length - 1, steps[i] > seconds ? i : i + 1)];
        return steps[Math.max(0, steps[i] >= seconds ? i - 1 : i)];
    }

    // The sleep timeout of the plugged-in profile has a switch of its own
    // (autoSuspend) from before; "Never" here is that switch off.
    function sleepSeconds() {
        if (section.onBatteryProfile) return Settings.suspendTimeoutBattery;
        return Settings.autoSuspend ? Settings.suspendTimeout : 0;
    }

    function setTimeout(base, seconds) {
        if (base === "suspendTimeout" && !section.onBatteryProfile) {
            Settings.apply(seconds > 0 ? { autoSuspend: true, suspendTimeout: seconds } : { autoSuspend: false });
        } else {
            Settings.set(section.keyOf(base), seconds);
        }
        idleReload.restart();
    }

    Card {
        title: I18n.tr("When idle")
        subtitle: section.onBatteryProfile ? I18n.tr("On battery") : I18n.tr("Plugged in")
        icon: "\u{f033e}"
        accentColor: Design.peach

        Flow {
            visible: Power.hasBattery
            Layout.fillWidth: true
            spacing: Design.s(Design.space.xs)
            Pill {
                icon: "\u{f06a5}"
                label: I18n.tr("Plugged in")
                active: !section.onBatteryProfile
                onClicked: section.profile = "ac"
            }
            Pill {
                icon: "\u{f0079}"
                label: I18n.tr("On battery")
                active: section.onBatteryProfile
                onClicked: section.profile = "battery"
            }
        }

        Repeater {
            model: [
                { base: "dimTimeout",     label: I18n.tr("Dim the screen after") },
                { base: "dpmsTimeout",    label: I18n.tr("Turn off the screen after") },
                { base: "lockTimeout",    label: I18n.tr("Lock after") },
                { base: "suspendTimeout", label: I18n.tr("Sleep after") }
            ]
            Stepper {
                required property var modelData
                readonly property int seconds: modelData.base === "suspendTimeout"
                    ? section.sleepSeconds() : (Settings[section.keyOf(modelData.base)] || 0)
                label: modelData.label
                valueText: section.timeoutText(seconds)
                onDecrement: section.setTimeout(modelData.base, section.stepFrom(seconds, -1))
                onIncrement: section.setTimeout(modelData.base, section.stepFrom(seconds, 1))
            }
        }

        Toggle {
            label: I18n.tr("Lock when the screen turns off")
            subtitle: I18n.tr("Off: the screen can go dark without locking, and lock only on its own timer")
            checked: Settings.lockWithScreenOff
            onToggled: Settings.set("lockWithScreenOff", !Settings.lockWithScreenOff)
        }

        Toggle {
            label: I18n.tr("Lock before sleep")
            subtitle: I18n.tr("Waking up shows the lock screen, not the desktop")
            checked: Settings.lockOnSleep
            onToggled: Settings.set("lockOnSleep", !Settings.lockOnSleep)
        }

        Toggle {
            label: I18n.tr("Dim screen on lock")
            subtitle: I18n.tr("Lower display brightness immediately when screen is locked")
            checked: Settings.dimOnLock
            onToggled: Settings.set("dimOnLock", !Settings.dimOnLock)
        }

        Toggle {
            label: I18n.tr("Other screens off when idle")
            subtitle: I18n.tr("When the main screen dims, the others go dark; any input brings them back")
            checked: Settings.idleSecondaryOff
            onToggled: Settings.set("idleSecondaryOff", !Settings.idleSecondaryOff)
        }

        Toggle {
            label: I18n.tr("Only the main screen while locked")
            subtitle: I18n.tr("The lock screen shows on the main screen; the others stay off until it is opened")
            checked: Settings.lockSecondaryOff
            onToggled: Settings.set("lockSecondaryOff", !Settings.lockSecondaryOff)
        }
    }

    // ── 5. Lid and power button ──────────────────────────────────────────────
    //
    // logind's HandleLidSwitch and HandlePowerKey are a system file, the same
    // for every account and editable only as root. The session takes both
    // over (a logind inhibitor, while sway's bindings send them to the
    // daemon) and does what is chosen here.
    readonly property var lidChoices: [
        { id: "sleep",      label: I18n.tr("Sleep") },
        { id: "lock",       label: I18n.tr("Lock") },
        { id: "screen-off", label: I18n.tr("Turn off the screen") },
        { id: "shutdown",   label: I18n.tr("Shut down") },
        { id: "nothing",    label: I18n.tr("Do nothing") }
    ]

    Card {
        title: Power.hasBattery ? I18n.tr("Lid and power button") : I18n.tr("Power button")
        subtitle: I18n.tr("What they do, instead of the system default")
        icon: "\u{f0425}"
        accentColor: Design.accent

        Label {
            visible: Power.hasBattery
            text: section.onBatteryProfile ? I18n.tr("Closing the lid, on battery") : I18n.tr("Closing the lid, plugged in")
            role: "caption"
            dim: true
        }
        Flow {
            visible: Power.hasBattery
            Layout.fillWidth: true
            spacing: Design.s(Design.space.xs)
            Repeater {
                model: section.lidChoices
                Pill {
                    required property var modelData
                    readonly property string current: Settings[section.keyOf("lidAction")] || "sleep"
                    label: modelData.label
                    active: current === modelData.id
                    onClicked: Settings.set(section.keyOf("lidAction"), modelData.id)
                }
            }
        }

        Toggle {
            visible: Power.hasBattery
            label: I18n.tr("With another screen connected, only turn off the built-in one")
            subtitle: I18n.tr("Closing the lid while docked keeps working on the other screen")
            checked: Settings.lidIgnoreDocked
            onToggled: Settings.set("lidIgnoreDocked", !Settings.lidIgnoreDocked)
        }

        Label {
            text: I18n.tr("Pressing the power button")
            role: "caption"
            dim: true
        }
        Flow {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.xs)
            Repeater {
                model: [{ id: "ask", label: I18n.tr("Ask what to do") }].concat(section.lidChoices)
                Pill {
                    required property var modelData
                    label: modelData.label
                    active: (Settings.powerKeyAction || "ask") === modelData.id
                    onClicked: Settings.set("powerKeyAction", modelData.id)
                }
            }
        }
    }
}
