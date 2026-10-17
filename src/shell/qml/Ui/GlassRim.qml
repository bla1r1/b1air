import QtQuick
import QtQuick.Effects

// =============================================================================
// The edge of a pane of glass, as light catches it: a hairline bright along
// the top that fades down the sides, a dark outline outside it that lifts the
// pane off what is behind, and a faint sheen across the top. A flat grey
// 1 px border on every panel was what made the glass read as a template.
//
//   Rectangle { radius: …; color: Design.glassBg
//       GlassRim { radius: parent.radius } }
// =============================================================================

Item {
    id: root

    property real radius: 0
    // The sheen is for panes you look into (popups, windows); a small pane
    // (a bar island, a tile) keeps only the rim.
    property bool sheen: true

    anchors.fill: parent
    visible: Design.translucent

    // The sheen: light from above, gone a third of the way down.
    Rectangle {
        visible: root.sheen
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: parent.height * 0.35
        radius: root.radius
        gradient: Gradient {
            GradientStop { position: 0.0; color: Design.glassSheen }
            GradientStop { position: 1.0; color: Qt.alpha(Design.glassSheen, 0) }
        }
    }

    // The outermost hairline is dark, so a light pane over a light sky
    // still has an edge; the lit rim runs just inside it.
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: "transparent"
        border.width: Design.border
        border.color: Design.glassOutline
    }

    // The rim itself: the ring is the mask, the gradient its light.
    Rectangle {
        id: ring
        anchors.fill: parent
        anchors.margins: Design.border
        radius: Math.max(0, root.radius - Design.border)
        color: "transparent"
        border.width: Design.border
        border.color: "white"
        visible: false
        layer.enabled: true
    }
    Rectangle {
        id: light
        anchors.fill: ring
        visible: false
        layer.enabled: true
        gradient: Gradient {
            GradientStop { position: 0.0; color: Design.glassRimTop }
            GradientStop { position: 0.45; color: Design.glassRimBottom }
            GradientStop { position: 1.0; color: Design.glassRimBottom }
        }
    }
    MultiEffect {
        anchors.fill: ring
        source: light
        maskEnabled: true
        maskSource: ring
    }
}
