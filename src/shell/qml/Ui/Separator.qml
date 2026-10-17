import QtQuick
import QtQuick.Layouts

// =============================================================================
// A hairline between groups of rows, in a layout: Rectangle { height: 1 } was
// written out by hand wherever one was wanted, each with its own colour.
//
//   Separator { inset: Design.s(Design.space.sm) }
// =============================================================================

Rectangle {
    // Room on each side, and above and below.
    property real inset: 0
    property real gap: 0

    Layout.fillWidth: true
    Layout.preferredHeight: 1
    Layout.leftMargin: inset
    Layout.rightMargin: inset
    Layout.topMargin: gap
    Layout.bottomMargin: gap
    implicitHeight: 1
    color: Design.separator
}
