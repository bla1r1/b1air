import QtQuick
import QtQuick.Layouts

// =============================================================================
// One row of a menu drawn outside QtQuick.Controls: the short menus under the
// bar's icons, which live in a popup window of their own and cannot be a
// C.Menu. It looks and behaves as AppMenuItem does — the same height and
// highlight — and takes the keyboard as every Control does.
//
//   MenuRow { glyph: "\u{f0928}"; text: "Home"; lit: true; onClicked: … }
// =============================================================================

Control {
    id: root

    property string glyph: ""
    property string text: ""
    property string detail: ""
    property string trailing: ""
    // What is on (a joined network, the output in use): a filled disc
    // behind the glyph, as a menu bar draws it.
    property bool lit: false

    Layout.fillWidth: true
    implicitHeight: Design.s(Design.size.md)
    radius: Design.s(Design.radius.sm)
    accessibleName: root.text

    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: root.pressed ? Design.tint(Design.accent, 0.30)
             : (root.hovered || root.activeFocus) ? Design.selection : "transparent"
        Behavior on color { ColorAnimation { duration: Design.duration.fast } }
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: Design.s(Design.space.sm)
        anchors.rightMargin: Design.s(Design.space.sm)
        spacing: Design.s(Design.space.sm)

        Rectangle {
            visible: root.glyph !== ""
            Layout.preferredWidth: Design.s(Design.size.mini)
            Layout.preferredHeight: Design.s(Design.size.mini)
            radius: width / 2
            color: root.lit ? Design.accent : Design.veilStrong
            Icon {
                anchors.centerIn: parent
                text: root.glyph
                role: "caption"
                color: root.lit ? Design.accentText : Design.text
            }
        }
        Label { Layout.fillWidth: true; text: root.text; elide: Text.ElideRight }
        Label { visible: root.detail !== ""; text: root.detail; role: "caption"; dim: true }
        Icon { visible: root.trailing !== ""; text: root.trailing; role: "caption"; color: Design.textDim }
    }
}
