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

    // On its own (not in a BarGroup) a labelled button gets the capsule
    // fill itself, so it reads as a button and not as text.
    property bool grouped: false        // set by BarGroup
    readonly property bool standalone: label !== "" && !grouped

    implicitHeight: Design.s(small ? 26 : 30)
    implicitWidth: label ? (glyphText.visible ? glyphText.implicitWidth + row.spacing : 0) + labelText.implicitWidth + Design.s(24) : implicitHeight + Design.s(4)
    radius: height / 2
    opacity: enabled ? 1.0 : 0.38
    color: primary ? (ma.containsMouse ? Qt.lighter(Design.accent, 1.1) : Design.accent)
         : checked ? Design.tint(Design.accent, 0.24)
         : ma.containsMouse ? (danger ? Design.tint(Design.danger, 0.18) : Design.hover)
         : standalone ? Design.raised : "transparent"
    Behavior on color { ColorAnimation { duration: Design.duration.fast } }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: Design.s(Design.space.xs + 2)
        Text {
            id: glyphText
            visible: root.glyph !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: root.glyph
            font.family: Design.font.icon
            font.pixelSize: Design.s(root.small ? 14 : 16)
            color: root.primary ? Design.accentText : root.danger ? Design.danger
                 : root.checked ? Design.accent : Design.text
        }
        Text {
            id: labelText
            visible: root.label !== ""
            anchors.verticalCenter: parent.verticalCenter
            // Squeezed by its layout, the label shortens instead of
            // running out over the capsule's edges.
            width: Math.min(implicitWidth, Math.max(0, root.width - Design.s(24)
                                                   - (glyphText.visible ? glyphText.implicitWidth + row.spacing : 0)))
            elide: Text.ElideRight
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
    // A shortened label still says the whole thing on hover.
    C.ToolTip.visible: (root.tip !== "" || labelText.truncated) && ma.containsMouse
    C.ToolTip.delay: 600
    C.ToolTip.text: root.tip !== "" ? root.tip : root.label
}
