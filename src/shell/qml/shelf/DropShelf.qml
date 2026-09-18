import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import "../Ui"

// =============================================================================
// DropShelf Floating Batch File Staging Tray (Super + Shift + D)
// =============================================================================

PopupShell {
    id: root

    padding: Design.s(Design.space.md)

    ListModel {
        id: stagedFiles
    }

    function addFile(path) {
        if (!path) return;
        path = path.replace(/^file:\/\//, "").trim();
        for (let i = 0; i < stagedFiles.count; i++) {
            if (stagedFiles.get(i).path === path) return;
        }
        const name = path.split("/").pop();
        stagedFiles.append({ path: path, name: name });
    }

    function copyAllPaths() {
        let paths = [];
        for (let i = 0; i < stagedFiles.count; i++) {
            paths.push(stagedFiles.get(i).path);
        }
        if (paths.length > 0) {
            Quickshell.execDetached(["wl-copy", paths.join("\n")]);
            Quickshell.execDetached(["notify-send", "-a", "DropShelf", "Paths Copied", paths.length + " file paths copied to clipboard"]);
        }
    }

    focus: true
    Keys.onEscapePressed: root.close()

    ColumnLayout {
        anchors.fill: parent
        spacing: Design.s(Design.space.md)

        // ── Header ────────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.sm)

            Icon {
                text: "\u{f07c}" // folder-open / stash
                role: "subhead"
                color: Design.accent
            }

            Label {
                text: "File Staging Shelf"
                role: "subhead"
                weight: Design.weight.bold
            }

            Badge {
                text: stagedFiles.count.toString()
                tone: Design.accent
            }

            Item { Layout.fillWidth: true }

            ActionButton {
                visible: stagedFiles.count > 0
                icon: "\u{f0c5}"
                label: "Copy Paths"
                onActivated: root.copyAllPaths()
            }

            ActionButton {
                visible: stagedFiles.count > 0
                icon: "\u{f0156}"
                label: "Clear All"
                onActivated: stagedFiles.clear()
            }
        }

        // ── Drop Zone / File List ──────────────────────────────────────────────
        Rectangle {
            id: dropZone
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Design.s(Design.radius.card)
            color: dropArea.containsDrag ? Design.tint(Design.accent, 0.15) : Design.sunken
            border.color: dropArea.containsDrag ? Design.accent : Design.glassBorder
            border.width: 1
            clip: true

            DropArea {
                id: dropArea
                anchors.fill: parent
                onDropped: drop => {
                    if (drop.hasUrls) {
                        for (let url of drop.urls) {
                            root.addFile(url.toString());
                        }
                    } else if (drop.hasText) {
                        const lines = drop.text.split("\n");
                        for (let l of lines) {
                            if (l.trim()) root.addFile(l.trim());
                        }
                    }
                }
            }

            ListView {
                id: fileList
                anchors.fill: parent
                anchors.margins: Design.s(Design.space.xs)
                spacing: Design.s(Design.space.xs)
                model: stagedFiles
                clip: true

                delegate: Rectangle {
                    id: fileCard
                    required property string path
                    required property string name
                    required property int index

                    width: ListView.view ? ListView.view.width : 0
                    height: Design.s(44)
                    radius: Design.s(Design.radius.ctl)
                    color: fileHover.containsMouse ? Design.raised : Design.glassCard
                    border.color: fileHover.containsMouse ? Design.accent : Design.glassBorder
                    border.width: 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Design.s(Design.space.sm)
                        anchors.rightMargin: Design.s(Design.space.sm)
                        spacing: Design.s(Design.space.sm)

                        Icon {
                            text: "\u{f15b}" // file icon
                            role: "body"
                            color: Design.accent
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1

                            Label {
                                text: fileCard.name
                                role: "body"
                                weight: Design.weight.bold
                                elide: Text.ElideRight
                                Layout.fillWidth: true
                            }

                            Label {
                                text: fileCard.path
                                role: "caption"
                                dim: true
                                elide: Text.ElideMiddle
                                Layout.fillWidth: true
                            }
                        }

                        IconButton {
                            icon: "\u{f08e}" // open in default app
                            role: "caption"
                            hoverTone: Design.accent
                            onClicked: Quickshell.execDetached(["xdg-open", fileCard.path])
                        }

                        IconButton {
                            icon: "\u{f00d}" // remove from shelf
                            role: "caption"
                            hoverTone: Design.danger
                            onClicked: stagedFiles.remove(fileCard.index)
                        }
                    }

                    // Hover only. It took the left button too, by default, and
                    // lying over the card it swallowed every click on the open
                    // and remove buttons.
                    MouseArea {
                        id: fileHover
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.NoButton
                    }
                }
            }

            // Empty Placeholder
            ColumnLayout {
                anchors.centerIn: parent
                visible: stagedFiles.count === 0
                spacing: Design.s(Design.space.sm)

                Icon {
                    text: "\u{f0ee}" // cloud-upload
                    role: "title"
                    color: Design.textDim
                    Layout.alignment: Qt.AlignHCenter
                }

                Label {
                    text: "Drag files here to stage"
                    role: "body"
                    weight: Design.weight.bold
                    dim: true
                    Layout.alignment: Qt.AlignHCenter
                }

                Label {
                    text: "Stage documents, images, or code before sending or batch moving"
                    role: "caption"
                    dim: true
                    Layout.alignment: Qt.AlignHCenter
                }
            }
        }
    }
}
