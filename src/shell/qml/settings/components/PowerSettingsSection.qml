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

    // "": the Power & Battery page. "lock": the locking card alone, for the
    // Lock & Login page — locking was four switches in the middle of "When
    // idle", on a page about energy.
    property string part: ""

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
        visible: section.part === ""
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

    // ── 3. Battery ───────────────────────────────────────────────────────────
    Card {
        visible: (section.part === "") && (Power.hasBattery)
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
        visible: (section.part === "") && (Power.hasChargeLimit || Power.hasChargeBehaviour)
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
        visible: (section.part === "") && (Power.hasBattery)
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

    // Plugged in and on battery side by side, one column each, the lid with
    // them. The page showed one of the two behind a switch, and the lid's
    // choice followed that switch from another card — so which of the two
    // you were changing depended on something two screens up.
    function keyOf(base, battery) { return battery ? base + "Battery" : base; }

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
    function seconds(base, battery) {
        if (base === "suspendTimeout" && !battery)
            return Settings.autoSuspend ? Settings.suspendTimeout : 0;
        return Settings[section.keyOf(base, battery)] || 0;
    }

    function setTimeout(base, battery, seconds) {
        if (base === "suspendTimeout" && !battery) {
            Settings.apply(seconds > 0 ? { autoSuspend: true, suspendTimeout: seconds } : { autoSuspend: false });
        } else {
            Settings.set(section.keyOf(base, battery), seconds);
        }
        idleReload.restart();
    }

    function lidIndex(battery) {
        const v = Settings[section.keyOf("lidAction", battery)] || "sleep";
        return Math.max(0, section.lidChoices.findIndex(c => c.id === v));
    }
    function stepLid(battery, dir) {
        const n = section.lidChoices.length;
        const i = (section.lidIndex(battery) + dir + n) % n;
        Settings.set(section.keyOf("lidAction", battery), section.lidChoices[i].id);
    }

    readonly property var idleRows: [
        { base: "dimTimeout",     label: I18n.tr("Dim the screen after") },
        { base: "dpmsTimeout",    label: I18n.tr("Turn off the screen after") },
        { base: "lockTimeout",    label: I18n.tr("Lock after") },
        { base: "suspendTimeout", label: I18n.tr("Sleep after") }
    ]

    Card {
        visible: section.part === ""
        title: I18n.tr("When idle")
        subtitle: Power.hasBattery
            ? I18n.tr("Plugged in and on battery each their own; the one in use is marked")
            : I18n.tr("What happens when the computer is left alone")
        icon: "\u{f033e}"
        accentColor: Design.peach

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.sm)

            // Header: which column is which, and which one applies now.
            RowLayout {
                Layout.fillWidth: true
                spacing: Design.s(Design.space.md)
                Item { Layout.fillWidth: true }
                Repeater {
                    model: Power.hasBattery ? [false, true] : [false]
                    RowLayout {
                        id: colHead
                        required property bool modelData
                        readonly property bool now: modelData === (Power.hasBattery && !Power.charging)
                        Layout.fillWidth: false
                        Layout.preferredWidth: Design.s(170)
                        spacing: Design.s(Design.space.xs)
                        Item { Layout.fillWidth: true }
                        Icon {
                            text: colHead.modelData ? "\u{f0079}" : "\u{f06a5}"
                            role: "caption"
                            color: colHead.now ? Design.accent : Design.textDim
                        }
                        Label {
                            text: colHead.modelData ? I18n.tr("On battery") : I18n.tr("Plugged in")
                            role: "caption"
                            weight: colHead.now ? Design.weight.bold : Design.weight.regular
                            color: colHead.now ? Design.accent : Design.textDim
                        }
                        Item { Layout.fillWidth: true }
                    }
                }
            }

            Repeater {
                model: section.idleRows
                delegate: RowLayout {
                    id: idleRow
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: Design.s(Design.space.md)
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Design.s(Design.space.md)
                        Label {
                            Layout.fillWidth: true
                            text: idleRow.modelData.label
                            role: "caption"
                            dim: true
                            elide: Text.ElideRight
                        }
                        Repeater {
                            model: Power.hasBattery ? [false, true] : [false]
                            Stepper {
                                required property bool modelData
                                Layout.fillWidth: false
                                Layout.preferredWidth: Design.s(170)
                                readonly property int value: section.seconds(idleRow.modelData.base, modelData)
                                valueText: section.timeoutText(value)
                                onDecrement: section.setTimeout(idleRow.modelData.base, modelData, section.stepFrom(value, -1))
                                onIncrement: section.setTimeout(idleRow.modelData.base, modelData, section.stepFrom(value, 1))
                            }
                        }
                    }
                }
            }

        }



        Toggle {
            label: I18n.tr("Other screens off when idle")
            subtitle: I18n.tr("When the main screen dims, the others go dark; any input brings them back")
            checked: Settings.idleSecondaryOff
            onToggled: Settings.set("idleSecondaryOff", !Settings.idleSecondaryOff)
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

    // The lid and the power button, each its own card: one card with the
    // two read as one setting.
    Card {
        visible: (section.part === "") && (Power.hasBattery)
        title: I18n.tr("Closing the lid")
        subtitle: I18n.tr("Plugged in and on battery each their own")
        icon: "\u{f0322}"
        accentColor: Design.peach

        RowLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.md)
            Item { Layout.fillWidth: true }
            Repeater {
                model: [false, true]
                RowLayout {
                    id: lidHead
                    required property bool modelData
                    readonly property bool now: modelData === (Power.hasBattery && !Power.charging)
                    Layout.fillWidth: false
                    Layout.preferredWidth: Design.s(170)
                    spacing: Design.s(Design.space.xs)
                    Item { Layout.fillWidth: true }
                    Icon {
                        text: lidHead.modelData ? "\u{f0079}" : "\u{f06a5}"
                        role: "caption"
                        color: lidHead.now ? Design.accent : Design.textDim
                    }
                    Label {
                        text: lidHead.modelData ? I18n.tr("On battery") : I18n.tr("Plugged in")
                        role: "caption"
                        weight: lidHead.now ? Design.weight.bold : Design.weight.regular
                        color: lidHead.now ? Design.accent : Design.textDim
                    }
                    Item { Layout.fillWidth: true }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.md)
            Label {
                Layout.fillWidth: true
                text: I18n.tr("When the lid closes")
                role: "caption"
                dim: true
                elide: Text.ElideRight
            }
            Repeater {
                model: [false, true]
                Stepper {
                    required property bool modelData
                    Layout.fillWidth: false
                    Layout.preferredWidth: Design.s(170)
                    valueText: section.lidChoices[section.lidIndex(modelData)].label
                    onDecrement: section.stepLid(modelData, -1)
                    onIncrement: section.stepLid(modelData, 1)
                }
            }
        }

        Toggle {
            label: I18n.tr("With another screen connected, only turn off the built-in one")
            subtitle: I18n.tr("Closing the lid while docked keeps working on the other screen")
            checked: Settings.lidIgnoreDocked
            onToggled: Settings.set("lidIgnoreDocked", !Settings.lidIgnoreDocked)
        }
    }

    Card {
        visible: section.part === ""
        title: I18n.tr("Power button")
        subtitle: I18n.tr("What it does, instead of the system default")
        icon: "\u{f0425}"
        accentColor: Design.accent

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

    Card {
        visible: section.part === "lock"
        title: I18n.tr("Locking")
        subtitle: I18n.tr("When the screen locks, and what the lock screen looks like. How soon after idling is on Power & Battery")
        icon: "\u{f033e}"
        accentColor: Design.blue

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
            label: I18n.tr("Only the main screen while locked")
            subtitle: I18n.tr("The lock screen shows on the main screen; the others stay off until it is opened")
            checked: Settings.lockSecondaryOff
            onToggled: Settings.set("lockSecondaryOff", !Settings.lockSecondaryOff)
        }
    }
}
