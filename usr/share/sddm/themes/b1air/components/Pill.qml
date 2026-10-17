import QtQuick

// A glass pill of an icon and a word, as on the lock screen's corners.
Glass {
    id: pill
    property string icon: ""
    property string text: ""
    property real u: 1
    property bool active: false
    signal clicked

    implicitWidth: row.implicitWidth + 28 * u
    implicitHeight: 34 * u
    radius: height / 2
    level: mouse.pressed || active ? 0.32 : mouse.containsMouse ? 0.26 : 0.16

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 7 * pill.u
        Glyph { anchors.verticalCenter: parent.verticalCenter; name: pill.icon; size: 16 * pill.u; visible: pill.icon !== "" }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: pill.text
            color: "white"
            font.family: "Inter"
            font.pixelSize: 14 * pill.u
            elide: Text.ElideRight
            width: Math.min(implicitWidth, 220 * pill.u)
        }
    }
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: pill.clicked()
    }
}
