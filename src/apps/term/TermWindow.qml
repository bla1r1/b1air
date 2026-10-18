import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Controls
import B1Air.Term 1.0
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
    title: I18n.tr("Terminal")
    width: Design.s(Design.window.compactWidth)
    height: Design.s(Design.window.compactHeight)
    minimumWidth: Design.s(Design.window.minWidth)
    minimumHeight: Design.s(Design.window.minHeight)
    visible: true
    color: "transparent"

    property int currentTabIndex: 0

    ListModel {
        id: tabsModel
        ListElement { tabTitle: "fish"; initialCmd: ""; initialDir: "" }
    }

    function createNewTab(cmd, dir) {
        tabsModel.append({
            tabTitle: "fish",
            initialCmd: cmd || "",
            initialDir: dir || ""
        });
        window.currentTabIndex = tabsModel.count - 1;
    }

    // A new tab opens where the current one's shell is, as other terminals do.
    function newTabHere() {
        const view = window.currentTermView();
        window.createNewTab("", view ? view.currentDirectory() : "");
    }

    function closeTab(index) {
        if (index < 0 || index >= tabsModel.count)
            return;
        if (tabsModel.count <= 1) {
            window.close();
            return;
        }
        tabsModel.remove(index);
        // Closing a tab to the left of the current one used to leave the
        // index where it was, which is now the next tab over: the view jumped
        // to a different shell than the one you were typing in.
        if (window.currentTabIndex > index || window.currentTabIndex >= tabsModel.count)
            window.currentTabIndex = Math.max(0, window.currentTabIndex - 1);
        Qt.callLater(() => { const v = window.currentTermView(); if (v) v.forceActiveFocus(); });
    }

    onClosing: Qt.quit()

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

            // One row, as the old 42px header was, in the toolbar's style:
            // with one shell its title on the left; with more the tabs take
            // that place (the title is the active tab's label), and a new tab
            // and the menu stay on the right. The tabs had a strip of their
            // own under the toolbar, which also said "Tab 2 of 2" above them.
            AppToolbar {
                Layout.fillWidth: true
                z: 10

                AppTitle {
                    visible: tabsModel.count < 2
                    readonly property var tab: tabsModel.count > window.currentTabIndex ? tabsModel.get(window.currentTabIndex) : null
                    title: (tab && tab.tabTitle) || "fish"
                }
                ListView {
                    id: tabStrip
                    visible: tabsModel.count > 1
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    Layout.preferredHeight: Design.s(Design.size.md)
                    orientation: ListView.Horizontal
                    spacing: Design.s(Design.space.xs)
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    model: tabsModel
                    currentIndex: window.currentTabIndex
                    // The active tab stays in view when there are more than fit.
                    highlightFollowsCurrentItem: false
                    onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
                    delegate: AppTab {
                        required property int index
                        required property var model
                        label: model.tabTitle || "fish"
                        active: window.currentTabIndex === index
                        closable: tabsModel.count > 1
                        onClicked: window.currentTabIndex = index
                        onCloseRequested: window.closeTab(index)
                    }
                }
                Button { variant: "ghost"; iconOnly: true; icon: "\u{f0415}"; tip: I18n.tr("New tab (Ctrl+Shift+T)"); onClicked: window.newTabHere() }
                Button {
                    id: termMoreBtn
                    variant: "ghost"; iconOnly: true; icon: "\u{f01d9}"
                    tip: I18n.tr("More")
                    onClicked: termMenu.popup(termMoreBtn, 0, termMoreBtn.height)
                }
                AppMenu {
                    id: termMenu
                    AppMenuItem { text: I18n.tr("Copy"); keys: "Ctrl+Shift+C"; glyph: "\u{f018f}"; onTriggered: currentTermView().copySelection() }
                    AppMenuItem { text: I18n.tr("Paste"); keys: "Ctrl+Shift+V"; glyph: "\u{f0192}"; onTriggered: currentTermView().pasteClipboard() }
                    AppMenuItem { text: I18n.tr("Clear"); glyph: "\u{f00e2}"; onTriggered: currentTermView().clear() }
                    AppMenuSeparator {}
                    AppMenuItem { text: I18n.tr("Larger text"); keys: "Ctrl+="; glyph: "\u{f0415}"; onTriggered: currentTermView().zoomIn() }
                    AppMenuItem { text: I18n.tr("Smaller text"); keys: "Ctrl+−"; glyph: "\u{f0374}"; onTriggered: currentTermView().zoomOut() }
                }
            }

            // ── Terminal Views Stack ─────────────────────────────────────────
            StackLayout {
                id: termStack
                Layout.fillWidth: true
                Layout.fillHeight: true
                currentIndex: window.currentTabIndex

                Repeater {
                    id: termRepeater
                    model: tabsModel
                    delegate: Item {
                        id: tabItem
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        TerminalView {
                            id: singleTermView
                            anchors.fill: parent
                            anchors.margins: Design.s(Design.space.sm)
                            focus: window.currentTabIndex === index

                            // The desktop theme's colours.
                            backgroundColor: Qt.alpha(Design.ground, 0)
                            foregroundColor: Design.text
                            // The sixteen from the theme's own colours, so a
                            // program's red is the desktop's red. The bright
                            // eight are a step away from the background: lighter
                            // on a dark theme, deeper on a light one; black and
                            // white are the theme's faint and plain text.
                            ansiColors: {
                                const dark = Design.darkTheme;
                                const step = c => dark ? Qt.lighter(c, 1.25) : Qt.darker(c, 1.2);
                                const base = [dark ? Design.textFaint : Design.textDim, Design.red, Design.green,
                                              Design.yellow, Design.blue, Design.mauve, Design.teal,
                                              dark ? Design.textDim : Design.text];
                                return base.concat([dark ? Design.textDim : Design.textFaint].concat(
                                                   base.slice(1, 7).map(step)).concat([Design.text]));
                            }

                            Component.onCompleted: {
                                var cmd = model.initialCmd || ((typeof InitialCommand !== "undefined" && index === 0) ? InitialCommand : "");
                                var dir = model.initialDir || ((typeof InitialDir !== "undefined" && index === 0) ? InitialDir : "");
                                launch(cmd, dir);
                                forceActiveFocus();
                            }

                            onTitleChanged: {
                                if (title && title.length > 0) {
                                    model.tabTitle = title;
                                }
                            }

                            // --hold keeps the first tab's finished command
                            // on screen until a key is pressed.
                            property bool holding: false
                            onProcessFinished: exitCode => {
                                if (index === 0 && !holding && typeof HoldOnExit !== "undefined" && HoldOnExit) {
                                    holding = true;
                                    showNotice(I18n.tr("[finished with code %1 — press any key to close]", exitCode));
                                    return;
                                }
                                window.closeTab(index);
                            }
                            onKeyAfterExit: {
                                if (holding) window.closeTab(index);
                            }
                        }

                        // Files dragged in from Files: their paths, typed in
                        // where the cursor is; text dragged in, pasted.
                        DropArea {
                            anchors.fill: singleTermView
                            onEntered: drag => drag.accept(Qt.CopyAction)
                            onDropped: drop => {
                                const urls = (drop.hasUrls ? Array.from(drop.urls, u => String(u))
                                                 : String(drop.getDataAsString("text/uri-list") || "").split(/\r?\n/).filter(l => l && !l.startsWith("#")));
                                if (urls.length > 0) singleTermView.dropUrls(urls);
                                else if (drop.hasText) singleTermView.pasteText(drop.text);
                                else return;
                                drop.accept(Qt.CopyAction);
                                window.currentTabIndex = index;
                            }
                        }
                    }
                }
            }
        }
    }

    // Through the Repeater, not termStack.children: the Repeater is itself
    // the first child of the stack, so children[i] was the tab before the
    // current one — copy, paste and zoom acted on the neighbouring tab, and on
    // the first tab did nothing at all.
    function currentTermView() {
        const tab = termRepeater.itemAt(window.currentTabIndex);
        return tab && tab.children.length > 0 ? tab.children[0] : null;
    }

    // Global Shortcuts
    Shortcut {
        sequences: ["Ctrl+Shift+T"]
        onActivated: window.newTabHere()
    }
    Shortcut {
        sequences: ["Ctrl+Shift+W"]
        onActivated: window.closeTab(window.currentTabIndex)
    }
    Shortcut {
        sequences: ["Ctrl+Shift+C"]
        onActivated: currentTermView() && currentTermView().copySelection()
    }
    Shortcut {
        sequences: ["Ctrl+Shift+V"]
        onActivated: currentTermView() && currentTermView().pasteClipboard()
    }
    Shortcut {
        sequences: ["Ctrl+Plus", "Ctrl+="]
        onActivated: currentTermView() && currentTermView().zoomIn()
    }
    Shortcut {
        sequences: ["Ctrl+Minus"]
        onActivated: currentTermView() && currentTermView().zoomOut()
    }
    Shortcut {
        sequences: ["Ctrl+0"]
        onActivated: currentTermView() && currentTermView().resetZoom()
    }
}
