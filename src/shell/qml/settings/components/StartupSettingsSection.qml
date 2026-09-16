import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import "../../Ui"
import "../../Services"
import "../../Services" as Services

// =============================================================================
// Startup & Services Manager (Dynamic App Picker & Custom Commands)
// =============================================================================

ColumnLayout {
    id: section

    Layout.fillWidth: true
    spacing: Design.s(Design.space.lg)

    property var autostartCustom: Settings.autostartCustom || []
    property bool openGuideAtStartup: Settings.openGuideAtStartup || false
    property bool showAppPicker: false
    property string appSearchQuery: ""

    readonly property ListModel allInstalledApps: ListModel {}

    // The installed-app scan is shared with the launchers via Services/Apps —
    // this page used to run its own `b1air-daemon apps all` alongside them.
    function rebuildInstalledApps() {
        section.allInstalledApps.clear();
        for (const app of Services.Apps.list) {
            section.allInstalledApps.append({
                name: app.name,
                exec: app.exec,
                desktopFile: app.desktopFile,
                icon: app.icon,
                comment: app.comment || ""
            });
        }
    }

    Component.onCompleted: section.rebuildInstalledApps()

    Connections {
        target: Services.Apps
        function onListChanged() { section.rebuildInstalledApps(); }
    }

    property string customError: ""

    /**
     * The session runs these through a shell but refuses anything with shell
     * syntax in it (session_manager.cpp, safe_custom_command), silently. Say
     * so here instead of saving an entry that will never start. Field codes
     * from a desktop file's Exec line (%u, %F…) are dropped: they are for a
     * launcher to fill in, and the daemon strips them too.
     */
    function cleanCommand(cmd) {
        return String(cmd || "").trim().split(/\s+/).filter(w => !/^%[a-zA-Z]$/.test(w)).join(" ");
    }

    function addCustomApp(name, cmd, icon) {
        const command = section.cleanCommand(cmd);
        if (!name.trim() || !command) return;
        if (/[;&|`$<>'"(){}\\]/.test(command)) {
            section.customError = "Startup commands cannot contain shell syntax (quotes, $, ;, |, & …). "
                + "Put it in a script and add the script instead.";
            return;
        }
        section.customError = "";
        var list = (section.autostartCustom || []).slice();
        list.push({
            name: name.trim(),
            command: command,
            icon: icon || "",
            enabled: true
        });
        section.autostartCustom = list;
        Settings.set("autostartCustom", list);
        customNameInput.text = "";
        customCmdInput.text = "";
        section.showAppPicker = false;
    }

    function toggleCustomApp(index) {
        var list = (section.autostartCustom || []).slice();
        if (index >= 0 && index < list.length) {
            list[index].enabled = !list[index].enabled;
            section.autostartCustom = list;
            Settings.set("autostartCustom", list);
        }
    }

    function removeCustomApp(index) {
        var list = (section.autostartCustom || []).slice();
        if (index >= 0 && index < list.length) {
            list.splice(index, 1);
            section.autostartCustom = list;
            Settings.set("autostartCustom", list);
        }
    }

    // A "Desktop Environment Services" card stood here with switches for the
    // shell, the top bar and the polkit agent. They wrote "quickshell" and
    // "polkit" into autostartApps, which the session never looks at for those
    // two — it always starts both, as it has to: the switch for the shell was
    // drawn by the shell. The bar and the shell also shared one id, so the two
    // switches moved together. Removed rather than wired to something that
    // would let you switch the desktop off from inside itself.

    // ── 2. Applications Autostart ────────────────────────────────────────────
    Card {
        title: "Autostart Applications"
        subtitle: "Launch your favourite applications, background daemons, and scripts on login"
        icon: "\u{f009}"
        accentColor: Design.mauve

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.md)

            // Header Action: Choose from installed applications
            RowLayout {
                Layout.fillWidth: true
                spacing: Design.s(Design.space.sm)

                Label {
                    text: "Startup Programs"
                    weight: Design.weight.bold
                    role: "subhead"
                    Layout.fillWidth: true
                }

                ActionButton {
                    Layout.fillWidth: false
                    icon: "󰐕"
                    label: section.showAppPicker ? "Close App List" : "Add Installed App…"
                    tone: Design.sapphire
                    onActivated: section.showAppPicker = !section.showAppPicker
                }
            }

            // ── Installed Apps Search & Picker Grid (Expanded on demand) ──────
            Rectangle {
                visible: section.showAppPicker
                Layout.fillWidth: true
                Layout.preferredHeight: Design.s(220)
                radius: Design.s(Design.radius.card)
                color: Design.ground
                border.color: Design.glassBorder
                border.width: 1

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Design.s(Design.space.sm)
                    spacing: Design.s(Design.space.xs)

                    // Search input
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Design.s(32)
                        radius: Design.s(Design.radius.ctl)
                        color: Design.surface
                        border.color: appSearchInput.activeFocus ? Design.sapphire : Design.tint(Design.line, 0.4)
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: Design.s(6)
                            spacing: Design.s(6)

                            Icon { text: "󰍉"; role: "caption"; color: Design.textDim }

                            TextInput {
                                id: appSearchInput
                                Layout.fillWidth: true
                                color: Design.text
                                font.pixelSize: Design.font.caption
                                clip: true
                                selectByMouse: true
                                onTextChanged: section.appSearchQuery = text.toLowerCase()
                                Text {
                                    text: "Search installed applications..."
                                    color: Design.textDim
                                    visible: !appSearchInput.text && !appSearchInput.activeFocus
                                    anchors.fill: parent
                                    font: appSearchInput.font
                                }
                            }
                        }
                    }

                    // App ListView
                    ListView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true
                        spacing: Design.s(4)
                        model: section.allInstalledApps

                        delegate: Rectangle {
                            id: appPickerItem
                            required property var model
                            required property int index

                            visible: section.appSearchQuery === "" ||
                                     appPickerItem.model.name.toLowerCase().includes(section.appSearchQuery) ||
                                     appPickerItem.model.exec.toLowerCase().includes(section.appSearchQuery)

                            width: ListView.view ? ListView.view.width : 0
                            height: visible ? Design.s(36) : 0
                            radius: Design.s(6)
                            color: pickerMa.containsMouse ? Design.glassHover : "transparent"

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: Design.s(6)
                                spacing: Design.s(8)

                                Image {
                                    Layout.preferredWidth: Design.s(20)
                                    Layout.preferredHeight: Design.s(20)
                                    // Decoded at the size drawn, not the file's (a 4K picture is 33 MB of pixels).
                                    sourceSize: Qt.size(64, 64)
                                    source: appPickerItem.model.icon ? (appPickerItem.model.icon.startsWith("/") ? "file://" + appPickerItem.model.icon : "image://icon/" + appPickerItem.model.icon) : ""
                                    visible: source.toString() !== ""
                                    fillMode: Image.PreserveAspectFit
                                }

                                Icon {
                                    visible: !parent.children[0].visible
                                    text: "󰄛"
                                    role: "caption"
                                    color: Design.sapphire
                                }

                                Label {
                                    text: appPickerItem.model.name
                                    weight: Design.weight.semibold
                                    role: "caption"
                                    elide: Text.ElideRight
                                    Layout.preferredWidth: Design.s(140)
                                }

                                Label {
                                    text: appPickerItem.model.exec
                                    role: "caption"
                                    dim: true
                                    isMono: true
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }

                                ActionButton {
                                    icon: "󰐕"
                                    label: "Add"
                                    tone: Design.sapphire
                                    onActivated: section.addCustomApp(appPickerItem.model.name, appPickerItem.model.exec, appPickerItem.model.icon)
                                }
                            }

                            MouseArea {
                                id: pickerMa
                                anchors.fill: parent
                                hoverEnabled: true
                                onClicked: section.addCustomApp(appPickerItem.model.name, appPickerItem.model.exec, appPickerItem.model.icon)
                            }
                        }
                    }
                }
            }

            // ── Manual Custom Binary / Script Row ────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: Design.s(Design.space.sm)

                // Field, like the rest of the settings. These were bare
                // TextInputs with a frame and font of their own that matched
                // no other field on the page, and the command's placeholder
                // was cut off mid-path.
                Field {
                    id: customNameInput
                    Layout.preferredWidth: Design.s(150)
                    placeholder: "Name"
                }

                Field {
                    id: customCmdInput
                    Layout.fillWidth: true
                    placeholder: "Command, e.g. syncthing or steam -silent"
                    onAccepted: v => section.addCustomApp(customNameInput.text, v, "")
                }

                // Sized to its own text. ActionButton fills width by default,
                // which is right when it is the only thing on its row and
                // wrong here: it shared the row with the command field and
                // took the space that field needs to be usable.
                ActionButton {
                    Layout.fillWidth: false
                    icon: "󰐕"
                    label: "Add Binary"
                    tone: Design.teal
                    onActivated: section.addCustomApp(customNameInput.text, customCmdInput.text, "")
                }
            }

            Label {
                visible: section.customError !== ""
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                role: "caption"
                color: Design.danger
                text: section.customError
            }

            // ── Active Startup Apps List ─────────────────────────────────────
            Repeater {
                model: section.autostartCustom || []
                delegate: ColumnLayout {
                    id: customAppItem
                    required property var modelData
                    required property int index

                    Layout.fillWidth: true
                    spacing: 0

                    Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Design.tint(Design.line, 0.4); visible: customAppItem.index > 0 }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Design.s(44)
                        spacing: Design.s(Design.space.md)

                        Icon { text: "󰄛"; role: "title"; color: Design.teal }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Label { text: customAppItem.modelData.name || "Custom App"; weight: Design.weight.semibold }
                            Label { text: customAppItem.modelData.command || ""; role: "caption"; isMono: true; dim: true }
                        }

                        Toggle {
                            checked: customAppItem.modelData.enabled !== false
                            onToggled: section.toggleCustomApp(customAppItem.index)
                        }

                        // Icon-sized: ActionButton fills its row by default,
                        // and this one took half the width of every entry.
                        IconButton {
                            icon: "󰆴"
                            hoverTone: Design.danger
                            onClicked: section.removeCustomApp(customAppItem.index)
                        }
                    }
                }
            }
        }
    }

    // ── 3. Welcome & User Guide ──────────────────────────────────────────────
    Card {
        title: "Session Hints & Welcome Guide"
        subtitle: "Preferences for onboarding prompts and keybinding guides"
        icon: "\u{f02d}"
        accentColor: Design.yellow

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.md)

            RowLayout {
                Layout.fillWidth: true
                spacing: Design.s(Design.space.md)
                Icon { text: "󰋖"; role: "title"; color: Design.yellow }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Design.s(2)
                    Label { text: "Open Guide on Login"; weight: Design.weight.semibold }
                    Label { text: "Displays the keybinding and tips modal after desktop loads"; role: "caption"; dim: true }
                }
                Toggle {
                    checked: section.openGuideAtStartup
                    onToggled: {
                        const next = !section.openGuideAtStartup;
                        section.openGuideAtStartup = next;
                        Settings.set("openGuideAtStartup", next);
                    }
                }
            }
        }
    }
}
