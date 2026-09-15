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
    Card {
        title: "Bluetooth"
        subtitle: Network.bluetooth.power === "on"
            ? (Network.bluetooth.connected ? "Connected to " + Network.bluetooth.connected.name : "Bluetooth is on, ready to connect")
            : "Bluetooth adapter is disabled"
        icon: "\u{f00af}"
        accentColor: Design.mauve

        // Master Switch
        RowLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.md)

            Toggle {
                label: "Bluetooth"
                subtitle: "Turn the adapter on to find, pair and connect devices"
                checked: Network.bluetooth.power === "on"
                onToggled: Network.toggleBluetooth()
            }
        }

        // Adapter Info & Discoverability
        Rectangle {
            visible: Network.bluetooth.power === "on"
            Layout.fillWidth: true

            // Its contents are anchored, and anchored children give a parent no
            // implicit height, so this box measured zero and the "Paired
            // devices" card below it was drawn straight over the adapter name
            // and the Scan button. The height has to be stated.
            Layout.preferredHeight: adapterBody.implicitHeight + Design.s(Design.space.md) * 2

            radius: Design.s(Design.radius.ctl)
            color: Design.sunken
            border.color: Design.tint(Design.mauve, 0.3)
            border.width: 1

            ColumnLayout {
                id: adapterBody
                anchors.fill: parent
                anchors.margins: Design.s(Design.space.md)
                spacing: Design.s(Design.space.sm)

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Design.s(Design.space.sm)

                    Icon {
                        text: "\u{f00af}"
                        role: "body"
                        color: Design.mauve
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        // fillWidth on the label, not only on the column
                        // around it — that is what actually pushes the Scan
                        // button to the end of the row, and it is what the
                        // network list two files over already does.
                        Label {
                            text: Network.adapter ? (Network.adapter.name || "Bluetooth Controller") : "Bluetooth Controller"
                            weight: Design.weight.semibold
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }

                        Label {
                            // `Network.adapter` can exist without an address,
                            // and the concatenation printed the literal text
                            // "Address: undefined" on screen.
                            text: (Network.adapter && Network.adapter.address)
                                ? "Address: " + Network.adapter.address : ""
                            visible: text !== ""
                            role: "caption"
                            dim: true
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                    }

                    Pill {
                        label: Network.scanning ? "Scanning..." : "Scan for devices"
                        icon: Network.scanning ? "\u{f0110}" : "\u{f002f}"
                        active: Network.scanning
                        activeColor: Design.mauve
                        onClicked: {
                            if (Network.scanning) Network.stopScan();
                            else Network.startScan();
                        }
                    }
                }
            }
        }
    }

    // ── 2. Paired Devices Card ───────────────────────────────────────────────
    Card {
        visible: Network.bluetooth.power === "on"
        title: "Paired devices"
        subtitle: "Devices trusted by this machine"
        icon: "\u{f00af}"
        accentColor: Design.mauve

        Repeater {
            model: section.paired

            RowLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: Design.s(Design.space.sm)

                Icon {
                    text: modelData.icon || "\u{f00af}"
                    role: "body"
                    color: modelData.connected ? Design.mauve : Design.textFaint
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    Label {
                        text: modelData.name || modelData.mac
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }

                    Label {
                        text: (modelData.connected ? "Connected" : "Paired")
                            + (modelData.battery >= 0 ? " • battery " + modelData.battery + "%" : "")
                            + " • " + modelData.mac
                        role: "caption"
                        dim: true
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                }

                Pill {
                    visible: !modelData.connected
                    label: "Connect"
                    onClicked: Network.connectDevice(modelData.mac)
                }

                Pill {
                    visible: modelData.connected
                    label: "Disconnect"
                    onClicked: Network.disconnectDevice(modelData.mac)
                }

                Pill {
                    label: "Forget"
                    icon: "\u{f01b4}"
                    activeColor: Design.danger
                    onClicked: Network.forgetDevice(modelData.mac)
                }
            }
        }

        EmptyState {
            Layout.fillWidth: true
            visible: section.paired.length === 0
            icon: "\u{f00b0}"
            title: "Nothing paired"
            hint: "Click 'Scan for devices' above to find and pair new accessories."
        }
    }

    // ── 3. Available Devices Card ────────────────────────────────────────────
    Card {
        visible: Network.bluetooth.power === "on" && (Network.scanning || section.available.length > 0)
        title: "Available devices"
        subtitle: "Discovered Bluetooth accessories in range"
        icon: "\u{f002f}"
        accentColor: Design.sapphire

        Repeater {
            model: section.available

            RowLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: Design.s(Design.space.sm)

                Icon {
                    text: modelData.icon || "\u{f00af}"
                    role: "body"
                    color: Design.sapphire
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    Label {
                        text: modelData.name || modelData.mac
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }

                    Label {
                        text: modelData.mac
                        role: "caption"
                        dim: true
                        Layout.fillWidth: true
                    }
                }

                Pill {
                    label: "Pair"
                    icon: "\u{f00af}"
                    activeColor: Design.sapphire
                    onClicked: Network.pairDevice(modelData.mac)
                }
            }
        }

        EmptyState {
            Layout.fillWidth: true
            visible: section.available.length === 0
            icon: "\u{f002f}"
            title: "Scanning for accessories..."
            hint: "Make sure your Bluetooth device is in pairing mode."
        }
    }
}
