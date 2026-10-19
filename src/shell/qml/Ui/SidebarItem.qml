import QtQuick
import B1air.Daemon
import QtQuick.Layouts

// One row of a sidebar: icon, label, optional detail line and badge, and a
// slot at the right for small buttons (unmount, remove). Selected rows take
// the accent, as everywhere; Settings used each page's own colour, so the
// highlight was green on one page and pink on the next.
Rectangle {
    id: root
    property string label: ""
    property string glyph: ""
    // The glyph's colour when not active: a tag's colour, say.
    property color glyphColor: Design.textDim
    // Keep glyphColor when active too (a tag's colour is what it is).
    property bool keepGlyphColor: false
    property string detail: ""
    property string badge: ""
    property bool active: false
    property bool highlight: false        // e.g. a drag hovering over it
    readonly property bool hovered: ma.containsMouse
    default property alias trailing: trail.data
    // Things that cover the whole row (a DropArea), not the button slot.
    property alias overlay: overlayItem.data
    signal clicked()

    Layout.fillWidth: true
    implicitHeight: Design.s(detail !== "" ? Design.size.row + Design.space.xxs : Design.size.md + Design.space.xs)
    // Its container's corner rule (Shape, Design.corner), else its own.
    radius: Design.corner(Shape.radius, Design.s(Design.radius.ctl))
    color: active ? Design.stateSelected
         : highlight ? Design.stateSelectedSoft
         : ma.containsMouse ? Design.stateHover : "transparent"
    Behavior on color { ColorAnimation { duration: Design.duration.fast } }

    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
    Item { id: overlayItem; anchors.fill: parent }
    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Design.s(Design.space.sm)
        anchors.rightMargin: Design.s(Design.space.xs)
        spacing: Design.s(Design.space.sm)
        Text {
            Layout.preferredWidth: Design.s(Design.size.mini)
            text: root.glyph
            font.family: Design.font.icon
            font.pixelSize: Design.s(Design.font.glyph)
            color: root.active && !root.keepGlyphColor ? Design.accent : root.glyphColor
            horizontalAlignment: Text.AlignHCenter
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            Label {
                Layout.fillWidth: true
                text: root.label
                elide: Text.ElideRight
                weight: root.active ? Design.weight.semibold : Design.weight.regular
                color: root.active ? Design.text : Design.text
            }
            Label { visible: root.detail !== ""; text: root.detail; role: "caption"; color: Design.textFaint }
        }
        Rectangle {
            visible: root.badge !== ""
            implicitWidth: badgeText.implicitWidth + Design.s(Design.space.md)
            implicitHeight: Design.s(Design.size.mini)
            radius: height / 2
            color: Design.well
            Text {
                id: badgeText
                anchors.centerIn: parent
                text: root.badge
                font.family: Design.font.sans
                font.pixelSize: Design.s(Design.font.caption)
                color: Design.textDim
            }
        }
        Row { id: trail; spacing: Design.s(Design.space.xxs) }
    }

    // Tab reaches it; Enter and Space do what a click does.
    activeFocusOnTab: true
    Keys.onReturnPressed: event => { root.clicked(); event.accepted = true; }
    Keys.onSpacePressed: event => { root.clicked(); event.accepted = true; }
    Accessible.role: Accessible.PageTab
    Accessible.name: root.label
    FocusRing { target: root }
}
