import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import "../Ui"

// =============================================================================
// A Windows program opened from Files (b1air-shell open windows FILE, which
// b1air-windows open asks for): what it is — its own icon and name, read from
// the .exe — where it goes, with which Proton, and what to do with it.
//
//   Where: the shared bottle (recommended: one place, one set of components
//   for every program), another existing bottle, or a new one of its own
//   (for a game that wants another Proton, or breaks the others).
//   Proton: the newest GE-Proton, recommended, which also applies the umu
//   database's fixes for a title it knows; Valve's; or one already
//   downloaded. A bottle that exists keeps its own: a prefix goes forward
//   with Proton, not back.
//
//   An installer: Install; what it puts in its Start menu comes to the
//   Launchpad, and a notification says when. A program: Add to the
//   Launchpad, as it is. Either: Run once, leaving nothing behind.
//
// Each program's settings, and the bottles', are in Settings → Windows
// programs.
// =============================================================================
PopupShell {
    id: sheet

    property string filePath: ""
    property var info: null      // b1air-windows inspect
    property bool failed: false
    property bool started: false // Install pressed: the rest is notifications
    property var bottles: []     // b1air-windows bottles
    property var protons: []     // the versions downloaded (b1air-windows runtime)
    property string bottle: "default"   // a bottle's id, or "new"
    property string runner: "GE-Proton"

    readonly property var chosenBottle: sheet.bottles.find(b => b.id === sheet.bottle) || null
    // A bottle that exists keeps its own Proton; a new one, or the shared one
    // not made yet, takes the one picked here.
    readonly property bool runnerFree: sheet.bottle === "new" || !sheet.chosenBottle || !sheet.chosenBottle.made
    readonly property var recommended: sheet.info && sheet.info.recommended ? sheet.info.recommended
                                       : ({ bottle: "default", runner: "GE-Proton", reason: "general" })

    readonly property real contentHeight: body.implicitHeight + Design.s(sheet.padding) * 2

    onFilePathChanged: {
        sheet.info = null;
        sheet.failed = false;
        sheet.started = false;
        if (sheet.filePath !== "") reader.running = true;
    }
    Component.onCompleted: {
        if (sheet.filePath !== "") reader.running = true;
        bottleReader.running = true;
        runtimeReader.running = true;
    }

    Process {
        id: bottleReader
        command: ["b1air-windows", "bottles"]
        stdout: StdioCollector {
            onStreamFinished: { try { sheet.bottles = JSON.parse(this.text.trim()); } catch (e) {} }
        }
    }
    Process {
        id: runtimeReader
        command: ["b1air-windows", "runtime"]
        stdout: StdioCollector {
            onStreamFinished: { try { sheet.protons = JSON.parse(this.text.trim()).proton || []; } catch (e) {} }
        }
    }

    Process {
        id: reader
        command: ["b1air-windows", "inspect", sheet.filePath]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    sheet.info = JSON.parse(this.text.trim());
                    // What is recommended, until something else is picked.
                    sheet.bottle = sheet.recommended.bottle;
                    sheet.runner = sheet.recommended.runner;
                } catch (e) { sheet.failed = true; }
            }
        }
        onExited: code => { if (code !== 0) sheet.failed = true; }
    }

    function act(command) {
        const where = command === "once"
            ? (sheet.bottle !== "new" ? ["--bottle", sheet.bottle] : [])
            : sheet.bottle === "new" ? ["--new-bottle", sheet.info.name, "--runner", sheet.runner]
            : ["--bottle", sheet.bottle].concat(sheet.runnerFree ? ["--runner", sheet.runner] : []);
        Quickshell.execDetached(["b1air-windows", command, sheet.filePath].concat(where));
        if (command === "install") {
            sheet.started = true;
            closeSoon.restart();
        } else {
            sheet.close();
        }
    }
    Timer { id: closeSoon; interval: 2600; onTriggered: sheet.close() }

    function sizeText(bytes) {
        if (bytes >= 1073741824) return (bytes / 1073741824).toFixed(1) + " " + I18n.tr("GB");
        if (bytes >= 1048576) return Math.round(bytes / 1048576) + " " + I18n.tr("MB");
        return Math.max(1, Math.round(bytes / 1024)) + " " + I18n.tr("KB");
    }

    ColumnLayout {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Design.s(Design.space.lg)

        // ── What it is ───────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.md)

            Item {
                Layout.preferredWidth: Design.s(Design.size.stat)
                Layout.preferredHeight: Design.s(Design.size.stat)
                IconImage {
                    anchors.fill: parent
                    visible: !!(sheet.info && sheet.info.icon)
                    source: sheet.info && sheet.info.icon ? "file://" + sheet.info.icon : ""
                    mipmap: true
                }
                Rectangle {
                    anchors.fill: parent
                    visible: !(sheet.info && sheet.info.icon)
                    radius: Design.s(Design.radius.card)
                    color: Design.glassTile
                    Icon {
                        anchors.centerIn: parent
                        text: "\u{f05b3}"
                        role: "title"
                        color: Design.textDim
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Design.s(Design.space.xxs)
                Label {
                    Layout.fillWidth: true
                    text: sheet.info ? sheet.info.name
                        : sheet.failed ? I18n.tr("Can't read this file") : I18n.tr("Reading…")
                    role: "title"
                    weight: Design.weight.semibold
                    elide: Text.ElideRight
                }
                Label {
                    Layout.fillWidth: true
                    text: !sheet.info ? sheet.filePath.split("/").pop()
                        : [sheet.info.installer ? I18n.tr("Windows installer") : I18n.tr("Windows program"),
                           sheet.info.company, sheet.info.version, sheet.sizeText(sheet.info.size)]
                          .filter(s => s).join(" · ")
                    role: "caption"
                    dim: true
                    elide: Text.ElideRight
                }
            }
        }

        // ── Where, and with which Proton ─────────────────────────────────────
        GridLayout {
            Layout.fillWidth: true
            visible: !!sheet.info && !sheet.started
            columns: 2
            columnSpacing: Design.s(Design.space.md)
            rowSpacing: Design.s(Design.space.sm)

            Label { text: I18n.tr("Bottle"); role: "body" }
            Select {
                Layout.fillWidth: true
                model: sheet.bottles.map(b => ({
                            id: b.id,
                            label: b.id === sheet.recommended.bottle ? I18n.tr("%1 (recommended)", b.name) : b.name,
                            detail: b.apps.length > 0 ? I18n.trn("%1 program", "%1 programs", b.apps.length) : "" }))
                       .concat([{ id: "new", label: I18n.tr("A new bottle of its own") }])
                current: sheet.bottle
                onPicked: id => sheet.bottle = id
            }

            Label { text: I18n.tr("Proton"); role: "body" }
            Select {
                Layout.fillWidth: true
                enabled: sheet.runnerFree
                model: [{ id: "GE-Proton",
                          label: sheet.recommended.runner === "GE-Proton"
                                 ? I18n.tr("Newest GE-Proton (recommended)") : I18n.tr("Newest GE-Proton") },
                        { id: "UMU-Proton", label: I18n.tr("Valve's Proton") }]
                       .concat(sheet.protons.map(v => ({ id: v, label: v })))
                current: sheet.runnerFree ? sheet.runner : (sheet.chosenBottle ? sheet.chosenBottle.runner : sheet.runner)
                onPicked: id => sheet.runner = id
            }
        }

        // Why that, or what picking otherwise means.
        Label {
            Layout.fillWidth: true
            visible: !!sheet.info && !sheet.started
            text: !sheet.runnerFree
                ? I18n.tr("This bottle keeps its own Proton; change it in Settings → Windows programs.")
                : sheet.recommended.reason === "known" && sheet.runner === "GE-Proton"
                ? I18n.tr("The umu database knows this title: its fixes are applied by themselves.")
                : sheet.bottle === "new"
                ? I18n.tr("Its own space and Proton: for a game that needs another version, or that breaks other programs.")
                : I18n.tr("The shared bottle and the newest GE-Proton suit most programs, and share one set of components.")
            role: "caption"
            dim: true
            wrapMode: Text.WordWrap
        }

        // ── What happens ─────────────────────────────────────────────────────
        Label {
            Layout.fillWidth: true
            visible: !!sheet.info && (sheet.started || sheet.info.installer !== undefined)
            text: sheet.started
                ? I18n.tr("Installing. You can close this: when it is done, the program is in the Launchpad and a notification says so.")
                : sheet.info && sheet.info.installer
                ? I18n.tr("What it adds to its Start menu comes to the Launchpad.")
                : I18n.tr("Add it to the Launchpad to keep it, with its own settings, or just run it once.")
            role: "body"
            dim: !sheet.started
            wrapMode: Text.WordWrap
        }

        RowLayout {
            Layout.fillWidth: true
            visible: !!sheet.info && !sheet.started
            spacing: Design.s(Design.space.sm)

            Button {
                variant: "ghost"
                label: I18n.tr("Run once")
                tip: I18n.tr("In a shared space, without adding it anywhere")
                onClicked: sheet.act("once")
            }
            Item { Layout.fillWidth: true }
            Button {
                label: I18n.tr("Cancel")
                onClicked: sheet.close()
            }
            Button {
                variant: "primary"
                icon: sheet.info && sheet.info.installer ? "\u{f01da}" : "\u{f0415}"
                label: sheet.info && sheet.info.installer ? I18n.tr("Install") : I18n.tr("Add to Launchpad")
                onClicked: sheet.act(sheet.info && sheet.info.installer ? "install" : "add")
            }
        }

        Label {
            Layout.fillWidth: true
            visible: !!sheet.info && !sheet.started
            text: I18n.tr("Proton fetches itself the first time (a few hundred megabytes).")
            role: "caption"
            dim: true
            wrapMode: Text.WordWrap
        }

        Button {
            Layout.alignment: Qt.AlignRight
            visible: sheet.failed
            label: I18n.tr("Close")
            onClicked: sheet.close()
        }
    }
}
