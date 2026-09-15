import QtQuick
import QtQuick.Layouts
import "../../Ui"
import "../../Services"

// =============================================================================
// Network — Complete Ethernet and Wi-Fi management.
//
// Shows live Ethernet connection details, Wi-Fi status, saved network profiles,
// and available wireless access points.
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

    readonly property var inRange: Network.wifi.networks || []
    readonly property var connectedWifi: Network.wifi.connected

    function _isNear(name) {
        return section.inRange.some(n => n.ssid === name);
    }

    // Joining a network was only possible from the Control Center popup: this
    // page listed saved profiles and could toggle, disconnect and forget, but
    // had no way to connect to anything new — on the page the sidebar calls
    // "Network & Wi-Fi" and the search sends you to for "wifi".
    property string askingFor: ""

    property bool showEthConfig: false
    property string ethMethod: "auto"
    property string ethIp: Network.ethernet && Network.ethernet.ip ? Network.ethernet.ip : "192.168.1.100"
    property string ethPrefix: Network.ethernet && Network.ethernet.prefix ? String(Network.ethernet.prefix) : "24"
    property string ethGateway: "192.168.1.1"
    property string ethDns: "1.1.1.1, 8.8.8.8"

    // ── 1. Ethernet Card ─────────────────────────────────────────────────────
    Card {
        title: "Ethernet (Wired)"
        subtitle: Network.ethernet && Network.ethernet.connected
            ? "Connected via " + Network.ethernet.ifname
            : "No active wired connection detected"
        icon: "\u{f0200}" // ethernet icon
        accentColor: Design.green

        RowLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.sm)

            Rectangle {
                width: Design.s(36)
                height: width
                radius: width / 2
                color: (Network.ethernet && Network.ethernet.connected)
                    ? Design.tint(Design.green, 0.15) : Design.sunken

                Icon {
                    anchors.centerIn: parent
                    text: "\u{f0200}"
                    role: "body"
                    color: (Network.ethernet && Network.ethernet.connected)
                        ? Design.green : Design.textDim
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                Label {
                    text: (Network.ethernet && Network.ethernet.connected)
                        ? "Wired Connection (" + Network.ethernet.ifname + ")"
                        : "Disconnected"
                    weight: Design.weight.semibold
                }

                Label {
                    text: (Network.ethernet && Network.ethernet.connected)
                        ? ("IPv4: " + Network.ethernet.ip + (Network.ethernet.prefix ? "/" + Network.ethernet.prefix : ""))
                        : "Plug in an Ethernet cable to connect"
                    role: "caption"
                    dim: true
                }
            }

            Badge {
                text: (Network.ethernet && Network.ethernet.connected) ? "Active" : "Offline"
                tone: (Network.ethernet && Network.ethernet.connected) ? Design.ok : Design.danger
            }

            // Gear icon button for advanced IP configuration
            Rectangle {
                width: Design.s(32)
                height: Design.s(32)
                radius: Design.s(Design.radius.ctl)
                color: section.showEthConfig ? Design.tint(Design.green, 0.25) : (gearMa.containsMouse ? Design.raised : Design.sunken)
                border.color: section.showEthConfig ? Design.green : (gearMa.containsMouse ? Design.hover : "transparent")
                border.width: 1

                Behavior on color { ColorAnimation { duration: Design.duration.fast } }
                Behavior on border.color { ColorAnimation { duration: Design.duration.fast } }

                Icon {
                    anchors.centerIn: parent
                    text: "\u{f0493}"
                    role: "body"
                    color: section.showEthConfig ? Design.green : Design.textDim
                }

                Clickable {
                    id: gearMa
                    onClicked: section.showEthConfig = !section.showEthConfig
                }
            }
        }

        // Ethernet Details Grid
        GridLayout {
            visible: Network.ethernet && Network.ethernet.connected && !section.showEthConfig
            Layout.fillWidth: true
            columns: 2
            columnSpacing: Design.s(Design.space.md)
            rowSpacing: Design.s(Design.space.xs)

            Label { text: "Interface:"; role: "caption"; dim: true }
            Label { text: Network.ethernet ? Network.ethernet.ifname : ""; role: "caption"; isMono: true }

            Label { text: "IPv4 Address:"; role: "caption"; dim: true }
            Label { text: Network.ethernet ? Network.ethernet.ip : ""; role: "caption"; isMono: true }

            Label { visible: Network.ethernet && Network.ethernet.ip6 !== ""; text: "IPv6 Address:"; role: "caption"; dim: true }
            Label { visible: Network.ethernet && Network.ethernet.ip6 !== ""; text: Network.ethernet ? Network.ethernet.ip6 : ""; role: "caption"; isMono: true; elide: Text.ElideRight }

            Label { visible: Network.ethernet && Network.ethernet.mac !== ""; text: "Hardware MAC:"; role: "caption"; dim: true }
            Label { visible: Network.ethernet && Network.ethernet.mac !== ""; text: Network.ethernet ? Network.ethernet.mac : ""; role: "caption"; isMono: true }
        }

        // ── Ethernet Advanced IP Configuration Panel ──
        Rectangle {
            visible: section.showEthConfig
            Layout.fillWidth: true
            Layout.preferredHeight: ethConfigCol.implicitHeight + Design.s(Design.space.lg)
            radius: Design.s(Design.radius.card)
            color: Design.sunken
            border.color: Design.tint(Design.green, 0.3)
            border.width: 1

            ColumnLayout {
                id: ethConfigCol
                anchors.fill: parent
                anchors.margins: Design.s(Design.space.md)
                spacing: Design.s(Design.space.md)

                RowLayout {
                    Layout.fillWidth: true
                    Label {
                        text: "IPv4 Configuration"
                        weight: Design.weight.bold
                        color: Design.green
                    }
                    Item { Layout.fillWidth: true }
                    Pill {
                        label: "Automatic (DHCP)"
                        active: section.ethMethod === "auto"
                        activeColor: Design.green
                        onClicked: section.ethMethod = "auto"
                    }
                    Pill {
                        label: "Manual (Static IP)"
                        active: section.ethMethod === "manual"
                        activeColor: Design.green
                        onClicked: section.ethMethod = "manual"
                    }
                }

                // Static IP Fields (when method === "manual")
                ColumnLayout {
                    visible: section.ethMethod === "manual"
                    Layout.fillWidth: true
                    spacing: Design.s(Design.space.xs)

                    RowLayout {
                        Layout.fillWidth: true
                        Label { text: "IP Address"; role: "caption"; dim: true; Layout.preferredWidth: Design.s(100) }
                        Field {
                            Layout.fillWidth: true
                            placeholder: "192.168.1.100"
                            text: section.ethIp
                            onCommitted: v => section.ethIp = v
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Label { text: "Subnet Prefix"; role: "caption"; dim: true; Layout.preferredWidth: Design.s(100) }
                        Field {
                            Layout.fillWidth: true
                            placeholder: "24"
                            text: section.ethPrefix
                            onCommitted: v => section.ethPrefix = v
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Label { text: "Gateway"; role: "caption"; dim: true; Layout.preferredWidth: Design.s(100) }
                        Field {
                            Layout.fillWidth: true
                            placeholder: "192.168.1.1"
                            text: section.ethGateway
                            onCommitted: v => section.ethGateway = v
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Label { text: "DNS Servers"; role: "caption"; dim: true; Layout.preferredWidth: Design.s(100) }
                        Field {
                            Layout.fillWidth: true
                            placeholder: "1.1.1.1, 8.8.8.8"
                            text: section.ethDns
                            onCommitted: v => section.ethDns = v
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Design.s(Design.space.sm)
                    Item { Layout.fillWidth: true }

                    Pill {
                        label: "Cancel"
                        onClicked: section.showEthConfig = false
                    }

                    Pill {
                        label: "Apply Changes"
                        icon: "\u{f012c}"
                        active: true
                        activeColor: Design.green
                        onClicked: {
                            if (Network.ethernet) {
                                Network.applyEthernetConfig(
                                    Network.ethernet.ifname,
                                    section.ethMethod,
                                    section.ethIp,
                                    section.ethPrefix,
                                    section.ethGateway,
                                    section.ethDns
                                );
                            }
                            section.showEthConfig = false;
                        }
                    }
                }
            }
        }
    }

    // ── 2. Wi-Fi Card ────────────────────────────────────────────────────────
    Card {
        visible: Network.hasWifi
        title: "Wi-Fi"
        subtitle: Network.wifi.power === "on"
            ? (section.connectedWifi ? "Connected to " + section.connectedWifi.ssid : "Wi-Fi is on, not connected")
            : "Wi-Fi adapter is turned off"
        icon: "\u{f0928}"
        accentColor: Design.blue

        // Master Switch
        RowLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.md)

            Toggle {
                label: "Wi-Fi"
                subtitle: "Scan for and join wireless networks"
                checked: Network.wifi.power === "on"
                onToggled: Network.toggleWifi()
            }
        }

        // Active Connection Diagnostics
        Rectangle {
            visible: section.connectedWifi !== null && Network.wifi.power === "on"
            Layout.fillWidth: true

            // Same as the Bluetooth adapter box: anchored contents give no
            // implicit height, so this measured zero and the "Available
            // networks" heading and the network list were painted over the top
            // of the connected network and its Disconnect button.
            Layout.preferredHeight: activeBody.implicitHeight + Design.s(Design.space.md) * 2

            radius: Design.s(Design.radius.ctl)
            color: Design.sunken
            border.color: Design.tint(Design.blue, 0.3)
            border.width: 1

            ColumnLayout {
                id: activeBody
                anchors.fill: parent
                anchors.margins: Design.s(Design.space.md)
                spacing: Design.s(Design.space.sm)

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Design.s(Design.space.sm)

                    Icon {
                        text: section.connectedWifi ? section.connectedWifi.icon : "\u{f0928}"
                        role: "body"
                        color: Design.blue
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        Label {
                            text: section.connectedWifi ? section.connectedWifi.ssid : ""
                            weight: Design.weight.semibold
                            color: Design.blue
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }

                        Label {
                            text: section.connectedWifi
                                ? ("Signal " + section.connectedWifi.signal + "% • " + (section.connectedWifi.security || "Open"))
                                : ""
                            role: "caption"
                            dim: true
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                    }

                    Pill {
                        label: "Disconnect"
                        activeColor: Design.warn
                        onClicked: Network.disconnectWifi()
                    }
                }
            }
        }

        SectionLabel {
            visible: Network.wifi.power === "on" && Network.savedWifi.length > 0
            text: "Available networks"
        }

        Repeater {
            model: Network.wifi.power === "on" ? section.inRange : []

            ColumnLayout {
                id: netEntry
                required property var modelData

                readonly property bool secured: netEntry.modelData.security
                    && netEntry.modelData.security !== "open"
                readonly property bool asking: section.askingFor === netEntry.modelData.ssid

                Layout.fillWidth: true
                spacing: Design.s(Design.space.xs)

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Design.s(Design.space.sm)

                    Icon {
                        text: netEntry.modelData.icon || "\u{f0928}"
                        role: "body"
                        color: Design.textDim
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        Label {
                            text: netEntry.modelData.ssid || "Hidden network"
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }

                        Label {
                            // Says why one row joins on a click and another asks
                            // for a passphrase, the way the mini view does.
                            text: Network.isBusy(netEntry.modelData.ssid) ? "Connecting…"
                                : (netEntry.modelData.known ? "Saved"
                                : (netEntry.secured ? "Password required" : "Open network"))
                            role: "caption"
                            dim: true
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                    }

                    Icon {
                        visible: netEntry.secured
                        text: "\u{f033e}"
                        role: "caption"
                        color: Design.textFaint
                    }

                    Pill {
                        label: netEntry.asking ? "Cancel" : "Connect"
                        icon: "\u{f0928}"
                        activeColor: Design.ok
                        onClicked: {
                            if (netEntry.asking) {
                                section.askingFor = "";
                                return;
                            }
                            if (netEntry.secured && !netEntry.modelData.known) {
                                section.askingFor = netEntry.modelData.ssid;
                                return;
                            }
                            Network.connectWifi(netEntry.modelData.ssid);
                        }
                    }
                }

                Field {
                    visible: netEntry.asking
                    Layout.fillWidth: true
                    placeholder: "Passphrase for " + (netEntry.modelData.ssid || "")
                    echoMode: TextInput.Password
                    onAccepted: psk => {
                        Network.connectWifi(netEntry.modelData.ssid, psk);
                        section.askingFor = "";
                    }
                }
            }
        }

        EmptyState {
            Layout.fillWidth: true
            visible: Network.wifi.power === "on" && section.inRange.length === 0
            icon: "\u{f092e}"
            title: "No networks in range"
            hint: "Nothing is broadcasting nearby, or the scan has not finished yet."
        }

        SectionLabel {
            text: "Saved networks"
        }

        Repeater {
            model: Network.wifi.power === "on" ? Network.savedWifi : []

            RowLayout {
                required property var modelData
                Layout.fillWidth: true
                spacing: Design.s(Design.space.sm)

                Icon {
                    text: "\u{f0928}"
                    role: "body"
                    color: section._isNear(modelData.name) ? Design.blue : Design.textFaint
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    Label {
                        text: modelData.name
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }

                    Label {
                        text: (section._isNear(modelData.name) ? "In range" : "Not in range")
                            + (modelData.autoconnect ? " • joins automatically" : " • manual")
                        role: "caption"
                        dim: true
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                }

                Pill {
                    label: "Forget"
                    icon: "\u{f01b4}"
                    activeColor: Design.danger
                    onClicked: Network.forgetWifi(modelData.name)
                }
            }
        }

        EmptyState {
            Layout.fillWidth: true
            visible: Network.wifi.power === "on" && Network.savedWifi.length === 0
            icon: "\u{f092e}"
            title: "No saved networks"
            hint: "Join a network and it will be remembered here."
        }
    }
}
