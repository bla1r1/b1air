import QtQuick
import QtQuick.Layouts

// A capsule holding a few related BarButtons: back/forward/up, zoom, views.
// The buttons inside are flat and light up on hover; the capsule is what
// reads as "a control" against the window.
Rectangle {
    id: root
    default property alias content: row.data
    implicitHeight: Design.s(36)
    implicitWidth: row.implicitWidth + Design.s(6)
    radius: height / 2
    color: Design.raised
    border.width: 1
    border.color: Design.tint(Design.text, 0.06)
    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: Design.s(2)
    }
    Component.onCompleted: {
        for (const c of row.children)
            if (c.grouped !== undefined) c.grouped = true;
    }
}
