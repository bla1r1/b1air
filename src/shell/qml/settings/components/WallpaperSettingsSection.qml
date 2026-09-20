import QtQuick
import QtQuick.Layouts
import Quickshell
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
    property string activeWallpaper: ""

    // Scan wallpaper folder for images
    Process {
        id: dirScanner
        command: ["find", section.wallpaperDir.replace(/^~/, Quickshell.env("HOME")), "-maxdepth", "2", "-type", "f", "!", "-name", ".*", "-print"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = (this.text || "").trim().split("\n").filter(l => l.trim() !== "");
                    section.wallpaperList = lines.sort().map(p => ({
                    path: p,
                    name: p.split("/").pop().replace(/\.[^/.]+$/, "")
                }));
            }
        }
    }

    // Read current wallpaper cache if present
    Process {
        id: currentWallReader
        command: ["md5sum", (Quickshell.env("XDG_CACHE_HOME") || (Quickshell.env("HOME") + "/.cache")) + "/current_wallpaper.jpg"]
        stdout: StdioCollector {
            onStreamFinished: {
                // Background scanner
            }
        }
    }

    function scan() {
        dirScanner.running = false;
        dirScanner.running = true;
    }

    Component.onCompleted: scan()
    onWallpaperDirChanged: scan()

    function applyWallpaper(path) {
        section.activeWallpaper = path;
        Cmd.run(["b1air-daemon", "wallpaper", "set", path], "Set wallpaper");
    }

    function setRandom() {
        Cmd.run(["b1air-daemon", "wallpaper", "random", section.wallpaperDir.replace(/^~/, Quickshell.env("HOME"))],
                "Shuffle wallpaper");
    }

    // ── 1. Wallpaper Gallery Card ────────────────────────────────────────────
    Card {
        title: "Wallpapers"
        subtitle: section.wallpaperList.length > 0
            ? section.wallpaperList.length + " wallpapers found. Click any thumbnail to apply."
            : "Choose and preview wallpapers from your collection"
        icon: "\u{f02ca}"
        accentColor: Design.pink

        // Actions & Source bar
        RowLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.sm)

            Pill {
                label: "Random Wallpaper"
                icon: "\u{f049d}"
                onClicked: section.setRandom()
            }

            Pill {
                label: "Refresh Gallery"
                icon: "\u{f0450}"
                onClicked: section.scan()
            }

            Item { Layout.fillWidth: true }
        }

        // Wallpaper Grid
        GridLayout {
            visible: section.wallpaperList.length > 0
            Layout.fillWidth: true
            columns: 3
            columnSpacing: Design.s(Design.space.md)
            rowSpacing: Design.s(Design.space.md)

            Repeater {
                model: section.wallpaperList

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
                        source: Paths.fileUrl(wallCard.modelData.path)
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
            title: "No wallpapers found"
            hint: "Check that the source folder below contains .jpg or .png images."
        }
    }

    // ── 2. Source Folder Configuration ───────────────────────────────────────
    Card {
        title: "Source folder"
        subtitle: "The directory where wallpapers are scanned and saved"
        icon: "\u{f024b}"
        accentColor: Design.pink

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.xs)

            Label { text: "Folder Path"; role: "caption"; dim: true }

            Field {
                mono: true
                Layout.fillWidth: true
                text: section.wallpaperDir
                placeholder: "/home/you/Pictures/Wallpapers"
                onCommitted: v => {
                    section.wallpaperDir = v;
                    section.wallpaperDirChangedByUser(v);
                    Settings.set("wallpaperDir", v);
                    section.accepted();
                    section.scan();
                }
            }

            Label {
                text: "Full path to your wallpapers directory. Press Enter to save and refresh."
                role: "caption"
                color: Design.textFaint
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
            }
        }
    }
}
