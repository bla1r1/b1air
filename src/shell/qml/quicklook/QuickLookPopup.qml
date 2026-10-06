import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import B1air.Daemon
import Quickshell.Io
import "../Ui"
import "../Services"

// =============================================================================
// QuickLook Instant File Preview Overlay (Space / b1air-daemon quicklook)
// =============================================================================

PopupShell {
    id: root

    padding: Design.s(Design.space.md)

    property string filePath: ""
    property string fileText: ""
    property string fileType: "text" // "image", "text", "pdf", "archive"

    readonly property string fileName: filePath ? filePath.split("/").pop() : I18n.tr("File Preview")
    readonly property string fileExt: fileName.includes(".") ? fileName.split(".").pop().toLowerCase() : ""

    function detectType() {
        const ext = root.fileExt;
        if (["png", "jpg", "jpeg", "webp", "svg", "gif", "bmp"].includes(ext)) {
            root.fileType = "image";
        } else if (["zip", "tar", "gz", "xz", "bz2", "7z"].includes(ext)) {
            root.fileType = "archive";
        } else if (ext === "pdf") {
            root.fileType = "pdf";
        } else {
            root.fileType = "text";
        }
    }

    /**
     * Read the file and show it.
     *
     * Each loader now gets its command assigned here rather than bound to
     * root.filePath. The binding and this handler both fire off the same
     * property change with no ordering between them, so `running = true` could
     * land while the command still held the previous path — an empty one on
     * the first open, which is how a freshly opened preview sat on "Loading
     * preview…" and never moved. The archive branch already did it this way;
     * the other two did not.
     *
     * Also called on completion: the popup is created with filePath among its
     * initial properties, and relying on the change signal for those is the
     * kind of thing that works until it does not.
     */
    function loadPreview() {
        textLoader.running = false;
        archiveLoader.running = false;
        pdfLoader.running = false;
        root.fileText = "";

        if (root.filePath === "")
            return;

        detectType();
        if (root.fileType === "text") {
            textLoader.command = ["head", "-n", "200", root.filePath];
            textLoader.running = true;
        } else if (root.fileType === "archive") {
            archiveLoader.command = root.filePath.toLowerCase().endsWith(".zip")
                ? ["unzip", "-l", root.filePath]
                : ["tar", "-tf", root.filePath];
            archiveLoader.running = true;
        } else if (root.fileType === "pdf") {
            pdfLoader.command = ["pdfinfo", root.filePath];
            pdfLoader.running = true;
        }
    }

    onFilePathChanged: root.loadPreview()
    Component.onCompleted: root.loadPreview()

    // An empty reply is an answer too — an empty file, or a command that could
    // not read it. Saying so beats leaving "Loading preview…" on screen for
    // good, which is indistinguishable from a hang.
    function _finish(text, emptyNote) {
        root.fileText = (text && text.length > 0) ? text : emptyNote;
    }

    Process {
        id: textLoader
        stdout: StdioCollector {
            onStreamFinished: root._finish(this.text, I18n.tr("This file is empty."))
        }
    }

    Process {
        id: archiveLoader
        stdout: StdioCollector {
            onStreamFinished: root._finish(this.text, I18n.tr("Could not list this archive."))
        }
    }

    Process {
        id: pdfLoader
        stdout: StdioCollector {
            onStreamFinished: root._finish(this.text, I18n.tr("PDF Document"))
        }
    }

    focus: true
    Keys.onEscapePressed: root.close()
    Keys.onSpacePressed: root.close()

    ColumnLayout {
        anchors.fill: parent
        spacing: Design.s(Design.space.md)

        // ── Header ────────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.sm)

            Icon {
                text: root.fileType === "image" ? "\u{f03e}" :
                      (root.fileType === "archive" ? "\u{f1c6}" :
                      (root.fileType === "pdf" ? "\u{f1c1}" : "\u{f15c}"))
                role: "subhead"
                color: Design.accent
            }

            ColumnLayout {
                spacing: 1
                Label {
                    text: root.fileName
                    role: "subhead"
                    weight: Design.weight.bold
                }
                Label {
                    text: root.filePath
                    role: "caption"
                    dim: true
                    elide: Text.ElideMiddle
                    Layout.preferredWidth: Design.s(450)
                }
            }

            Item { Layout.fillWidth: true }

            // Both actions operate on root.filePath, so with no file open one
            // copied an empty string to the clipboard and the other asked
            // xdg-open to open "". Neither reported anything; they simply did
            // nothing while looking available.
            ActionButton {
                enabled: root.filePath !== ""
                icon: "\u{f0c5}"
                label: I18n.tr("Copy Path")
                onActivated: {
                    Quickshell.execDetached(["b1air-clip", "copy", "--", root.filePath]);
                    Osd.show("edit-copy", I18n.tr("Path copied"), root.filePath);
                }
            }

            ActionButton {
                enabled: root.filePath !== ""
                icon: "\u{f08e}"
                label: I18n.tr("Open")
                onActivated: {
                    Quickshell.execDetached(["xdg-open", root.filePath]);
                    root.close();
                }
            }
        }

        // ── Preview Canvas ────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Design.s(Design.radius.card)
            color: Design.well
            border.color: Design.glassBorder
            border.width: 1
            clip: true

            // 1. Image Preview
            Image {
                visible: root.fileType === "image"
                anchors.fill: parent
                anchors.margins: Design.s(Design.space.sm)
                source: root.fileType === "image" && root.filePath ? Paths.fileUrl(root.filePath) : ""
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                smooth: true
                // Decode to preview size: a full-res photo would otherwise cost
                // hundreds of MB of pixel data for a thumbnail-sized view.
                sourceSize.width: Math.max(1, Math.round(width))
                sourceSize.height: Math.max(1, Math.round(height))
            }

            // 2. Nothing open yet.
            //
            // This used to be the placeholder text of the preview TextArea:
            // one line of monospace in the top-left corner of an otherwise
            // blank box, which reads like a file whose contents are the words
            // "Select a file to preview". Every other surface in the shell
            // states an empty view the same way, and now so does this one.
            EmptyState {
                anchors.centerIn: parent
                width: parent.width - Design.s(Design.space.xl)
                visible: root.filePath === ""
                icon: "\u{f0214}"
                title: I18n.tr("Nothing to preview")
                hint: I18n.tr("Pick a file in Files and press Space.")
            }

            // 3. Text / Code / Archive / PDF Metadata Preview
            ScrollView {
                visible: root.fileType !== "image" && root.filePath !== ""
                anchors.fill: parent
                anchors.margins: Design.s(Design.space.sm)
                clip: true

                TextArea {
                    text: root.fileText || I18n.tr("Loading preview…")
                    readOnly: true
                    selectByMouse: true
                    font.family: Design.font.mono
                    font.pixelSize: Design.s(12)
                    color: Design.text
                    background: null
                    wrapMode: TextEdit.WrapAnywhere
                }
            }
        }
    }
}
