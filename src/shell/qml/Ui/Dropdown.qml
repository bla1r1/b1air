import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as QQC

// A closed list: the current choice on a button, every choice under it when
// clicked, and a search field above them once there are more than a handful.
// The input layouts' picker (Keyboard), made general, for settings that were
// a wall of pills — Language & Region had one pill per installed locale, three
// times over. The list opens over the page, in the window's own overlay (not
// a window of its own), so it works the same in the shell and in Settings.
//
//   Dropdown {
//       model: [{ id: "uk", label: "Українська", detail: "uk_UA" }, …]
//       current: Settings.uiLanguage
//       onPicked: id => Settings.set("uiLanguage", id)
//   }
ColumnLayout {
    id: root

    property var model: []                 // [{ id, label, detail? }]
    property string current: ""
    property string placeholder: I18n.tr("Choose…")
    property bool searchable: root.model.length > 8
    property string searchPlaceholder: I18n.tr("Search")
    property bool open: false
    property string query: ""

    signal picked(string id)

    // Opened and closed by call: a `visible: root.open` binding is broken the
    // first time the popup closes itself (Esc, a click elsewhere).
    onOpenChanged: {
        if (!open) { popup.close(); return; }
        // Down, unless the window ends first: then up, as a combo box does,
        // rather than pushed up over its own button.
        const bottom = button.mapToItem(null, 0, button.height).y;
        const room = (button.Window.height || 0) - bottom - Design.s(12);
        // From the rows, not popup.implicitHeight: before the first showing
        // its layout has not run, and it reported 40 for a list of three.
        const height = Math.min(Design.s(260), Math.max(1, root.shown.length) * Design.s(32))
            + (root.searchable ? Design.s(36) + Design.s(4) : 0) + Design.s(8);
        popup.y = room >= height ? button.height + Design.s(4) : -height - Design.s(4);
        popup.open();
    }

    spacing: Design.s(4)
    opacity: enabled ? 1 : Design.opacity.disabled
    Layout.preferredWidth: Design.s(300)
    Layout.maximumWidth: Design.s(360)

    readonly property var selected: {
        for (const m of root.model)
            if (m.id === root.current) return m;
        return null;
    }
    readonly property var shown: {
        const q = root.query.trim().toLowerCase();
        if (q === "") return root.model;
        return root.model.filter(m =>
            (String(m.label) + " " + String(m.detail || "") + " " + String(m.id)).toLowerCase().indexOf(q) >= 0);
    }

    function close() {
        root.open = false;
        root.query = "";
        if (searchLoader.item) searchLoader.item.text = "";
    }
    function choose(id) {
        root.close();
        if (id !== root.current) root.picked(id);
    }

    Rectangle {
        id: button
        Layout.fillWidth: true
        Layout.preferredHeight: Design.s(36)
        radius: Design.s(Design.radius.ctl)
        color: buttonArea.containsMouse || root.open ? Design.hover : Design.raised
        border.color: root.open ? Design.accent : Design.line
        border.width: 1

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Design.s(Design.space.md)
            anchors.rightMargin: Design.s(Design.space.sm)
            spacing: Design.s(Design.space.sm)

            Label {
                Layout.fillWidth: true
                text: root.selected ? root.selected.label : root.placeholder
                dim: !root.selected
                elide: Text.ElideRight
            }
            Label {
                visible: text !== ""
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
            cursorShape: Qt.PointingHandCursor
            onClicked: root.open ? root.close() : (root.open = true)
        }
    }

    // Over the page, not in it: opened in place it pushed every row below it
    // down. A Popup sits in the window's overlay, stays inside the window
    // (margins), and closes on Esc or a click anywhere else.
    QQC.Popup {
        id: popup
        parent: button
        width: button.width
        padding: Design.s(4)
        margins: Design.s(8)
        closePolicy: QQC.Popup.CloseOnEscape | QQC.Popup.CloseOnPressOutsideParent
        onClosed: root.close()
        onOpened: if (searchLoader.item) searchLoader.item.focusInput()

        background: Rectangle {
            radius: Design.s(Design.radius.ctl)
            color: Design.sunken
            border.color: Design.line
            border.width: 1
        }

        contentItem: ColumnLayout {
            spacing: Design.s(4)

            Loader {
                id: searchLoader
                Layout.fillWidth: true
                active: root.searchable
                visible: active
                sourceComponent: Field {
                    placeholder: root.searchPlaceholder
                    onEdited: v => root.query = v
                    // Enter takes the first match, as the layouts' field does.
                    onAccepted: if (root.shown.length > 0) root.choose(root.shown[0].id)
                }
            }

            Label {
                visible: root.shown.length === 0
                Layout.fillWidth: true
                Layout.margins: Design.s(Design.space.sm)
                text: I18n.tr("Nothing matches")
                role: "caption"
                dim: true
            }

                ListView {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Math.min(Design.s(260), root.shown.length * Design.s(32))
                    clip: true
                    model: root.shown
                    boundsBehavior: Flickable.StopAtBounds
                    QQC.ScrollBar.vertical: OverflowBar {}

                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        readonly property bool isCurrent: modelData.id === root.current
                        width: ListView.view.width
                        height: Design.s(32)
                        radius: Design.s(Design.radius.ctl)
                        color: rowArea.containsMouse ? Design.hover
                             : row.isCurrent ? Design.tint(Design.accent, 0.12) : "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Design.s(Design.space.sm)
                            anchors.rightMargin: Design.s(Design.space.sm)
                            spacing: Design.s(Design.space.sm)

                            Icon {
                                Layout.preferredWidth: Design.s(16)
                                text: row.isCurrent ? "\u{f012c}" : "" // check
                                role: "caption"
                                color: Design.accent
                            }
                            Label {
                                Layout.fillWidth: true
                                text: row.modelData.label
                                weight: row.isCurrent ? Design.weight.semibold : Design.weight.regular
                                elide: Text.ElideRight
                            }
                            Label {
                                visible: text !== ""
                                text: String(row.modelData.detail || "")
                                role: "caption"
                                dim: true
                                isMono: true
                            }
                        }

                        MouseArea {
                            id: rowArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.choose(row.modelData.id)
                        }
                    }
                }
        }
    }
}
