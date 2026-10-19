import QtQuick
import QtQuick.Layouts
import QtQuick.Dialogs
import Quickshell
import Quickshell.Io
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

    // First-run setup (SetupWizard) shows the page without the cards for
    // later: what anyone needs on the first day, not everything there is.
    property bool essentials: false

    Layout.fillWidth: true
    spacing: Design.s(Design.space.lg)

    property bool _held: false
    function _hold(on) {
        if (on === section._held)
            return;
        section._held = on;
        if (on) { Network.acquire(); Vpn.acquire(); }
        else { Network.release(); Vpn.release(); }
    }
    Component.onCompleted: section._hold(visible)
    onVisibleChanged: section._hold(visible)
    Component.onDestruction: section._hold(false)

    readonly property var inRange: Network.wifi.networks || []
    readonly property var connectedWifi: Network.wifi.connected
    // In range, less the one in use: that one has its own row on top.
    readonly property var others: Network.wifi.power === "on"
        ? section.inRange.filter(n => !section.connectedWifi || n.ssid !== section.connectedWifi.ssid) : []

    function _isNear(name) {
        return section.inRange.some(n => n.ssid === name);
    }

    // Joining a network was only possible from the Control Center popup: this
    // page listed saved profiles and could toggle, disconnect and forget, but
    // had no way to connect to anything new — on the page the sidebar calls
    // "Network & Wi-Fi" and the search sends you to for "wifi".
    property string askingFor: ""

    function ask(ssid) {
        section.askingFor = ssid;
        pskField.text = "";
        pskField.focusInput();
    }

    // A failed join said nothing at all. NM reports a wrong passphrase as
    // missing secrets or the supplicant giving up, depending on the driver.
    function failText(reason) {
        if (reason === "WifiNetworkLost") return I18n.tr("The network went out of range");
        if (reason === "Unknown" || reason === "") return I18n.tr("Could not connect");
        return I18n.tr("Wrong password, or the network refused it");
    }

    Connections {
        target: Network
        // Asked again at once, for the one that just failed.
        function onWifiFailed(ssid, reason) { section.ask(ssid); }
    }

    property bool showEthConfig: false
    property string ethMethod: "auto"
    property string ethIp: Network.ethernet && Network.ethernet.ip ? Network.ethernet.ip : "192.168.1.100"
    property string ethPrefix: Network.ethernet && Network.ethernet.prefix ? String(Network.ethernet.prefix) : "24"
    property string ethGateway: "192.168.1.1"
    property string ethDns: "1.1.1.1, 8.8.8.8"

    // ── 1. Ethernet Card ─────────────────────────────────────────────────────
    SettingsGroup {
        visible: !section.essentials
        title: I18n.tr("Ethernet (Wired)")
        icon: "\u{f0200}" // ethernet icon

        // Its state is the row: no group note retelling it, and no red
        // "Offline" — an unplugged cable is not a fault.
        SettingsRow {
            id: ethRow
            readonly property bool wired: !!(Network.ethernet && Network.ethernet.connected)
            label: wired ? I18n.tr("Wired Connection (%1)", Network.ethernet.ifname) : I18n.tr("Disconnected")
            note: wired
                ? ("IPv4: " + Network.ethernet.ip + (Network.ethernet.prefix ? "/" + Network.ethernet.prefix : ""))
                : I18n.tr("Plug in an Ethernet cable to connect")

            Badge {
                visible: ethRow.wired
                text: I18n.tr("Active")
                tone: Design.ok
            }
            Button {
                iconOnly: true
                variant: "ghost"
                checked: section.showEthConfig
                icon: "\u{f0493}"
                text: I18n.tr("IPv4 Configuration")
                tip: I18n.tr("IPv4 Configuration")
                onClicked: section.showEthConfig = !section.showEthConfig
            }
        }

        // Ethernet Details Grid
        GridLayout {
            visible: Network.ethernet && Network.ethernet.connected && !section.showEthConfig
            Layout.fillWidth: true
            columns: 2
            columnSpacing: Design.s(Design.space.md)
            rowSpacing: Design.s(Design.space.xs)

            Label { text: I18n.tr("Interface:"); role: "caption"; dim: true }
            Label { text: Network.ethernet ? Network.ethernet.ifname : ""; role: "caption"; isMono: true }

            Label { text: I18n.tr("IPv4 Address:"); role: "caption"; dim: true }
            Label { text: Network.ethernet ? Network.ethernet.ip : ""; role: "caption"; isMono: true }

            Label { visible: Network.ethernet && Network.ethernet.ip6 !== ""; text: I18n.tr("IPv6 Address:"); role: "caption"; dim: true }
            Label { visible: Network.ethernet && Network.ethernet.ip6 !== ""; text: Network.ethernet ? Network.ethernet.ip6 : ""; role: "caption"; isMono: true; elide: Text.ElideRight }

            Label { visible: Network.ethernet && Network.ethernet.mac !== ""; text: I18n.tr("Hardware MAC:"); role: "caption"; dim: true }
            Label { visible: Network.ethernet && Network.ethernet.mac !== ""; text: Network.ethernet ? Network.ethernet.mac : ""; role: "caption"; isMono: true }
        }

        // ── Ethernet Advanced IP Configuration Panel ──
        Surface {
            kind: "well"
            visible: section.showEthConfig
            Layout.fillWidth: true
            Layout.preferredHeight: ethConfigCol.implicitHeight + Design.s(Design.space.lg)
            radius: Design.s(Design.radius.card)
            border.color: Design.line
            border.width: 1

            ColumnLayout {
                id: ethConfigCol
                anchors.fill: parent
                anchors.margins: Design.s(Design.space.md)
                spacing: Design.s(Design.space.md)

                RowLayout {
                    Layout.fillWidth: true
                    Label {
                        text: I18n.tr("IPv4 Configuration")
                        weight: Design.weight.semibold
                        color: Design.text
                    }
                    Item { Layout.fillWidth: true }
                    SegmentedControl {
                            model: [
                            { id: "auto", label: I18n.tr("Automatic (DHCP)") },
                            { id: "manual", label: I18n.tr("Manual (Static IP)") }
                        ]
                        current: section.ethMethod
                        onPicked: id => section.ethMethod = id
                    }
                }

                // Static IP Fields (when method === "manual")
                ColumnLayout {
                    visible: section.ethMethod === "manual"
                    Layout.fillWidth: true
                    spacing: Design.s(Design.space.xs)

                    RowLayout {
                        Layout.fillWidth: true
                        Label { text: I18n.tr("IP Address"); role: "caption"; dim: true; Layout.preferredWidth: Design.s(Design.width.field) }
                        Field {
                            mono: true
                            Layout.fillWidth: true
                            placeholder: "192.168.1.100"
                            text: section.ethIp
                            onCommitted: v => section.ethIp = v
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Label { text: I18n.tr("Subnet Prefix"); role: "caption"; dim: true; Layout.preferredWidth: Design.s(Design.width.field) }
                        Field {
                            mono: true
                            Layout.fillWidth: true
                            placeholder: "24"
                            text: section.ethPrefix
                            onCommitted: v => section.ethPrefix = v
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Label { text: I18n.tr("Gateway"); role: "caption"; dim: true; Layout.preferredWidth: Design.s(Design.width.field) }
                        Field {
                            mono: true
                            Layout.fillWidth: true
                            placeholder: "192.168.1.1"
                            text: section.ethGateway
                            onCommitted: v => section.ethGateway = v
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Label { text: I18n.tr("DNS Servers"); role: "caption"; dim: true; Layout.preferredWidth: Design.s(Design.width.field) }
                        Field {
                            mono: true
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

                    Button {
                            variant: "secondary"
                        text: I18n.tr("Cancel")
                        onClicked: section.showEthConfig = false
                    }

                    Button {
                            variant: "primary"
                        icon: "\u{f012c}"
                        text: I18n.tr("Apply Changes")
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
    SettingsGroup {
        visible: Network.hasWifi
        icon: "\u{f0928}"

        // Master Switch. The group has no title of its own: it said "Wi-Fi"
        // over a switch that said "Wi-Fi". Its state is the switch's note.
        SwitchRow {
            title: I18n.tr("Wi-Fi")
            note: Network.wifi.power === "on"
                ? (section.connectedWifi ? I18n.tr("Connected to %1", section.connectedWifi.ssid) : I18n.tr("Wi-Fi is on, not connected"))
                : I18n.tr("Wi-Fi adapter is turned off")
            checked: Network.wifi.power === "on"
            onToggled: Network.toggleWifi()
        }

        // The network in use: a row like the others, with its one command.
        SettingsRow {
            visible: section.connectedWifi !== null && Network.wifi.power === "on"
            icon: (section.connectedWifi && section.connectedWifi.icon) || "\u{f0928}"
            label: section.connectedWifi ? section.connectedWifi.ssid : ""
            note: section.connectedWifi
                ? I18n.tr("Signal %1% • %2", section.connectedWifi.signal, (section.connectedWifi.security || I18n.tr("Open")))
                : ""
            Button {
                text: I18n.tr("Disconnect")
                onClicked: Network.disconnectWifi()
            }
        }
    }

    // The networks in range, a card of their own: under a small caption
    // inside the Wi-Fi card they ran into the connected network above.
    SettingsGroup {
        visible: Network.hasWifi && Network.wifi.power === "on"
        title: I18n.tr("Available networks")

        // The passphrase field, outside the list: Services/Network replaces
        // the list every two seconds (signal strengths change), and the
        // Repeater builds every row again — a field inside a row lost what
        // had been typed into it and its focus with it, mid-password.
        ColumnLayout {
            visible: section.askingFor !== ""
            Layout.fillWidth: true
            spacing: Design.s(Design.space.xs)

            Field {
                id: pskField
                Layout.fillWidth: true
                placeholder: I18n.tr("Passphrase for %1", section.askingFor)
                echoMode: TextInput.Password
                onAccepted: psk => {
                    if (psk.length === 0) return;
                    Network.connectWifi(section.askingFor, psk);
                    section.askingFor = "";
                }
            }

            Label {
                visible: Network.failedSsid !== "" && Network.failedSsid === section.askingFor
                text: section.failText(Network.failedReason)
                role: "caption"
                color: Design.danger
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
            }
        }

        Repeater {
            model: section.others

            // Connect is secondary: one per network, so none of them is the
            // page's primary action.
            SettingsRow {
                id: netEntry
                required property var modelData

                readonly property bool secured: !!netEntry.modelData.security
                    && netEntry.modelData.security !== "open"
                readonly property bool asking: section.askingFor === netEntry.modelData.ssid

                icon: netEntry.modelData.icon || "\u{f0928}"
                label: netEntry.modelData.ssid || I18n.tr("Hidden network")
                // Says why one row joins on a click and another asks for a
                // passphrase, the way the mini view does.
                note: Network.isBusy(netEntry.modelData.ssid) ? I18n.tr("Connecting…")
                    : Network.failedSsid === netEntry.modelData.ssid ? section.failText(Network.failedReason)
                    : (netEntry.modelData.known ? I18n.tr("Saved")
                    : (netEntry.secured ? I18n.tr("Password required") : I18n.tr("Open network")))

                Button {
                    text: netEntry.asking ? I18n.tr("Cancel") : I18n.tr("Connect")
                    onClicked: {
                        if (netEntry.asking) {
                            section.askingFor = "";
                            return;
                        }
                        if (netEntry.secured && !netEntry.modelData.known) {
                            section.ask(netEntry.modelData.ssid);
                            return;
                        }
                        Network.connectWifi(netEntry.modelData.ssid);
                    }
                }
            }
        }

        EmptyState {
            Layout.fillWidth: true
            visible: Network.wifi.power === "on" && section.inRange.length === 0
            icon: "\u{f092e}"
            title: I18n.tr("No networks in range")
            hint: I18n.tr("Nothing is broadcasting nearby, or the scan has not finished yet.")
        }

    }

    SettingsGroup {
        visible: Network.hasWifi && Network.wifi.power === "on" && Network.savedWifi.length > 0
        title: I18n.tr("Saved networks")

        // Nothing saved needs no notice: the list above already says which
        // networks are known.
        Repeater {
            model: Network.wifi.power === "on" ? Network.savedWifi : []

            SettingsRow {
                id: savedRow
                required property var modelData
                icon: "\u{f0928}"
                label: savedRow.modelData.name
                note: (section._isNear(savedRow.modelData.name) ? I18n.tr("In range") : I18n.tr("Not in range"))
                    + " • " + (savedRow.modelData.autoconnect ? I18n.tr("joins automatically") : I18n.tr("manual"))
                Button {
                    variant: "ghost"
                    iconOnly: true
                    icon: "\u{f0a7a}"
                    text: I18n.tr("Forget")
                    tip: I18n.tr("Forget")
                    onClicked: Network.forgetWifi(savedRow.modelData.name)
                }
            }
        }
    }

    // ── VPN ──────────────────────────────────────────────────────────────────
    // NetworkManager's connections and Tailscale (Services/Vpn.qml). A
    // provider's .ovpn or a WireGuard .conf becomes a connection with Import.
    SettingsGroup {
        title: I18n.tr("VPN")

        Repeater {
            model: Vpn.connections

            SettingsRow {
                id: vpnRow
                required property var modelData
                icon: "\u{f0498}"
                label: vpnRow.modelData.name
                note: vpnRow.modelData.type + (vpnRow.modelData.active ? " • " + I18n.tr("Connected") : "")
                Switch {
                    checked: vpnRow.modelData.active
                    accessibleName: vpnRow.modelData.name
                    onToggled: vpnRow.modelData.active ? Vpn.down(vpnRow.modelData.name) : Vpn.up(vpnRow.modelData.name)
                }
            }
        }

        SettingsRow {
            visible: Vpn.hasTailscale
            icon: "\u{f0498}"
            label: "Tailscale"
            note: Vpn.tailscaleUp ? I18n.tr("Connected")
                : Vpn.tailscaleState === "NeedsLogin" ? I18n.tr("Not signed in: turning it on opens the sign-in page")
                : Vpn.tailscaleState === "stopped" ? I18n.tr("Its service is not running")
                : I18n.tr("Off")
            Switch {
                checked: Vpn.tailscaleUp
                accessibleName: "Tailscale"
                onToggled: Vpn.tailscaleUp ? Vpn.down("Tailscale") : Vpn.up("Tailscale")
            }
        }

        EmptyState {
            Layout.fillWidth: true
            visible: !Vpn.available
            icon: "\u{f0498}"
            title: I18n.tr("No VPN set up")
            hint: I18n.tr("Import the .ovpn or WireGuard .conf file your VPN provider gives you.")
        }

        SettingsRow {
            label: I18n.tr("Add a VPN")
            note: section.vpnNote !== "" ? section.vpnNote : I18n.tr("OpenVPN (.ovpn) or WireGuard (.conf)")
            Button {
                icon: "\u{f0552}"
                label: I18n.tr("Import…")
                onActivated: vpnFileDialog.open()
            }
        }
    }

    property string vpnNote: ""
    Connections {
        target: Vpn
        function onFailed(message) { section.vpnNote = message; }
    }

    FileDialog {
        id: vpnFileDialog
        title: I18n.tr("Import a VPN")
        nameFilters: [I18n.tr("VPN configurations") + " (*.ovpn *.conf)"]
        onAccepted: {
            section.vpnNote = "";
            Vpn.importFile(selectedFile.toString());
        }
    }

    // ── Firewall ─────────────────────────────────────────────────────────────
    // firewalld, which the default edition installs and turns on with the
    // remote desktop and mDNS let in (install.sh, configure_firewall).
    property string firewallState: ""   // "" unknown, "absent", "running", "not running"

    Process {
        id: firewallProbe
        running: section.visible
        command: ["sh", "-c", "command -v firewall-cmd >/dev/null 2>&1 || { echo absent; exit; }; firewall-cmd --state 2>&1 | tail -n1"]
        stdout: StdioCollector { onStreamFinished: section.firewallState = this.text.trim() }
    }
    Process {
        id: firewallSwitch
        onExited: { firewallProbe.running = false; firewallProbe.running = true; }
    }

    SettingsGroup {
        visible: section.firewallState !== "" && section.firewallState !== "absent"
        title: I18n.tr("Firewall")

        SettingsRow {
            icon: "\u{f0498}"
            label: I18n.tr("Firewall")
            note: section.firewallState === "running"
                ? I18n.tr("On: only the remote desktop and devices on this network can reach in")
                : I18n.tr("Off: anything on the network can reach whatever this computer serves")
            Switch {
                checked: section.firewallState === "running"
                accessibleName: I18n.tr("Firewall")
                onToggled: {
                    firewallSwitch.command = ["pkexec", "systemctl", checked ? "disable" : "enable", "--now", "firewalld"];
                    firewallSwitch.running = true;
                }
            }
        }
    }
}
