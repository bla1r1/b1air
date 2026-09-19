import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Controls as C
import "Ui"

// b1air-files.
//
// Rebuilt around FilesBackend.files (dir_model.cpp) instead of Qt's
// FolderListModel, which could hold no selection, could not open a folder
// with "#" in its name, and knew a file's type only by its suffix. What that
// made possible, and what the old window did not have: selecting several
// items (Ctrl/Shift, Ctrl+A, the keyboard), acting on all of them, drag and
// drop, a list with columns, a details panel, the trash and mounted drives in
// the sidebar, Open With, and a size that can be read.
C.ApplicationWindow {
    id: window

    palette.window: Design.surface
    palette.windowText: Design.text
    palette.base: Design.sunken
    palette.alternateBase: Design.raised
    palette.text: Design.text
    palette.button: Design.raised
    palette.buttonText: Design.text
    palette.brightText: Design.text
    palette.highlight: Design.accent
    palette.highlightedText: Design.accentText
    palette.toolTipBase: Design.raised
    palette.toolTipText: Design.text
    palette.placeholderText: Design.textFaint
    palette.light: Design.highest
    palette.midlight: Design.high
    palette.mid: Design.line
    palette.dark: Design.sunken
    palette.shadow: Design.ground

    title: (FilesBackend.inTrash ? "Trash" : window.folderName) + " — Files"
    width: Design.s(1120)
    height: Design.s(720)
    minimumWidth: 760
    minimumHeight: 480
    visible: true
    color: Design.surface

    readonly property var fm: FilesBackend.files
    readonly property string homeDir: FilesBackend.homePath
    readonly property string currentPath: FilesBackend.currentPath
    readonly property string folderName: currentPath === homeDir ? "Home"
                                       : currentPath === "/" ? "File System"
                                       : currentPath.substring(currentPath.lastIndexOf("/") + 1)

    // ── Preferences, kept between runs ───────────────────────────────────────
    readonly property var prefs: FilesBackend.loadPrefs()
    property string viewMode: prefs.viewMode === "list" ? "list" : "grid"
    property int iconSize: prefs.iconSize || 88
    property bool showInfo: prefs.showInfo !== false
    Component.onCompleted: {
        FilesBackend.showHidden = prefs.showHidden === true;
        FilesBackend.dirsFirst = prefs.dirsFirst !== false;
        FilesBackend.sortField = prefs.sortBy || "name";
        FilesBackend.sortAscending = prefs.sortDescending !== true;
        currentView().forceActiveFocus();
    }
    function savePrefs() {
        FilesBackend.savePrefs({
            viewMode: viewMode, iconSize: iconSize, showInfo: showInfo,
            showHidden: FilesBackend.showHidden, dirsFirst: FilesBackend.dirsFirst,
            sortBy: FilesBackend.sortField, sortDescending: !FilesBackend.sortAscending
        });
    }
    onViewModeChanged: savePrefs()
    onIconSizeChanged: savePrefs()
    onShowInfoChanged: savePrefs()
    Connections {
        target: FilesBackend
        function onShowHiddenChanged() { window.savePrefs(); }
        function onSortChanged() { window.savePrefs(); }
        function onErrorOccurred(message) { window.note(message); }
        function onPasteFinished(ok, message) { window.note(ok && FilesBackend.undoLabel ? message + " · Ctrl+Z undoes it" : message); }
        function onCurrentPathChanged() { window.typed = ""; currentView().positionViewAtBeginning(); }
    }

    // A line in the status bar for a few seconds.
    property string statusNote: ""
    function note(text) { statusNote = text; noteTimer.restart(); }
    Timer { id: noteTimer; interval: 4000; onTriggered: window.statusNote = "" }

    // ── Kinds of file: one glyph and one colour each ─────────────────────────
    function glyphFor(category) {
        switch (category) {
        case "folder":     return "\u{f024b}";
        case "image":      return "\u{f02e9}";
        case "video":      return "\u{f0567}";
        case "audio":      return "\u{f075a}";
        case "code":       return "\u{f0169}";
        case "text":       return "\u{f0219}";
        case "archive":    return "\u{f05c4}";
        case "pdf":        return "\u{f0226}";
        case "document":   return "\u{f022c}";
        case "executable": return "\u{f018d}";
        default:           return "\u{f0214}";
        }
    }
    function toneFor(category) {
        switch (category) {
        case "folder":     return Design.accent;
        case "image":      return Design.mauve;
        case "video":      return Design.peach;
        case "audio":      return Design.pink;
        case "code":       return Design.sapphire;
        case "archive":    return Design.yellow;
        case "pdf":        return Design.red;
        case "document":   return Design.blue;
        case "executable": return Design.green;
        default:           return Design.textDim;
        }
    }

    // ── Navigation ───────────────────────────────────────────────────────────
    function navigateTo(path) {
        if (!path || path === currentPath) return;
        FilesBackend.currentPath = path;
    }
    function currentView() { return viewMode === "grid" ? gridView : listView; }

    // ── What the actions work on ─────────────────────────────────────────────
    // The selection, or the item under the cursor when nothing is selected.
    function targets() {
        const sel = fm.selectedPaths();
        if (sel.length > 0) return sel;
        const cur = fm.get(fm.currentIndex);
        return cur.path ? [cur.path] : [];
    }
    function single() { const t = targets(); return t.length === 1 ? fm.get(fm.indexOfPath(t[0])) : null; }

    function openRow(row) {
        const it = fm.get(row);
        if (!it.path) return;
        if (it.isDir) navigateTo(it.path);
        else FilesBackend.openItem(it.path);
    }
    function openSelection() {
        const t = targets();
        if (t.length === 1) { openRow(fm.indexOfPath(t[0])); return; }
        for (const p of t) {
            const it = fm.get(fm.indexOfPath(p));
            if (!it.isDir) FilesBackend.openItem(p);
        }
    }
    function copySelection(cut) {
        const t = targets();
        if (t.length === 0) return;
        FilesBackend.copyFiles(t, cut);
        note((cut ? "Cut " : "Copied ") + (t.length === 1 ? t[0].split("/").pop() : t.length + " items")
             + " — paste with Ctrl+V");
    }
    function trashSelection() {
        const t = targets();
        if (t.length === 0) return;
        if (FilesBackend.inTrash) { confirmDelete.ask(t); return; }
        if (FilesBackend.trashItems(t))
            note((t.length === 1 ? "Moved " + t[0].split("/").pop() + " to the trash" : "Moved " + t.length + " items to the trash")
                 + " · Ctrl+Z undoes it");
    }
    function renameSelection() {
        const it = single();
        if (it) askName("rename", it.path, it.name);
    }

    // ── Typing to find ───────────────────────────────────────────────────────
    property string typed: ""
    Timer { id: typedReset; interval: 900; onTriggered: window.typed = "" }
    function typeToFind(ch) {
        typed += ch;
        typedReset.restart();
        const row = fm.findPrefix(typed, typed.length === 1 ? fm.currentIndex + 1 : fm.currentIndex);
        if (row >= 0) { fm.select(row, 0); currentView().positionViewAtIndex(row, GridView.Contain); }
    }

    // ── Keyboard, for whichever view is shown ────────────────────────────────
    function handleKey(event, columns) {
        const n = fm.count;
        const cur = fm.currentIndex;
        let next = -1;
        switch (event.key) {
        case Qt.Key_Left:  if (columns > 1) next = Math.max(0, cur - 1); break;
        case Qt.Key_Right: if (columns > 1) next = Math.min(n - 1, cur + 1); break;
        case Qt.Key_Up:    next = cur < 0 ? 0 : Math.max(0, cur - columns); break;
        case Qt.Key_Down:  next = cur < 0 ? 0 : Math.min(n - 1, cur + columns); break;
        case Qt.Key_Home:  next = 0; break;
        case Qt.Key_End:   next = n - 1; break;
        case Qt.Key_PageUp:   next = Math.max(0, cur - columns * 5); break;
        case Qt.Key_PageDown: next = Math.min(n - 1, cur + columns * 5); break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            openSelection(); event.accepted = true; return;
        default:
            if (event.text.length === 1 && event.text >= " " && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier))) {
                typeToFind(event.text); event.accepted = true;
            }
            return;
        }
        if (next < 0 || n === 0) return;
        event.accepted = true;
        fm.select(next, (event.modifiers & Qt.ShiftModifier) ? 2 : 0);
        currentView().positionViewAtIndex(next, GridView.Contain);
    }

    // Selection mode for a click with these modifiers.
    function clickMode(mods) {
        const ctrl = mods & Qt.ControlModifier, shift = mods & Qt.ShiftModifier;
        return ctrl && shift ? 3 : shift ? 2 : ctrl ? 1 : 0;
    }

    // ── Dialogs ──────────────────────────────────────────────────────────────
    function askName(mode, target, initial) {
        nameDialog.mode = mode;
        nameDialog.target = target;
        nameField.text = initial;
        nameDialog.open();
    }
    function submitName(text) {
        const v = String(text || "").trim();
        if (v === "") return;
        const mode = nameDialog.mode;
        if (mode !== "goto" && v.indexOf("/") >= 0) { note("A name cannot contain /"); return; }
        if (mode === "rename") {
            if (!FilesBackend.renameItem(nameDialog.target, v)) { note("Could not rename to " + v); return; }
            fm.selectPaths([window.parentOf(nameDialog.target) + "/" + v]);
        } else if (mode === "newfolder") {
            if (!FilesBackend.createFolder(v)) { note("Could not create " + v); return; }
            fm.selectPaths([currentPath.replace(/\/$/, "") + "/" + v]);
        } else if (mode === "newfile") {
            if (!FilesBackend.createFile(v)) { note("Could not create " + v); return; }
            fm.selectPaths([currentPath.replace(/\/$/, "") + "/" + v]);
        } else if (mode === "goto") {
            const path = v.startsWith("~") ? homeDir + v.substring(1) : v;
            FilesBackend.currentPath = path;
            if (FilesBackend.currentPath !== path.replace(/\/+$/, "") && path !== "/") note("No folder at " + v);
        }
        nameDialog.close();
        currentView().forceActiveFocus();
    }
    function parentOf(path) {
        const i = path.lastIndexOf("/");
        return i <= 0 ? "/" : path.substring(0, i);
    }

    // ── Bookmarks ────────────────────────────────────────────────────────────
    property var bookmarks: FilesBackend.loadBookmarks()
    function addBookmark(path) {
        if (bookmarks.some(b => b.path === path)) return;
        const copy = Array.from(bookmarks);
        copy.push({ name: path.split("/").pop() || path, path: path });
        bookmarks = copy;
        FilesBackend.saveBookmarks(copy);
        note("Bookmarked " + (path.split("/").pop() || path));
    }
    function removeBookmark(index) {
        const copy = Array.from(bookmarks);
        copy.splice(index, 1);
        bookmarks = copy;
        FilesBackend.saveBookmarks(copy);
    }

    // ── Drag and drop ────────────────────────────────────────────────────────
    function urlsOf(paths) { return paths.map(p => Paths.fileUrl(p)).join("\r\n"); }
    // Move by default, as everywhere; Ctrl copies.
    function dropInto(drop, dest) {
        const paths = [];
        for (const u of drop.urls) {
            const s = String(u);
            if (s.startsWith("file://")) paths.push(decodeURIComponent(s.substring(7)));
        }
        if (paths.length === 0) return;
        // Ctrl during the drag proposes a copy.
        const copy = drop.proposedAction === Qt.CopyAction;
        if (dest === FilesBackend.trashPath && !copy) FilesBackend.trashItems(paths);
        else FilesBackend.transfer(paths, dest, !copy);
        drop.accept(copy ? Qt.CopyAction : Qt.MoveAction);
    }

    // ── Shortcuts ────────────────────────────────────────────────────────────
    Shortcut { sequence: "Alt+Up"; onActivated: FilesBackend.goUp() }
    Shortcut { sequence: "Backspace"; onActivated: FilesBackend.goUp() }
    Shortcut { sequence: "Alt+Left"; onActivated: FilesBackend.historyBack() }
    Shortcut { sequence: "Alt+Right"; onActivated: FilesBackend.historyForward() }
    Shortcut { sequence: "Alt+Home"; onActivated: window.navigateTo(window.homeDir) }
    Shortcut { sequence: "Ctrl+A"; onActivated: fm.selectAll() }
    Shortcut { sequence: "Ctrl+Z"; onActivated: FilesBackend.undo() }
    Shortcut { sequence: "Ctrl+C"; onActivated: window.copySelection(false) }
    Shortcut { sequence: "Ctrl+X"; onActivated: window.copySelection(true) }
    Shortcut { sequence: "Ctrl+V"; onActivated: if (!FilesBackend.busy) FilesBackend.paste() }
    Shortcut { sequence: "Delete"; onActivated: window.trashSelection() }
    Shortcut { sequence: "Shift+Delete"; onActivated: { const t = window.targets(); if (t.length) confirmDelete.ask(t); } }
    Shortcut { sequence: "F2"; onActivated: window.renameSelection() }
    Shortcut { sequence: "Ctrl+Shift+N"; onActivated: window.askName("newfolder", "", "New Folder") }
    Shortcut { sequence: "Ctrl+L"; onActivated: window.askName("goto", "", window.currentPath) }
    Shortcut { sequence: "Ctrl+F"; onActivated: searchField.focusInput() }
    Shortcut { sequence: "Ctrl+H"; onActivated: FilesBackend.showHidden = !FilesBackend.showHidden }
    Shortcut { sequence: "Ctrl+I"; onActivated: window.showInfo = !window.showInfo }
    Shortcut { sequence: "Ctrl+1"; onActivated: window.viewMode = "grid" }
    Shortcut { sequence: "Ctrl+2"; onActivated: window.viewMode = "list" }
    Shortcut { sequences: ["Ctrl+=", "Ctrl++"]; onActivated: window.iconSize = Math.min(176, window.iconSize + 16) }
    Shortcut { sequence: "Ctrl+-"; onActivated: window.iconSize = Math.max(56, window.iconSize - 16) }
    Shortcut { sequence: "Ctrl+T"; onActivated: FilesBackend.openTerminal(window.currentPath) }
    Shortcut { sequence: "Ctrl+Shift+C"; onActivated: { const t = window.targets(); FilesBackend.copyText(t.length ? t.join("\n") : window.currentPath); window.note("Path copied"); } }
    Shortcut { sequence: "Ctrl+D"; onActivated: window.addBookmark(window.currentPath) }
    Shortcut { sequence: "F5"; onActivated: FilesBackend.refresh() }
    Shortcut { sequence: "Space"; onActivated: { const it = window.single(); if (it && !it.isDir) FilesBackend.triggerQuickLook(it.path); } }
    Shortcut {
        sequence: "Escape"
        onActivated: {
            if (searchField.text !== "") { searchField.text = ""; FilesBackend.filterQuery = ""; }
            else fm.clearSelection();
            window.currentView().forceActiveFocus();
        }
    }

    // ═════════════════════════════════════════════════════════════════════════
    RowLayout {
        anchors.fill: parent
        spacing: 0

        // ── Sidebar ──────────────────────────────────────────────────────────
        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: Design.s(220)
            color: Design.sunken

            Rectangle { anchors.right: parent.right; width: 1; height: parent.height; color: Design.line }

            C.ScrollView {
                anchors.fill: parent
                anchors.topMargin: Design.s(Design.space.md)
                anchors.bottomMargin: Design.s(Design.space.md)
                contentWidth: availableWidth
                C.ScrollBar.horizontal.policy: C.ScrollBar.AlwaysOff

                ColumnLayout {
                    width: parent.width
                    spacing: Design.s(2)

                    SideHeading { text: "Places" }
                    SideRow { label: "Home"; glyph: "\u{f02dc}"; path: window.homeDir }
                    Repeater {
                        model: [
                            { label: "Desktop",   glyph: "\u{f01c4}", sub: "Desktop" },
                            { label: "Documents", glyph: "\u{f0219}", sub: "Documents" },
                            { label: "Downloads", glyph: "\u{f01da}", sub: "Downloads" },
                            { label: "Pictures",  glyph: "\u{f02e9}", sub: "Pictures" },
                            { label: "Music",     glyph: "\u{f075a}", sub: "Music" },
                            { label: "Videos",    glyph: "\u{f0567}", sub: "Videos" }
                        ]
                        delegate: SideRow {
                            required property var modelData
                            label: modelData.label
                            glyph: modelData.glyph
                            path: window.homeDir + "/" + modelData.sub
                            visible: FilesBackend.pathExists(path)
                        }
                    }
                    SideRow {
                        label: "Trash"
                        glyph: FilesBackend.trashCount > 0 ? "\u{f0a7a}" : "\u{f0a79}"
                        path: FilesBackend.trashPath
                        badge: FilesBackend.trashCount > 0 ? String(FilesBackend.trashCount) : ""
                    }

                    SideHeading { text: "Devices" }
                    SideRow { label: "File System"; glyph: "\u{f02ca}"; path: "/"; detail: FilesBackend.diskFreeSpace }
                    Repeater {
                        model: FilesBackend.volumes
                        delegate: SideRow {
                            required property var modelData
                            label: modelData.name
                            glyph: "\u{f02cb}"
                            path: modelData.path
                            detail: modelData.free
                            ejectable: true
                            onEject: FilesBackend.unmount(modelData.path)
                        }
                    }

                    SideHeading {
                        text: "Bookmarks"
                        action: "\u{f0415}"
                        actionTip: "Bookmark this folder (Ctrl+D)"
                        onActionClicked: window.addBookmark(window.currentPath)
                    }
                    Repeater {
                        model: window.bookmarks
                        delegate: SideRow {
                            required property var modelData
                            required property int index
                            label: modelData.name
                            glyph: "\u{f00c0}"
                            path: modelData.path
                            removable: true
                            onRemove: window.removeBookmark(index)
                        }
                    }
                    Label {
                        visible: window.bookmarks.length === 0
                        Layout.leftMargin: Design.s(Design.space.lg)
                        Layout.rightMargin: Design.s(Design.space.md)
                        Layout.fillWidth: true
                        text: "Drag a folder here, or press Ctrl+D"
                        role: "caption"
                        color: Design.textFaint
                        wrapMode: Text.WordWrap
                    }
                    // Dropping a folder on the bookmark list bookmarks it.
                    DropArea {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Design.s(28)
                        keys: ["text/uri-list"]
                        onDropped: drop => {
                            for (const u of drop.urls) {
                                const p = decodeURIComponent(String(u).replace(/^file:\/\//, ""));
                                if (FilesBackend.isDirectory(p)) window.addBookmark(p);
                            }
                            drop.accept(Qt.LinkAction);
                        }
                    }
                }
            }
        }

        // ── Main column ──────────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // Folder chooser bar, in --pick-folder mode.
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Design.s(52)
                visible: FilesBackend.pickMode
                color: Design.tint(Design.accent, 0.14)
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Design.s(Design.space.lg)
                    anchors.rightMargin: Design.s(Design.space.lg)
                    spacing: Design.s(Design.space.md)
                    Icon { text: "\u{f024b}"; color: Design.accent }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Label { text: "Choose a folder"; role: "caption"; dim: true }
                        Label { Layout.fillWidth: true; text: window.currentPath; weight: Design.weight.semibold; elide: Text.ElideMiddle }
                    }
                    BarButton { label: "Cancel"; onClicked: FilesBackend.cancelPick() }
                    BarButton { label: "Choose this folder"; primary: true; onClicked: FilesBackend.confirmPick() }
                }
            }

            // ── Toolbar ──────────────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Design.s(52)
                color: Design.surface
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Design.line }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Design.s(Design.space.md)
                    anchors.rightMargin: Design.s(Design.space.md)
                    spacing: Design.s(Design.space.xs)

                    BarButton { glyph: "\u{f004d}"; tip: "Back (Alt+←)"; enabled: FilesBackend.canGoBack; onClicked: FilesBackend.historyBack() }
                    BarButton { glyph: "\u{f0054}"; tip: "Forward (Alt+→)"; enabled: FilesBackend.canGoForward; onClicked: FilesBackend.historyForward() }
                    BarButton { glyph: "\u{f005d}"; tip: "Up (Alt+↑)"; enabled: window.currentPath !== "/"; onClicked: FilesBackend.goUp() }

                    // Path: clickable segments; a click on the empty part of the
                    // bar, or Ctrl+L, types one instead.
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Design.s(34)
                        Layout.leftMargin: Design.s(Design.space.sm)
                        radius: Design.s(Design.radius.ctl)
                        color: Design.sunken
                        border.color: Design.line
                        border.width: 1
                        clip: true

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.IBeamCursor
                            onClicked: window.askName("goto", "", window.currentPath)
                        }
                        ListView {
                            id: crumbs
                            anchors.fill: parent
                            anchors.leftMargin: Design.s(Design.space.xs)
                            anchors.rightMargin: Design.s(Design.space.xs)
                            orientation: ListView.Horizontal
                            interactive: false
                            spacing: 0
                            model: FilesBackend.inTrash ? [{ name: "Trash", path: FilesBackend.trashPath }] : FilesBackend.breadcrumbs
                            onCountChanged: positionViewAtEnd()
                            delegate: Row {
                                required property var modelData
                                required property int index
                                height: crumbs.height
                                Text {
                                    visible: index > 0
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: "\u{f0142}"
                                    font.family: Design.font.icon
                                    font.pixelSize: Design.s(12)
                                    color: Design.textFaint
                                }
                                Rectangle {
                                    readonly property bool last: index === crumbs.count - 1
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: crumbText.implicitWidth + Design.s(16)
                                    height: Design.s(26)
                                    radius: Design.s(Design.radius.sm)
                                    color: crumbMa.containsMouse ? Design.hover : (last ? Design.raised : "transparent")
                                    Text {
                                        id: crumbText
                                        anchors.centerIn: parent
                                        text: modelData.name === "~" ? "Home" : modelData.name
                                        font.family: Design.font.sans
                                        font.pixelSize: Design.s(Design.font.body)
                                        font.weight: parent.last ? Design.weight.semibold : Design.weight.regular
                                        color: parent.last ? Design.text : Design.textDim
                                    }
                                    MouseArea {
                                        id: crumbMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: window.navigateTo(modelData.path)
                                    }
                                    DropArea {
                                        anchors.fill: parent
                                        keys: ["text/uri-list"]
                                        onDropped: drop => window.dropInto(drop, modelData.path)
                                    }
                                }
                            }
                        }
                    }

                    Field {
                        id: searchField
                        Layout.preferredWidth: Design.s(220)
                        Layout.leftMargin: Design.s(Design.space.sm)
                        placeholder: "Search this folder (Ctrl+F)"
                        onEdited: value => FilesBackend.filterQuery = value
                        onAccepted: window.currentView().forceActiveFocus()
                    }

                    Item { Layout.preferredWidth: Design.s(Design.space.sm) }

                    BarButton {
                        visible: FilesBackend.inTrash
                        glyph: "\u{f0a7a}"
                        label: "Empty Trash"
                        danger: true
                        enabled: FilesBackend.trashCount > 0
                        onClicked: confirmEmpty.open()
                    }
                    BarButton { visible: !FilesBackend.inTrash; glyph: "\u{f0b9d}"; tip: "New folder (Ctrl+Shift+N)"; onClicked: window.askName("newfolder", "", "New Folder") }
                    BarButton { glyph: "\u{f0570}"; tip: "Icons (Ctrl+1)"; checked: window.viewMode === "grid"; onClicked: window.viewMode = "grid" }
                    BarButton { glyph: "\u{f0279}"; tip: "List (Ctrl+2)"; checked: window.viewMode === "list"; onClicked: window.viewMode = "list" }
                    BarButton { glyph: "\u{f02fd}"; tip: "Details panel (Ctrl+I)"; checked: window.showInfo; onClicked: window.showInfo = !window.showInfo }
                    BarButton { glyph: "\u{f01d9}"; tip: "View options"; onClicked: viewMenu.popup() }
                }
            }

            // ── Content ──────────────────────────────────────────────────────
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                // Drops on empty space land in this folder.
                DropArea {
                    anchors.fill: parent
                    keys: ["text/uri-list"]
                    onDropped: drop => window.dropInto(drop, window.currentPath)
                }

                // Clicks on empty space: clear the selection, right-click for
                // the folder's own menu. Under the views so items get theirs.
                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: mouse => {
                        window.currentView().forceActiveFocus();
                        if (!(mouse.modifiers & (Qt.ControlModifier | Qt.ShiftModifier))) fm.clearSelection();
                        if (mouse.button === Qt.RightButton) bgMenu.popup();
                    }
                }

                // ── Icons ────────────────────────────────────────────────────
                GridView {
                    id: gridView
                    anchors.fill: parent
                    anchors.margins: Design.s(Design.space.md)
                    visible: window.viewMode === "grid"
                    model: fm
                    clip: true
                    focus: visible
                    boundsBehavior: Flickable.StopAtBounds
                    readonly property int columns: Math.max(1, Math.floor(width / cellWidth))
                    cellWidth: Design.s(window.iconSize + 44)
                    cellHeight: Design.s(window.iconSize + 62)
                    currentIndex: fm.currentIndex
                    highlightFollowsCurrentItem: false
                    C.ScrollBar.vertical: OverflowBar {}
                    Keys.onPressed: event => window.handleKey(event, gridView.columns)

                    delegate: Item {
                        id: tile
                        required property int index
                        required property string name
                        required property string path
                        required property bool isDir
                        required property bool isImage
                        required property bool selected
                        required property bool hidden
                        required property bool symlink
                        required property string category
                        required property string sizeText
                        width: gridView.cellWidth
                        height: gridView.cellHeight

                        Rectangle {
                            id: tileBg
                            anchors.fill: parent
                            anchors.margins: Design.s(3)
                            radius: Design.s(Design.radius.card)
                            color: tile.selected ? Design.tint(Design.accent, 0.24)
                                 : tileDrop.containsDrag ? Design.tint(Design.accent, 0.16)
                                 : tileMa.containsMouse ? Design.hover : "transparent"
                            border.width: tile.selected || tileDrop.containsDrag ? 1 : 0
                            border.color: Design.accent
                            opacity: tile.hidden ? 0.65 : 1.0

                            Item {
                                id: thumbBox
                                anchors.top: parent.top
                                anchors.topMargin: Design.s(Design.space.sm)
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: Design.s(window.iconSize)
                                height: Design.s(window.iconSize)

                                Image {
                                    id: thumb
                                    anchors.fill: parent
                                    visible: tile.isImage && status === Image.Ready
                                    source: tile.isImage ? Paths.fileUrl(tile.path) : ""
                                    sourceSize: Qt.size(Design.s(window.iconSize) * 2, Design.s(window.iconSize) * 2)
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                    smooth: true
                                }
                                Text {
                                    anchors.centerIn: parent
                                    visible: !thumb.visible
                                    text: window.glyphFor(tile.category)
                                    font.family: Design.font.icon
                                    font.pixelSize: Design.s(window.iconSize * 0.78)
                                    color: window.toneFor(tile.category)
                                }
                                Text {
                                    visible: tile.symlink
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    text: "\u{f0339}"
                                    font.family: Design.font.icon
                                    font.pixelSize: Design.s(14)
                                    color: Design.text
                                }
                            }
                            Text {
                                anchors.top: thumbBox.bottom
                                anchors.topMargin: Design.s(Design.space.xs)
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: Design.s(Design.space.xs)
                                anchors.rightMargin: Design.s(Design.space.xs)
                                text: tile.name
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WrapAnywhere
                                maximumLineCount: 2
                                elide: Text.ElideRight
                                font.family: Design.font.sans
                                font.pixelSize: Design.s(Design.font.body)
                                color: Design.text
                            }
                        }

                        DragProxy { id: tileProxy; active: tileMa.drag.active; paths: tile.selected ? fm.selectedPaths() : [tile.path] }

                        MouseArea {
                            id: tileMa
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            drag.target: tileProxy
                            drag.threshold: Design.s(10)
                            onPressed: mouse => window.itemPressed(tile.index, mouse)
                            onReleased: mouse => window.itemReleased(tile.index, mouse, drag.active)
                            onDoubleClicked: mouse => { if (mouse.button === Qt.LeftButton) window.openRow(tile.index); }
                        }
                        DropArea {
                            id: tileDrop
                            anchors.fill: parent
                            enabled: tile.isDir
                            keys: ["text/uri-list"]
                            onDropped: drop => window.dropInto(drop, tile.path)
                        }
                    }
                }

                // ── List with columns ────────────────────────────────────────
                ColumnLayout {
                    anchors.fill: parent
                    visible: window.viewMode === "list"
                    spacing: 0

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Design.s(34)
                        color: Design.surface
                        Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Design.line }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: Design.s(Design.space.lg)
                            anchors.rightMargin: Design.s(Design.space.lg)
                            spacing: Design.s(Design.space.md)
                            ColumnHead { Layout.fillWidth: true; label: "Name"; field: "name" }
                            ColumnHead { Layout.preferredWidth: Design.s(110); label: "Size"; field: "size"; alignRight: true }
                            ColumnHead { Layout.preferredWidth: Design.s(170); label: "Kind"; field: "type" }
                            ColumnHead { Layout.preferredWidth: Design.s(150); label: "Modified"; field: "time" }
                        }
                    }

                    ListView {
                        id: listView
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        model: fm
                        clip: true
                        focus: visible
                        boundsBehavior: Flickable.StopAtBounds
                        currentIndex: fm.currentIndex
                        highlightFollowsCurrentItem: false
                        C.ScrollBar.vertical: OverflowBar {}
                        Keys.onPressed: event => window.handleKey(event, 1)

                        delegate: Item {
                            id: row
                            required property int index
                            required property string name
                            required property string path
                            required property bool isDir
                            required property bool selected
                            required property bool hidden
                            required property string category
                            required property string sizeText
                            required property string kind
                            required property string modifiedText
                            width: listView.width
                            height: Design.s(36)

                            Rectangle {
                                anchors.fill: parent
                                anchors.leftMargin: Design.s(Design.space.sm)
                                anchors.rightMargin: Design.s(Design.space.sm)
                                radius: Design.s(Design.radius.sm)
                                color: row.selected ? Design.tint(Design.accent, 0.24)
                                     : rowDrop.containsDrag ? Design.tint(Design.accent, 0.16)
                                     : rowMa.containsMouse ? Design.hover
                                     : (row.index % 2 ? Design.tint(Design.raised, 0.35) : "transparent")
                                opacity: row.hidden ? 0.65 : 1.0

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: Design.s(Design.space.sm)
                                    anchors.rightMargin: Design.s(Design.space.sm)
                                    spacing: Design.s(Design.space.md)
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Design.s(Design.space.sm)
                                        Text {
                                            Layout.preferredWidth: Design.s(20)
                                            text: window.glyphFor(row.category)
                                            font.family: Design.font.icon
                                            font.pixelSize: Design.s(17)
                                            color: window.toneFor(row.category)
                                            horizontalAlignment: Text.AlignHCenter
                                        }
                                        Label { Layout.fillWidth: true; text: row.name; elide: Text.ElideMiddle }
                                    }
                                    Label { Layout.preferredWidth: Design.s(110); text: row.isDir ? "—" : row.sizeText; dim: true; horizontalAlignment: Text.AlignRight }
                                    Label { Layout.preferredWidth: Design.s(170); text: row.kind; dim: true; elide: Text.ElideRight }
                                    Label { Layout.preferredWidth: Design.s(150); text: row.modifiedText; dim: true; elide: Text.ElideRight }
                                }
                            }

                            DragProxy { id: rowProxy; active: rowMa.drag.active; paths: row.selected ? fm.selectedPaths() : [row.path] }

                            MouseArea {
                                id: rowMa
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                drag.target: rowProxy
                                drag.threshold: Design.s(10)
                                onPressed: mouse => window.itemPressed(row.index, mouse)
                                onReleased: mouse => window.itemReleased(row.index, mouse, drag.active)
                                onDoubleClicked: mouse => { if (mouse.button === Qt.LeftButton) window.openRow(row.index); }
                            }
                            DropArea {
                                id: rowDrop
                                anchors.fill: parent
                                enabled: row.isDir
                                keys: ["text/uri-list"]
                                onDropped: drop => window.dropInto(drop, row.path)
                            }
                        }
                    }
                }

                // ── Nothing to show ──────────────────────────────────────────
                ColumnLayout {
                    anchors.centerIn: parent
                    width: Math.min(parent.width - Design.s(48), Design.s(360))
                    visible: fm.count === 0
                    spacing: Design.s(Design.space.sm)
                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: fm.error ? "\u{f0b8a}"
                            : FilesBackend.filterQuery ? "\u{f0349}"
                            : FilesBackend.inTrash ? "\u{f0a79}" : "\u{f0256}"
                        font.family: Design.font.icon
                        font.pixelSize: Design.s(56)
                        color: Design.textFaint
                    }
                    Label {
                        Layout.alignment: Qt.AlignHCenter
                        role: "subhead"
                        weight: Design.weight.semibold
                        text: fm.error ? "Can't open this folder"
                            : FilesBackend.filterQuery ? "Nothing matches “" + FilesBackend.filterQuery + "”"
                            : FilesBackend.inTrash ? "Trash is empty" : "This folder is empty"
                    }
                    Label {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        dim: true
                        text: fm.error ? fm.error
                            : FilesBackend.filterQuery ? "Search looks at names in this folder only."
                            : FilesBackend.inTrash ? "Things you delete wait here until you empty it."
                            : "Drop files here, paste with Ctrl+V, or make a folder with Ctrl+Shift+N."
                    }
                }
            }

            // ── Status bar ───────────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Design.s(32)
                color: Design.surface
                Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: Design.line }
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Design.s(Design.space.lg)
                    anchors.rightMargin: Design.s(Design.space.md)
                    spacing: Design.s(Design.space.md)
                    Label {
                        Layout.fillWidth: true
                        role: "caption"
                        elide: Text.ElideRight
                        color: window.statusNote ? Design.accent : Design.textDim
                        text: window.statusNote
                              || (FilesBackend.busy ? "Copying…"
                              : fm.selectionCount > 0 ? fm.selectionSummary : fm.summary)
                    }
                    Label { role: "caption"; dim: true; text: FilesBackend.diskFreeSpace; visible: !FilesBackend.inTrash }
                    // Icon size, for the icon view.
                    RowLayout {
                        visible: window.viewMode === "grid"
                        spacing: Design.s(Design.space.xs)
                        BarButton { glyph: "\u{f0374}"; small: true; tip: "Smaller (Ctrl+−)"; onClicked: window.iconSize = Math.max(56, window.iconSize - 16) }
                        BarButton { glyph: "\u{f0415}"; small: true; tip: "Larger (Ctrl+=)"; onClicked: window.iconSize = Math.min(176, window.iconSize + 16) }
                    }
                }
            }
        }

        // ── Details panel ────────────────────────────────────────────────────
        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: Design.s(270)
            visible: window.showInfo && window.width > 980
            color: Design.sunken
            Rectangle { anchors.left: parent.left; width: 1; height: parent.height; color: Design.line }

            // What it describes: the one selected item, or the folder itself.
            readonly property string subject: {
                const n = fm.selectionCount;   // re-read on selection change
                const t = n > 0 ? fm.selectedPaths() : [];
                return t.length === 1 ? t[0] : (t.length === 0 ? window.currentPath : "");
            }
            property var info: ({})
            property string folderSize: ""
            onSubjectChanged: refreshInfo()
            Component.onCompleted: refreshInfo()
            Connections { target: fm; function onReloaded() { infoPanel.refreshInfo(); } }
            id: infoPanel
            function refreshInfo() {
                infoPanel.folderSize = "";
                infoPanel.info = infoPanel.subject ? FilesBackend.itemInfo(infoPanel.subject) : ({});
            }
            Connections {
                target: FilesBackend
                function onFolderSizeReady(path, text, files) {
                    if (path === infoPanel.subject)
                        infoPanel.folderSize = text + " in " + files + (files === 1 ? " file" : " files");
                }
            }

            C.ScrollView {
                anchors.fill: parent
                anchors.margins: Design.s(Design.space.lg)
                contentWidth: availableWidth
                C.ScrollBar.horizontal.policy: C.ScrollBar.AlwaysOff

                ColumnLayout {
                    width: parent.width
                    spacing: Design.s(Design.space.md)

                    // Several selected: a count and a total.
                    ColumnLayout {
                        visible: infoPanel.subject === ""
                        Layout.fillWidth: true
                        spacing: Design.s(Design.space.sm)
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: "\u{f0c51}"
                            font.family: Design.font.icon
                            font.pixelSize: Design.s(72)
                            color: Design.accent
                        }
                        Label { Layout.alignment: Qt.AlignHCenter; role: "subhead"; weight: Design.weight.semibold; text: fm.selectionCount + " items" }
                        Label { Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; dim: true; text: fm.selectionSummary }
                    }

                    // One item, or the folder.
                    ColumnLayout {
                        visible: infoPanel.subject !== ""
                        Layout.fillWidth: true
                        spacing: Design.s(Design.space.md)

                        Rectangle {
                            Layout.fillWidth: true
                            Layout.preferredHeight: Design.s(150)
                            radius: Design.s(Design.radius.card)
                            color: Design.raised
                            Image {
                                id: preview
                                anchors.fill: parent
                                anchors.margins: Design.s(Design.space.sm)
                                visible: infoPanel.info.category === "image" && status === Image.Ready
                                source: infoPanel.info.category === "image" ? Paths.fileUrl(infoPanel.info.path) : ""
                                sourceSize: Qt.size(Design.s(500), Design.s(300))
                                fillMode: Image.PreserveAspectFit
                                asynchronous: true
                            }
                            Text {
                                anchors.centerIn: parent
                                visible: !preview.visible
                                text: window.glyphFor(infoPanel.info.category || "folder")
                                font.family: Design.font.icon
                                font.pixelSize: Design.s(84)
                                color: window.toneFor(infoPanel.info.category || "folder")
                            }
                        }
                        Label {
                            Layout.fillWidth: true
                            text: infoPanel.subject === window.currentPath && infoPanel.subject === window.homeDir ? "Home" : (infoPanel.info.name || "")
                            role: "subhead"
                            weight: Design.weight.semibold
                            wrapMode: Text.WrapAnywhere
                            maximumLineCount: 3
                            elide: Text.ElideRight
                        }
                        Label { text: infoPanel.info.kind || ""; dim: true; Layout.topMargin: -Design.s(Design.space.sm) }

                        Rectangle { Layout.fillWidth: true; height: 1; color: Design.line }

                        InfoRow { label: "Size"; value: infoPanel.info.isDir ? (infoPanel.folderSize || infoPanel.info.sizeText) : (infoPanel.info.sizeText || "") }
                        InfoRow { label: "Contains"; value: infoPanel.info.isDir ? infoPanel.info.items + (infoPanel.info.items === 1 ? " item" : " items") : "" }
                        InfoRow { label: "Modified"; value: infoPanel.info.modified || "" }
                        InfoRow { label: "Created"; value: infoPanel.info.created || "" }
                        InfoRow { label: "Where"; value: infoPanel.info.location || ""; mono: true }
                        InfoRow { label: "Links to"; value: infoPanel.info.symlinkTarget || ""; mono: true }
                        InfoRow { label: "Access"; value: infoPanel.info.permissions ? infoPanel.info.permissions + (infoPanel.info.writable ? "" : "  (read-only for you)") : ""; mono: true }
                        InfoRow { label: "Owner"; value: infoPanel.info.owner || "" }
                    }
                }
            }
        }
    }

    // ── Pressing and releasing an item ───────────────────────────────────────
    //
    // Press selects at once (and right-press opens the menu), except a plain
    // press on something already selected: that may be the start of dragging
    // the whole selection, so the narrowing to one item waits for a release
    // that was not a drag.
    function itemPressed(row, mouse) {
        currentView().forceActiveFocus();
        if (mouse.button === Qt.RightButton) {
            if (!fm.isSelected(row)) fm.select(row, 0);
            openItemMenu();
            return;
        }
        const mode = clickMode(mouse.modifiers);
        if (mode !== 0 || !fm.isSelected(row)) fm.select(row, mode);
    }
    function itemReleased(row, mouse, dragged) {
        if (mouse.button !== Qt.LeftButton || dragged) return;
        if (clickMode(mouse.modifiers) === 0 && fm.selectionCount > 1 && fm.isSelected(row)) fm.select(row, 0);
    }

    // ── Menus ────────────────────────────────────────────────────────────────
    function openItemMenu() {
        const t = targets();
        itemMenu.first = t.length ? fm.get(fm.indexOfPath(t[0])) : ({});
        itemMenu.paths = t;
        itemMenu.apps = t.length === 1 && !!!itemMenu.first.isDir ? FilesBackend.openWithApps(t[0]) : [];
        itemMenu.popup();
    }

    AppMenu {
        id: itemMenu
        property var paths: []
        property var first: ({})
        property var apps: []
        readonly property bool one: paths.length === 1
        readonly property bool trash: FilesBackend.inTrash

        AppMenuItem { text: itemMenu.one && !!itemMenu.first.isDir ? "Open" : (itemMenu.one ? "Open" : "Open " + itemMenu.paths.length + " items"); glyph: "\u{f0770}"; keys: "Enter"; enabled: !itemMenu.trash; onTriggered: window.openSelection() }
        AppMenu {
            id: openWithMenu
            title: "Open With"
            enabled: itemMenu.apps.length > 1 && !itemMenu.trash
            Instantiator {
                model: itemMenu.apps
                delegate: AppMenuItem {
                    required property var modelData
                    text: modelData.name + (modelData.isDefault ? "  (default)" : "")
                    onTriggered: FilesBackend.openWith(modelData.id, itemMenu.paths)
                }
                onObjectAdded: (i, o) => openWithMenu.insertItem(i, o)
                onObjectRemoved: (i, o) => openWithMenu.removeItem(o)
            }
        }
        AppMenuItem { text: "Quick Look"; glyph: "\u{f0208}"; keys: "Space"; enabled: itemMenu.one && !!!itemMenu.first.isDir && !itemMenu.trash; onTriggered: FilesBackend.triggerQuickLook(itemMenu.paths[0]) }
        AppMenuItem { text: "Open Terminal Here"; glyph: "\u{f018d}"; enabled: itemMenu.one && !itemMenu.trash; onTriggered: FilesBackend.openTerminal(!!itemMenu.first.isDir ? itemMenu.paths[0] : window.parentOf(itemMenu.paths[0])) }
        AppMenuSeparator { visible: !itemMenu.trash; height: visible ? implicitHeight : 0 }
        AppMenuItem { text: "Restore"; glyph: "\u{f0450}"; enabled: itemMenu.trash; onTriggered: FilesBackend.restoreFromTrash(itemMenu.paths) }
        AppMenuItem { text: "Cut"; glyph: "\u{f0190}"; keys: "Ctrl+X"; enabled: !itemMenu.trash; onTriggered: window.copySelection(true) }
        AppMenuItem { text: "Copy"; glyph: "\u{f018f}"; keys: "Ctrl+C"; onTriggered: window.copySelection(false) }
        AppMenuItem { text: "Paste Into Folder"; glyph: "\u{f0192}"; enabled: itemMenu.one && !!itemMenu.first.isDir && !itemMenu.trash && FilesBackend.clipboardHasFiles(); onTriggered: { window.navigateTo(itemMenu.paths[0]); FilesBackend.paste(); } }
        AppMenuItem { text: "Rename…"; glyph: "\u{f03eb}"; keys: "F2"; enabled: itemMenu.one && !itemMenu.trash; onTriggered: window.renameSelection() }
        AppMenuSeparator {}
        AppMenuItem { text: "Extract Here"; glyph: "\u{f05c4}"; enabled: itemMenu.one && itemMenu.first.category === "archive" && !itemMenu.trash
                      onTriggered: window.note(FilesBackend.extractArchive(itemMenu.paths[0]) ? "Extracted " + itemMenu.first.name : "Could not extract " + itemMenu.first.name) }
        AppMenuItem { text: "Set as Wallpaper"; glyph: "\u{f02e9}"; enabled: itemMenu.one && itemMenu.first.category === "image" && !itemMenu.trash
                      onTriggered: { FilesBackend.setWallpaper(itemMenu.paths[0]); window.note("Wallpaper set"); } }
        AppMenuItem { text: "Add to Bookmarks"; glyph: "\u{f00c0}"; keys: "Ctrl+D"; enabled: itemMenu.one && !!itemMenu.first.isDir && !itemMenu.trash; onTriggered: window.addBookmark(itemMenu.paths[0]) }
        AppMenuItem { text: "Copy Path"; glyph: "\u{f0219}"; keys: "Ctrl+Shift+C"; onTriggered: { FilesBackend.copyText(itemMenu.paths.join("\n")); window.note("Path copied"); } }
        AppMenuItem { text: "Properties"; glyph: "\u{f02fd}"; keys: "Ctrl+I"; onTriggered: window.showInfo = true }
        AppMenuSeparator {}
        AppMenuItem { text: "Move to Trash"; glyph: "\u{f0a7a}"; keys: "Del"; tone: Design.danger; enabled: !itemMenu.trash; onTriggered: window.trashSelection() }
        AppMenuItem { text: "Delete Permanently…"; glyph: "\u{f05e8}"; keys: itemMenu.trash ? "Del" : "Shift+Del"; tone: Design.danger; onTriggered: confirmDelete.ask(itemMenu.paths) }
    }

    AppMenu {
        id: bgMenu
        AppMenuItem { text: "Undo " + FilesBackend.undoLabel; glyph: "\u{f054c}"; keys: "Ctrl+Z"; enabled: FilesBackend.undoLabel !== ""; onTriggered: FilesBackend.undo() }
        AppMenuItem { text: "Paste"; glyph: "\u{f0192}"; keys: "Ctrl+V"; enabled: !FilesBackend.inTrash && FilesBackend.clipboardHasFiles() && !FilesBackend.busy; onTriggered: FilesBackend.paste() }
        AppMenuItem { text: "New Folder…"; glyph: "\u{f0b9d}"; keys: "Ctrl+Shift+N"; enabled: !FilesBackend.inTrash; onTriggered: window.askName("newfolder", "", "New Folder") }
        AppMenuItem { text: "New File…"; glyph: "\u{f0224}"; enabled: !FilesBackend.inTrash; onTriggered: window.askName("newfile", "", "New File.txt") }
        AppMenuItem { text: "Select All"; glyph: "\u{f0486}"; keys: "Ctrl+A"; enabled: fm.count > 0; onTriggered: fm.selectAll() }
        AppMenuItem { text: "Empty Trash…"; glyph: "\u{f0a7a}"; tone: Design.danger; enabled: FilesBackend.inTrash && FilesBackend.trashCount > 0; onTriggered: confirmEmpty.open() }
        AppMenuSeparator {}
        AppMenuItem { text: "Open Terminal Here"; glyph: "\u{f018d}"; keys: "Ctrl+T"; enabled: !FilesBackend.inTrash; onTriggered: FilesBackend.openTerminal(window.currentPath) }
        AppMenuItem { text: "Bookmark This Folder"; glyph: "\u{f00c0}"; keys: "Ctrl+D"; enabled: !FilesBackend.inTrash; onTriggered: window.addBookmark(window.currentPath) }
        AppMenuItem { text: "Copy Folder Path"; glyph: "\u{f0219}"; onTriggered: { FilesBackend.copyText(window.currentPath); window.note("Path copied"); } }
        AppMenuItem { text: "Refresh"; glyph: "\u{f0450}"; keys: "F5"; onTriggered: FilesBackend.refresh() }
    }

    AppMenu {
        id: viewMenu
        AppMenuItem { text: "Show Hidden Files"; checkable: true; checked: FilesBackend.showHidden; keys: "Ctrl+H"; onTriggered: FilesBackend.showHidden = !FilesBackend.showHidden }
        AppMenuItem { text: "Folders First"; checkable: true; checked: FilesBackend.dirsFirst; onTriggered: FilesBackend.dirsFirst = !FilesBackend.dirsFirst }
        AppMenuSeparator {}
        AppMenuItem { text: "Sort by Name"; checkable: true; checked: FilesBackend.sortField === "name"; onTriggered: FilesBackend.sortField = "name" }
        AppMenuItem { text: "Sort by Size"; checkable: true; checked: FilesBackend.sortField === "size"; onTriggered: FilesBackend.sortField = "size" }
        AppMenuItem { text: "Sort by Kind"; checkable: true; checked: FilesBackend.sortField === "type"; onTriggered: FilesBackend.sortField = "type" }
        AppMenuItem { text: "Sort by Date Modified"; checkable: true; checked: FilesBackend.sortField === "time"; onTriggered: FilesBackend.sortField = "time" }
        AppMenuItem { text: "Reverse Order"; checkable: true; checked: !FilesBackend.sortAscending; onTriggered: FilesBackend.sortAscending = !FilesBackend.sortAscending }
    }

    // ── Dialogs ──────────────────────────────────────────────────────────────
    AppDialog {
        id: nameDialog
        property string mode: ""
        property string target: ""
        title: mode === "rename" ? "Rename"
             : mode === "newfolder" ? "New folder"
             : mode === "newfile" ? "New file" : "Go to folder"
        standardButtons: C.Dialog.Cancel | C.Dialog.Ok
        Component.onCompleted: standardButton(C.Dialog.Ok).text = Qt.binding(() =>
            mode === "rename" ? "Rename" : mode === "goto" ? "Go" : "Create")
        onOpened: {
            nameField.focusInput();
            // A rename selects the name without its extension, as everywhere.
            const dot = (mode === "rename" || mode === "newfile") ? nameField.text.lastIndexOf(".") : -1;
            if (dot > 0) nameField.selectRange(0, dot);
        }
        onAccepted: window.submitName(nameField.text)
        onRejected: window.currentView().forceActiveFocus()
        contentItem: ColumnLayout {
            implicitWidth: Design.s(420)
            spacing: Design.s(Design.space.sm)
            Label {
                text: nameDialog.mode === "goto" ? "Path (~ for home)" : "Name"
                role: "caption"
                dim: true
            }
            Field { id: nameField; Layout.fillWidth: true }
        }
    }

    AppDialog {
        id: confirmDelete
        property var paths: []
        function ask(p) { paths = p; open(); }
        title: paths.length === 1 ? "Delete “" + String(paths[0]).split("/").pop() + "” permanently?"
                                  : "Delete " + paths.length + " items permanently?"
        message: "This cannot be undone. Nothing goes to the trash."
        acceptTone: Design.danger
        standardButtons: C.Dialog.Cancel | C.Dialog.Ok
        Component.onCompleted: standardButton(C.Dialog.Ok).text = "Delete"
        onAccepted: FilesBackend.deletePermanently(paths)
    }

    AppDialog {
        id: confirmEmpty
        title: "Empty the trash?"
        message: FilesBackend.trashCount + (FilesBackend.trashCount === 1 ? " item is" : " items are") + " deleted for good."
        acceptTone: Design.danger
        standardButtons: C.Dialog.Cancel | C.Dialog.Ok
        Component.onCompleted: standardButton(C.Dialog.Ok).text = "Empty Trash"
        onAccepted: FilesBackend.emptyTrash()
    }

    // ═════════════════════════════════════════════════════════════════════════
    // Pieces
    // ═════════════════════════════════════════════════════════════════════════

    // Carries the drag: text/uri-list, so other applications take it too.
    component DragProxy: Item {
        property var paths: []
        property bool active: false
        width: 1; height: 1
        Drag.active: active
        Drag.dragType: Drag.Automatic
        Drag.supportedActions: Qt.MoveAction | Qt.CopyAction
        Drag.proposedAction: Qt.MoveAction
        Drag.mimeData: ({ "text/uri-list": window.urlsOf(paths) })
        Drag.keys: ["text/uri-list"]
    }

    component SideHeading: RowLayout {
        id: sh
        property alias text: shLabel.text
        property string action: ""
        property string actionTip: ""
        signal actionClicked()
        Layout.fillWidth: true
        Layout.topMargin: Design.s(Design.space.md)
        Layout.leftMargin: Design.s(Design.space.lg)
        Layout.rightMargin: Design.s(Design.space.sm)
        Layout.bottomMargin: Design.s(Design.space.xxs)
        Label {
            id: shLabel
            Layout.fillWidth: true
            role: "caption"
            weight: Design.weight.semibold
            color: Design.textFaint
            font.capitalization: Font.AllUppercase
            font.letterSpacing: 0.6
        }
        BarButton { visible: sh.action !== ""; glyph: sh.action; tip: sh.actionTip; small: true; onClicked: sh.actionClicked() }
    }

    component SideRow: Rectangle {
        id: sr
        property string label: ""
        property string glyph: ""
        property string path: ""
        property string detail: ""
        property string badge: ""
        property bool removable: false
        property bool ejectable: false
        signal remove()
        signal eject()
        readonly property bool active: path === window.currentPath
        Layout.fillWidth: true
        Layout.leftMargin: Design.s(Design.space.sm)
        Layout.rightMargin: Design.s(Design.space.sm)
        Layout.preferredHeight: visible ? Design.s(36) : 0
        radius: Design.s(Design.radius.ctl)
        color: active ? Design.tint(Design.accent, 0.22)
             : srDrop.containsDrag ? Design.tint(Design.accent, 0.14)
             : srMa.containsMouse ? Design.hover : "transparent"

        MouseArea {
            id: srMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { window.navigateTo(sr.path); window.currentView().forceActiveFocus(); }
        }
        DropArea {
            id: srDrop
            anchors.fill: parent
            keys: ["text/uri-list"]
            onDropped: drop => window.dropInto(drop, sr.path)
        }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Design.s(Design.space.sm)
            anchors.rightMargin: Design.s(Design.space.xs)
            spacing: Design.s(Design.space.sm)
            Text {
                Layout.preferredWidth: Design.s(22)
                text: sr.glyph
                font.family: Design.font.icon
                font.pixelSize: Design.s(17)
                color: sr.active ? Design.accent : Design.textDim
                horizontalAlignment: Text.AlignHCenter
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Label {
                    Layout.fillWidth: true
                    text: sr.label
                    elide: Text.ElideRight
                    weight: sr.active ? Design.weight.semibold : Design.weight.regular
                }
                Label { visible: sr.detail !== ""; text: sr.detail; role: "caption"; color: Design.textFaint }
            }
            Rectangle {
                visible: sr.badge !== ""
                implicitWidth: badgeText.implicitWidth + Design.s(12)
                implicitHeight: Design.s(20)
                radius: height / 2
                color: Design.raised
                Text { id: badgeText; anchors.centerIn: parent; text: sr.badge; font.family: Design.font.sans; font.pixelSize: Design.s(Design.font.caption); color: Design.textDim }
            }
            BarButton {
                visible: sr.removable && (srMa.containsMouse || hovered)
                glyph: "\u{f0156}"; small: true; tip: "Remove bookmark"
                onClicked: sr.remove()
            }
            BarButton {
                visible: sr.ejectable
                glyph: "\u{f01ea}"; small: true; tip: "Unmount"
                onClicked: sr.eject()
            }
        }
    }

    component ColumnHead: Item {
        id: ch
        property string label: ""
        property string field: ""
        property bool alignRight: false
        readonly property bool sorted: FilesBackend.sortField === field
        implicitHeight: Design.s(34)
        Row {
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: ch.alignRight ? parent.right : undefined
            anchors.left: ch.alignRight ? undefined : parent.left
            anchors.leftMargin: ch.alignRight ? 0 : Design.s(28)
            spacing: Design.s(Design.space.xs)
            Text {
                text: ch.label
                font.family: Design.font.sans
                font.pixelSize: Design.s(Design.font.caption)
                font.weight: Design.weight.semibold
                color: ch.sorted ? Design.text : Design.textDim
            }
            Text {
                visible: ch.sorted
                text: FilesBackend.sortAscending ? "\u{f005d}" : "\u{f0045}"
                font.family: Design.font.icon
                font.pixelSize: Design.s(Design.font.caption)
                color: Design.accent
            }
        }
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (ch.sorted) FilesBackend.sortAscending = !FilesBackend.sortAscending;
                else { FilesBackend.sortField = ch.field; FilesBackend.sortAscending = ch.field === "name" || ch.field === "type"; }
            }
        }
    }

    component InfoRow: ColumnLayout {
        property string label: ""
        property string value: ""
        property bool mono: false
        visible: value !== ""
        Layout.fillWidth: true
        spacing: Design.s(Design.space.xxs)
        Label { text: parent.label; role: "caption"; color: Design.textFaint }
        Label { Layout.fillWidth: true; text: parent.value; wrapMode: Text.WrapAnywhere; isMono: parent.mono; role: parent.mono ? "caption" : "body" }
    }
}
