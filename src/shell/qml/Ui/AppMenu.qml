import QtQuick
import QtQuick.Controls as C

// A context menu in the desktop's colours. The apps each drew their own —
// b1air-files one way, b1air-git another — or left Menu to the Basic style,
// which is a light-grey box with no shortcut column.
C.Menu {
    id: root
    padding: Design.s(Design.space.xs)
    background: Rectangle {
        implicitWidth: Design.s(240)
        radius: Design.s(Design.radius.ctl)
        color: Design.raised
        border.color: Design.line
        border.width: 1
    }
    delegate: AppMenuItem {}
}
