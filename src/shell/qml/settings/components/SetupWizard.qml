import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../Ui"
import "../../Services"
import "."

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
//
// It looks like a Mac's Setup Assistant: the whole screen dimmed (the shell
// opens it as "setup", a full-screen panel), one card in the middle, "Hello"
// in one language after another first, a step a page with its question large
// at the top, Back and Continue at the foot, and "You're all set" last. The
// hello and the end come with the language step, which is to say after an
// install or by hand; an update's few new steps go straight to them.
// =============================================================================

Item {
    id: wizard

    // "setup" or "setup.keyboard.theme…", from SettingsApp's page.
    property string page: "setup"
    // Emitted on Finish or Skip, after the marker is written.
    signal finished()
    // A page named by the news: the setup is done, Settings goes there.
    signal openPage(string id)
    // The screen dimmed behind the card: in the shell's full-screen panel,
    // not in a window of its own.
    property bool backdrop: true

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
    // "hello", "steps" or "done": the greeting and the end are not steps,
    // there is nothing to mark seen in them.
    readonly property bool full: wizard.steps.some(s => s.id === "keyboard")
    property string stage: wizard.full ? "hello" : "steps"
    readonly property bool newsOnly: wizard.steps.length === 1 && wizard.steps[0].id === "news"
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
    function next() {
        if (wizard.stage === "hello") wizard.stage = "steps";
        else if (wizard.stage === "done") wizard.finish();
        else if (!wizard.last) wizard.index++;
        else if (wizard.newsOnly) wizard.finish();
        else wizard.stage = "done";
    }
    function back() {
        if (wizard.stage === "done") wizard.stage = "steps";
        else if (wizard.index > 0) wizard.index--;
        else if (wizard.full) wizard.stage = "hello";
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

    // ── The screen behind ───────────────────────────────────────────────────
    // Dimmed a little, as a sheet dims what is under it: light enough to stay
    // under qs-master's blur threshold (0.4), so the desktop shows through
    // sharp and only the card is frosted.
    Rectangle {
        anchors.fill: parent
        visible: wizard.backdrop
        color: Qt.rgba(0, 0, 0, Design.darkTheme ? 0.34 : 0.22)
        radius: wizard.width > card.width + Design.s(Design.space.xxl * 3) ? 0 : Design.s(Design.radius.panel)
    }

    // Over the desktop; on a window's own opaque ground its rings show.
    PanelShadow {
        visible: wizard.backdrop
        anchors.fill: card
        radius: card.radius
        spread: Design.s(Design.space.xxl * 2)
        drop: Design.s(Design.space.md)
        strength: Design.darkTheme ? 0.35 : 0.18
    }

    // The card: the desktop's glass, as every panel of it.
    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(parent.width - Design.s(Design.space.xl) * 2, Design.s(Design.width.dash + Design.width.control))
        height: Math.min(parent.height - Design.s(Design.space.xl) * 2, Design.s(Design.width.dash + Design.width.label))
        // Larger than a panel's, as a Mac's setup card is; written from the
        // window radius so a change to the panels' does not swell it.
        radius: Design.s(Design.radius.window + Design.space.sm)
        color: Design.glassBg
        border.width: Design.border
        border.color: Design.glassBorder
        clip: true

        // Light along the top edge, as on glass.
        Rectangle {
            anchors.fill: parent
            anchors.margins: Design.border
            radius: parent.radius - Design.border
            color: "transparent"
            border.width: Design.border
            border.color: Design.glassEdge
            opacity: 0.7
        }

        // ── Hello ───────────────────────────────────────────────────────────
        Item {
            id: hello
            anchors.fill: parent
            visible: wizard.stage === "hello"

            readonly property var words: ["Hello", "Привет", "Привіт", "Hola", "Bonjour", "Hallo", "Ciao", "Olá", "Cześć", "こんにちは", "안녕하세요", "你好"]
            property int at: 0
            Timer {
                running: hello.visible
                interval: 2200
                repeat: true
                onTriggered: fade.restart()
            }
            SequentialAnimation {
                id: fade
                NumberAnimation { target: word; property: "opacity"; to: 0; duration: 380; easing.type: Easing.InQuad }
                ScriptAction { script: hello.at = (hello.at + 1) % hello.words.length }
                NumberAnimation { target: word; property: "opacity"; to: 1; duration: 520; easing.type: Easing.OutQuad }
            }

            ColumnLayout {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -Design.s(Design.size.row)
                spacing: Design.s(Design.space.lg)
                Text {
                    id: word
                    Layout.alignment: Qt.AlignHCenter
                    text: hello.words[hello.at]
                    color: Design.text
                    font.family: Design.font.sans
                    font.pixelSize: Design.s(Design.font.jumbo * 0.8)
                    font.weight: Font.Light
                    font.letterSpacing: -Design.s(Design.space.xxs)
                }
                Label {
                    Layout.alignment: Qt.AlignHCenter
                    text: I18n.tr("Welcome to b1air")
                    role: "title"
                    dim: true
                }
            }

            // The round arrow under it, as on a Mac.
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: Design.s(Design.size.stat)
                width: Design.s(Design.size.tile)
                height: width
                radius: width / 2
                color: go.containsMouse ? Qt.lighter(Design.accent, 1.12) : Design.accent
                scale: go.pressed ? 0.94 : 1
                Behavior on scale { NumberAnimation { duration: Design.duration.fast } }
                Icon {
                    anchors.centerIn: parent
                    text: "\u{f0054}"
                    role: "title"
                    color: Design.accentText
                }
                Clickable { id: go; onClicked: wizard.next() }
            }
            Shortcut {
                sequences: ["Return", "Enter"]
                enabled: hello.visible
                onActivated: wizard.next()
            }
        }

        // ── A step ──────────────────────────────────────────────────────────
        ColumnLayout {
            anchors.fill: parent
            anchors.topMargin: Design.s(Design.size.header + Design.space.sm)
            anchors.bottomMargin: Design.s(Design.space.xl)
            anchors.leftMargin: Design.s(Design.space.xl)
            anchors.rightMargin: Design.s(Design.space.xl)
            visible: wizard.stage === "steps"
            spacing: Design.s(Design.space.lg)

            // The question, large, in the middle at the top.
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: Design.s(Design.size.tile + Design.space.sm)
                Layout.preferredHeight: Design.s(Design.size.tile + Design.space.sm)
                radius: width / 2
                color: "transparent"
                // Lit from above, as an app's icon.
                GradientRect {
                    anchors.fill: parent
                    radius: parent.radius
                    from: Qt.lighter(Design.accent, 1.3)
                    to: Design.accent
                }
                Icon {
                    anchors.centerIn: parent
                    text: wizard.step.icon
                    font.pixelSize: Design.s(Design.font.display)
                    color: Design.accentText
                }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Design.s(Design.space.xs)
                Label {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: wizard.step.title
                    role: "display"
                    weight: Design.weight.bold
                    elide: Text.ElideRight
                }
                Label {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.maximumWidth: Design.s(Design.width.dash)
                    horizontalAlignment: Text.AlignHCenter
                    text: wizard.step.hint
                    dim: true
                    wrapMode: Text.WordWrap
                }
            }

            ScrollView {
                id: scroll
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.topMargin: Design.s(Design.space.sm)
                clip: true
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                ScrollBar.vertical: OverflowBar { view: scroll }

                // The page in a column narrower than the card, as a Mac's
                // assistant keeps its controls in the middle.
                Item {
                    width: scroll.availableWidth
                    implicitHeight: pageColumn.implicitHeight

                    ColumnLayout {
                        id: pageColumn
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: Math.min(parent.width, Design.s(Design.width.dash + Design.size.row * 2))
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
                            sourceComponent: Component { UserSettingsSection { part: "setup"; width: parent ? parent.width : 0 } }
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
                                SettingsGroup {
                                    width: parent ? parent.width : 0
                                    title: I18n.tr("In Settings")
                                    icon: "\u{f0394}"
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
                                            Button {
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
            }

            // ── Moving on ───────────────────────────────────────────────────
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: Design.s(Design.size.md)

                Button {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    variant: "ghost"
                    label: I18n.tr("Skip setup")
                    onClicked: wizard.finish()
                }

                // Where you are: a dot a step, the current one long.
                Row {
                    anchors.centerIn: parent
                    spacing: Design.s(Design.space.xs)
                    visible: wizard.steps.length > 1
                    Repeater {
                        model: wizard.steps.length
                        Rectangle {
                            required property int index
                            width: index === wizard.index ? Design.s(Design.size.mini) : Design.s(Design.space.sm)
                            height: Design.s(Design.space.sm)
                            radius: height / 2
                            color: index <= wizard.index ? Design.accent : Design.line
                            Behavior on width { NumberAnimation { duration: Design.duration.fast } }
                        }
                    }
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Design.s(Design.space.sm)
                    Button {
                        visible: wizard.index > 0 || wizard.full
                        width: Math.max(implicitWidth, Design.s(Design.width.field))
                        radius: height / 2
                        label: I18n.tr("Back")
                        onClicked: wizard.back()
                    }
                    Button {
                        variant: "primary"
                        width: Math.max(implicitWidth, Design.s(Design.width.field))
                        radius: height / 2
                        label: wizard.last && wizard.newsOnly ? I18n.tr("Finish") : I18n.tr("Continue")
                        onClicked: wizard.next()
                    }
                }
            }
        }

        // ── You're all set ──────────────────────────────────────────────────
        Item {
            anchors.fill: parent
            visible: wizard.stage === "done"

            ColumnLayout {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -Design.s(Design.size.row)
                width: Math.min(parent.width - Design.s(Design.space.xl) * 2, Design.s(Design.width.dash - Design.size.row))
                spacing: Design.s(Design.space.lg)

                Rectangle {
                    id: tick
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: Design.s(Design.size.avatar)
                    Layout.preferredHeight: Design.s(Design.size.avatar)
                    radius: width / 2
                    color: Design.ok
                    scale: 0.6
                    opacity: 0
                    Icon {
                        anchors.centerIn: parent
                        text: "\u{f012c}"
                        font.pixelSize: Design.s(Design.font.hero)
                        color: "white"
                    }
                    states: State {
                        when: wizard.stage === "done"
                        PropertyChanges { target: tick; scale: 1; opacity: 1 }
                    }
                    transitions: Transition {
                        NumberAnimation { properties: "scale,opacity"; duration: 420; easing.type: Easing.OutBack }
                    }
                }
                Label {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: I18n.tr("You're all set")
                    role: "display"
                    weight: Design.weight.bold
                }
                Label {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: I18n.tr("All of it stays in Settings, to change whenever you like.")
                    dim: true
                    wrapMode: Text.WordWrap
                }
            }

            Row {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: Design.s(Design.space.xl)
                spacing: Design.s(Design.space.sm)
                Button {
                    width: Math.max(implicitWidth, Design.s(Design.width.field))
                    radius: height / 2
                    label: I18n.tr("Back")
                    onClicked: wizard.back()
                }
                Button {
                    variant: "primary"
                    width: Math.max(implicitWidth, Design.s(Design.width.field))
                    radius: height / 2
                    label: I18n.tr("Start using b1air")
                    onClicked: wizard.finish()
                }
            }
            Shortcut {
                sequences: ["Return", "Enter"]
                enabled: wizard.stage === "done"
                onActivated: wizard.finish()
            }
        }
    }
}
