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
        saturation: 0.3
        brightness: Design.darkTheme ? -0.12 : 0.1
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
        property var source: blurredTex
        property size size: Qt.size(width, height)
        property real pad: root.pad
        property real full: root.barHeight * 0.7
        // Under the blurred copy, mostly hiding the sharp content there.
        property color base: Design.tint(Design.surface, 0.85)
        fragmentShader: "shaders/edge.frag.qsb"
    }

    // Without effects: an opaque bar and its hairline.
    Rectangle {
        visible: !root.effects
        width: parent.width
        height: root.barHeight
        color: Design.surface
        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: Design.border
            color: Design.separator
        }
    }
}
