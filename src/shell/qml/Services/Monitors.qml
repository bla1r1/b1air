pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import B1air.Daemon

// =============================================================================
// Owner of display layout and external-monitor brightness.
//
// The state and the two scripts were locked inside MonitorPopup, which is why
// the settings window had a Displays page that could only render empty: the
// section wanted a model and nothing in the shell owned one. It does now, and
// the popup is gone.
//
// Reads sway's outputs (and follows its output events while in use), writes through tools/monitors.sh (which
// applies and remembers the layout) and controls/monitor-brightness.sh (DDC).
// =============================================================================

Singleton {
    id: root

    /** "" for anything wlroots could not actually read off the display. */
    function _named(v) {
        const t = String(v || "").trim();
        return t.toLowerCase() === "unknown" ? "" : t;
    }

    // {name, make, model, resW, resH, rate, sysScale, x, y, focused, active,
    //  modes: [{w, h, rate}]}
    property var outputs: []

    // {id, name, type, brightness} — external panels that answer DDC/CI.
    property var brightness: []

    readonly property bool hasBrightness: root.brightness.length > 0

    readonly property string scriptDir: (Quickshell.env("QS_SCRIPT_DIR")
        || (Quickshell.env("HOME") + "/.config/quickshell")).replace(/\/quickshell\/?$/, "")

    // ── Consumers ────────────────────────────────────────────────────────────
    // Only the settings page reads this, and only while it is open: probing DDC
    // spawns ddcutil, which is slow and wakes the panel's i2c bus.
    property int _users: 0
    function acquire() {
        root._users++;
        if (root._users === 1)
            root.refresh();
    }
    function release() { if (root._users > 0) root._users--; }

    // ── Reads ────────────────────────────────────────────────────────────────

    function refresh() {
        root.readOutputs();
        brightnessReader.running = true;
    }

    function readOutputs() {
        Sway.query("outputs", outs => root._parseOutputs(outs));
    }

    // Plugged in, unplugged, reconfigured: sway says so.
    Connections {
        target: Sway
        enabled: root._users > 0
        function onOutputEvent(e) { root.readOutputs(); }
    }

    Process {
        id: brightnessReader
        command: ["b1air-daemon", "ddc", "list"]
        stdout: StdioCollector {
            onStreamFinished: root._parseBrightness(this.text)
        }
    }


    function _parseOutputs(txt) {
        let data;
        try {
            data = Array.isArray(txt) ? txt : JSON.parse((txt || "").trim() || "[]");
        } catch (e) {
            console.warn("Monitors: cannot parse outputs —", e);
            return;
        }

        const list = data.map(o => {
            const rect = o.rect || { x: 0, y: 0, width: 0, height: 0 };
            const mode = o.current_mode || { width: rect.width, height: rect.height, refresh: 60000 };
            const modes = (o.modes || []).map(m => ({
                w: m.width,
                h: m.height,
                rate: Math.round((m.refresh || 60000) / 1000)
            }));
            return {
                name: o.name,

                // Sway reports the literal string "Unknown" for make, model and
                // serial on any output with no EDID to read — a headless
                // output, a virtual one, some KVMs. Callers only checked for an
                // empty string, so the Displays page introduced the selected
                // screen as "Unknown Unknown". Absent is absent.
                make: root._named(o.make),
                model: root._named(o.model),
                resW: mode.width,
                resH: mode.height,
                rate: Math.round((mode.refresh || 60000) / 1000),
                sysScale: o.scale !== undefined ? o.scale : 1.0,
                x: rect.x,
                y: rect.y,
                focused: !!o.focused,
                active: o.active !== false,
                transform: o.transform || "normal",
                modes: modes
            };
        });

        root.outputs = list;
    }

    function _parseBrightness(txt) {
        try {
            const data = JSON.parse((txt || "").trim() || "[]");
            root.brightness = data.map(d => ({
                id: d.id || "",
                name: d.name || "Display",
                type: d.type || "ddc",
                brightness: Math.max(1, Math.min(100, parseInt(d.brightness) || 50))
            }));
        } catch (e) {
            root.brightness = [];
        }
    }

    // ── Writes ───────────────────────────────────────────────────────────────

    /** layout: [{name, resW, resH, rate, sysScale, x, y, transform, active}] — the daemon normalises. */
    function apply(layout) {
        if (!layout || layout.length === 0)
            return;
        // Only a scale change needs the shell reloaded (below); a move or a
        // new mode does not, and reloading closed Settings under the pointer
        // after every screen dropped on the arrangement canvas.
        const scaleChanged = layout.some(l => {
            const o = root.outputs.find(x => x.name === l.name);
            return o && Math.abs((o.sysScale || 1) - (l.sysScale || 1)) > 0.001;
        });
        Daemon.monitorsApply(JSON.stringify(layout));
        applyRecheck.restart();
        if (!scaleChanged)
            return;
        // Design.uiScale follows Screen.devicePixelRatio, but nothing tells
        // TopBar's or a popup's own PanelWindow surface to renegotiate its
        // actual Wayland buffer size against the new scale — only a reload
        // does that, so a scale change left the bar clipped (rendered at the
        // new scale, but still sized for the old one) until the shell
        // happened to reload for some unrelated reason.
        reloadAfterScale.restart();
    }

    Timer {
        id: reloadAfterScale
        interval: 1200
        // Daemon.reload() also runs `swaymsg reload`, which re-reads sway's
        // config files from disk — since the scale we just applied at
        // runtime was never written to one, that snapped it straight back
        // to whatever the config says (1x). forceReload() only reloads the
        // shell's own QML, which is all that's actually needed here.
        onTriggered: Daemon.forceReload()
    }

    /**
     * Turn an output on or off, and remember it.
     *
     * This used to shell straight out to `swaymsg output NAME disable` and
     * stop there. The choice never reached the saved layout, and the daemon's
     * restore ignored the field anyway, so a display switched off in Settings
     * came back on at the next login — twice over. Going through apply() means
     * one path: sway gets the command, the layout gets written, and restore
     * reproduces it.
     */
    function setEnabled(name, enabled) {
        const layout = root.outputs.map(o => ({
            name: o.name, resW: o.resW, resH: o.resH, rate: o.rate,
            sysScale: o.sysScale, x: o.x, y: o.y, transform: o.transform,
            active: o.name === name ? enabled : o.active
        }));
        root.apply(layout);
    }

    function setTransform(name, rot) {
        Sway.command("output " + Sway.quote(name) + " transform " + Number(rot));
        applyRecheck.restart();
    }

    // Each screen shows its number (osd/IdentifyOverlay.qml). Asked of the
    // shell by command, since Settings may be its own process.
    function identify() {
        Quickshell.execDetached(["b1air-shell", "open", "identify"]);
    }

    Timer {
        id: applyRecheck
        interval: 1200
        onTriggered: root.readOutputs()
    }

    function setBrightness(id, pct) {
        const v = Math.max(1, Math.min(100, Math.round(pct)));
        // Optimistic: ddcutil takes the better part of a second to answer.
        root.brightness = root.brightness.map(d => d.id === id ? Object.assign({}, d, { brightness: v }) : d);
        Daemon.ddcSet(id, v);
    }

    function redetect() {
        redetector.running = true;
    }

    Process {
        id: redetector
        command: ["b1air-daemon", "ddc", "refresh"]
        stdout: StdioCollector {
            onStreamFinished: root._parseBrightness(this.text)
        }
    }
}
