import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import "../Ui"
import "../Services"
import "../notifications"

// =============================================================================
// Notifications Mini View (Control Center Subpage)
//
// Was the one subpage of five that did not use MiniView: it hand-rolled the
// same header, with a different back-arrow glyph and a bordered button where
// the other four use a hover tone, and it was the only mini view with no way
// through to its own full settings page. Same frame as its siblings now.
//
// The list is a timeline (Now, Today, Yesterday, Earlier), one card for an
// app and sender with its lines in it, quiet fills and no frames; Do Not
// Disturb and Clear are chips in the header. Over it, a search through the
// last seven days (Notifications.archive), cleared ones included.
// =============================================================================

MiniView {
    id: root

    title: I18n.tr("Notifications")
    icon: "\u{f009a}"
    tone: Design.accent
    footerLabel: I18n.tr("Notification Settings…")

    // While this list is on screen, a toast repeating one of its lines is
    // noise — and toasts used to be drawn on top of it, because both surfaces
    // sat on the overlay layer and this one was created first.
    Component.onCompleted: Notifications.acquireList()
    Component.onDestruction: Notifications.releaseList()

    // Do Not Disturb and Clear, as chips in the header rather than a settings
    // row over the list.
    trailing: RowLayout {
        spacing: Design.s(Design.space.xs)
        Chip {
            icon: "\u{f009b}"
            label: Notifications.dnd && Notifications.modeInfo ? Notifications.modeInfo.name : I18n.tr("Do Not Disturb")
            active: Notifications.dnd
            onClicked: Notifications.toggleDnd()
        }
        Chip {
            visible: Notifications.history.count > 0
            icon: "\u{f0156}"
            label: I18n.tr("Clear")
            onClicked: Notifications.clearAllHistory()
        }
    }

    ColumnLayout {
        id: page
        anchors.fill: parent
        spacing: Design.s(Design.space.md)

        // ── The timeline ─────────────────────────────────────────────────────
        //
        // Now (the last hour), Today, Yesterday, Earlier. In each, one card
        // for an app and sender — a chat reads as a chat, its lines in order —
        // with the newest one's picture, actions and reply. Yesterday and
        // earlier are one line each until opened: what is old is there, and
        // not in the way.
        //
        // Worked out when the list or the time of day changes, not as a
        // binding: reading a ListModel's rows inside one bound the result to
        // the rows themselves, and Qt reported a binding loop on every
        // change — twenty-odd times when the centre opened over a full list.
        property var opened: ({})
        property var sections: []
        Connections {
            target: Notifications.history
            function onCountChanged() { page.rebuild(); }
        }
        Connections {
            target: Notifications
            function onNowChanged() { page.rebuild(); }
            function onArchiveStampChanged() { page.find(); }
        }
        Component.onCompleted: page.rebuild()
        function rebuild() {
            const order = ["now", "today", "yesterday", "earlier"];
            const out = order.map(id => ({ id: id, cards: [], items: 0, apps: [] }));
            for (let i = 0; i < Notifications.history.count; i++) {
                const it = Notifications.history.get(i);
                const sec = out[order.indexOf(Notifications.sectionOf(it.ts))];
                const key = (it.appName || "") + "\n" + (it.summary || "");
                let card = sec.cards.find(c => c.key === key);
                if (!card) {
                    card = { key: key, newest: i, indices: [], lines: [] };
                    sec.cards.push(card);
                }
                card.indices.push(i);
                if (it.body) card.lines.unshift(it.body);   // oldest first, as read
                sec.items++;
                if (sec.apps.indexOf(it.appIcon || it.icon || "") < 0) sec.apps.push(it.appIcon || it.icon || "");
            }
            page.sections = out.filter(s => s.cards.length > 0);
        }
        function sectionTitle(id) {
            return id === "now" ? I18n.tr("Now") : id === "today" ? I18n.tr("Today")
                 : id === "yesterday" ? I18n.tr("Yesterday") : I18n.tr("Earlier");
        }
        function toggleSection(id) {
            const o = Object.assign({}, page.opened);
            o[id] = !o[id];
            page.opened = o;
        }
        function dismissCard(card) {
            const idx = card.indices.slice().sort((a, b) => b - a);
            for (const i of idx) Notifications.dismissHistoryItem(i);
        }

        // ── Search, through the week's archive ───────────────────────────────
        property string query: ""
        readonly property bool searching: page.query.trim() !== ""
        // Found when the query or the archive changes (see rebuild()).
        property var found: []
        onQueryChanged: page.find()
        // From the query itself: `searching` may not have caught up with it
        // yet when this runs.
        function find() {
            const q = page.query.trim();
            page.found = q !== "" ? Notifications.search(q, 100) : [];
        }
        Field {
            id: search
            Layout.fillWidth: true
            visible: Notifications.archive.count > 0
            placeholder: I18n.tr("Search the last 7 days")
            onEdited: value => page.query = value
            Keys.onEscapePressed: { search.text = ""; page.query = ""; }
        }

        ScrollArea {
            id: results
            framed: false
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: page.searching && page.found.length > 0

            ColumnLayout {
                width: results.availableWidth
                spacing: Design.s(Design.space.xs)
                Repeater {
                    model: page.found
                    delegate: ListRow {
                        id: hit
                        required property var modelData
                        Layout.fillWidth: true
                        implicitHeight: hitBody.implicitHeight + Design.s(Design.space.sm) * 2
                        onClicked: Notifications.activate(hit.modelData)
                        RowLayout {
                            id: hitBody
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: Design.s(Design.space.sm)
                            anchors.rightMargin: Design.s(Design.space.sm)
                            spacing: Design.s(Design.space.sm)
                            NotificationIcon {
                                Layout.alignment: Qt.AlignTop
                                size: Design.s(Design.size.sm)
                                image: hit.modelData.image || ""
                                appIcon: hit.modelData.appIcon || hit.modelData.icon || ""
                                critical: !!hit.modelData.critical
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                RowLayout {
                                    Layout.fillWidth: true
                                    Label {
                                        Layout.fillWidth: true
                                        text: hit.modelData.summary
                                        weight: Design.weight.semibold
                                        elide: Text.ElideRight
                                    }
                                    Label {
                                        text: Notifications.relTime(hit.modelData.ts)
                                        role: "caption"
                                        dim: true
                                        tabular: true
                                    }
                                }
                                Label {
                                    Layout.fillWidth: true
                                    visible: text !== ""
                                    text: hit.modelData.body
                                    role: "caption"
                                    color: Design.textDim
                                    wrapMode: Text.WordWrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                }
                                Label {
                                    text: hit.modelData.appName
                                    role: "caption"
                                    color: Design.textFaint
                                }
                            }
                        }
                    }
                }
            }
        }

        AppState {
            Layout.fillWidth: true
            Layout.fillHeight: true
            mode: page.searching && page.found.length === 0 ? "empty" : ""
            icon: "\u{f0349}"
            title: I18n.tr("Nothing found")
            hint: I18n.tr("Notifications are kept for 7 days.")
        }

        ScrollArea {
            id: scroll
            framed: false
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: Notifications.history.count > 0 && !page.searching

            ColumnLayout {
                width: scroll.availableWidth
                spacing: Design.s(Design.space.sm)

                Repeater {
                    model: page.sections
                    delegate: ColumnLayout {
                        id: section
                        required property var modelData
                        // Now and today open; yesterday and earlier one line until opened.
                        readonly property bool open: modelData.id === "now" || modelData.id === "today"
                                                     || !!page.opened[modelData.id]
                        Layout.fillWidth: true
                        spacing: Design.s(Design.space.sm)

                        Label {
                            Layout.topMargin: Design.s(Design.space.xs)
                            text: page.sectionTitle(section.modelData.id)
                            role: "caption"
                            weight: Design.weight.semibold
                            dim: true
                        }

                        // Folded: the apps' icons and how many.
                        Box {
                            Layout.fillWidth: true
                            visible: !section.open
                            implicitHeight: Design.s(Design.size.row)
                            radius: Design.s(Design.radius.card)
                            color: foldArea.containsMouse ? Design.stateHover : Design.glassCard
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Design.s(Design.space.md)
                                anchors.rightMargin: Design.s(Design.space.md)
                                spacing: Design.s(Design.space.xs)
                                Repeater {
                                    model: section.modelData.apps.slice(0, 3)
                                    delegate: Picture {
                                        required property string modelData
                                        Layout.preferredWidth: Design.s(Design.size.xs)
                                        Layout.preferredHeight: Design.s(Design.size.xs)
                                        source: modelData
                                        sourceSize: Qt.size(64, 64)
                                        fillMode: Image.PreserveAspectFit
                                        mipmap: true
                                    }
                                }
                                Label {
                                    Layout.fillWidth: true
                                    Layout.leftMargin: Design.s(Design.space.xs)
                                    text: I18n.trn("%1 notification", "%1 notifications", section.modelData.items)
                                    role: "caption"
                                    dim: true
                                    elide: Text.ElideRight
                                }
                                Icon { text: "\u{f0140}"; color: Design.textDim }
                            }
                            Clickable {
                                id: foldArea
                                anchors.fill: parent
                                onClicked: page.toggleSection(section.modelData.id)
                            }
                        }

                        Repeater {
                            model: section.open ? section.modelData.cards : []
                            delegate: Box {
                                id: card
                                required property var modelData
                                readonly property var item: Notifications.history.get(card.modelData.newest)
                                readonly property var actions: (card.item && card.item.obj && card.item.obj.actions
                                    ? card.item.obj.actions : []).filter(a => a.identifier !== "default")
                                readonly property int count: card.modelData.indices.length
                                Layout.fillWidth: true
                                implicitHeight: body.implicitHeight + Design.s(Design.space.md) * 2
                                radius: Design.s(Design.radius.card)
                                color: cardHover.hovered ? Design.stateHover : Design.glassCard
                                Box {
                                    anchors.fill: parent
                                    visible: !!(card.item && card.item.critical)
                                    radius: parent.radius
                                    color: Design.warnSoft
                                }

                                HoverHandler { id: cardHover }
                                PointerArea {
                                    anchors.fill: parent
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onClicked: mouse => {
                                        if (mouse.button === Qt.RightButton) page.dismissCard(card.modelData);
                                        else Notifications.activate(card.item);
                                    }
                                }

                                RowLayout {
                                    id: body
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.top: parent.top
                                    anchors.margins: Design.s(Design.space.md)
                                    spacing: Design.s(Design.space.md)

                                    NotificationIcon {
                                        id: icon
                                        Layout.alignment: Qt.AlignTop
                                        size: Design.s(Design.size.md)
                                        image: card.item ? (card.item.image || "") : ""
                                        appIcon: card.item ? (card.item.appIcon || card.item.icon || "") : ""
                                        critical: !!(card.item && card.item.critical)
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: Design.s(Design.space.xxs)
                                        RowLayout {
                                            Layout.fillWidth: true
                                            spacing: Design.s(Design.space.sm)
                                            Label {
                                                Layout.fillWidth: true
                                                text: card.item ? card.item.summary + (card.count > 1 ? " · " + card.count : "") : ""
                                                weight: Design.weight.semibold
                                                elide: Text.ElideRight
                                            }
                                            Label {
                                                text: card.item ? (card.item.ts ? Notifications.relTime(card.item.ts) : card.item.time) : ""
                                                role: "caption"
                                                dim: true
                                                tabular: true
                                            }
                                            IconButton {
                                                visible: cardHover.hovered
                                                icon: "\u{f0156}"
                                                role: "caption"
                                                onClicked: page.dismissCard(card.modelData)
                                            }
                                        }
                                        // Its lines, oldest first; a long run shows its last four.
                                        Label {
                                            visible: card.modelData.lines.length > 4
                                            text: I18n.trn("%1 earlier", "%1 earlier", card.modelData.lines.length - 4)
                                            role: "caption"
                                            color: Design.textFaint
                                        }
                                        Repeater {
                                            model: card.modelData.lines.slice(-4)
                                            delegate: Label {
                                                required property string modelData
                                                Layout.fillWidth: true
                                                text: modelData
                                                role: "caption"
                                                color: Design.textDim
                                                wrapMode: Text.WordWrap
                                                maximumLineCount: 3
                                                elide: Text.ElideRight
                                            }
                                        }
                                        Label {
                                            visible: !!card.item && card.item.appName !== "" && !icon.hasAvatar
                                                     && card.item.appName !== card.item.summary
                                            text: card.item ? card.item.appName : ""
                                            role: "caption"
                                            color: Design.textFaint
                                        }
                                        Picture {
                                            visible: icon.isPicture
                                            Layout.topMargin: Design.s(Design.space.xxs)
                                            Layout.preferredWidth: Math.min(parent.width, Design.s(Design.size.thumb) * 1.5)
                                            Layout.preferredHeight: Layout.preferredWidth * 9 / 16
                                            source: icon.isPicture && card.item ? card.item.image : ""
                                            sourceSize: Qt.size(360, 202)
                                            fillMode: Image.PreserveAspectCrop
                                            asynchronous: true
                                        }
                                        // What the app offers, while it still can.
                                        Flow {
                                            Layout.fillWidth: true
                                            Layout.topMargin: Design.s(Design.space.xs)
                                            visible: card.actions.length > 0
                                            spacing: Design.s(Design.space.xs)
                                            Repeater {
                                                model: card.actions
                                                delegate: Chip {
                                                    required property var modelData
                                                    label: modelData.text || I18n.tr("Open")
                                                    onClicked: if (typeof modelData.invoke === "function") modelData.invoke()
                                                }
                                            }
                                        }
                                        ReplyField {
                                            Layout.fillWidth: true
                                            Layout.topMargin: Design.s(Design.space.xs)
                                            visible: !!(card.item && card.item.obj && card.item.obj.hasInlineReply)
                                            item: card.item
                                        }
                                    }
                                }
                            }
                        }

                        // An opened old section folds again.
                        Button {
                            Layout.alignment: Qt.AlignRight
                            visible: section.open && !!page.opened[section.modelData.id]
                            size: "sm"
                            variant: "ghost"
                            label: I18n.tr("Show less")
                            onClicked: page.toggleSection(section.modelData.id)
                        }
                    }
                }
            }
        }

        AppState {
            Layout.fillWidth: true
            Layout.fillHeight: true
            mode: !page.searching && Notifications.history.count === 0 ? "empty" : ""
            icon: "\u{f009b}"
            title: I18n.tr("No notifications")
            hint: I18n.tr("You're all caught up.")
        }

        // ── Widgets under the list, as a notification centre has them ────────
        RowLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.sm)

            Surface {
                visible: Weather.loaded
                Layout.fillWidth: true
                Layout.preferredHeight: Design.s(Design.size.avatar)
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Design.s(Design.space.md)
                    spacing: 0
                    Label { text: Weather.location; role: "caption"; weight: Design.weight.semibold; elide: Text.ElideRight; Layout.fillWidth: true }
                    RowLayout {
                        Label { text: Weather.temp; role: "display"; weight: Design.weight.medium; tabular: true }
                        Item { Layout.fillWidth: true }
                        Icon { text: Weather.icon; role: "title"; color: Design.textDim }
                    }
                    Label { text: Weather.condition; role: "caption"; dim: true; elide: Text.ElideRight; Layout.fillWidth: true }
                }
            }

            Surface {
                Layout.fillWidth: true
                Layout.preferredHeight: Design.s(Design.size.avatar)
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Design.s(Design.space.md)
                    spacing: 0
                    Label { text: I18n.tr("Focus"); role: "caption"; weight: Design.weight.semibold }
                    Label {
                        text: Focus.active ? Focus.remainingText : I18n.tr("%1 min", Focus.workMinutes)
                        role: "display"
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
                Clickable {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Quickshell.execDetached(["b1air-shell", "toggle", "focustime"])
                }
            }
        }
    }
}
