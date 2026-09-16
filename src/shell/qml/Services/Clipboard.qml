pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// =============================================================================
// Clipboard Service
//
// Monitors Wayland clipboard (wl-paste) and provides searchable history with
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
    // `wl-paste --watch` runs its command on every clipboard change and keeps
    // running. StdioCollector hands over its text when the stream *closes*, and
    // this stream never closes — so nothing was ever collected. Measured: copy
    // twice, open the popup, and the six seeded templates are still all there
    // is. SplitParser delivers a record at a time instead. The watched command
    // marks the end of each one with U+001E, the ASCII record separator, which
    // is the one thing that cannot turn up inside pasted text — a newline can,
    // so the default marker would cut multi-line clips into pieces.
    //
    // The watcher alone is not enough. Measured on sway 1.12 with wl-clipboard
    // 2.3.0: one-shot `wl-paste` returns the current clipboard correctly, while
    // `wl-paste --watch` fires for nothing at all — three copies, zero events,
    // no error on stderr. A clipboard manager that silently records nothing is
    // worse than none, so the watcher is the fast path and `reconcile` below is
    // the guarantee.
    // `stdinEnabled` is not there to write anything: it is what makes stdin a
    // pipe, so `cat` blocks until the shell process goes away and the wrapper
    // can then kill the watcher. Without it the watcher outlived the shell —
    // reparented to init and still subscribed to the clipboard — so every
    // restart of the shell left another one behind. Measured: six orphaned
    // `wl-paste --watch` processes after an afternoon of restarts, and with
    // that many subscribers the compositor stopped delivering change events to
    // any of them, which is a clipboard history that silently stops recording.
    Process {
        id: watcher
        running: true
        stdinEnabled: true
        //
        // Text only, and at most 256 KB of it. A bare `wl-paste` hands over
        // whatever type comes first, and with an image on the clipboard —
        // every screenshot is copied there by default — that was megabytes of
        // PNG bytes pushed into the shell as "text" and kept in the history.
        // Measured: a 4K screenshot jammed three readers on 14 MB each.
        //
        // The trap ends the watcher however this wrapper ends. `kill $w` after
        // `cat` only ran when stdin closed; a SIGTERM (the Process being
        // stopped or restarted) killed bash first, and the watcher lived on,
        // reparented to init — three of them on the test session, each reading
        // every copy. `wait` is interruptible, so the trap runs at once.
        command: ["bash", "-c",
                  "trap 'kill $w $c 2>/dev/null' EXIT; trap 'exit 0' TERM INT HUP; " +
                  "wl-paste --watch sh -c 'wl-paste --type text --no-newline 2>/dev/null | head -c 262144; printf \"\\036\"' & w=$!; " +
                  "cat <&0 >/dev/null 2>&1 & c=$!; wait $c"]
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
        command: ["sh", "-c", "wl-paste --type text --no-newline 2>/dev/null | head -c 262144"]
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
        Quickshell.execDetached(["bash", "-c", "printf '%s' \"$1\" | wl-copy", "--", text]);
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

    function togglePin(id) {
        const index = root._indexOfId(id);
        if (index < 0)
            return;
        const item = root.items.get(index);
        item.pinned = !item.pinned;
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

    function _save() {
        if (!root._loaded) {
            root._saveWanted = true;
            return;
        }

        const arr = [];
        for (let i = 0; i < root.items.count; i++) {
            const it = root.items.get(i);
            arr.push({
                id: it.id,
                text: it.text,
                preview: it.preview,
                type: it.type,
                time: it.time,
                pinned: it.pinned
            });
        }
        root.pendingSave = JSON.stringify(arr);
        saveDebounce.restart();
    }
}
