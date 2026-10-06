import QtQuick
import QtQuick.Controls

// =============================================================================
// The scrollbar a scrolling surface needs, and half of them forgot.
//
// A list or grid that overflows with no bar shows a card sliced off by the
// panel edge and nothing at all saying there is more below. That does not read
// as "scroll me", it reads as a rendering fault — and four surfaces had exactly
// it: the Control Center, the Launchpad grid, the clipboard list and the media
// popup, each with its own inline bar or none.
//
// Visible for as long as anything is below the fold, rather than fading out
// when idle, because being seen is the entire job.
//
//   ListView   { ScrollBar.vertical: OverflowBar {} }
//   Flickable  { ScrollBar.vertical: OverflowBar {} }
//   ScrollView { id: sv; ScrollBar.vertical: OverflowBar { view: sv } }
//
// A ScrollView does not place a bar it is given (a ListView does): without
// `view` it sat at the view's top-left corner, a sliver drawn over the
// first card, nowhere near the right edge where it could be dragged.
// =============================================================================

ScrollBar {
    id: root

    active: true

    // The ScrollView this bar belongs to, for it to stand at its right edge.
    property Item view: null
    Binding { when: root.view !== null; target: root; property: "parent"; value: root.view }
    Binding { when: root.view !== null; target: root; property: "x"
              value: root.view ? (root.view.mirrored ? 0 : root.view.width - root.width) : 0 }
    Binding { when: root.view !== null; target: root; property: "y"; value: root.view ? root.view.topPadding : 0 }
    Binding { when: root.view !== null; target: root; property: "height"; value: root.view ? root.view.availableHeight : 0 }

    // `size` is the fraction of the content currently on screen, so anything
    // below 1 means there is more of it. Works the same for a ListView, a
    // GridView and a bare Flickable, and needs nothing measured by hand.
    policy: (root.size > 0 && root.size < 1) ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff

    // 4px of a light outline colour, not 3px of a mid grey at 0.6 alpha:
    // measured against the panel that drew #394E62 on #0A3B4C, a difference
    // nobody notices — which is the same as not being there, for a control
    // whose only job is to be noticed.
    // Something to take hold of: 4px drawn, but the bar answers the pointer
    // across its padding as well, and grows while the pointer is on it. At
    // 4px and nothing around it, dragging it meant finding a 4px target.
    hoverEnabled: true
    padding: Design.s(3)
    minimumSize: 0.08

    contentItem: Rectangle {
        implicitWidth: root.hovered || root.pressed ? Design.s(8) : Design.s(4)
        implicitHeight: implicitWidth
        radius: width / 2
        color: root.pressed ? Design.textDim : Design.textFaint
        opacity: root.hovered || root.pressed ? 1.0 : 0.8
        Behavior on implicitWidth { NumberAnimation { duration: Design.duration.fast } }
    }
}
