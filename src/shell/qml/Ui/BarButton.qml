import QtQuick
import QtQuick.Controls as C

// A toolbar button: an icon, optionally a label, a tooltip. The apps each had
// their own — 24px squares with 12px glyphs in one, bare MouseAreas over Text
// in another — so the same action looked different in every window.
Rectangle {
    id: root
    property string glyph: ""
    property string label: ""
    property string tip: ""
    property bool checked: false
    property bool small: false
    property bool danger: false
    property bool primary: false
    readonly property bool hovered: ma.containsMouse
    signal clicked()

    implicitHeight: Design.s(small ? 26 : 34)
    implicitWidth: label ? row.implicitWidth + Design.s(22) : implicitHeight
    radius: Design.s(Design.radius.ctl)
    opacity: enabled ? 1.0 : 0.38
    color: primary ? (ma.containsMouse ? Qt.lighter(Design.accent, 1.1) : Design.accent)
         : checked ? Design.tint(Design.accent, 0.22)
         : ma.containsMouse ? (danger ? Design.tint(Design.danger, 0.18) : Design.hover)
         : (label ? Design.raised : "transparent")

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Design.s(Design.space.xs + 2)
        Text {
            visible: root.glyph !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: root.glyph
            font.family: Design.font.icon
            font.pixelSize: Design.s(root.small ? 14 : 17)
            color: root.primary ? Design.accentText : root.danger ? Design.danger
                 : root.checked ? Design.accent : Design.text
        }
        Text {
            visible: root.label !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: root.label
            font.family: Design.font.sans
            font.pixelSize: Design.s(Design.font.body)
            font.weight: root.primary ? Design.weight.semibold : Design.weight.regular
            color: root.primary ? Design.accentText : root.danger ? Design.danger : Design.text
        }
    }
    MouseArea {
        id: ma
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
    C.ToolTip.visible: root.tip !== "" && ma.containsMouse
    C.ToolTip.delay: 600
    C.ToolTip.text: root.tip
}
