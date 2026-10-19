pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../Ui"

// =============================================================================
// Lyrics for what is playing (Services/Media), in time with it, for the
// player (music/MusicPopup).
//
// Looked for, in order:
//   1. a .lrc file beside a local track (song.flac → song.lrc), as players
//      and taggers leave them;
//   2. a copy kept from an earlier lookup (~/.cache/b1air/lyrics);
//   3. LRCLIB (lrclib.net), an open database of synced lyrics — only with
//      Settings.lyricsOnline, as it tells a server what is playing. Off
//      until asked for, from the player itself.
//
// Synced lyrics are LRC: "[01:02.50]a line", several times on one line for a
// chorus, an [offset:ms] tag to shift all of them. A track with only plain
// text has its lines, unsynced (`synced` false).
//
// Looked up only while someone is reading them (acquire/release), and once
// per track.
// =============================================================================

Singleton {
    id: root

    property int _users: 0
    function acquire() { root._users++; root._lookUp(); }
    function release() { if (root._users > 0) root._users--; }
    readonly property bool wanted: root._users > 0

    readonly property var player: Media.player
    readonly property string title: root.player ? (root.player.trackTitle || "") : ""
    readonly property string artist: root.player ? (root.player.trackArtist || "") : ""
    readonly property string album: root.player ? (root.player.trackAlbum || "") : ""
    readonly property real length: root.player ? root.player.length : 0
    readonly property string trackUrl: root.player && root.player.metadata
        ? String(root.player.metadata["xesam:url"] || "") : ""
    readonly property string key: root.artist + "\n" + root.title

    // [{ t: seconds (-1 unsynced), text }]
    property var lines: []
    property bool synced: false
    // "" nothing asked yet, "loading", "found", "none" (looked, found none),
    // "ask" (none here, and looking online is off).
    property string state: ""
    property string from: ""          // "file", "cache", "lrclib"
    property string _loadedKey: ""

    // Where the track is, read while lyrics are on screen: Quickshell works
    // out a player's position from its rate when asked, so a 1/5 s tick
    // keeps the line in step without the player sending anything.
    property real position: 0
    Timer {
        interval: 200
        repeat: true
        running: root.wanted && root.synced && Media.playing
        onTriggered: root.position = root.player ? root.player.position : 0
    }
    Connections {
        target: root.player
        ignoreUnknownSignals: true
        function onPositionChanged() { root.position = root.player.position; }
    }
    // The line being sung: the last that has started (a fifth of a second
    // early, as a reader's eye runs ahead).
    readonly property int current: {
        if (!root.synced) return -1;
        let i = -1;
        for (let k = 0; k < root.lines.length; k++) {
            if (root.lines[k].t <= root.position + 0.2) i = k;
            else break;
        }
        return i;
    }

    onKeyChanged: root._lookUp()
    onWantedChanged: root._lookUp()
    Connections {
        target: Settings
        function onLyricsOnlineChanged() { if (root.state === "ask") { root._loadedKey = ""; root._lookUp(); } }
    }

    // ── Parsing ──────────────────────────────────────────────────────────────

    function parse(text) {
        const out = [];
        let offset = 0;
        let anyTime = false;
        const plain = [];
        for (const raw of String(text || "").split(/\r?\n/)) {
            const off = raw.match(/^\[offset:\s*([+-]?\d+)\s*\]/i);
            if (off) { offset = Number(off[1]) / 1000; continue; }
            const tags = [];
            let rest = raw;
            let m;
            while ((m = rest.match(/^\[(\d+):(\d+(?:[.:]\d+)?)\]/))) {
                tags.push(Number(m[1]) * 60 + Number(m[2].replace(":", ".")));
                rest = rest.slice(m[0].length);
            }
            // [ar:…], [ti:…] and the like: about the file, not lines.
            if (tags.length === 0 && /^\[[a-z]+:.*\]$/i.test(raw.trim())) continue;
            const line = rest.replace(/<\d+:\d+(?:\.\d+)?>/g, "").trim();
            if (tags.length > 0) {
                anyTime = true;
                for (const t of tags) out.push({ t: Math.max(0, t - offset), text: line });
            } else if (line !== "" || plain.length > 0) {
                plain.push({ t: -1, text: line });
            }
        }
        if (anyTime) {
            out.sort((a, b) => a.t - b.t);
            return { lines: out, synced: true };
        }
        while (plain.length > 0 && plain[plain.length - 1].text === "") plain.pop();
        return { lines: plain, synced: false };
    }

    function _found(text, from) {
        const p = root.parse(text);
        if (p.lines.length === 0) return false;
        root.lines = p.lines;
        root.synced = p.synced;
        root.from = from;
        root.state = "found";
        root.position = root.player ? root.player.position : 0;
        return true;
    }

    // ── Looking ──────────────────────────────────────────────────────────────

    readonly property string cacheDir: (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache"))
                                       + "/b1air/lyrics"
    readonly property string cacheFile: root.cacheDir + "/" + Qt.md5(root.key) + ".lrc"
    readonly property string besideFile: {
        const u = root.trackUrl;
        if (!u.startsWith("file://")) return "";
        const path = decodeURIComponent(u.slice(7));
        const dot = path.lastIndexOf(".");
        return (dot > path.lastIndexOf("/") ? path.slice(0, dot) : path) + ".lrc";
    }

    function _lookUp() {
        if (!root.wanted || root.title === "" || root._loadedKey === root.key) return;
        root._loadedKey = root.key;
        root.lines = [];
        root.synced = false;
        root.from = "";
        root.state = "loading";
        // Beside the track, then the cache: one `cat` each, the first that
        // has something wins.
        reader.candidates = [[root.besideFile, "file"], [root.cacheFile, "cache"]].filter(c => c[0] !== "");
        reader.next();
    }

    Process {
        id: reader
        property var candidates: []
        property string from: ""
        property string forKey: ""
        function next() {
            if (reader.candidates.length === 0) { root._online(); return; }
            const c = reader.candidates[0];
            reader.candidates = reader.candidates.slice(1);
            reader.from = c[1];
            reader.forKey = root.key;
            reader.command = ["cat", c[0]];
            reader.running = true;
        }
        stdout: StdioCollector {
            onStreamFinished: {
                if (reader.forKey !== root.key) return;
                if (!root._found(this.text, reader.from)) reader.next();
            }
        }
    }

    function _online() {
        if (Settings.lyricsOnline !== true) { root.state = "ask"; return; }
        const forKey = root.key;
        const q = "artist_name=" + encodeURIComponent(root.artist)
                + "&track_name=" + encodeURIComponent(root.title)
                + (root.album ? "&album_name=" + encodeURIComponent(root.album) : "")
                + (root.length > 0 ? "&duration=" + Math.round(root.length) : "");
        root._get("https://lrclib.net/api/get?" + q, (status, body) => {
            if (forKey !== root.key) return;
            if (status === 200 && root._fromLrclib(body)) return;
            // Not that exact track (another album, a second off): the best
            // of a search.
            root._get("https://lrclib.net/api/search?track_name=" + encodeURIComponent(root.title)
                      + "&artist_name=" + encodeURIComponent(root.artist), (s2, b2) => {
                if (forKey !== root.key) return;
                let best = null;
                try {
                    const list = JSON.parse(b2);
                    best = list.find(x => x.syncedLyrics) || list.find(x => x.plainLyrics) || null;
                } catch (e) {}
                if (!(s2 === 200 && best && root._fromLrclib(JSON.stringify(best))))
                    root.state = "none";
            });
        });
    }
    function _fromLrclib(body) {
        let d = null;
        try { d = JSON.parse(body); } catch (e) { return false; }
        const text = d && (d.syncedLyrics || d.plainLyrics);
        if (!text || !root._found(text, "lrclib")) return false;
        // Kept, so the track is not asked for again.
        writer.text = text;
        writer.command = ["sh", "-c", 'mkdir -p "$1" && cat > "$2"', "sh", root.cacheDir, root.cacheFile];
        writer.running = true;
        return true;
    }
    function _get(url, done) {
        const x = new XMLHttpRequest();
        x.onreadystatechange = () => { if (x.readyState === XMLHttpRequest.DONE) done(x.status, x.responseText); };
        x.open("GET", url);
        // LRCLIB asks clients to say who they are.
        x.setRequestHeader("Lrclib-Client", "b1air (https://github.com/bla1r1/b1air)");
        x.send();
    }
    Process {
        id: writer
        property string text: ""
        stdinEnabled: true
        onStarted: { write(writer.text); stdinEnabled = false; }
        onExited: stdinEnabled = true
    }

    // The player's "look online" button.
    function allowOnline() { Settings.set("lyricsOnline", true); }
}
