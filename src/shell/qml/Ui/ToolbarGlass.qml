import QtQuick
import B1air.Daemon

// =============================================================================
// The glass of a Mac's toolbar controls (HIG: Toolbars): LiquidGlass tuned
// for a control that floats over content scrolling under the bar — thin,
// quiet, blurred well and washed with the surface, as it sees the content
// directly rather than the scroll edge it sits on (over a light picture it
// was a light spot on a dimmed bar). Ui/ToolbarGroup is buttons on it; a
// field, a path bar or a segmented control in a toolbar can lie on it too:
//
//   Field { color: "transparent"; ToolbarGlass { anchors.fill: parent; z: -1; backdrop: content } }
// =============================================================================

LiquidGlass {
    id: tg
    radius: height / 2
    // What lies on it is concentric with it (Ui/ToolbarGroup sets the inset).
    Shape.radius: radius

    // Air is the surface, glass the tool: over the bare window (the Air the
    // window is made of) it is a light film of it with a lit rim, nothing
    // to bend and no shadow — glass on glass read as a dark pill. Over
    // content scrolled under the toolbar it takes a body: it bends what is
    // under it and lifts off it. Followed from the AppToolbar it sits in
    // (`over`); `body` can be set where there is none.
    readonly property Item _bar: {
        let p = tg.parent;
        while (p && !p.isAppToolbar) p = p.parent;
        return p;
    }
    property real body: tg._bar && tg._bar.over ? 1 : 0
    Behavior on body { enabled: !Design.reduceMotion; NumberAnimation { duration: Design.duration.base; easing.type: Easing.OutCubic } }

    variant: "regular"
    refraction: Design.s(Design.space.sm) * tg.body
    bevel: Math.min(Design.s(Design.space.sm + Design.space.xxs), height / 2)
    // Lit by the light the window's panes are (Design.light); the light
    // gathered at its foot grows with its body.
    rim: Design.glassRim * (1 + 0.25 * tg.body)
    caustic: Design.glassCaustic * (0.6 + 0.4 * tg.body)
    hold: tg.body
    shadow: 0.18 * tg.body
    blur: 0.85
    // From the film at rest to the glass's own darker tint over content,
    // so what is under it does not take the labels' contrast.
    tint: Qt.rgba(Design.glassFilm.r + (_deep.r - Design.glassFilm.r) * tg.body,
                  Design.glassFilm.g + (_deep.g - Design.glassFilm.g) * tg.body,
                  Design.glassFilm.b + (_deep.b - Design.glassFilm.b) * tg.body,
                  Design.glassFilm.a + (_deep.a - Design.glassFilm.a) * tg.body)
    // At 0.5 the capsules were dark pills over a scrolled list; the scroll
    // edge under them already dims what they show.
    readonly property color _deep: Design.tint(Design.surface, 0.4)
    adaptiveLabels: false
    plainColor: Design.glassFilm
}
