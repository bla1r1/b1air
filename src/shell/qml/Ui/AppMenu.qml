import QtQuick
import QtQuick.Controls as C

// A context menu in the desktop's colours. The apps each drew their own —
// b1air-files one way, b1air-git another — or left Menu to the Basic style,
// which is a light-grey box with no shortcut column.
C.Menu {
    id: root
    padding: Design.s(Design.space.xs)
    // As wide as the widest row that is showing, so "Delete Permanently…"
    // with its shortcut is not cut to "Delete Permanen…"; 240 at least, so
    // short menus do not shrink to slivers, and capped so a long file name
    // in an item cannot stretch it across the screen.
    readonly property real _widest: {
        let w = 0;
        for (let i = 0; i < root.count; ++i) {
            const it = root.itemAt(i);
            if (it && it.visible) w = Math.max(w, it.implicitWidth);
        }
        return w;
    }
    background: Rectangle {
        implicitWidth: Math.min(Design.s(440), Math.max(Design.s(240), root._widest + root.leftPadding + root.rightPadding))
        radius: Design.s(Design.radius.ctl)
        color: Design.raised
        border.color: Design.line
        border.width: 1
    }
    delegate: AppMenuItem {}
}
