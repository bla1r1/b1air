import QtQuick

// A short list to pick from, over a pill: the session, the user. Opaque
// enough to read on any wallpaper — the theme's ground, as the shell's menus.
Rectangle {
    id: menu
    property var items: []        // [{ text }]
    property int current: -1
    property real u: 1
    signal picked(int index)

    width: Math.max(220 * u, column.implicitWidth + 12 * u)
    height: column.implicitHeight + 12 * u
    radius: 14 * u
    color: Qt.rgba(ThemeColors.ground.r, ThemeColors.ground.g, ThemeColors.ground.b, 0.9)
    border.width: 1
    border.color: Qt.rgba(ThemeColors.text.r, ThemeColors.text.g, ThemeColors.text.b, 0.12)

    Column {
        id: column
        x: 6 * menu.u
        y: 6 * menu.u
        width: menu.width - 12 * menu.u
        Repeater {
            model: menu.items
            delegate: Rectangle {
                required property var modelData
                required property int index
                width: column.width
                height: 34 * menu.u
                radius: 9 * menu.u
                color: row.containsMouse ? Qt.rgba(ThemeColors.text.r, ThemeColors.text.g, ThemeColors.text.b, 0.09)
                                         : "transparent"
                Text {
                    x: 12 * menu.u
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 40 * menu.u
                    text: modelData.text
                    color: ThemeColors.text
                    font.family: ThemeColors.sans
                    font.pixelSize: 13 * menu.u
                    font.weight: index === menu.current ? Font.DemiBold : Font.Normal
                    elide: Text.ElideRight
                }
                Rectangle {   // the one in use
                    visible: index === menu.current
                    anchors.right: parent.right
                    anchors.rightMargin: 14 * menu.u
                    anchors.verticalCenter: parent.verticalCenter
                    width: 7 * menu.u
                    height: width
                    radius: width / 2
                    color: ThemeColors.primary
                }
                MouseArea {
                    id: row
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: menu.picked(index)
                }
            }
        }
    }
}
