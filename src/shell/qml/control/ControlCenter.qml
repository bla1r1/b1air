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
                                    "gamemode", "caffeine", "screenshot", "dropper"]
    readonly property var tileById: ({
        "wifi": wifiTile, "bluetooth": btTile, "dnd": dndTile, "nightlight": nightTile,
        "powermode": powerTile, "gamemode": gameTile, "caffeine": caffeineTile,
        "screenshot": screenTile, "dropper": pickerTile
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
        if (!center.editing && Settings.isWidgetHidden(Settings.ccHiddenTiles, id))
            return false;
        if (id === "wifi") return Network.hasWifi;
        if (id === "bluetooth") return Network.hasBluetooth;
        if (id === "powermode") return Power.hasBattery || Power.hasProfiles;
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

    // The remove/restore badge, wherever a thing that can be hidden is drawn.
    component EditBadge: Rectangle {
        id: badge
        property string listKey: ""
        property string widgetId: ""
        readonly property bool off: Settings.isWidgetHidden(
            badge.listKey === "ccHiddenCards" ? Settings.ccHiddenCards : Settings.ccHiddenTiles,
            badge.widgetId)

        visible: center.editing
        width: Design.s(20)
        height: Design.s(20)
        radius: width / 2
        z: 25
        color: badge.off ? Design.tint(Design.ok, 0.85) : Design.tint(Design.red, 0.85)

        Icon {
            anchors.centerIn: parent
            text: badge.off ? "\u{f0415}" : "\u{f0156}"
            role: "caption"
            color: Design.accentText
        }

        TapHandler {
            onTapped: Settings.setWidgetHidden(badge.listKey, badge.widgetId, !badge.off)
        }
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
        readonly property bool tileHidden: tile.widgetId !== ""
            && Settings.isWidgetHidden(Settings.ccHiddenTiles, tile.widgetId)

        opacity: tileDrag.active ? 0.85 : (tile.tileHidden ? 0.35 : 1.0)

        DragHandler {
            id: tileDrag
            // Only while arranging. A panel where a slightly long press on
            // Wi-Fi silently moves it is a panel that rearranges itself by
            // accident.
            enabled: center.editing && tile.widgetId !== ""
            target: null
            onActiveChanged: {
                if (!tileDrag.active && tile.widgetId !== "")
                    center.swapTiles(tile.widgetId, tileDrag.centroid.scenePosition);
            }
        }

        z: tileDrag.active ? 20 : 0
        scale: tileDrag.active ? 1.06 : 1.0
        Behavior on scale { NumberAnimation { duration: Design.duration.fast; easing.type: Design.easing } }
        Behavior on opacity { NumberAnimation { duration: Design.duration.fast } }

        // While arranging, the tile stops being a control. Tapping it steps
        // through the sizes instead of toggling Wi-Fi, which is the only way a
        // grid of live switches can also be a grid you edit.
        MouseArea {
            anchors.fill: parent
            visible: center.editing && tile.widgetId !== ""
            enabled: visible
            z: 15
            cursorShape: Qt.PointingHandCursor
            onClicked: center.cycleTileSpan(tile.widgetId)
        }

        // Take it out, or put it back.
        Rectangle {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: Design.s(Design.space.xs)
            visible: center.editing && tile.widgetId !== ""
            width: Design.s(20)
            height: Design.s(20)
            radius: width / 2
            z: 25
            color: tile.tileHidden ? Design.tint(Design.ok, 0.85) : Design.tint(Design.red, 0.85)

            Icon {
                anchors.centerIn: parent
                text: tile.tileHidden ? "\u{f0415}" : "\u{f0156}"
                role: "caption"
                color: Design.accentText
            }

            TapHandler {
                onTapped: Settings.setWidgetHidden("ccHiddenTiles", tile.widgetId,
                                                   !tile.tileHidden)
            }
        }

        // Wide or normal. A tile has no room for a resize handle and inventing
        // a gesture for it would be a gesture nobody finds, so the width is a
        // switch on the Widgets settings page and this is the shortcut for
        // anyone who already knows.
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
                text: "\u{f0067}"   // grid
                role: "subhead"
                color: Design.accent
            }

            Label {
                text: center.editing ? "Arrange" : "Control Center"
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
                text: "drag to swap · tap size · × to remove"
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
            rowSpacing: Design.s(Design.space.sm)
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
                title: "Wi-Fi"
                on: Network.wifi.power === "on"
                activeColor: Design.blue
                detail: Network.wifi.connected ? Network.wifi.connected.ssid
                                               : (on ? "Not connected" : "Off")
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
                title: "Bluetooth"
                on: Network.bluetooth.power === "on"
                activeColor: Design.mauve
                detail: Network.bluetooth.connected ? Network.bluetooth.connected.name
                                                    : (on ? "No device" : "Off")
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
                title: "Do Not Disturb"
                on: Notifications.dnd
                activeColor: Design.peach
                detail: Notifications.dnd ? "Silenced" : "Off"
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
                title: "Night Light"
                on: Settings.nightLightEnabled !== undefined ? Settings.nightLightEnabled : false
                activeColor: Design.yellow
                glyphTone: on ? Design.yellow : Design.textDim
                detail: on ? "Warm (" + (Settings.nightLightTemp || 4000) + "K)" : "Off"
                onToggled: {
                    const next = !(Settings.nightLightEnabled !== undefined ? Settings.nightLightEnabled : false);
                    Settings.set("nightLightEnabled", next);
                    const temp = Settings.nightLightTemp || 4000;
                    if (!next) {
                        Quickshell.execDetached(["bash", "-c", "killall wlsunset gammastep 2>/dev/null || true"]);
                    } else {
                        Quickshell.execDetached(["bash", "-c",
                            "killall wlsunset gammastep 2>/dev/null || true; wlsunset -t " + temp + " -T " + temp + " 2>/dev/null || gammastep -O " + temp + " 2>/dev/null &"
                        ]);
                    }
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
                title: "Power Mode"
                on: false
                activeColor: powerTile.profileTone
                glyphTone: powerTile.profileTone
                detail: Power.profile === "performance" ? "Performance"
                      : (Power.profile === "power-saver" ? "Power Saver" : "Balanced")

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
                title: "Game Mode"
                on: Settings.gameModeEnabled !== undefined ? Settings.gameModeEnabled : false
                activeColor: Design.red
                glyphTone: on ? Design.red : Design.textDim
                detail: on ? "Performance" : "Off"
                trailingGlyph: ""
                onToggled: {
                    const next = !(Settings.gameModeEnabled !== undefined ? Settings.gameModeEnabled : false);
                    Settings.set("gameModeEnabled", next);
                    Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/b1air-daemon", "game-mode", next ? "on" : "off"]);
                }
                onActivated: center.openFull("settings:gamemode")
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
                title: "Caffeine"
                property bool active: false
                on: caffeineTile.active
                activeColor: Design.teal
                glyphTone: on ? Design.teal : Design.textDim
                detail: on ? "Stay Awake" : "Sleep Normal"
                trailingGlyph: ""
                onToggled: {
                    caffeineTile.active = !caffeineTile.active;
                    Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/b1air-daemon", "caffeine", caffeineTile.active ? "on" : "off"]);
                }
                onActivated: {
                    caffeineTile.active = !caffeineTile.active;
                    Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/b1air-daemon", "caffeine", caffeineTile.active ? "on" : "off"]);
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
                title: "Screenshot"
                on: false
                circleToggles: false
                activeColor: Design.pink
                glyphTone: Design.pink
                detail: "Capture area"
                trailingGlyph: ""
                onActivated: {
                    center.close();
                    Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/b1air-daemon", "screenshot", "area"]);
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
                title: "Color Dropper"
                on: false
                circleToggles: false
                activeColor: Design.sapphire
                glyphTone: Design.sapphire
                detail: "Pick from screen"
                trailingGlyph: ""
                onActivated: {
                    center.close();
                    Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/b1air-daemon", "color-picker"]);
                }
            }
        }

        // ── 3. Sliders ───────────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            visible: center.editing || !Settings.isWidgetHidden(Settings.ccHiddenCards, "sliders")
            opacity: Settings.isWidgetHidden(Settings.ccHiddenCards, "sliders") ? 0.35 : 1.0
            spacing: Design.s(Design.space.sm)

            Slider {
                visible: Power.hasBacklight
                Layout.fillWidth: true
                Layout.preferredHeight: Design.s(Design.size.ctl)
                value: Power.brightness
                tone: Design.yellow
                icon: "\u{f00df}"
                label: "Brightness"
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
                    label: "Volume"
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

            // A Layout cannot carry an anchored child, so here the
            // badge is laid out with everything else.
            EditBadge {
                Layout.alignment: Qt.AlignRight
                listKey: "ccHiddenCards"
                widgetId: "sliders"
            }
        }

        // ── 3.5 Live Weather Card ──────────────────────────────────────────
        Rectangle {
            id: weatherCard
            Layout.fillWidth: true
            visible: center.editing || !Settings.isWidgetHidden(Settings.ccHiddenCards, "weather")
            opacity: Settings.isWidgetHidden(Settings.ccHiddenCards, "weather") ? 0.35 : 1.0
            Layout.preferredHeight: Design.s(52)
            radius: Design.s(Design.radius.card)
            color: Design.glassCard
            border.color: Design.glassBorder
            border.width: Design.border

            EditBadge {
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: Design.s(Design.space.xs)
                listKey: "ccHiddenCards"
                widgetId: "weather"
            }

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
                    text: "Live"
                    tone: Design.ok
                }
            }
        }

        // ── 4. Media ─────────────────────────────────────────────────────────
        Rectangle {
            id: mediaCard
            Layout.fillWidth: true
            visible: center.editing || !Settings.isWidgetHidden(Settings.ccHiddenCards, "media")
            opacity: Settings.isWidgetHidden(Settings.ccHiddenCards, "media") ? 0.35 : 1.0
            Layout.preferredHeight: Design.s(Design.size.media)
            radius: Design.s(Design.radius.card)
            color: Design.glassCard
            border.color: Design.glassBorder
            border.width: Design.border

            EditBadge {
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: Design.s(Design.space.xs)
                listKey: "ccHiddenCards"
                widgetId: "media"
            }

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
                            text: Media.track.title || (Media.hasPlayer ? "Nothing playing" : "No media player")
                            weight: Design.weight.semibold
                            color: Media.hasPlayer ? Design.text : Design.textDim
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }

                        Label {
                            text: Media.track.artist || (Media.hasPlayer ? "Press play to resume" : "Start one to control it here")
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

        Item {
            Layout.fillHeight: true
            Layout.fillWidth: true
        }

        // ── 5. Session actions ───────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            visible: center.editing || !Settings.isWidgetHidden(Settings.ccHiddenCards, "session")
            opacity: Settings.isWidgetHidden(Settings.ccHiddenCards, "session") ? 0.35 : 1.0
            spacing: Design.s(Design.space.sm)

            ActionButton {
                icon: "\u{f033e}"
                label: "Lock"
                onActivated: Daemon.lock()
            }

            ActionButton {
                icon: "\u{f04b2}"
                label: "Sleep"
                onActivated: Daemon.power("suspend")
            }

            ActionButton {
                icon: "\u{f0709}"
                label: "Reboot"
                iconTone: Design.peach
                tone: Design.peach
                destructive: true
                onActivated: Daemon.power("reboot")
            }

            ActionButton {
                icon: "\u{f0425}"
                label: "Off"
                iconTone: Design.danger
                tone: Design.danger
                destructive: true
                onActivated: Daemon.power("shutdown")
            }

            // A Layout cannot carry an anchored child, so here the
            // badge is laid out with everything else.
            EditBadge {
                Layout.alignment: Qt.AlignRight
                listKey: "ccHiddenCards"
                widgetId: "session"
            }
        }
    }
    }

    // ── Mini-settings pages ──────────────────────────────────────────────────
    WifiMiniView {
        anchors.fill: parent
        visible: center.currentView === "wifi"
        onBackClicked: center.currentView = "main"
        onOpenFullSettings: center.openFull("settings", "network")
    }

    BluetoothMiniView {
        anchors.fill: parent
        visible: center.currentView === "bluetooth"
        onBackClicked: center.currentView = "main"
        onOpenFullSettings: center.openFull("settings", "bluetooth")
    }

    SoundMiniView {
        anchors.fill: parent
        visible: center.currentView === "sound"
        onBackClicked: center.currentView = "main"
        onOpenFullSettings: center.openFull("settings", "audio")
    }

    PowerMiniView {
        anchors.fill: parent
        visible: center.currentView === "power"
        onBackClicked: center.currentView = "main"
        onOpenFullSettings: center.openFull("settings", "power")
    }

    NotificationsMiniView {
        anchors.fill: parent
        visible: center.currentView === "notifications"
        onBackClicked: center.currentView = "main"
        // Notification rules live on the Screen Time & DND page.
        onOpenFullSettings: center.openFull("settings", "focus")
    }

    Component.onCompleted: {
        Audio.acquire(); Power.acquire(); Media.acquire(); Network.acquire();
    }
    Component.onDestruction: {
        Audio.release(); Power.release(); Media.release(); Network.release();
    }
}
