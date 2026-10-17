pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import B1air.Daemon

// =============================================================================
// Owner of the player state, on MPRIS directly.
//
// Was: `music_info.sh` once a second — playerctl, plus curling the album art
// and deriving colours from it, all re-done every tick whether or not anything
// had changed. 60 spawns a minute.
//
// Now: title, artist, art, status and position come from MPRIS as signals, and
// the script runs ONLY when the track changes. Roughly one spawn per song.
//
// Same split as the brightness work: the live values move to the native source,
// while the script keeps the part it is actually good at. Colour extraction
// from cover art is not something MPRIS exposes, and reimplementing it blind
// would be trading a working thing for an unverified one.
//
// Public shape unchanged — MusicPopup reads `Media.track.*`.
// =============================================================================

Singleton {
    id: root

    /** The shape MusicPopup consumes. Live fields from MPRIS, derived from the script. */
    property var track: ({})

    readonly property var player: Mpris.players.values.find(p => p.canControl) || null
    readonly property bool hasPlayer: root.player !== null

    readonly property string status: !root.player ? ""
        : (root.player.playbackState === MprisPlaybackState.Playing ? "Playing"
        : (root.player.playbackState === MprisPlaybackState.Paused ? "Paused" : "Stopped"))
    readonly property bool playing: root.status === "Playing"

    readonly property string _dir: Quickshell.env("HOME") + "/.config/quickshell/music"

    // ── Consumers ────────────────────────────────────────────────────────────

    property int _users: 0
    function acquire() { root._users++; }
    function release() { if (root._users > 0) root._users--; }

    // ── Transport ────────────────────────────────────────────────────────────
    // No optimistic flip any more: MPRIS reports the state change itself, and
    // faking it locally only mattered when the truth arrived a poll later.

    function playPause() { if (root.player) root.player.togglePlaying(); }
    function next()       { if (root.player) root.player.next(); }
    function previous()   { if (root.player) root.player.previous(); }

    function seek(seconds) {
        if (root.player && root.player.canSeek)
            root.player.position = Number(seconds);
    }

    function refresh() { infoProc.running = true; }

    // ── Live fields ──────────────────────────────────────────────────────────
    // Merged over whatever the daemon last derived, so colours survive while
    // title and position update at MPRIS speed.

    function _merge() {
        const p = root.player;
        root.track = Object.assign({}, root.track, {
            status: root.status,
            title: p ? p.trackTitle : "",
            artist: p ? p.trackArtist : "",
            album: p ? p.trackAlbum : "",
            artUrl: p ? p.trackArtUrl : "",
            playerName: p ? p.identity : "",
            percent: (p && p.length > 0) ? Math.round(p.position * 100 / p.length) : 0,
            positionStr: root._clock(p ? p.position : 0),
            lengthStr: root._clock(p ? p.length : 0)
        });
    }

    function _clock(sec) {
        if (!sec || sec < 0) return "0:00";
        const m = Math.floor(sec / 60);
        const s = Math.floor(sec % 60);
        return m + ":" + (s < 10 ? "0" : "") + s;
    }

    Connections {
        target: root.player
        ignoreUnknownSignals: true
        function onTrackTitleChanged() { root._merge(); root.refresh(); }
        function onTrackArtUrlChanged() { root._merge(); root.refresh(); }
        function onPlaybackStateChanged() { root._merge(); }
        function onPositionChanged() { root._merge(); }
    }

    onPlayerChanged: { root._merge(); root.refresh(); }

    // MPRIS players commonly do not emit position continuously; ask for it while
    // something is actually playing. This touches nothing outside the process.
    Timer {
        interval: 1000
        repeat: true
        running: root._users > 0 && root.playing
        onTriggered: {
            if (root.player)
                root.player.positionChanged();
            root._merge();
        }
    }

    // ── Derived fields ───────────────────────────────────────────────────────
    // Cover-art colours, output device name and icon. Runs on track change, not
    // on a clock.

    Process {
        id: infoProc
        command: ["b1air-daemon", "media-info"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = (this.text || "").trim();
                if (!out) return;
                try {
                    const d = JSON.parse(out);
                    // Keep only what MPRIS does not provide; the live fields
                    // above must win, or a slow script would stutter the UI.
                    root.track = Object.assign({}, root.track, {
                        textColor: d.textColor, grad: d.grad, blur: d.blur,
                        source: d.source, deviceName: d.deviceName,
                        deviceIcon: d.deviceIcon
                    });
                } catch (e) {}
            }
        }
    }

    Component.onCompleted: {
        root._merge();
    }
}
