pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// =============================================================================
// VPN connections — NetworkManager's (OpenVPN, WireGuard) and Tailscale — as
// the Control Center's VPN tile and Settings → Network see them.
//
// nmcli and tailscale, not a VPN client of our own: NetworkManager already
// keeps the connections, their secrets and the routes, and Tailscale has its
// own daemon. This reads both every few seconds and asks them to connect.
// =============================================================================

Singleton {
    id: root

    /** NetworkManager's VPN and WireGuard connections: [{ name, type, active }]. */
    property var connections: []
    /** "absent" (not installed), "stopped" (no daemon), "NeedsLogin", "Stopped", "Running", … */
    property string tailscaleState: "absent"

    readonly property bool hasTailscale: root.tailscaleState !== "absent"
    readonly property bool tailscaleUp: root.tailscaleState === "Running"
    readonly property bool available: root.connections.length > 0 || root.hasTailscale
    readonly property var activeNames: {
        const out = root.connections.filter(c => c.active).map(c => c.name);
        if (root.tailscaleUp) out.push("Tailscale");
        return out;
    }
    readonly property bool active: root.activeNames.length > 0

    /** The last one turned on here, to bring back up from the tile. */
    property string lastUsed: ""

    /** Emitted with nmcli's or tailscale's own words when something failed. */
    signal failed(string message)

    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: if (!reader.running) reader.running = true
    }
    Timer { id: recheck; interval: 800; onTriggered: if (!reader.running) reader.running = true }

    Process {
        id: reader
        // One process for both, a separator between them.
        command: ["sh", "-c",
            "nmcli -t -f NAME,TYPE,ACTIVE connection show 2>/dev/null; echo '--tailscale--'; "
            + "if ! command -v tailscale >/dev/null 2>&1; then echo absent; "
            + "else tailscale status --json 2>/dev/null | grep -o '\"BackendState\": *\"[A-Za-z]*\"' "
            + "| head -n1 | sed 's/.*\"\\([A-Za-z]*\\)\"$/\\1/' | grep . || echo stopped; fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = this.text.split("--tailscale--");
                const out = [];
                for (const line of (parts[0] || "").split("\n")) {
                    if (line === "") continue;
                    // nmcli -t escapes a colon inside a field as "\:".
                    const f = line.split(/(?<!\\):/).map(x => x.replace(/\\:/g, ":"));
                    if (f.length < 3) continue;
                    if (f[1] !== "vpn" && f[1] !== "wireguard") continue;
                    out.push({ name: f[0], type: f[1] === "vpn" ? "OpenVPN" : "WireGuard", active: f[2] === "yes" });
                }
                root.connections = out;
                root.tailscaleState = String(parts[1] || "absent").trim() || "absent";
            }
        }
    }

    function _run(argv) {
        runner.command = argv;
        runner.running = true;
    }
    Process {
        id: runner
        stderr: StdioCollector { id: runnerErr }
        onExited: code => {
            if (code !== 0)
                root.failed(String(runnerErr.text).trim().split("\n").pop() || "");
            recheck.restart();
        }
    }

    function up(name) {
        root.lastUsed = name;
        // Not signed in yet: `tailscale up` waits for a sign-in in a browser
        // and prints the link to it; open that link rather than wait.
        if (name === "Tailscale" && root.tailscaleState === "NeedsLogin")
            root._run(["sh", "-c", "tailscale up 2>&1 | grep -o -m1 'https://[^[:space:]]*' | xargs -r xdg-open"]);
        else if (name === "Tailscale") root._run(["tailscale", "up"]);
        else root._run(["nmcli", "connection", "up", "id", name]);
    }
    function down(name) {
        if (name === "Tailscale") root._run(["tailscale", "down"]);
        else root._run(["nmcli", "connection", "down", "id", name]);
    }

    /** The tile: everything off when something is on, else the last one used. */
    function toggle() {
        if (root.active) {
            for (const n of root.activeNames) root.down(n);
            return;
        }
        const names = root.connections.map(c => c.name);
        if (root.hasTailscale) names.push("Tailscale");
        const pick = names.indexOf(root.lastUsed) >= 0 ? root.lastUsed : names[0];
        if (pick) root.up(pick);
    }

    /** An .ovpn or WireGuard .conf, made into a NetworkManager connection. */
    function importFile(path) {
        const p = String(path).replace(/^file:\/\//, "");
        const type = /\.ovpn$/i.test(p) ? "openvpn" : "wireguard";
        root._run(["nmcli", "connection", "import", "type", type, "file", p]);
    }
}
