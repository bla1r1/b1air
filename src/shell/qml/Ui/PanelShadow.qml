import QtQuick

// =============================================================================
// The soft shadow round a popup panel, drawn by the shell on its full-screen
// layer: a stack of rounded rings outside the panel, each fainter than the
// last. Rectangles, not an effect: the same on the GPU and the software
// renderer, and nothing to compute per frame.
//
// Nothing is drawn under the panel itself — the panel is glass, and a shadow
// behind it would darken it — and nothing here is more than 40% opaque: the
// compositor's blur_ignore_alpha 0.4 (swayfx 0009) keeps the blur off the
// shadow and under the panel alone. Without that patch the daemon does not
// set it, and Main.qml leaves this off (Design.panelShadows).
//
//   PanelShadow { anchors.fill: panel; radius: panel.radius }
// =============================================================================

Item {
    id: root

    property real radius: 0
    // How far it reaches, and how dark it starts at the panel's edge.
    property real spread: Design.s(Design.space.xl)
    property real strength: Design.darkTheme ? 0.22 : 0.12
    // A light from above: the shadow reaches further below than above.
    property real drop: Design.s(Design.space.xs)

    readonly property int rings: 12

    Repeater {
        model: root.rings

        Rectangle {
            required property int index
            // The ring's share of the spread, and how much of it is left:
            // quadratic falloff, which reads as soft rather than as a halo.
            readonly property real step: root.spread / root.rings
            readonly property real t: (index + 1) / root.rings

            x: -step * (index + 1)
            y: -step * (index + 1) + root.drop * t
            width: root.width + 2 * step * (index + 1)
            height: root.height + 2 * step * (index + 1)
            radius: root.radius + step * (index + 1)
            color: "transparent"
            border.width: step
            border.color: Qt.rgba(0, 0, 0, Math.min(0.4, root.strength * (1 - t) * (1 - t)))
            antialiasing: true
        }
    }
}
