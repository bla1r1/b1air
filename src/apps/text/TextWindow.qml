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
    palette.light: Design.active
    palette.midlight: Design.hover
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

    Surface {
        kind: "glass"
        border.width: 0
        id: windowFrame
        anchors.fill: parent
        // No corners or outline of our own: sway draws both, and only sway
        // knows which window has focus. The app drew a fixed 1px line and sway
        // was told `border none` for it, so ours were the only windows on the
        // desktop that did not light up when focused. SwayFX's corner_radius
        // rounds the surface; a 14px radius inside its 10px one left slivers.
        radius: 0
        clip: true

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

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

            // The toolbar over the text, as a Mac's: the text starts below it
            // (the editor's top padding) and scrolls under its glass, the
            // edge effect behind the tabs and the title so they read over it.
            ScrollEdge {
                id: scrollEdge
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                backdrop: editors
                barHeight: textBar.height
                flick: window.pane ? window.pane.flick : null
            }
            AppToolbar {
                id: textBar
                over: scrollEdge.scrolledUnder
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                z: 10
                rule: false

                // One file: its name and folder, as every app's title. More:
                // the tabs in the title's place, as Terminal has them — a
                // strip of their own under the toolbar was a browser's.
                AppTitle {
                    visible: tabStrip.count < 2
                    title: TextBackend.fileName || I18n.tr("Untitled")
                    subtitle: TextBackend.filePath ? TextBackend.filePath.replace(/\/[^\/]*$/, "") : ""
                    modified: TextBackend.isModified
                }
                ListView {
                    id: tabStrip
                    visible: count > 1
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredHeight: Design.s(Design.size.md)
                    orientation: ListView.Horizontal
                    spacing: Design.s(Design.space.xs)
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    model: TextBackend.tabs
                    currentIndex: TextBackend.currentIndex
                    highlightFollowsCurrentItem: false
                    onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
                    delegate: AppTab {
                        required property int index
                        required property string docId
                        required property string name
                        required property string path
                        // Not `required property bool modified`: AppTab has
                        // its own, which a second would hide.
                        required property var model
                        modified: model.modified
                        label: name
                        tip: path
                        active: index === TextBackend.currentIndex
                        onClicked: TextBackend.currentIndex = index
                        onCloseRequested: window.closeTab(index)
                    }
                }
                ToolbarGroup {
                    backdrop: editors
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
                }
                Button { variant: TextBackend.isModified ? "primary" : "secondary"; icon: "\u{f0193}"; label: I18n.tr("Save"); tip: I18n.tr("Save (Ctrl+S) · Save as (Ctrl+Shift+S)"); onClicked: window.save() }
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
    component EditorPane: Box {
        id: pane
        // What scrolls, for the toolbar's edge effect.
        readonly property Flickable flick: editorFlickable
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

        // The first line below the toolbar once the text is in, unless the
        // caret it reopens at is further down: TextArea keeps its caret in
        // view and knows nothing of the view's top margin.
        function settleTop() {
            if (editorArea.cursorRectangle.y + editorArea.cursorRectangle.height
                    < editorFlickable.height - editorFlickable.topMargin)
                editorFlickable.contentY = -editorFlickable.topMargin;
        }

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
            Box {
                Layout.fillHeight: true
                Layout.preferredWidth: Design.s(Design.size.rowTall)
                color: Design.veil

                ListView {
                    id: lineNumbersView
                    anchors.fill: parent
                    anchors.topMargin: editorArea.topPadding + editorFlickable.topMargin
                    anchors.bottomMargin: editorArea.bottomPadding
                    clip: true
                    interactive: false
                    contentY: editorFlickable.contentY + editorFlickable.topMargin

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

                        Label {
                            width: parent.width
                            height: parent._here.height
                            text: String(index + 1)
                            isMono: true
                            color: (index + 1 === pane.currentLine) ? Design.accent : Design.textFaint
                            horizontalAlignment: Text.AlignRight
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }

                // Gutter Right Divider
                Box {
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
                // Below the toolbar at rest, under its glass when scrolled:
                // a margin of the view, not the text's own padding — a text
                // does not draw the lines that scroll into its padding.
                topMargin: textBar.height
                // A plain Flickable starts at 0 whatever its margin (a list
                // starts above it): put the first line below the toolbar,
                // and keep it there while the toolbar finds its height.
                Component.onCompleted: contentY = -topMargin
                onTopMarginChanged: if (contentY <= 0) contentY = -topMargin

                ScrollBar.vertical: OverflowBar {}
                ScrollBar.horizontal: OverflowBar { orientation: Qt.Horizontal; enabled: !window.wordWrapEnabled; visible: !window.wordWrapEnabled }

                TextArea.flickable: TextBox {
                    id: editorArea
                    // The style's own frame drew an accent outline round the
                    // whole page whenever it had the caret, i.e. always.
                    background: null
                    font.family: Design.font.mono
                    font.pixelSize: Design.s(Design.font.body)
                    color: Design.text
                    selectionColor: Design.stateSelectedStrong
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
                        Qt.callLater(pane.settleTop);
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
                PointerArea {
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
