pragma Singleton

import QtQuick

// =============================================================================
// The desktop's live palette, inside the login screen.
//
// Every colour in this theme used to be a hex value typed into default.conf.
// They happened to be the same Tokyo Night values the shell uses, so the two
// matched — until the theme was changed once, and then the desktop was one
// colour and the screen you log in through was still the old one. Nothing
// carried a palette across that boundary, because there was no boundary that
// could be crossed: sddm runs as its own user and cannot read $HOME.
//
// b1air-daemon writes /var/cache/wallpaper/Palette.qml on every appearance
// apply — the same directory the login wallpaper is already shared through,
// group `wallpaper`, of which sddm is a member. This loads it.
//
// Loaded with Qt.createComponent rather than read with XMLHttpRequest: the
// greeter refuses file:// XHR unless QML_XHR_ALLOW_FILE_READ is set in sddm's
// service environment, and a theme that needs a systemd drop-in to show the
// right colours is a theme that will one day show the wrong ones. A component
// needs no permission.
//
// Every value falls back to the desktop's default palette (Breeze Dark's), so
// a machine where the daemon has never run — or where the wallpaper group was
// never set up — still looks like the desktop it logs into.
// =============================================================================

QtObject {
    id: palette

    readonly property string sourceFile: "file:///var/cache/wallpaper/Palette.qml"

    // The loaded object, or null. Not a property binding on a Component:
    // createObject() has to run after the component is Ready, and a synchronous
    // createComponent() is Ready or Error by the time it returns.
    property QtObject live: null

    Component.onCompleted: {
        var c = Qt.createComponent(palette.sourceFile, Component.PreferSynchronous);
        if (c.status === Component.Ready) {
            palette.live = c.createObject(palette);
        } else if (c.status === Component.Error) {
            // Expected on a fresh install, and not worth a visible failure:
            // the fallbacks below are the theme's own defaults.
            console.info("[b1air-theme] no shared palette (" + c.errorString() + ")");
        }
    }

    // Deliberately not hasOwnProperty(): a QML object's declared properties live
    // on its prototype, not on the object, so hasOwnProperty() answers false for
    // every one of them and the palette would have been silently ignored with
    // the fallbacks quietly taking over — the exact failure this file exists to
    // end. An undefined check is what actually distinguishes a missing key.
    function pick(key, fallback) {
        if (palette.live) {
            var v = palette.live[key];
            if (v !== undefined && String(v) !== "")
                return v;
        }
        return fallback;
    }

    // ── Surfaces ─────────────────────────────────────────────────────────────
    readonly property color ground: pick("ground", "#202326")          // backdrop
    readonly property color lowest: pick("lowest", "#141618")          // inputs, popups
    readonly property color low: pick("low", "#1b1e20")                // panels
    readonly property color mid: pick("mid", "#292c30")                // cards
    readonly property color high: pick("high", "#31363b")              // hover
    readonly property color highest: pick("highest", "#3e434a")        // pressed

    // ── Content ──────────────────────────────────────────────────────────────
    readonly property color text: pick("text", "#fcfcfc")
    readonly property color textDim: pick("textDim", "#b4bbc2")
    readonly property color outline: pick("outline", "#6b737a")        // inactive borders
    readonly property color outlineVariant: pick("outlineVariant", "#3a3f44")

    // ── Accent ───────────────────────────────────────────────────────────────
    readonly property color primary: pick("primary", "#3daee9")
    readonly property color primaryText: pick("primaryText", "#0d1b24")
    readonly property color primaryBox: pick("primaryBox", "#1f4a63")
    readonly property color tertiary: pick("tertiary", "#b07ad9")

    // ── Status ───────────────────────────────────────────────────────────────
    readonly property color error: pick("error", "#ed4b5b")
    readonly property color errorText: pick("errorText", "#ffffff")
    readonly property color warning: pick("yellow", "#fdbc4b")
    readonly property color ok: pick("green", "#2ecc71")

    // ── Over the wallpaper ───────────────────────────────────────────────────
    // The clock, the field and the buttons sit on the picture, not on the
    // palette: white and glass over a darkened photo, as a Mac's login has
    // them, whatever the theme. One set, used everywhere on the screen; the
    // values were typed out a dozen times in four strengths of white.
    readonly property color wallText: "#ebffffff"       // the clock, the name, a message
    readonly property color wallTextDim: "#a6ffffff"    // a placeholder, a hint
    readonly property color wallGlass: "#29ffffff"      // a field or a button on the picture
    readonly property color wallGlassHover: "#47ffffff"
    readonly property color wallShadow: "#38000000"     // under white text, so it reads on a bright photo
    readonly property color wallScrim: "#29000000"      // over the whole picture
    readonly property color wallShade: "#42000000"      // the top and bottom fades, at their darkest

    // Whether the session resolved to a dark face. Kept for components that
    // need to choose a shadow or an overlay rather than a palette colour.
    // The lock screen's language (Settings → language), "" for the system's.
    readonly property string lang: (palette.live && palette.live.lang !== undefined)
                                   ? palette.live.lang : ""
    // Inter, the desktop's sans, where it is installed; else the system's
    // sans-serif. Asked for a family that is not there, Qt took what
    // fontconfig ranked first — on this desktop the terminal's monospace,
    // all over the login screen.
    readonly property string sans: Qt.fontFamilies().indexOf("Inter") >= 0 ? "Inter" : "sans-serif"
    readonly property bool dark: (palette.live && palette.live.dark !== undefined)
                                 ? palette.live.dark : true
}
