pragma Singleton

import QtQuick
import Quickshell
import B1air.Daemon
import Quickshell.Io
import Quickshell.Services.Pipewire

// =============================================================================
// Owner of the audio state, on PipeWire directly.
//
// Previously this used a separate script once a second; state is now queried
// directly through the native daemon bridge.
// `audio_control.sh` shelling out to pactl for every write. 60 process spawns a
// minute for state that PipeWire already pushes.
//
// Now: no processes at all. Node properties arrive as signals.
//
// The PUBLIC SHAPE IS UNCHANGED on purpose — VolumePopup and BatteryPopup are
// already written against it, and the interface is the seam that made swapping
// the implementation a one-file change. Volume stays 0..100 int here even
// though PipeWire works in 0..1, because that is what the popups speak.
//
// NOTE: PwObjectTracker is required. Quickshell does not bind node properties
// unless something is tracking the object — without it `audio.volume` reads
// once and never updates again. That is the single easiest thing to get wrong
// in this file.
// =============================================================================

Singleton {
    id: root

    readonly property ListModel outputs: ListModel {}
    readonly property ListModel inputs: ListModel {}
    readonly property ListModel apps: ListModel {}

    property var defaultSink: null
    property var defaultSource: null

    // A sound card the kernel knows of: a line like " 0 [PCH            ]:".
    readonly property bool hasAudioSys: /\d+ \[/.test(Sys.readFile("/proc/asound/cards"))
    readonly property bool hasAudio: root.hasAudioSys || root.defaultSink !== null || root.sinkNodes.length > 0

    // ── Consumers ────────────────────────────────────────────────────────────
    // No longer gates a poller — there is none. It scopes the object tracker,
    // which is not free: tracking every node in the graph all session would
    // cost for nothing while no audio UI is on screen.

    property int _users: 0
    function acquire() { root._users++; }
    function release() { if (root._users > 0) root._users--; }

    readonly property bool _tracking: root._users > 0

    // ── The graph ────────────────────────────────────────────────────────────

    readonly property var sinkNodes: Pipewire.nodes.values.filter(n => n.isSink && !n.isStream)
    readonly property var sourceNodes: Pipewire.nodes.values.filter(n => !n.isSink && !n.isStream && n.audio)
    readonly property var streamNodes: Pipewire.nodes.values.filter(n => n.isStream)

    // ── Device connect chime ─────────────────────────────────────────────────
    //
    // A headset, a USB audio interface, a dock or a Bluetooth audio device
    // appears here as a new PipeWire sink or source, which is the only place
    // in the shell where "a peripheral just connected" is actually observable.
    // Sound settings has offered a toggle for it since the page was written
    // and nothing read the setting.
    //
    // Nodes are already being watched for the volume UI, so this costs a list
    // comparison per change and a process only when something is plugged in.
    property var _knownNodeIds: []
    property bool _chimeArmed: false

    // Everything present at login arrives as a burst of new nodes. Without a
    // pause the shell would chime at itself on every start.
    Timer {
        interval: 5000
        running: true
        onTriggered: root._chimeArmed = true
    }

    function _noteNodes() {
        const now = root.sinkNodes.concat(root.sourceNodes).map(n => String(n.id));
        const before = root._knownNodeIds;
        root._knownNodeIds = now;

        if (!root._chimeArmed)
            return;
        for (const id of now) {
            if (before.indexOf(id) < 0) {
                SoundEffects.playDeviceConnected();
                return;
            }
        }
    }

    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource].filter(Boolean).concat(
            root._tracking ? root.sinkNodes.concat(root.sourceNodes, root.streamNodes) : []
        )
    }

    readonly property var rawSink: Pipewire.defaultAudioSink
    readonly property var rawSource: Pipewire.defaultAudioSource

    readonly property real volume: (rawSink && rawSink.audio) ? rawSink.audio.volume : 0.0
    readonly property int volumePercent: Math.round(root.volume * 100)
    readonly property bool muted: (rawSink && rawSink.audio) ? rawSink.audio.muted : false

    onVolumeChanged: root._rebuild()
    onMutedChanged: root._rebuild()

    // ── Writes ───────────────────────────────────────────────────────────────
    // `type` is still "sink" | "source" | "sink-input" so callers do not change.

    function _node(id) {
        return Pipewire.nodes.values.find(n => String(n.id) === String(id)) || null;
    }

    function setMasterVolume(pct) {
        if (root.rawSink && root.rawSink.audio) {
            if (pct > 0 && root.rawSink.audio.muted)
                root.rawSink.audio.muted = false;
            root.rawSink.audio.volume = Math.max(0, Math.min(150, pct)) / 100;
        } else {
            Quickshell.execDetached(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", (pct / 100).toFixed(2)]);
        }
    }

    function toggleMasterMute() {
        if (root.rawSink && root.rawSink.audio) {
            root.rawSink.audio.muted = !root.rawSink.audio.muted;
        } else {
            Quickshell.execDetached(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]);
        }
    }

    function setVolume(type, id, pct) {
        const n = root._node(id);
        if (n && n.audio)
            n.audio.volume = Math.max(0, Math.min(100, pct)) / 100;
    }

    function toggleMute(type, id) {
        const n = root._node(id);
        if (n && n.audio)
            n.audio.muted = !n.audio.muted;
    }

    readonly property bool masterMute: root.muted

    function setDefault(type, name) {
        // Choosing a default is wirePlumber policy, not a node property, and
        // PipeWire has no call for it — this is the one write that still shells
        // out. It happens on a click, never in a loop.
        Quickshell.execDetached(["wpctl", "set-default", String(name)]);
    }

    function testAudio(sinkId) {
        const n = root._node(sinkId);
        const target = n ? n.name : "@DEFAULT_AUDIO_SINK@";
        // PipeWire node names are external data. Never interpolate them into
        // a shell command; accept only the syntax supported by the tools.
        if (!/^[A-Za-z0-9_.:@-]+$/.test(target)) return;
        Quickshell.execDetached(["paplay", "--device=" + target, "/usr/share/sounds/freedesktop/stereo/bell.oga"]);
    }

    function isDeviceDisabled(name) {
        const list = Settings.disabledAudioDevices || [];
        return list.includes(name);
    }

    function toggleDeviceDisabled(name) {
        const list = (Settings.disabledAudioDevices || []).slice();
        const idx = list.indexOf(name);
        if (idx >= 0) list.splice(idx, 1);
        else list.push(name);
        Settings.set("disabledAudioDevices", list);
        root._rebuild();
    }

    // Raising a muted device should unmute it, or the slider moves and nothing
    // is heard. Both popups had this rule; it lives here once.
    function applyVolume(type, device, pct) {
        if (!device || device.id === undefined)
            return;
        const n = root._node(device.id);
        if (!n || !n.audio)
            return;
        if (pct > 0 && n.audio.muted)
            n.audio.muted = false;
        n.audio.volume = Math.max(0, Math.min(100, pct)) / 100;
    }

    /** Kept for source compatibility. Nothing polls, so there is nothing to ask. */
    function refresh() {}

    // ── Drag protection ──────────────────────────────────────────────────────
    // Still needed: PipeWire reports the value it actually applied, which can
    // trail a fast drag by a frame or two and would fight the pointer.

    property var _held: ({})

    function hold(id, holding) {
        let h = Object.assign({}, root._held);
        if (holding) h[String(id)] = true;
        else delete h[String(id)];
        root._held = h;
    }

    function isHeld(id) { return root._held[String(id)] === true; }

    // ── Graph → the shape the popups read ────────────────────────────────────

    function _row(n, isDefault) {
        return {
            id: String(n.id),
            name: n.name || "",
            description: n.nickname || n.description || n.name || "",
            volume: isDefault ? root.volumePercent : (n.audio ? Math.round(n.audio.volume * 100) : 0),
            mute: isDefault ? root.muted : (n.audio ? n.audio.muted : false),
            is_default: !!isDefault,
            disabled: root.isDeviceDisabled(n.name || ""),
            icon: n.isSink ? "\u{f057e}" : "\u{f036c}"
        };
    }

    function _sync(model, nodes, defaultNode) {
        const rows = nodes.map(n => root._row(n, defaultNode && n.id === defaultNode.id));

        for (let i = model.count - 1; i >= 0; i--) {
            if (!rows.some(r => r.id === model.get(i).id))
                model.remove(i);
        }

        for (let i = 0; i < rows.length; i++) {
            const d = rows[i];
            let at = -1;
            for (let j = i; j < model.count; j++) {
                if (model.get(j).id === d.id) { at = j; break; }
            }
            if (at === -1) {
                model.insert(i, d);
                continue;
            }
            if (at !== i)
                model.move(at, i, 1);
            for (const key in d) {
                if (key === "volume" && root.isHeld(d.id))
                    continue;
                if (model.get(i)[key] !== d[key])
                    model.setProperty(i, key, d[key]);
            }
        }
    }

    function _rebuild() {
        const sink = Pipewire.defaultAudioSink;
        const source = Pipewire.defaultAudioSource;

        root._sync(root.outputs, root.sinkNodes, sink);
        root._sync(root.inputs, root.sourceNodes, source);
        root._sync(root.apps, root.streamNodes, null);

        root.defaultSink = sink ? root._row(sink, true) : null;
        root.defaultSource = source ? root._row(source, true) : null;
    }

    // Rebuild whenever the graph or the tracked values move. Cheap: it is a
    // diff against ListModels that mostly do not change.
    onSinkNodesChanged: { root._rebuild(); root._noteNodes(); }
    onSourceNodesChanged: { root._rebuild(); root._noteNodes(); }
    onStreamNodesChanged: root._rebuild()

    Connections {
        target: Pipewire
        function onDefaultAudioSinkChanged() { root._rebuild(); }
        function onDefaultAudioSourceChanged() { root._rebuild(); }
    }

    // Node volume changes do not re-emit the list bindings above, so poke the
    // rebuild on a slow tick as a floor. 2s, not 1s, and it touches nothing
    // outside this process — no fork, no parse.
    Timer {
        interval: 2000
        repeat: true
        running: root._tracking
        onTriggered: root._rebuild()
    }

    Component.onCompleted: root._rebuild()
}
