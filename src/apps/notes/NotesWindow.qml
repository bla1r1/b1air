import QtQuick
import QtQuick.Controls
import QtQuick.Window
import QtQuick.Layouts
import Ui

ApplicationWindow {
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
    title: NotesBackend.currentNoteId ? "Notes — " + NotesBackend.currentTitle : "Notes"
    width: Design.s(960)
    height: Design.s(620)
    minimumWidth: 460
    minimumHeight: 360
    visible: true
    color: "transparent"
    flags: Qt.Window

    // A second, hand-rolled Tokyo Night palette used to live here alongside the
    // Catppuccin one in Ui/Design.qml, so this window never followed the theme.
    // The names stay — they are used throughout the file — but each now resolves
    // to a design-system role, exactly as FilesWindow.qml was already migrated.
    readonly property color colBg: Design.surface
    readonly property color colDark: Design.ground
    readonly property color colSidebar: Design.sunken
    readonly property color colSunken: Design.sunken
    readonly property color colBorder: Design.glassBorder
    readonly property color colBorderSubtle: Design.line
    readonly property color colBlue: Design.accent
    readonly property color colPurple: Design.mauve
    readonly property color colCyan: Design.sapphire
    readonly property color colGreen: Design.ok
    readonly property color colOrange: Design.warn
    readonly property color colRed: Design.danger
    readonly property color colFg: Design.text
    readonly property color colDim: Design.textDim

    property string searchQuery: ""
    property bool showPreview: window.width > 800

    // b1air-git and b1air-notes were the only two apps in the suite with no
    // key bindings at all — every sibling (files, monitor, settings, text,
    // view) closes on Escape, and b1air-text already had Ctrl+S / Ctrl+N for
    // exactly these actions.
    Shortcut {
        sequence: "Escape"
        onActivated: window.close()
    }

    Shortcut {
        sequence: "Ctrl+N"
        onActivated: window.newNote()
    }

    // Editing is auto-saved on a 500 ms debounce; Ctrl+S is the "now, please"
    // that every editor has trained people to expect.
    Shortcut {
        sequence: "Ctrl+S"
        onActivated: {
            autoSaveTimer.stop();
            NotesBackend.saveCurrentNote(titleInput.text, editorArea.text, tagInput.text);
        }
    }

    Shortcut {
        sequence: "Ctrl+P"
        onActivated: window.showPreview = !window.showPreview
    }

    // The last half-second of typing waits on the debounce below; anything
    // that leaves the note — another note, a new one, closing the window —
    // writes it first. Switching notes or pressing Escape inside that half
    // second used to drop it.
    function flushSave() {
        if (autoSaveTimer.running) {
            autoSaveTimer.stop();
            NotesBackend.saveCurrentNote(titleInput.text, editorArea.text, "");
        }
    }

    function newNote() {
        flushSave();
        NotesBackend.createNote("Untitled");
        titleInput.forceActiveFocus();
        titleInput.selectAll();
    }

    onClosing: flushSave()

    // Auto-save debounce timer
    Timer {
        id: autoSaveTimer
        interval: 500
        repeat: false
        onTriggered: {
            NotesBackend.saveCurrentNote(titleInput.text, editorArea.text, tagInput.text);
        }
    }

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

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // ── Headerbar (40px) ─────────────────────────────────────────────
            AppToolbar {
                Layout.fillWidth: true

                BarGroup {
                    BarButton { glyph: "\u{f0415}"; label: "New note"; tip: "Ctrl+N"; onClicked: window.newNote() }
                    // Left: re-read the vault (or choose one, the first time).
                    // Right-click: choose a different vault.
                    BarButton {
                        glyph: "\u{f0219}"
                        label: NotesBackend.obsidianVaultPath ? "Obsidian" : "Connect Obsidian…"
                        tip: NotesBackend.obsidianVaultPath
                             ? "Re-read " + NotesBackend.obsidianVaultPath + " · right-click to choose another vault"
                             : "Choose your Obsidian vault folder"
                        onClicked: { window.flushSave(); NotesBackend.syncWithObsidian(); }
                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.RightButton
                            onClicked: { window.flushSave(); NotesBackend.chooseObsidianVault(); }
                        }
                    }
                }
                Label {
                    id: syncStatusText
                    Layout.fillWidth: true
                    text: NotesBackend.syncStatus
                    elide: Text.ElideRight
                    role: "caption"
                    color: NotesBackend.syncStatus.indexOf("Error") >= 0 || NotesBackend.syncStatus.indexOf("Could not") >= 0
                           ? Design.warn : Design.textFaint
                    opacity: NotesBackend.syncStatus !== "" && NotesBackend.syncStatus !== "Ready" ? 1 : 0
                }
                Field {
                    id: searchInput
                    Layout.preferredWidth: Design.s(220)
                    placeholder: "Search notes"
                    radius: height / 2
                    onEdited: value => window.searchQuery = value.toLowerCase()
                }
                BarGroup {
                    BarButton { glyph: "\u{f0208}"; tip: "Preview (Ctrl+P)"; checked: window.showPreview; onClicked: window.showPreview = !window.showPreview }
                }
            }

            // ── Main Notes Workspace ─────────────────────────────────────────
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                RowLayout {
                    anchors.fill: parent
                    spacing: 0

                    // Left Column: Note List (240px)
                    Rectangle {
                        Layout.preferredWidth: Design.s(224)
                        Layout.fillHeight: true
                        color: window.colSidebar

                        // Right vertical divider
                        Rectangle {
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: 1
                            color: Design.line
                        }

                        ListView {
                            id: notesList
                            anchors.fill: parent
                            anchors.topMargin: Design.s(Design.space.md)
                            anchors.bottomMargin: Design.s(Design.space.md)
                            anchors.leftMargin: Design.s(Design.space.sm)
                            anchors.rightMargin: Design.s(Design.space.sm) + 1
                            clip: true
                            spacing: Design.s(2)
                            model: NotesBackend.noteList

                            delegate: Rectangle {
                                width: notesList.width
                                // A hidden delegate still occupies its height in a
                                // ListView, so filtering by `visible` alone left a
                                // 58 px hole for every note the search excluded.
                                height: matchesSearch ? Design.s(58) : 0
                                // Selected as a row of any sidebar is (Ui/SidebarItem):
                                // the accent fill, no outline.
                                radius: Design.s(Design.radius.ctl)
                                clip: true
                                color: isSelected ? Design.tint(Design.accent, 0.22) : (itemArea.containsMouse ? Design.hover : "transparent")

                                readonly property bool isSelected: NotesBackend.currentNoteId === modelData.id
                                readonly property bool matchesSearch: window.searchQuery === ""
                                    || (modelData.title || "").toLowerCase().includes(window.searchQuery)
                                    || (modelData.content || "").toLowerCase().includes(window.searchQuery)
                                visible: matchesSearch

                                ColumnLayout {
                                    anchors.fill: parent
                                    anchors.margins: Design.s(8)
                                    spacing: Design.s(3)

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text {
                                            Layout.fillWidth: true
                                            text: modelData.title || "Untitled"
                                            font.family: Design.font.sans
                                            font.pixelSize: Design.s(Design.font.body)
                                            font.bold: true
                                            color: isSelected ? Design.text : window.colFg
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            text: modelData.date || ""
                                            font.family: Design.font.sans
                                            font.pixelSize: Design.s(Design.font.caption)
                                            color: window.colDim
                                        }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: (modelData.content || "").replace(/\n/g, " ")
                                        font.family: Design.font.sans
                                        font.pixelSize: Design.s(Design.font.caption)
                                        color: window.colDim
                                        elide: Text.ElideRight
                                        maximumLineCount: 1
                                    }
                                }

                                MouseArea {
                                    id: itemArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        window.flushSave();
                                        NotesBackend.selectNote(modelData.id);
                                        titleInput.text = modelData.title || "";
                                        editorArea.text = modelData.content || "";
                                        tagInput.text = modelData.tags || "";
                                    }
                                }
                            }
                        }
                    }

                    // Middle/Right Column: Editor & Preview
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        color: window.colBg

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: Design.s(16)
                            spacing: Design.s(12)

                            // Note Title Input & Delete Button
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Design.s(10)

                                TextInput {
                                    id: titleInput
                                    Layout.fillWidth: true
                                    text: NotesBackend.currentTitle
                                    // The size and weight of a Settings page title.
                                    font.family: Design.font.sans
                                    font.pixelSize: Design.s(Design.font.display)
                                    font.weight: Design.weight.bold
                                    color: window.colFg
                                    selectByMouse: true
                                    onTextChanged: autoSaveTimer.restart()
                                }

                                BarButton {
                                    glyph: "\u{f0a7a}"
                                    danger: true
                                    tip: "Delete note"
                                    onClicked: deleteConfirm.open()
                                }
                            }

                            // Tags Bar
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Design.s(8)

                                Text { text: "󰓹"; font.family: Design.font.mono; font.pixelSize: Design.s(12); color: window.colCyan }
                                TextInput {
                                    id: tagInput
                                    Layout.fillWidth: true
                                    // The note's #hashtags, read from its text. This
                                    // was an editable field whose edits were kept
                                    // in memory only and gone after a restart.
                                    text: NotesBackend.currentTags
                                    readOnly: true
                                    font.family: Design.font.mono
                                    font.pixelSize: Design.s(Design.font.caption)
                                    color: window.colCyan
                                    selectByMouse: true

                                    Text {
                                        text: "Tags: write #tag anywhere in the note"
                                        font.family: Design.font.sans
                                        font.pixelSize: Design.s(Design.font.caption)
                                        color: window.colDim
                                        visible: !tagInput.text
                                    }
                                }
                            }

                            // Horizontal Divider
                            Rectangle { Layout.fillWidth: true; height: 1; color: window.colBorder }

                            // Editor & Preview Row
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                spacing: Design.s(14)

                                // Markdown Raw Text Editor
                                //
                                // The two panes each carried a full-strength
                                // border, so a nine-line note sat inside two
                                // heavy frames taking the whole window. They
                                // are separated by their fills and a hairline
                                // now, which is how the cards elsewhere in the
                                // suite are drawn.
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    color: window.colDark
                                    radius: Design.s(8)
                                    border.color: Design.tint(Design.line, 0.45)
                                    border.width: 1

                                    Flickable {
                                        id: editorFlick
                                        anchors.fill: parent
                                        anchors.margins: Design.s(12)
                                        contentWidth: width
                                        contentHeight: editorArea.height
                                        clip: true

                                        TextArea {
                                            id: editorArea
                                            width: parent.width
                                            // At least the pane's height, so a
                                            // click anywhere in it starts typing;
                                            // it was only as tall as its text.
                                            height: Math.max(implicitHeight + 20, editorFlick.height)
                                            text: NotesBackend.currentContent
                                            font.family: Design.font.mono
                                            font.pixelSize: Design.s(13)
                                            color: window.colFg
                                            selectionColor: Design.tint(Design.accent, 0.35)
                                            wrapMode: TextEdit.Wrap
                                            background: null
                                            selectByMouse: true
                                            onTextChanged: autoSaveTimer.restart()
                                        }
                                    }
                                }

                                // Live Markdown Rich Preview Pane (Optional)
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    color: Design.tint(Design.surface, 0.60)
                                    radius: Design.s(8)
                                    border.color: Design.tint(Design.line, 0.45)
                                    border.width: 1
                                    visible: window.showPreview

                                    Flickable {
                                        anchors.fill: parent
                                        anchors.margins: Design.s(14)
                                        contentWidth: width
                                        contentHeight: previewText.implicitHeight + 20
                                        clip: true

                                        Text {
                                            id: previewText
                                            width: parent.width
                                            // The preview follows the theme.
                                            // The renderer used to carry
                                            // fourteen Tokyo Night hex values,
                                            // so picking any other theme left
                                            // every note rendered in the old
                                            // one.
                                            text: NotesBackend.renderMarkdownToHtml(editorArea.text, {
                                                "heading1": Design.accent,
                                                "heading2": Design.mauve,
                                                "heading3": Design.sapphire,
                                                "body":     Design.text,
                                                "dim":      Design.textDim,
                                                "strong":   Design.text,
                                                "accent":   Design.accent,
                                                "done":     Design.ok,
                                                "codeBg":   Design.sunken,
                                                "codeFg":   Design.teal,
                                                "inlineBg": Design.raised,
                                                "inlineFg": Design.peach
                                            })
                                            textFormat: Text.RichText
                                            font.family: Design.font.sans
                                            font.pixelSize: Design.s(13)
                                            color: window.colFg
                                            wrapMode: Text.Wrap
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    AppDialog {
        id: deleteConfirm
        title: "Delete note?"
        message: "This note will be permanently deleted."
        acceptTone: Design.danger
        standardButtons: Dialog.Cancel | Dialog.Ok
        onAccepted: {
            autoSaveTimer.stop();
            NotesBackend.deleteNote(NotesBackend.currentNoteId);
        }
        Component.onCompleted: standardButton(Dialog.Ok).text = "Delete"
    }
}
