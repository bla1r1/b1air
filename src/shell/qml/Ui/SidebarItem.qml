import QtQuick
import QtQuick.Layouts

// One row of a sidebar: icon, label, optional detail line and badge, and a
// slot at the right for small buttons (unmount, remove). Selected rows take
// the accent, as everywhere; Settings used each page's own colour, so the
// highlight was green on one page and pink on the next.
Rectangle {
    id: root
    property string label: ""
    property string glyph: ""
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
    implicitHeight: Design.s(detail !== "" ? 42 : 36)
    radius: Design.s(Design.radius.ctl)
    color: active ? Design.tint(Design.accent, 0.22)
         : highlight ? Design.tint(Design.accent, 0.14)
         : ma.containsMouse ? Design.hover : "transparent"
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
            Layout.preferredWidth: Design.s(22)
            text: root.glyph
            font.family: Design.font.icon
            font.pixelSize: Design.s(17)
            color: root.active ? Design.accent : Design.textDim
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
            implicitWidth: badgeText.implicitWidth + Design.s(12)
            implicitHeight: Design.s(20)
            radius: height / 2
            color: Design.raised
            Text {
                id: badgeText
                anchors.centerIn: parent
                text: root.badge
                font.family: Design.font.sans
                font.pixelSize: Design.s(Design.font.caption)
                color: Design.textDim
            }
        }
        Row { id: trail; spacing: Design.s(2) }
    }
}
