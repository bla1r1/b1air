import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC

// =============================================================================
// ListPicker component with search filter, section support, and keyboard navigation.
//
// Model items: [{ id, label, detail?, section?, icon? }]
// =============================================================================

ColumnLayout {
    id: root

    property var model: []
    property string current: ""
    property bool searchable: root.model && root.model.length > 8
    property string searchPlaceholder: I18n.tr("Search")
    property string query: ""
    property real maxHeight: Design.s(Design.width.list)

    signal picked(string id, var item)
    signal cancelled()

    spacing: Design.s(Design.space.xs)

    readonly property var shown: {
        if (!root.model) return [];
        const q = root.query.trim().toLowerCase();
        if (q === "") return root.model;
        return root.model.filter(m => {
            const str = (String(m.label || "") + " " + String(m.detail || "") + " " + String(m.section || "") + " " + String(m.id || "")).toLowerCase();
            return str.indexOf(q) >= 0;
        });
    }

    function choose(id, item) {
        root.picked(id, item);
    }

    function focusSearch() {
        if (searchField.visible) searchField.forceActiveFocus();
    }

    // Optional search input
    Field {
        id: searchField
        Layout.fillWidth: true
        visible: root.searchable
        placeholder: root.searchPlaceholder
        text: root.query
        onEdited: function(v) { root.query = v; }
        onAccepted: {
            if (root.shown.length > 0) {
                const item = root.shown[0];
                root.choose(item.id, item);
            }
        }
        Keys.onDownPressed: {
            if (listView.count > 0) listView.forceActiveFocus();
        }
        Keys.onEscapePressed: root.cancelled()
    }

    Label {
        visible: root.shown.length === 0
        Layout.fillWidth: true
        Layout.margins: Design.s(Design.space.sm)
        text: I18n.tr("Nothing matches")
        role: "caption"
        dim: true
        horizontalAlignment: Text.AlignHCenter
    }

    ListView {
        id: listView
        Layout.fillWidth: true
        Layout.preferredHeight: Math.min(root.maxHeight, Math.max(1, root.shown.length) * Design.s(Design.size.md))
        clip: true
        model: root.shown
        boundsBehavior: Flickable.StopAtBounds
        QQC.ScrollBar.vertical: OverflowBar {}
        activeFocusOnTab: true

        Keys.onEscapePressed: root.cancelled()
        Keys.onReturnPressed: {
            if (currentIndex >= 0 && currentIndex < root.shown.length) {
                const it = root.shown[currentIndex];
                root.choose(it.id, it);
            }
        }

        delegate: Rectangle {
            id: row
            required property var modelData
            required property int index
            readonly property bool isCurrent: modelData.id === root.current
            readonly property bool isHighlighted: listView.currentIndex === index || rowArea.containsMouse

            width: ListView.view.width
            height: Design.s(Design.size.md)
            radius: Design.s(Design.radius.ctl)
            color: row.isHighlighted ? Design.hover
                 : (row.isCurrent ? Design.selection : "transparent")

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Design.s(Design.space.sm)
                anchors.rightMargin: Design.s(Design.space.sm)
                spacing: Design.s(Design.space.xs + 2)

                Icon {
                    visible: !!row.modelData.icon
                    text: row.modelData.icon || ""
                    role: "body"
                    color: row.isCurrent ? Design.accent : Design.textDim
                }

                Label {
                    Layout.fillWidth: true
                    text: row.modelData.label || String(row.modelData.id || "")
                    color: row.isCurrent ? Design.accent : Design.text
                    weight: row.isCurrent ? Design.weight.semibold : Design.weight.regular
                    elide: Text.ElideRight
                }

                Label {
                    visible: !!row.modelData.detail
                    text: String(row.modelData.detail || "")
                    role: "caption"
                    dim: true
                    isMono: true
                }

                Icon {
                    visible: row.isCurrent
                    text: "\u{f012c}" // checkmark
                    role: "caption"
                    color: Design.accent
                }
            }

            MouseArea {
                id: rowArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    listView.currentIndex = row.index;
                    root.choose(row.modelData.id, row.modelData);
                }
            }
        }
    }
}
