import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../Ui"
import "../Services"

// =============================================================================
// Native Clipboard Manager Popup
//
// Fast, searchable clipboard history with pinning, format detection, and
// 1-click paste/copy.
// =============================================================================

PopupShell {
    id: root

    property string searchFilter: ""

    readonly property var permanentTemplates: [
        { text: "Best regards,\nBlair\nSent from b1air desktop", title: I18n.tr("Email Signature"), type: "text", pinned: true, template: true },
        { text: "feat(scope): short summary\n\nDetailed context and implementation rationale.", title: I18n.tr("Git Commit Template"), type: "code", pinned: true, template: true },
        { text: "sudo pacman -Syu && yay -Sua", title: I18n.tr("Arch System Upgrade"), type: "code", pinned: true, template: true },
        { text: "- [ ] Task 1\n- [ ] Task 2\n- [ ] Task 3", title: I18n.tr("Markdown Checklist"), type: "code", pinned: true, template: true },
        { text: "Lorem ipsum dolor sit amet, consectetur adipiscing elit, sed do eiusmod tempor incididunt ut labore et dolore magna aliqua.", title: I18n.tr("Lorem Ipsum Text"), type: "text", pinned: true, template: true },
        { text: "#include <iostream>\n\nint main(int argc, char* argv[]) {\n    std::cout << \"Hello, b1air!\\n\";\n    return 0;\n}", title: I18n.tr("C++20 Boilerplate"), type: "code", pinned: true, template: true }
    ]

    // Order: what the user pinned, then what they copied, then the built-ins.
    //
    // The templates came first. Six of them, and the panel shows six rows — so
    // a clipboard manager opened to a full screen of boilerplate and the thing
    // just copied was below the fold, every time. They are still here, and
    // still last, because that is where a fixed list of snippets belongs once
    // there is real history to show.
    readonly property var allItems: {
        // Read into the result, so the binding depends on it: re-sorts and
        // re-colours when a pin changes (see Clipboard.revision).
        const rev = Clipboard.revision;
        const pinned = [];
        const recent = [];
        for (let i = 0; i < Clipboard.items.count; i++) {
            const m = Clipboard.items.get(i);
            // Plain copies, not the ListModel's own element objects: those
            // kept the value they were read with, so a pinned entry went on
            // drawing as unpinned until the popup was rebuilt.
            const it = { id: m.id, text: m.text, preview: m.preview, type: m.type,
                         time: m.time, pinned: !!m.pinned };
            (it.pinned ? pinned : recent).push(it);
        }
        return rev >= 0 ? pinned.concat(recent, root.permanentTemplates) : [];
    }

    readonly property var filteredItems: root.allItems.filter(it => {
        return !root.searchFilter || it.text.toLowerCase().includes(root.searchFilter.toLowerCase());
    })

    ColumnLayout {
        anchors.fill: parent
        spacing: Design.s(Design.space.md)

        // ── 1. Header ────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.sm)

            Icon {
                text: "\u{f0ea}" // clipboard
                role: "subhead"
                color: Design.textDim
            }

            Label {
                text: I18n.tr("Clipboard History")
                role: "subhead"
                weight: Design.weight.semibold
            }

            Badge {
                text: String(root.filteredItems.length)
            }

            Item { Layout.fillWidth: true }

            Button {
                visible: Clipboard.items.count > 0
                icon: "\u{f0156}"
                label: I18n.tr("Clear All")
                onActivated: clearConfirm.open()
            }
        }

        // ── 2. Search Field ───────────────────────────────────────────────────
        Field {
            id: searchInput
            Layout.fillWidth: true
            placeholder: I18n.tr("Search clipboard history...")
            text: root.searchFilter
            onEdited: v => root.searchFilter = v
            Component.onCompleted: searchInput.forceActiveFocus()
        }

        // ── 3. Clipboard Items List ──────────────────────────────────────────
        ListView {
            id: clipList
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.filteredItems.length > 0
            clip: true
            spacing: Design.s(Design.space.xs)
            model: root.filteredItems

            // The list scrolled with the wheel and said so nowhere: the last
            // entry sat cut in half against the bottom of the panel. The
            // margin keeps it off that edge once scrolled to the end.
            bottomMargin: Design.s(Design.space.sm)
            ScrollBar.vertical: OverflowBar {}

            delegate: Rectangle {
                id: clipCard
                required property var modelData
                required property int index
                readonly property bool pinned: !!clipCard.modelData.pinned

                width: ListView.view ? ListView.view.width : 0
                implicitHeight: cardCol.implicitHeight + Design.s(Design.space.sm)
                radius: Design.s(Design.radius.card)
                // Pinned: a hint of the accent. A full accent frame on every
                // template made a list of them read as a list of warnings.
                color: clipCard.pinned ? Design.tint(Design.accent, 0.08)
                     : (cardHoverMa.containsMouse ? Design.glassHover : Design.glassCard)
                border.color: clipCard.pinned ? Design.tint(Design.accent, 0.40)
                            : (cardHoverMa.containsMouse ? Design.glassBorderStrong : Design.glassBorder)
                border.width: 1

                RowLayout {
                    id: cardCol
                    anchors.fill: parent
                    anchors.margins: Design.s(Design.space.sm)
                    spacing: Design.s(Design.space.sm)

                    // Type Icon
                    Rectangle {
                        Layout.preferredWidth: Design.s(Design.size.md)
                        Layout.preferredHeight: Design.s(Design.size.md)
                        radius: Design.s(Design.radius.ctl)
                        color: clipCard.modelData.type === "color" ? clipCard.modelData.text.trim() : Design.well
                        Layout.alignment: Qt.AlignTop

                        Icon {
                            visible: clipCard.modelData.type !== "color"
                            anchors.centerIn: parent
                            text: clipCard.modelData.type === "code" ? "\u{f0169}"
                                : (clipCard.modelData.type === "link" ? "\u{f0339}" : "\u{f0219}")
                            role: "caption"
                            color: Design.textDim
                        }
                    }

                    // Content Snippet
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        RowLayout {
                            Layout.fillWidth: true
                            Label {
                                text: clipCard.modelData.title ? clipCard.modelData.title : clipCard.modelData.type.toUpperCase()
                                role: "caption"
                                weight: Design.weight.semibold
                            }
                            Label {
                                text: "• " + (clipCard.modelData.time || I18n.tr("Template"))
                                role: "caption"
                                dim: true
                            }
                            Label {
                                text: I18n.tr("(%1 chars)", clipCard.modelData.text.length)
                                role: "caption"
                                dim: true
                            }
                        }

                        Label {
                            text: clipCard.modelData.preview || clipCard.modelData.text
                            isMono: clipCard.modelData.type === "code"
                            role: "body"
                            maximumLineCount: 3
                            wrapMode: Text.WrapAnywhere
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }

                    // Action buttons
                    RowLayout {
                        spacing: Design.s(Design.space.xxs)
                        Layout.alignment: Qt.AlignTop

                        // A template is not in the history, so there is
                        // nothing to unpin or delete — the buttons were drawn
                        // anyway and acted on whatever real clip happened to
                        // share the row number.
                        IconButton {
                            visible: !clipCard.modelData.template
                            icon: clipCard.pinned ? "\u{f0403}" : "\u{f0404}"
                            role: "caption"
                            hoverTone: Design.accent
                            onClicked: Clipboard.togglePin(clipCard.modelData.id)
                        }

                        IconButton {
                            visible: !clipCard.modelData.template
                            icon: "\u{f0156}"
                            role: "caption"
                            hoverTone: Design.danger
                            onClicked: Clipboard.deleteItem(clipCard.modelData.id)
                        }
                    }
                }

                Clickable {
                    id: cardHoverMa
                    // Below the card's contents: declared last, it lay over the
                    // pin and delete buttons, and pressing either copied the
                    // entry and closed the popup instead.
                    z: -1
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        Clipboard.copyToClipboard(clipCard.modelData.text);
                        root.close();
                    }
                }
            }
        }

        // Before the store is read, an empty list says nothing about history.
        AppState {
            Layout.fillWidth: true
            Layout.fillHeight: true
            mode: root.filteredItems.length > 0 ? "" : !Clipboard._loaded ? "loading" : "empty"
            icon: "\u{f0ea}"
            title: mode === "loading" ? ""
                 : root.searchFilter ? I18n.tr("No matching clips found") : I18n.tr("Clipboard history is empty")
            hint: root.searchFilter ? "" : I18n.tr("Copied text and snippets will appear here automatically")
        }
    }

    AppDialog {
        id: clearConfirm
        title: I18n.tr("Clear clipboard history?")
        message: I18n.tr("All unpinned clipboard entries will be removed.")
        destructive: true
        standardButtons: Dialog.Cancel | Dialog.Ok
        onAccepted: Clipboard.clearHistory()
        buttonText: ({ [Dialog.Ok]: I18n.tr("Clear") })
    }
}
