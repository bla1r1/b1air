import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as C
import "Ui"

// A music player shown as a device, the way Finder shows one: what it is,
// how full, its songs and playlists — rather than a drive of folders named
// F00…F49 holding files named KTGO.m4a.
//
// Everything goes through Devices (devices.cpp), which runs podsync. Songs
// are added by dropping files or folders here, or on the iPod in the sidebar.
Item {
    id: pane

    // The device, from Devices.devices: {kind, path, name, model, …}
    property var device: ({})
    readonly property string path: pane.device.path || ""
    signal note(string text)
    // The window's passing message, for this pane's status bar.
    property string statusNote: ""
    signal closed()

    // ── What is on it ────────────────────────────────────────────────────────
    property var library: ({ tracks: [], playlists: [], device: {} })
    property bool loading: true
    property string error: ""
    property int coverStamp: 0
    property bool coversReady: false
    readonly property var info: Object.assign({}, pane.device, pane.library.device || {})

    // Also when the pane is made: path is set then, and changes from "".
    onPathChanged: pane.reload()
    function reload() {
        if (!pane.path) return;
        pane.loading = true;
        pane.error = "";
        pane.selected = ({});
        pane.coversReady = false;
        Devices.load(pane.path);
    }

    Connections {
        target: Devices
        function onLibraryLoaded(path, library) {
            if (path !== pane.path) return;
            pane.library = library;
            pane.loading = false;
            // A playlist that was deleted is not shown empty.
            if (pane.playlistId && !pane.library.playlists.some(p => p.id === pane.playlistId))
                pane.playlistId = "";
        }
        function onCoversReady(path) { if (path === pane.path) { pane.coverStamp++; pane.coversReady = true; } }
        function onFinished(path, op, ok, message, result) {
            if (path !== pane.path) return;
            if (op === "library") { pane.loading = false; pane.error = message; return; }
            if (!ok) { pane.note(I18n.tr("Could not change the iPod: %1", message)); return; }
            if (op !== "eject") pane.coversReady = false;
            if (op === "add") {
                const added = (result.added || []).length, skipped = result.skipped || [];
                pane.note(skipped.length > 0
                    ? I18n.tr("%1 added; %2 skipped: %3", added, skipped.length, skipped[0].reason)
                    : I18n.trn("%1 song added", "%1 songs added", added));
            } else if (op === "remove") {
                pane.note(I18n.trn("%1 song removed", "%1 songs removed", (result.removed || []).length));
            } else if (op === "eject") {
                pane.note(I18n.tr("It is safe to disconnect “%1”", pane.info.name || "iPod"));
                pane.closed();
            } else if (op === "playlist-create" && result.id) {
                pane.tab = "playlists";
                pane.playlistId = result.id;
            }
        }
    }

    // ── Formatting ───────────────────────────────────────────────────────────
    function size(bytes) {
        const u = ["B", "KB", "MB", "GB", "TB"];
        let v = Number(bytes) || 0, i = 0;
        while (v >= 1000 && i < u.length - 1) { v /= 1000; i++; }
        return (i === 0 ? v.toFixed(0) : v.toFixed(v < 10 ? 1 : 0)) + " " + u[i];
    }
    function time(ms) {
        const s = Math.round((Number(ms) || 0) / 1000);
        const h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), r = s % 60;
        return (h > 0 ? h + ":" + String(m).padStart(2, "0") : m) + ":" + String(r).padStart(2, "0");
    }
    function cover(track) {
        return track.art && pane.coversReady ? Devices.coverUrl(pane.path) + "/" + track.art + ".png?" + pane.coverStamp : "";
    }

    // ── Tabs, search, the list shown ─────────────────────────────────────────
    property string tab: "general"          // general | music | playlists
    property string query: ""
    property string playlistId: ""
    readonly property var playlist: pane.library.playlists.find(p => p.id === pane.playlistId) || null
    readonly property var byId: {
        const m = {};
        for (const t of pane.library.tracks) m[t.id] = t;
        return m;
    }
    // Artist, album, disc, track: how a music library reads.
    function ordered(tracks) {
        const key = t => [(t.album_artist || t.artist || "").toLowerCase(), (t.album || "").toLowerCase()];
        return tracks.slice().sort((a, b) => {
            const ka = key(a), kb = key(b);
            return ka[0].localeCompare(kb[0]) || ka[1].localeCompare(kb[1])
                || (a.disc_number - b.disc_number) || (a.track_number - b.track_number)
                || a.title.localeCompare(b.title);
        });
    }
    readonly property var shown: {
        let list = pane.tab === "playlists"
            ? (pane.playlist ? pane.playlist.track_ids.map(id => pane.byId[id]).filter(t => !!t) : [])
            : pane.ordered(pane.library.tracks);
        const q = pane.query.trim().toLowerCase();
        if (q) list = list.filter(t => (t.title + " " + t.artist + " " + t.album + " " + t.genre).toLowerCase().includes(q));
        return list;
    }

    // ── Selection: click, Ctrl, Shift, Ctrl+A ────────────────────────────────
    property var selected: ({})
    property int anchorIndex: -1
    readonly property var selectedIds: Object.keys(pane.selected).filter(k => pane.selected[k])
    onShownChanged: pane.anchorIndex = -1
    onTabChanged: pane.selected = ({})
    onPlaylistIdChanged: pane.selected = ({})
    function press(index, mouse) {
        const id = pane.shown[index].id;
        const s = Object.assign({}, pane.selected);
        if (mouse.modifiers & Qt.ShiftModifier && pane.anchorIndex >= 0) {
            const a = Math.min(pane.anchorIndex, index), b = Math.max(pane.anchorIndex, index);
            for (let i = a; i <= b; i++) s[pane.shown[i].id] = true;
        } else if (mouse.modifiers & Qt.ControlModifier) {
            s[id] = !s[id];
            pane.anchorIndex = index;
        } else {
            if (mouse.button === Qt.RightButton && s[id]) { pane.selected = s; return; }
            for (const k in s) delete s[k];
            s[id] = true;
            pane.anchorIndex = index;
        }
        pane.selected = s;
    }
    function selectAll() {
        const s = {};
        for (const t of pane.shown) s[t.id] = true;
        pane.selected = s;
    }

    // ── Changing it ──────────────────────────────────────────────────────────
    readonly property bool busyHere: Devices.busy && Devices.busyPath === pane.path
    function addPaths(paths) {
        if (paths.length === 0) return;
        Devices.addFiles(pane.path, paths, pane.tab === "playlists" ? pane.playlistId : "");
    }
    function removeSelected() {
        if (pane.selectedIds.length === 0) return;
        if (pane.tab === "playlists" && pane.playlist) Devices.playlist(pane.path, "remove", [pane.playlistId].concat(pane.selectedIds));
        else confirmRemove.ask(pane.selectedIds);
    }

    // Keys on the list.
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Delete) { pane.removeSelected(); event.accepted = true; }
        else if (event.key === Qt.Key_A && (event.modifiers & Qt.ControlModifier)) { pane.selectAll(); event.accepted = true; }
        else if (event.key === Qt.Key_Escape) { pane.selected = ({}); event.accepted = true; }
    }

    // ═════════════════════════════════════════════════════════════════════════
    FilesDeviceFrame {
        id: frame
        anchors.fill: parent
        kind: "ipod"
        tint: pane.info.color || ""
        name: pane.info.name || "iPod"
        subtitle: [pane.info.model,
                   (pane.info.total_bytes || 0) > 0
                       ? I18n.tr("%1 (%2 free)", frame.size(pane.info.total_bytes), frame.size(pane.info.free_bytes)) : "",
                   pane.library.tracks.length > 0 ? I18n.trn("%1 song", "%1 songs", pane.library.tracks.length) : ""]
                  .filter(s => !!s).join("  ·  ")
        renamable: !pane.busyHere && !pane.loading
        onRenameRequested: nameDialog.ask("rename", pane.info.name || "")

        tabs: [{ id: "general", label: I18n.tr("General") },
               { id: "music", label: I18n.tr("Music") },
               { id: "playlists", label: I18n.tr("Playlists") }]
        tab: pane.tab
        onTabClicked: id => pane.tab = id

        segments: [{ label: I18n.tr("Music"), bytes: storage.music, color: Design.pink },
                   { label: I18n.tr("Other"), bytes: storage.other, color: Design.yellow }]
        totalBytes: pane.info.total_bytes || 0
        freeBytes: pane.info.free_bytes || 0
        note: pane.statusNote || (pane.selectedIds.length > 0
            ? I18n.trn("%1 song selected", "%1 songs selected", pane.selectedIds.length) : "")

        progressText: !pane.busyHere ? ""
            : Devices.busyOp === "add" && Devices.progressTotal > 0 && Devices.progressDone < Devices.progressTotal
              ? I18n.tr("Copying %1 of %2 — %3", Devices.progressDone + 1, Devices.progressTotal, Devices.progressFile)
            : Devices.busyOp === "eject" ? I18n.tr("Ejecting…") : I18n.tr("Writing the iPod's library…")
        progress: Devices.busyOp === "add" && Devices.progressTotal > 0 ? Devices.progressDone / Devices.progressTotal : -1

        actions: [
            BarButton {
                glyph: "\u{f01ea}"
                label: I18n.tr("Eject")
                enabled: !pane.busyHere
                onClicked: Devices.eject(pane.path)
            }
        ]
        footer: [
            BarButton {
                glyph: "\u{f0415}"
                label: I18n.tr("Add Music…")
                primary: true
                tip: I18n.tr("Opens your Music folder beside this window: drag songs or albums here")
                onClicked: Devices.openWindow(FilesBackend.homePath + "/Music")
            }
        ]

        // ── General ─────────────────────────────────────────────────────────
        Flickable {
            id: general
            anchors.fill: parent
            visible: pane.tab === "general"
            contentHeight: generalBody.implicitHeight + Design.s(Design.space.xl) * 2
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            C.ScrollBar.vertical: OverflowBar {}
            ColumnLayout {
                id: generalBody
                x: Math.max(Design.s(Design.space.xl), (general.width - width) / 2)
                y: Design.s(Design.space.xl)
                width: Math.min(general.width - Design.s(Design.space.xl) * 2, Design.s(720))
                spacing: Design.s(Design.space.xl)

                FilesDeviceRow {
                    label: I18n.tr("Software")
                    Label { text: pane.info.firmware ? I18n.tr("Version %1", pane.info.firmware) : I18n.tr("Unknown") }
                    Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        dim: true
                        text: I18n.tr("The iPod's own software is not updated from here; its music, playlists and covers are.")
                    }
                }
                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Design.line }
                FilesDeviceRow {
                    label: I18n.tr("Library")
                    Label {
                        text: I18n.trn("%1 song", "%1 songs", pane.library.tracks.length) + "  ·  "
                            + I18n.trn("%1 playlist", "%1 playlists", pane.library.playlists.length) + "  ·  "
                            + pane.time(pane.library.tracks.reduce((a, t) => a + t.length_ms, 0))
                    }
                    Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        dim: true
                        text: I18n.tr("Drop songs or whole albums anywhere on this page, or on the iPod in the sidebar. FLAC, Ogg and Opus are converted for it on the way; tags and covers come along.")
                    }
                }
                Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Design.line }
                FilesDeviceRow {
                    label: I18n.tr("About")
                    GridLayout {
                        columns: 2
                        columnSpacing: Design.s(Design.space.lg)
                        rowSpacing: Design.s(Design.space.xs)
                        Label { text: I18n.tr("Model"); dim: true }
                        Label { text: [pane.info.model, pane.info.model_number].filter(s => !!s).join(" · ") }
                        Label { text: I18n.tr("Capacity"); dim: true; visible: !!pane.info.capacity }
                        Label { text: pane.info.capacity || ""; visible: !!pane.info.capacity }
                        Label { text: I18n.tr("Serial number"); dim: true; visible: !!pane.info.serial }
                        Label { text: pane.info.serial || ""; visible: !!pane.info.serial; font.family: Design.font.mono }
                        Label { text: I18n.tr("Mounted at"); dim: true }
                        Label { text: pane.path; font.family: Design.font.mono; elide: Text.ElideMiddle; Layout.maximumWidth: Design.s(420) }
                    }
                }
            }
        }

        // ── Music and Playlists ─────────────────────────────────────────────
        RowLayout {
            anchors.fill: parent
            visible: pane.tab !== "general"
            spacing: 0

            // Playlists, in that tab.
            Rectangle {
                visible: pane.tab === "playlists"
                Layout.fillHeight: true
                Layout.preferredWidth: Design.s(230)
                color: Design.sunken
                Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Design.line }
                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Design.s(Design.space.sm)
                    spacing: Design.s(2)
                    ListView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        model: pane.library.playlists
                        C.ScrollBar.vertical: OverflowBar {}
                        delegate: SidebarItem {
                            required property var modelData
                            width: ListView.view.width
                            label: modelData.name
                            glyph: modelData.smart ? "\u{f0068}" : "\u{f0cb8}"
                            badge: String(modelData.track_ids.length)
                            active: pane.playlistId === modelData.id
                            onClicked: pane.playlistId = modelData.id
                            overlay: [
                                DropArea {
                                    anchors.fill: parent
                                    keys: ["text/uri-list", "application/x-b1air-tracks"]
                                    onDropped: drop => {
                                        if (drop.hasText && drop.keys.indexOf("application/x-b1air-tracks") >= 0) {
                                            Devices.playlist(pane.path, "add", [modelData.id].concat(JSON.parse(drop.text)));
                                        } else {
                                            Devices.addFiles(pane.path, pane.pathsOf(drop), modelData.id);
                                        }
                                        drop.accept(Qt.CopyAction);
                                    }
                                }
                            ]
                        }
                    }
                    BarButton {
                        Layout.fillWidth: true
                        glyph: "\u{f0415}"
                        label: I18n.tr("New Playlist")
                        enabled: !pane.loading
                        onClicked: nameDialog.ask("playlist", I18n.tr("Playlist"))
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                // The list's own bar: the playlist's name and tools, search.
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: Design.s(Design.space.lg)
                    Layout.rightMargin: Design.s(Design.space.lg)
                    Layout.topMargin: Design.s(Design.space.sm)
                    Layout.bottomMargin: Design.s(Design.space.xs)
                    spacing: Design.s(Design.space.xs)
                    Label {
                        Layout.fillWidth: true
                        text: pane.tab === "playlists" ? (pane.playlist ? pane.playlist.name : "")
                            : I18n.trn("%1 song", "%1 songs", pane.shown.length) + ", " + pane.time(pane.shown.reduce((a, t) => a + t.length_ms, 0))
                        role: pane.tab === "playlists" ? "subhead" : "body"
                        weight: pane.tab === "playlists" ? Design.weight.semibold : Design.weight.regular
                        dim: pane.tab !== "playlists"
                        elide: Text.ElideRight
                    }
                    BarButton {
                        visible: pane.tab === "playlists" && !!pane.playlist && !pane.playlist.smart
                        glyph: "\u{f03eb}"; small: true; tip: I18n.tr("Rename playlist")
                        onClicked: nameDialog.ask("renamePlaylist", pane.playlist.name)
                    }
                    BarButton {
                        visible: pane.tab === "playlists" && !!pane.playlist && !pane.playlist.smart
                        glyph: "\u{f0a7a}"; small: true; danger: true; tip: I18n.tr("Delete playlist")
                        onClicked: confirmPlaylist.open()
                    }
                    Field {
                        Layout.preferredWidth: Design.s(220)
                        placeholder: I18n.tr("Search songs")
                        onEdited: value => pane.query = value
                    }
                }

                // Column heads.
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Design.s(30)
                    Layout.leftMargin: Design.s(Design.space.lg)
                    Layout.rightMargin: Design.s(Design.space.lg)
                    spacing: Design.s(Design.space.md)
                    visible: pane.shown.length > 0
                    Item { Layout.preferredWidth: Design.s(28) }
                    Label { Layout.fillWidth: true; Layout.preferredWidth: 3; text: I18n.tr("Song title"); role: "caption"; dim: true; weight: Design.weight.semibold }
                    Label { Layout.fillWidth: true; Layout.preferredWidth: 2; text: I18n.tr("Artist"); role: "caption"; dim: true; weight: Design.weight.semibold }
                    Label { Layout.fillWidth: true; Layout.preferredWidth: 2; text: I18n.tr("Album"); role: "caption"; dim: true; weight: Design.weight.semibold }
                    Label { Layout.preferredWidth: Design.s(56); text: I18n.tr("Time"); role: "caption"; dim: true; weight: Design.weight.semibold; horizontalAlignment: Text.AlignRight }
                }

                ListView {
                    id: songs
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    focus: true
                    model: pane.shown
                    boundsBehavior: Flickable.StopAtBounds
                    C.ScrollBar.vertical: OverflowBar {}
                    Keys.forwardTo: [pane]

                    delegate: Item {
                        id: song
                        required property var modelData
                        required property int index
                        readonly property bool picked: !!pane.selected[modelData.id]
                        width: songs.width
                        height: Design.s(40)

                        Rectangle {
                            anchors.fill: parent
                            anchors.leftMargin: Design.s(Design.space.sm)
                            anchors.rightMargin: Design.s(Design.space.sm)
                            radius: Design.s(Design.radius.sm)
                            color: song.picked ? Design.tint(Design.accent, 0.24)
                                 : songMa.containsMouse ? Design.hover
                                 : (song.index % 2 ? Design.tint(Design.raised, 0.35) : "transparent")
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Design.s(Design.space.sm)
                                anchors.rightMargin: Design.s(Design.space.sm)
                                spacing: Design.s(Design.space.md)
                                Rectangle {
                                    Layout.preferredWidth: Design.s(28)
                                    Layout.preferredHeight: Design.s(28)
                                    radius: Design.s(4)
                                    color: Design.tint(Design.pink, 0.18)
                                    clip: true
                                    Text {
                                        anchors.centerIn: parent
                                        visible: art.status !== Image.Ready
                                        text: song.modelData.video ? "\u{f0567}" : "\u{f075a}"
                                        font.family: Design.font.icon
                                        font.pixelSize: Design.s(15)
                                        color: Design.pink
                                    }
                                    Image {
                                        id: art
                                        anchors.fill: parent
                                        source: pane.cover(song.modelData)
                                        sourceSize: Qt.size(Design.s(56), Design.s(56))
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                        cache: false
                                    }
                                }
                                Label { Layout.fillWidth: true; Layout.preferredWidth: 3; text: song.modelData.title; elide: Text.ElideRight }
                                Label { Layout.fillWidth: true; Layout.preferredWidth: 2; text: song.modelData.artist; dim: true; elide: Text.ElideRight }
                                Label { Layout.fillWidth: true; Layout.preferredWidth: 2; text: song.modelData.album; dim: true; elide: Text.ElideRight }
                                Label { Layout.preferredWidth: Design.s(56); text: pane.time(song.modelData.length_ms); dim: true; horizontalAlignment: Text.AlignRight }
                            }
                        }

                        // Dragged onto a playlist, a song joins it.
                        Item {
                            id: songProxy
                            Drag.active: songMa.drag.active
                            Drag.keys: ["application/x-b1air-tracks"]
                            Drag.mimeData: ({ "text/plain": JSON.stringify(song.picked ? pane.selectedIds : [song.modelData.id]) })
                            Drag.dragType: Drag.Automatic
                            Drag.supportedActions: Qt.CopyAction
                        }
                        MouseArea {
                            id: songMa
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            drag.target: songProxy
                            drag.threshold: Design.s(10)
                            onPressed: mouse => { songs.forceActiveFocus(); pane.press(song.index, mouse); }
                            onClicked: mouse => { if (mouse.button === Qt.RightButton) songMenu.popup(); }
                            // Plays it, from the iPod, in whatever plays music here.
                            onDoubleClicked: mouse => {
                                if (mouse.button === Qt.LeftButton && song.modelData.file)
                                    Qt.openUrlExternally("file://" + song.modelData.file);
                            }
                        }
                    }
                }
            }
        }

        // ── Nothing to show ─────────────────────────────────────────────────
        ColumnLayout {
            anchors.centerIn: parent
            width: Math.min(parent.width - Design.s(48), Design.s(380))
            visible: pane.tab !== "general" && (pane.loading || pane.error !== "" || pane.shown.length === 0)
            spacing: Design.s(Design.space.sm)
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: pane.error ? "\u{f0b8a}" : pane.loading ? "\u{f0450}" : "\u{f075a}"
                font.family: Design.font.icon
                font.pixelSize: Design.s(48)
                color: Design.textFaint
            }
            Label {
                Layout.alignment: Qt.AlignHCenter
                role: "subhead"
                weight: Design.weight.semibold
                text: pane.error ? I18n.tr("Can't read this iPod")
                    : pane.loading ? I18n.tr("Reading the iPod…")
                    : pane.query ? I18n.tr("Nothing matches “%1”", pane.query)
                    : pane.tab === "playlists" && !pane.playlist ? I18n.tr("Pick a playlist")
                    : pane.tab === "playlists" ? I18n.tr("This playlist is empty")
                    : I18n.tr("No music yet")
            }
            Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                dim: true
                visible: text !== ""
                text: pane.error ? pane.error
                    : pane.loading || pane.query ? ""
                    : pane.tab === "playlists" && pane.playlist ? I18n.tr("Drag songs from Music onto the playlist on the left.")
                    : pane.tab === "playlists" ? ""
                    : I18n.tr("Drag songs or whole albums here. FLAC and Ogg are converted on the way.")
            }
        }
    }

    // What the storage bar shows: music, the rest, what is free.
    QtObject {
        id: storage
        readonly property real total: pane.info.total_bytes || 1
        readonly property real music: pane.info.music_bytes || 0
        readonly property real free: pane.info.free_bytes || 0
        readonly property real other: Math.max(0, storage.total - storage.free - storage.music)
    }

    // ── Dropping music ──────────────────────────────────────────────────────
    function pathsOf(drop) {
        const paths = [];
        for (const u of drop.urls) {
            const s = String(u);
            if (s.startsWith("file://")) paths.push(decodeURIComponent(s.substring(7)));
        }
        return paths;
    }
    DropArea {
        id: dropAll
        anchors.fill: parent
        keys: ["text/uri-list"]
        onDropped: drop => { pane.addPaths(pane.pathsOf(drop)); drop.accept(Qt.CopyAction); }
        Rectangle {
            anchors.fill: parent
            anchors.margins: Design.s(Design.space.sm)
            visible: dropAll.containsDrag
            radius: Design.s(Design.radius.card)
            color: Design.tint(Design.accent, 0.08)
            border.color: Design.accent
            border.width: Design.s(2)
            Label {
                anchors.centerIn: parent
                text: pane.tab === "playlists" && pane.playlist
                    ? I18n.tr("Add to the iPod and to “%1”", pane.playlist.name)
                    : I18n.tr("Add to the iPod")
                role: "subhead"; weight: Design.weight.semibold
                color: Design.accent
            }
        }
    }

    // ── Menus and dialogs ───────────────────────────────────────────────────
    AppMenu {
        id: songMenu
        readonly property var normal: pane.library.playlists.filter(p => !p.smart)
        AppMenu {
            id: addToMenu
            title: I18n.tr("Add to Playlist")
            AppMenuItem {
                text: I18n.tr("New Playlist…")
                glyph: "\u{f0415}"
                onTriggered: nameDialog.ask("playlistFromSelection", I18n.tr("Playlist"))
            }
            Instantiator {
                model: songMenu.normal
                delegate: AppMenuItem {
                    required property var modelData
                    text: modelData.name
                    glyph: "\u{f0cb8}"
                    onTriggered: Devices.playlist(pane.path, "add", [modelData.id].concat(pane.selectedIds))
                }
                onObjectAdded: (i, o) => addToMenu.insertItem(i + 1, o)
                onObjectRemoved: (i, o) => addToMenu.removeItem(o)
            }
        }
        AppMenuItem {
            text: I18n.tr("Play")
            glyph: "\u{f040a}"
            enabled: pane.selectedIds.length === 1
            onTriggered: { const t = pane.byId[pane.selectedIds[0]]; if (t && t.file) Qt.openUrlExternally("file://" + t.file); }
        }
        AppMenuSeparator {}
        AppMenuItem {
            visible: pane.tab === "playlists" && !!pane.playlist && !pane.playlist.smart
            height: visible ? implicitHeight : 0
            text: I18n.tr("Remove from Playlist")
            glyph: "\u{f0374}"
            keys: "Del"
            onTriggered: Devices.playlist(pane.path, "remove", [pane.playlistId].concat(pane.selectedIds))
        }
        AppMenuItem {
            text: I18n.trn("Delete %1 Song from the iPod…", "Delete %1 Songs from the iPod…", pane.selectedIds.length)
            glyph: "\u{f0a7a}"
            keys: pane.tab === "music" ? "Del" : ""
            tone: Design.danger
            onTriggered: confirmRemove.ask(pane.selectedIds)
        }
    }

    AppDialog {
        id: confirmRemove
        property var ids: []
        function ask(list) { ids = list.slice(); open(); }
        title: ids.length === 1
            ? I18n.tr("Delete “%1” from the iPod?", (pane.byId[ids[0]] || {}).title || "")
            : I18n.trn("Delete %1 song from the iPod?", "Delete %1 songs from the iPod?", ids.length)
        message: I18n.tr("The files on this computer stay; only the iPod's copies go.")
        acceptTone: Design.danger
        standardButtons: C.Dialog.Cancel | C.Dialog.Ok
        buttonText: ({ [C.Dialog.Ok]: I18n.tr("Delete") })
        onAccepted: { Devices.removeTracks(pane.path, ids); pane.selected = ({}); }
    }

    AppDialog {
        id: confirmPlaylist
        title: I18n.tr("Delete the playlist “%1”?", pane.playlist ? pane.playlist.name : "")
        message: I18n.tr("Its songs stay on the iPod.")
        acceptTone: Design.danger
        standardButtons: C.Dialog.Cancel | C.Dialog.Ok
        buttonText: ({ [C.Dialog.Ok]: I18n.tr("Delete") })
        onAccepted: Devices.playlist(pane.path, "delete", [pane.playlistId])
    }

    AppDialog {
        id: nameDialog
        property string mode: ""     // rename | playlist | playlistFromSelection | renamePlaylist
        property var ids: []
        function ask(m, value) {
            mode = m;
            ids = pane.selectedIds.slice();
            nameField.text = value;
            open();
        }
        title: mode === "rename" ? I18n.tr("Rename the iPod")
             : mode === "renamePlaylist" ? I18n.tr("Rename playlist") : I18n.tr("New playlist")
        standardButtons: C.Dialog.Cancel | C.Dialog.Ok
        buttonText: ({ [C.Dialog.Ok]: mode === "rename" || mode === "renamePlaylist" ? I18n.tr("Rename") : I18n.tr("Create") })
        onOpened: { nameField.focusInput(); nameField.selectRange(0, nameField.text.length); }
        onAccepted: {
            const name = nameField.text.trim();
            if (!name) return;
            if (mode === "rename") Devices.rename(pane.path, name);
            else if (mode === "renamePlaylist") Devices.playlist(pane.path, "rename", [pane.playlistId, name]);
            else Devices.playlist(pane.path, "create", [name].concat(mode === "playlistFromSelection" ? ids : []));
        }
        contentItem: Item {
            implicitWidth: Design.s(380)
            implicitHeight: nameBody.implicitHeight
            ColumnLayout {
                id: nameBody
                width: parent.width
                spacing: Design.s(Design.space.sm)
                Label { text: I18n.tr("Name"); role: "caption"; dim: true }
                Field { id: nameField; Layout.fillWidth: true; onAccepted: nameDialog.accept() }
            }
        }
    }
}
