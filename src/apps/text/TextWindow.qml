import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Controls
import Ui

Window {
    id: window
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

    function newFileWithConfirmation() {
        window.closeAfterSave = false;
        if (TextBackend.isModified) unsavedDialog.open();
        else TextBackend.newFile();
    }

    function calculateCursorPos() {
        let textBefore = editorArea.text.substring(0, editorArea.cursorPosition);
        let lines = textBefore.split("\n");
        currentLine = lines.length;
        currentCol = lines[lines.length - 1].length + 1;
    }

    // ── Global Shortcuts ─────────────────────────────────────────────────────
    Shortcut { sequence: "Ctrl+S"; onActivated: TextBackend.saveFile() }
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
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: Design.s(36)
            color: Design.crust
            border.color: Design.glassBorder
            border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Design.s(Design.space.sm)
                anchors.rightMargin: Design.s(Design.space.sm)
                spacing: Design.s(Design.space.xs)

                // File Icon
                Rectangle {
                    width: Design.s(22)
                    height: Design.s(22)
                    radius: Design.s(Design.radius.sm)
                    color: Design.tint(Design.accent, 0.18)

                    Text {
                        anchors.centerIn: parent
                        text: "\u{f0f6}" // file-text
                        color: Design.accent
                        font.family: Design.font.icon
                        font.pixelSize: Design.s(12)
                    }
                }

                // File Name & Path
                RowLayout {
                    spacing: Design.s(6)

                    Text {
                        text: TextBackend.fileName
                        font.family: Design.font.sans
                        font.weight: Design.weight.bold
                        font.pixelSize: Design.s(12)
                        color: Design.text
                    }

                    Rectangle {
                        width: Design.s(6)
                        height: Design.s(6)
                        radius: 3
                        color: Design.peach
                        visible: TextBackend.isModified
                    }

                    Text {
                        text: TextBackend.filePath ? ("— " + TextBackend.filePath) : ""
                        font.family: Design.font.sans
                        font.pixelSize: Design.s(11)
                        color: Design.textDim
                        elide: Text.ElideMiddle
                        Layout.maximumWidth: Design.s(320)
                    }
                }

                Item { Layout.fillWidth: true }

                // Actions: New, Save, Word Wrap
                RowLayout {
                    spacing: Design.s(4)

                    IconButton {
                        icon: "\u{f067}" // plus
                        bordered: true
                        onClicked: window.newFileWithConfirmation()
                    }

                    IconButton {
                        icon: "\u{f0c7}" // save
                        bordered: true
                        hoverTone: Design.teal
                        fill: TextBackend.isModified ? Design.tint(Design.accent, 0.25) : "transparent"
                        tone: TextBackend.isModified ? Design.accent : Design.textDim
                        onClicked: TextBackend.saveFile()
                    }

                    Rectangle {
                        implicitWidth: wrapBtnText.implicitWidth + Design.s(12)
                        implicitHeight: Design.s(24)
                        radius: Design.s(Design.radius.ctl)
                        color: window.wordWrapEnabled ? Design.tint(Design.accent, 0.22) : Design.sunken
                        border.color: Design.glassBorder
                        border.width: 1

                        Text {
                            id: wrapBtnText
                            anchors.centerIn: parent
                            text: "Wrap"
                            font.family: Design.font.sans
                            font.weight: Design.weight.medium
                            font.pixelSize: Design.s(10)
                            color: window.wordWrapEnabled ? Design.accent : Design.textDim
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: window.wordWrapEnabled = !window.wordWrapEnabled
                        }
                    }
                }
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
                        anchors.topMargin: Design.s(12)
                        anchors.bottomMargin: Design.s(12)
                        clip: true
                        interactive: false
                        contentY: editorFlickable.contentY

                        model: TextBackend.lineCount

                        delegate: Text {
                            width: lineNumbersView.width - Design.s(14)
                            height: Design.s(20)
                            text: String(index + 1)
                            font.family: Design.font.mono
                            font.pixelSize: Design.s(12)
                            color: (index + 1 === window.currentLine) ? Design.accent : Design.textFaint
                            horizontalAlignment: Text.AlignRight
                            verticalAlignment: Text.AlignVCenter
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

                        text: TextBackend.fileContent

                        onTextChanged: {
                            if (text !== TextBackend.fileContent) {
                                TextBackend.setFileContent(text);
                            }
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
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: Design.s(26)
            color: Design.crust
            border.color: Design.glassBorder
            border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Design.s(Design.space.md)
                anchors.rightMargin: Design.s(Design.space.md)
                spacing: Design.s(Design.space.md)

                Text {
                    text: "Ln " + window.currentLine + ", Col " + window.currentCol
                    font.family: Design.font.mono
                    font.pixelSize: Design.s(10)
                    color: Design.textDim
                }

                Text {
                    text: TextBackend.lineCount + " lines  •  " + TextBackend.wordCount + " words"
                    font.family: Design.font.sans
                    font.pixelSize: Design.s(10)
                    color: Design.textDim
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    implicitWidth: ftText.implicitWidth + Design.s(12)
                    implicitHeight: Design.s(18)
                    radius: Design.s(9)
                    color: Design.tint(Design.teal, 0.18)

                    Text {
                        id: ftText
                        anchors.centerIn: parent
                        text: TextBackend.fileType
                        font.family: Design.font.sans
                        font.weight: Design.weight.bold
                        font.pixelSize: Design.s(9)
                        color: Design.teal
                    }
                }

                Text {
                    text: "UTF-8"
                    font.family: Design.font.sans
                    font.pixelSize: Design.s(10)
                    color: Design.textDim
                }
            }
        }
    }
}

    Dialog {
        id: unsavedDialog
        title: "Unsaved changes"
        modal: true
        anchors.centerIn: parent
        standardButtons: Dialog.Cancel | Dialog.Discard | Dialog.Save
        onAccepted: {
            TextBackend.saveFile();
            if (window.closeAfterSave) Qt.quit();
            else TextBackend.newFile();
        }
        onDiscarded: {
            if (window.closeAfterSave) Qt.quit();
            else TextBackend.newFile();
        }
        // Same shape as b1air-notes' delete dialog: a wrapping label and the
        // Dialog would each size from the other, and Text.implicitWidth is
        // read-only, so the explicit size lives on a wrapping Item.
        contentItem: Item {
            implicitWidth: Design.s(340)
            implicitHeight: saveMsg.implicitHeight + Design.s(36)

            Label {
                id: saveMsg
                anchors.fill: parent
                anchors.margins: Design.s(18)
                text: "Save changes before starting a new file or closing the editor?"
                wrapMode: Text.WordWrap
            }
        }
    }

}
