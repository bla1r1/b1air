import QtQuick
import QtQuick.Layouts

// One tab in an app's tab strip: Term's shells, Files' folders. The same
// capsule as a BarButton, lit with the accent tint when it is the one shown;
// a close × on the right, and a middle click closes it, as in every browser.
//
//   AppTab {
//       label: "Downloads"; glyph: "\u{f024b}"
//       active: index === window.tabIndex
//       closable: tabs.length > 1
//       onClicked: window.switchTab(index)
//       onCloseRequested: window.closeTab(index)
//   }
Rectangle {
    id: root
    property string label: ""
    property string glyph: ""
    property bool active: false
    property bool closable: true
    signal clicked()
    signal closeRequested()

    implicitHeight: Design.s(30)
    implicitWidth: Math.min(Design.s(220), row.implicitWidth + Design.s(Design.space.md) * 2)
    radius: height / 2
    color: active ? Design.tint(Design.accent, 0.22)
         : area.containsMouse ? Design.hover : "transparent"
    Behavior on color { ColorAnimation { duration: Design.duration.fast } }

    // Under the close button, so the × gets its own clicks.
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => {
            if (mouse.button === Qt.MiddleButton) { if (root.closable) root.closeRequested(); }
            else root.clicked();
        }
    }

    RowLayout {
        id: row
        anchors.fill: parent
        anchors.leftMargin: Design.s(Design.space.md)
        anchors.rightMargin: root.closable ? Design.s(Design.space.xs) : Design.s(Design.space.md)
        spacing: Design.s(Design.space.xs + 2)

        Text {
            visible: root.glyph !== ""
            text: root.glyph
            font.family: Design.font.icon
            font.pixelSize: Design.s(14)
            color: root.active ? Design.accent : Design.textDim
        }
        Text {
            Layout.fillWidth: true
            text: root.label
            font.family: Design.font.sans
            font.pixelSize: Design.s(Design.font.body)
            font.weight: root.active ? Design.weight.semibold : Design.weight.regular
            color: root.active ? Design.text : Design.textDim
            elide: Text.ElideRight
        }
        Rectangle {
            visible: root.closable
            Layout.preferredWidth: Design.s(20)
            Layout.preferredHeight: Design.s(20)
            radius: width / 2
            color: closeArea.containsMouse ? Design.tint(Design.danger, 0.22) : "transparent"
            // Faint until the tab is pointed at, so a row of tabs is a row
            // of names and not a row of ×.
            opacity: area.containsMouse || closeArea.containsMouse || root.active ? 1 : 0.0
            Text {
                anchors.centerIn: parent
                text: "\u{f0156}"
                font.family: Design.font.icon
                font.pixelSize: Design.s(12)
                color: closeArea.containsMouse ? Design.danger : Design.textDim
            }
            MouseArea {
                id: closeArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.closeRequested()
            }
        }
    }
}
