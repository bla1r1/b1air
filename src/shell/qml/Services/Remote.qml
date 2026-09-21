pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import B1air.Daemon

// =============================================================================
// Remote desktop (WayVNC), as the bar and the Control Center see it.
//
// The Settings page had its own copy of this state, fetched once when the
// page opened, which is fine for a page and useless for a privacy indicator:
// someone connecting is exactly the moment nobody has Settings open. This
// asks the daemon over D-Bus every few seconds — one bus call, no process —
// and the daemon counts established connections on the server's port from
// /proc/net, so a viewer shows up here within one tick of connecting.
// =============================================================================

Singleton {
    id: root

    property bool available: false      // wayvnc is installed
    property bool running: false
    property int clients: 0
    property int port: 5900

    /** Emitted when starting failed — no password saved yet, most likely. */
    signal needsSetup()

    Timer {
        interval: 4000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: Daemon.requestRemoteStatus("remote-service")
    }

    Connections {
        target: Daemon
        function onRemoteStatusReady(tag, json) {
            if (tag !== "remote-service") return;
            try {
                const s = JSON.parse(String(json).trim());
                root.available = s.available === true;
                root.running = s.running === true;
                root.clients = s.clients || 0;
                root.port = s.port || 5900;
            } catch (e) {}
        }
    }

    // Soon after a start or stop, rather than waiting out the poll.
    Timer {
        id: recheck
        interval: 700
        onTriggered: Daemon.requestRemoteStatus("remote-service")
    }

    /** Stops the server, which drops every viewer with it. */
    function stop() {
        Quickshell.execDetached(["b1air-daemon", "remote", "stop"]);
        root.running = false;
        root.clients = 0;
        recheck.restart();
    }

    function start() { starter.running = true; }
    function toggle() { if (root.running) root.stop(); else root.start(); }

    // Started with the password already in the secret store; the daemon
    // refuses to start without one rather than run unauthenticated.
    Process {
        id: starter
        command: ["b1air-daemon", "remote", "start", String(root.port)]
        onExited: (code) => {
            if (code !== 0) root.needsSetup();
            recheck.restart();
        }
    }
}
