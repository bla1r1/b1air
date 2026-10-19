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
    radius: height / 2
    // What lies on it is concentric with it (Ui/ToolbarGroup sets the inset).
    Shape.radius: radius
    variant: "regular"
    refraction: Design.s(Design.space.sm)
    bevel: Math.min(Design.s(Design.space.sm + Design.space.xxs), height / 2)
    rim: 0.4
    shadow: 0.18
    blur: 0.85
    tint: Design.tint(Design.surface, 0.5)
    adaptiveLabels: false
    plainColor: Design.glassCard
}
