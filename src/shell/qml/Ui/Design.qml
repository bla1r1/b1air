pragma Singleton

import QtQuick
import B1air.Daemon
import QtCore
import "../WindowRegistry.js" as LayoutMath

// =============================================================================
// THE reference file for the whole shell UI.
//
// Colour, type, shape, motion and scale — one place, one import.
//
// How the colours are meant to be used:
//   - surfaces (ground … active) and text (text, textDim, textFaint) for
//     everything that is not saying something;
//   - accent for what is chosen, in focus, or the main action — one thing;
//   - ok / warn / danger for state, and only for state;
//   - the named hues (blue, mauve, peach, …) for data: Files tags, charts,
//     avatars, and the accent picker. Not to tell one widget from another.
// =============================================================================

QtObject {
    id: root

    component FontScale: QtObject {
        // macOS's text styles (HIG: Typography), each with its line height:
        // Subheadline 11/14, Callout 12/15, Body 13/16, Title 3 15/20,
        // Title 2 17/22, Large Title 26/32. Title was 20 and display 28,
        // between the steps.
        readonly property int caption: 11   // metadata, units, timestamps
        readonly property int footnote: 12  // note, secondary text
        readonly property int body: 13      // standard UI working size
        readonly property int subhead: 15   // card titles, device names
        readonly property int title: 17     // page and popup titles
        readonly property int display: 26   // popup headlines, hero numbers
        readonly property var lineHeight: ({ 11: 14, 12: 15, 13: 16, 15: 20, 17: 22, 26: 32 })
        readonly property int hero: 44      // a clock or a big glyph that is the popup
        readonly property int jumbo: 120    // a screen's number when identifying screens
        readonly property int glyph: 16     // an icon in a button or row
        readonly property int glyphSm: 14   // an icon in a small button, menu item, tab

        // Inter: the open face closest to the one a desktop like this is
        // usually set in — wide, even, with figures that can be told to
        // line up (Design.tabular). Where it is missing, sans-serif, which
        // .config/fontconfig/fonts.conf orders Fira Sans after it. Not
        // "Inter" regardless: asked for a family that is not installed,
        // fontconfig hands over what it ranks first, and that was JetBrains
        // Mono — the whole desktop, every app and the bar, in the terminal's
        // font, which is how the inter-font package going missing looked.
        readonly property string sans: Qt.fontFamilies().indexOf("Inter") >= 0 ? "Inter" : "sans-serif"
        readonly property string mono: "JetBrainsMono Nerd Font"
        // The "Mono" cut, deliberately: in the plain Nerd Font the icon glyphs
        // are drawn inside a double-width advance with the ink hugging the left
        // of it, so centring the text box leaves every glyph sitting left of
        // centre. NFM gives each icon a single cell, and the box centre is the
        // glyph centre.
        //
        // "b1air Symbols" is that font with its icons redrawn in one style
        // (tools/build-symbols.py, .local/share/fonts): the same codepoints,
        // so every "\u{f05a9}" in the source still means Wi-Fi. Without it
        // fontconfig falls back to the Nerd Font (.config/fontconfig).
        readonly property string icon: "b1air Symbols"
    }

    // OpenType features for figures that line up (Inter has them).
    readonly property var tabular: ({ "tnum": 1 })

    component WeightScale: QtObject {
        readonly property int regular: Font.Normal     // 400
        readonly property int medium: Font.Medium      // 500
        readonly property int semibold: Font.DemiBold  // 600
        readonly property int bold: Font.Bold          // 700
    }

    component RadiusScale: QtObject {
        readonly property int sm: 4       // chips, badges, inner elements
        readonly property int ctl: 8      // buttons, fields, list rows, selects
        readonly property int card: 12    // cards, groups, quick-tiles
        // The outer shapes, one radius: an app's window (sway's corner_radius,
        // Settings → Windows) and a popup panel are the same material. 20 so
        // that what sits inside is concentric with it: a sidebar 8 in at 12,
        // its rows 4 further in at 8 (see concentric()).
        readonly property int window: 20
        readonly property int panel: 20   // popup panels
        readonly property int pill: 999   // toggles, chips, status pills
    }

    // Apple's rule for corners (HIG: Layout, Toolbars): something inside a
    // rounded shape, `inset` from its edge, has the shape's radius less that
    // inset — so the two curves run parallel instead of the inner one
    // bulging at the corner. Never below the smallest radius.
    // Letter spacing for Inter at a size, in pixels: its own dynamic
    // metrics (rsms.me/inter/dynmetrics), as SF's tracking table is Apple's
    // (HIG: Typography) — a little open when small, tighter as it grows.
    function tracking(px) {
        return px * (-0.0223 + 0.185 * Math.exp(-0.1745 * px));
    }

    // The radius the corner rule gives an element (Shape.radius, from the
    // B1air.Daemon plugin: what its container leaves it), or its own where
    // the rule has none (-1: it sits as far in as the corner is round).
    //   radius: Design.corner(Shape.radius, Design.s(Design.radius.ctl))
    function corner(shapeRadius, own) {
        return shapeRadius >= 0 ? shapeRadius : own;
    }

    function concentric(outer, inset) {
        return Math.max(root.radius.sm, outer - inset);
    }

    component SpaceScale: QtObject {
        readonly property int xxs: 2      // hairline gap inside a chip or stacked labels
        readonly property int xs: 4
        readonly property int sm: 8
        readonly property int md: 12
        readonly property int lg: 16
        readonly property int xl: 24
        readonly property int xxl: 32

        // Semantic layout spacing tokens
        readonly property int pagePadding: 24
        readonly property int groupGap: 24
        readonly property int rowPaddingX: 12
    }

    // Canonical 5 heights and component sizes across the shell.
    component SizeScale: QtObject {
        // Canonical 5 heights
        readonly property int xs: 24        // bar, chip
        readonly property int sm: 28        // toolbar, icon button
        readonly property int md: 32        // text field, button, select, segmented, menu item
        readonly property int row: 40       // single-line list row
        readonly property int rowTall: 52   // two-line list row

        readonly property int mini: 20      // badge, a tab's close button, a frame's tools
        readonly property int micro: 16     // spinner, the smallest square control
        readonly property int knob: 36      // circular toggle inside a tile
        readonly property int header: 36    // brand / title row at the top of a panel
        readonly property int art: 48       // album art
        readonly property int tile: 56      // quick tile
        readonly property int media: 76     // media card
        readonly property int stat: 72      // a figure tile (screen time, focus)
        readonly property int avatar: 88    // a user picture
        readonly property int thumb: 120    // a wallpaper thumbnail
        readonly property int canvas: 260   // the display arrangement canvas
        readonly property int bar: 38       // the top bar
        readonly property int barZone: 40   // the space the bar keeps from windows
        readonly property int island: 30    // one group of items in the bar
        readonly property int dot: 6        // an unread or status dot
    }

    // Widths that repeat: the same sidebar, menu or field in every app.
    component WidthScale: QtObject {
        readonly property int sidebar: 224     // an app's sidebar
        readonly property int menuMin: 240     // a menu or popover, narrowest
        readonly property int menuMax: 440     // a menu, widest
        readonly property int select: 280      // a Select, closed and open
        readonly property int dialog: 340      // a dialog's message column
        readonly property int tab: 220         // one tab, widest
        readonly property int text: 320        // a short centred paragraph
        readonly property int dash: 520        // the calendar's dashboard with weather
        readonly property int field: 120       // a field with no layout width
        readonly property int segment: 220     // a segmented control, narrowest
        readonly property int segmentSm: 110   // one segment, small
        readonly property int segmentMd: 125   // one segment
        readonly property int list: 260        // a popup list's height, at most
        readonly property int control: 220     // a Select or stepper at the end of a settings row
        readonly property int label: 160       // a label column in a form, a key cap
        readonly property int page: 1040       // a settings page's column, widest
    }

    component DurationScale: QtObject {
        readonly property int fast: 150   // pointer response: hover, press
        readonly property int base: 250   // state change: toggle, selection
        readonly property int slow: 400   // window enter / exit
        // One turn of a busy glyph: every spinner at one speed (they ran
        // at 900, 1000 and 1200).
        readonly property int spin: 900
    }

    // Springs, for what moves as if it had weight: a selection sliding to
    // its place, a switch's knob, glass that flexes when pressed. Under
    // Reduce Motion they are not used (reduceMotion below).
    component SpringScale: QtObject {
        readonly property var snappy: ({ spring: 5.0, damping: 0.36 })   // a knob, a thumb
        readonly property var smooth: ({ spring: 3.6, damping: 0.42 })   // a selection moving over
        readonly property var bouncy: ({ spring: 4.5, damping: 0.26 })   // a press that flexes
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
    readonly property color textDim: root.increaseContrast ? root._ensure(_p.textDim, _p.high, 7.0, root._lum(root._col(_p.text)) > root._lum(root._col(_p.ground))) : _p.textDim
    // The faintest text — hints, metadata, placeholders — still 4.5:1 on
    // the lightest surface it is drawn on (hover), as Apple's minimum for
    // text up to 17 pt asks. It was the outline colour, 2.5:1 on a hovered
    // row in Breeze Dark: a border's colour, not a text's. Derived from the
    // palette, so every theme gets it.
    readonly property color textFaint: root._ensure(_p.outline, _p.high, 4.5, root._lum(root._col(_p.text)) > root._lum(root._col(_p.ground)))

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
    // A colour named by its role, for what comes from outside QML (the
    // daemon's weather says "yellow" for a clear sky): the current theme's,
    // so it follows a light theme and a theme of one's own. `fallback` for
    // a name it does not know.
    function tone(name, fallback) {
        switch (String(name || "")) {
        case "text":      return root.text;
        case "textDim":   return root.textDim;
        case "accent":    return root.accent;
        case "blue":      return _p.blue;
        case "sapphire":  return _p.sapphire;
        case "mauve":     return _p.mauve;
        case "lavender":  return _p.lavender;
        case "teal":      return _p.teal;
        case "green":     return _p.green;
        case "yellow":    return _p.yellow;
        case "peach":     return _p.peach;
        case "red":       return _p.red;
        case "pink":      return _p.pink;
        default:          return fallback !== undefined ? fallback : root.accent;
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
    // card, and text over a busy picture turned to mush. Then every surface is
    // solid, as a Mac's with Reduce Transparency.
    //
    // Two halves. What the settings allow (blur on, Reduce Transparency off):
    // the shell binds it from Settings, an app reads it from settings.json.
    property bool glassAllowed: true
    // Whether the compositor blurs at all: swayFX, which needs a GPU to run
    // (scenefx draws with GLES), so this is "a GPU" too. Assumed until sway
    // answers, so that a swayFX desktop does not flash solid as it starts.
    // The shell computed this and never used it; the apps never asked.
    readonly property bool compositorBlurs: Sway.compositorName === "" || Sway.swayfx
    readonly property bool translucent: glassAllowed && compositorBlurs
    // Popup panels cast a soft shadow (PanelShadow). Main.qml sets it where
    // the compositor keeps the blur off a shadow (swayfx 0009's
    // blur_ignore_alpha): elsewhere the blur would show through it as a
    // blurred halo round every panel.
    property bool panelShadows: false

    // How much of the wallpaper a glass panel lets through. 0.88 was glass in
    // name only: with the blur off on the shell's layers it read as a flat
    // dark panel. Behind a real blur (layer_effects in windowrules.conf) 0.7
    // keeps text readable over a bright sky and still shows what is behind.
    readonly property bool darkTheme: _lum(_col(text)) > _lum(_col(ground))
    readonly property color glassBg: tint(surface, translucent ? (increaseContrast ? 0.86 : darkTheme ? 0.70 : 0.66) : 1.0)
    // Cards sit on a glass panel, so their own glass adds to it: at 0.5 a
    // card on a 0.7 panel came out nearly opaque. A lighter film keeps them
    // distinct by their edge and a shade, as cards on a desktop's panels are.
    readonly property color glassCard: translucent ? tint(raised, 0.36) : raised
    readonly property color glassTile: translucent ? tint(raised, 0.32) : raised
    readonly property color glassBorder: tint(text, increaseContrast ? 0.32 : 0.12)
    // One light over the whole desktop, from above. Air, a flat sheet, takes
    // it on its top edge (glassEdge); glass has a body, so it takes it on its
    // rim and gathers it inside the edge facing away, as a drop of water
    // does (glassRim, LiquidGlass.caustic). One amount for both, so a pane
    // and a capsule on it are lit by the same sun: the capsules' rim was
    // 0.3 in either theme while the panes' edge was 0.1 in the dark one.
    readonly property real light: translucent ? (darkTheme ? 0.10 : 0.55) : 0
    // The lit top edge of a pane of glass: a hairline lighter than the border.
    readonly property color glassEdge: translucent ? tint("#ffffff", light) : "transparent"
    readonly property real glassRim: 0.15 + 0.45 * light
    // Light passes through: the dark theme's glass is lit at its foot
    // nearly as the light one's, though its panes' edge is dimmer.
    readonly property real glassCaustic: translucent ? 0.5 + 0.5 * light : 0
    // An app's sidebar: the desktop through it, blurred, as a desktop's own
    // sidebars are. The rest of an app window is glassBg, the same pane as
    // the shell's popups: a window and the Control Center are one material.
    // A recess in a glass panel — a search field, an icon well, a day of the
    // calendar: a lighter pane of the glass. Design.sunken there was a black
    // hole cut through it.
    // Solid (no blur, Reduce Transparency), the same lighter step on the
    // card it is mostly set in, made opaque: sunken there was the darkest
    // colour of the palette, a black hole in every card where a field sat.
    readonly property color well: translucent ? tint(text, 0.07) : Qt.tint(raised, tint(text, 0.06))
    // A lighter film on the window's glass, as a Mac's sidebar is the more
    // see-through of the two: a darker layer here made every sidebar a
    // slab beside a lighter page.
    readonly property color glassSidebar: translucent ? tint(raised, 0.30) : raised
    // A toolbar's glass at rest, over the bare window: the same film as the
    // sidebar a step lighter — the Air the window is made of, not a darker
    // pill laid on it. Over content it takes a body (Ui/ToolbarGlass).
    // Lighter than the window in either theme: in the dark one a film of
    // its cards' colour was still a darker, denser pill over the wallpaper
    // (more of a dark material), so there it is a veil of light instead.
    readonly property color glassFilm: !translucent ? raised : darkTheme ? tint(text, 0.08) : tint(raised, 0.42)
    // Hover/active variant. ClipboardPopup has referenced this since it was
    // written; undeclared, it evaluated to an invalid colour, so hovering a
    // clipboard card swapped its border for black instead of brightening it.
    readonly property color glassBorderStrong: tint(text, 0.22)
    readonly property color glassHover: stateHover
    readonly property color glassActive: stateSelected

    readonly property color veil: tint(text, 0.05)
    readonly property color veilStrong: tint(text, 0.10)
    readonly property color veilBold: tint(text, 0.16)

    // ── Semantic States & Highlights ─────────────────────────────────────────
    readonly property color focusRing: accent
    readonly property color separator: line
    readonly property color selection: tint(accent, 0.22)
    // Behind a modal: the window dimmed, not blacked out. One value for every
    // dialog; AppDialog had 0.25 and Git's own 0.45.
    readonly property color scrim: Qt.rgba(0, 0, 0, 0.25)
    // The states of anything that can be pointed at, pressed or chosen — a
    // row, a tile, a button without a fill of its own. These and nothing
    // else: written by hand, a selection came in fifteen strengths of the
    // accent and a hover in nine of the text, so two lists side by side
    // looked like two systems (tools/check-design.sh holds the line).
    // See-through fills, so a hover on glass is glass a shade lighter, not a
    // slab laid on it.
    readonly property color stateHover: tint(text, 0.07)
    readonly property color statePressed: tint(text, 0.12)
    // Chosen, quietly: a drop target, a hover over something chosen nearby,
    // a day with something in it.
    readonly property color stateSelectedSoft: tint(accent, 0.14)
    readonly property color stateSelected: selection
    // Chosen and pointed at, or chosen and focused.
    readonly property color stateSelectedStrong: tint(accent, 0.32)
    // The edge of something chosen, or of a place to drop.
    readonly property color accentLine: tint(accent, 0.45)
    // A control with a fill of its own (a secondary button, a stepper, a
    // toolbar cell): at rest, under the pointer, pressed. On glass a lighter
    // pane of it; on a solid window the raised surface and its steps.
    readonly property color controlFill: translucent ? well : raised
    readonly property color controlHover: translucent ? veilBold : hover
    readonly property color controlPressed: translucent ? tint(text, 0.20) : active
    // The same for what cannot be undone: under the pointer, pressed, its
    // edge. Five strengths of red were mixed by hand for these.
    readonly property color stateDanger: tint(danger, 0.20)
    readonly property color stateDangerPressed: tint(danger, 0.30)
    readonly property color dangerLine: tint(danger, 0.40)
    // Behind a line that reports a failure or a warning, a strip or a card.
    readonly property color dangerSoft: tint(danger, 0.14)
    readonly property color warnSoft: tint(warn, 0.14)
    readonly property real disabledOpacity: opacity.disabled

    // =========================================================================
    // TYPE & SHAPE
    // =========================================================================
    readonly property FontScale font: FontScale {}
    readonly property WeightScale weight: WeightScale {}
    readonly property RadiusScale radius: RadiusScale {}
    readonly property SpaceScale space: SpaceScale {}
    readonly property SizeScale size: SizeScale {}
    readonly property WidthScale width: WidthScale {}
    // An app window's first size, by how much it shows: compact (one document
    // or one table: Text, Term, Camera, Monitor), standard (View, Settings),
    // large (a sidebar, a list and a pane: Files, Git). Each app had its own
    // pair of numbers, seven sizes for three kinds of window.
    component WindowScale: QtObject {
        readonly property int compactWidth: 880
        readonly property int compactHeight: 580
        readonly property int standardWidth: 960
        readonly property int standardHeight: 640
        readonly property int largeWidth: 1120
        readonly property int largeHeight: 720
        readonly property int minWidth: 560
        readonly property int minHeight: 400
        readonly property int largeMinWidth: 760
        readonly property int largeMinHeight: 480
    }
    readonly property WindowScale window: WindowScale {}
    readonly property DurationScale duration: DurationScale {}
    readonly property SpringScale spring: SpringScale {}

    // ── Accessibility (HIG: Accessibility, Motion, Materials) ───────────────
    // Settings → Appearance → Accessibility, read here for the apps and bound
    // by the shell (Main.qml), as `translucent` is. Reduce Transparency is
    // `translucent: false` itself.
    // Reduce Motion: no springs, no scaling or elastic flex, no sliding;
    // what changes, fades.
    property bool reduceMotion: false
    // Increase Contrast: firmer edges, denser glass, secondary text at 7:1.
    property bool increaseContrast: false
    readonly property OpacityScale opacity: OpacityScale {}
    readonly property ShadowSpec shadow: ShadowSpec {}

    readonly property int border: 1
    readonly property int focusWidth: 2   // the keyboard focus outline
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
    Component.onCompleted: {
        if (!root.loadActiveTheme()) root.applyPalette(root.builtinPalette);
        root.loadGlassSetting();
    }

    // The apps follow Settings' "Window Blur" too: without a blur behind it a
    // see-through sidebar shows the wallpaper sharp, which is worse than an
    // opaque one. The shell binds `translucent` itself (Main.qml); this is
    // for the apps, read once, like the theme.
    function loadGlassSetting() {
        const xhr = new XMLHttpRequest();
        try {
            xhr.open("GET", StandardPaths.writableLocation(StandardPaths.HomeLocation) + "/.config/sway/settings.json", false);
            xhr.send();
            if (xhr.responseText) {
                const s = JSON.parse(xhr.responseText);
                root.glassAllowed = !(s.blurEnabled === false || s.reduceTransparency === true);
                root.reduceMotion = s.reduceMotion === true;
                root.increaseContrast = s.increaseContrast === true;
            }
        } catch (e) {}
    }

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
}
