import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../Ui"
import "../../Services"
import "../../Services" as Services

// =============================================================================
// Default Applications
//
// The choice is recorded with xdg-mime and read back from it; xdg-mime is the
// one store here that anything else consults. Mod+T, Mod+E and Mod+F go
// through `b1air-daemon open-default`, which asks xdg-mime too, so picking a
// terminal on this page is what the terminal key opens.
//
// What this page was before, and why each part changed:
//
//   - Five copies of the same card, about a hundred lines each. They are one
//     component over a table now.
//   - It saved the choice to five settings keys (defaultBrowser and so on)
//     that nothing ever read. Those are gone from the schema.
//   - The highlighted pill was decided by a substring match between the
//     detected "firefox.desktop" and the Exec line "/usr/lib/firefox/firefox
//     %u", which never matched in either direction — nothing was ever shown
//     as the current choice, including the one just clicked, as soon as the
//     page had read the system's answer.
//   - The custom field turned whatever was typed into "<text>.desktop" and
//     registered it, whether or not such an entry existed. A typo made every
//     link open in nothing. It now has to name an installed application.
//   - The player row set "video/mkv", which is not a MIME type; Matroska is
//     video/x-matroska.
// =============================================================================

ColumnLayout {
    id: section

    Layout.fillWidth: true
    spacing: Design.s(Design.space.lg)

    // kind -> desktop id xdg-mime reports for the row's first MIME type.
    property var current: ({})
    // kind -> a line of feedback under the custom field.
    property var notes: ({})

    // The binary-name lists are what decides which installed apps are offered
    // in a row; matching the whole Exec line offered qrencode as a code editor.
    readonly property var rows: [
        { kind: "browser", title: "Web Browser", subtitle: "Links, web pages and Mod+F",
          icon: "\u{f0ac}", tone: Design.sapphire,
          mimes: ["x-scheme-handler/https", "x-scheme-handler/http", "text/html"],
          names: ["firefox", "chrome", "google-chrome", "google-chrome-stable", "chromium", "brave",
                  "brave-browser", "zen", "zen-browser", "vivaldi", "librewolf", "floorp",
                  "qutebrowser", "epiphany"],
          missing: "No web browser found. Install one with: sudo pacman -S firefox" },
        { kind: "terminal", title: "Terminal", subtitle: "What Mod+T opens",
          icon: "\u{f120}", tone: Design.green,
          mimes: ["x-scheme-handler/terminal"],
          names: ["b1air-term", "foot", "alacritty", "ghostty", "wezterm", "konsole", "xterm",
                  "kitty", "gnome-terminal"],
          missing: "No terminal found. b1air-term is built with the rest of the desktop." },
        { kind: "files", title: "File Manager", subtitle: "Folders, and what Mod+E opens",
          icon: "\u{f07c}", tone: Design.peach,
          mimes: ["inode/directory"],
          names: ["b1air-files", "thunar", "nautilus", "dolphin", "nemo", "pcmanfm", "pcmanfm-qt"],
          missing: "No file manager found. Install one with: sudo pacman -S thunar" },
        { kind: "editor", title: "Text Editor", subtitle: "Plain text, Markdown and JSON files",
          icon: "\u{f121}", tone: Design.mauve,
          mimes: ["text/plain", "text/markdown", "application/json"],
          names: ["b1air-text", "code", "codium", "vscodium", "cursor", "gvim", "zed", "kate",
                  "gedit", "gnome-text-editor", "subl", "sublime_text"],
          missing: "No graphical text editor found." },
        { kind: "player", title: "Media Player", subtitle: "Video and audio files",
          icon: "\u{f008}", tone: Design.teal,
          mimes: ["video/mp4", "video/x-matroska", "video/webm", "audio/mpeg", "audio/flac"],
          names: ["mpv", "vlc", "celluloid", "audacious", "totem", "haruna"],
          missing: "No media player found. Install one with: sudo pacman -S mpv" }
    ]

    /** The command's binary name: "/usr/bin/foo --bar %U" -> "foo". */
    function execBinary(exec) {
        const first = String(exec || "").trim().split(/\s+/)[0] || "";
        return first.split("/").pop().toLowerCase();
    }

    function candidates(row) {
        const out = [];
        for (const app of Services.Apps.list) {
            if (row.names.indexOf(section.execBinary(app.exec)) >= 0)
                out.push(app);
        }
        // Whatever is set right now is offered even when it is not in the
        // list above, so the current choice always has a pill to light up.
        const cur = section.current[row.kind] || "";
        if (cur && !out.some(a => a.desktopFile === cur)) {
            const app = Services.Apps.list.find(a => a.desktopFile === cur);
            if (app) out.push(app);
        }
        return out;
    }

    function choose(row, desktopId) {
        Quickshell.execDetached(["xdg-mime", "default", desktopId].concat(row.mimes));
        const cur = Object.assign({}, section.current);
        cur[row.kind] = desktopId;
        section.current = cur;
        section.note(row.kind, "");
    }

    /** A name typed into the custom field: the binary or the desktop id. */
    function chooseTyped(row, text) {
        const want = String(text || "").trim().toLowerCase().replace(/\.desktop$/, "");
        if (want === "")
            return false;
        const app = Services.Apps.list.find(a =>
            section.execBinary(a.exec) === want
            || String(a.desktopFile).toLowerCase().replace(/\.desktop$/, "") === want);
        if (!app) {
            section.note(row.kind, "Nothing installed goes by “" + text.trim()
                + "”. It needs a desktop entry to be a default.");
            return false;
        }
        section.choose(row, app.desktopFile);
        section.note(row.kind, "Set to " + app.name + ".");
        return true;
    }

    function note(kind, text) {
        const n = Object.assign({}, section.notes);
        n[kind] = text;
        section.notes = n;
    }

    // Every time the page is shown, not once: the section is built when the
    // shell starts and kept, so a default changed anywhere else afterwards
    // (a browser's own "make default" button, xdg-mime) never showed here.
    onVisibleChanged: if (visible) { detector.running = false; detector.running = true; }

    Process {
        id: detector
        running: true
        command: ["bash", "-c", "for m in \"$@\"; do printf '%s\\n' \"$(xdg-mime query default \"$m\" 2>/dev/null)\"; done",
                  "--"].concat(section.rows.map(r => r.mimes[0]))
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.split("\n");
                const cur = {};
                section.rows.forEach((r, i) => cur[r.kind] = (lines[i] || "").trim());
                section.current = cur;
            }
        }
    }

    Repeater {
        model: section.rows

        Card {
            id: rowCard
            required property var modelData
            readonly property var apps: {
                // Re-evaluated when the scan or the current choice changes.
                Services.Apps.list;
                section.current;
                return section.candidates(rowCard.modelData);
            }

            Layout.fillWidth: true
            title: rowCard.modelData.title
            subtitle: rowCard.modelData.subtitle
            icon: rowCard.modelData.icon
            accentColor: rowCard.modelData.tone

            Label {
                visible: rowCard.apps.length === 0
                Layout.fillWidth: true
                text: rowCard.modelData.missing
                role: "caption"
                dim: true
                wrapMode: Text.WordWrap
            }

            // A Flow rather than a row: four browsers side by side ran off the
            // edge of the card below about 1600px.
            Flow {
                visible: rowCard.apps.length > 0
                Layout.fillWidth: true
                spacing: Design.s(Design.space.xs)

                Repeater {
                    model: rowCard.apps
                    delegate: Pill {
                        required property var modelData
                        label: modelData.name
                        active: modelData.desktopFile === (section.current[rowCard.modelData.kind] || "")
                        activeColor: rowCard.modelData.tone
                        onClicked: section.choose(rowCard.modelData, modelData.desktopFile)
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Design.s(Design.space.sm)

                Field {
                    id: customField
                    Layout.fillWidth: true
                    placeholder: "Something else — type its command or desktop id"
                    onAccepted: v => { if (section.chooseTyped(rowCard.modelData, v)) customField.text = ""; }
                }

                ActionButton {
                    Layout.fillWidth: false
                    icon: "\u{f012c}"
                    label: "Set"
                    tone: rowCard.modelData.tone
                    onActivated: if (section.chooseTyped(rowCard.modelData, customField.text)) customField.text = ""
                }
            }

            Label {
                visible: text !== ""
                Layout.fillWidth: true
                text: section.notes[rowCard.modelData.kind] || ""
                role: "caption"
                dim: true
                wrapMode: Text.WordWrap
            }
        }
    }
}
