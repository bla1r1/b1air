pragma Singleton

import QtQuick
import Qt.labs.folderlistmodel
import Quickshell
import B1air.Daemon
import Quickshell.Io
import "../Ui"

// =============================================================================
// Themes: pick one, write your own, carry it between machines.
//
// A theme is the palette Ui/Design holds — surfaces, text, accents — as a flat
// JSON object of role -> colour. Design.applyPalette() takes exactly that
// shape, and any role a theme leaves out keeps its built-in value, so a theme
// that only restyles the accents is a five-line file.
//
// Two themes ship built in. That is deliberate rather than decorative: the
// shell's palette was Catppuccin Mocha while SwayFX's window borders, the
// Kvantum widget theme, the SDDM greeter and the README all said Tokyo Night,
// so the desktop was visibly two themes at once with no way to reconcile them.
// Now it is a choice.
//
// User themes live in ~/.config/b1air/themes/*.json and are listed alongside
// the built-ins. Import copies a file in; export writes the live palette out.
// =============================================================================

Singleton {
    id: root

    readonly property string themesDir: Quickshell.env("HOME") + "/.config/b1air/themes"

    // Design reads this file at startup in every process, so a theme picked in
    // Settings reaches b1air-monitor, -term, -text and the rest, not just the
    // shell. Keep the name in step with Design.activeThemePath.
    readonly property string activeFile: Quickshell.env("HOME") + "/.config/b1air/theme.json"

    // byUser: a theme picked by hand takes back the accent from the swatch
    // picker. Re-applying the saved theme at login must not, or the swatch
    // was forgotten on every login.
    function _publish(palette, byUser) {
        if (byUser !== false && palette && (palette.primary || palette.accent))
            Settings.set("accentName", "");
        root._writeActive(byUser !== false ? "" : Settings.accentName);
    }

    // theme.json is what the lock screen, the apps and the login screen read,
    // so the swatch accent goes into it as primary.
    function _writeActive(accentName) {
        const out = Design.exportPalette();
        const named = String(accentName !== undefined ? accentName : Settings.accentName).toLowerCase();
        if (named && out[named]) out.primary = out[named];
        activeWriter.path = root.activeFile;
        activeWriter.setText(JSON.stringify(out, null, 2));
        // GTK, Kvantum, SDDM and sway borders follow after the write lands.
        appsRecolour.restart();
    }

    Connections {
        target: Settings
        function onAccentNameChanged() {
            if (Settings.loaded) Qt.callLater(() => root._writeActive(Settings.accentName));
        }
    }

    FileView {
        id: activeWriter
        printErrors: false
        atomicWrites: true
    }

    Timer {
        id: appsRecolour
        interval: 400
        onTriggered: Quickshell.execDetached(["b1air-daemon", "appearance", "apply"])
    }

    // ── Built-in themes ──────────────────────────────────────────────────────

    // The four the desktop ships: KDE's Breeze and GNOME's Adwaita, dark and
    // light. They replaced Catppuccin Mocha and Latte and Tokyo Night, whose
    // pastels on near-black put the text, the dim text and the borders a few
    // shades apart — pleasant, and hard to tell apart. These are the colours
    // the two big desktops settled on for legibility, with the dim text a
    // step stronger still. Breeze Dark is the default (Design.builtinPalette).
    readonly property var builtins: [
        {
            name: "Breeze Dark",
            id: "breeze-dark",
            palette: Design.builtinPalette
        },
        {
            name: "Breeze Light",
            id: "breeze-light",
            palette: {
                ground: "#eff0f1", lowest: "#dee0e2", low: "#f7f7f8",
                mid: "#ffffff", high: "#e5e7e9", highest: "#d3d6da",
                text: "#232629", textDim: "#4d5257",
                outline: "#7f868d", outlineVariant: "#c8ccd0",
                primary: "#1f7ac2", primaryText: "#ffffff",
                primaryBox: "#d2e6f6", tertiary: "#8e44ad",
                error: "#c62b3b", errorText: "#ffffff",
                blue: "#1f7ac2", sapphire: "#0f7fa8", mauve: "#8e44ad",
                pink: "#c2185b", peach: "#d35400", yellow: "#a86b00",
                green: "#1e8a4b", teal: "#128772", red: "#c62b3b",
                maroon: "#9b2335", lavender: "#5260d6"
            }
        },
        {
            name: "Adwaita Dark",
            id: "adwaita-dark",
            palette: {
                ground: "#222226", lowest: "#1a1a1d", low: "#28282c",
                mid: "#303034", high: "#3a3a3e", highest: "#48484d",
                text: "#ffffff", textDim: "#c0bfc4",
                outline: "#77767b", outlineVariant: "#3f3f45",
                primary: "#3584e4", primaryText: "#ffffff",
                primaryBox: "#233f63", tertiary: "#c061cb",
                error: "#ff7b63", errorText: "#1a1a1d",
                blue: "#62a0ea", sapphire: "#99c1f1", mauve: "#c061cb",
                pink: "#dc8add", peach: "#ffa348", yellow: "#f6d32d",
                green: "#57e389", teal: "#33c7de", red: "#f66151",
                maroon: "#ed333b", lavender: "#9cb6f7"
            }
        },
        {
            name: "Adwaita Light",
            id: "adwaita-light",
            palette: {
                ground: "#fafafb", lowest: "#ebebed", low: "#f6f6f7",
                mid: "#ffffff", high: "#ebebed", highest: "#dcdce0",
                text: "#1e1e22", textDim: "#4f4f55",
                outline: "#87878c", outlineVariant: "#d6d6da",
                primary: "#1c71d8", primaryText: "#ffffff",
                primaryBox: "#d6e6fa", tertiary: "#813d9c",
                error: "#c01c28", errorText: "#ffffff",
                blue: "#1c71d8", sapphire: "#1a5fb4", mauve: "#813d9c",
                pink: "#a8327f", peach: "#c64600", yellow: "#9c6e03",
                green: "#1b8553", teal: "#0f7b8c", red: "#c01c28",
                maroon: "#a51d2d", lavender: "#613583"
            }
        }
    ]

    // The built-ins this desktop had before, and what stands in for them, so
    // a saved choice of one lands on the nearest of the new set.
    readonly property var retired: ({
        "catppuccin-mocha": "breeze-dark",
        "tokyo-night": "breeze-dark",
        "catppuccin-latte": "breeze-light"
    })

    // ── User themes on disk ──────────────────────────────────────────────────

    // FolderListModel rather than `bash -c ls`: one fewer process per refresh,
    // and it re-lists by itself when the directory changes.
    FolderListModel {
        id: userThemeFiles
        folder: "file://" + root.themesDir
        nameFilters: ["*.json"]
        showDirs: false
        sortField: FolderListModel.Name
        onCountChanged: root._rebuild()
    }

    property var userThemes: []

    /** [{ name, id, builtin, path }] — built-ins first, then user themes. */
    property var available: []

    function _rebuild() {
        const users = [];
        for (let i = 0; i < userThemeFiles.count; ++i) {
            const file = String(userThemeFiles.get(i, "fileName"));
            const id = file.replace(/\.json$/i, "");
            users.push({
                name: id.replace(/[-_]/g, " ").replace(/\b\w/g, c => c.toUpperCase()),
                id: id,
                builtin: false,
                path: root.themesDir + "/" + file
            });
        }
        root.userThemes = users;

        const all = root.builtins.map(t => ({
            name: t.name, id: t.id, builtin: true, path: ""
        }));
        root.available = all.concat(users);
    }

    Component.onCompleted: root._rebuild()

    // ── Applying ─────────────────────────────────────────────────────────────

    readonly property string current: Settings.themeName

    function _builtinById(id) {
        for (const t of root.builtins)
            if (t.id === id) return t;
        return null;
    }

    /** Apply by id, persist the choice, and fall back cleanly if it is gone. */
    /**
     * A palette built from the wallpaper.
     *
     * The picture decides a hue; the plugin builds every role from fixed
     * lightness steps on it, which is what keeps the result readable whatever
     * the picture is — colours sampled straight out of an image give you two
     * that are nearly the same and text you cannot read on its own background.
     *
     * The wallpaper is read from ~/.cache/current_wallpaper.jpg, which is where
     * the daemon puts whatever it last set, so this follows the wallpaper
     * without needing to be told what it is.
     */
    function _wallpaperPalette() {
        const palette = Daemon.paletteFromImage(Quickshell.env("HOME") + "/.cache/current_wallpaper.jpg");
        return (palette && palette.ground) ? palette : null;
    }

    function applyFromWallpaper(byUser) {
        const palette = root._wallpaperPalette();
        // Unreadable or greyscale: keep what is on screen.
        if (!palette) return false;
        Design.applyPalette(palette);
        root._publish(palette, byUser);
        Settings.set("themeName", "wallpaper");
        return true;
    }

    property bool _applyByUser: true

    function apply(id, byUser) {
        if (root.retired[id]) id = root.retired[id];
        if (id === "wallpaper")
            return root.applyFromWallpaper(byUser);

        const b = root._builtinById(id);
        if (b) {
            Design.applyPalette(b.palette);
            root._publish(b.palette, byUser);
            Settings.set("themeName", id);
            return true;
        }
        root._applyByUser = byUser !== false;
        // The path is derived from the id rather than looked up in
        // `userThemes`, because that list is filled by FolderListModel, which
        // populates asynchronously. At login the list is still empty when the
        // saved theme is applied, so the lookup found nothing and fell through
        // to the reset below — the desktop came up in the built-in palette
        // every time, no matter what was picked.
        themeReader.path = root.themesDir + "/" + id + ".json";
        themeReader.reload();
        Settings.set("themeName", id);
        return true;
    }

    FileView {
        id: themeReader
        printErrors: false
        onLoaded: {
            try {
                const obj = JSON.parse(text());
                Design.applyPalette(obj);
                root._publish(obj, root._applyByUser);
            } catch (e) {
                root.lastError = "Not a valid theme file: " + e;
                Design.resetPalette();
            }
        }
        // Reached when the id names no file — a theme deleted behind our
        // back — so the desktop falls back instead of staying half-styled.
        onLoadFailed: {
            root.lastError = "Could not read the theme file.";
            Design.resetPalette();
        }
    }

    property string lastError: ""

    // Applies the saved choice once Settings has actually loaded — reading it
    // earlier gets the schema default rather than what the user picked.
    Connections {
        target: Settings
        function onLoadedChanged() {
            if (Settings.loaded && Settings.themeName)
                root.apply(Settings.themeName, false);
        }
    }

    // ── Creating and editing ─────────────────────────────────────────────────

    /**
     * Start a new theme from whatever is on screen right now.
     *
     * Creation deliberately begins from the live palette rather than a blank
     * file: every role already has a sensible value, so a new theme is a few
     * edits rather than 27 required decisions, and a half-finished one still
     * renders a usable desktop.
     */
    function createFrom(displayName) {
        return root._saveNew(displayName, Design.exportPalette());
    }

    /** Keep the wallpaper's palette as a theme of its own, so a new wallpaper doesn't replace it. */
    function saveWallpaperAs(displayName) {
        const palette = root._wallpaperPalette();
        if (!palette) {
            root.lastError = "Could not build a palette from the wallpaper.";
            return "";
        }
        Design.applyPalette(palette);
        const name = String(displayName || "").trim()
            || "Wallpaper " + I18n.locale.toString(new Date(), "d MMM hh-mm");
        return root._saveNew(name, Design.exportPalette());
    }

    function _slug(name) {
        return String(name).trim().toLowerCase()
            .replace(/[\/\\\s.]+/g, "-").replace(/^-+|-+$/g, "");
    }

    function _saveNew(displayName, palette) {
        const name = String(displayName || "").trim();
        if (name === "") {
            root.lastError = "Give the theme a name first.";
            return "";
        }
        let id = root._slug(name);
        if (id === "") {
            root.lastError = "That name has no usable characters.";
            return "";
        }
        if (root._builtinById(id)) {
            root.lastError = "That name collides with a built-in theme.";
            return "";
        }
        const taken = root.userThemes.map(t => t.id);
        const base = id;
        for (let n = 2; taken.indexOf(id) >= 0; ++n) id = base + "-" + n;

        writer.path = root.themesDir + "/" + id + ".json";
        writer.setText(JSON.stringify(palette, null, 2));
        root.lastError = "";
        root._rebuild();

        // Apply the object itself: the file list apply(id) would use fills in later.
        Design.applyPalette(palette);
        root._publish(palette);
        Settings.set("themeName", id);
        return id;
    }

    // ── Editing in place ─────────────────────────────────────────────────────

    property string editingId: ""
    property var draft: ({})
    property var _original: ({})

    // Edits save themselves, like everything else in Settings.
    Timer {
        id: draftSave
        interval: 400
        onTriggered: root._writeDraft()
    }

    function _writeDraft() {
        if (root.editingId === "") return;
        writer.path = root.themesDir + "/" + root.editingId + ".json";
        writer.setText(JSON.stringify(root.draft, null, 2));
        root._publish(root.draft, false);
        if (Settings.themeName !== root.editingId) Settings.set("themeName", root.editingId);
    }

    FileView {
        id: editReader
        blockLoading: true
        printErrors: false
    }

    function beginEdit(id) {
        if (root._builtinById(id) || id === "wallpaper") return false;
        root.finishEdit();
        editReader.path = root.themesDir + "/" + id + ".json";
        editReader.reload();
        let obj;
        try {
            obj = JSON.parse(editReader.text());
        } catch (e) {
            root.lastError = "Could not read that theme.";
            return false;
        }
        Design.applyPalette(obj);
        root.draft = Design.exportPalette();
        root._original = root.draft;
        root.editingId = id;
        root.lastError = "";
        return true;
    }

    /** Change one role in the draft and show it on screen straight away. */
    function setDraft(role, colour) {
        // A picked swatch would hide an edited accent.
        if (role === "primary" && Settings.accentName !== "") Settings.set("accentName", "");
        const d = Object.assign({}, root.draft);
        d[role] = String(colour);
        root.draft = d;
        Design.applyPalette(d);
        draftSave.restart();
    }

    /** Write anything pending and close the editor. */
    function finishEdit() {
        if (root.editingId === "") return;
        if (draftSave.running) {
            draftSave.stop();
            root._writeDraft();
        }
        root.editingId = "";
    }

    /** Back to the colours the theme had when editing started. */
    function revertEdit() {
        if (root.editingId === "") return;
        root.draft = root._original;
        Design.applyPalette(root.draft);
        draftSave.stop();
        root._writeDraft();
    }

    function deleteTheme(id) {
        if (root._builtinById(id) || id === "wallpaper") return;
        if (root.editingId === id) root.editingId = "";
        Quickshell.execDetached(["rm", "-f", "--", root.themesDir + "/" + id + ".json"]);
        if (Settings.themeName === id) root.apply("breeze-dark");
    }

    /** Path of the current theme's file, or "" for a built-in. */
    readonly property string currentFile:
        root._builtinById(Settings.themeName) ? "" : root.themesDir + "/" + Settings.themeName + ".json"

    /**
     * Open the current theme in the desktop's own text editor.
     *
     * A bespoke colour picker would be a second editor to build and maintain,
     * when a theme is a small JSON file and the suite already ships one. Saving
     * in b1air-text reloads the theme through the watcher below, so editing is
     * live.
     */
    function editCurrent() {
        if (root.currentFile === "") {
            root.lastError = "Built-in themes cannot be edited — duplicate it first.";
            return false;
        }
        Quickshell.execDetached(["b1air-text", root.currentFile]);
        return true;
    }

    // Re-applies the current theme when its file changes on disk, so an edit
    // made in the text editor (or by any other tool) lands without a restart.
    FileView {
        id: currentWatcher
        path: root.currentFile
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            if (root.currentFile === "")
                return;
            try {
                if (root.editingId !== "") return;
                const obj = JSON.parse(text());
                Design.applyPalette(obj);
                root._publish(obj, false);
                root.lastError = "";
            } catch (e) {
                // A half-typed file is normal while editing — say so, but keep
                // the last good palette rather than resetting the desktop.
                root.lastError = "Theme file is not valid JSON yet.";
            }
        }
    }

    // ── Import / export ──────────────────────────────────────────────────────

    property string lastExportPath: ""

    /**
     * Write the live palette to `path` (default: the themes dir).
     * The result is a plain JSON object, so it is the same thing Import eats.
     */
    function exportTo(path) {
        const target = path && path !== ""
            ? path
            : root.themesDir + "/exported-" + Qt.formatDateTime(new Date(), "yyyyMMdd-hhmmss") + ".json";
        writer.path = target;
        writer.setText(JSON.stringify(Design.exportPalette(), null, 2));
        root.lastExportPath = target;
        return target;
    }

    FileView {
        id: writer
        printErrors: false
        atomicWrites: true
    }

    /** Copy an outside .json into the themes dir so it shows up in the list. */
    function importFrom(path) {
        if (!path || path === "")
            return false;
        const clean = String(path).replace(/^file:\/\//, "");
        importReader.path = clean;
        importReader.reload();
        return true;
    }

    FileView {
        id: importReader
        printErrors: false
        onLoaded: {
            let obj;
            try {
                obj = JSON.parse(text());
            } catch (e) {
                root.lastError = "That file is not JSON.";
                return;
            }
            // Refuse a file with nothing we recognise rather than installing a
            // theme that would change nothing and look broken.
            const known = Object.keys(Design.builtinPalette);
            const hits = Object.keys(obj).filter(k => known.indexOf(k) >= 0
                || ["crust", "base", "mantle", "surface0", "surface1", "surface2",
                    "accent", "accentAlt", "accentSoft", "accentText", "danger",
                    "subtext0", "overlay0", "line", "sunken", "raised", "hover",
                    "active"].indexOf(k) >= 0);
            if (hits.length === 0) {
                root.lastError = "No palette roles in that file.";
                return;
            }

            const base = String(importReader.path).split("/").pop().replace(/\.json$/i, "");
            const id = base.toLowerCase().replace(/[^a-z0-9_-]+/g, "-");
            writer.path = root.themesDir + "/" + id + ".json";
            writer.setText(JSON.stringify(obj, null, 2));
            root.lastError = "";
            root._rebuild();

            // Apply the object we already parsed rather than calling apply(id):
            // the list it looks the id up in comes from FolderListModel, which
            // notices the new file asynchronously. Going through apply() here
            // found nothing, fell through to the "theme is gone" branch and
            // reset the desktop to the built-in palette — an import that
            // silently did the opposite of what it said.
            Design.applyPalette(obj);
            root._publish(obj);
            Settings.set("themeName", id);
        }
        onLoadFailed: root.lastError = "Could not read that file."
    }
}
