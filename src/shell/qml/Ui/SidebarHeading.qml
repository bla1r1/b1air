import QtQuick
import QtQuick.Layouts

// "PLACES", "DEVICES", "PERSONALIZATION": a section label in a sidebar, with
// an optional small action at the right (a + to add a bookmark).
Item {
    id: root
    property alias text: label.text
    property string action: ""
    property string actionTip: ""
    signal actionClicked()
    implicitHeight: Design.s(32)
    Layout.fillWidth: true

    Label {
        id: label
        anchors.left: parent.left
        anchors.leftMargin: Design.s(Design.space.sm)
        anchors.right: btn.visible ? btn.left : parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Design.s(Design.space.xs)
        role: "caption"
        weight: Design.weight.semibold
        color: Design.textFaint
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 0.6
        elide: Text.ElideRight
    }
    BarButton {
        id: btn
        visible: root.action !== ""
        anchors.right: parent.right
        anchors.verticalCenter: label.verticalCenter
        small: true
        glyph: root.action
        tip: root.actionTip
        onClicked: root.actionClicked()
    }
}
