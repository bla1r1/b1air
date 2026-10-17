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
    property real diameter: Design.size.iconBtn

    property color tone: Design.textDim
    property color hoverTone: Design.accent
    property color fill: Design.hover
    property bool bordered: false

    signal clicked()

    implicitWidth: Design.s(root.diameter)
    implicitHeight: implicitWidth

    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: ma.pressed ? Design.veilBold : ma.containsMouse ? root.fill : "transparent"
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

    Clickable { id: ma; onClicked: root.clicked() }
}
