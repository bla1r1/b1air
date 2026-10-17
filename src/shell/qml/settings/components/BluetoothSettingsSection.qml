import QtQuick
import QtQuick.Layouts
import "../../Ui"
import "../../Services"

// =============================================================================
// Bluetooth Settings — Complete adapter and device management.
//
// Shows Bluetooth adapter details, discoverability, paired devices manager
// with battery info and disconnect/forget actions, and active device discovery.
// =============================================================================

ColumnLayout {
    id: section

    Layout.fillWidth: true
    spacing: Design.s(Design.space.lg)

    property bool _held: false
    function _hold(on) {
        if (on === section._held)
            return;
        section._held = on;
        if (on) Network.acquire();
        else Network.release();
    }
    Component.onCompleted: section._hold(visible)
    onVisibleChanged: section._hold(visible)
    Component.onDestruction: section._hold(false)

    readonly property var allDevices: Network.bluetooth.devices || []
    readonly property var paired: allDevices.filter(d => d.paired)
    readonly property var available: allDevices.filter(d => !d.paired)

    // ── 1. Bluetooth Adapter Card ────────────────────────────────────────────
    SettingsGroup {
        icon: "\u{f00af}"

        // Master Switch; its state is its note (see Network's Wi-Fi).
        SwitchRow {
            title: I18n.tr("Bluetooth")
            note: Network.bluetooth.power === "on"
                ? (Network.bluetooth.connected ? I18n.tr("Connected to %1", Network.bluetooth.connected.name) : I18n.tr("Bluetooth is on, ready to connect"))
                : I18n.tr("Bluetooth adapter is disabled")
            checked: Network.bluetooth.power === "on"
            onToggled: Network.toggleBluetooth()
        }

        // The adapter, and the scan that finds new devices.
        SettingsRow {
            visible: Network.bluetooth.power === "on"
            label: (Network.adapter && Network.adapter.name) || I18n.tr("Bluetooth Controller")
            // `Network.adapter` can exist without an address; the
            // concatenation once printed "Address: undefined".
            note: (Network.adapter && Network.adapter.address) ? Network.adapter.address : ""
            Button {
                checked: Network.scanning
                icon: Network.scanning ? "\u{f0110}" : "\u{f002f}"
                text: Network.scanning ? I18n.tr("Scanning...") : I18n.tr("Scan for devices")
                onClicked: {
                    if (Network.scanning) Network.stopScan();
                    else Network.startScan();
                }
            }
        }
    }

    // A device's state in words: connected or only paired, its battery, and
    // its address when it has one (a missing one printed "undefined").
    function _deviceNote(d, withState) {
        const parts = [];
        if (withState) parts.push(d.connected ? I18n.tr("Connected") : I18n.tr("Paired"));
        if (d.battery >= 0) parts.push(I18n.tr("battery %1%", d.battery));
        if (d.mac && d.name) parts.push(d.mac);
        return parts.join(" • ");
    }

    // ── 2. Paired Devices Card ───────────────────────────────────────────────
    SettingsGroup {
        visible: Network.bluetooth.power === "on"
        title: I18n.tr("Paired devices")
        icon: "\u{f00af}"

        Repeater {
            model: section.paired

            // Connect is a command among several devices, not the page's
            // one primary action: secondary, as Disconnect is.
            SettingsRow {
                id: pairedRow
                required property var modelData
                icon: pairedRow.modelData.icon || "\u{f00af}"
                label: pairedRow.modelData.name || pairedRow.modelData.mac || ""
                note: section._deviceNote(pairedRow.modelData, true)

                Button {
                    text: pairedRow.modelData.connected ? I18n.tr("Disconnect") : I18n.tr("Connect")
                    onClicked: pairedRow.modelData.connected ? Network.disconnectDevice(pairedRow.modelData.mac)
                                                   : Network.connectDevice(pairedRow.modelData.mac)
                }
                Button {
                    variant: "ghost"
                    iconOnly: true
                    icon: "\u{f0a7a}"
                    text: I18n.tr("Forget")
                    tip: I18n.tr("Forget")
                    onClicked: Network.forgetDevice(pairedRow.modelData.mac)
                }
            }
        }

        EmptyState {
            Layout.fillWidth: true
            Layout.bottomMargin: Design.s(Design.space.sm)
            visible: section.paired.length === 0
            icon: "\u{f00b0}"
            title: I18n.tr("Nothing paired")
            hint: I18n.tr("Click 'Scan for devices' above to find and pair new accessories.")
        }
    }

    // ── 3. Available Devices Card ────────────────────────────────────────────
    SettingsGroup {
        visible: Network.bluetooth.power === "on" && (Network.scanning || section.available.length > 0)
        title: I18n.tr("Available devices")
        icon: "\u{f002f}"

        Repeater {
            model: section.available

            SettingsRow {
                id: foundRow
                required property var modelData
                icon: foundRow.modelData.icon || "\u{f00af}"
                label: foundRow.modelData.name || foundRow.modelData.mac || ""
                note: section._deviceNote(foundRow.modelData, false)

                Button {
                    text: I18n.tr("Pair")
                    onClicked: Network.pairDevice(foundRow.modelData.mac)
                }
            }
        }

        EmptyState {
            Layout.fillWidth: true
            Layout.bottomMargin: Design.s(Design.space.sm)
            visible: section.available.length === 0
            icon: "\u{f002f}"
            title: I18n.tr("Scanning for accessories...")
            hint: I18n.tr("Make sure your Bluetooth device is in pairing mode.")
        }
    }
}
