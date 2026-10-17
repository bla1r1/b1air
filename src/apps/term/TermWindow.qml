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
        color: Design.surface
        clip: true

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // The standard toolbar: what runs in the current tab on the left,
            // a new tab and a menu on the right. It was a 42px header of its
            // own, with the tabs, an app glyph and five icon buttons in a row.
            AppToolbar {
                Layout.fillWidth: true
                rule: tabsModel.count < 2
                z: 10

                AppTitle {
                    readonly property var tab: tabsModel.count > window.currentTabIndex ? tabsModel.get(window.currentTabIndex) : null
                    title: (tab && tab.tabTitle) || "fish"
                    subtitle: tabsModel.count > 1 ? I18n.tr("Tab %1 of %2", window.currentTabIndex + 1, tabsModel.count) : ""
                }
                Button { variant: "ghost"; iconOnly: true; icon: "\u{f0415}"; tip: I18n.tr("New tab (Ctrl+Shift+T)"); onClicked: window.createNewTab("", "") }
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

            // The tabs, under the toolbar as in Files; with one there is
            // nothing to choose between, so no strip.
            Item {
                visible: tabsModel.count > 1
                Layout.fillWidth: true
                Layout.preferredHeight: Design.s(Design.size.knob)
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Design.s(Design.space.md)
                    anchors.rightMargin: Design.s(Design.space.md)
                    spacing: Design.s(Design.space.xs)
                    Repeater {
                        model: tabsModel
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
                    Item { Layout.fillWidth: true }
                }
                Rectangle {
                    anchors.left: parent.left; anchors.right: parent.right; anchors.bottom: parent.bottom
                    height: Design.border
                    color: Design.separator
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

                            // Follow the desktop theme. The terminal painted
                            // itself Catppuccin from two hardcoded constants,
                            // so the one window that fills its whole area with
                            // a single colour was the one that ignored the
                            // theme picker.
                            backgroundColor: Design.ground
                            foregroundColor: Design.text

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
        onActivated: window.createNewTab("", "")
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
