import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import "../Ui"
import "../Services"

// =============================================================================
// Notifications Mini View (Control Center Subpage)
//
// Was the one subpage of five that did not use MiniView: it hand-rolled the
// same header, with a different back-arrow glyph and a bordered button where
// the other four use a hover tone, and it was the only mini view with no way
// through to its own full settings page. Same frame as its siblings now.
// =============================================================================

MiniView {
    id: root

    title: I18n.tr("Notifications")
    icon: "\u{f009a}"
    tone: Design.lavender
    footerLabel: I18n.tr("Notification Settings…")

    // While this list is on screen, a toast repeating one of its lines is
    // noise — and toasts used to be drawn on top of it, because both surfaces
    // sat on the overlay layer and this one was created first.
    Component.onCompleted: Notifications.acquireList()
    Component.onDestruction: Notifications.releaseList()

    trailing: ActionButton {
        visible: Notifications.history.count > 0
        icon: "\u{f0156}"
        label: I18n.tr("Clear")
        onActivated: Notifications.clearAllHistory()
    }

    ColumnLayout {
        id: page
        anchors.fill: parent
        spacing: Design.s(Design.space.md)

        // ── DND toggle ───────────────────────────────────────────────────────
        Card {
            Layout.fillWidth: true

            Toggle {
                label: I18n.tr("Do Not Disturb")
                subtitle: I18n.tr("Silence popups and store them in history")
                checked: Notifications.dnd
                onToggled: Notifications.toggleDnd()
            }
        }

        // ── History ──────────────────────────────────────────────────────────
        // ── Grouped by app ──────────────────────────────────────────────────
        //
        // As a desktop's notification centre: an app's notifications in one
        // stack, newest on top and the rest peeking out under it; a click
        // spreads them. Each shows the actions its app offers while it is
        // still alive (Reply, Open, …).
        property var expanded: ({})
        property int stamp: 0
        Connections {
            target: Notifications.history
            function onCountChanged() { page.stamp++; }
        }
        readonly property var groups: {
            const _ = page.stamp;
            const order = [], byApp = {};
            for (let i = 0; i < Notifications.history.count; i++) {
                const it = Notifications.history.get(i);
                const app = it.appName || "";
                if (!byApp[app]) { byApp[app] = { app: app, icon: it.icon, items: [] }; order.push(byApp[app]); }
                byApp[app].items.push({ index: i, summary: it.summary, body: it.body, time: it.time, icon: it.icon, obj: it.obj });
            }
            return order;
        }
        function toggleGroup(app) {
            const e = Object.assign({}, page.expanded);
            e[app] = !e[app];
            page.expanded = e;
        }
        function clearGroup(group) {
            for (let k = group.items.length - 1; k >= 0; k--)
                Notifications.dismissHistoryItem(group.items[k].index);
        }

        ListView {
            id: list
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: Design.s(Design.space.sm)
            model: parent.groups
            boundsBehavior: Flickable.StopAtBounds

            delegate: ColumnLayout {
                id: group
                required property var modelData
                readonly property bool open: !!page.expanded[group.modelData.app] || group.modelData.items.length === 1
                width: ListView.view ? ListView.view.width : 0
                spacing: Design.s(Design.space.xs)

                // The app's line: its name, and for a spread stack, fold and clear.
                RowLayout {
                    Layout.fillWidth: true
                    visible: group.modelData.items.length > 1
                    Label {
                        Layout.fillWidth: true
                        text: group.modelData.app
                        role: "caption"
                        weight: Design.weight.semibold
                        dim: true
                        elide: Text.ElideRight
                    }
                    Pill {
                        visible: group.open
                        label: I18n.tr("Show less")
                        onClicked: page.toggleGroup(group.modelData.app)
                    }
                    IconButton {
                        icon: "\u{f0156}"
                        role: "caption"
                        onClicked: page.clearGroup(group.modelData)
                    }
                }

                Repeater {
                    model: group.open ? group.modelData.items : group.modelData.items.slice(0, 1)
                    delegate: Item {
                        id: cell
                        required property var modelData
                        required property int index
                        // A folded stack: the cards under the top one peek out below it.
                        readonly property int under: group.open ? 0 : Math.min(2, group.modelData.items.length - 1)
                        Layout.fillWidth: true
                        implicitHeight: card.implicitHeight + cell.under * Design.s(6)

                        // Only what shows below the top card: drawn whole under
                        // it, the glass would let them show through.
                        Item {
                            y: card.implicitHeight
                            width: parent.width
                            height: cell.under * Design.s(6)
                            clip: true
                            Repeater {
                                model: cell.under
                                Rectangle {
                                    required property int index
                                    x: Design.s(8) * (index + 1)
                                    width: card.width - 2 * x
                                    y: -Design.s(24) + Design.s(6) * (index + 1)
                                    height: Design.s(24)
                                    radius: Design.s(Design.radius.card)
                                    color: Design.glassCard
                                    border.color: Design.glassBorder
                                    border.width: 1
                                    opacity: 0.8 - index * 0.25
                                    z: -index
                                }
                            }
                        }

                        Rectangle {
                            id: card
                            width: parent.width
                            implicitHeight: body.implicitHeight + Design.s(Design.space.sm) * 2
                            radius: Design.s(Design.radius.card)
                            color: cardMa.containsMouse ? Design.glassHover : Design.glassCard
                            border.color: Design.glassBorder
                            border.width: 1

                            MouseArea {
                                id: cardMa
                                anchors.fill: parent
                                hoverEnabled: true
                                enabled: !group.open
                                onClicked: page.toggleGroup(group.modelData.app)
                            }

                            RowLayout {
                                id: body
                                anchors.fill: parent
                                anchors.margins: Design.s(Design.space.sm)
                                spacing: Design.s(Design.space.sm)

                                Rectangle {
                                    Layout.preferredWidth: Design.s(32)
                                    Layout.preferredHeight: Design.s(32)
                                    Layout.alignment: Qt.AlignTop
                                    radius: Design.s(Design.radius.ctl)
                                    color: Design.well
                                    Image {
                                        id: appIcon
                                        anchors.centerIn: parent
                                        width: Design.s(20); height: width
                                        sourceSize: Qt.size(64, 64)
                                        source: String(cell.modelData.icon || "").indexOf("://") >= 0 ? cell.modelData.icon : ""
                                        visible: status === Image.Ready
                                        fillMode: Image.PreserveAspectFit
                                    }
                                    Icon {
                                        anchors.centerIn: parent
                                        visible: !appIcon.visible
                                        text: "\u{f009a}"
                                        role: "caption"
                                        color: Design.textDim
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: Design.s(2)
                                    RowLayout {
                                        Layout.fillWidth: true
                                        Label {
                                            Layout.fillWidth: true
                                            text: cell.modelData.summary
                                            weight: Design.weight.semibold
                                            elide: Text.ElideRight
                                        }
                                        Label { text: cell.modelData.time; role: "caption"; dim: true; tabular: true }
                                    }
                                    Label {
                                        visible: cell.modelData.body !== ""
                                        Layout.fillWidth: true
                                        text: cell.modelData.body
                                        role: "caption"
                                        dim: true
                                        wrapMode: Text.WordWrap
                                        maximumLineCount: group.open ? 4 : 2
                                        elide: Text.ElideRight
                                    }
                                    Label {
                                        visible: !group.open && group.modelData.items.length > 1
                                        text: I18n.trn("%1 more notification", "%1 more notifications", group.modelData.items.length - 1)
                                        role: "caption"
                                        color: Design.textFaint
                                    }
                                    // What the app offers: Reply, Open, Mark as read…
                                    Flow {
                                        Layout.fillWidth: true
                                        Layout.topMargin: Design.s(Design.space.xs)
                                        spacing: Design.s(Design.space.xs)
                                        visible: group.open && !!cell.modelData.obj && !!cell.modelData.obj.actions
                                                 && cell.modelData.obj.actions.length > 0
                                        Repeater {
                                            model: cell.modelData.obj && cell.modelData.obj.actions ? cell.modelData.obj.actions : []
                                            delegate: Pill {
                                                required property var modelData
                                                label: modelData.text || I18n.tr("Open")
                                                onClicked: if (typeof modelData.invoke === "function") modelData.invoke()
                                            }
                                        }
                                    }
                                }

                                IconButton {
                                    visible: group.open
                                    icon: "\u{f0156}"
                                    role: "caption"
                                    Layout.alignment: Qt.AlignTop
                                    onClicked: Notifications.dismissHistoryItem(cell.modelData.index)
                                }
                            }
                        }
                    }
                }
            }

            Label {
                anchors.centerIn: parent
                visible: Notifications.history.count === 0
                text: I18n.tr("No notifications")
                role: "body"
                dim: true
            }
        }

        // ── Widgets under the list, as a notification centre has them ────────
        RowLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.sm)

            Rectangle {
                visible: Weather.loaded
                Layout.fillWidth: true
                Layout.preferredHeight: Design.s(92)
                radius: Design.s(Design.radius.card)
                color: Design.glassCard
                border.color: Design.glassBorder
                border.width: 1
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Design.s(Design.space.md)
                    spacing: 0
                    Label { text: Weather.location; role: "caption"; weight: Design.weight.semibold; elide: Text.ElideRight; Layout.fillWidth: true }
                    RowLayout {
                        Label { text: Weather.temp; font.pixelSize: Design.s(28); weight: Design.weight.medium; tabular: true }
                        Item { Layout.fillWidth: true }
                        Icon { text: Weather.icon; role: "title"; color: Design.yellow }
                    }
                    Label { text: Weather.condition; role: "caption"; dim: true; elide: Text.ElideRight; Layout.fillWidth: true }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Design.s(92)
                radius: Design.s(Design.radius.card)
                color: Design.glassCard
                border.color: Design.glassBorder
                border.width: 1
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Design.s(Design.space.md)
                    spacing: 0
                    Label { text: I18n.tr("Focus"); role: "caption"; weight: Design.weight.semibold }
                    Label {
                        text: Focus.active ? Focus.remainingText : I18n.tr("%1 min", Focus.workMinutes)
                        font.pixelSize: Design.s(28)
                        weight: Design.weight.medium
                        tabular: true
                    }
                    Label {
                        text: Focus.active ? Focus.phaseLabel : I18n.tr("Not running")
                        role: "caption"
                        dim: true
                        elide: Text.ElideRight
                        Layout.fillWidth: true
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Quickshell.execDetached(["b1air-shell", "toggle", "focustime"])
                }
            }
        }
    }
}
