import QtQuick
import QtQuick.Layouts

// =============================================================================
// Labelled switch row: label and optional consequence note on the left,
// unified Switch on the right.
// =============================================================================

Item {
    id: root

    property string label: ""
    property string title: "" // alias for label
    readonly property string _effectiveLabel: label !== "" ? label : title
    property string subtitle: ""
    property string note: ""
    readonly property string _effectiveNote: note !== "" ? note : subtitle
    property string icon: ""
    property bool checked: false

    signal toggled()

    Layout.fillWidth: true
    implicitWidth: 400

    // A row in a SettingsGroup: the group leaves its padding to it, and a
    // hairline separates it from a row right above it.
    readonly property bool settingsRow: true
    readonly property bool _afterRow: {
        const kids = root.parent ? root.parent.children : [];
        let prev = null;
        for (let i = 0; i < kids.length; ++i) {
            if (kids[i] === root) break;
            if (kids[i].visible) prev = kids[i];
        }
        return !!(prev && prev.settingsRow);
    }
    Rectangle {
        visible: root._afterRow
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Design.s(Design.space.rowPaddingX)
        anchors.rightMargin: Design.s(Design.space.rowPaddingX)
        height: 1
        color: Design.separator
        opacity: 0.6
    }

    readonly property bool _hasNote: _effectiveNote !== ""
    readonly property real _minHeight: Design.s(_hasNote ? Design.size.rowTall : Design.size.row)
    implicitHeight: Math.max(_minHeight, rowLayout.implicitHeight + Design.s(Design.space.xs) * 2)
    Layout.preferredHeight: implicitHeight
    opacity: enabled ? 1.0 : Design.opacity.disabled

    RowLayout {
        id: rowLayout
        anchors.fill: parent
        anchors.leftMargin: Design.s(Design.space.rowPaddingX)
        anchors.rightMargin: Design.s(Design.space.rowPaddingX)
        spacing: Design.s(Design.space.md)

        Icon {
            visible: root.icon !== ""
            text: root.icon
            role: "subhead"
            color: Design.textDim
            Layout.alignment: Qt.AlignVCenter
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignVCenter
            spacing: Design.s(Design.space.xxs)

            Label {
                text: root._effectiveLabel
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            Label {
                text: root._effectiveNote
                visible: text !== ""
                role: "footnote"
                dim: true
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: {
                    if (root.enabled) {
                        switchControl.forceActiveFocus(Qt.MouseFocusReason);
                        root.toggled();
                    }
                }
            }
        }

        Switch {
            id: switchControl
            Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
            checked: root.checked
            accessibleName: root._effectiveLabel
            enabled: root.enabled
            onToggled: root.toggled()
        }
    }
}
