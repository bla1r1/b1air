pragma Singleton

import QtQuick
import QtCore
import "../WindowRegistry.js" as LayoutMath

// =============================================================================
// THE reference file for the whole shell UI.
//
// Colour, type, shape, motion and scale — one place, one import.
// Provides both semantic design-system tokens and the rich Catppuccin /
// Material You palette for vibrant, modern rice aesthetics.
// =============================================================================

QtObject {
    id: root

    component FontScale: QtObject {
        readonly property int caption: 11   // metadata, units, timestamps
        readonly property int body: 13      // standard UI working size
        readonly property int subhead: 15   // card titles, device names
        readonly property int title: 18     // section / page titles
        readonly property int display: 24   // popup headlines, hero numbers

        readonly property string sans: "Fira Sans"
        readonly property string mono: "JetBrainsMono Nerd Font"
        // The "Mono" cut, deliberately: in the plain Nerd Font the icon glyphs
        // are drawn inside a double-width advance with the ink hugging the left
        // of it, so centring the text box leaves every glyph sitting left of
        // centre. NFM gives each icon a single cell, and the box centre is the
        // glyph centre.
        readonly property string icon: "JetBrainsMono Nerd Font Mono"
    }

    component WeightScale: QtObject {
        readonly property int regular: Font.Normal     // 400
        readonly property int medium: Font.Medium      // 500
        readonly property int semibold: Font.DemiBold  // 600
        readonly property int bold: Font.Bold          // 700
    }

    component RadiusScale: QtObject {
        // b1air-monitor and b1air-text (and their two copies under shell/qml)
        // already referenced Design.radius.sm, which was never declared here:
        // Design.s(undefined) is NaN, so those four elements were drawn with
        // radius NaN instead of a small rounded corner.
        readonly property int sm: 6       // chips, inline badges, inner boxes
        readonly property int ctl: 10     // buttons, fields, list rows, sliders
        readonly property int card: 14    // cards, quick-tiles
        readonly property int panel: 20   // popup panels, main windows
        readonly property int pill: 999   // toggles, chips, status pills
    }

    component SpaceScale: QtObject {
        readonly property int xxs: 2      // hairline gap inside a chip or stacked labels
        readonly property int xs: 4
        readonly property int sm: 8
        readonly property int md: 12
        readonly property int lg: 16
        readonly property int xl: 24
        readonly property int xxl: 32
    }

    // Fixed heights that repeat across the shell. Before this scale the same
    // control was Design.s(34), s(36) and s(38) in three files, so nothing in a
    // row lined up with anything else in it.
    component SizeScale: QtObject {
        readonly property int header: 36    // brand / title row at the top of a panel
        readonly property int iconBtn: 28   // round header / media button
        // Inline controls that stack inside one Card. They were written as
        // Design.s(32) in Field and Pill and Design.s(30) in Stepper, so a
        // card mixing a field, a stepper and a pill had three row heights
        // that did not line up — the exact drift this scale exists to stop.
        readonly property int field: 32     // text field, stepper, pill
        readonly property int knob: 36      // circular toggle inside a tile
        readonly property int row: 38       // one-line list row, square button
        readonly property int ctl: 38       // slider, field, capsule control
        readonly property int rowTall: 44   // two-line list row
        readonly property int action: 36    // bottom action button
        readonly property int art: 48       // album art
        readonly property int tile: 56      // quick tile
        readonly property int media: 76     // media card
    }

    component DurationScale: QtObject {
        readonly property int fast: 150   // pointer response: hover, press
        readonly property int base: 250   // state change: toggle, selection
        readonly property int slow: 400   // window enter / exit
    }

    component OpacityScale: QtObject {
        readonly property real disabled: 0.38
        readonly property real muted: 0.62
        readonly property real full: 1.0
    }

    component ShadowSpec: QtObject {
        readonly property color tone: "#000000"
        readonly property real blur: 0.6
        readonly property real blurStrong: 1.0
        readonly property real opacity: 0.5
    }

    // =========================================================================
    // SCALE
    // =========================================================================
    // screenWidth used to be pushed in from PopupShell, so the scale was stale
    // until a popup opened and then belonged to whichever popup opened last.
    // Read it here instead — Qt.application.screens needs no Quickshell, which
    // matters because the standalone apps load these tokens too.
    readonly property real screenWidth: Qt.application.screens.length > 0
                                        ? Qt.application.screens[0].width : 1920
    readonly property real screenHeight: Qt.application.screens.length > 0
                                         ? Qt.application.screens[0].height : 1080

    // Assigned by the shell root and by each popup; the standalone apps have no
    // access to Settings and stay at 1.0, exactly as before.
    property real uiScale: 1.0

    readonly property real scale: LayoutMath.getScale(screenWidth, uiScale, screenHeight)

    function s(val) {
        return LayoutMath.s(val, root.scale);
    }

    // =========================================================================
    // COLOUR & PALETTE
    // =========================================================================
    // Dynamic values arrive from the theme, or fall back to Breeze Dark.

    // ── Surfaces ─────────────────────────────────────────────────────────────
    readonly property color ground: _p.ground     // backdrop ground
    readonly property color sunken: _p.lowest     // recessed tracks, input fields
    readonly property color surface: _p.low       // popup / panel base
    readonly property color raised: _p.mid        // cards, tiles
    readonly property color hover: _p.high        // hover highlight, active surface
    readonly property color active: _p.highest    // pressed / selected item

    // ── Text & Content ───────────────────────────────────────────────────────
    readonly property color text: _p.text
    readonly property color textDim: _p.textDim
    readonly property color textFaint: _p.outline

    // ── Lines & Borders ──────────────────────────────────────────────────────
    readonly property color line: _p.outlineVariant

    // ── Primary Accent ───────────────────────────────────────────────────────
    // Which named palette colour acts as the accent.
    //
    // The Appearance page has offered a nine-swatch accent picker since it was
    // written, and picking a swatch changed nothing on screen: `accent` was
    // pinned to _p.primary, and the only thing that ever reassigned _p was
    // _applyPalette(), which nothing calls. 156 bindings across the shell read
    // Design.accent, so the picker looked like the most powerful control in
    // Settings while being the one that did the least.
    //
    // Ui deliberately does not import Services to read this itself: the
    // standalone apps (b1air-monitor, -text, -term) load Ui into a plain
    // QQmlApplicationEngine with no Quickshell runtime, and Services/Settings
    // needs Quickshell.Io. The shell assigns it instead.
    // Empty means "whatever the theme calls primary". A named colour picks
    // that role out of the *current* palette, so choosing Green under a
    // Solarized theme gives Solarized's green, not Catppuccin's.
    property string accentName: ""

    readonly property color accent: {
        switch ((root.accentName || "").toLowerCase()) {
        case "sapphire":  return _p.sapphire;
        case "mauve":     return _p.mauve;
        case "teal":      return _p.teal;
        case "peach":     return _p.peach;
        case "pink":      return _p.pink;
        case "green":     return _p.green;
        case "lavender":  return _p.lavender;
        case "yellow":    return _p.yellow;
        case "red":       return _p.red;
        case "blue":      return _p.blue;
        default:          return _p.primary;
        }
    }
    // The theme's own primary, whatever accent is picked over it.
    readonly property color themePrimary: _p.primary
    // Text that reads on a fill: dark on a light one, white on a dark one.
    // The theme's primaryText suits its primary only — yellow picked as the
    // accent on a light theme had white text on it.
    function readableOn(c) {
        const l = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b;
        return l > 0.55 ? "#111418" : "#ffffff";
    }
    readonly property color accentText: (root.accentName || "") === "" ? _p.primaryText : root.readableOn(root.accent)
    readonly property color accentSoft: _p.primaryBox
    readonly property color accentAlt: _p.tertiary

    // ── Rich Semantic Palette ────────────────────────────────────────────────
    readonly property color blue: _p.blue
    readonly property color sapphire: _p.sapphire
    readonly property color mauve: _p.mauve
    readonly property color pink: _p.pink
    readonly property color peach: _p.peach
    readonly property color yellow: _p.yellow
    readonly property color green: _p.green
    readonly property color teal: _p.teal
    readonly property color cyan: _p.teal
    readonly property color red: _p.red
    readonly property color maroon: _p.maroon
    readonly property color lavender: _p.lavender

    // ── Status Colours ───────────────────────────────────────────────────────
    readonly property color ok: _p.green
    readonly property color warn: _p.peach
    readonly property color danger: _p.red
    readonly property color dangerText: _p.errorText

    // Tint helper
    function tint(c, alpha) {
        if (!c) return Qt.rgba(0, 0, 0, alpha !== undefined ? alpha : 1.0);
        if (typeof c === "object" && c.r !== undefined) {
            return Qt.rgba(c.r, c.g, c.b, alpha !== undefined ? alpha : 1.0);
        }
        let s = String(c).trim();
        if (s.startsWith("#") && s.length >= 7) {
            let r = parseInt(s.substring(1, 3), 16) / 255.0;
            let g = parseInt(s.substring(3, 5), 16) / 255.0;
            let b = parseInt(s.substring(5, 7), 16) / 255.0;
            return Qt.rgba(r, g, b, alpha !== undefined ? alpha : 1.0);
        }
        return Qt.rgba(0.5, 0.5, 0.5, alpha !== undefined ? alpha : 1.0);
    }

    // Readable text on an arbitrary fill.
    function contrastOn(c) {
        let r = 0.5, g = 0.5, b = 0.5;
        if (typeof c === "object" && c.r !== undefined) {
            r = c.r; g = c.g; b = c.b;
        } else if (String(c).startsWith("#") && String(c).length >= 7) {
            let s = String(c).trim();
            r = parseInt(s.substring(1, 3), 16) / 255.0;
            g = parseInt(s.substring(3, 5), 16) / 255.0;
            b = parseInt(s.substring(5, 7), 16) / 255.0;
        }
        return (0.299 * r + 0.587 * g + 0.114 * b) > 0.55 ? _p.ground : _p.text;
    }

    // ── Glassmorphic & Translucency Tokens ────────────────────────────────────
    // Whether surfaces may let the wallpaper through. Only with a compositor
    // that blurs what is behind them (swayFX, blur on): on plain sway, or with
    // blur off, a translucent panel shows the wallpaper sharp through every
    // card, and text over a busy picture turned to mush. The shell sets it;
    // the standalone apps leave it true, where these sit on their own window.
    property bool translucent: true

    readonly property color glassBg: tint(surface, translucent ? 0.88 : 1.0)
    readonly property color glassCard: translucent ? tint(raised, 0.65) : raised
    readonly property color glassTile: translucent ? tint(raised, 0.55) : raised
    readonly property color glassBorder: tint(text, 0.12)
    // Hover/active variant. ClipboardPopup has referenced this since it was
    // written; undeclared, it evaluated to an invalid colour, so hovering a
    // clipboard card swapped its border for black instead of brightening it.
    readonly property color glassBorderStrong: tint(text, 0.22)
    readonly property color glassHover: tint(text, 0.08)
    readonly property color glassActive: tint(accent, 0.20)

    readonly property color veil: tint(text, 0.05)
    readonly property color veilStrong: tint(text, 0.10)
    readonly property color veilBold: tint(text, 0.16)

    // =========================================================================
    // TYPE & SHAPE
    // =========================================================================
    readonly property FontScale font: FontScale {}
    readonly property WeightScale weight: WeightScale {}
    readonly property RadiusScale radius: RadiusScale {}
    readonly property SpaceScale space: SpaceScale {}
    readonly property SizeScale size: SizeScale {}
    readonly property DurationScale duration: DurationScale {}
    readonly property OpacityScale opacity: OpacityScale {}
    readonly property ShadowSpec shadow: ShadowSpec {}

    readonly property int border: 1
    readonly property int easing: Easing.OutCubic
    readonly property int blurMax: 64

    // =========================================================================
    // LOADING & PALETTE PARSER
    // =========================================================================
    readonly property bool loaded: _p.loaded

    function reload() {
        root.resetPalette();
    }

    // The palette a theme overwrites. Kept as a plain object so applyPalette()
    // can put every role back without re-reading the file that changed them.
    // Breeze Dark (Services/Theme.qml has the other built-ins).
    readonly property var builtinPalette: ({
        ground: "#202326", lowest: "#141618", low: "#1b1e20",
        mid: "#292c30", high: "#31363b", highest: "#3e434a",
        text: "#fcfcfc", textDim: "#b4bbc2", outline: "#6b737a", outlineVariant: "#3a3f44",
        primary: "#3daee9", primaryText: "#0d1b24", primaryBox: "#1f4a63", tertiary: "#b07ad9",
        error: "#ed4b5b", errorText: "#ffffff",
        blue: "#3daee9", sapphire: "#1d99f3", mauve: "#b07ad9", pink: "#e93a9a",
        peach: "#f67400", yellow: "#fdbc4b", green: "#2ecc71", teal: "#1abc9c",
        red: "#ed4b5b", maroon: "#c0392b", lavender: "#8e9bff"
    })

    property QtObject _p: QtObject {
        property bool loaded: false

        property color ground: "#202326"
        property color lowest: "#141618"
        property color low: "#1b1e20"
        property color mid: "#292c30"
        property color high: "#31363b"
        property color highest: "#3e434a"

        property color text: "#fcfcfc"
        property color textDim: "#b4bbc2"
        property color outline: "#6b737a"
        property color outlineVariant: "#3a3f44"

        property color primary: "#3daee9"
        property color primaryText: "#0d1b24"
        property color primaryBox: "#1f4a63"
        property color tertiary: "#b07ad9"

        property color error: "#ed4b5b"
        property color errorText: "#ffffff"

        property color blue: "#3daee9"
        property color sapphire: "#1d99f3"
        property color mauve: "#b07ad9"
        property color pink: "#e93a9a"
        property color peach: "#f67400"
        property color yellow: "#fdbc4b"
        property color green: "#2ecc71"
        property color teal: "#1abc9c"
        property color red: "#ed4b5b"
        property color maroon: "#c0392b"
        property color lavender: "#8e9bff"
    }

    /**
     * Apply a palette.
     *
     * `obj` maps role names to colours; any role it omits keeps the built-in
     * value, so a theme can restyle only the accents and leave the surfaces
     * alone. Roles are the keys of builtinPalette above, plus the aliases the
     * Catppuccin naming uses (crust/base/mantle/surface0…), so a palette
     * exported from either vocabulary loads.
     *
     * This replaces _applyPalette(txt), which called a _parse() that does not
     * exist anywhere in the project — it would have thrown on the first call.
     */
    function applyPalette(obj) {
        const src = obj || {};
        const pick = (...names) => {
            for (const n of names)
                if (src[n]) return src[n];
            return undefined;
        };

        const bp = root.builtinPalette;
        const set = (key, ...names) => {
            const v = pick(...names);
            root._p[key] = (v !== undefined) ? v : bp[key];
        };

        // The canonical role name comes first in every lookup. It used to be
        // missing from most of these — set("lowest", "sunken", "base") never
        // looked for "lowest" — so a theme written in role names got only the
        // few roles whose alias happened to match, and exporting it produced a
        // file that was half one palette and half the other.
        set("ground", "ground", "crust");
        set("lowest", "lowest", "sunken", "base");
        set("low", "low", "surface", "mantle");
        set("mid", "mid", "raised", "surface0");
        set("high", "high", "hover", "surface1");
        set("highest", "highest", "active", "surface2");

        set("text", "text");
        set("textDim", "textDim", "subtext0");
        set("outline", "outline", "textFaint", "overlay0");
        set("outlineVariant", "outlineVariant", "line", "surface1");

        set("primary", "primary", "accent", "blue");
        set("primaryText", "primaryText", "accentText", "onAccent");
        set("primaryBox", "primaryBox", "accentSoft", "sapphire");
        set("tertiary", "tertiary", "accentAlt", "mauve");

        set("error", "error", "danger", "red");
        set("errorText", "errorText", "dangerText", "onDanger");

        for (const n of ["blue", "sapphire", "mauve", "pink", "peach", "yellow",
                         "green", "teal", "red", "maroon", "lavender"])
            set(n, n);

        root._guardContrast();
        root._p.loaded = true;
    }

    // ── Contrast guard ───────────────────────────────────────────────────────
    //
    // Measured (WCAG ratio) before this existed: faint text — hints, captions,
    // secondary labels — sat at 2.3–2.6 on a card, where 4.5 is the floor for
    // reading; card borders at 1.4–1.6 against the card; and under Tokyo
    // Night a card, its hover state and the panel behind it were 1.07–1.08
    // apart, which is the same colour. Every palette passes through here —
    // built-in, wallpaper-made or a user's file — and each role that falls
    // short is moved in lightness, away from its background, until it does
    // not. A palette that already passes comes out unchanged.
    function _col(c) { return Qt.lighter(c, 1.0); }
    function _lum(c) {
        const f = v => v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4);
        return 0.2126 * f(c.r) + 0.7152 * f(c.g) + 0.0722 * f(c.b);
    }
    function contrastRatio(a, b) {
        const la = root._lum(root._col(a)), lb = root._lum(root._col(b));
        return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05);
    }
    // `fg` moved away from `bg` (lighter on a dark theme, darker on a light
    // one) in small lightness steps until the ratio is met or it runs out.
    function _ensure(fg, bg, min, dark) {
        let c = root._col(fg);
        for (let i = 0; i < 60 && root.contrastRatio(c, bg) < min; ++i) {
            const l = Math.max(0, Math.min(1, c.hslLightness + (dark ? 0.015 : -0.015)));
            if (l === c.hslLightness) break;
            c = Qt.hsla(c.hslHue < 0 ? 0 : c.hslHue, c.hslSaturation, l, 1);
        }
        return c.toString();
    }
    function _guardContrast() {
        const p = root._p;
        const dark = root._lum(root._col(p.text)) > root._lum(root._col(p.ground));
        // Surfaces: each step distinguishable from the one under it.
        if (dark) {
            p.mid = root._ensure(p.mid, p.low, 1.22, dark);
            p.high = root._ensure(p.high, p.mid, 1.20, dark);
            p.highest = root._ensure(p.highest, p.high, 1.15, dark);
        } else {
            // A light interface raises a card by making it *lighter* — white
            // over a grey ground — and darkens only for hover and press. The
            // one-way ladder pushed white cards to #ddd and hover to slate.
            // Cards just need to differ from the panel, either way; hover and
            // press step down from the card.
            if (root.contrastRatio(p.mid, p.low) < 1.05)
                p.mid = root._ensure(p.mid, p.low, 1.05, dark);
            p.high = root._ensure(p.high, p.mid, 1.12, dark);
            p.highest = root._ensure(p.highest, p.high, 1.08, dark);
        }
        // Lines visible against the card they outline. Lighter on a light
        // palette, where 1.8 turns every outline into a drawn stroke.
        p.outlineVariant = root._ensure(p.outlineVariant, p.mid, dark ? 1.8 : 1.4, dark);
        // Text, on the lightest surface it is drawn on (hover).
        p.text = root._ensure(p.text, p.high, 7.0, dark);
        p.textDim = root._ensure(p.textDim, p.high, 4.5, dark);
        p.outline = root._ensure(p.outline, p.mid, 4.0, dark);
        // The accent is used for text and icons on cards.
        p.primary = root._ensure(p.primary, p.mid, 3.5, dark);
        for (const n of ["blue", "sapphire", "mauve", "pink", "peach", "yellow",
                         "green", "teal", "red", "maroon", "lavender", "tertiary", "error"])
            p[n] = root._ensure(p[n], p.mid, 3.0, dark);
        // Text on an accent fill: whichever of its own colour or the ground
        // reads, never a third shade that does neither.
        if (root.contrastRatio(p.primaryText, p.primary) < 4.5)
            p.primaryText = root.contrastRatio(p.ground, p.primary) >= root.contrastRatio(p.text, p.primary)
                            ? p.ground : p.text;
    }

    // ── Loading the active theme ─────────────────────────────────────────────
    //
    // Services/Theme writes the resolved palette to ~/.config/b1air/theme.json
    // whenever a theme is picked. Design reads it directly rather than going
    // through that service, because Design is loaded by every app in the suite
    // — b1air-monitor, -text, -term and the rest run in a plain
    // QQmlApplicationEngine with no Quickshell runtime, so anything reaching
    // for Quickshell.Io here would break them. StandardPaths and
    // XMLHttpRequest are plain Qt, which is what makes one theme apply across
    // the whole desktop instead of only inside the shell.
    readonly property string activeThemePath:
        StandardPaths.writableLocation(StandardPaths.HomeLocation)
        + "/.config/b1air/theme.json"

    function loadActiveTheme() {
        const xhr = new XMLHttpRequest();
        try {
            // Startup-time and tiny, so synchronous: the alternative is a
            // frame or two rendered in the wrong palette.
            xhr.open("GET", root.activeThemePath, false);
            xhr.send();
            if ((xhr.status === 0 || xhr.status === 200)
                    && xhr.responseText && xhr.responseText.trim() !== "") {
                root.applyPalette(JSON.parse(xhr.responseText));
                return true;
            }
        } catch (e) {
            // No theme picked yet, or the file is unreadable. The built-in
            // palette is already in place, so there is nothing to repair.
        }
        return false;
    }

    // Without a theme file the built-in palette still goes through the guard.
    Component.onCompleted: if (!root.loadActiveTheme()) root.applyPalette(root.builtinPalette)

    /** Back to the palette compiled into this file. */
    function resetPalette() {
        root.applyPalette(root.builtinPalette);
    }

    /** The live palette, in the shape applyPalette() accepts — for export. */
    function exportPalette() {
        const out = {};
        for (const k in root.builtinPalette)
            out[k] = String(root._p[k]);
        return out;
    }

    // Legacy aliases
    readonly property color base: surface
    readonly property color mantle: sunken
    readonly property color crust: ground
    readonly property color subtext0: textDim
    readonly property color subtext1: textDim
    readonly property color surface0: raised
    readonly property color surface1: hover
    readonly property color surface2: active
    readonly property color overlay0: textFaint
    readonly property color overlay1: textFaint
    readonly property color overlay2: textFaint
}
