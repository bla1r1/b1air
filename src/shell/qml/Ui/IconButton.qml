import QtQuick

// =============================================================================
// Round icon button — back arrows, the gear, media transport.
//
// Every one of these was a Rectangle with `width: Design.s(28)` sitting inside
// a RowLayout. A layout owns its children's geometry: it overwrites width and
// height with the implicit ones, which on a bare Rectangle are zero. They were
// being drawn at whatever the layout felt like, never at 28.
//
//   IconButton { icon: "\u{f004d}"; onClicked: root.backClicked() }
// =============================================================================

Item {
    id: root

    property string icon: ""
    property string role: "body"
    property real diameter: Design.size.sm

    property color tone: Design.textDim
    // Brighter under the pointer, not another colour: a hover is not a
    // choice, and the accent is kept for what is chosen.
    property color hoverTone: Design.text
    property color fill: Design.stateHover
    // What it does, for a screen reader and the tooltip-less: the glyph says
    // nothing aloud.
    property string label: ""
    property bool bordered: false

    readonly property bool hovered: ma.containsMouse
    signal clicked()

    implicitWidth: Design.s(root.diameter)
    implicitHeight: implicitWidth

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: ma.pressed ? Design.statePressed : ma.containsMouse ? root.fill : "transparent"
        border.color: (root.bordered && ma.containsMouse) ? Design.glassBorder : "transparent"
        border.width: Design.border

        Behavior on color { ColorAnimation { duration: Design.duration.fast } }
        Behavior on border.color { ColorAnimation { duration: Design.duration.fast } }

        Icon {
            anchors.centerIn: parent
            text: root.icon
            role: root.role
            color: ma.containsMouse ? root.hoverTone : root.tone
            Behavior on color { ColorAnimation { duration: Design.duration.fast } }
        }
    }

    Clickable { id: ma; keyboard: false; onClicked: root.clicked() }

    // Tab reaches it; Enter and Space do what a click does.
    activeFocusOnTab: root.enabled
    Keys.onReturnPressed: event => { root.clicked(); event.accepted = true; }
    Keys.onSpacePressed: event => { root.clicked(); event.accepted = true; }
    Accessible.role: Accessible.Button
    Accessible.name: root.label !== "" ? root.label : root.icon
    FocusRing { target: root; cornerRadius: root.width / 2 + Design.s(Design.space.xxs) }
}
