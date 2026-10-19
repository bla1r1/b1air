import QtQuick
import QtQuick.Layouts
import QtQuick.Controls

// One tab in an app's tab strip: Term's shells, Files' folders. The same
// height as a toolbar Button, lit with the accent tint when it is the one shown;
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
    // Unsaved changes: a dot where the close button is, until the tab is
    // pointed at, as a Mac's tabs and windows say it.
    property bool modified: false
    // Shown when the pointer rests on it: a file's whole path, say.
    property string tip: ""
    signal clicked()
    signal closeRequested()

    implicitHeight: Design.s(Design.size.md)
    implicitWidth: Math.min(Design.s(Design.width.tab), row.implicitWidth + Design.s(Design.space.md) * 2)
    radius: height / 2
    color: active ? Design.stateSelected
         : area.containsMouse ? Design.stateHover : "transparent"
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
            font.pixelSize: Design.s(Design.font.glyphSm)
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
            Layout.preferredWidth: Design.s(Design.size.mini)
            Layout.preferredHeight: Design.s(Design.size.mini)
            radius: width / 2
            color: closeArea.containsMouse ? Design.stateDanger : "transparent"
            // Faint until the tab is pointed at, so a row of tabs is a row
            // of names and not a row of ×.
            readonly property bool pointed: area.containsMouse || closeArea.containsMouse
            opacity: pointed || root.active || root.modified ? 1 : 0.0
            Rectangle {
                anchors.centerIn: parent
                visible: root.modified && !parent.pointed
                width: Design.s(Design.size.dot); height: width; radius: width / 2
                color: Design.accent
            }
            Text {
                anchors.centerIn: parent
                visible: !root.modified || parent.pointed
                text: "\u{f0156}"
                font.family: Design.font.icon
                font.pixelSize: Design.s(Design.font.footnote)
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

    // Tab reaches it; Enter and Space do what a click does.
    activeFocusOnTab: true
    Keys.onReturnPressed: event => { root.clicked(); event.accepted = true; }
    Keys.onSpacePressed: event => { root.clicked(); event.accepted = true; }
    Accessible.role: Accessible.PageTab
    Accessible.name: root.label
    ToolTip.visible: root.tip !== "" && area.containsMouse
    ToolTip.delay: 600
    ToolTip.text: root.tip
    FocusRing { target: root }
}
