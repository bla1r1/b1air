pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// =============================================================================
// Clipboard Service
//
// Monitors the Wayland clipboard (b1air-clip) and provides searchable history with
// pinning, formatting detection (text, url, hex color, code), and 1-click restore.
// Replaces external tools (copyq, cliphist, rofi_clipboard).
// =============================================================================

Singleton {
    id: root

    readonly property ListModel items: ListModel {}
    property string lastText: ""
    property string pendingSave: ""

    // 1. Initial load
    //
    // Nothing may be written back before this has finished. The clipboard
    // watcher reports the current selection the moment it connects, which is
    // sooner than a subprocess can read the store — so the first save of the
    // session went out with a one-entry list and replaced everything that was
    // there. Measured: a store holding ten entries came back holding one, the
    // clip that happened to be on the clipboard at login.
    property bool _loaded: false
    property bool _saveWanted: false

    function _applyStored(raw) {
        if (root._loaded)
            return;
        try {
            const list = JSON.parse((raw || "").trim() || "[]");
            if (Array.isArray(list)) {
                for (const entry of list) {
                    if (!entry || !entry.text)
                        continue;
                    // Anything captured while the read was in flight is newer
                    // than the stored copy and already at the top, so keep that
                    // one rather than listing the clip twice.
                    let dup = false;
                    for (let i = 0; i < root.items.count; i++) {
                        if (root.items.get(i).text === entry.text) {
                            dup = true;
                            break;
                        }
                    }
                    if (!dup)
                        root.items.append(entry);
                }
            }
        } catch (e) {
            console.log("Clipboard cache load error:", e);
        }
        root._loaded = true;
        if (root._saveWanted)
            root._save();
    }

    Process {
        id: loadProcess
        running: true
        command: ["b1air-secret-service", "get", "clipboard-history"]
        stdout: StdioCollector {
            onStreamFinished: root._applyStored(this.text)
        }
    }

    // If the store never answers — no daemon, a broken keyring — recording has
    // to start anyway, or the history is frozen for the whole session.
    Timer {
        id: loadGuard
        interval: 4000
        running: !root._loaded
        onTriggered: root._applyStored("")
    }

    // Writing the history back.
    //
    // `stdinEnabled = false` closes the pipe so the reader sees EOF, and it is
    // a property, not a one-shot: it stayed false for every later run, so the
    // second save onwards started the helper and handed it an empty stdin. The
    // store therefore froze at whatever the first save of the session held.
    // Measured with the debug build: seven saves, item counts 1..7, and a store
    // still holding the single record from save one. Re-open stdin each time.
    //
    // The write is debounced because a save follows every single change —
    // pinning, deleting, a burst of copies — and each one spawns a helper. A
    // quarter of a second collapses a burst into one write, and since the
    // payload is always the whole list, only the last write matters anyway.
    Process {
        id: saveProcess
        stdinEnabled: true
        command: ["b1air-secret-service", "set", "clipboard-history"]
        onStarted: {
            write(root.pendingSave);
            stdinEnabled = false;
        }
    }

    Timer {
        id: saveDebounce
        interval: 250
        onTriggered: {
            saveProcess.running = false;
            saveProcess.stdinEnabled = true;
            saveProcess.running = true;
        }
    }

    // 2. Clipboard monitor: a watcher, and a poll that covers for it
    //
    // `b1air-clip watch` prints every text put on the clipboard, each one
    // followed by U+001E, the ASCII record separator — the one thing that
    // cannot turn up inside pasted text, where a newline can. SplitParser
    // hands over a record at a time; a StdioCollector would wait for a stream
    // that never closes.
    //
    // It is text only and at most 256 KB of it, so a screenshot on the
    // clipboard is not pushed into the shell as megabytes of "text". And it
    // ends when its stdin closes — `stdinEnabled` makes that a pipe from the
    // shell — so a restarted shell does not leave watchers behind, which on
    // the old `wl-paste --watch` wrapper piled up until the compositor stopped
    // telling any of them about changes.
    Process {
        id: watcher
        running: true
        stdinEnabled: true
        command: ["b1air-clip", "watch", "--max", "262144"]
        stdout: SplitParser {
            splitMarker: "\u001e"
            onRead: data => {
                if (!data)
                    return;
                // The watcher has proved it works on this compositor, so the
                // reconcile poll can stand down.
                root._watchWorks = true;
                root._handleNewClip(data);
            }
        }
        onExited: {
            // A watcher that died has proved nothing any more.
            root._watchWorks = false;
            restartTimer.start();
        }
    }

    Timer {
        id: restartTimer
        interval: 3000
        onTriggered: watcher.running = true
    }

    /** Set once the watcher has actually delivered a clip on this machine. */
    property bool _watchWorks: false

    // Reads the clipboard on a timer and feeds anything new through the same
    // path as a watch event. It stops itself as soon as the watcher delivers
    // once, so on a compositor where the watch works this costs three polls at
    // startup and nothing afterwards; where it does not, the feature works.
    Timer {
        id: reconcile
        interval: 3000
        repeat: true
        running: !root._watchWorks
        onTriggered: {
            // Off then on. A Process that has already run does not start again
            // from `running = true` alone — it is already false, so the write
            // changes nothing and no signal is emitted. Measured: the poll
            // captured the clipboard once at startup and never again, six
            // copies later the store still held the first one.
            pollProc.running = false;
            pollProc.running = true;
        }
    }

    Process {
        id: pollProc
        command: ["b1air-clip", "paste", "--max", "262144"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (this.text)
                    root._handleNewClip(this.text);
            }
        }
    }

    function _detectType(text) {
        if (!text) return "text";
        const t = text.trim();
        if (/^https?:\/\/[^\s]+$/i.test(t)) return "link";
        if (/^#([0-9a-fA-F]{3}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/.test(t)) return "color";
        if (/^(\{|\}|\[|\]|function|class|const|let|var|def|import|export|if|for|while|select|curl|git|docker)/m.test(t) || t.includes("\n")) return "code";
        return "text";
    }

    function _handleNewClip(text) {
        if (!text || text.trim() === "" || text === root.lastText) return;
        root.lastText = text;

        const trimmed = text.trim();
        // Check if already exists in history
        for (let i = 0; i < root.items.count; i++) {
            const cur = root.items.get(i);
            if (cur.text === text) {
                // If it's already top, skip
                if (i === 0) return;
                // Move to top
                const pinned = cur.pinned;
                root.items.remove(i);
                root.items.insert(0, {
                    id: Date.now().toString(),
                    text: text,
                    preview: trimmed.slice(0, 200),
                    type: root._detectType(text),
                    time: new Date().toLocaleTimeString(Qt.locale(), "hh:mm"),
                    pinned: pinned
                });
                root._save();
                return;
            }
        }

        // Insert new clip at index 0
        root.items.insert(0, {
            id: Date.now().toString(),
            text: text,
            preview: trimmed.slice(0, 200),
            type: root._detectType(text),
            time: new Date().toLocaleTimeString(Qt.locale(), "hh:mm"),
            pinned: false
        });

        // Limit to 60 items
        while (root.items.count > 60) {
            let removed = false;
            for (let j = root.items.count - 1; j >= 0; j--) {
                if (!root.items.get(j).pinned) {
                    root.items.remove(j);
                    removed = true;
                    break;
                }
            }
            if (!removed) break;
        }

        root._save();
    }

    function copyToClipboard(text) {
        if (!text) return;
        root.lastText = text;
        // b1air-clip takes the text as its argument; "--" so a text starting
        // with "-" is not read as an option. (data-control, so no focus
        // needed — the shell's own surfaces rarely have it.)
        Quickshell.execDetached(["b1air-clip", "copy", "--", text]);
    }

    /**
     * Row identity, not row number.
     *
     * These two took the index of the row that was clicked, and the popup
     * hands out the index within the list it *displays* — which starts with
     * six built-in templates and is narrowed further whenever the search box
     * has anything in it. So the pin and delete buttons acted on a different
     * clip than the one they were drawn next to: pressing delete on the first
     * template removed the newest real entry, and with a search term active
     * the offset was whatever the filter happened to make it.
     */
    function _indexOfId(id) {
        for (let i = 0; i < root.items.count; i++) {
            if (root.items.get(i).id === id)
                return i;
        }
        return -1;
    }

    // Bumped when an entry changes in place. Views that sort or group the
    // entries read it: a binding over `items` follows count, not a field of
    // one element, so pinning saved the pin and the list did not move or
    // change colour until it was reopened.
    property int revision: 0

    function togglePin(id) {
        const index = root._indexOfId(id);
        if (index < 0)
            return;
        const item = root.items.get(index);
        item.pinned = !item.pinned;
        root.revision++;
        root._save();
    }

    function deleteItem(id) {
        const index = root._indexOfId(id);
        if (index < 0)
            return;
        root.items.remove(index);
        root._save();
    }

    function clearHistory() {
        // Keep pinned
        for (let i = root.items.count - 1; i >= 0; i--) {
            if (!root.items.get(i).pinned) {
                root.items.remove(i);
            }
        }
        root._save();
    }

    /** Bytes the string takes as UTF-8, as the store counts them. */
    function _utf8Length(str) {
        let n = 0;
        for (let i = 0; i < str.length; i++) {
            const c = str.charCodeAt(i);
            if (c < 0x80) n += 1;
            else if (c < 0x800) n += 2;
            else if (c >= 0xd800 && c <= 0xdbff) { n += 4; i++; }   // a surrogate pair
            else n += 3;
        }
        return n;
    }

    function _save() {
        if (!root._loaded) {
            root._saveWanted = true;
            return;
        }

        const all = [];
        for (let i = 0; i < root.items.count; i++) {
            const it = root.items.get(i);
            all.push({
                id: it.id,
                text: it.text,
                preview: it.preview,
                type: it.type,
                time: it.time,
                pinned: it.pinned
            });
        }

        // The store takes at most 1 MB a value (src/daemon/secret_store.cpp)
        // and refused anything over without a word: one large paste — a log,
        // a JSON dump — and no save went through again, so everything copied
        // since was gone at the next login. What fits is saved: pinned
        // clips first, then the newest; one that does not fit stays in the
        // list until logout and is skipped on disk.
        const budget = 900 * 1024;
        const order = all.map((e, i) => i).sort((a, b) => (all[b].pinned ? 1 : 0) - (all[a].pinned ? 1 : 0) || a - b);
        const keep = {};
        let used = 2;
        for (const i of order) {
            const size = root._utf8Length(JSON.stringify(all[i])) + 1;
            if (used + size > budget)
                continue;
            keep[i] = true;
            used += size;
        }
        const arr = all.filter((e, i) => keep[i]);
        root.pendingSave = JSON.stringify(arr);
        saveDebounce.restart();
    }
}
