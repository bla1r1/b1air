import QtQuick
import QtQuick.Effects

// =============================================================================
// The scroll edge effect, under a toolbar that content scrolls beneath
// (HIG: Toolbars, Materials). No bar of its own: what is under it is blurred
// and dimmed most at the window's edge and fades out below the toolbar, with
// no line where it stops — the toolbar's controls float on the content.
//
// `backdrop` is the content that scrolls under, an item this is not inside
// of; `barHeight` the toolbar's, under which it stays full. Without a GPU
// (Qt's software renderer draws no shaders), with Reduce Transparency or with
// the blur off (Design.translucent), it is an opaque bar with a hairline, so
// the controls never sit on bare content.
//
//   ScrollEdge { anchors.top: parent.top; width: parent.width; backdrop: content; barHeight: toolbar.height }
// =============================================================================

Item {
    id: root

    property Item backdrop
    property real barHeight: 0
    // What scrolls under it, if it is one view: the edge (or, without
    // effects, the bar's fill) then shows only once something is scrolled
    // beneath it, as a Mac's toolbar shows its material only over content.
    // An item that is not a Flickable (a fixed layout) is never scrolled
    // under it.
    property Item flick: null
    readonly property bool scrolledUnder: !root.flick ? true
                                        : root.flick.atYBeginning === undefined ? false
                                        : !root.flick.atYBeginning
    readonly property bool effects: GraphicsInfo.api !== GraphicsInfo.Software
                                    && Design.translucent && root.backdrop !== null

    height: root.barHeight + Design.s(Design.space.xxl)

    // Taken and blurred with this much more on every side, so the blur does
    // not fade dark at the edges of what it was given.
    readonly property real pad: Design.s(Design.space.xxl * 2)

    ShaderEffectSource {
        id: under
        visible: false
        sourceItem: root.effects ? root.backdrop : null
        live: true
        width: root.width + 2 * root.pad
        height: root.height + 2 * root.pad
    }
    // Where this sits over the backdrop, in its coordinates. Worked out when
    // either moves or changes size, not every frame: a FrameAnimation here
    // kept the window drawing sixty times a second while nothing changed.
    // (What scrolls under it is the backdrop's own business: `live` above
    // redraws the copy when its content does.)
    function place() {
        if (!root.effects) return;
        const p = root.backdrop.mapFromItem(root, 0, 0);
        under.sourceRect = Qt.rect(p.x - root.pad, p.y - root.pad, root.width + 2 * root.pad, root.height + 2 * root.pad);
    }
    onXChanged: place()
    onYChanged: place()
    onWidthChanged: place()
    onHeightChanged: place()
    onEffectsChanged: place()
    Component.onCompleted: place()
    Connections {
        target: root.backdrop
        function onXChanged() { root.place(); }
        function onYChanged() { root.place(); }
        function onWidthChanged() { root.place(); }
        function onHeightChanged() { root.place(); }
    }
    MultiEffect {
        id: blurred
        visible: false
        width: under.width
        height: under.height
        source: under
        autoPaddingEnabled: false
        blurEnabled: true
        blur: 1.0
        blurMax: 48
        saturation: 0.6
        brightness: Design.darkTheme ? -0.05 : 0.1
    }
    ShaderEffectSource {
        id: blurredTex
        visible: false
        sourceItem: root.effects ? blurred : null
        live: true
    }
    ShaderEffect {
        anchors.fill: parent
        visible: root.effects
        // Only over something: with nothing scrolled under the toolbar it
        // was a dark band across the top of an empty window.
        opacity: root.scrolledUnder ? 1 : 0
        Behavior on opacity { enabled: !Design.reduceMotion; NumberAnimation { duration: Design.duration.fast } }
        property var source: blurredTex
        property size size: Qt.size(width, height)
        property real pad: root.pad
        property real full: root.barHeight * 0.7
        // Under the blurred copy, hiding the sharp content there enough for
        // the toolbar's labels to read, and no more: what is under it still
        // shows, as through Air. At 0.85 with a darker blur it was a black
        // band across the top of every scrolled window.
        property color base: Design.tint(Design.surface, 0.65)
        fragmentShader: "shaders/edge.frag.qsb"
    }

    // Without effects: the window's own glass and a hairline — a pane of the
    // same material as the window, not a darker slab across it (opaque
    // where the window is, with Reduce Transparency or the blur off).
    Box {
        visible: !root.effects
        width: parent.width
        height: root.barHeight
        color: Design.glassBg
        opacity: root.scrolledUnder ? 1 : 0
        Behavior on opacity { enabled: !Design.reduceMotion; NumberAnimation { duration: Design.duration.fast } }
        Box {
            anchors.bottom: parent.bottom
            width: parent.width
            height: Design.border
            color: Design.separator
        }
    }
}
