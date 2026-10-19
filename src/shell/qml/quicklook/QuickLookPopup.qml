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
    // "" while there is text to show, else what AppState says instead:
    // "empty" (an empty file) or "error" (an archive that could not be listed).
    property string previewState: ""

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
        root.previewState = "";

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
    // not read it. Saying so beats leaving the loading state on screen for
    // good, which is indistinguishable from a hang. It is said as a state, not
    // as the file's text: a sentence in the monospace pane reads as content.
    function _finish(text, emptyState) {
        if (text && text.length > 0)
            root.fileText = text;
        else
            root.previewState = emptyState;
    }

    Process {
        id: textLoader
        stdout: StdioCollector {
            onStreamFinished: root._finish(this.text, "empty")
        }
    }

    Process {
        id: archiveLoader
        stdout: StdioCollector {
            onStreamFinished: root._finish(this.text, "error")
        }
    }

    Process {
        id: pdfLoader
        stdout: StdioCollector {
            // pdfinfo printing nothing still leaves a PDF worth naming.
            onStreamFinished: root.fileText = this.text && this.text.length > 0 ? this.text : I18n.tr("PDF Document")
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
                    weight: Design.weight.semibold
                }
                Label {
                    text: root.filePath
                    role: "caption"
                    dim: true
                    elide: Text.ElideMiddle
                    Layout.preferredWidth: Design.s(Design.width.menuMax)
                }
            }

            Item { Layout.fillWidth: true }

            // Both actions operate on root.filePath, so with no file open one
            // copied an empty string to the clipboard and the other asked
            // xdg-open to open "". Neither reported anything; they simply did
            // nothing while looking available.
            Button {
                enabled: root.filePath !== ""
                icon: "\u{f0c5}"
                label: I18n.tr("Copy Path")
                onActivated: {
                    Quickshell.execDetached(["b1air-clip", "copy", "--", root.filePath]);
                    Osd.show("edit-copy", I18n.tr("Path copied"), root.filePath);
                }
            }

            Button {
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
        Surface {
            kind: "well"
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Design.s(Design.radius.card)
            border.width: 1
            clip: true

            // 1. Image Preview
            Picture {
                id: image
                visible: root.fileType === "image" && status !== Image.Error
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
            Scroller {
                visible: root.fileType !== "image" && root.filePath !== "" && root.previewState === ""
                anchors.fill: parent
                anchors.margins: Design.s(Design.space.sm)
                clip: true

                TextBox {
                    text: root.fileText
                    readOnly: true
                    selectByMouse: true
                    font.family: Design.font.mono
                    font.pixelSize: Design.s(Design.font.footnote)
                    color: Design.text
                    background: null
                    wrapMode: TextEdit.WrapAnywhere
                }
            }

            // 4. Still reading, nothing in the file, or nothing readable.
            AppState {
                anchors.fill: parent
                readonly property bool imageFailed: root.fileType === "image" && image.status === Image.Error
                readonly property bool reading: root.fileText === ""
                    && (textLoader.running || archiveLoader.running || pdfLoader.running)
                mode: root.filePath === "" ? ""
                    : imageFailed ? "error"
                    : root.previewState !== "" ? root.previewState
                    : reading ? "loading" : ""
                icon: mode === "empty" ? "\u{f0214}" : ""
                title: mode === "loading" ? I18n.tr("Loading preview…")
                    : imageFailed ? I18n.tr("Can't preview this image")
                    : root.previewState === "error" ? I18n.tr("Can't read this archive")
                    : I18n.tr("This file is empty")
                hint: imageFailed ? I18n.tr("The file may be damaged or in an unsupported format.") : ""
            }
        }
    }
}
