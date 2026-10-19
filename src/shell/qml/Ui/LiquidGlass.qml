import QtQuick
import QtQuick.Effects

// =============================================================================
// Liquid glass over `backdrop`, after Apple's Human Interface Guidelines
// (Materials, Color, Motion) — shaders/liquid.frag.
//
//   variant "regular"  bars, sidebars, popovers, anything with text on it:
//                      blurred, its luminosity held in a range so text reads.
//   variant "clear"    controls with little text over photos and video:
//                      highly translucent, dimmed 35% over something bright.
//   standard: true     the content layer, where Apple says no Liquid Glass:
//                      blur only — no lensing, no light on the edge.
//
// Only for the functional layer, and sparingly (HIG: Materials). Pressed, it
// flexes and lights from within, from under the pointer outward. Labels on
// it are monochrome and turn dark over something light (shaders/labels.frag).
//
// `backdrop` is what the glass shows: an item it is not inside of — a glass
// that showed its own parent would show itself. Without a GPU (Qt's software
// renderer draws no shaders), or with Reduce Transparency or the blur off
// (Design.translucent), it is the flat pane the apps had.
//
//   LiquidGlass { backdrop: content; width: 300; height: Design.s(Design.size.rowTall) }
// =============================================================================

Item {
    id: g

    property Item backdrop
    // With nothing under it to bend (no backdrop), the plain capsule: the
    // shader drew from an empty source there.
    property bool effects: GraphicsInfo.api !== GraphicsInfo.Software && Design.translucent && backdrop !== null
    property string variant: "regular"
    property bool standard: false
    property real radius: height / 2
    property real refraction: standard ? 0 : Design.s(Design.space.md + Design.space.xxs)
    property real bevel: Math.min(Design.s(Design.space.md + Design.space.xxs), height / 2)
    property real rim: standard ? 0.12 : 0.5
    // The light gathered at its foot (shaders/liquid.frag): glass has a body.
    property real caustic: standard ? 0 : Design.glassCaustic
    property real dispersion: 0.08
    property real blur: variant === "regular" ? 0.55 : 0.1
    property real vibrancy: 0.4
    // How far the luminosity of what is behind is held in a range (the
    // regular variant's): a glass at rest over the window's own Air holds
    // nothing, or it is a darker pill on it (Ui/ToolbarGlass).
    property real hold: variant === "regular" || standard ? 1 : 0
    property color tint: Design.tint(Design.text, 0.03)
    property real shadow: standard ? 0 : 0.25
    property bool adaptiveLabels: true
    // The pane without effects: the panels' own glass colour.
    property color plainColor: Design.glassBg
    default property alias content: inner.data

    // Pressed: it flexes — not under Reduce Motion, which takes the elastic
    // properties away — and lights from within.
    property bool pressed: false
    property point pressPoint: Qt.point(width / 2, height / 2)
    property real glow: pressed ? 1 : 0
    Behavior on glow { NumberAnimation { duration: g.pressed ? Design.duration.fast / 2 : Design.duration.slow; easing.type: Easing.OutCubic } }
    property real flex: 1.035
    scale: pressed && !Design.reduceMotion ? flex : 1
    Behavior on scale {
        enabled: !Design.reduceMotion
        SpringAnimation { spring: Design.spring.bouncy.spring; damping: Design.spring.bouncy.damping; epsilon: 0.0005 }
    }

    // Coming and going: the lensing grows in rather than the pane fading.
    property real presence: 1
    Behavior on presence { NumberAnimation { duration: Design.reduceMotion ? 0 : Design.duration.slow; easing.type: Easing.OutCubic } }
    opacity: Math.min(1, presence * 1.6)

    // What is behind is taken and blurred with this much more on every side,
    // so the blur has something to reach into at the edge (it went dark there).
    readonly property real pad: Design.s(Design.space.xxl)

    ShaderEffectSource {
        id: under
        visible: false
        sourceItem: g.effects ? g.backdrop : null
        live: true
        width: g.width + 2 * g.pad
        height: g.height + 2 * g.pad
    }
    // Where the glass is over the backdrop: worked out when it or the
    // backdrop moves or changes size. Every frame only while `tracking` —
    // set it while the glass is dragged or animated from outside (an
    // ancestor moving does not reach the handlers here); a FrameAnimation
    // left running kept the window drawing sixty times a second at rest.
    property bool tracking: false
    function place() {
        if (!g.effects || !g.backdrop) return;
        const p = g.backdrop.mapFromItem(g, 0, 0);
        under.sourceRect = Qt.rect(p.x - g.pad, p.y - g.pad, g.width + 2 * g.pad, g.height + 2 * g.pad);
    }
    onXChanged: place()
    onYChanged: place()
    onWidthChanged: place()
    onHeightChanged: place()
    onEffectsChanged: place()
    onBackdropChanged: place()
    Component.onCompleted: place()
    Connections {
        target: g.backdrop
        function onXChanged() { g.place(); }
        function onYChanged() { g.place(); }
        function onWidthChanged() { g.place(); }
        function onHeightChanged() { g.place(); }
    }
    FrameAnimation {
        running: g.tracking && g.effects && g.visible && g.backdrop !== null
        onTriggered: g.place()
    }
    MultiEffect {
        id: frosted
        visible: false
        width: under.width
        height: under.height
        source: under
        autoPaddingEnabled: false
        blurEnabled: g.blur > 0
        blur: g.blur
        blurMax: 32
        saturation: g.vibrancy
    }
    ShaderEffectSource {
        id: frostedTex
        visible: false
        sourceItem: g.effects ? frosted : null
        live: true
    }

    // The shadow: the shape blurred and dropped a little, cut away where the
    // glass is, so it never darkens the glass itself.
    readonly property real spread: Design.s(Design.space.lg + Design.space.xxs)
    Item {
        id: shadowShape
        visible: false
        x: -g.spread; y: -g.spread
        width: g.width + 2 * g.spread; height: g.height + 2 * g.spread
        layer.enabled: g.effects && g.shadow > 0
        Rectangle { x: g.spread; y: g.spread + Design.s(Design.space.xs); width: g.width; height: g.height; radius: g.radius; color: "black" }
    }
    Item {
        id: hole
        visible: false
        x: -g.spread; y: -g.spread
        width: shadowShape.width; height: shadowShape.height
        layer.enabled: g.effects && g.shadow > 0
        Rectangle { x: g.spread; y: g.spread; width: g.width; height: g.height; radius: g.radius; color: "white" }
    }
    MultiEffect {
        visible: g.effects && g.shadow > 0
        x: -g.spread; y: -g.spread
        width: shadowShape.width; height: shadowShape.height
        source: shadowShape
        autoPaddingEnabled: false
        blurEnabled: true
        blur: 1.0
        blurMax: 24
        maskEnabled: true
        maskInverted: true
        maskSource: hole
        opacity: g.shadow
    }

    ShaderEffect {
        anchors.fill: parent
        visible: g.effects
        property var source: frostedTex
        property size size: Qt.size(width, height)
        property real radius: Math.min(g.radius, width / 2, height / 2)
        property real refraction: g.refraction * g.presence
        property real bevel: g.bevel
        property real rim: g.rim
        property real dispersion: g.dispersion
        property real pad: g.pad
        property real regular: g.hold
        property real solid: 0
        property real contrast: Design.increaseContrast ? 1 : 0
        property real caustic: g.caustic
        property real glow: g.glow
        property point glowPos: g.pressPoint
        property color tint: g.tint
        property color base: Design.surface
        fragmentShader: "shaders/liquid.frag.qsb"
    }

    // Without effects: the flat pane.
    Rectangle {
        anchors.fill: parent
        visible: !g.effects
        radius: g.radius
        color: g.plainColor
        border.width: Design.border
        border.color: Design.glassBorder
    }

    Item {
        id: inner
        anchors.fill: parent
        layer.enabled: g.effects && g.adaptiveLabels
        layer.effect: ShaderEffect {
            property var behind: frostedTex
            property size size: Qt.size(g.width, g.height)
            property real pad: g.pad
            property real amount: 1
            fragmentShader: "shaders/labels.frag.qsb"
        }
    }
}
