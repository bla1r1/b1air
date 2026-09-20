pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Qt.labs.folderlistmodel
import Quickshell.Bluetooth
import Quickshell.Networking

// =============================================================================
// Owner of Wi-Fi and Bluetooth state, on NetworkManager and BlueZ directly.
//
// Was: two shell scripts on a 1-3 second timer — wifi_panel_logic.sh calling
// nmcli, bluetooth_panel_logic.sh calling bluetoothctl, both parsed from JSON.
//
// An earlier version of this file said these had no native equivalent. That was
// wrong and was written from memory: Quickshell.Networking and
// Quickshell.Bluetooth both exist and are event-driven.
//
// PUBLIC SHAPE UNCHANGED. NetworkPopup parses `{power, connected, networks}` and
// `{power, connected, devices}` out of the two signals, so the same objects are
// built here from live properties rather than from a script's stdout. That seam
// is why swapping the source did not touch the popup.
// =============================================================================

Singleton {
    id: root

    property var wifi: ({})
    property var bluetooth: ({})

    signal wifiUpdated(var data)
    signal bluetoothUpdated(var data)

    // ── Consumers ────────────────────────────────────────────────────────────
    // Nothing polls any more, so this only scopes the scan: leaving the Wi-Fi
    // scanner running all session drains battery for a list nobody is reading.

    property int _users: 0
    function acquire() { root._users++; }
    function release() { if (root._users > 0) root._users--; }

    // ── Devices ──────────────────────────────────────────────────────────────

    readonly property var wifiDevice: {
        const d = Networking.devices.values.find(x => x.type === DeviceType.Wifi);
        return d || null;
    }

    property bool hasWifiSys: false

    FolderListModel {
        id: netNodes
        folder: "file:///sys/class/net"
        showFiles: true
        showDirs: true
        showDotAndDotDot: false

        // Matched here rather than with nameFilters, which FolderListModel
        // applies to files only — the sysfs entries are directories, so a
        // filter would have matched every interface including lo and eth0.
        onCountChanged: {
            let found = false;
            for (let i = 0; i < count; ++i) {
                if (String(get(i, "fileName")).startsWith("wl")) {
                    found = true;
                    break;
                }
            }
            root.hasWifiSys = found;
        }
    }
    readonly property bool hasWifi: root.hasWifiSys || root.wifiDevice !== null

    readonly property var adapter: Bluetooth.defaultAdapter

    // A directory listing, not a job for a shell — same reasoning as
    // Services/Power's battery and backlight probes.
    readonly property bool hasBluetoothSys: bluetoothNodes.count > 0

    FolderListModel {
        id: bluetoothNodes
        folder: "file:///sys/class/bluetooth"
        showFiles: true
        showDirs: true
        showDotAndDotDot: false
    }
    readonly property bool hasBluetooth: root.hasBluetoothSys || root.adapter !== null

    Binding {
        target: root.wifiDevice
        property: "scannerEnabled"
        value: root._users > 0
        when: root.wifiDevice !== null
    }

    // ── In-flight operations ─────────────────────────────────────────────────
    // Kept from the old file: the popup marks a row busy while a connect or a
    // radio toggle is in flight, and reads it back to show a spinner.

    property var busy: ({})

    function setBusy(id, on) {
        let b = Object.assign({}, root.busy);
        if (on) b[id] = true;
        else delete b[id];
        root.busy = b;
    }

    function isBusy(id) { return root.busy[id] === true; }
    readonly property bool anyBusy: Object.keys(root.busy).length > 0

    // ── Writes ───────────────────────────────────────────────────────────────

    function setWifiEnabled(on) { Networking.wifiEnabled = on; }

    function toggleWifi() {
        const next = !Networking.wifiEnabled;
        Networking.wifiEnabled = next;
        Quickshell.execDetached(["nmcli", "radio", "wifi", next ? "on" : "off"]);
        root._rebuild();
    }

    function connectWifi(ssid, psk) {
        if (!root.wifiDevice) return;
        const n = root.wifiDevice.networks.values.find(x => x.name === ssid);
        if (!n) return;
        root.setBusy(ssid, true);
        if (psk !== undefined && psk !== "") n.connectWithPsk(psk);
        else n.connect();
    }

    /** Deleting the saved connection is the only way to stop NM auto-joining. */
    function forgetWifi(ssid) {
        Quickshell.execDetached(["nmcli", "connection", "delete", "id", ssid]);
        savedReader.restart();
    }

    // Saved profiles, which are not the same list as "networks in range": the
    // settings page has to show the ones you are nowhere near, or "forget" is
    // only offered for networks you are currently standing next to.
    property var savedWifi: []

    Process {
        id: savedReader
        running: root._users > 0
        command: ["nmcli", "-t", "-f", "NAME,TYPE,AUTOCONNECT", "connection", "show"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.savedWifi = (this.text || "").split("\n")
                    .map(l => root._splitTerse(l))
                    .filter(f => f.length >= 2 && f[1] === "802-11-wireless" && f[0] !== "")
                    .map(f => ({ name: f[0], autoconnect: f[2] === "yes" }));
            }
        }
        function restart() { running = false; running = true; }
    }

    /**
     * One line of `nmcli -t` output into its fields.
     *
     * nmcli separates fields with ":" and escapes a literal colon inside a
     * value as "\\:". Splitting on every colon therefore tears a network whose
     * name contains one into two fields, the type lands in the wrong column,
     * and the row is dropped: an SSID like "Cafe:Guest" simply vanished from
     * the saved-networks list.
     */
    function _splitTerse(line) {
        const out = [];
        let cur = "";
        for (let i = 0; i < line.length; ++i) {
            const c = line[i];
            if (c === "\\" && i + 1 < line.length) {
                cur += line[++i];
            } else if (c === ":") {
                out.push(cur);
                cur = "";
            } else {
                cur += c;
            }
        }
        out.push(cur);
        return out;
    }

    function disconnectWifi() {
        if (root.wifiDevice) root.wifiDevice.disconnect();
    }

    function setBluetoothEnabled(on) {
        if (root.adapter) root.adapter.enabled = on;
    }

    function toggleBluetooth() {
        const next = !(root.adapter && root.adapter.enabled);
        if (root.adapter) root.adapter.enabled = next;
        Quickshell.execDetached(["bluetoothctl", "power", next ? "on" : "off"]);
        root._rebuild();
    }

    function connectDevice(address) {
        const d = Bluetooth.devices.values.find(x => x.address === address);
        if (!d) return;
        root.setBusy(address, true);
        if (!d.paired) d.pair();
        else d.connect();
    }

    // ── Ethernet & IP Diagnostics ───────────────────────────────────────────
    property var ethernet: null

    Process {
        id: ipReader
        running: root._users > 0
        command: ["bash", "-c", "ip -j -p addr show 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const ifaces = JSON.parse(this.text || "[]");
                    // Find ethernet interface (not loopback, not wlan/wl)
                    const eth = ifaces.find(i => i.ifname !== "lo" && !i.ifname.startsWith("wl") && i.link_type === "ether");
                    if (eth) {
                        const inet = (eth.addr_info || []).find(a => a.family === "inet");
                        const inet6 = (eth.addr_info || []).find(a => a.family === "inet6");
                        root.ethernet = {
                            ifname: eth.ifname,
                            state: eth.operstate || "UNKNOWN",
                            connected: eth.operstate === "UP",
                            ip: inet ? inet.local : "",
                            prefix: inet ? inet.prefixlen : "",
                            ip6: inet6 ? inet6.local : "",
                            mac: eth.address || ""
                        };
                    } else {
                        root.ethernet = null;
                    }
                } catch (e) {
                    root.ethernet = null;
                }
            }
        }
    }

    Timer {
        id: ethTimer
        interval: 1500
        onTriggered: {
            ipReader.running = false;
            ipReader.running = true;
        }
    }

    function applyEthernetConfig(ifname, method, ip, prefix, gateway, dns) {
        const name = String(ifname || "");
        const address = String(ip || "");
        const gatewayValue = String(gateway || "");
        const dnsValue = String(dns || "");
        const prefixValue = String(prefix || "24");
        // Keep the fallback shell positional-only.  NetworkManager values can
        // originate from the UI and must never become shell source text.
        if (!/^[A-Za-z0-9_.:-]{1,64}$/.test(name)) return;
        if (!/^(?:[0-9]{1,3}\.){3}[0-9]{1,3}(?:\/[0-9]{1,2})?$|^[0-9A-Fa-f:]+(?:\/[0-9]{1,3})?$/.test(address)) return;
        if (!/^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$|^[0-9A-Fa-f:]+$/.test(gatewayValue) && gatewayValue !== "") return;
        if (!/^(?:[0-9]{1,3}\.){3}[0-9]{1,3}$|^[0-9A-Fa-f:]+$/.test(dnsValue) && dnsValue !== "") return;
        if (!/^([0-9]|[1-9][0-9]|1[01][0-9]|12[0-8])$/.test(prefixValue)) return;
        if (method === "auto") {
            Quickshell.execDetached(["sh", "-c",
                "nmcli connection modify \"$1\" ipv4.method auto ipv4.addresses '' ipv4.gateway '' ipv4.dns '' 2>/dev/null || true; nmcli connection up \"$1\" 2>/dev/null || true",
                "--", name]);
        } else {
            Quickshell.execDetached(["sh", "-c",
                "nmcli connection modify \"$1\" ipv4.method manual ipv4.addresses \"$2/$3\" ipv4.gateway \"$4\" ipv4.dns \"$5\" 2>/dev/null || { ip addr flush dev \"$1\"; ip addr add \"$2/$3\" dev \"$1\"; [ -n \"$4\" ] && ip route add default via \"$4\" dev \"$1\"; }; nmcli connection up \"$1\" 2>/dev/null || true",
                "--", name, address, prefixValue, gatewayValue, dnsValue]);
        }
        ethTimer.start();
    }

    // ── Bluetooth discovery & pairing ────────────────────────────────────────
    property bool scanning: false

    function startScan() {
        if (root.adapter) root.adapter.discovering = true;
        Quickshell.execDetached(["bluetoothctl", "scan", "on"]);
        root.scanning = true;
    }

    function stopScan() {
        if (root.adapter) root.adapter.discovering = false;
        Quickshell.execDetached(["bluetoothctl", "scan", "off"]);
        root.scanning = false;
    }

    function pairDevice(address) {
        root.setBusy(address, true);
        Quickshell.execDetached(["bluetoothctl", "pair", address]);
    }

    function trustDevice(address, trust) {
        Quickshell.execDetached(["bluetoothctl", trust ? "trust" : "untrust", address]);
    }

    function disconnectDevice(address) {
        const d = Bluetooth.devices.values.find(x => x.address === address);
        if (d) d.disconnect();
    }

    function forgetDevice(address) {
        const d = Bluetooth.devices.values.find(x => x.address === address);
        if (d) d.forget();
        Quickshell.execDetached(["bluetoothctl", "remove", address]);
    }

    function refresh() {
        root._rebuild();
        if (ipReader.running) ipReader.restart();
        if (savedReader.running) savedReader.restart();
    }

    // ── Live state → the shape the popup reads ───────────────────────────────

    function _wifiIcon(signal) {
        if (signal >= 80) return "\u{f0928}";
        if (signal >= 60) return "\u{f0925}";
        if (signal >= 40) return "\u{f0922}";
        if (signal >= 20) return "\u{f091f}";
        return "\u{f092f}";
    }

    function _btIcon(d) {
        const icon = (d.icon || "").toLowerCase();
        const name = (d.deviceName || d.name || "").toLowerCase();
        if (icon.includes("audio") || icon.includes("headset") || icon.includes("headphone") || name.includes("buds") || name.includes("airpods") || name.includes("headphone") || name.includes("speaker") || name.includes("sound"))
            return "\u{f057e}";
        if (icon.includes("input-keyboard") || name.includes("keyboard") || name.includes("keychron"))
            return "\u{f030c}";
        if (icon.includes("input-mouse") || name.includes("mouse") || name.includes("trackpad") || name.includes("logitech") || name.includes("touchpad"))
            return "\u{f087c}";
        if (icon.includes("phone") || name.includes("iphone") || name.includes("android") || name.includes("galaxy") || name.includes("pixel"))
            return "\u{f03dc}";
        if (icon.includes("gamepad") || name.includes("controller") || name.includes("xbox") || name.includes("ps4") || name.includes("ps5") || name.includes("dualshock") || name.includes("dualsense"))
            return "\u{f0022}";
        return "\u{f00af}";
    }

    function _net(n) {
        // signalStrength is 0..1, the same convention as the Bluetooth battery
        // below and as UPower's percentage. Passed straight through, it reached
        // the network list as "Signal 0.76%" and reached _wifiIcon(), whose
        // thresholds are 80/60/40/20, as a number that can never clear the
        // lowest of them — so every network on the panel, however strong, was
        // drawn with the no-signal glyph.
        const strength = Math.round(n.signalStrength * 100);
        // security is WifiSecurityType::Enum, a number. The panel printed it
        // raw: a WPA2 network read "Signal 76% • 3". The module ships the
        // spelling, so nothing here keeps a table of its own in step.
        return {
            id: n.name,
            ssid: n.name,
            name: n.name,
            signal: strength,
            security: WifiSecurityType.toString(n.security),
            connected: n.connected,
            known: n.known,
            icon: root._wifiIcon(strength)
        };
    }

    function _dev(d) {
        return {
            id: d.address,
            mac: d.address,
            name: d.deviceName || d.name || d.address,
            icon: root._btIcon(d),
            connected: d.connected,
            paired: d.paired,
            trusted: d.trusted || false,
            battery: d.batteryAvailable ? Math.round(d.battery * 100) : -1,
            type: "bluetooth"
        };
    }

    function _rebuild() {
        const dev = root.wifiDevice;
        const nets = dev ? dev.networks.values.map(root._net) : [];
        root.wifi = {
            power: Networking.wifiEnabled ? "on" : "off",
            connected: nets.find(n => n.connected) || null,
            networks: nets
        };
        root.wifiUpdated(root.wifi);

        const a = root.adapter;
        const devs = a ? Bluetooth.devices.values.map(root._dev) : [];
        root.bluetooth = {
            power: (a && a.enabled) ? "on" : "off",
            connected: devs.find(d => d.connected) || null,
            devices: devs
        };
        root.bluetoothUpdated(root.bluetooth);
    }

    // Property changes on the live objects do not re-run _rebuild by themselves,
    // so a slow tick sweeps them up. Nothing forks — this is a walk over objects
    // already in memory, unlike the 1-3s nmcli and bluetoothctl calls it replaces.
    Timer {
        interval: 2000
        repeat: true
        running: root._users > 0
        onTriggered: root._rebuild()
    }

    // Neither of these watches `devices`, and the pair used to. The property is
    // a constant pointer to a model whose *contents* change, so the pointer it
    // returns never does and the handler never ran — measured: with Bluetooth's
    // `ignoreUnknownSignals` taken off, both warned "no signal of the target
    // matches the name" the moment the service was first instantiated. The
    // Bluetooth block carried that flag, which is what kept its half quiet.
    // Content changes are what the two-second sweep above is for.
    Connections {
        target: Networking
        function onWifiEnabledChanged() { root._rebuild(); }
    }

    Connections {
        target: Bluetooth
        // The standalone settings window gets a compat Bluetooth without
        // this signal; the shell's real one has it.
        ignoreUnknownSignals: true
        function onDefaultAdapterChanged() { root._rebuild(); }
    }

    Component.onCompleted: root._rebuild()
}
