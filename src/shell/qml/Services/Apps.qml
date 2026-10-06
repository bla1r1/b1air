pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import "../Ui"

// =============================================================================
// The installed-application list, fetched once.
//
// Launchpad and SpotlightLauncher each ran their own `b1air-daemon apps all`
// and each parsed the reply themselves — the same twenty lines twice, and two
// subprocesses scanning the same desktop files. They differed only in how they
// presented the result: Launchpad resolves an icon path and maps the category,
// Spotlight uses a glyph and files everything under "Applications".
//
// So the fetch lives here and the raw entries are handed out unchanged; each
// launcher keeps its own presentation. Loading is lazy — a QML singleton is not
// created until something refers to it — so nothing is scanned until a launcher
// is actually opened.
// =============================================================================

Singleton {
    id: root

    /** Raw entries as the daemon reports them: name, comment, icon, iconPath, exec, category. */
    property var list: []

    readonly property bool loaded: root._loaded
    property bool _loaded: false

    /**
     * The icon for a window, from its app_id.
     *
     * Surfaces that show live windows — the Alt+Tab switcher, the top bar's
     * running-apps island — used the app_id directly as an icon name:
     * `image://icon/b1air-files`. That works only when an application's app_id
     * happens to also be an icon name, which is true for firefox and konsole
     * and false for every app in this suite, so our own windows all drew the
     * "icon not found" placeholder. A Wayland app_id is by convention the base
     * name of the application's desktop entry, and the entry is what knows the
     * icon, so look it up there.
     *
     * Returns an absolute path or an icon name; "" when nothing matches, so a
     * caller can fall back to the old behaviour for anything not installed as
     * a desktop entry.
     */
    function iconFor(appId) {
        const id = String(appId || "").toLowerCase();
        if (id === "")
            return "";

        for (const a of root.list) {
            const base = String(a.desktopFile || "").replace(/\.desktop$/i, "").toLowerCase();
            if (base === id)
                return a.iconPath || a.icon || "";
        }

        // Reverse-DNS entries (org.kde.dolphin.desktop) against a plain class
        // (dolphin), and the other way round.
        for (const a of root.list) {
            const base = String(a.desktopFile || "").replace(/\.desktop$/i, "").toLowerCase();
            if (base.endsWith("." + id) || id.endsWith("." + base))
                return a.iconPath || a.icon || "";
        }
        return "";
    }

    /** Re-scan. Cheap to call: one process, and only when asked. */
    function reload() {
        appLoader.running = false;
        appLoader.running = true;
    }

    Process {
        id: appLoader
        running: true
        command: ["b1air-daemon", "apps", "all"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const items = JSON.parse(this.text);
                    root.list = Array.isArray(items) ? items : [];
                } catch (e) {
                    // A daemon that is not up yet, or a truncated reply. Keep
                    // whatever was listed before rather than blanking the
                    // launcher the user is looking at.
                    if (!root._loaded)
                        root.list = [];
                }
                root._loaded = true;
            }
        }
    }

    // An icon name or path as an Image source: the suite's own icons by file,
    // a few legacy names from AdwaitaLegacy, the rest through the icon theme.
    function iconSource(icon) {
        const value = (icon || "application-x-executable").trim();
        if (value.startsWith("/") || value.startsWith("file://")) return Paths.fileUrl(value);
        // The suite's own icons, by file, from the copy `make install` puts
        // beside this QML. They used to be read from ~/.local/share/icons,
        // where a system-wide install never put them.
        if (value.startsWith("b1air-")) return Qt.resolvedUrl("../icons/apps/" + value + ".svg");
        const legacy = {
            "utilities-terminal": "utilities-terminal.png",
            "system-file-manager": "system-file-manager.png",
            "utilities-system-monitor": "utilities-system-monitor.png",
            "preferences-system": "preferences-system.png",
            "text-editor": "accessories-text-editor.png",
            // Notes asks for this name directly and had no entry, so it fell
            // through to image://icon/ and drew the missing-image checkerboard.
            "accessories-text-editor": "accessories-text-editor.png",
            "image-x-generic": "../mimetypes/image-x-generic.png",
            "x-office-calendar": "../mimetypes/x-office-calendar.png",
            "git": "applications-development.png",
            "web-browser": "web-browser.png",
            "edit-paste": "edit-paste.png",
            "system-lock-screen": "system-lock-screen.png",
            "system-shutdown": "system-shutdown.png",
            "system-search": "system-search.png",
            "color-picker": "insert-image.png"
        };
        if (legacy[value]) return "file:///usr/share/icons/AdwaitaLegacy/48x48/legacy/" + legacy[value];
        return "image://icon/" + value;
    }
}
