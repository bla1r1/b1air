import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import B1air.Daemon
import Quickshell.Io
import "../Ui"
import "../Services"
import "."

// =============================================================================
// Control Center — the one-click hub, with the mini-settings pages behind it.
// =============================================================================

PopupShell {
    id: center

    padding: Design.space.lg

    property string page: "main"
    property string currentView: (center.page && center.page !== "") ? center.page : "main"

    onPageChanged: currentView = (center.page && center.page !== "") ? center.page : "main"

    // Escape used to close the window from inside a sub-page, so the only way
    // back to the tiles was to reopen the panel.
    escapeHook: function () {
        if (center.currentView === "main")
            return false;
        center.currentView = "main";
        return true;
    }

    function openFull(name, section) {
        Quickshell.execDetached(["b1air-shell", "open", name, section || ""]);
    }

    // ── Tile geometry ────────────────────────────────────────────────────────
    // A two-column grid with an odd number of tiles leaves a hole. The last
    // visible tile fills it instead — the old version tried to decide this per
    // tile and the power branch could never be true.
    // Nine tiles, and this used to add up eight: pickerTile was in neither the
    // count nor the lastTile chain, and it and screenTile had columnSpan pinned
    // to 1 rather than asking spanOf() — so the two of them sat outside the
    // hole-filling mechanism entirely and the grid worked from a tile count
    // that was wrong whenever the dropper was on screen. One list now, in
    // order, which also means a tile the user switches off is one the
    // arithmetic stops counting.
    // Arrange mode. Off by default and never persisted: it is a mode you are
    // in for a few seconds, and a panel that reopens in it would be a panel
    // that looks broken.
    property bool editing: false

    readonly property var tileIds: ["wifi", "bluetooth", "dnd", "nightlight", "powermode",
                                    "gamemode", "caffeine", "screenshot", "dropper", "remote"]
    readonly property var tileById: ({
        "wifi": wifiTile, "bluetooth": btTile, "dnd": dndTile, "nightlight": nightTile,
        "powermode": powerTile, "gamemode": gameTile, "caffeine": caffeineTile,
        "screenshot": screenTile, "dropper": pickerTile, "remote": remoteTile
    })

    /**
     * Whether a tile is on screen at all: the user's choice, and for three of
     * them whether the hardware is there.
     *
     * A function reading Settings and the device services directly, rather than
     * the placement loop reading each tile's own `visible`. That version bailed
     * out when a tile did not exist yet, and a binding that returns before
     * touching anything captures no dependencies and never runs again — so the
     * grid was computed once during construction, found no tiles, and put all
     * nine in cell (0,0). QGridLayoutEngine said so nine times a reload.
     *
     * It also removes a precedence trap: `Power.hasBattery || Power.hasProfiles
     * && shown` parses as `hasBattery || (hasProfiles && shown)`, so a laptop
     * with a battery ignored the choice to hide that tile.
     */
    function tileShown(id) {
        // Hidden while arranging too: a removed tile is in the "Add a widget"
        // tray, not ghosted in place at a third of its opacity, which read as
        // disabled rather than as something to put back.
        if (Settings.isWidgetHidden(Settings.ccHiddenTiles, id))
            return false;
        if (id === "wifi") return Network.hasWifi;
        if (id === "bluetooth") return Network.hasBluetooth;
        if (id === "powermode") return Power.hasBattery || Power.hasProfiles;
        if (id === "remote") return Remote.available;
        return true;
    }

    // Where each tile sits, packed into two columns from the saved order.
    //
    // The grid used to be declaration order with a span decided per tile, and
    // the arithmetic behind it added up eight of the nine — pickerTile was in
    // neither the count nor the last-tile chain, and it and screenTile had
    // columnSpan pinned to 1 rather than asking. Both are gone: this places
    // every tile explicitly, so the order is whatever the user dragged it into
    // and a tile switched off leaves no gap behind.
    readonly property var placement: {
        const arr = Settings.tileArrangement(Settings.ccTileLayout, center.tileIds);
        let out = ({});
        let taken = ({});          // "row,col" -> true
        let lastId = "";

        const free = function (row, col, cols, rows) {
            if (col + cols > 2)
                return false;
            for (let r = row; r < row + rows; r++)
                for (let c = col; c < col + cols; c++)
                    if (taken[r + "," + c])
                        return false;
            return true;
        };

        for (const id of arr.order) {
            if (!center.tileShown(id))
                continue;
            const size = Settings.tileSizeCells(arr.spans[id]);

            // First free block, scanning row by row. An occupancy map rather
            // than a running column counter, because a two-row tile leaves the
            // cell beside it usable and the one under it not — which a counter
            // cannot express, and which is the whole reason a "large" size is
            // possible at all.
            let row = 0;
            let col = 0;
            while (!free(row, col, size.cols, size.rows)) {
                col++;
                if (col > 1) {
                    col = 0;
                    row++;
                }
            }
            for (let r = row; r < row + size.rows; r++)
                for (let c = col; c < col + size.cols; c++)
                    taken[r + "," + c] = true;

            out[id] = { row: row, col: col, cols: size.cols, rows: size.rows };
            lastId = id;
        }

        // An odd number of small tiles leaves a hole at the end; the last one
        // fills it, which is what the old spanOf() was for. Only when it is
        // small — a size the user chose is a size the user gets.
        if (lastId !== "" && out[lastId].cols === 1 && out[lastId].rows === 1) {
            const beside = out[lastId].col === 0 ? 1 : 0;
            if (!taken[out[lastId].row + "," + beside]) {
                out[lastId].col = 0;
                out[lastId].cols = 2;
            }
        }
        return out;
    }

    // A GridLayout sizes a row to its tallest item, and a tile spanning two
    // rows whose implicitHeight is one row tall does not make either of them
    // taller — the second row has nothing else in it, so it collapses to
    // nothing and the tile keeps its single-row height while its stacked
    // contents spill onto whatever is underneath. Asking for the height
    // outright is what makes the span mean anything.
    function tileHeightFor(id) {
        const rows = center.placeOf(id).rows;
        return rows > 1
            ? Design.s(Design.size.tile) * rows + Design.s(Design.space.sm) * (rows - 1)
            : Design.s(Design.size.tile);
    }

    // The frame a card wears while arranging: move it, or take it out.
    component CardFrame: EditFrame {
        property string cardId: ""
        anchors.fill: parent
        active: center.editing
        dropTarget: center.dragOver !== "" && center.dragOver === cardId
        onRemove: Settings.setWidgetHidden("ccHiddenCards", cardId, true)
        onDragMoved: p => center.dragOver = center.itemAt(center.cardIds, center.cardById, cardId, p)
        onDropped: p => {
            center.swapCards(cardId, p);
            center.dragOver = "";
        }
    }

    /** "S", "M" or "L" for the frame's size button. */
    function tileSizeLetter(id) {
        const n = Settings.tileSizeName(Settings.tileArrangement(Settings.ccTileLayout, center.tileIds).spans[id]);
        return n === "large" ? "L" : (n === "medium" ? "M" : "S");
    }

    // Which widget a drag is over, so it can light up as the place it will go.
    property string dragOver: ""

    function itemAt(ids, byId, fromId, scenePos) {
        for (const id of ids) {
            if (id === fromId)
                continue;
            const it = byId[id];
            if (!it || !it.visible)
                continue;
            const local = it.mapFromItem(null, scenePos);
            if (local.x >= 0 && local.y >= 0 && local.x <= it.width && local.y <= it.height)
                return id;
        }
        return "";
    }

    // ── Cards below the tiles ────────────────────────────────────────────────
    // The sliders, weather, media and power-button rows could be switched off
    // and not moved. They are ordered now, from ccCardLayout, the same way the
    // tiles are from ccTileLayout.
    readonly property var cardIds: ["sliders", "weather", "media", "session"]
    readonly property var cardById: ({
        "sliders": slidersCard, "weather": weatherCard, "media": mediaCard, "session": sessionCard
    })
    readonly property var cardOrder: Settings.tileArrangement(Settings.ccCardLayout, center.cardIds).order

    function cardRow(id) { return Math.max(0, center.cardOrder.indexOf(id)); }
    function cardShown(id) { return !Settings.isWidgetHidden(Settings.ccHiddenCards, id); }

    function swapCards(fromId, scenePos) {
        const to = center.itemAt(center.cardIds, center.cardById, fromId, scenePos);
        if (to === "")
            return;
        const arr = Settings.tileArrangement(Settings.ccCardLayout, center.cardIds);
        const a = arr.order.indexOf(fromId);
        const b = arr.order.indexOf(to);
        arr.order[a] = to;
        arr.order[b] = fromId;
        Settings.setTileArrangement("ccCardLayout", arr.order, arr.spans);
    }

    readonly property var widgetTitles: ({
        "wifi": ["Wi-Fi", "\u{f05a9}"], "bluetooth": ["Bluetooth", "\u{f00af}"],
        "dnd": ["Do Not Disturb", "\u{f009b}"], "nightlight": ["Night Light", "\u{f0599}"],
        "powermode": ["Power Mode", "\u{f0e4}"], "gamemode": ["Game Mode", "\u{f11b}"],
        "caffeine": ["Caffeine", "\u{f0f4}"], "screenshot": ["Screenshot", "\u{f016d}"],
        "dropper": ["Color Dropper", "\u{f0592}"], "remote": ["Remote Desktop", "\u{f0379}"], "sliders": ["Brightness & Volume", "\u{f00df}"],
        "weather": ["Weather", "\u{f0590}"], "media": ["Now Playing", "\u{f0025}"],
        "session": ["Power Buttons", "\u{f0425}"]
    })

    readonly property var trayItems: {
        const out = [];
        for (const id of center.tileIds) {
            if (!Settings.isWidgetHidden(Settings.ccHiddenTiles, id)) continue;
            // Not offered where the hardware is not there to drive.
            if (id === "wifi" && !Network.hasWifi) continue;
            if (id === "bluetooth" && !Network.hasBluetooth) continue;
            if (id === "powermode" && !(Power.hasBattery || Power.hasProfiles)) continue;
            out.push({ id: id, kind: "tile", title: I18n.tr(center.widgetTitles[id][0]), icon: center.widgetTitles[id][1] });
        }
        for (const id of center.cardIds)
            if (Settings.isWidgetHidden(Settings.ccHiddenCards, id))
                out.push({ id: id, kind: "card", title: I18n.tr(center.widgetTitles[id][0]), icon: center.widgetTitles[id][1] });
        return out;
    }

    function placeOf(id) {
        return center.placement[id] || ({ row: 0, col: 0, cols: 1, rows: 1 });
    }

    /**
     * Finish a drag: whatever tile the pointer was released over swaps places
     * with the one being dragged. Swap rather than insert — the user asked for
     * "поменять местами", and a swap needs no notion of where between two
     * cells a pointer is, which is the part that goes wrong on a grid.
     */
    function swapTiles(fromId, scenePos) {
        for (const id of center.tileIds) {
            if (id === fromId)
                continue;
            const tile = center.tileById[id];
            if (!tile || !tile.visible)
                continue;
            const local = tile.mapFromItem(null, scenePos);
            if (local.x < 0 || local.y < 0 || local.x > tile.width || local.y > tile.height)
                continue;

            const arr = Settings.tileArrangement(Settings.ccTileLayout, center.tileIds);
            const a = arr.order.indexOf(fromId);
            const b = arr.order.indexOf(id);
            if (a < 0 || b < 0)
                return;
            arr.order[a] = id;
            arr.order[b] = fromId;
            Settings.setTileArrangement("ccTileLayout", arr.order, arr.spans);
            return;
        }
    }

    /** small → medium → large → small. */
    function cycleTileSpan(id) {
        const arr = Settings.tileArrangement(Settings.ccTileLayout, center.tileIds);
        const now = Settings.tileSizeName(arr.spans[id]);
        arr.spans[id] = now === "small" ? "medium" : (now === "medium" ? "large" : "small");
        Settings.setTileArrangement("ccTileLayout", arr.order, arr.spans);
    }

    function setTileSize(id, size) {
        const arr = Settings.tileArrangement(Settings.ccTileLayout, center.tileIds);
        arr.spans[id] = size;
        Settings.setTileArrangement("ccTileLayout", arr.order, arr.spans);
    }

    // A quick-toggle tile: circle toggles, the rest of the tile opens the page.
    component QuickTile: Tile {
        id: tile

        property string glyph: ""
        property string title: ""
        property string detail: ""
        property color glyphTone: tile.on ? tile.activeTextColor : Design.textDim
        property bool circleToggles: true
        // Only a tile that opens a page shows a chevron. Focus does not.
        property string trailingGlyph: "\u{f0142}"
        // Which entry in the saved arrangement this tile is.
        property string widgetId: ""

        signal toggled()

        // ── Rearranging ──────────────────────────────────────────────────────
        //
        // Press and drag a tile onto another and the two swap places; the
        // arrangement is saved, so it survives a restart. A swap rather than an
        // insertion because that is what was asked for, and because a swap
        // needs no decision about which side of a cell boundary a pointer is
        // on — the part of grid reordering that goes wrong.
        //
        // DragHandler has its own threshold, so a press that does not travel is
        // still a click: the circle keeps toggling and the body keeps opening
        // the page. The tile lifts rather than moves, because a GridLayout owns
        // its children's positions and fighting it for them would make the
        // whole grid jump on every frame of the drag.
        opacity: tileFrame.dragging ? 0.85 : 1.0
        z: tileFrame.dragging ? 20 : 0
        scale: tileFrame.dragging ? 1.04 : 1.0
        Behavior on scale { NumberAnimation { duration: Design.duration.fast; easing.type: Design.easing } }
        Behavior on opacity { NumberAnimation { duration: Design.duration.fast } }

        // Arranging: move, resize, remove — all on a frame over the tile,
        // which also keeps a tap from toggling the thing underneath.
        EditFrame {
            id: tileFrame
            anchors.fill: parent
            active: center.editing && tile.widgetId !== ""
            sizeLabel: center.tileSizeLetter(tile.widgetId)
            dropTarget: center.dragOver !== "" && center.dragOver === tile.widgetId
            onRemove: Settings.setWidgetHidden("ccHiddenTiles", tile.widgetId, true)
            onCycleSize: center.cycleTileSpan(tile.widgetId)
            onDragMoved: p => center.dragOver = center.itemAt(center.tileIds, center.tileById, tile.widgetId, p)
            onDropped: p => {
                center.swapTiles(tile.widgetId, p);
                center.dragOver = "";
            }
        }

        // Middle click steps through the sizes, for anyone who knows.
        TapHandler {
            acceptedButtons: Qt.MiddleButton
            enabled: tile.widgetId !== ""
            onTapped: center.cycleTileSpan(tile.widgetId)
        }

        // A large tile is two rows tall, so it has to earn the height rather
        // than centre one line of text in an empty box: the circle grows and
        // the whole thing stacks. Read off the placement, so the tile does not
        // have to be told twice what size it is.
        readonly property bool tall: tile.widgetId !== ""
                                     && center.placeOf(tile.widgetId).rows > 1

        implicitHeight: Design.s(Design.size.tile)
        interactive: true

        GridLayout {
            anchors.fill: parent
            anchors.margins: Design.s(Design.space.sm)
            columns: tile.tall ? 1 : 3
            rowSpacing: Design.s(Design.space.xs)
            columnSpacing: Design.s(Design.space.sm)

            Rectangle {
                Layout.alignment: tile.tall ? Qt.AlignHCenter | Qt.AlignBottom : Qt.AlignVCenter
                Layout.preferredWidth: tile.tall ? Design.s(Design.size.knob) * 1.6
                                                 : Design.s(Design.size.knob)
                Layout.preferredHeight: tile.tall ? Design.s(Design.size.knob) * 1.6
                                                  : Design.s(Design.size.knob)
                radius: width / 2
                color: tile.on ? Design.tint(tile.activeTextColor, 0.22) : Design.sunken
                Behavior on color { ColorAnimation { duration: Design.duration.fast } }

                Icon {
                    anchors.centerIn: parent
                    text: tile.glyph
                    role: tile.tall ? "title" : "subhead"
                    color: tile.glyphTone
                    Behavior on color { ColorAnimation { duration: Design.duration.fast } }
                }

                // Declared inside the tile's own children, so it sits above the
                // tile-wide MouseArea and wins the click.
                Clickable {
                    enabled: tile.circleToggles
                    onClicked: tile.toggled()
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: tile.tall ? Qt.AlignHCenter | Qt.AlignTop : Qt.AlignVCenter
                spacing: 0

                Label {
                    text: tile.title
                    role: tile.tall ? "body" : "caption"
                    weight: Design.weight.bold
                    color: tile.on ? tile.activeTextColor : Design.text
                    Layout.fillWidth: true
                    horizontalAlignment: tile.tall ? Text.AlignHCenter : Text.AlignLeft
                    elide: Text.ElideRight
                }

                Label {
                    text: tile.detail
                    role: "caption"
                    color: tile.on ? Design.tint(tile.activeTextColor, 0.85) : Design.textDim
                    Layout.fillWidth: true
                    horizontalAlignment: tile.tall ? Text.AlignHCenter : Text.AlignLeft
                    elide: Text.ElideRight
                }
            }

            Icon {
                // The chevron is a row-layout affordance; stacked, it has
                // nowhere to point.
                visible: tile.trailingGlyph !== "" && !tile.tall
                text: tile.trailingGlyph
                role: "caption"
                color: tile.on ? Design.tint(tile.activeTextColor, 0.6) : Design.textFaint
            }
        }
    }

    // What this panel would like to be, in pixels of height.
    //
    // The registry gives every popup a fixed size, and its note beside this one
    // explains the 700: "the tile grid, the two sliders, the weather card and
    // the media card add up to roughly 690px". They do — when all of them are
    // there. Switch three tiles and two cards off and the panel still opened at
    // 700 with a third of it empty below the last button. The number in the
    // registry is a ceiling now and this is the request; the smaller wins.
    //
    // Zero on the mini pages, which say nothing and so keep the full height.
    onCurrentViewChanged: if (center.currentView !== "main") center.editing = false;

    readonly property real contentHeight: center.currentView === "main"
        ? mainScroll.contentHeight + 2 * Design.s(center.padding)
        : 0

    // ── Main dashboard ───────────────────────────────────────────────────────
    // The tile grid plus every mini-view below it never fit the popup's fixed
    // height once more than a couple of tiles were visible — content past the
    // bottom just clipped, with no way to reach it. A Flickable lets it
    // scroll instead; the ColumnLayout keeps its own layout unchanged, it's
    // just no longer forced to exactly the popup's height.
    Flickable {
        id: mainScroll
        anchors.fill: parent
        visible: center.currentView === "main"
        contentWidth: width

        // The trailing gap is the point: without it the last card ended flush
        // against the panel's rounded bottom edge, so a card that happened to
        // land there looked sliced off rather than scrolled past.
        contentHeight: mainColumn.implicitHeight + Design.s(Design.space.md)
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ScrollBar.vertical: OverflowBar {}

    ColumnLayout {
        id: mainColumn

        // Step aside for the scrollbar rather than running under it: at full
        // width the right-hand column of tiles had its edge and its chevron
        // painted over by the bar.
        width: parent.width - (mainScroll.ScrollBar.vertical.visible
            ? mainScroll.ScrollBar.vertical.width + Design.s(Design.space.xs) : 0)
        spacing: Design.s(Design.space.md)

        // ── 1. Header ────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.sm)

            Icon {
                text: "\u{f062e}"   // sliders; the bar's button uses the same
                role: "subhead"
                color: Design.accent
            }

            Label {
                text: center.editing ? I18n.tr("Arrange") : I18n.tr("Control Center")
                role: "subhead"
                weight: Design.weight.bold
                color: center.editing ? Design.accent : Design.text
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            // In edit mode the header is the instruction and the way out, and
            // nothing else: a battery pill and a bell that open other pages
            // while you are rearranging tiles are two ways to lose the work.
            Label {
                visible: center.editing
                text: I18n.tr("drag to move · S M L to size · × to remove")
                role: "caption"
                color: Design.textDim
                elide: Text.ElideRight
            }

            BatteryPill {
                visible: !center.editing
                Layout.alignment: Qt.AlignVCenter
                onClicked: center.currentView = "power"
            }

            IconButton {
                visible: !center.editing
                icon: Notifications.history.count > 0 ? "\u{f009a}" : "\u{f009b}"
                bordered: true
                hoverTone: Design.accent
                onClicked: center.currentView = (center.currentView === "notifications" ? "main" : "notifications")
            }

            // Rearranging happens here, in front of the thing being rearranged,
            // rather than as a list of switches in another window where the
            // only way to see the result is to close it and open this.
            IconButton {
                icon: center.editing ? "\u{f012c}" : "\u{f03eb}"   // check / tune
                bordered: true
                hoverTone: Design.accent
                onClicked: center.editing = !center.editing
            }

            IconButton {
                visible: !center.editing
                icon: "\u{f0493}"   // cog
                bordered: true
                onClicked: {
                    Quickshell.execDetached(["b1air-settings"]);
                    window.close();
                }
            }
        }

        // ── 2. Quick toggles ─────────────────────────────────────────────────
        GridLayout {
            Layout.fillWidth: true
            // Always two: every tile now names its own row and column, and a
            // lone visible tile is widened to span both by the packer.
            columns: 2
            // Wider while arranging, for the toolbars on each tile's top edge.
            rowSpacing: Design.s(center.editing ? Design.space.lg : Design.space.sm)
            columnSpacing: Design.s(Design.space.sm)

            QuickTile {
                id: wifiTile
                Layout.fillWidth: true
                widgetId: "wifi"
                Layout.row: center.placeOf("wifi").row
                Layout.column: center.placeOf("wifi").col
                Layout.columnSpan: center.placeOf("wifi").cols
                Layout.rowSpan: center.placeOf("wifi").rows
                Layout.preferredHeight: center.tileHeightFor("wifi")
                visible: center.tileShown("wifi")
                glyph: "\u{f0928}"
                title: I18n.tr("Wi-Fi")
                on: Network.wifi.power === "on"
                activeColor: Design.blue
                detail: Network.wifi.connected ? Network.wifi.connected.ssid
                                               : (on ? I18n.tr("Not connected") : I18n.tr("Off"))
                onToggled: Network.toggleWifi()
                onActivated: center.currentView = "wifi"
            }

            QuickTile {
                id: btTile
                Layout.fillWidth: true
                widgetId: "bluetooth"
                Layout.row: center.placeOf("bluetooth").row
                Layout.column: center.placeOf("bluetooth").col
                Layout.columnSpan: center.placeOf("bluetooth").cols
                Layout.rowSpan: center.placeOf("bluetooth").rows
                Layout.preferredHeight: center.tileHeightFor("bluetooth")
                visible: center.tileShown("bluetooth")
                glyph: "\u{f00af}"
                title: I18n.tr("Bluetooth")
                on: Network.bluetooth.power === "on"
                activeColor: Design.mauve
                detail: Network.bluetooth.connected ? Network.bluetooth.connected.name
                                                    : (on ? I18n.tr("No device") : I18n.tr("Off"))
                onToggled: Network.toggleBluetooth()
                onActivated: center.currentView = "bluetooth"
            }

            QuickTile {
                id: dndTile
                Layout.fillWidth: true
                widgetId: "dnd"
                Layout.row: center.placeOf("dnd").row
                Layout.column: center.placeOf("dnd").col
                Layout.columnSpan: center.placeOf("dnd").cols
                Layout.rowSpan: center.placeOf("dnd").rows
                Layout.preferredHeight: center.tileHeightFor("dnd")
                visible: center.tileShown("dnd")
                glyph: Notifications.dnd ? "\u{f009b}" : "\u{f009a}"
                // "Focus" meant three things: this tile, the FocusTime
                // dashboard, and the work phase of the focus timer. It is the
                // Do Not Disturb switch — its id has said so all along — so it
                // says so too. And its detail line read "Active" when
                // notifications were *not* silenced, which is the opposite of
                // how the word reads next to a tile that is lit when on.
                title: I18n.tr("Do Not Disturb")
                on: Notifications.dnd
                activeColor: Design.peach
                detail: Notifications.dnd ? I18n.tr("Silenced") : I18n.tr("Off")
                trailingGlyph: ""
                onToggled: Notifications.toggleDnd()
                onActivated: Notifications.toggleDnd()
            }

            QuickTile {
                id: nightTile
                Layout.fillWidth: true
                widgetId: "nightlight"
                Layout.row: center.placeOf("nightlight").row
                Layout.column: center.placeOf("nightlight").col
                Layout.columnSpan: center.placeOf("nightlight").cols
                Layout.rowSpan: center.placeOf("nightlight").rows
                Layout.preferredHeight: center.tileHeightFor("nightlight")
                visible: center.tileShown("nightlight")
                glyph: "\u{f0599}"
                title: I18n.tr("Night Light")
                on: Settings.nightLightEnabled
                activeColor: Design.yellow
                glyphTone: on ? Design.yellow : Design.textDim
                detail: on ? I18n.tr("Warm (%1K)", Settings.nightLightTemp) : I18n.tr("Off")
                // Through the daemon, like the Settings page. The command that
                // was here passed wlsunset equal -t and -T, which it refuses,
                // so this tile had never changed the screen.
                onToggled: {
                    const next = !Settings.nightLightEnabled;
                    Settings.set("nightLightEnabled", next);
                    Quickshell.execDetached(next
                        ? ["b1air-daemon", "night-light", "on", String(Settings.nightLightTemp), "--quiet"]
                        : ["b1air-daemon", "night-light", "off", "--quiet"]);
                }
                onActivated: center.openFull("nightlight")
            }

            QuickTile {
                id: powerTile
                Layout.fillWidth: true
                widgetId: "powermode"
                Layout.row: center.placeOf("powermode").row
                Layout.column: center.placeOf("powermode").col
                Layout.columnSpan: center.placeOf("powermode").cols
                Layout.rowSpan: center.placeOf("powermode").rows
                Layout.preferredHeight: center.tileHeightFor("powermode")
                visible: center.tileShown("powermode")
                glyph: Power.profile === "performance" ? "\u{f0e4}"
                     : (Power.profile === "power-saver" ? "\u{f0084}" : "\u{f0241}")
                title: I18n.tr("Power Mode")
                on: false
                activeColor: powerTile.profileTone
                glyphTone: powerTile.profileTone
                detail: Power.profile === "performance" ? I18n.tr("Performance")
                      : (Power.profile === "power-saver" ? I18n.tr("Power Saver") : I18n.tr("Balanced"))

                readonly property color profileTone: Power.profile === "performance" ? Design.red
                    : (Power.profile === "power-saver" ? Design.green : Design.sapphire)

                onToggled: Power.setProfile(Power.profile === "balanced" ? "performance"
                                          : (Power.profile === "performance" ? "power-saver" : "balanced"))
                onActivated: center.currentView = "power"
            }

            QuickTile {
                id: gameTile
                Layout.fillWidth: true
                widgetId: "gamemode"
                Layout.row: center.placeOf("gamemode").row
                Layout.column: center.placeOf("gamemode").col
                Layout.columnSpan: center.placeOf("gamemode").cols
                Layout.rowSpan: center.placeOf("gamemode").rows
                Layout.preferredHeight: center.tileHeightFor("gamemode")
                visible: center.tileShown("gamemode")
                glyph: "\u{f11b}"
                title: I18n.tr("Game Mode")
                on: Settings.gameModeEnabled !== undefined ? Settings.gameModeEnabled : false
                activeColor: Design.red
                glyphTone: on ? Design.red : Design.textDim
                detail: on ? I18n.tr("Performance") : I18n.tr("Off")
                trailingGlyph: ""
                onToggled: {
                    const next = !(Settings.gameModeEnabled !== undefined ? Settings.gameModeEnabled : false);
                    Settings.set("gameModeEnabled", next);
                    Quickshell.execDetached(["b1air-daemon", "game-mode", next ? "on" : "off"]);
                }
                // "settings:gamemode" arrived as target "settings:gamemode" and was
                // split on the colon into page "gamemode:", which is no page.
                onActivated: center.openFull("settings", "gamemode")
            }

            QuickTile {
                id: remoteTile
                Layout.fillWidth: true
                widgetId: "remote"
                Layout.row: center.placeOf("remote").row
                Layout.column: center.placeOf("remote").col
                Layout.columnSpan: center.placeOf("remote").cols
                Layout.rowSpan: center.placeOf("remote").rows
                Layout.preferredHeight: center.tileHeightFor("remote")
                visible: center.tileShown("remote")
                glyph: "\u{f0379}"
                title: I18n.tr("Remote Desktop")
                on: Remote.running
                // Red while someone is actually watching: that is the state
                // worth noticing, not the server merely listening.
                activeColor: Remote.clients > 0 ? Design.red : Design.blue
                glyphTone: on ? activeColor : Design.textDim
                detail: !on ? I18n.tr("Off")
                      : Remote.clients > 0 ? I18n.trn("%1 viewer connected", "%1 viewers connected", Remote.clients)
                      : I18n.tr("Waiting on port %1", Remote.port)
                trailingGlyph: ""
                onToggled: Remote.toggle()
                onActivated: center.openFull("settings", "remote")
                Connections {
                    target: Remote
                    // No password saved yet: the page where one is set.
                    function onNeedsSetup() { center.openFull("settings", "remote"); }
                }
            }

            QuickTile {
                id: caffeineTile
                Layout.fillWidth: true
                widgetId: "caffeine"
                Layout.row: center.placeOf("caffeine").row
                Layout.column: center.placeOf("caffeine").col
                Layout.columnSpan: center.placeOf("caffeine").cols
                Layout.rowSpan: center.placeOf("caffeine").rows
                Layout.preferredHeight: center.tileHeightFor("caffeine")
                visible: center.tileShown("caffeine")
                glyph: "\u{f0f4}"
                title: I18n.tr("Caffeine")
                // Asked of the daemon, which holds the inhibitor. This was a
                // property of the tile starting at false, so after the shell
                // restarted — or anything else switched it — the tile said
                // "Sleep Normal" over a machine that would not sleep.
                property bool active: false
                on: caffeineTile.active
                activeColor: Design.teal
                glyphTone: on ? Design.teal : Design.textDim
                detail: on ? I18n.tr("Stay Awake") : I18n.tr("Sleep Normal")
                trailingGlyph: ""
                function flip() {
                    caffeineTile.active = !caffeineTile.active;
                    caffeineSet.command = ["b1air-daemon", "caffeine", caffeineTile.active ? "on" : "off"];
                    caffeineSet.running = false;
                    caffeineSet.running = true;
                }
                onToggled: caffeineTile.flip()
                onActivated: caffeineTile.flip()

                Process {
                    id: caffeineSet
                    onExited: { caffeineProbe.running = false; caffeineProbe.running = true; }
                }
                Process {
                    id: caffeineProbe
                    running: center.visible
                    command: ["b1air-daemon", "caffeine", "status"]
                    stdout: StdioCollector {
                        onStreamFinished: caffeineTile.active = this.text.trim() === "active"
                    }
                }
            }

            QuickTile {
                id: screenTile
                Layout.fillWidth: true
                widgetId: "screenshot"
                Layout.row: center.placeOf("screenshot").row
                Layout.column: center.placeOf("screenshot").col
                Layout.columnSpan: center.placeOf("screenshot").cols
                Layout.rowSpan: center.placeOf("screenshot").rows
                Layout.preferredHeight: center.tileHeightFor("screenshot")
                visible: center.tileShown("screenshot")
                glyph: "\u{f016d}"
                title: I18n.tr("Screenshot")
                on: false
                circleToggles: false
                activeColor: Design.pink
                glyphTone: Design.pink
                detail: I18n.tr("Capture area")
                trailingGlyph: ""
                onActivated: {
                    center.close();
                    Quickshell.execDetached(["b1air-daemon", "screenshot", "area"]);
                }
            }

            QuickTile {
                id: pickerTile
                Layout.fillWidth: true
                widgetId: "dropper"
                Layout.row: center.placeOf("dropper").row
                Layout.column: center.placeOf("dropper").col
                Layout.columnSpan: center.placeOf("dropper").cols
                Layout.rowSpan: center.placeOf("dropper").rows
                Layout.preferredHeight: center.tileHeightFor("dropper")
                visible: center.tileShown("dropper")
                glyph: "\u{f0592}"
                title: I18n.tr("Color Dropper")
                on: false
                circleToggles: false
                activeColor: Design.sapphire
                glyphTone: Design.sapphire
                detail: I18n.tr("Pick from screen")
                trailingGlyph: ""
                onActivated: {
                    center.close();
                    Quickshell.execDetached(["b1air-daemon", "color-picker"]);
                }
            }
        }

        // ── Add a widget (arranging only) ────────────────────────────────────
        WidgetTray {
            Layout.fillWidth: true
            active: center.editing
            items: center.trayItems
            onAdd: id => {
                const it = center.trayItems.find(x => x.id === id);
                if (it)
                    Settings.setWidgetHidden(it.kind === "tile" ? "ccHiddenTiles" : "ccHiddenCards", id, false);
            }
        }

        // ── Cards, in the saved order ────────────────────────────────────────
        // A one-column GridLayout rather than a ColumnLayout, because a grid
        // takes an explicit row per child and a column layout only takes
        // declaration order.
        GridLayout {
            Layout.fillWidth: true
            columns: 1
            rowSpacing: Design.s(center.editing ? Design.space.lg : Design.space.md)

        // ── 3. Sliders ───────────────────────────────────────────────────────
        Item {
            id: slidersCard
            Layout.fillWidth: true
            Layout.row: center.cardRow("sliders")
            visible: center.cardShown("sliders")
            implicitHeight: slidersCol.implicitHeight
            opacity: slidersFrame.dragging ? 0.85 : 1.0

        ColumnLayout {
            id: slidersCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            spacing: Design.s(Design.space.sm)

            Slider {
                visible: Power.hasBacklight
                Layout.fillWidth: true
                Layout.preferredHeight: Design.s(Design.size.ctl)
                value: Power.brightness
                tone: Design.yellow
                icon: "\u{f00df}"
                label: I18n.tr("Brightness")
                onMoved: pct => Power.setBrightness(pct)
            }

            // No sink, no slider. A volume control with nothing behind it is a
            // dead control, not information.
            RowLayout {
                visible: Audio.rawSink !== null || Audio.hasAudio
                Layout.fillWidth: true
                spacing: Design.s(Design.space.xs)

                Slider {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Design.s(Design.size.ctl)
                    value: Audio.volumePercent
                    muted: Audio.muted
                    tone: Design.sapphire
                    icon: Audio.muted ? "\u{f075f}" : "\u{f057f}"
                    label: I18n.tr("Volume")
                    iconClickable: true
                    onIconClicked: Audio.toggleMasterMute()
                    onMoved: pct => Audio.setMasterVolume(pct)
                }

                Rectangle {
                    Layout.preferredWidth: Design.s(Design.size.ctl)
                    Layout.preferredHeight: Design.s(Design.size.ctl)
                    radius: Design.s(Design.radius.ctl)
                    color: soundBtnMa.containsMouse ? Design.glassHover : Design.glassCard
                    border.color: Design.glassBorder
                    border.width: Design.border
                    Behavior on color { ColorAnimation { duration: Design.duration.fast } }

                    Icon {
                        anchors.centerIn: parent
                        text: "\u{f0142}"
                        role: "caption"
                        color: soundBtnMa.containsMouse ? Design.accent : Design.textDim
                    }

                    Clickable { id: soundBtnMa; onClicked: center.currentView = "sound" }
                }
            }

        }

            CardFrame { id: slidersFrame; cardId: "sliders" }
        }

        // ── 3.5 Live Weather Card ──────────────────────────────────────────
        Rectangle {
            id: weatherCard
            Layout.fillWidth: true
            Layout.row: center.cardRow("weather")
            visible: center.cardShown("weather")
            Layout.preferredHeight: Design.s(52)
            radius: Design.s(Design.radius.card)
            color: Design.glassCard
            border.color: Design.glassBorder
            border.width: Design.border

            CardFrame { cardId: "weather" }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Design.s(Design.space.md)
                anchors.rightMargin: Design.s(Design.space.md)
                spacing: Design.s(Design.space.md)

                Rectangle {
                    Layout.preferredWidth: Design.s(34)
                    Layout.preferredHeight: Design.s(34)
                    radius: Design.s(Design.radius.ctl)
                    color: Design.tint(Design.yellow, 0.15)

                    Icon {
                        anchors.centerIn: parent
                        text: Weather.icon
                        role: "subhead"
                        color: Design.yellow
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    Label {
                        text: Weather.condition + " • " + Weather.temp
                        weight: Design.weight.semibold
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }

                    Label {
                        text: Weather.location
                        role: "caption"
                        color: Design.textDim
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }
                }

                Badge {
                    text: I18n.tr("Live")
                    tone: Design.ok
                }
            }
        }

        // ── 4. Media ─────────────────────────────────────────────────────────
        Rectangle {
            id: mediaCard
            Layout.fillWidth: true
            Layout.row: center.cardRow("media")
            visible: center.cardShown("media")
            Layout.preferredHeight: Design.s(Design.size.media)
            radius: Design.s(Design.radius.card)
            color: Design.glassCard
            border.color: Design.glassBorder
            border.width: Design.border

            CardFrame { cardId: "media" }

            RowLayout {
                anchors.fill: parent
                anchors.margins: Design.s(Design.space.md)
                spacing: Design.s(Design.space.md)

                Rectangle {
                    Layout.preferredWidth: Design.s(Design.size.art)
                    Layout.preferredHeight: Design.s(Design.size.art)
                    radius: Design.s(Design.radius.ctl)
                    color: Design.sunken
                    clip: true

                    Image {
                        anchors.fill: parent
                        // Decoded at the size drawn, not the file's (a 4K picture is 33 MB of pixels).
                        sourceSize: Qt.size(256, 256)
                        source: Media.track.artUrl || ""
                        fillMode: Image.PreserveAspectCrop
                        visible: source !== ""
                    }

                    Icon {
                        anchors.centerIn: parent
                        visible: !Media.track.artUrl
                        text: "\u{f0025}"
                        role: "subhead"
                        color: Media.playing ? Design.accent : Design.textFaint
                    }
                }

                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Design.s(36)

                    ColumnLayout {
                        anchors.fill: parent
                        spacing: 2

                        Label {
                            text: Media.track.title || (Media.hasPlayer ? I18n.tr("Nothing playing") : I18n.tr("No media player"))
                            weight: Design.weight.semibold
                            color: Media.hasPlayer ? Design.text : Design.textDim
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }

                        Label {
                            text: Media.track.artist || (Media.hasPlayer ? I18n.tr("Press play to resume") : I18n.tr("Start one to control it here"))
                            role: "caption"
                            dim: true
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: Media.hasPlayer
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: center.openFull("music")
                    }
                }

                RowLayout {
                    spacing: Design.s(Design.space.xs)
                    opacity: Media.hasPlayer ? Design.opacity.full : Design.opacity.disabled
                    enabled: Media.hasPlayer
                    Behavior on opacity { NumberAnimation { duration: Design.duration.fast } }

                    IconButton {
                        icon: "\u{f04ae}"
                        role: "caption"
                        hoverTone: Design.text
                        onClicked: Media.previous()
                    }

                    Rectangle {
                        Layout.preferredWidth: Design.s(Design.size.knob)
                        Layout.preferredHeight: Design.s(Design.size.knob)
                        radius: width / 2
                        color: Design.accent

                        scale: playMa.pressed ? 0.92 : 1.0
                        Behavior on scale { NumberAnimation { duration: Design.duration.fast; easing.type: Design.easing } }

                        Icon {
                            anchors.centerIn: parent
                            text: Media.playing ? "\u{f03e4}" : "\u{f040a}"
                            role: "body"
                            color: Design.contrastOn(Design.accent)
                        }

                        Clickable { id: playMa; onClicked: Media.playPause() }
                    }

                    IconButton {
                        icon: "\u{f04ad}"
                        role: "caption"
                        hoverTone: Design.text
                        onClicked: Media.next()
                    }
                }
            }
        }

        // ── 5. Session actions ───────────────────────────────────────────────
        Item {
            id: sessionCard
            Layout.fillWidth: true
            Layout.row: center.cardRow("session")
            visible: center.cardShown("session")
            implicitHeight: sessionRow.implicitHeight

        RowLayout {
            id: sessionRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            spacing: Design.s(Design.space.sm)

            ActionButton {
                icon: "\u{f033e}"
                label: I18n.tr("Lock")
                onActivated: Daemon.lock()
            }

            ActionButton {
                icon: "\u{f04b2}"
                label: I18n.tr("Sleep")
                onActivated: Daemon.power("suspend")
            }

            ActionButton {
                icon: "\u{f0709}"
                label: I18n.tr("Reboot")
                iconTone: Design.peach
                tone: Design.peach
                destructive: true
                onActivated: Daemon.power("reboot")
            }

            ActionButton {
                icon: "\u{f0425}"
                label: I18n.tr("Off")
                iconTone: Design.danger
                tone: Design.danger
                destructive: true
                onActivated: Daemon.power("shutdown")
            }

        }

            CardFrame { cardId: "session" }
        }
        }
    }
    }

    // ── Mini-settings pages ──────────────────────────────────────────────────
    // Built when opened, not with the Control Center: all five were created
    // every time it opened, hidden behind the tile grid. Measured on a fresh
    // shell, opening the Control Center added 36 MB that stayed after it
    // closed.
    Loader {
        anchors.fill: parent
        active: center.currentView === "wifi"
        sourceComponent: Component {
            WifiMiniView {
                onBackClicked: center.currentView = "main"
                onOpenFullSettings: center.openFull("settings", "network")
            }
        }
    }

    Loader {
        anchors.fill: parent
        active: center.currentView === "bluetooth"
        sourceComponent: Component {
            BluetoothMiniView {
                onBackClicked: center.currentView = "main"
                onOpenFullSettings: center.openFull("settings", "bluetooth")
            }
        }
    }

    Loader {
        anchors.fill: parent
        active: center.currentView === "sound"
        sourceComponent: Component {
            SoundMiniView {
                onBackClicked: center.currentView = "main"
                onOpenFullSettings: center.openFull("settings", "audio")
            }
        }
    }

    Loader {
        anchors.fill: parent
        active: center.currentView === "power"
        sourceComponent: Component {
            PowerMiniView {
                onBackClicked: center.currentView = "main"
                onOpenFullSettings: center.openFull("settings", "power")
            }
        }
    }

    Loader {
        anchors.fill: parent
        active: center.currentView === "notifications"
        sourceComponent: Component {
            NotificationsMiniView {
                onBackClicked: center.currentView = "main"
                // Notification rules live on the Screen Time & DND page.
                onOpenFullSettings: center.openFull("settings", "focus")
            }
        }
    }

    Component.onCompleted: {
        Audio.acquire(); Power.acquire(); Media.acquire(); Network.acquire();
    }
    Component.onDestruction: {
        Audio.release(); Power.release(); Media.release(); Network.release();
    }
}
