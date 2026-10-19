import QtQuick
import QtQuick.Layouts
import QtQuick.Dialogs
import Quickshell
import Quickshell.Io
import "../../Ui"
import "../../Services"

// =============================================================================
// The account's picture: one of a set, an emoji on a colour, or a photo.
//
// What is picked is drawn in the preview and that preview is what is saved —
// a 512-pixel PNG, whatever was picked (a 4000-pixel photo too: AccountsService
// takes a megabyte at most) — through `b1air-daemon user set-avatar`, which
// puts it in ~/.face.icon and hands it to AccountsService for the login
// screen. A pick is applied as it is made, as in the setup it has to be.
// =============================================================================

ColumnLayout {
    id: picker

    // The picture there is now, and the name for the initial when none.
    property string current: ""
    property string name: ""
    signal saved()

    spacing: Design.s(Design.space.lg)
    // A layout is no wider than its widest child can be, and every child
    // here has a width of its own: without this the picker sat at the left
    // of its card, 400 pixels wide, instead of in the middle of it.
    Layout.fillWidth: true
    Layout.maximumWidth: Number.POSITIVE_INFINITY

    // "set", "emoji" or "photo": the tab; and what the preview shows.
    property string tab: "set"
    property string kind: ""             // "", "emoji" or "photo": "" is the current file
    property string emoji: ""
    property color topColour: Design.blue
    property color bottomColour: Design.mauve
    property string photo: ""

    // The set: an emoji on a gradient each, ready made.
    readonly property var presets: [
        { e: "🦊", a: "#ff9a5a", b: "#e8573f" }, { e: "🐼", a: "#b8e1c6", b: "#5fae84" },
        { e: "🐱", a: "#ffd36e", b: "#f39c3d" }, { e: "🐶", a: "#a7c8ff", b: "#5b8def" },
        { e: "🦁", a: "#ffcf70", b: "#e0892b" }, { e: "🐸", a: "#c6f07a", b: "#5fb83c" },
        { e: "🐧", a: "#9fd8ff", b: "#3a8bd8" }, { e: "🦉", a: "#d9b8ff", b: "#8a5bd6" },
        { e: "🐙", a: "#ffb3c8", b: "#e5578a" }, { e: "🦄", a: "#ffc6f0", b: "#b07ad9" },
        { e: "🌵", a: "#d4f5b0", b: "#58a55c" }, { e: "🌸", a: "#ffd6e5", b: "#f07aa5" },
        { e: "🚀", a: "#7f8cff", b: "#3b3f9e" }, { e: "🎧", a: "#5ee0d0", b: "#1a9c8f" },
        { e: "🎮", a: "#9aa4b8", b: "#4a5468" }, { e: "☕", a: "#e6c3a0", b: "#9b6a43" },
        { e: "⚡", a: "#fff07a", b: "#f5b82e" }, { e: "🌙", a: "#4b5a8a", b: "#1c2340" }
    ]
    readonly property var emojis: ["😀", "😎", "🤓", "🥳", "😇", "🤠", "🙂", "😺", "👽", "🤖", "👻", "🐵",
        "🐨", "🐯", "🐰", "🐻", "🐢", "🐝", "🦋", "🐳", "🌻", "🍀", "🍉", "🍕",
        "🍩", "🎨", "🎸", "⚽", "🏀", "🚲", "✈️", "🏔️", "🌊", "🔥", "⭐", "❤️"]
    readonly property var colours: [Design.blue, Design.teal, Design.green, Design.yellow, Design.peach,
        Design.red, Design.pink, Design.mauve, "#5a6478"]

    function pickPreset(p) {
        picker.kind = "emoji";
        picker.emoji = p.e;
        picker.topColour = p.a;
        picker.bottomColour = p.b;
        apply.restart();
    }
    function pickEmoji(e) {
        if (picker.kind !== "emoji") { picker.topColour = Qt.lighter(picker.colours[0], 1.25); picker.bottomColour = picker.colours[0]; }
        picker.kind = "emoji";
        picker.emoji = e;
        apply.restart();
    }
    function pickColour(c) {
        picker.topColour = Qt.lighter(c, 1.25);
        picker.bottomColour = c;
        if (picker.kind === "emoji") apply.restart();
    }

    // A moment after the last pick, so going through the set saves once.
    Timer { id: apply; interval: 450; onTriggered: picker.save() }

    readonly property string tmpPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/b1air-avatar.png"
    function save() {
        if (picker.kind === "") return;
        face.grabToImage(result => {
            if (!result.saveToFile(picker.tmpPath)) return;
            setAvatar.running = false;
            setAvatar.running = true;
        }, Qt.size(512, 512));
    }
    Process {
        id: setAvatar
        command: ["b1air-daemon", "user", "set-avatar", picker.tmpPath]
        onExited: picker.saved()
    }

    FileDialog {
        id: photoDialog
        title: I18n.tr("Select Avatar Image")
        nameFilters: [I18n.tr("Image files") + " (*.png *.jpg *.jpeg *.webp *.svg)"]
        onAccepted: {
            picker.photo = selectedFile.toString();
            picker.kind = "photo";
        }
    }

    // ── The preview, which is also what is saved ────────────────────────────
    Item {
        Layout.alignment: Qt.AlignHCenter
        Layout.preferredWidth: Design.s(Design.size.thumb)
        Layout.preferredHeight: Design.s(Design.size.thumb)

        Rectangle {
            id: face
            anchors.fill: parent
            radius: width / 2
            color: picker.kind === "" && picker.current === "" ? Design.tint(Design.accent, 0.14) : "transparent"

            GradientRect {
                anchors.fill: parent
                radius: parent.radius
                visible: picker.kind === "emoji"
                from: picker.topColour
                to: picker.bottomColour
            }

            Text {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: parent.height * 0.02
                visible: picker.kind === "emoji"
                text: picker.emoji
                font.family: "Noto Color Emoji"
                font.pixelSize: parent.height * 0.56
            }
            RoundImage {
                id: shown
                anchors.fill: parent
                visible: picker.kind === "photo" || (picker.kind === "" && picker.current !== "")
                source: picker.kind === "photo" ? picker.photo
                      : picker.current !== "" ? Paths.fileUrl(picker.current) : ""
                cache: false
                // A photo is saved once it is drawn, not before.
                onStatusChanged: if (status === Image.Ready && picker.kind === "photo") apply.restart()
            }
            Label {
                anchors.centerIn: parent
                visible: picker.kind === "" && picker.current === ""
                text: String(picker.name || "?").charAt(0).toUpperCase()
                font.pixelSize: parent.height * 0.42
                weight: Design.weight.semibold
                color: Design.accent
            }
        }
        Rectangle {   // a fine ring, as on the login screen
            anchors.fill: parent
            anchors.margins: -Design.s(Design.space.xs)
            radius: width / 2
            color: "transparent"
            border.width: Design.s(Design.space.xxs)
            border.color: Design.tint(Design.accent, 0.5)
        }
    }

    SegmentedControl {
        Layout.alignment: Qt.AlignHCenter
        Layout.preferredWidth: Design.s(Design.width.dialog)
        model: [{ id: "set", label: I18n.tr("Collection") }, { id: "emoji", label: I18n.tr("Emoji") },
                { id: "photo", label: I18n.tr("Photo") }]
        current: picker.tab
        onPicked: id => picker.tab = id
    }

    // ── The set ─────────────────────────────────────────────────────────────
    Flow {
        visible: picker.tab === "set"
        Layout.fillWidth: true
        Layout.maximumWidth: Design.s(Design.size.tile * 6 + Design.space.md * 5)
        Layout.alignment: Qt.AlignHCenter
        spacing: Design.s(Design.space.md)
        Repeater {
            model: picker.presets
            Rectangle {
                required property var modelData
                readonly property bool chosen: picker.kind === "emoji" && picker.emoji === modelData.e
                    && Qt.colorEqual(picker.bottomColour, modelData.b)
                width: Design.s(Design.size.tile)
                height: width
                radius: width / 2
                color: "transparent"
                GradientRect {
                    anchors.fill: parent
                    radius: parent.radius
                    from: modelData.a
                    to: modelData.b
                }
                border.width: chosen ? Design.s(Design.space.xxs) : 0
                border.color: Design.accent
                scale: hit.pressed ? 0.94 : hit.containsMouse ? 1.06 : 1
                Behavior on scale { NumberAnimation { duration: Design.duration.fast } }
                Text {
                    anchors.centerIn: parent
                    text: modelData.e
                    font.family: "Noto Color Emoji"
                    font.pixelSize: parent.height * 0.52
                }
                Clickable { id: hit; onClicked: picker.pickPreset(modelData) }
            }
        }
    }

    // ── Any emoji, on a colour ──────────────────────────────────────────────
    ColumnLayout {
        visible: picker.tab === "emoji"
        Layout.fillWidth: true
        spacing: Design.s(Design.space.md)

        Flow {
            Layout.fillWidth: true
            Layout.maximumWidth: Design.s(Design.size.row * 12 + Design.size.dot * 11)
            Layout.alignment: Qt.AlignHCenter
            spacing: Design.s(Design.size.dot)
            Repeater {
                model: picker.emojis
                Rectangle {
                    required property string modelData
                    width: Design.s(Design.size.row)
                    height: width
                    radius: Design.s(Design.radius.ctl)
                    color: picker.kind === "emoji" && picker.emoji === modelData ? Design.tint(Design.accent, 0.25)
                         : em.containsMouse ? Design.hover : "transparent"
                    Text {
                        anchors.centerIn: parent
                        text: modelData
                        font.family: "Noto Color Emoji"
                        font.pixelSize: parent.height * 0.6
                    }
                    Clickable { id: em; onClicked: picker.pickEmoji(modelData) }
                }
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Design.s(Design.space.sm)
            Label { text: I18n.tr("Or type one:"); dim: true }
            Field {
                Layout.preferredWidth: Design.s(Design.width.field)
                horizontalAlignment: TextInput.AlignHCenter
                placeholder: "🙂"
                // Whatever was typed or pasted, a sequence (👩‍💻) included.
                onEdited: v => {
                    const t = Array.from(String(v).trim()).slice(0, 8).join("");
                    if (t !== "") picker.pickEmoji(t);
                }
            }
        }

        Row {
            Layout.alignment: Qt.AlignHCenter
            spacing: Design.s(Design.space.sm)
            Repeater {
                model: picker.colours
                Rectangle {
                    required property color modelData
                    width: Design.s(Design.size.sm)
                    height: width
                    radius: width / 2
                    color: modelData
                    border.width: Qt.colorEqual(picker.bottomColour, modelData) ? Design.s(Design.space.xxs) : 0
                    border.color: Design.text
                    Clickable { onClicked: picker.pickColour(modelData) }
                }
            }
        }
    }

    // ── A photo ─────────────────────────────────────────────────────────────
    ColumnLayout {
        visible: picker.tab === "photo"
        Layout.fillWidth: true
        spacing: Design.s(Design.space.sm)
        Button {
            Layout.alignment: Qt.AlignHCenter
            icon: "\u{f03e}"
            label: I18n.tr("Choose a photo…")
            onActivated: photoDialog.open()
        }
        Label {
            Layout.alignment: Qt.AlignHCenter
            text: I18n.tr("The middle of it is cut round")
            role: "caption"
            dim: true
        }
    }
}
