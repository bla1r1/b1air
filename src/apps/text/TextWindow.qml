import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Controls
import Ui

Window {
    id: window

    // Colours for every stock control in the window — tooltips, scroll bars,
    // combo boxes, text fields — from the desktop palette. Left to the Basic
    // style they were its own: a pale-yellow tooltip, light-grey bars.
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
    title: (TextBackend.isModified ? "● " : "") + "Text Editor — " + TextBackend.fileName
    width: Design.s(900)
    height: Design.s(620)
    minimumWidth: Design.s(680)
    minimumHeight: Design.s(420)
    visible: true
    color: "transparent"

    // This copy — the one main.cpp actually loads — quit outright, so closing
    // b1air-text with unsaved changes threw them away without a word. The
    // confirmation below already existed in src/apps/text/TextWindow.qml, a
    // copy nothing loads, so the protection was written and then never shipped.
    onClosing: function(close) {
        if (TextBackend.isModified) {
            close.accepted = false;
            window.closeAfterSave = true;
            unsavedDialog.open();
        } else {
            Qt.quit();
        }
    }

    property bool closeAfterSave: false
    property bool wordWrapEnabled: false
    property int currentLine: 1
    property int currentCol: 1
    // Offset of the first character of every line, for the gutter.
    property var lineStarts: [0]

    function recomputeLineStarts() {
        const t = editorArea.text;
        const starts = [0];
        let i = -1;
        while ((i = t.indexOf("\n", i + 1)) !== -1) starts.push(i + 1);
        window.lineStarts = starts;
    }

    function newFileWithConfirmation() {
        window.closeAfterSave = false;
        if (TextBackend.isModified) unsavedDialog.open();
        else TextBackend.newFile();
    }

    // What to do once a save started by the unsaved-changes dialog lands:
    // "quit", "new", or "" for a plain save. Only after it succeeds — the
    // dialog's Save used to quit straight away, so a save that failed (an
    // Untitled file has nowhere to go) threw the text away anyway.
    property string afterSave: ""

    function save() {
        if (!TextBackend.filePath) {
            saveAsDialog.open();
            return;
        }
        TextBackend.saveFile();
    }

    Connections {
        target: TextBackend
        function onSaved(ok) {
            if (!ok) { window.afterSave = ""; return; }
            const next = window.afterSave;
            window.afterSave = "";
            if (next === "quit") Qt.quit();
            else if (next === "new") TextBackend.newFile();
        }
    }

    function calculateCursorPos() {
        let textBefore = editorArea.text.substring(0, editorArea.cursorPosition);
        let lines = textBefore.split("\n");
        currentLine = lines.length;
        currentCol = lines[lines.length - 1].length + 1;
    }

    // ── Global Shortcuts ─────────────────────────────────────────────────────
    Shortcut { sequence: "Ctrl+S"; onActivated: window.save() }
    Shortcut { sequence: "Ctrl+Shift+S"; onActivated: saveAsDialog.open() }
    Shortcut { sequence: "Ctrl+N"; onActivated: window.newFileWithConfirmation() }
    Shortcut { sequence: "Escape"; onActivated: window.close() }

    Rectangle {
        id: windowFrame
        anchors.fill: parent
        // No corners or outline of our own: sway draws both, and only sway
        // knows which window has focus. The app drew a fixed 1px line and sway
        // was told `border none` for it, so ours were the only windows on the
        // desktop that did not light up when focused. SwayFX's corner_radius
        // rounds the surface; a 14px radius inside its 10px one left slivers.
        radius: 0
        color: Design.base
        clip: true

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

        // ═════════════════════════════════════════════════════════════════════
        // TOP HEADER BAR (COMPACT TILED TOOLBAR)
        // ═════════════════════════════════════════════════════════════════════
        AppToolbar {
            Layout.fillWidth: true

            BarGroup {
                BarButton { glyph: "\u{f0415}"; label: "New"; tip: "New file (Ctrl+N)"; onClicked: window.newFileWithConfirmation() }
                BarButton { glyph: "\u{f0193}"; label: "Save"; primary: TextBackend.isModified; tip: "Save (Ctrl+S) · Save as (Ctrl+Shift+S)"; onClicked: window.save() }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                Label {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: TextBackend.fileName + (TextBackend.isModified ? "  •" : "")
                    weight: Design.weight.semibold
                    elide: Text.ElideMiddle
                }
                Label {
                    Layout.fillWidth: true
                    visible: text !== ""
                    horizontalAlignment: Text.AlignHCenter
                    text: TextBackend.filePath ? TextBackend.filePath.replace(/\/[^\/]*$/, "") : ""
                    role: "caption"
                    color: Design.textFaint
                    elide: Text.ElideMiddle
                }
            }
            BarGroup {
                BarButton { glyph: "\u{f05b6}"; tip: "Wrap long lines"; checked: window.wordWrapEnabled; onClicked: window.wordWrapEnabled = !window.wordWrapEnabled }
            }
        }

        // ═════════════════════════════════════════════════════════════════════
        // MAIN TEXT EDITOR WITH LINE NUMBERS
        // ═════════════════════════════════════════════════════════════════════
        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            color: Design.base

            RowLayout {
                anchors.fill: parent
                spacing: 0

                // ── Line Numbers Gutter ──────────────────────────────────────
                Rectangle {
                    Layout.fillHeight: true
                    Layout.preferredWidth: Design.s(52)
                    color: Design.crust

                    ListView {
                        id: lineNumbersView
                        anchors.fill: parent
                        anchors.topMargin: editorArea.topPadding
                        anchors.bottomMargin: editorArea.bottomPadding
                        clip: true
                        interactive: false
                        contentY: editorFlickable.contentY

                        // One number per logical line, each as tall as that
                        // line is in the editor and placed where it is. They
                        // had a fixed 20px row against the editor's ~16px
                        // line, so the numbers drifted further from their
                        // lines the further down the file one read.
                        model: window.lineStarts.length

                        delegate: Item {
                            required property int index
                            // Re-evaluated when the layout changes: width
                            // (wrapping) and contentHeight (any edit).
                            readonly property real _layout: editorArea.contentHeight + editorArea.width
                            readonly property rect _here: (_layout, editorArea.positionToRectangle(window.lineStarts[index] || 0))
                            readonly property real _next: index + 1 < window.lineStarts.length
                                ? (_layout, editorArea.positionToRectangle(window.lineStarts[index + 1]).y)
                                : _here.y + _here.height
                            width: lineNumbersView.width - Design.s(14)
                            height: Math.max(1, _next - _here.y)

                            Text {
                                width: parent.width
                                height: parent._here.height
                                text: String(index + 1)
                                font.family: Design.font.mono
                                font.pixelSize: Design.s(Design.font.body)
                                color: (index + 1 === window.currentLine) ? Design.accent : Design.textFaint
                                horizontalAlignment: Text.AlignRight
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                    }

                    // Gutter Right Divider
                    Rectangle {
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: 1
                        color: Design.glassBorder
                    }
                }

                // ── Editor TextArea ──────────────────────────────────────────
                Flickable {
                    id: editorFlickable
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    ScrollBar.vertical: OverflowBar {}
                    ScrollBar.horizontal: ScrollBar { policy: window.wordWrapEnabled ? ScrollBar.AlwaysOff : ScrollBar.AsNeeded }

                    TextArea.flickable: TextArea {
                        id: editorArea
                        font.family: Design.font.mono
                        font.pixelSize: Design.s(13)
                        color: Design.text
                        selectionColor: Design.tint(Design.accent, 0.35)
                        selectedTextColor: Design.text
                        tabStopDistance: 32
                        wrapMode: window.wordWrapEnabled ? TextEdit.Wrap : TextEdit.NoWrap
                        padding: Design.s(12)
                        selectByMouse: true
                        // Typing works the moment the window appears.
                        Component.onCompleted: forceActiveFocus()

                        text: TextBackend.fileContent

                        onTextChanged: {
                            if (text !== TextBackend.fileContent) {
                                TextBackend.setFileContent(text);
                            }
                            window.recomputeLineStarts();
                            window.calculateCursorPos();
                        }

                        onCursorPositionChanged: {
                            window.calculateCursorPos();
                        }

                        Connections {
                            target: TextBackend
                            function onContentChanged() {
                                if (editorArea.text !== TextBackend.fileContent) {
                                    editorArea.text = TextBackend.fileContent;
                                }
                            }
                        }
                    }

                    // The TextArea is only as tall as its text, so a click in
                    // the empty space below the last line landed on nothing
                    // and the editor never took the caret. This takes it there
                    // and puts the caret at the end.
                    MouseArea {
                        x: 0
                        y: editorArea.height
                        width: editorFlickable.width
                        height: Math.max(0, editorFlickable.height - editorArea.height)
                        cursorShape: Qt.IBeamCursor
                        onClicked: {
                            editorArea.forceActiveFocus();
                            editorArea.cursorPosition = editorArea.length;
                        }
                    }

                    // Something to read on an empty document.
                    //
                    // Every other app in this suite says what to do when it
                    // has nothing open — the image viewer names the command,
                    // the git client says to pick a repository. This one drew
                    // a black field and the number 1 in the gutter, which is
                    // the same thing a broken window looks like.
                    ColumnLayout {
                        // Positioned against the Flickable's viewport rather
                        // than anchored to `parent`: assigning TextArea.flickable
                        // makes this a child of the content item, whose origin
                        // is the top-left of the *document*, so centring on it
                        // put the message in the gutter.
                        x: (editorFlickable.width - implicitWidth) / 2
                        y: (editorFlickable.height - implicitHeight) / 2
                        spacing: Design.s(Design.space.sm)
                        visible: editorArea.text.length === 0
                                 && !TextBackend.filePath
                                 && !editorArea.activeFocus

                        Icon {
                            Layout.alignment: Qt.AlignHCenter
                            text: "\u{f0219}"
                            role: "display"
                            color: Design.textFaint
                        }

                        Label {
                            Layout.alignment: Qt.AlignHCenter
                            text: "Empty document"
                            weight: Design.weight.semibold
                            dim: true
                        }

                        Label {
                            Layout.alignment: Qt.AlignHCenter
                            horizontalAlignment: Text.AlignHCenter
                            text: "Start typing, or open a file: b1air-text notes.md"
                            role: "caption"
                            color: Design.textFaint
                        }
                    }
                }
            }
        }

        // ═════════════════════════════════════════════════════════════════════
        // BOTTOM STATUS BAR
        // ═════════════════════════════════════════════════════════════════════
        AppStatusBar {
            Layout.fillWidth: true
            Label { text: "Ln " + window.currentLine + ", Col " + window.currentCol; role: "caption"; isMono: true; dim: true }
            Label { text: TextBackend.lineCount + " lines  ·  " + TextBackend.wordCount + " words"; role: "caption"; dim: true }
            // A save or open that failed says so, where the eye already is.
            Label {
                Layout.fillWidth: true
                text: TextBackend.lastError
                elide: Text.ElideRight
                role: "caption"
                color: Design.danger
            }
            Label { text: TextBackend.fileType + "  ·  UTF-8"; role: "caption"; color: Design.textFaint }
        }
    }
}

    AppDialog {
        id: unsavedDialog
        title: "Unsaved changes"
        message: "Save changes before starting a new file or closing the editor?"
        standardButtons: Dialog.Cancel | Dialog.Discard | Dialog.Save
        onAccepted: {
            window.afterSave = window.closeAfterSave ? "quit" : "new";
            window.save();
        }
        onDiscarded: {
            unsavedDialog.close();
            if (window.closeAfterSave) Qt.quit();
            else TextBackend.newFile();
        }
    }

    AppDialog {
        id: saveAsDialog
        title: "Save as"
        standardButtons: Dialog.Cancel | Dialog.Save
        onOpened: {
            savePathField.text = TextBackend.suggestedPath;
            savePathField.focusInput();
        }
        onAccepted: TextBackend.saveFile(savePathField.text.trim())
        onRejected: window.afterSave = ""

        contentItem: ColumnLayout {
            implicitWidth: Design.s(420)
            spacing: Design.s(Design.space.sm)

            Label {
                text: "Path"
                role: "caption"
                dim: true
            }
            Field {
                id: savePathField
                Layout.fillWidth: true
                onAccepted: saveAsDialog.accept()
            }
        }
    }
}
