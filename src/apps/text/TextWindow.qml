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
    title: (TextBackend.isModified ? "● " : "") + I18n.tr("Text Editor — %1", TextBackend.fileName)
    width: Design.s(Design.window.compactWidth)
    height: Design.s(Design.window.compactHeight)
    minimumWidth: Design.s(Design.window.minWidth)
    minimumHeight: Design.s(Design.window.minHeight)
    visible: true
    color: "transparent"

    // Closing keeps everything: the tabs and what is typed in them are the
    // session (backend.cpp), back as they were at the next start, unsaved
    // changes included — and the files on disk as they were, until Save.
    onClosing: Qt.quit()

    property bool wordWrapEnabled: false
    // The editor in front, for the status bar and the keys.
    property var pane: null

    // Another `b1air-text` handed its files over (main.cpp): this window
    // comes forward with them.
    Connections {
        target: TextBackend
        function onRaiseRequested() {
            window.raise();
            window.requestActivate();
        }
    }

    function save() {
        if (!TextBackend.filePath) {
            saveAsDialog.open();
            return;
        }
        TextBackend.saveFile();
    }

    // The tab to close once a save started by the unsaved-changes dialog
    // lands. Only after it succeeds — a save that failed (an Untitled file
    // has nowhere to go) must not throw the text away anyway.
    property string closeAfterSave: ""
    Connections {
        target: TextBackend
        function onSaved(ok) {
            const id = window.closeAfterSave;
            window.closeAfterSave = "";
            if (ok && id) window.closeTabNow(id);
        }
    }

    function tabIndexOf(id) {
        for (let i = 0; i < tabRepeater.count; i++)
            if (tabRepeater.itemAt(i) && tabRepeater.itemAt(i).docId === id) return i;
        return -1;
    }
    function closeTabNow(id) {
        const i = window.tabIndexOf(id);
        if (i >= 0) TextBackend.closeTab(i);
    }
    // A tab with changes is asked about; one without closes.
    function closeTab(i) {
        if (i < 0 || i >= tabRepeater.count) return;
        if (!TextBackend.isModifiedAt(i)) {
            TextBackend.closeTab(i);
            return;
        }
        TextBackend.currentIndex = i;
        unsavedDialog.closing = TextBackend.currentId;
        unsavedDialog.open();
    }
    function step(by) {
        const n = tabRepeater.count;
        if (n > 1) TextBackend.currentIndex = (TextBackend.currentIndex + by + n) % n;
    }

    // ── Global Shortcuts ─────────────────────────────────────────────────────
    Shortcut { sequence: "Ctrl+S"; onActivated: window.save() }
    Shortcut { sequence: "Ctrl+Shift+S"; onActivated: saveAsDialog.open() }
    Shortcut { sequences: ["Ctrl+N", "Ctrl+T"]; onActivated: TextBackend.newFile() }
    Shortcut { sequence: "Ctrl+W"; onActivated: window.closeTab(TextBackend.currentIndex) }
    Shortcut { sequences: ["Ctrl+Tab", "Ctrl+PgDown"]; onActivated: window.step(1) }
    Shortcut { sequences: ["Ctrl+Shift+Tab", "Ctrl+PgUp"]; onActivated: window.step(-1) }
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
        color: Design.glassBg
        clip: true

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // ═════════════════════════════════════════════════════════════════
            // TOP HEADER BAR (COMPACT TILED TOOLBAR)
            // ═════════════════════════════════════════════════════════════════
            // What is open on the left, as in every app; the commands on the right,
            // Save the one primary while there is something to save.
            AppToolbar {
                Layout.fillWidth: true

                AppTitle {
                    title: TextBackend.fileName || I18n.tr("Untitled")
                    subtitle: TextBackend.filePath ? TextBackend.filePath.replace(/\/[^\/]*$/, "") : ""
                    modified: TextBackend.isModified
                }
                Button { variant: "ghost"; iconOnly: true; icon: "\u{f05b6}"; tip: I18n.tr("Wrap long lines"); checked: window.wordWrapEnabled; onClicked: window.wordWrapEnabled = !window.wordWrapEnabled }
                // Changes kept from before (the session) or made now,
                // let go: the file as it is on disk.
                Button {
                    visible: TextBackend.isModified && TextBackend.filePath !== ""
                    variant: "ghost"; iconOnly: true; icon: "\u{f054c}"
                    tip: I18n.tr("Back to the saved file")
                    onClicked: revertDialog.open()
                }
                Button { variant: "ghost"; iconOnly: true; icon: "\u{f0415}"; tip: I18n.tr("New tab (Ctrl+T)"); onClicked: TextBackend.newFile() }
                Button { variant: TextBackend.isModified ? "primary" : "secondary"; icon: "\u{f0193}"; label: I18n.tr("Save"); tip: I18n.tr("Save (Ctrl+S) · Save as (Ctrl+Shift+S)"); onClicked: window.save() }
            }

            // ═════════════════════════════════════════════════════════════════
            // TABS — one file each
            // ═════════════════════════════════════════════════════════════════
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Design.s(Design.size.md)
                color: Design.veil
                Rectangle { anchors.bottom: parent.bottom; width: parent.width; height: 1; color: Design.glassBorder }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Design.s(Design.space.xs)
                    anchors.rightMargin: Design.s(Design.space.xs)
                    spacing: Design.s(Design.space.xxs)

                    ListView {
                        id: tabStrip
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.maximumWidth: contentWidth
                        orientation: ListView.Horizontal
                        clip: true
                        spacing: Design.s(Design.space.xxs)
                        boundsBehavior: Flickable.StopAtBounds
                        model: TextBackend.tabs
                        currentIndex: TextBackend.currentIndex
                        onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

                        delegate: Rectangle {
                            id: tab
                            required property int index
                            required property string docId
                            required property string name
                            required property string path
                            required property bool modified
                            readonly property bool current: index === TextBackend.currentIndex
                            height: tabStrip.height
                            width: Math.min(Design.s(Design.width.tab), tabRow.implicitWidth + Design.s(Design.space.lg))
                            color: current ? Design.veilStrong : (tabMa.containsMouse ? Design.stateHover : "transparent")

                            Rectangle {
                                visible: tab.current
                                anchors.top: parent.top
                                width: parent.width; height: Design.s(Design.space.xxs)
                                color: Design.accent
                            }

                            MouseArea {
                                id: tabMa
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                                onClicked: mouse => {
                                    if (mouse.button === Qt.MiddleButton) window.closeTab(tab.index);
                                    else TextBackend.currentIndex = tab.index;
                                }
                            }

                            RowLayout {
                                id: tabRow
                                anchors.fill: parent
                                anchors.leftMargin: Design.s(Design.space.md)
                                anchors.rightMargin: Design.s(Design.space.xs)
                                spacing: Design.s(Design.space.xs)
                                Label {
                                    Layout.fillWidth: true
                                    Layout.maximumWidth: Design.s(Design.width.label)
                                    text: tab.name
                                    elide: Text.ElideMiddle
                                    role: "caption"
                                    weight: tab.current ? Design.weight.semibold : Design.weight.regular
                                    color: tab.current ? Design.text : Design.textDim
                                }
                                // The dot for changes; the cross under the pointer.
                                Item {
                                    Layout.preferredWidth: Design.s(Design.size.micro)
                                    Layout.preferredHeight: Design.s(Design.size.micro)
                                    Rectangle {
                                        anchors.centerIn: parent
                                        visible: tab.modified && !tabMa.containsMouse && !closeMa.containsMouse
                                        width: Design.s(Design.size.dot); height: width; radius: width / 2
                                        color: Design.accent
                                    }
                                    Icon {
                                        anchors.centerIn: parent
                                        visible: tabMa.containsMouse || closeMa.containsMouse || (tab.current && !tab.modified)
                                        text: "\u{f0156}"
                                        role: "caption"
                                        color: closeMa.containsMouse ? Design.text : Design.textFaint
                                    }
                                    MouseArea {
                                        id: closeMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: window.closeTab(tab.index)
                                    }
                                }
                            }
                            ToolTip.visible: tabMa.containsMouse && tab.path !== ""
                            ToolTip.delay: 600
                            ToolTip.text: tab.path
                        }
                    }
                    Button {
                        Layout.alignment: Qt.AlignVCenter
                        variant: "ghost"; iconOnly: true; size: "sm"
                        icon: "\u{f0415}"
                        tip: I18n.tr("New tab (Ctrl+T)")
                        onClicked: TextBackend.newFile()
                    }
                    Item { Layout.fillWidth: true }
                }
            }

            // ═════════════════════════════════════════════════════════════════
            // THE EDITORS — one per tab, each with its own undo and place
            // ═════════════════════════════════════════════════════════════════
            StackLayout {
                id: editors
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: TextBackend.currentIndex

                Repeater {
                    id: tabRepeater
                    model: TextBackend.tabs
                    delegate: EditorPane {}
                }
            }

            // ═════════════════════════════════════════════════════════════════
            // BOTTOM STATUS BAR
            // ═════════════════════════════════════════════════════════════════
            AppStatusBar {
                Layout.fillWidth: true
                Label { text: I18n.tr("Ln %1, Col %2", window.pane ? window.pane.currentLine : 1, window.pane ? window.pane.currentCol : 1); role: "caption"; isMono: true; dim: true }
                Label { text: I18n.trn("%1 line", "%1 lines", TextBackend.lineCount) + "  ·  " + I18n.trn("%1 word", "%1 words", TextBackend.wordCount); role: "caption"; dim: true }
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

    // Above everything: files dragged in from Files open here, each in a tab
    // of its own beside what is open already.
    DropArea {
        anchors.fill: parent
        keys: ["text/uri-list"]
        onDropped: drop => {
            // urls, or the list itself when the drag carried only that.
            const urls = (drop.hasUrls ? Array.from(drop.urls, u => String(u))
                              : String(drop.getDataAsString("text/uri-list") || "").split(/\r?\n/).filter(l => l && !l.startsWith("#")));
            const files = urls.filter(u => u.startsWith("file://"));
            if (files.length === 0) return;
            drop.accept(Qt.CopyAction);
            for (const u of files) TextBackend.openFile(decodeURIComponent(u.slice(7)));
        }
    }

    AppDialog {
        id: unsavedDialog
        // The tab being closed.
        property string closing: ""
        title: I18n.tr("Unsaved changes")
        message: I18n.tr("Save changes to %1 before closing it?", TextBackend.fileName)
        standardButtons: Dialog.Cancel | Dialog.Discard | Dialog.Save
        onAccepted: {
            window.closeAfterSave = unsavedDialog.closing;
            window.save();
        }
        onDiscarded: {
            unsavedDialog.close();
            window.closeTabNow(unsavedDialog.closing);
        }
        onRejected: unsavedDialog.closing = ""
    }

    AppDialog {
        id: revertDialog
        title: I18n.tr("Back to the saved file")
        message: I18n.tr("Let go of the changes to %1 and show it as it is on disk?", TextBackend.fileName)
        standardButtons: Dialog.Cancel | Dialog.Discard
        onDiscarded: {
            revertDialog.close();
            TextBackend.revertCurrent();
        }
    }

    AppDialog {
        id: saveAsDialog
        title: I18n.tr("Save as")
        standardButtons: Dialog.Cancel | Dialog.Save
        onOpened: {
            savePathField.text = TextBackend.suggestedPath;
            savePathField.focusInput();
        }
        onAccepted: TextBackend.saveFile(savePathField.text.trim())
        onRejected: window.closeAfterSave = ""

        contentItem: ColumnLayout {
            implicitWidth: Design.s(Design.width.menuMax)
            spacing: Design.s(Design.space.sm)

            Label {
                text: I18n.tr("Path")
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

    // ═════════════════════════════════════════════════════════════════════════
    // One tab's editor: line numbers and the text
    // ═════════════════════════════════════════════════════════════════════════
    component EditorPane: Rectangle {
        id: pane
        required property int index
        required property string docId
        required property string path
        color: "transparent"

        property int currentLine: 1
        property int currentCol: 1
        // Offset of the first character of every line, for the gutter.
        property var lineStarts: [0]

        readonly property bool isCurrent: StackLayout.isCurrentItem
        onIsCurrentChanged: if (isCurrent) { window.pane = pane; editorArea.forceActiveFocus(); }

        function recomputeLineStarts(t) {
            const starts = [0];
            let i = -1;
            while ((i = t.indexOf("\n", i + 1)) !== -1) starts.push(i + 1);
            pane.lineStarts = starts;
        }
        // From the line starts, by halves: it took the text up to the caret
        // and split it into lines, a copy of most of the file on every key.
        function calculateCursorPos() {
            const pos = editorArea.cursorPosition, starts = pane.lineStarts;
            let lo = 0, hi = starts.length - 1;
            while (lo < hi) {
                const mid = (lo + hi + 1) >> 1;
                if (starts[mid] <= pos) lo = mid; else hi = mid - 1;
            }
            pane.currentLine = lo + 1;
            pane.currentCol = pos - starts[lo] + 1;
        }

        RowLayout {
            anchors.fill: parent
            spacing: 0

            // ── Line Numbers Gutter ──────────────────────────────────────────
            Rectangle {
                Layout.fillHeight: true
                Layout.preferredWidth: Design.s(Design.size.rowTall)
                color: Design.veil

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
                    model: pane.lineStarts.length

                    delegate: Item {
                        required property int index
                        // Re-evaluated when the layout changes: width
                        // (wrapping) and contentHeight (any edit).
                        readonly property real _layout: editorArea.contentHeight + editorArea.width
                        readonly property rect _here: (_layout, editorArea.positionToRectangle(pane.lineStarts[index] || 0))
                        readonly property real _next: index + 1 < pane.lineStarts.length
                            ? (_layout, editorArea.positionToRectangle(pane.lineStarts[index + 1]).y)
                            : _here.y + _here.height
                        width: lineNumbersView.width - Design.s(Design.space.md)
                        height: Math.max(1, _next - _here.y)

                        Text {
                            width: parent.width
                            height: parent._here.height
                            text: String(index + 1)
                            font.family: Design.font.mono
                            font.pixelSize: Design.s(Design.font.body)
                            color: (index + 1 === pane.currentLine) ? Design.accent : Design.textFaint
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

            // ── Editor TextArea ──────────────────────────────────────────────
            Flickable {
                id: editorFlickable
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                ScrollBar.vertical: OverflowBar {}
                ScrollBar.horizontal: ScrollBar { policy: window.wordWrapEnabled ? ScrollBar.AlwaysOff : ScrollBar.AsNeeded }

                TextArea.flickable: TextArea {
                    id: editorArea
                    // The style's own frame drew an accent outline round the
                    // whole page whenever it had the caret, i.e. always.
                    background: null
                    font.family: Design.font.mono
                    font.pixelSize: Design.s(Design.font.body)
                    color: Design.text
                    selectionColor: Design.tint(Design.accent, 0.35)
                    selectedTextColor: Design.text
                    tabStopDistance: 32
                    wrapMode: window.wordWrapEnabled ? TextEdit.Wrap : TextEdit.NoWrap
                    padding: Design.s(Design.space.md)
                    selectByMouse: true
                    // The tab's text is put in when it opens and when the
                    // backend replaces it (contentReset), not bound: bound,
                    // each key sent the whole text back to be compared with
                    // itself.
                    property bool loading: true
                    Component.onCompleted: {
                        text = TextBackend.contentOf(pane.docId);
                        cursorPosition = Math.min(TextBackend.cursorOf(pane.docId), length);
                        loading = false;
                        pane.recomputeLineStarts(text);
                        pane.calculateCursorPos();
                        if (pane.isCurrent) { window.pane = pane; forceActiveFocus(); }
                    }

                    onTextChanged: {
                        if (loading) return;
                        const t = text;
                        TextBackend.setContentOf(pane.docId, t);
                        pane.recomputeLineStarts(t);
                        pane.calculateCursorPos();
                    }

                    onCursorPositionChanged: {
                        pane.calculateCursorPos();
                        if (!loading) TextBackend.setCursorOf(pane.docId, cursorPosition);
                    }

                    Connections {
                        target: TextBackend
                        function onContentReset(id) {
                            if (id !== pane.docId) return;
                            const pos = editorArea.cursorPosition;
                            editorArea.loading = true;
                            editorArea.text = TextBackend.contentOf(pane.docId);
                            editorArea.cursorPosition = Math.min(pos, editorArea.length);
                            editorArea.loading = false;
                            pane.recomputeLineStarts(editorArea.text);
                            pane.calculateCursorPos();
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
                EmptyState {
                    // Positioned against the Flickable's viewport rather
                    // than anchored to `parent`: assigning TextArea.flickable
                    // makes this a child of the content item, whose origin
                    // is the top-left of the *document*, so centring on it
                    // put the message in the gutter.
                    width: Math.min(editorFlickable.width, Design.s(Design.width.dialog))
                    x: (editorFlickable.width - width) / 2
                    y: (editorFlickable.height - implicitHeight) / 2
                    visible: editorArea.text.length === 0
                             && !pane.path
                             && !editorArea.activeFocus
                    icon: "\u{f0219}"
                    title: I18n.tr("Empty document")
                    hint: I18n.tr("Start typing, or open a file.")
                }
            }
        }
    }
}
