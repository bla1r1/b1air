import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Controls
import "Ui"
import Qt.labs.folderlistmodel

ApplicationWindow {
    id: window
    title: "Files — " + currentPathDisplay
    width: Design.s(1060)
    height: Design.s(680)
    minimumWidth: 740
    minimumHeight: 480
    visible: true
    color: "transparent"
    flags: Qt.Window

    readonly property bool isNative: typeof FilesBackend !== "undefined"
    readonly property string homeDir: isNative ? FilesBackend.homePath : "/home/dev"

    // Where this desktop's own checkout actually is. install.sh records it and
    // SystemControl::find_dotfiles_repo() reads the same file, which is what
    // stopped the daemon guessing at a handful of paths — one of them a
    // specific developer's. Read the same way Ui/Design reads the active
    // theme: plain Qt over XMLHttpRequest, which is what the session sets
    // QML_XHR_ALLOW_FILE_READ for. Empty when there is no such file, and the
    // sidebar entry is then simply absent rather than pointing nowhere.
    readonly property string dotfilesRepo: {
        if (!window.isNative)
            return "";
        const xhr = new XMLHttpRequest();
        try {
            xhr.open("GET", "file://" + window.homeDir + "/.local/state/b1air/dotfiles-repo", false);
            xhr.send();
            if (xhr.status === 0 || xhr.status === 200)
                return (xhr.responseText || "").trim();
        } catch (e) {}
        return "";
    }
    property string currentPath: isNative ? FilesBackend.currentPath : homeDir
    property string currentPathDisplay: currentPath.startsWith(homeDir) 
        ? ("~" + currentPath.substring(homeDir.length)) 
        : currentPath

    property var history: [currentPath]
    property int historyIndex: 0

    property bool showHidden: false
    property string filterQuery: ""
    property string viewMode: "grid" // "grid", "list", "gallery"
    property int selectedIndex: -1
    property string selectedPath: ""

    // User Bookmarks
    // Read from disk, not shipped. The one entry that used to be hard-coded
    // here pointed at ~/DotsFiles, which does not exist on a machine that
    // cloned the repository anywhere else, and the list itself was never
    // stored: the "+" in the sidebar appended to this array, the row appeared,
    // and closing the window lost it. loadBookmarks() also drops any entry
    // whose directory has since gone, so a bookmark on screen is one that
    // still leads somewhere.
    property var customBookmarks: window.isNative ? FilesBackend.loadBookmarks() : []

    // A second, hand-rolled Tokyo Night palette used to live here alongside the
    // Catppuccin one in Ui/Design.qml, so this window never followed the theme.
    // The names stay — they are used throughout the file — but each now resolves
    // to a design-system role.
    readonly property color colBg: Design.surface
    readonly property color colDark: Design.ground
    readonly property color colSidebar: Design.sunken
    readonly property color colSunken: Design.sunken
    readonly property color colCard: Design.raised
    readonly property color colCardHover: Design.hover
    readonly property color colBorder: Design.glassBorder
    readonly property color colBorderSubtle: Design.line
    readonly property color colBlue: Design.accent
    readonly property color colPurple: Design.mauve
    readonly property color colPink: Design.pink
    readonly property color colCyan: Design.sapphire
    readonly property color colGreen: Design.ok
    readonly property color colOrange: Design.warn
    readonly property color colYellow: Design.yellow
    readonly property color colRed: Design.danger
    readonly property color colFg: Design.text
    readonly property color colDim: Design.textDim

    function formatSize(bytes) {
        if (!bytes || bytes <= 0) return "0 B";
        if (bytes < 1024) return bytes + " B";
        if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + " KB";
        if (bytes < 1024 * 1024 * 1024) return (bytes / (1024 * 1024)).toFixed(1) + " MB";
        return (bytes / (1024 * 1024 * 1024)).toFixed(1) + " GB";
    }

    function formatDate(d) {
        if (!d) return "";
        let date = new Date(d);
        return date.toLocaleDateString(Qt.locale(), "MMM d, yyyy") + " " + date.toLocaleTimeString(Qt.locale(), "hh:mm");
    }

    // One table, not two lists.
    //
    // The glyph and the colour were each chosen by their own chain of
    // indexOf() calls over their own hand-kept extension lists, and the two had
    // drifted: .ts, .bmp and every audio format had a glyph but no colour, so
    // they drew a music note in the default foreground; .ini and .toml had the
    // document colour but the generic file glyph; .bz2 and .xz were archives to
    // one list and unknown to the other. A file's kind is one fact, so it is
    // decided once and both answers come from it.
    readonly property var fileKinds: [
        { glyph: "󰋩", tone: "purple", ext: ["png","jpg","jpeg","webp","gif","svg","bmp","ico","tiff","avif"] },
        { glyph: "󰕼", tone: "orange", ext: ["mp4","mkv","avi","mov","webm","m4v"] },
        { glyph: "󰎆", tone: "pink",   ext: ["mp3","flac","wav","ogg","m4a","opus"] },
        { glyph: "󰅩", tone: "cyan",   ext: ["cpp","hpp","cc","cxx","c","h","rs","py","js","ts","jsx","tsx","qml","go","java","rb","lua","vim"] },
        { glyph: "󰆍", tone: "green",  ext: ["sh","bash","zsh","fish"] },
        { glyph: "󰛫", tone: "yellow", ext: ["zip","tar","gz","7z","bz2","xz","zst","rar"] },
        { glyph: "󰘦", tone: "green",  ext: ["json","yaml","yml","toml","ini","conf","cfg"] },
        { glyph: "󰈙", tone: "green",  ext: ["txt","md","rst","org"] },
        { glyph: "󰈦", tone: "red",    ext: ["pdf"] }
    ]

    function fileKind(name) {
        const ext = (name || "").split('.').pop().toLowerCase();
        for (const k of window.fileKinds)
            if (k.ext.indexOf(ext) >= 0) return k;
        return null;
    }

    function getIconGlyph(name, isDir) {
        if (isDir) return "󰉋";
        const k = window.fileKind(name);
        return k ? k.glyph : "󰈔";
    }

    function getIconColor(name, isDir) {
        if (isDir) return window.colBlue;
        const k = window.fileKind(name);
        switch (k ? k.tone : "") {
        case "purple": return window.colPurple;
        case "orange": return window.colOrange;
        case "pink":   return window.colPink;
        case "cyan":   return window.colCyan;
        case "green":  return window.colGreen;
        case "yellow": return window.colYellow;
        case "red":    return window.colRed;
        default:       return window.colFg;
        }
    }

    function isImageFile(name) {
        if (!name) return false;
        let ext = name.split('.').pop().toLowerCase();
        return ["png","jpg","jpeg","webp","gif","svg","bmp"].indexOf(ext) >= 0;
    }

    function getBreadcrumbs() {
        let p = currentPath;
        let crumbs = [];
        if (p.startsWith(homeDir)) {
            crumbs.push({ name: "~", path: homeDir });
            let rel = p.substring(homeDir.length);
            let parts = rel.split("/").filter(Boolean);
            let acc = homeDir;
            for (let i = 0; i < parts.length; ++i) {
                acc += "/" + parts[i];
                crumbs.push({ name: parts[i], path: acc });
            }
        } else {
            crumbs.push({ name: "/", path: "/" });
            let parts = p.split("/").filter(Boolean);
            let acc = "";
            for (let i = 0; i < parts.length; ++i) {
                acc += "/" + parts[i];
                crumbs.push({ name: parts[i], path: acc });
            }
        }
        return crumbs;
    }

    function navigateTo(path) {
        if (!path || path === currentPath) return;
        currentPath = path;
        selectedIndex = -1;
        selectedPath = "";

        if (historyIndex >= 0 && historyIndex < history.length - 1) {
            history = history.slice(0, historyIndex + 1);
        }
        history.push(path);
        historyIndex = history.length - 1;
    }

    function historyBack() {
        if (historyIndex > 0) {
            historyIndex--;
            currentPath = history[historyIndex];
            selectedIndex = -1;
            selectedPath = "";
        }
    }

    function historyForward() {
        if (historyIndex < history.length - 1) {
            historyIndex++;
            currentPath = history[historyIndex];
            selectedIndex = -1;
            selectedPath = "";
        }
    }

    function goUp() {
        if (currentPath === "/" || currentPath === "") return;
        let parts = currentPath.split("/").filter(Boolean);
        if (parts.length <= 1) {
            navigateTo("/");
        } else {
            parts.pop();
            navigateTo("/" + parts.join("/"));
        }
    }

    function openItem(path, isDir) {
        if (isDir) {
            navigateTo(path);
        } else if (isNative) {
            FilesBackend.openItem(path);
        }
    }

    function openTerminalHere() {
        if (isNative) {
            FilesBackend.openTerminal(currentPath);
        }
    }

    function triggerQuickLook() {
        if (selectedPath && isNative) {
            FilesBackend.triggerQuickLook(selectedPath);
        }
    }

    function addCurrentToBookmarks() {
        let name = currentPath.split('/').pop() || "Folder";
        if (currentPath === homeDir) name = "Home";
        if (currentPath === "/") name = "Root";

        for (let b of customBookmarks) {
            if (b.path === currentPath) return;
        }
        let copy = Array.from(customBookmarks);
        copy.push({ name: name, path: currentPath, icon: "󰉋" });
        customBookmarks = copy;
        if (window.isNative) FilesBackend.saveBookmarks(copy);
    }

    function removeBookmark(index) {
        let copy = Array.from(customBookmarks);
        copy.splice(index, 1);
        customBookmarks = copy;
        if (window.isNative) FilesBackend.saveBookmarks(copy);
    }

    // ── FolderListModel ──────────────────────────────────────────────────────
    FolderListModel {
        id: folderModel
        folder: "file://" + window.currentPath
        showDirsFirst: true
        showDotAndDotDot: false
        showHidden: window.showHidden
        nameFilters: window.filterQuery ? ["*" + window.filterQuery + "*"] : ["*"]
        sortField: FolderListModel.Name
        sortReversed: false
    }

    // ── Global Keyboard Shortcuts ────────────────────────────────────────────
    Shortcut { sequence: "Space"; onActivated: window.triggerQuickLook() }
    Shortcut { sequence: "Return"; onActivated: {
        if (selectedIndex >= 0 && selectedIndex < folderModel.count) {
            window.openItem(folderModel.get(selectedIndex, "filePath"), folderModel.isFolder(selectedIndex));
        }
    }}
    Shortcut { sequence: "Alt+Up"; onActivated: window.goUp() }
    Shortcut { sequence: "Backspace"; onActivated: window.goUp() }
    Shortcut { sequence: "Alt+Left"; onActivated: window.historyBack() }
    Shortcut { sequence: "Alt+Right"; onActivated: window.historyForward() }
    Shortcut { sequence: "Ctrl+H"; onActivated: window.showHidden = !window.showHidden }
    Shortcut { sequence: "Ctrl+T"; onActivated: window.openTerminalHere() }
    Shortcut { sequence: "Ctrl+F"; onActivated: searchField.forceActiveFocus() }
    Shortcut { sequence: "Escape"; onActivated: { searchField.text = ""; window.filterQuery = ""; } }

    // ═════════════════════════════════════════════════════════════════════════
    // ROOT WINDOW FRAME (Rounded Corners + Antialiased Border)
    // ═════════════════════════════════════════════════════════════════════════
    Rectangle {
        id: windowFrame
        anchors.fill: parent
        // No corners or outline of our own: sway draws both, and only sway
        // knows which window has focus. The app drew a fixed 1px line and sway
        // was told `border none` for it, so ours were the only windows on the
        // desktop that did not light up when focused. SwayFX's corner_radius
        // rounds the surface; a 14px radius inside its 10px one left slivers.
        radius: 0
        color: window.colBg
        clip: true

        RowLayout {
            anchors.fill: parent
            spacing: 0

            // ═════════════════════════════════════════════════════════════════
            // LEFT SIDEBAR (210px, Full-Height Sleek Obsidian)
            // ═════════════════════════════════════════════════════════════════
            Rectangle {
                Layout.fillHeight: true
                Layout.preferredWidth: Design.s(210)
                color: window.colSidebar

                // Subtle right divider line
                Rectangle {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: 1
                    color: window.colBorderSubtle
                    z: 5
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Design.s(14)
                    spacing: Design.s(10)

                    // No app header. The window is opened by name, has this suite's frame
                    // and a folder tree in it — nothing about "Files / Explorer & Gallery"
                    // was news, and it cost the top of the sidebar, which is where the
                    // places you actually navigate to belong.

                    // 1. QUICK JUMP (Root, Home, the dotfiles checkout)
                    //
                    // Three of the glyphs below were simply the wrong picture,
                    // which in a sidebar of icon-and-label rows is only half
                    // wrong — and in the viewer's unlabelled toolbar, where the
                    // same check found a ✕ on "Zoom Out", entirely so. Root had
                    // Home's house, Downloads pointed *up*, and Videos was the
                    // VLC traffic cone among six generic places. Verified by
                    // rendering the codepoints, not by trusting their names.
                    Text {
                        text: "QUICK JUMP"
                        font.family: Design.font.mono
                        font.pixelSize: Design.s(9)
                        font.bold: true
                        color: window.colDim
                        Layout.topMargin: 4
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Design.s(2)

                        SidebarPill { label: "Root (/)"; path: "/"; icon: "󰋊"; iconCol: window.colRed }
                        SidebarPill { label: "Home (~)"; path: window.homeDir; icon: "󰋜"; iconCol: window.colBlue }
                        SidebarPill {
                            // Was hard-coded to ~/DotsFiles, which does not exist on a
                            // machine that cloned the repository anywhere else — this one
                            // keeps it under ~/Documents/GitHub — so the shortcut led to a
                            // directory that is not there, and duplicated the bookmark
                            // below on a machine where it happened to be right. install.sh
                            // records the real path and the daemon reads the same file to
                            // find the checkout; so does this.
                            visible: window.dotfilesRepo !== ""
                            label: window.dotfilesRepo.split("/").pop()
                            path: window.dotfilesRepo
                            icon: "\u{f02a2}"
                            iconCol: window.colCyan
                        }
                    }

                    // 2. PLACES
                    Text {
                        text: "PLACES"
                        font.family: Design.font.mono
                        font.pixelSize: Design.s(9)
                        font.bold: true
                        color: window.colDim
                        Layout.topMargin: 4
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Design.s(2)

                        SidebarPill { label: "Documents"; path: window.homeDir + "/Documents"; icon: "󰈙"; iconCol: window.colPurple }
                        SidebarPill { label: "Downloads"; path: window.homeDir + "/Downloads"; icon: "󰁅"; iconCol: window.colGreen }
                        SidebarPill { label: "Pictures"; path: window.homeDir + "/Pictures"; icon: "󰋩"; iconCol: window.colPurple }
                        SidebarPill { label: "Music"; path: window.homeDir + "/Music"; icon: "󰎆"; iconCol: window.colOrange }
                        SidebarPill { label: "Videos"; path: window.homeDir + "/Videos"; icon: "󰎁"; iconCol: window.colRed }
                    }

                    // 3. BOOKMARKS
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 4

                        Text {
                            text: "BOOKMARKS"
                            font.family: Design.font.mono
                            font.pixelSize: Design.s(9)
                            font.bold: true
                            color: window.colDim
                        }
                        Item { Layout.fillWidth: true }
                        Rectangle {
                            width: Design.s(18); height: Design.s(18); radius: Design.s(4)
                            color: addBmArea.containsMouse ? Design.tint(Design.accent, 0.25) : "transparent"
                            Text {
                                anchors.centerIn: parent
                                text: "󰐕"
                                font.family: Design.font.mono
                                font.pixelSize: Design.s(11)
                                color: addBmArea.containsMouse ? window.colBlue : window.colDim
                            }
                            MouseArea {
                                id: addBmArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: window.addCurrentToBookmarks()
                            }
                        }
                    }

                    ListView {
                        id: bookmarksList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: Design.s(2)
                        model: window.customBookmarks

                        delegate: Rectangle {
                            width: bookmarksList.width
                            height: Design.s(28)
                            radius: Design.s(6)
                            color: window.currentPath === modelData.path ? Design.tint(Design.accent, 0.20) : (bmArea.containsMouse ? Design.tint(Design.text, 0.05) : "transparent")
                            border.color: window.currentPath === modelData.path ? Design.tint(Design.accent, 0.40) : "transparent"
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Design.s(8)
                                anchors.rightMargin: Design.s(6)
                                spacing: Design.s(6)

                                Text { text: modelData.icon || "󰉋"; font.family: Design.font.mono; font.pixelSize: Design.s(12); color: window.colBlue }
                                Text { text: modelData.name; font.family: Design.font.sans; font.pixelSize: Design.s(11); color: window.colFg; Layout.fillWidth: true; elide: Text.ElideRight }
                                Text {
                                    text: "×"
                                    font.pixelSize: Design.s(13)
                                    color: delBmArea.containsMouse ? window.colRed : window.colDim
                                    visible: bmArea.containsMouse
                                    MouseArea {
                                        id: delBmArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: window.removeBookmark(index)
                                    }
                                }
                            }

                            MouseArea {
                                id: bmArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: window.navigateTo(modelData.path)
                            }
                        }
                    }

                    // Storage Device Card with Progress Bar
                    Rectangle {
                        Layout.fillWidth: true
                        height: Design.s(44)
                        radius: Design.s(8)
                        color: window.colSunken
                        border.color: window.colBorderSubtle
                        border.width: 1

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: Design.s(8)
                            spacing: Design.s(4)

                            RowLayout {
                                Layout.fillWidth: true
                                Text { text: "󰋊 System Drive"; font.family: Design.font.sans; font.pixelSize: Design.s(10); font.bold: true; color: window.colFg }
                                Item { Layout.fillWidth: true }
                                Text { text: isNative ? FilesBackend.diskFreeSpace : "12.8 GB free"; font.family: Design.font.sans; font.pixelSize: Design.s(9); color: window.colDim }
                            }

                            Rectangle {
                                Layout.fillWidth: true
                                height: Design.s(4)
                                radius: Design.s(2)
                                color: window.colBorderSubtle

                                Rectangle {
                                    width: parent.width * 0.42
                                    height: parent.height
                                    radius: Design.s(2)
                                    color: window.colBlue
                                }
                            }
                        }
                    }
                }

                component SidebarPill: Rectangle {
                    id: pill
                    property string label: ""
                    property string path: ""
                    property string icon: "󰉋"
                    property color iconCol: window.colBlue

                    readonly property bool isActive: window.currentPath === pill.path

                    Layout.fillWidth: true
                    height: Design.s(28)
                    radius: Design.s(6)
                    color: isActive ? Design.tint(Design.accent, 0.20) : (pillArea.containsMouse ? Design.tint(Design.text, 0.05) : "transparent")
                    border.color: isActive ? Design.tint(Design.accent, 0.45) : "transparent"
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Design.s(8)
                        anchors.rightMargin: Design.s(8)
                        spacing: Design.s(8)

                        Text { text: pill.icon; font.family: Design.font.mono; font.pixelSize: Design.s(12); color: pill.isActive ? window.colBlue : pill.iconCol }
                        Text { text: pill.label; font.family: Design.font.sans; font.pixelSize: Design.s(11); color: pill.isActive ? "#ffffff" : window.colFg; Layout.fillWidth: true; elide: Text.ElideRight }
                    }

                    MouseArea {
                        id: pillArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: window.navigateTo(pill.path)
                    }
                }
            }

            // ═════════════════════════════════════════════════════════════════
            // RIGHT WORKSPACE: HEADER TOOLBAR, FILE BROWSER, FOOTER
            // ═════════════════════════════════════════════════════════════════
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                // ── Top Navigation Bar (46px) ────────────────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Design.s(46)
                    color: window.colDark

                    // Subtle bottom divider
                    Rectangle {
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: 1
                        color: window.colBorderSubtle
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Design.s(12)
                        anchors.rightMargin: Design.s(12)
                        spacing: Design.s(8)

                        // History Navigation Cluster
                        //
                        // This had a height and no width. Its only child is
                        // anchored, and an anchored child gives its parent no
                        // implicit size, so the capsule was zero pixels wide:
                        // the background and border never drew at all, and the
                        // row of four buttons spilled out of it symmetrically —
                        // half of it left, across the sidebar divider and up
                        // against the app title, and half right, underneath the
                        // breadcrumb. Sized from its contents, it sits in the
                        // toolbar where it belongs and collides with nothing.
                        Rectangle {
                            implicitWidth: navRow.implicitWidth + Design.s(10)
                            height: Design.s(30)
                            radius: Design.s(6)
                            color: window.colSunken
                            border.color: window.colBorderSubtle
                            border.width: 1

                            Row {
                                id: navRow
                                anchors.centerIn: parent
                                spacing: Design.s(2)

                                NavIconBtn { icon: "󰁍"; enabled: window.historyIndex > 0; onClicked: window.historyBack() }
                                NavIconBtn { icon: "󰁔"; enabled: window.historyIndex < window.history.length - 1; onClicked: window.historyForward() }
                                NavIconBtn { icon: "󰁝"; enabled: window.currentPath !== "/"; onClicked: window.goUp() }
                                // Re-points the model as well as asking the backend for the disk
                                // figures. The button used to do only the second of those — the list
                                // is a FolderListModel bound to currentPath, and nothing told it to
                                // look again — so "refresh" refreshed the free-space readout and left
                                // the files exactly as they were.
                                NavIconBtn {
                                    icon: "󰑐"
                                    enabled: true
                                    onClicked: {
                                        if (!isNative) return;
                                        FilesBackend.refresh();
                                        const here = folderModel.folder;
                                        folderModel.folder = "";
                                        folderModel.folder = here;
                                    }
                                }
                            }
                        }

                        // Breadcrumbs, not a capsule.
                        //
                        // These sat inside a sunken, bordered, full-width
                        // field. In the home directory that drew a 900-pixel
                        // inset box around a single "~" chip — and an empty
                        // inset field is the shape of a text input waiting to
                        // be filled, which this is not. Without the box the
                        // crumbs are just a path on the toolbar, which is what
                        // they are and what every other file manager shows.
                        // The width still fills, so a long path has room and
                        // still scrolls.
                        Rectangle {
                            Layout.fillWidth: true
                            height: Design.s(30)
                            radius: Design.s(6)
                            color: "transparent"
                            clip: true

                            ListView {
                                id: breadcrumbsList
                                anchors.fill: parent
                                anchors.leftMargin: Design.s(8)
                                anchors.rightMargin: Design.s(8)
                                orientation: ListView.Horizontal
                                spacing: Design.s(4)
                                clip: true
                                model: window.getBreadcrumbs()

                                delegate: RowLayout {
                                    spacing: Design.s(4)
                                    anchors.verticalCenter: parent.verticalCenter

                                    Rectangle {
                                        // The child Text referenced isLast unqualified, which does not
                                        // resolve from its scope, so the current folder was never
                                        // highlighted. Naming the chip fixes both uses.
                                        id: crumbChip
                                        implicitWidth: crumbText.implicitWidth + Design.s(12)
                                        height: Design.s(22)
                                        radius: Design.s(4)
                                        // accentSoft is a container role, and on
                                        // this palette it resolves to a muddy grey
                                        // that reads as a disabled field rather
                                        // than as where you are. The accent tint is
                                        // what marks a selection everywhere else in
                                        // the suite — the sidebar pills, the
                                        // launcher — so the path follows the theme
                                        // the way the rest of it does.
                                        color: crumbChip.isLast ? Design.tint(Design.accent, 0.20)
                                             : (crumbHover.containsMouse ? Design.tint(Design.text, 0.08) : "transparent")
                                        border.color: crumbChip.isLast ? Design.tint(Design.accent, 0.45) : "transparent"
                                        border.width: 1

                                        readonly property bool isLast: index === (breadcrumbsList.count - 1)

                                        Text {
                                            id: crumbText
                                            anchors.centerIn: parent
                                            text: modelData.name
                                            font.family: Design.font.sans
                                            font.pixelSize: Design.s(11)
                                            font.bold: crumbChip.isLast
                                            color: crumbChip.isLast ? Design.accent
                                                 : (crumbHover.containsMouse ? Design.text : window.colFg)
                                        }

                                        HoverHandler { id: crumbHover }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: window.navigateTo(modelData.path)
                                        }
                                    }

                                    Text {
                                        text: "󰅂"
                                        font.family: Design.font.mono
                                        color: window.colDim
                                        font.pixelSize: Design.s(9)
                                        visible: index < (breadcrumbsList.count - 1)
                                    }
                                }
                            }
                        }

                        // Search Filter Bar
                        Rectangle {
                            Layout.preferredWidth: Math.min(180, Math.max(120, window.width * 0.18))
                            height: Design.s(30)
                            radius: Design.s(6)
                            color: window.colSunken
                            border.color: searchField.activeFocus ? window.colBlue : window.colBorderSubtle
                            border.width: 1

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Design.s(8)
                                anchors.rightMargin: Design.s(8)
                                spacing: Design.s(6)

                                Text { text: "󰍉"; font.family: Design.font.mono; font.pixelSize: Design.s(11); color: searchField.activeFocus ? window.colBlue : window.colDim }
                                TextInput {
                                    id: searchField
                                    Layout.fillWidth: true
                                    font.family: Design.font.sans
                                    font.pixelSize: Design.s(11)
                                    color: window.colFg
                                    clip: true
                                    selectByMouse: true
                                    onTextChanged: window.filterQuery = text.trim()

                                    Text {
                                        text: "Search files..."
                                        font.family: Design.font.sans
                                        font.pixelSize: Design.s(11)
                                        color: window.colDim
                                        visible: !searchField.text && !searchField.activeFocus
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }
                                Text {
                                    text: "󰅖"
                                    font.family: Design.font.mono
                                    font.pixelSize: Design.s(10)
                                    color: window.colDim
                                    visible: searchField.text.length > 0
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: { searchField.text = ""; window.filterQuery = ""; }
                                    }
                                }
                            }
                        }

                        // Segmented View Mode Capsule [ Grid | List | Gallery ]
                        Rectangle {
                            height: Design.s(30)
                            width: Design.s(90)
                            radius: Design.s(6)
                            color: window.colSunken
                            border.color: window.colBorderSubtle
                            border.width: 1

                            Row {
                                anchors.centerIn: parent
                                spacing: Design.s(2)

                                ViewSegmentBtn { icon: "󰕰"; active: window.viewMode === "grid"; onClicked: window.viewMode = "grid" }
                                ViewSegmentBtn { icon: "󰕱"; active: window.viewMode === "list"; onClicked: window.viewMode = "list" }
                                ViewSegmentBtn { icon: "󰋩"; active: window.viewMode === "gallery"; onClicked: window.viewMode = "gallery" }
                            }
                        }

                        // Quick Action Buttons (Hidden Toggle & Terminal)
                        Row {
                            spacing: Design.s(4)
                            Layout.alignment: Qt.AlignVCenter

                            Rectangle {
                                width: Design.s(30); height: Design.s(30); radius: Design.s(6)
                                color: window.showHidden ? Design.tint(Design.accent, 0.25) : (hidArea.containsMouse ? Design.tint(Design.text, 0.08) : window.colSunken)
                                border.color: window.showHidden ? window.colBlue : window.colBorderSubtle
                                border.width: 1
                                Text { anchors.centerIn: parent; text: "󰈉"; font.family: Design.font.mono; font.pixelSize: Design.s(13); color: window.showHidden ? window.colBlue : window.colDim }
                                MouseArea { id: hidArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: window.showHidden = !window.showHidden }
                            }

                            Rectangle {
                                width: Design.s(30); height: Design.s(30); radius: Design.s(6)
                                color: termArea.containsMouse ? Design.tint(Design.text, 0.08) : window.colSunken
                                border.color: window.colBorderSubtle
                                border.width: 1
                                Text { anchors.centerIn: parent; text: "󰞷"; font.family: Design.font.mono; font.pixelSize: Design.s(13); color: window.colFg }
                                MouseArea { id: termArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: window.openTerminalHere() }
                            }
                        }
                    }
                }

                // ── Main File Browser Canvas ─────────────────────────────────
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    // 1. GRID VIEW (Default, Smooth Fast Scrolling)
                    GridView {
                        id: grid
                        reuseItems: true
                        anchors.fill: parent
                        anchors.margins: Design.s(14)
                        // A fixed cell size ignores the window. At 1280px wide
                        // that laid out fourteen columns of 80px around a 24px
                        // glyph, so a file manager full of files still read as
                        // mostly empty, and every name longer than "DotsFiles"
                        // was elided. The floor decides how small a cell may
                        // get; the remainder is shared out evenly so the grid
                        // reaches the right edge instead of leaving a ragged
                        // strip beside it.
                        readonly property int columns: Math.max(1, Math.floor(width / Design.s(136)))
                        cellWidth: Math.floor(width / grid.columns)
                        cellHeight: grid.cellWidth
                        clip: true
                        visible: window.viewMode === "grid"
                        model: folderModel
                        cacheBuffer: 300

                        delegate: Rectangle {
                            id: gridCard
                            width: grid.cellWidth - Design.s(10)
                            height: grid.cellHeight - Design.s(10)
                            radius: Design.s(8)
                            color: isSelected ? Design.tint(Design.accent, 0.22) : (cardHover.containsMouse ? window.colCardHover : "transparent")
                            border.color: isSelected ? window.colBlue : (cardHover.containsMouse ? Design.tint(Design.text, 0.08) : "transparent")
                            border.width: 1

                            readonly property bool isSelected: window.selectedIndex === index

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: Design.s(6)
                                spacing: Design.s(4)

                                // Low-res fast thumbnail or vector icon
                                Item {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true

                                    Image {
                                        id: gridThumb
                                        anchors.centerIn: parent
                                        width: Design.s(60); height: Design.s(60)
                                        source: window.isImageFile(model.fileName) ? model.filePath : ""
                                        fillMode: Image.PreserveAspectFit

                                        // Ready, not "the name ends in .png". Whether a file is
                                        // an image decided both halves of this, so a picture
                                        // that would not decode — truncated, empty, or simply
                                        // not the format its name claims — drew an empty cell
                                        // with a filename under it and no icon of any kind.
                                        // The glyph now covers that, and covers the moment
                                        // before an async thumbnail arrives.
                                        visible: status === Image.Ready
                                        asynchronous: true
                                        cache: true
                                        // Low resolution decoding to eliminate scroll stutter!
                                        sourceSize: Qt.size(64, 64)
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        text: window.getIconGlyph(model.fileName, model.fileIsDir)
                                        font.family: Design.font.mono
                                        font.pixelSize: Design.s(46)
                                        color: window.getIconColor(model.fileName, model.fileIsDir)
                                        visible: !gridThumb.visible
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: model.fileName || ""
                                    font.family: Design.font.sans
                                    font.pixelSize: Design.s(11)
                                    font.bold: gridCard.isSelected
                                    color: gridCard.isSelected ? "#ffffff" : window.colFg
                                    horizontalAlignment: Text.AlignHCenter
                                    // Two lines. One elided line in an 80px cell
                                    // turned most of a real directory into
                                    // "DotsFile…es" and "run-headl…sh".
                                    wrapMode: Text.Wrap
                                    maximumLineCount: 2
                                    elide: Text.ElideRight
                                }

                                Text {
                                    Layout.fillWidth: true
                                    // A folder is already drawn as a folder, so
                                    // the word under it was a third line of type
                                    // saying what the icon says. Files keep their
                                    // size, which the icon cannot tell you.
                                    visible: !model.fileIsDir
                                    text: window.formatSize(model.fileSize)
                                    font.family: Design.font.sans
                                    font.pixelSize: Design.s(9)
                                    color: window.colDim
                                    horizontalAlignment: Text.AlignHCenter
                                }
                            }

                            HoverHandler { id: cardHover }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    window.selectedIndex = index;
                                    window.selectedPath = model.filePath;
                                }
                                onDoubleClicked: window.openItem(model.filePath, model.fileIsDir)
                            }
                        }
                    }

                    // 2. LIST VIEW
                    ListView {
                        id: listView
                        reuseItems: true
                        anchors.fill: parent
                        anchors.margins: Design.s(10)
                        clip: true
                        visible: window.viewMode === "list"
                        model: folderModel
                        spacing: Design.s(2)

                        delegate: Rectangle {
                            id: listCard
                            width: listView.width
                            height: Design.s(32)
                            radius: Design.s(6)
                            color: isSelected ? Design.tint(Design.accent, 0.22) : (lHover.containsMouse ? window.colCardHover : "transparent")
                            border.color: isSelected ? window.colBlue : "transparent"
                            border.width: 1

                            readonly property bool isSelected: window.selectedIndex === index

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Design.s(10)
                                anchors.rightMargin: Design.s(10)
                                spacing: Design.s(8)

                                Text {
                                    text: window.getIconGlyph(model.fileName, model.fileIsDir)
                                    font.family: Design.font.mono
                                    font.pixelSize: Design.s(15)
                                    color: window.getIconColor(model.fileName, model.fileIsDir)
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: model.fileName || ""
                                    font.family: Design.font.sans
                                    font.pixelSize: Design.s(11)
                                    color: listCard.isSelected ? "#ffffff" : window.colFg
                                    elide: Text.ElideMiddle
                                }

                                Text {
                                    width: Design.s(80)
                                    text: model.fileIsDir ? "Folder" : window.formatSize(model.fileSize)
                                    font.family: Design.font.mono
                                    font.pixelSize: Design.s(10)
                                    color: window.colDim
                                    horizontalAlignment: Text.AlignRight
                                }

                                Text {
                                    width: Design.s(140)
                                    text: window.formatDate(model.fileModified)
                                    font.family: Design.font.sans
                                    font.pixelSize: Design.s(10)
                                    color: window.colDim
                                    horizontalAlignment: Text.AlignRight
                                }
                            }

                            HoverHandler { id: lHover }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    window.selectedIndex = index;
                                    window.selectedPath = model.filePath;
                                }
                                onDoubleClicked: window.openItem(model.filePath, model.fileIsDir)
                            }
                        }
                    }

                    // 3. GALLERY VIEW
                    GridView {
                        id: galView
                        reuseItems: true
                        anchors.fill: parent
                        anchors.margins: Design.s(14)
                        cellWidth: Design.s(180)
                        cellHeight: Design.s(160)
                        clip: true
                        visible: window.viewMode === "gallery"
                        model: folderModel
                        cacheBuffer: 200

                        delegate: Rectangle {
                            id: galCard
                            width: Design.s(170)
                            height: Design.s(150)
                            radius: Design.s(8)
                            color: isSelected ? Design.tint(Design.accent, 0.22) : (gHover.containsMouse ? window.colCardHover : window.colSunken)
                            border.color: isSelected ? window.colBlue : window.colBorderSubtle
                            border.width: 1

                            readonly property bool isSelected: window.selectedIndex === index

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: Design.s(8)
                                spacing: Design.s(6)

                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    radius: Design.s(6)
                                    color: window.colSunken
                                    clip: true

                                    Image {
                                        id: galleryThumb
                                        anchors.fill: parent
                                        source: window.isImageFile(model.fileName) ? model.filePath : ""
                                        fillMode: Image.PreserveAspectCrop
                                        visible: status === Image.Ready
                                        asynchronous: true
                                        cache: true
                                        // Low resolution for gallery view
                                        sourceSize: Qt.size(120, 90)
                                    }

                                    Text {
                                        anchors.centerIn: parent
                                        text: window.getIconGlyph(model.fileName, model.fileIsDir)
                                        font.family: Design.font.mono
                                        font.pixelSize: Design.s(38)
                                        color: window.getIconColor(model.fileName, model.fileIsDir)
                                        visible: !galleryThumb.visible
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: model.fileName || ""
                                    font.family: Design.font.sans
                                    font.pixelSize: Design.s(11)
                                    font.bold: galCard.isSelected
                                    color: galCard.isSelected ? "#ffffff" : window.colFg
                                    horizontalAlignment: Text.AlignHCenter
                                    elide: Text.ElideMiddle
                                }
                            }

                            HoverHandler { id: gHover }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    window.selectedIndex = index;
                                    window.selectedPath = model.filePath;
                                }
                                onDoubleClicked: window.openItem(model.filePath, model.fileIsDir)
                            }
                        }
                    }
                }

                // ── Bottom Status Bar (30px) ─────────────────────────────────
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Design.s(30)
                    color: window.colDark

                    // Subtle top divider
                    Rectangle {
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: 1
                        color: window.colBorderSubtle
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Design.s(12)
                        anchors.rightMargin: Design.s(12)

                        Text {
                            text: folderModel.count + " items" + (window.selectedPath ? ("  •  Selected: " + window.selectedPath.split('/').pop()) : "")
                            font.family: Design.font.sans
                            font.pixelSize: Design.s(10)
                            color: window.colDim
                            Layout.fillWidth: true
                        }

                        Row {
                            spacing: Design.s(8)
                            Text { text: "Space QuickLook"; font.family: Design.font.mono; font.pixelSize: Design.s(9); color: window.colDim }
                            Text { text: "•"; font.pixelSize: Design.s(8); color: window.colBorderSubtle }
                            Text { text: "Ctrl+T Terminal"; font.family: Design.font.mono; font.pixelSize: Design.s(9); color: window.colDim }
                            Text { text: "•"; font.pixelSize: Design.s(8); color: window.colBorderSubtle }
                            Text { text: "Ctrl+H Hidden"; font.family: Design.font.mono; font.pixelSize: Design.s(9); color: window.colDim }
                        }
                    }
                }
            }
        }
    }

    component NavIconBtn: Rectangle {
        id: nb
        property string icon: ""
        property bool enabled: true
        signal clicked()

        width: Design.s(24); height: Design.s(24); radius: Design.s(4)
        color: nbArea.containsMouse && nb.enabled ? Design.tint(Design.text, 0.10) : "transparent"
        opacity: nb.enabled ? 1.0 : 0.35

        Text {
            anchors.centerIn: parent
            text: nb.icon
            font.family: Design.font.mono
            font.pixelSize: Design.s(11)
            color: window.colFg
        }

        MouseArea {
            id: nbArea
            anchors.fill: parent
            enabled: nb.enabled
            hoverEnabled: true
            cursorShape: nb.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: nb.clicked()
        }
    }

    component ViewSegmentBtn: Rectangle {
        id: vsb
        property string icon: ""
        property bool active: false
        signal clicked()

        width: Design.s(26); height: Design.s(24); radius: Design.s(4)
        color: vsb.active ? window.colBlue : (vsbArea.containsMouse ? Design.tint(Design.text, 0.08) : "transparent")

        Text {
            anchors.centerIn: parent
            text: vsb.icon
            font.family: Design.font.mono
            font.pixelSize: Design.s(11)
            color: vsb.active ? Design.accentText : (vsbArea.containsMouse ? "#ffffff" : window.colDim)
        }

        MouseArea {
            id: vsbArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: vsb.clicked()
        }
    }
}
