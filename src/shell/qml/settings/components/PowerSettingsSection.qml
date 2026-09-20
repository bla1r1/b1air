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
     * swayidle's command line is built out of these four timeouts once, when
     * the session starts, so every change here only applied at the next login
     * — with nothing on the page to say so. Someone shortening "Turn off
     * screen after" to test it would sit through the old timeout and conclude
     * the setting did nothing.
     *
     * The daemon rebuilds swayidle from the file, so the write has to have
     * landed first; Settings.set writes asynchronously, hence the small delay.
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
        title: "Energy & performance"
        subtitle: "Tune system performance and power consumption"
        icon: "\u{f0084}"
        accentColor: Design.green

        // The mini view in the Control Center has always had this empty state;
        // the full page drew three live-looking tiles that silently did nothing
        // when power-profiles-daemon was not running.
        EmptyState {
            visible: !Power.hasProfiles
            Layout.fillWidth: true
            icon: "\u{f0241}"
            title: "No energy modes"
            hint: "power-profiles-daemon is not running, so there is nothing to switch between."
        }

        RowLayout {
            visible: Power.hasProfiles
            Layout.fillWidth: true
            spacing: Design.s(Design.space.sm)

            Repeater {
                model: [
                    { id: "performance", label: "Performance", icon: "\u{f0e4}" },
                    { id: "balanced",    label: "Balanced",    icon: "\u{f0241}" },
                    { id: "power-saver", label: "Power Saver", icon: "\u{f0084}" }
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
        title: "Display brightness"
        subtitle: "Backlight level of the built-in panel"
        icon: "\u{f00df}"
        accentColor: Design.yellow

        Slider {
            Layout.fillWidth: true
            Layout.preferredHeight: Design.s(Design.size.ctl)
            value: Power.brightness
            tone: Design.yellow
            icon: "\u{f00df}"
            label: "Brightness"
            onMoved: pct => Power.setBrightness(pct)
        }
    }

    // ── 3. Battery ───────────────────────────────────────────────────────────
    Card {
        visible: Power.hasBattery
        title: "Battery"
        subtitle: Power.charging ? "Currently charging" : "Running on battery power"
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
                    text: Power.status + (Power.timeRemainingText !== ""
                        ? " • " + (Power.charging ? "until full " : "left ") + Power.timeRemainingText
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
            text: "Installed packs"
            Layout.topMargin: Design.s(Design.space.sm)
        }

        Repeater {
            model: Power.hasMultipleBatteries ? Power.batteries : []

            DeviceRow {
                required property var modelData

                Layout.fillWidth: true
                title: Power.labelOf(modelData) + (modelData.model ? " · " + modelData.model : "")
                subtitle: Power.stateTextOf(modelData)
                    + (Power.healthOf(modelData) > 0
                        ? " • health " + Power.healthOf(modelData) + "%"
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
            title: "Battery health"
            subtitle: "Capacity now, against what the pack shipped with"
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
        title: "Charge control"
        subtitle: "Keep the battery off a full charge, so it ages more slowly"
        icon: "\u{f0084}"
        accentColor: Design.teal

        Toggle {
            visible: Power.hasChargeLimit
            label: "Limit the charge"
            subtitle: "Stop charging below full. 100% means no limit."
            checked: Power.chargeLimit < 100
            onToggled: Power.setChargeLimit(Power.chargeLimit < 100 ? 100 : 80)
        }

        Stepper {
            visible: Power.hasChargeLimit && Power.chargeLimit < 100
            label: "Stop charging at"
            valueText: Power.chargeLimit + "%"
            // Not below 50: the pack would spend its life nearly empty, which
            // trades one kind of wear for another.
            onDecrement: Power.setChargeLimit(Math.max(50, Power.chargeLimit - 5))
            onIncrement: Power.setChargeLimit(Math.min(100, Power.chargeLimit + 5))
        }

        SectionLabel {
            visible: Power.hasChargeBehaviour
            text: "While plugged in"
            Layout.topMargin: Design.s(Design.space.sm)
        }

        RowLayout {
            visible: Power.hasChargeBehaviour
            Layout.fillWidth: true
            spacing: Design.s(Design.space.xs)

            Repeater {
                model: [
                    { id: "auto",            label: "Charge" },
                    { id: "inhibit-charge",  label: "Hold" },
                    { id: "force-discharge", label: "Discharge" }
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
            text: "These files belong to root on this machine, so a change will ask "
                + "for a password. Re-running the installer puts you in the `power` "
                + "group and installs the udev rule that makes it direct."
        }
    }

    // ── 3.5 Low battery ──────────────────────────────────────────────────────
    Card {
        visible: Power.hasBattery
        title: "Low battery"
        subtitle: "What happens as the charge runs out"
        icon: "\u{f0084}"
        accentColor: Design.warn

        Toggle {
            label: "Warn me when the battery is low"
            subtitle: "A notification at the level below. Nothing warned about the "
                    + "charge before — the machine simply went off."
            checked: Settings.batteryLowWarning !== false
            onToggled: Settings.set("batteryLowWarning", !(Settings.batteryLowWarning !== false))
        }

        Stepper {
            visible: Settings.batteryLowWarning !== false
            label: "Warn at"
            valueText: Power.lowThreshold + "%"
            onDecrement: Settings.set("batteryLowPercent",
                                      Math.max(Power.criticalThreshold + 5, Power.lowThreshold - 5))
            onIncrement: Settings.set("batteryLowPercent", Math.min(50, Power.lowThreshold + 5))
        }

        Toggle {
            label: "Suspend before the battery dies"
            subtitle: "A suspend with a few percent left keeps the session; a flat "
                    + "battery does not."
            checked: Settings.batteryCriticalAction !== "none"
            onToggled: Settings.set("batteryCriticalAction",
                                    Settings.batteryCriticalAction === "none" ? "suspend" : "none")
        }

        Stepper {
            visible: Settings.batteryCriticalAction !== "none"
            label: "Suspend at"
            valueText: Power.criticalThreshold + "%"
            onDecrement: Settings.set("batteryCriticalPercent", Math.max(2, Power.criticalThreshold - 1))
            onIncrement: Settings.set("batteryCriticalPercent",
                                      Math.min(Power.lowThreshold - 5, Power.criticalThreshold + 1))
        }
    }

    // ── 4. Screen and Sleep Timeouts ─────────────────────────────────────────
    Card {
        title: "Screen & sleep timeouts"
        subtitle: "Control idle dimming, display power off, and automatic system suspension"
        icon: "\u{f033e}"
        accentColor: Design.peach

        Toggle {
            label: "Dim screen on lock"
            subtitle: "Lower display brightness immediately when screen is locked"
            checked: Settings.dimOnLock
            onToggled: Settings.set("dimOnLock", !Settings.dimOnLock)
        }

        // Dimming and locking were the two timeouts swayidle was already
        // being built with and the only two this page did not show, so the
        // machine dimmed at five minutes and locked at ten with nothing here
        // saying so, let alone offering to change it.
        Stepper {
            label: "Dim screen after"
            valueText: (Math.round(Settings.dimTimeout / 60)) + " min"
            onDecrement: section.setIdleTimeout("dimTimeout", Math.max(60, Settings.dimTimeout - 60))
            onIncrement: section.setIdleTimeout("dimTimeout", Math.min(3600, Settings.dimTimeout + 60))
        }

        Stepper {
            label: "Lock screen after"
            valueText: (Math.round(Settings.lockTimeout / 60)) + " min"
            onDecrement: section.setIdleTimeout("lockTimeout", Math.max(60, Settings.lockTimeout - 60))
            onIncrement: section.setIdleTimeout("lockTimeout", Math.min(7200, Settings.lockTimeout + 60))
        }

        Stepper {
            label: "Turn off screen after"
            valueText: (Math.round(Settings.dpmsTimeout / 60)) + " min"
            onDecrement: section.setIdleTimeout("dpmsTimeout", Math.max(60, Settings.dpmsTimeout - 60))
            onIncrement: section.setIdleTimeout("dpmsTimeout", Math.min(3600, Settings.dpmsTimeout + 60))
        }

        Toggle {
            label: "Automatic sleep"
            subtitle: "Suspend the system automatically when left idle"
            checked: Settings.autoSuspend
            onToggled: section.setIdleTimeout("autoSuspend", !Settings.autoSuspend)
        }

        Stepper {
            visible: Settings.autoSuspend
            label: "Suspend system after"
            valueText: (Math.round(Settings.suspendTimeout / 60)) + " min"
            onDecrement: section.setIdleTimeout("suspendTimeout", Math.max(300, Settings.suspendTimeout - 300))
            onIncrement: section.setIdleTimeout("suspendTimeout", Math.min(7200, Settings.suspendTimeout + 300))
        }
    }
}
