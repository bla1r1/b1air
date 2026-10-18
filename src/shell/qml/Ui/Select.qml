import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC

// =============================================================================
// Unified Select component.
//
// Trigger button with current choice, opening a Popover with searchable
// ListPicker when items exceed 8 or when explicitly searchable.
// =============================================================================

Item {
    id: root

    property var model: []                 // [{ id, label, detail?, icon? }]
    property string current: ""
    property string placeholder: I18n.tr("Choose…")
    property bool searchable: root.model && root.model.length > 8
    property string searchPlaceholder: I18n.tr("Search")
    property bool open: false

    signal picked(string id)

    implicitHeight: Design.s(Design.size.md)
    implicitWidth: Design.s(Design.width.select)
    Layout.preferredHeight: Design.s(Design.size.md)
    Layout.preferredWidth: implicitWidth

    readonly property var selected: {
        if (!root.model) return null;
        for (let i = 0; i < root.model.length; ++i) {
            const m = root.model[i];
            if (m.id === root.current) return m;
        }
        return null;
    }

    function toggleOpen() {
        if (root.open) {
            popover.close();
        } else {
            popover.open();
        }
    }

    // Trigger button
    Rectangle {
        id: button
        anchors.fill: parent
        radius: Design.s(Design.radius.ctl)
        color: buttonArea.containsMouse || root.open ? Design.hover : Design.well
        border.color: root.open ? Design.accent : Design.line
        border.width: 1
        opacity: root.enabled ? 1.0 : Design.opacity.disabled

        activeFocusOnTab: root.enabled
        Accessible.role: Accessible.ComboBox
        Accessible.name: root.selected ? root.selected.label : root.placeholder
        Accessible.focusable: root.enabled

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Design.s(Design.space.md)
            anchors.rightMargin: Design.s(Design.space.sm)
            spacing: Design.s(Design.space.sm)

            Icon {
                visible: !!(root.selected && root.selected.icon)
                text: (root.selected && root.selected.icon) ? root.selected.icon : ""
                role: "body"
                color: Design.accent
            }

            Label {
                Layout.fillWidth: true
                text: root.selected ? root.selected.label : root.placeholder
                dim: !root.selected
                elide: Text.ElideRight
            }

            Label {
                visible: !!(root.selected && root.selected.detail)
                text: root.selected ? String(root.selected.detail || "") : ""
                role: "caption"
                dim: true
                isMono: true
            }

            Icon {
                text: root.open ? "\u{f0143}" : "\u{f0140}" // chevron up / down
                role: "caption"
                color: Design.textDim
            }
        }

        MouseArea {
            id: buttonArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: {
                if (root.enabled) {
                    button.forceActiveFocus(Qt.MouseFocusReason);
                    root.toggleOpen();
                }
            }
        }

        Keys.onReturnPressed: function(event) {
            if (root.enabled) {
                root.toggleOpen();
                event.accepted = true;
            }
        }

        Keys.onSpacePressed: function(event) {
            if (root.enabled) {
                root.toggleOpen();
                event.accepted = true;
            }
        }

        FocusRing {
            target: button
            cornerRadius: button.radius + Design.s(Design.space.xxs)
        }
    }

    Popover {
        id: popover
        anchorItem: button
        contentWidth: Math.max(button.width, Design.s(Design.width.select))
        cornerRadius: Design.s(Design.radius.ctl)
        onOpened: {
            root.open = true;
            listPicker.focusSearch();
        }
        onClosed: {
            root.open = false;
        }

        ListPicker {
            id: listPicker
            Layout.fillWidth: true
            model: root.model
            current: root.current
            searchable: root.searchable
            searchPlaceholder: root.searchPlaceholder
            onPicked: function(id, item) {
                popover.close();
                if (id !== root.current) {
                    root.current = id;
                    root.picked(id);
                }
            }
            onCancelled: popover.close()
        }
    }
}
