import QtQuick
import QtQuick.Layouts

// =============================================================================
// SettingsGroup: grouped settings card with outer rounded corners and
// inner row dividers.
//
// Usage:
//   SettingsGroup {
//       title: I18n.tr("General")
//       SettingsRow { label: "Auto-start"; Switch { ... } }
//       SettingsRow { label: "Theme"; Select { ... } }
//   }
// =============================================================================

Rectangle {
    id: root

    property string title: ""
    property string description: ""
    property string subtitle: ""
    property string note: ""
    readonly property string _effectiveNote: root.note !== "" ? root.note : (root.description !== "" ? root.description : root.subtitle)
    property string icon: ""
    property color accentColor: "transparent"
    readonly property color tone: root.accentColor.a > 0 ? root.accentColor : Design.accent
    default property alias content: container.data

    Layout.fillWidth: true
    implicitHeight: contentColumn.implicitHeight
    Layout.preferredHeight: implicitHeight

    radius: Design.s(Design.radius.card)
    color: Design.translucent ? Design.glassCard : Design.raised
    border.width: 1
    border.color: Design.glassBorder
    clip: true

    ColumnLayout {
        id: contentColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: 0

        // Section header inside the card
        ColumnLayout {
            visible: root.title !== "" || root._effectiveNote !== ""
            Layout.fillWidth: true
            Layout.leftMargin: Design.s(Design.space.rowPaddingX)
            Layout.rightMargin: Design.s(Design.space.rowPaddingX)
            Layout.topMargin: Design.s(Design.space.md)
            Layout.bottomMargin: (container.children.length > 0) ? Design.s(Design.space.xs) : Design.s(Design.space.md)
            spacing: Design.s(Design.space.xxs)

            Label {
                visible: root.title !== ""
                text: root.title
                role: "subhead"
                weight: Design.weight.semibold
                color: Design.text
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            Label {
                visible: root._effectiveNote !== ""
                text: root._effectiveNote
                role: "footnote"
                dim: true
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
        }

        // The slot for child items
        ColumnLayout {
            id: container
            Layout.fillWidth: true
            Layout.topMargin: (root.title === "" && root._effectiveNote === "") ? Design.s(Design.space.xs) : 0
            Layout.bottomMargin: (children.length > 0) ? Design.s(Design.space.xs) : 0
            spacing: 0

            onChildrenChanged: root._padChildren()
        }
    }

    // Rows pad themselves and draw the hairline between them (SettingsRow,
    // SwitchRow). Anything else put in a group — a stepper, a free layout of
    // fields and buttons — ran edge to edge of the card; it gets the rows'
    // side padding unless it set margins of its own.
    function _padChildren() {
        const pad = Design.s(Design.space.rowPaddingX);
        for (let i = 0; i < container.children.length; ++i) {
            const c = container.children[i];
            if (c.settingsRow) continue;
            if (c.Layout.leftMargin === 0 && c.Layout.rightMargin === 0) {
                c.Layout.leftMargin = pad;
                c.Layout.rightMargin = pad;
            }
        }
    }
}
