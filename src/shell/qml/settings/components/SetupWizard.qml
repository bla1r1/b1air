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
// ../setup-steps.json is the list of steps, each with a version, and the news
// of each release; b1air-settings reads the same file. ~/.config/b1air/
// setup-done holds what this account has seen, a line each: "keyboard@2",
// "news@0.2.2" ("keyboard" alone, from before versions, is version 1).
// `b1air-settings --first-run` (autostart.conf) opens "setup.<id>.<id>…" with
// only the steps that are new or newer than the one seen, and that this
// machine has the hardware for, and ".news" after an update with news — so an
// update shows what it changed, and the fingerprint step waits until there is
// a reader. Plain "setup" is every step, by hand.
// `b1air-settings --setup-baseline` (update-dotfiles.sh) marks the steps an
// account set up by hand before there was a setup.
// =============================================================================

Item {
    id: wizard

    // "setup" or "setup.keyboard.theme…", from SettingsApp's page.
    property string page: "setup"
    // Emitted on Finish or Skip, after the marker is written.
    signal finished()
    // A page named by the news: the setup is done, Settings goes there.
    signal openPage(string id)

    readonly property var catalog: [
        { id: "keyboard",    icon: "\u{f05ca}", title: I18n.tr("Language & keyboard"),
          hint: I18n.tr("The language of the desktop and of other programs, the formats, and the layouts you type in") },
        { id: "network",     icon: "\u{f0928}", title: I18n.tr("Wi-Fi"),
          hint: I18n.tr("Join a network now, or later from the top bar"), when: Network.hasWifi },
        { id: "theme",       icon: "\u{f0765}", title: I18n.tr("Theme"),
          hint: I18n.tr("Colours for the desktop and every app in it") },
        { id: "wallpaper",   icon: "\u{f02ca}", title: I18n.tr("Wallpaper"),
          hint: I18n.tr("The picture behind your windows and on the login screen") },
        { id: "user",        icon: "\u{f007}",  title: I18n.tr("Your account"),
          hint: I18n.tr("Name, picture and the shell you log in with") },
        { id: "fingerprint", icon: "\u{f0237}", title: I18n.tr("Fingerprint"),
          hint: I18n.tr("Unlock the screen with a touch"), when: wizard.fpAvailable },
        // Only when named: --first-run adds it after an update.
        { id: "news",        icon: "\u{f0394}", title: I18n.tr("What's new"),
          hint: I18n.tr("This update added these; each opens where it is set"), when: false }
    ]

    // ── setup-steps.json and setup-done ─────────────────────────────────────
    property var spec: ({ steps: [], news: [] })
    FileView {
        path: String(Qt.resolvedUrl("../setup-steps.json")).replace(/^file:\/\//, "")
        printErrors: false
        onLoaded: {
            try { wizard.spec = JSON.parse(text()); } catch (e) {}
        }
    }
    readonly property string markerPath: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/b1air/setup-done"
    property var seenNews: []
    FileView {
        path: wizard.markerPath
        printErrors: false
        onLoaded: wizard.seenNews = String(text() || "").split("\n")
            .filter(l => l.indexOf("news@") === 0).map(l => l.slice(5))
    }
    function versionOf(id) {
        const s = (wizard.spec.steps || []).find(x => x.id === id);
        return s && s.version ? s.version : 1;
    }
    // The news not seen yet, newest release first, items flattened.
    readonly property var news: {
        const out = [];
        for (const n of (wizard.spec.news || []).slice().reverse()) {
            if (wizard.seenNews.indexOf(n.id) >= 0) continue;
            for (const it of (n.items || [])) out.push(it);
        }
        return out;
    }

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

    // Adds lines to the marker, each once: steps at their version, and the
    // news. Finishing marks all news seen — after an install too, where
    // everything is new and none of it news.
    function markSeen(ids) {
        const lines = ids.filter(i => /^[a-z]+$/.test(i) && i !== "news").map(i => i + "@" + wizard.versionOf(i));
        for (const n of (wizard.spec.news || []))
            if (/^[0-9A-Za-z.-]+$/.test(n.id)) lines.push("news@" + n.id);
        const list = lines.join(" ");
        Quickshell.execDetached(["sh", "-c",
            "d=\"${XDG_CONFIG_HOME:-$HOME/.config}/b1air\"; mkdir -p \"$d\"; f=\"$d/setup-done\"; "
            + "for i in " + list + "; do grep -qx \"$i\" \"$f\" 2>/dev/null || echo \"$i\" >> \"$f\"; done"]);
    }

    function finish() {
        wizard.markSeen(wizard.steps.map(s => s.id));
        wizard.finished();
    }
    // A page the news names: Settings goes there, with a way back to the
    // news (SettingsApp's returnPage). Nothing is marked seen: that is Finish.
    function finishAt(id) {
        wizard.openPage(id);
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
            // Not the news: markSeen would mark it, and it comes after.
            Quickshell.execDetached(["sh", "-c",
                "d=\"${XDG_CONFIG_HOME:-$HOME/.config}/b1air\"; mkdir -p \"$d\"; echo keyboard@" + wizard.versionOf("keyboard") + " >> \"$d/setup-done\""]);
            // Back once the new shell is up: a fixed two seconds came too soon
            // as often as not — the setup asked a shell still loading and
            // nothing opened. Waits for a shell process other than this one,
            // then for it to load; ten seconds at most.
            Quickshell.execDetached(["sh", "-c",
                "old=$(pgrep -xo quickshell); i=0; "
                + "while [ $i -lt 40 ]; do new=$(pgrep -xo quickshell); "
                + "[ -n \"$new\" ] && [ \"$new\" != \"$old\" ] && break; sleep 0.25; i=$((i+1)); done; "
                + "sleep 2.5; exec b1air-settings --first-run"]);
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
            ScrollBar.vertical: OverflowBar { view: scroll }

            ColumnLayout {
                width: scroll.availableWidth
                spacing: Design.s(Design.space.lg)

                // One step built at a time, as SettingsApp does with pages.
                // The languages and formats, then the keyboard: two loaders,
                // as every other step's section is, rather than one layout
                // holding both.
                Loader {
                    Layout.fillWidth: true
                    active: wizard.step.id === "keyboard"
                    visible: active
                    sourceComponent: Component { RegionSettingsSection { width: parent ? parent.width : 0 } }
                }
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
                Loader {
                    Layout.fillWidth: true
                    active: wizard.step.id === "news"
                    visible: active
                    sourceComponent: Component {
                        Card {
                            width: parent ? parent.width : 0
                            title: I18n.tr("In Settings")
                            icon: "\u{f0394}"
                            accentColor: Design.accent
                            Repeater {
                                model: wizard.news
                                delegate: RowLayout {
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: Design.s(Design.space.md)
                                    Label {
                                        Layout.fillWidth: true
                                        text: I18n.tr(modelData.text)
                                        wrapMode: Text.WordWrap
                                    }
                                    Pill {
                                        visible: !!modelData.page
                                        label: I18n.tr("Open")
                                        icon: "\u{f0054}"
                                        onClicked: wizard.finishAt(modelData.page)
                                    }
                                }
                            }
                        }
                    }
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
