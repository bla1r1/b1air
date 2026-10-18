import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import "../../Ui"
import "../../Services"

// =============================================================================
// Windows programs (src/scripts/b1air-windows): Proton, the bottles, and each
// program installed or added from Files.
//
// A bottle is a Wine prefix with its Proton and its Windows components; most
// programs share one. Here: each bottle's Proton, its components, Wine's own
// settings for it, and removing it with what is in it. Each program: its
// options (they are its own, even in a shared bottle), its log, and removing
// it — alone in its bottle the bottle goes with it, sharing one its own
// uninstaller runs. An installer that made no Start menu shortcut shows the
// programs it left, to pick the one to start.
// =============================================================================
ColumnLayout {
    id: section

    Layout.fillWidth: true
    spacing: Design.s(Design.space.lg)

    property var apps: []
    property var bottles: []
    property bool loaded: false
    property var runtime: ({ umu: "", proton: [], ntsync: false })
    property string expanded: ""

    function refresh() {
        lister.running = true;
        bottleReader.running = true;
        runtimeReader.running = true;
    }
    function bottleName(id) {
        const b = section.bottles.find(x => x.id === id);
        return b ? b.name : id;
    }
    Component.onCompleted: refresh()

    Process {
        id: lister
        command: ["b1air-windows", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { section.apps = JSON.parse(this.text.trim()); } catch (e) { section.apps = []; }
                section.loaded = true;
            }
        }
        onExited: code => { if (code !== 0) section.loaded = true; }
    }
    Process {
        id: bottleReader
        command: ["b1air-windows", "bottles"]
        stdout: StdioCollector {
            onStreamFinished: { try { section.bottles = JSON.parse(this.text.trim()); } catch (e) {} }
        }
    }
    Process {
        id: runtimeReader
        command: ["b1air-windows", "runtime"]
        stdout: StdioCollector {
            onStreamFinished: { try { section.runtime = JSON.parse(this.text.trim()); } catch (e) {} }
        }
    }
    // A change made here, then the list again; a second time a moment later
    // for what runs detached (an update, a component).
    function run(args) {
        Quickshell.execDetached(["b1air-windows"].concat(args));
        again.restart();
    }
    Timer { id: again; interval: 700; onTriggered: section.refresh() }

    function sizeText(bytes) {
        if (bytes >= 1073741824) return (bytes / 1073741824).toFixed(1) + " " + I18n.tr("GB");
        return Math.max(1, Math.round(bytes / 1048576)) + " " + I18n.tr("MB");
    }

    // The components most programs ask for, as winetricks names them.
    readonly property var components: [
        { id: "vcrun2022", label: I18n.tr("Visual C++ 2015–2022") },
        { id: "dotnet48", label: I18n.tr(".NET Framework 4.8") },
        { id: "corefonts", label: I18n.tr("Windows fonts") },
        { id: "d3dcompiler_47", label: I18n.tr("D3D compiler") },
        { id: "xact", label: I18n.tr("XAudio (old games)") }
    ]

    // ── Proton ───────────────────────────────────────────────────────────────
    SettingsGroup {
        title: I18n.tr("Proton")
        icon: "\u{f05b3}"
        note: I18n.tr("Windows programs run with Proton, the Wine Valve makes for Steam, through umu-launcher. Open a .exe or .msi in Files to install or add one.")

        SettingsRow {
            label: section.runtime.proton.length > 0 ? section.runtime.proton[0]
                 : I18n.tr("Not downloaded yet")
            note: section.runtime.proton.length > 0
                ? I18n.tr("Kept up to date: a newer GE-Proton is fetched when there is one.")
                : !section.runtime.umu ? I18n.tr("umu-launcher is fetched with it, the first time a program runs.")
                : I18n.tr("Fetched the first time a program runs, a few hundred megabytes.")
            Button {
                size: "sm"
                icon: "\u{f06b0}"
                label: section.runtime.proton.length > 0 ? I18n.tr("Update") : I18n.tr("Download")
                onClicked: section.run(["runtime", "update"])
            }
        }
        SettingsRow {
            label: I18n.tr("ntsync")
            note: section.runtime.ntsync
                ? I18n.tr("On: Windows' synchronisation in the kernel, for smoother games.")
                : I18n.tr("Off: it needs Linux 6.14 or newer. Proton uses fsync meanwhile.")
            Icon {
                text: section.runtime.ntsync ? "\u{f012c}" : "\u{f0026}"
                color: section.runtime.ntsync ? Design.ok : Design.textDim
            }
        }
    }

    // ── Bottles ──────────────────────────────────────────────────────────────
    Repeater {
        model: section.bottles.filter(b => b.made)

        delegate: SettingsGroup {
            id: bottleGroup
            required property var modelData
            readonly property var bottle: modelData
            Layout.fillWidth: true
            title: bottle.shared ? I18n.tr("%1 · for every program", bottle.name) : bottle.name
            icon: "\u{f1363}"
            note: [bottle.apps.length > 0 ? bottle.apps.map(a => a.name).join(", ") : I18n.tr("No programs in it"),
                   section.sizeText(bottle.size)].join(" · ")

            SettingsRow {
                label: I18n.tr("Proton version")
                note: I18n.tr("Its programs all run with it. Going back to an older one can break what is installed.")
                Select {
                    model: [{ id: "GE-Proton", label: I18n.tr("Newest GE-Proton (recommended)") },
                            { id: "UMU-Proton", label: I18n.tr("Valve's Proton") }]
                           .concat(section.runtime.proton.map(v => ({ id: v, label: v })))
                    current: bottleGroup.bottle.runner || "GE-Proton"
                    onPicked: id => section.run(["bottle-set", bottleGroup.bottle.id, "runner", id])
                }
            }

            // Windows components, each installed once into the bottle, for
            // every program in it.
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Design.s(Design.space.xs)
                Label {
                    text: I18n.tr("Windows components")
                    role: "caption"
                    dim: true
                }
                Flow {
                    Layout.fillWidth: true
                    spacing: Design.s(Design.space.xs)
                    Repeater {
                        model: section.components
                        delegate: Chip {
                            required property var modelData
                            readonly property bool installed: (bottleGroup.bottle.deps || []).indexOf(modelData.id) >= 0
                            label: modelData.label
                            icon: installed ? "\u{f012c}" : "\u{f0415}"
                            active: installed
                            onClicked: if (!installed) section.run(["deps", bottleGroup.bottle.id, modelData.id])
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Design.s(Design.space.sm)
                Button {
                    size: "sm"
                    variant: "ghost"
                    label: I18n.tr("Wine settings")
                    onClicked: Quickshell.execDetached(["b1air-windows", "config", bottleGroup.bottle.id])
                }
                Item { Layout.fillWidth: true }
                Button {
                    size: "sm"
                    variant: "danger"
                    destructive: true
                    label: I18n.tr("Remove bottle")
                    confirmText: bottleGroup.bottle.apps.length > 0
                        ? I18n.trn("Remove it and %1 program?", "Remove it and %1 programs?", bottleGroup.bottle.apps.length)
                        : I18n.tr("Sure?")
                    onActivated: section.run(["bottle-remove", bottleGroup.bottle.id])
                }
            }
        }
    }

    // ── Nothing yet ──────────────────────────────────────────────────────────
    Item {
        Layout.fillWidth: true
        Layout.preferredHeight: Design.s(Design.size.thumb)
        visible: section.apps.length === 0
        AppState {
            anchors.fill: parent
            mode: !section.loaded ? "loading" : "empty"
            icon: "\u{f05b3}"
            title: !section.loaded ? I18n.tr("Loading…") : I18n.tr("No Windows programs yet")
            hint: I18n.tr("Open an installer (.exe or .msi) from Files: it installs here, and its programs come to the Launchpad.")
        }
    }

    // ── Each program ─────────────────────────────────────────────────────────
    Repeater {
        model: section.apps

        delegate: SettingsGroup {
            id: group
            required property var modelData
            readonly property var app: modelData
            readonly property bool open: section.expanded === app.slug
            readonly property var opt: app.options || ({})
            Layout.fillWidth: true

            // Its icon, its name, what it takes on disk, and the actions.
            RowLayout {
                Layout.fillWidth: true
                spacing: Design.s(Design.space.md)

                Item {
                    Layout.preferredWidth: Design.s(Design.size.md)
                    Layout.preferredHeight: Design.s(Design.size.md)
                    IconImage {
                        anchors.fill: parent
                        readonly property string icon: group.app.launchers.length > 0 ? (group.app.launchers[0].icon || "") : ""
                        visible: icon !== ""
                        source: icon !== "" ? "file://" + icon : ""
                        mipmap: true
                    }
                    Icon {
                        anchors.centerIn: parent
                        visible: !(group.app.launchers.length > 0 && group.app.launchers[0].icon)
                        text: "\u{f05b3}"
                        color: Design.textDim
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Label {
                        Layout.fillWidth: true
                        text: group.app.name
                        role: "body"
                        weight: Design.weight.semibold
                        elide: Text.ElideRight
                    }
                    Label {
                        Layout.fillWidth: true
                        text: [group.app.launchers.length > 1
                                   ? I18n.trn("%1 program", "%1 programs", group.app.launchers.length)
                                   : group.app.launchers.length === 0 ? I18n.tr("Pick what to start") : "",
                               I18n.tr("in %1", section.bottleName(group.app.bottle)),
                               group.app.gameid !== "0" ? I18n.tr("fixes from the umu database") : ""]
                              .filter(s => s).join(" · ")
                        role: "caption"
                        dim: true
                        elide: Text.ElideRight
                    }
                }
                Button {
                    size: "sm"
                    visible: group.app.launchers.length > 0
                    icon: "\u{f040a}"
                    label: I18n.tr("Open")
                    onClicked: Quickshell.execDetached(["b1air-windows", "run", group.app.slug])
                }
                IconButton {
                    icon: group.open ? "\u{f0143}" : "\u{f0140}"
                    onClicked: section.expanded = group.open ? "" : group.app.slug
                }
            }

            // Installed, and no shortcut: the .exe files it left.
            ColumnLayout {
                Layout.fillWidth: true
                visible: group.app.launchers.length === 0 && group.app.candidates.length > 0
                spacing: Design.s(Design.space.xs)
                Label {
                    text: I18n.tr("The installer made no shortcut. Which of these is the program?")
                    role: "caption"
                    dim: true
                }
                Repeater {
                    model: group.app.candidates
                    delegate: Button {
                        required property string modelData
                        Layout.fillWidth: true
                        size: "sm"
                        variant: "ghost"
                        label: modelData.split("/").slice(-2).join(" / ")
                        onClicked: section.run(["pick", group.app.slug, modelData])
                    }
                }
            }

            // ── Its settings ─────────────────────────────────────────────────
            SwitchRow {
                visible: group.open
                label: I18n.tr("A game")
                note: I18n.tr("In the Launchpad's Games")
                checked: !!group.opt.game
                onToggled: section.run(["set", group.app.slug, "game", group.opt.game ? "off" : "on"])
            }
            SwitchRow {
                visible: group.open
                label: I18n.tr("DirectX over Vulkan (DXVK)")
                note: I18n.tr("Faster, and what most games need. Off: Wine's own, for a program that draws wrongly with it.")
                checked: group.opt.dxvk !== false
                onToggled: section.run(["set", group.app.slug, "dxvk", group.opt.dxvk !== false ? "off" : "on"])
            }
            SwitchRow {
                visible: group.open
                label: I18n.tr("Native Wayland")
                note: I18n.tr("Sharp on scaled screens, without XWayland. Still new: turn it off if the program misbehaves.")
                checked: !!group.opt.wayland
                onToggled: section.run(["set", group.app.slug, "wayland", group.opt.wayland ? "off" : "on"])
            }
            SwitchRow {
                visible: group.open
                label: I18n.tr("HDR")
                note: I18n.tr("For games that have it, on a screen that has it (with Native Wayland)")
                checked: !!group.opt.hdr
                onToggled: section.run(["set", group.app.slug, "hdr", group.opt.hdr ? "off" : "on"])
            }
            SwitchRow {
                visible: group.open
                label: I18n.tr("AMD FSR upscaling")
                note: I18n.tr("A fullscreen game at a lower resolution, scaled up sharply")
                checked: !!group.opt.fsr
                onToggled: section.run(["set", group.app.slug, "fsr", group.opt.fsr ? "off" : "on"])
            }
            SwitchRow {
                visible: group.open
                label: I18n.tr("Performance overlay (MangoHud)")
                checked: !!group.opt.mangohud
                onToggled: section.run(["set", group.app.slug, "mangohud", group.opt.mangohud ? "off" : "on"])
            }
            SwitchRow {
                visible: group.open
                label: I18n.tr("Game Mode while it runs")
                note: I18n.tr("Feral's gamemode: the CPU and GPU at full speed")
                checked: !!group.opt.gamemode
                onToggled: section.run(["set", group.app.slug, "gamemode", group.opt.gamemode ? "off" : "on"])
            }
            SwitchRow {
                visible: group.open
                label: I18n.tr("In gamescope")
                note: I18n.tr("A compositor of its own, for games that will not go fullscreen or scale properly")
                checked: !!group.opt.gamescope
                onToggled: section.run(["set", group.app.slug, "gamescope", group.opt.gamescope ? "off" : "on"])
            }
            RowLayout {
                Layout.fillWidth: true
                visible: group.open
                spacing: Design.s(Design.space.sm)
                Button {
                    size: "sm"
                    variant: "ghost"
                    visible: group.app.log !== ""
                    label: I18n.tr("Last run's log")
                    onClicked: Quickshell.execDetached(["xdg-open", group.app.log])
                }
                Item { Layout.fillWidth: true }
                Button {
                    size: "sm"
                    variant: "danger"
                    destructive: true
                    label: I18n.tr("Remove")
                    // Alone in its bottle, the bottle goes too; sharing one,
                    // its uninstaller runs (and may ask things).
                    readonly property var inBottle: section.bottles.find(b => b.id === group.app.bottle)
                    readonly property bool alone: !!inBottle && !inBottle.shared && inBottle.apps.length <= 1
                    confirmText: alone ? I18n.tr("Remove with its bottle?")
                               : group.app.uninstaller ? I18n.tr("Run its uninstaller?") : I18n.tr("Remove from the Launchpad?")
                    onActivated: section.run(["remove", group.app.slug])
                }
            }
        }
    }
}
