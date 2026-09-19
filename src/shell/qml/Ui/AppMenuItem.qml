import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as C

// One row of an AppMenu: glyph, label, shortcut. A disabled row is hidden
// rather than greyed — a menu of things you cannot do is noise — unless
// `showDisabled` says it should be seen.
C.MenuItem {
    id: root
    property string glyph: ""
    property string keys: ""
    property bool showDisabled: false
    property color tone: Design.text

    implicitHeight: visible ? Design.s(32) : 0
    visible: enabled || showDisabled
    height: visible ? implicitHeight : 0
    leftPadding: Design.s(Design.space.sm)
    rightPadding: Design.s(Design.space.sm)

    contentItem: RowLayout {
        spacing: Design.s(Design.space.sm)
        opacity: root.enabled ? 1.0 : 0.45
        Text {
            Layout.preferredWidth: Design.s(18)
            text: root.checkable ? (root.checked ? "\u{f012c}" : "") : root.glyph
            font.family: Design.font.icon
            font.pixelSize: Design.s(14)
            color: root.checked ? Design.accent : (root.tone === Design.text ? Design.textDim : root.tone)
            horizontalAlignment: Text.AlignHCenter
        }
        Text {
            Layout.fillWidth: true
            text: root.text
            font.family: Design.font.sans
            font.pixelSize: Design.s(Design.font.body)
            color: root.tone
            elide: Text.ElideRight
        }
        Text {
            visible: root.keys !== "" || root.subMenu
            text: root.subMenu ? "\u{f0142}" : root.keys
            font.family: root.subMenu ? Design.font.icon : Design.font.mono
            font.pixelSize: Design.s(Design.font.caption)
            color: Design.textFaint
        }
    }
    arrow: null
    indicator: null
    background: Rectangle {
        radius: Design.s(Design.radius.sm)
        color: root.highlighted ? Design.tint(Design.accent, 0.22) : "transparent"
    }
}
