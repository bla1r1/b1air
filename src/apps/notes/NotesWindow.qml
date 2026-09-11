import QtQuick
import QtQuick.Controls
import QtQuick.Window
import QtQuick.Layouts
import Ui

ApplicationWindow {
    id: window
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
        onActivated: NotesBackend.createNote("Untitled Note")
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
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Design.s(40)
                color: window.colSidebar
                border.color: window.colBorder
                border.width: 1
                z: 10

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Design.s(12)
                    anchors.rightMargin: Design.s(12)
                    spacing: Design.s(8)

                    // App Icon & Title
                    // No app name in the toolbar. Same reasoning as the file manager:
                    // the window was opened by name and is full of notes, so "b1air-notes"
                    // beside the New Note button was a label nobody needed and a gap the
                    // buttons could have had.

                    // New Note Button
                    Rectangle {
                        width: newRow.implicitWidth + Design.s(14)
                        height: Design.s(26)
                        radius: Design.s(6)
                        color: newArea.containsMouse ? Design.tint(Design.accent, 0.25) : Design.tint(Design.raised, 0.60)
                        border.color: window.colBorder
                        border.width: 1

                        Row {
                            id: newRow
                            anchors.centerIn: parent
                            spacing: Design.s(4)
                            Text { text: "󰐕"; font.family: Design.font.mono; font.pixelSize: Design.s(12); color: window.colBlue }
                            Text { text: "New Note"; font.family: Design.font.sans; font.pixelSize: Design.s(11); font.bold: true; color: window.colFg }
                        }

                        MouseArea {
                            id: newArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: NotesBackend.createNote("Untitled Note")
                        }
                    }

                    // Obsidian Sync Pill
                    Rectangle {
                        width: obsRow.implicitWidth + Design.s(14)
                        height: Design.s(26)
                        radius: Design.s(6)
                        color: obsArea.containsMouse ? Design.tint(Design.mauve, 0.25) : Design.tint(Design.raised, 0.40)
                        border.color: window.colBorder
                        border.width: 1

                        Row {
                            id: obsRow
                            anchors.centerIn: parent
                            spacing: Design.s(4)
                            Text { text: "󰈚"; font.family: Design.font.mono; font.pixelSize: Design.s(12); color: window.colPurple }
                            Text { text: "Obsidian Sync"; font.family: Design.font.sans; font.pixelSize: Design.s(11); font.bold: true; color: window.colPurple }
                        }

                        MouseArea {
                            id: obsArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: NotesBackend.syncWithObsidian()
                        }
                    }

                    // Notion Sync Pill
                    Rectangle {
                        width: notionRow.implicitWidth + Design.s(14)
                        height: Design.s(26)
                        radius: Design.s(6)
                        color: notionArea.containsMouse ? Design.tint(Design.ok, 0.25) : Design.tint(Design.raised, 0.40)
                        border.color: window.colBorder
                        border.width: 1

                        Row {
                            id: notionRow
                            anchors.centerIn: parent
                            spacing: Design.s(4)
                            Text { text: "󰍉"; font.family: Design.font.mono; font.pixelSize: Design.s(12); color: window.colGreen }
                            Text { text: "Notion Sync"; font.family: Design.font.sans; font.pixelSize: Design.s(11); font.bold: true; color: window.colGreen }
                        }

                        MouseArea {
                            id: notionArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: NotesBackend.syncWithNotion()
                        }
                    }

                    // What the two buttons above did. Both set a status the
                    // window never showed, so pressing either was silent —
                    // including the case where Notion has no credentials at
                    // all, which is every install, since nothing here sets
                    // them. Now the button says so, and says where they go.
                    Text {
                        id: syncStatusText
                        Layout.fillWidth: true
                        Layout.leftMargin: Design.s(Design.space.sm)
                        text: NotesBackend.syncStatus
                        elide: Text.ElideRight
                        font.family: Design.font.sans
                        font.pixelSize: Design.s(11)
                        color: NotesBackend.syncStatus.indexOf("Error") >= 0
                               || NotesBackend.syncStatus.indexOf("not configured") >= 0
                               || NotesBackend.syncStatus.indexOf("No Obsidian") >= 0
                            ? Design.warn : Design.textDim
                        visible: NotesBackend.syncStatus !== "" && NotesBackend.syncStatus !== "Ready"
                    }

                    Item { Layout.fillWidth: !syncStatusText.visible }

                    // Search Bar
                    Rectangle {
                        width: Math.min(160, Math.max(100, window.width * 0.18))
                        height: Design.s(26)
                        radius: Design.s(6)
                        color: window.colBg
                        border.color: searchInput.activeFocus ? window.colBlue : window.colBorder
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: Design.s(4)
                            spacing: Design.s(4)

                            Text { text: "󰍉"; font.family: Design.font.mono; font.pixelSize: Design.s(11); color: window.colDim }

                            TextInput {
                                id: searchInput
                                Layout.fillWidth: true
                                font.family: Design.font.sans
                                font.pixelSize: Design.s(11)
                                color: window.colFg
                                selectByMouse: true
                                onTextChanged: window.searchQuery = text.toLowerCase()
                            }
                        }
                    }

                    // Toggle Preview Button
                    Rectangle {
                        width: Design.s(26); height: Design.s(26); radius: Design.s(5)
                        color: prevArea.containsMouse ? Design.tint(Design.accent, 0.25) : "transparent"
                        border.color: window.colBorder
                        border.width: 1
                        Text {
                            anchors.centerIn: parent
                            text: window.showPreview ? "󰈙" : "󱡁"
                            font.family: Design.font.mono
                            font.pixelSize: Design.s(13)
                            color: window.colFg
                        }
                        MouseArea {
                            id: prevArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                            onClicked: window.showPreview = !window.showPreview
                        }
                    }
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
                        Layout.preferredWidth: Design.s(240)
                        Layout.fillHeight: true
                        color: window.colSidebar

                        // Right vertical divider
                        Rectangle {
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: 1
                            color: window.colBorder
                        }

                        ListView {
                            id: notesList
                            anchors.fill: parent
                            anchors.margins: Design.s(8)
                            clip: true
                            spacing: Design.s(4)
                            model: NotesBackend.noteList

                            delegate: Rectangle {
                                width: notesList.width
                                // A hidden delegate still occupies its height in a
                                // ListView, so filtering by `visible` alone left a
                                // 58 px hole for every note the search excluded.
                                height: matchesSearch ? Design.s(58) : 0
                                radius: Design.s(6)
                                clip: true
                                color: isSelected ? Design.tint(Design.accent, 0.20) : (itemArea.containsMouse ? Design.tint(Design.text, 0.05) : "transparent")
                                border.color: isSelected ? window.colBlue : "transparent"
                                border.width: 1

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
                                            font.pixelSize: Design.s(12)
                                            font.bold: true
                                            color: isSelected ? "#ffffff" : window.colFg
                                            elide: Text.ElideRight
                                        }
                                        Text {
                                            text: modelData.date || ""
                                            font.family: Design.font.sans
                                            font.pixelSize: Design.s(9)
                                            color: window.colDim
                                        }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        text: (modelData.content || "").replace(/\n/g, " ")
                                        font.family: Design.font.sans
                                        font.pixelSize: Design.s(10)
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
                                    font.family: Design.font.sans
                                    font.pixelSize: Design.s(20)
                                    font.bold: true
                                    color: window.colFg
                                    selectByMouse: true
                                    onTextChanged: autoSaveTimer.restart()
                                }

                                Rectangle {
                                    width: Design.s(28); height: Design.s(28); radius: Design.s(6)
                                    color: delArea.containsMouse ? Design.tint(Design.danger, 0.25) : "transparent"
                                    border.color: window.colBorder
                                    border.width: 1
                                    Text {
                                        anchors.centerIn: parent
                                        text: "󰆴"
                                        font.family: Design.font.mono
                                        font.pixelSize: Design.s(13)
                                        color: window.colRed
                                    }
                                    MouseArea {
                                        id: delArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                                        onClicked: deleteConfirm.open()
                                    }
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
                                    text: NotesBackend.currentTags
                                    font.family: Design.font.mono
                                    font.pixelSize: Design.s(11)
                                    color: window.colCyan
                                    selectByMouse: true
                                    onTextChanged: autoSaveTimer.restart()

                                    Text {
                                        text: "Add tags (comma separated)..."
                                        font.family: Design.font.sans
                                        font.pixelSize: Design.s(11)
                                        color: window.colDim
                                        visible: !tagInput.text && !tagInput.activeFocus
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
                                        contentHeight: editorArea.implicitHeight + 20
                                        clip: true

                                        TextArea {
                                            id: editorArea
                                            width: parent.width
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

    Dialog {
        id: deleteConfirm
        title: "Delete note?"
        modal: true
        standardButtons: Dialog.Cancel | Dialog.Ok
        onAccepted: NotesBackend.deleteNote(NotesBackend.currentNoteId)
        // A wrapping label as contentItem sizes itself from the width the
        // Dialog gives it, while the Dialog sizes itself from the label —
        // Qt reported "Binding loop detected for property implicitWidth" on
        // every start. An explicit implicitWidth breaks the cycle.
        // Text.implicitWidth is read-only, so the loop has to be broken one
        // level up: an Item can carry an explicit implicit size, and the
        // wrapping label lays out inside it.
        contentItem: Item {
            implicitWidth: Design.s(300)
            implicitHeight: delMsg.implicitHeight + Design.s(36)

            Label {
                id: delMsg
                anchors.fill: parent
                anchors.margins: Design.s(18)
                text: "This note will be permanently deleted."
                wrapMode: Text.WordWrap
            }
        }
    }
}
