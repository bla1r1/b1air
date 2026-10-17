import QtQuick

// A glass circle with an icon, and a word under it (macOS's Sleep, Restart,
// Shut Down).
Item {
    id: button
    property string icon: ""
    property string label: ""
    property real u: 1
    signal clicked

    implicitWidth: Math.max(circle.width, word.implicitWidth)
    implicitHeight: circle.height + 8 * u + word.implicitHeight

    Glass {
        id: circle
        anchors.horizontalCenter: parent.horizontalCenter
        width: 44 * button.u
        height: width
        radius: width / 2
        level: mouse.pressed ? 0.36 : mouse.containsMouse ? 0.28 : 0.16
        Glyph { anchors.centerIn: parent; name: button.icon; size: 19 * button.u }
    }
    Text {
        id: word
        anchors.top: circle.bottom
        anchors.topMargin: 8 * button.u
        anchors.horizontalCenter: parent.horizontalCenter
        text: button.label
        color: "white"
        opacity: mouse.containsMouse ? 1 : 0.85
        font.family: "Inter"
        font.pixelSize: 12 * button.u
        style: Text.Raised
        styleColor: "#40000000"
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: button.clicked()
    }
}
