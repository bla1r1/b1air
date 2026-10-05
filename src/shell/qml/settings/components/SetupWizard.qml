import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../Ui"
import "../../Services"

// =============================================================================
// First-run setup: the settings page called "setup".
//
// What install.sh used to decide for whoever ran it — the login shell, among
// other things — and what nobody was asked at all: language and keyboard,
// Wi-Fi, how it looks, the account, the fingerprint. Each step is the
// settings page itself (the part that matters on day one), so there is one
// place that sets a thing, and what is chosen here is what Settings shows.
//
// ~/.config/b1air/setup-done lists the steps already seen, one id a line.
// `b1air-settings --first-run` (autostart.conf) opens "setup.<id>.<id>…" with
// only the steps that are new and that this machine has the hardware for —
// so an update that adds a step shows that step, and the fingerprint step
// waits until there is a reader. Plain "setup" is all of them, by hand.
// update-dotfiles.sh marks the steps that came before this as seen.
// =============================================================================

Item {
    id: wizard

    // "setup" or "setup.keyboard.theme…", from SettingsApp's page.
    property string page: "setup"
    // Emitted on Finish or Skip, after the marker is written.
    signal finished()

    readonly property var catalog: [
        { id: "keyboard",    icon: "\u{f05ca}", title: I18n.tr("Language & keyboard"),
          hint: I18n.tr("The language of the desktop, and the layouts you type in") },
        { id: "network",     icon: "\u{f0928}", title: I18n.tr("Wi-Fi"),
          hint: I18n.tr("Join a network now, or later from the top bar"), when: Network.hasWifi },
        { id: "theme",       icon: "\u{f0765}", title: I18n.tr("Theme"),
          hint: I18n.tr("Colours for the desktop and every app in it") },
        { id: "wallpaper",   icon: "\u{f02ca}", title: I18n.tr("Wallpaper"),
          hint: I18n.tr("The picture behind your windows and on the login screen") },
        { id: "user",        icon: "\u{f007}",  title: I18n.tr("Your account"),
          hint: I18n.tr("Name, picture and the shell you log in with") },
        { id: "fingerprint", icon: "\u{f0237}", title: I18n.tr("Fingerprint"),
          hint: I18n.tr("Unlock the screen with a touch"), when: wizard.fpAvailable }
    ]

    readonly property var only: wizard.page.indexOf(".") > 0 ? wizard.page.split(".").slice(1) : []
    // Named steps were already checked for hardware by --first-run.
    readonly property var steps: wizard.only.length > 0
        ? wizard.catalog.filter(s => wizard.only.indexOf(s.id) >= 0)
        : wizard.catalog.filter(s => s.when === undefined || s.when)

    property int index: 0
    readonly property var step: wizard.steps.length > 0
        ? wizard.steps[Math.min(wizard.index, wizard.steps.length - 1)] : wizard.catalog[0]
    readonly property bool last: wizard.index >= wizard.steps.length - 1

    // A reader fprintd can drive; no reader, no step.
    property bool fpAvailable: false
    Process {
        running: true
        command: ["b1air-daemon", "fingerprint", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { wizard.fpAvailable = JSON.parse(this.text).available === true; } catch (e) {}
            }
        }
    }

    // Adds ids to the marker, each once.
    function markSeen(ids) {
        const list = ids.filter(i => /^[a-z]+$/.test(i)).join(" ");
        Quickshell.execDetached(["sh", "-c",
            "d=\"${XDG_CONFIG_HOME:-$HOME/.config}/b1air\"; mkdir -p \"$d\"; f=\"$d/setup-done\"; "
            + "for i in " + list + "; do grep -qx \"$i\" \"$f\" 2>/dev/null || echo \"$i\" >> \"$f\"; done"]);
    }

    function finish() {
        wizard.markSeen(wizard.steps.map(s => s.id));
        wizard.finished();
    }

    onIndexChanged: if (scroll.contentItem) scroll.contentItem.contentY = 0

    // A new language restarts the shell (Keyboard page), and the setup with
    // it when it is the shell's panel. The language step is done by then, so
    // it comes back, in the new language, with the steps still to go. A
    // standalone window closes for the new one.
    signal restarting()
    Connections {
        target: Settings
        function onUiLanguageChanged() {
            wizard.markSeen(["keyboard"]);
            Quickshell.execDetached(["sh", "-c", "sleep 2; exec b1air-settings --first-run"]);
            wizard.restarting();
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Design.s(Design.space.xl)
        spacing: Design.s(Design.space.lg)

        // ── Where you are ───────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.md)

            Rectangle {
                Layout.preferredWidth: Design.s(48)
                Layout.preferredHeight: Design.s(48)
                radius: Design.s(Design.radius.ctl)
                color: Design.tint(Design.accent, 0.18)
                Icon {
                    anchors.centerIn: parent
                    text: wizard.step.icon
                    role: "title"
                    color: Design.accent
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Design.s(2)
                Label {
                    Layout.fillWidth: true
                    text: wizard.index === 0 && wizard.step.id === "keyboard" ? I18n.tr("Welcome to b1air") + " — " + wizard.step.title : wizard.step.title
                    role: "display"
                    weight: Design.weight.bold
                    elide: Text.ElideRight
                }
                Label {
                    Layout.fillWidth: true
                    text: wizard.step.hint
                    dim: true
                    wrapMode: Text.WordWrap
                }
            }

            // Step dots, the current one long.
            Row {
                spacing: Design.s(6)
                Repeater {
                    model: wizard.steps.length
                    Rectangle {
                        required property int index
                        width: index === wizard.index ? Design.s(22) : Design.s(8)
                        height: Design.s(8)
                        radius: height / 2
                        color: index <= wizard.index ? Design.accent : Design.line
                        Behavior on width { NumberAnimation { duration: Design.duration.fast } }
                    }
                }
            }
        }

        // ── The step ────────────────────────────────────────────────────────
        ScrollView {
            id: scroll
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            ScrollBar.vertical: OverflowBar {}

            ColumnLayout {
                width: scroll.availableWidth
                spacing: Design.s(Design.space.lg)

                // One step built at a time, as SettingsApp does with pages.
                Loader {
                    Layout.fillWidth: true
                    active: wizard.step.id === "keyboard"
                    visible: active
                    sourceComponent: Component { KeyboardSettingsSection { essentials: true; width: parent ? parent.width : 0 } }
                }
                Loader {
                    Layout.fillWidth: true
                    active: wizard.step.id === "network"
                    visible: active
                    sourceComponent: Component { NetworkSettingsSection { essentials: true; width: parent ? parent.width : 0 } }
                }
                Loader {
                    Layout.fillWidth: true
                    active: wizard.step.id === "theme"
                    visible: active
                    sourceComponent: Component { ThemeSettingsSection { width: parent ? parent.width : 0 } }
                }
                Loader {
                    Layout.fillWidth: true
                    active: wizard.step.id === "wallpaper"
                    visible: active
                    sourceComponent: Component { WallpaperSettingsSection { width: parent ? parent.width : 0 } }
                }
                Loader {
                    Layout.fillWidth: true
                    active: wizard.step.id === "user"
                    visible: active
                    sourceComponent: Component { UserSettingsSection { part: "account"; width: parent ? parent.width : 0 } }
                }
                Loader {
                    Layout.fillWidth: true
                    active: wizard.step.id === "fingerprint"
                    visible: active
                    sourceComponent: Component { UserSettingsSection { part: "fingerprint"; width: parent ? parent.width : 0 } }
                }
            }
        }

        // ── Moving on ───────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.sm)

            Pill {
                label: I18n.tr("Skip setup")
                onClicked: wizard.finish()
            }
            Item { Layout.fillWidth: true }
            Pill {
                visible: wizard.index > 0
                label: I18n.tr("Back")
                icon: "\u{f004d}"
                onClicked: wizard.index--
            }
            Pill {
                active: true
                label: wizard.last ? I18n.tr("Finish") : I18n.tr("Next")
                icon: wizard.last ? "\u{f012c}" : "\u{f0054}"
                onClicked: {
                    if (wizard.last) wizard.finish();
                    else wizard.index++;
                }
            }
        }
    }
}
