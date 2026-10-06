import QtQuick
import QtQuick.Layouts
import Quickshell
import B1air.Daemon
import Quickshell.Io
import "../../Ui"
import "../../Services"

// =============================================================================
// Wallpaper Gallery & Settings — Hyprland-style visual thumbnail selector.
//
// Shows source directory configuration, a "Random Wallpaper" action, and an
// interactive thumbnail grid with 1-click wallpaper application.
// =============================================================================

ColumnLayout {
    id: section

    property string wallpaperDir: Settings.wallpaperDir || (Quickshell.env("HOME") + "/.wallpapers")
    signal wallpaperDirChangedByUser(string value)
    signal accepted()

    Layout.fillWidth: true
    spacing: Design.s(Design.space.lg)

    property var wallpaperList: []
    // The category shown: "*" all of them, "" the pictures in no folder.
    property string category: "*"
    readonly property var categories: {
        const seen = [];
        for (const w of section.wallpaperList)
            if (seen.indexOf(w.category) < 0) seen.push(w.category);
        // Named folders in order, the loose pictures last.
        return seen.filter(c => c !== "").sort().concat(seen.indexOf("") >= 0 ? [""] : []);
    }
    readonly property var shownWallpapers: section.category === "*"
        ? section.wallpaperList
        : section.wallpaperList.filter(w => w.category === section.category)
    // The shipped categories in the interface language; one of your own
    // folders as it is named.
    function categoryLabel(c) {
        if (c === "") return I18n.tr("Other");
        const known = { Mountains: I18n.tr("Mountains"), Water: I18n.tr("Water"), Nature: I18n.tr("Nature"),
                        Forest: I18n.tr("Forest"), Art: I18n.tr("Art"), City: I18n.tr("City"), Sky: I18n.tr("Sky") };
        return known[c] || c;
    }
    property string activeWallpaper: ""

    // Scan wallpaper folder for images
    Process {
        id: dirScanner
        command: ["find", section.wallpaperDir.replace(/^~/, Quickshell.env("HOME")), "-maxdepth", "2", "-type", "f", "!", "-name", ".*", "-print"]
        stdout: StdioCollector {
            onStreamFinished: {
                const root = section.wallpaperDir.replace(/^~/, Quickshell.env("HOME")).replace(/\/+$/, "");
                const lines = (this.text || "").trim().split("\n")
                    .filter(l => /\.(jpe?g|png|webp)$/i.test(l.trim()));
                // The folder a picture is in, under the wallpaper folder, is
                // its category (Mountains/, Sky/…); loose at the top, none.
                section.wallpaperList = lines.sort().map(p => {
                    const rel = p.startsWith(root + "/") ? p.slice(root.length + 1) : p.split("/").pop();
                    const parts = rel.split("/");
                    return {
                        path: p,
                        category: parts.length > 1 ? parts[0] : "",
                        name: parts[parts.length - 1].replace(/\.[^/.]+$/, "")
                    };
                });
            }
        }
    }

    // The connected screens, and which has a picture of its own. With more
    // than one, the gallery applies to the screen picked above it.
    property var screens: []
    property string target: ""          // "" = every screen
    Process {
        id: screenReader
        command: ["b1air-daemon", "wallpaper", "screens"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { section.screens = JSON.parse(this.text.trim() || "[]"); }
                catch (e) { section.screens = []; }
                if (section.target !== "" && !section.screens.some(o => o.name === section.target))
                    section.target = "";
            }
        }
    }
    Timer {
        id: screenRecheck
        interval: 1200
        onTriggered: { screenReader.running = true; workspaceReader.running = true; }
    }

    // The workspace this page is open on, and which workspaces have a picture
    // of their own. b1air-bg shows those whenever the workspace is, on any
    // screen. The target for one is "ws:<name>".
    property string workspace: ""
    property var workspaceWallpapers: ({})
    readonly property bool targetIsWorkspace: target.startsWith("ws:")
    readonly property bool targetHasOwn: targetIsWorkspace
        ? (workspaceWallpapers[target.slice(3)] || "") !== ""
        : target !== "" && screens.some(o => o.name === target && o.wallpaper !== "")
    function readFocusedWorkspace() {
        Sway.query("workspaces", list => {
            const ws = Array.isArray(list) ? list.find(w => w.focused) : null;
            section.workspace = ws ? String(ws.name) : "";
        });
    }
    Process {
        id: workspaceReader
        command: ["b1air-daemon", "wallpaper", "workspaces"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { section.workspaceWallpapers = JSON.parse(this.text.trim() || "{}"); }
                catch (e) { section.workspaceWallpapers = ({}); }
            }
        }
    }

    function unsetTarget() {
        Cmd.run(section.targetIsWorkspace
                    ? ["b1air-daemon", "wallpaper", "unset", "--workspace", section.target.slice(3)]
                    : ["b1air-daemon", "wallpaper", "unset", section.target], "Use shared wallpaper");
        screenRecheck.restart();
    }

    function scan() {
        dirScanner.running = false;
        dirScanner.running = true;
    }

    Component.onCompleted: {
        scan();
        screenReader.running = true;
        section.readFocusedWorkspace();
        workspaceReader.running = true;
    }
    onWallpaperDirChanged: scan()

    function applyWallpaper(path) {
        section.activeWallpaper = path;
        Cmd.run(section.targetIsWorkspace
                    ? ["b1air-daemon", "wallpaper", "set", path, "--workspace", section.target.slice(3)]
                    : section.target !== ""
                    ? ["b1air-daemon", "wallpaper", "set", path, section.target]
                    : ["b1air-daemon", "wallpaper", "set", path], "Set wallpaper");
        screenRecheck.restart();
    }

    function setRandom() {
        Cmd.run(["b1air-daemon", "wallpaper", "random", section.wallpaperDir.replace(/^~/, Quickshell.env("HOME"))],
                I18n.tr("Shuffle wallpaper"));
    }

    // ── 1. Wallpaper Gallery Card ────────────────────────────────────────────
    Card {
        title: I18n.tr("Wallpapers")
        subtitle: section.wallpaperList.length > 0
            ? I18n.trn("%1 wallpaper found. Click any thumbnail to apply.", "%1 wallpapers found. Click any thumbnail to apply.", section.wallpaperList.length)
            : I18n.tr("Choose and preview wallpapers from your collection")
        icon: "\u{f02ca}"
        accentColor: Design.pink

        // Actions & Source bar
        RowLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.sm)

            Pill {
                label: I18n.tr("Random Wallpaper")
                icon: "\u{f049d}"
                onClicked: section.setRandom()
            }

            Pill {
                label: I18n.tr("Refresh Gallery")
                icon: "\u{f0450}"
                onClicked: section.scan()
            }

            Item { Layout.fillWidth: true }
        }

        // Where a click applies: everywhere, one screen, or the workspace this
        // page is open on. "Everywhere" also clears every screen's and
        // workspace's own picture, which is what it says.
        Flow {
            visible: section.screens.length > 1 || section.workspace !== ""
            Layout.fillWidth: true
            spacing: Design.s(Design.space.xs)
            Pill {
                label: section.screens.length > 1 ? I18n.tr("All screens") : I18n.tr("Everywhere")
                icon: "\u{f0379}"
                active: section.target === ""
                onClicked: section.target = ""
            }
            Repeater {
                model: section.screens.length > 1 ? section.screens : []
                delegate: Pill {
                    required property var modelData
                    label: modelData.name + (modelData.wallpaper !== "" ? " · " + I18n.tr("own picture") : "")
                    active: section.target === modelData.name
                    onClicked: section.target = modelData.name
                }
            }
            Pill {
                visible: section.workspace !== ""
                label: I18n.tr("Workspace %1", section.workspace)
                       + ((section.workspaceWallpapers[section.workspace] || "") !== "" ? " · " + I18n.tr("own picture") : "")
                icon: "\u{f0570}"
                active: section.target === "ws:" + section.workspace
                onClicked: section.target = "ws:" + section.workspace
            }
            Pill {
                visible: section.targetHasOwn
                label: I18n.tr("Use shared picture")
                icon: "\u{f0450}"
                onClicked: section.unsetTarget()
            }
        }

        // Categories: all of them, or one folder.
        Flow {
            visible: section.categories.length > 1
            Layout.fillWidth: true
            spacing: Design.s(Design.space.xs)
            Pill {
                label: I18n.tr("All")
                active: section.category === "*"
                onClicked: section.category = "*"
            }
            Repeater {
                model: section.categories
                delegate: Pill {
                    required property string modelData
                    label: section.categoryLabel(modelData)
                    active: section.category === modelData
                    onClicked: section.category = modelData
                }
            }
        }

        // Wallpaper Grid
        GridLayout {
            visible: section.wallpaperList.length > 0
            Layout.fillWidth: true
            columns: 3
            columnSpacing: Design.s(Design.space.md)
            rowSpacing: Design.s(Design.space.md)

            Repeater {
                model: section.shownWallpapers

                Rectangle {
                    id: wallCard
                    required property var modelData
                    required property int index

                    Layout.fillWidth: true
                    Layout.preferredHeight: Design.s(120)
                    radius: Design.s(Design.radius.card)
                    color: Design.sunken
                    clip: true

                    readonly property bool isSelected: section.activeWallpaper === wallCard.modelData.path
                    border.color: wallCard.isSelected ? Design.pink : (wallMa.containsMouse ? Design.hover : Design.line)
                    border.width: wallCard.isSelected ? 2 : 1

                    Behavior on border.color { ColorAnimation { duration: Design.duration.fast } }

                    scale: wallMa.pressed ? 0.97 : (wallMa.containsMouse ? 1.02 : 1.0)
                    Behavior on scale { NumberAnimation { duration: Design.duration.fast; easing.type: Easing.OutSine } }

                    Image {
                        anchors.fill: parent
                        anchors.margins: wallCard.isSelected ? 2 : 1
                        // A cached thumbnail: the picture itself is a 4K file
                        // read whole for every card each time the page opens.
                        source: "image://thumb/" + encodeURIComponent(wallCard.modelData.path)
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: true
                        sourceSize.width: 320
                        sourceSize.height: 180
                    }

                    // Scrim gradient overlay for title legibility
                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: Design.s(32)
                        gradient: Gradient {
                            GradientStop { position: 0.0; color: "transparent" }
                            GradientStop { position: 1.0; color: "#dd000000" }
                        }

                        Label {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.margins: Design.s(Design.space.xs)
                            text: wallCard.modelData.name
                            role: "caption"
                            color: "#ffffff"
                            elide: Text.ElideRight
                        }
                    }

                    // Active Selection Badge
                    Rectangle {
                        visible: wallCard.isSelected
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: Design.s(Design.space.xs)
                        width: Design.s(22)
                        height: width
                        radius: width / 2
                        color: Design.pink

                        Icon {
                            anchors.centerIn: parent
                            text: "\u{f012c}"
                            role: "caption"
                            color: Design.accentText
                        }
                    }

                    Clickable {
                        id: wallMa
                        onClicked: section.applyWallpaper(wallCard.modelData.path)
                    }
                }
            }
        }

        EmptyState {
            Layout.fillWidth: true
            visible: section.wallpaperList.length === 0
            icon: "\u{f02ca}"
            title: I18n.tr("No wallpapers found")
            hint: I18n.tr("Check that the source folder below contains .jpg or .png images.")
        }
    }

    // ── 2. Source Folder Configuration ───────────────────────────────────────
    Card {
        title: I18n.tr("Source folder")
        subtitle: I18n.tr("The directory where wallpapers are scanned and saved")
        icon: "\u{f024b}"
        accentColor: Design.pink

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.xs)

            Label { text: I18n.tr("Folder Path"); role: "caption"; dim: true }

            Field {
                mono: true
                Layout.fillWidth: true
                text: section.wallpaperDir
                placeholder: I18n.tr("/home/you/Pictures/Wallpapers")
                onCommitted: v => {
                    section.wallpaperDir = v;
                    section.wallpaperDirChangedByUser(v);
                    Settings.set("wallpaperDir", v);
                    section.accepted();
                    section.scan();
                }
            }

            Label {
                text: I18n.tr("Full path to your wallpapers directory. Press Enter to save and refresh.")
                role: "caption"
                color: Design.textFaint
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
            }
        }
    }
}
