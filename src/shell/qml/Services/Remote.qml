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

    // RustDesk beside our VNC: installed, its service on (it starts a
    // server in every session), a server running here, someone connected.
    property bool rustdeskInstalled: false
    property bool rustdeskService: false
    // A system service to turn on (the package ships one; Flatpak does not).
    property bool rustdeskServiceAvailable: false
    property bool rustdesk: false
    property bool rustdeskSession: false
    // The virtual screen standing in for a missing one (daemon
    // remote_display), or "".
    property string virtualOutput: ""

    // Anyone looking from afar, by either.
    readonly property int viewers: root.clients + (root.rustdeskSession ? 1 : 0)

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
                root.rustdeskInstalled = s.rustdeskInstalled === true;
                root.rustdeskService = s.rustdeskService === true;
                root.rustdeskServiceAvailable = s.rustdeskServiceAvailable === true;
                root.rustdesk = s.rustdesk === true;
                root.rustdeskSession = s.rustdeskSession === true;
                root.virtualOutput = s.virtualOutput || "";
            } catch (e) {}
        }
    }

    // Soon after a start or stop, rather than waiting out the poll.
    Timer {
        id: recheck
        interval: 700
        onTriggered: Daemon.requestRemoteStatus("remote-service")
    }
    // After the password dialog has been answered, which takes a while.
    Timer {
        id: serviceRecheck
        interval: 2500
        repeat: true
        property int left: 8
        onRunningChanged: if (running) left = 8
        onTriggered: {
            Daemon.requestRemoteStatus("remote-service");
            if (--left <= 0) stop();
        }
    }

    /** Stops the server, which drops every viewer with it. */
    function stop() {
        Quickshell.execDetached(["b1air-daemon", "remote", "stop"]);
        root.running = false;
        root.clients = 0;
        recheck.restart();
    }

    function start() { starter.running = true; }

    /** Ends the RustDesk session going on now (its viewer is let go). */
    // Not cleared here: the indicator stays until the daemon says nobody is
    // connected — it is a privacy light, and must not go out early.
    function stopRustdesk() {
        Quickshell.execDetached(["b1air-daemon", "remote", "rustdesk-disconnect"]);
        recheck.restart();
    }
    /** RustDesk's service on or off for good: asks for the password. */
    function setRustdeskService(on) {
        Quickshell.execDetached(["b1air-daemon", "remote", "rustdesk", on ? "on" : "off"]);
        serviceRecheck.restart();
    }
    function openRustdesk() { Quickshell.execDetached(["b1air-daemon", "remote", "rustdesk-open"]); }

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
