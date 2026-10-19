import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../Ui"
import "../../Services"

// =============================================================================
// The welcome: Settings' page "welcome", what Mod+H opens and what is shown at
// login until "Show at login" is unticked (Settings.openGuideAtStartup).
//
// Not the first-run setup (SetupWizard), which asks things once — language,
// Wi-Fi, the account. This is where the desktop's parts are, each a card that
// opens it, with its key: the first thing someone new needs, and what anyone
// can come back to. A card for what is not installed (Bottles, Steam,
// Distrobox — the editions differ) is not shown.
// =============================================================================

Item {
    id: welcome

    signal finished()
    signal openPage(string id)

    // What is installed, and the edition (/etc/b1air/edition), asked once.
    property var have: []
    property string edition: ""
    Process {
        running: true
        command: ["sh", "-c",
            "for c in bottles wine steam heroic distrobox; do command -v $c >/dev/null 2>&1 && echo $c; done; "
            + "command -v flatpak >/dev/null 2>&1 && flatpak list --app --columns=application 2>/dev/null; "
            + "echo edition=$(cat /etc/b1air/edition 2>/dev/null)"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.split("\n").filter(l => l !== "");
                welcome.have = lines;
                const e = lines.find(l => l.indexOf("edition=") === 0);
                welcome.edition = e ? e.slice(8) : "";
            }
        }
    }
    function has(...names) { return names.some(n => welcome.have.indexOf(n) >= 0); }

    // `back`: closing that panel comes back here (Main.qml's returnTo) — for
    // the Control Center and the updater, which are looked at and closed.
    // Spotlight and the Launchpad start a program, and the welcome popping
    // up over it would be in the way.
    function shell(target, back) {
        if (back && typeof masterWindow !== "undefined") masterWindow.returnTo = "guide";
        Quickshell.execDetached(["b1air-shell", "toggle", target]);
    }
    // A program by its command, or its Flatpak where that is how it came.
    function launch(cmd, flatpakId) {
        Quickshell.execDetached(["sh", "-c", "command -v \"$1\" >/dev/null 2>&1 && exec \"$1\" || exec flatpak run \"$2\"",
                                 "sh", cmd, flatpakId]);
        welcome.finished();
    }

    readonly property var cards: [
        { icon: "\u{f002}", title: I18n.tr("Find anything"),
          hint: I18n.tr("Apps, files, settings and sums. Type “install” and a name to get a new program."),
          keys: "Super+K", shown: true, act: () => welcome.shell("spotlight") },
        { icon: "\u{f003b}", title: I18n.tr("Your apps"),
          hint: I18n.tr("Everything installed, in one place."),
          keys: "Super+Space", shown: true, act: () => welcome.shell("launchpad") },
        { icon: "\u{f062e}", title: I18n.tr("Control Center"),
          hint: I18n.tr("Wi-Fi, Bluetooth, sound, VPN, Do Not Disturb."),
          keys: "Super+C", shown: true, act: () => welcome.shell("control", true) },
        { icon: "\u{f05b3}", title: I18n.tr("Windows programs"),
          hint: I18n.tr("Open an .exe or .msi from Files: it installs with Proton, and comes to the Launchpad."),
          keys: "", shown: true, act: () => welcome.openPage("winapps") },
        { icon: "\u{f11b}", title: I18n.tr("Games"),
          hint: I18n.tr("Steam and Heroic. Game Mode turns on by itself when a game asks for it."),
          keys: "", shown: welcome.has("steam", "com.valvesoftware.Steam"),
          act: () => welcome.launch("steam", "com.valvesoftware.Steam") },
        { icon: "\u{f0868}", title: I18n.tr("Other systems' apps"),
          hint: I18n.tr("Ubuntu, Fedora or Arch in a container, its programs in your Launchpad."),
          keys: "", shown: welcome.has("distrobox"),
          act: () => welcome.launch("boxbuddy-rs", "io.github.dvlv.boxbuddyrs") },
        { icon: "\u{f03d8}", title: I18n.tr("Make it yours"),
          hint: I18n.tr("Theme, accent colour, wallpaper."),
          keys: "", shown: true, act: () => welcome.openPage("appearance") },
        { icon: "\u{f11c}", title: I18n.tr("Keyboard shortcuts"),
          hint: I18n.tr("Every key, and changing them."),
          keys: "", shown: true, act: () => welcome.openPage("shortcuts") },
        { icon: "\u{f06b0}", title: I18n.tr("Updates"),
          hint: I18n.tr("The desktop and the system's packages, in one place."),
          keys: "", shown: true, act: () => welcome.shell("updater", true) }
    ]

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Design.s(Design.space.xl)
        spacing: Design.s(Design.space.lg)

        // ── Hello ───────────────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.xxs)
            Label {
                Layout.fillWidth: true
                text: I18n.tr("Welcome to b1air")
                role: "display"
                weight: Design.weight.semibold
            }
            Label {
                Layout.fillWidth: true
                text: welcome.edition !== ""
                    ? I18n.tr("The %1 edition. Here is where things are.", welcome.edition)
                    : I18n.tr("Here is where things are.")
                dim: true
                wrapMode: Text.WordWrap
            }
        }

        // ── Where things are ────────────────────────────────────────────────
        ScrollArea {
            id: scroll
            framed: false
            Layout.fillWidth: true
            Layout.fillHeight: true

            GridLayout {
                width: scroll.availableWidth
                columns: width > Design.s(Design.width.page) * 0.7 ? 3 : 2
                columnSpacing: Design.s(Design.space.sm)
                rowSpacing: Design.s(Design.space.sm)

                Repeater {
                    model: welcome.cards.filter(c => c.shown)

                    Box {
                        id: card
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        // One height for all: the heading and two lines of hint.
                        Layout.preferredHeight: Design.s(Design.size.stat) + Design.s(Design.size.knob)
                        radius: Design.s(Design.radius.card)
                        color: cardArea.containsMouse ? Design.stateHover : Design.glassCard
                        Behavior on color { ColorAnimation { duration: Design.duration.fast } }

                        ColumnLayout {
                            id: cardBody
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: Design.s(Design.space.md)
                            spacing: Design.s(Design.space.xs)

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Design.s(Design.space.sm)
                                Box {
                                    Layout.preferredWidth: Design.s(Design.size.knob)
                                    Layout.preferredHeight: Design.s(Design.size.knob)
                                    radius: width / 2
                                    color: Design.tint(Design.text, 0.10)
                                    Icon {
                                        anchors.centerIn: parent
                                        text: card.modelData.icon
                                        role: "title"
                                        color: Design.text
                                    }
                                }
                                Label {
                                    Layout.fillWidth: true
                                    text: card.modelData.title
                                    role: "subhead"
                                    weight: Design.weight.semibold
                                    elide: Text.ElideRight
                                }
                                Label {
                                    visible: card.modelData.keys !== ""
                                    text: card.modelData.keys
                                    role: "caption"
                                    isMono: true
                                    dim: true
                                }
                            }
                            Label {
                                Layout.fillWidth: true
                                text: card.modelData.hint
                                role: "footnote"
                                dim: true
                                wrapMode: Text.WordWrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                            }
                        }

                        Clickable {
                            id: cardArea
                            onClicked: card.modelData.act()
                        }
                    }
                }
            }
        }

        // ── Leaving ─────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.sm)

            CheckBox {
                text: I18n.tr("Show at login")
                checked: Settings.openGuideAtStartup === true
                onToggled: Settings.set("openGuideAtStartup", !(Settings.openGuideAtStartup === true))
            }
            Item { Layout.fillWidth: true }
            Button {
                label: I18n.tr("Set up again")
                tip: I18n.tr("Language, Wi-Fi, theme, wallpaper, account")
                onClicked: welcome.openPage("setup")
            }
            Button {
                variant: "primary"
                label: I18n.tr("Close")
                onClicked: welcome.finished()
            }
        }
    }
}
