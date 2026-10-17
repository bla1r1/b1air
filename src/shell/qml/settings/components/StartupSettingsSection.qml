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
    property bool openGuideAtStartup: Settings.openGuideAtStartup === true
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
            section.customError = I18n.tr("Startup commands cannot contain shell syntax (quotes, $, ;, |, & …). Put it in a script and add the script instead.");
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
    SettingsGroup {
        title: I18n.tr("Autostart Applications")
        icon: "\u{f009}"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.md)

            // Header Action: Choose from installed applications
            RowLayout {
                Layout.fillWidth: true
                spacing: Design.s(Design.space.sm)

                // No heading of its own: the group's title says it.
                Button {
                    Layout.fillWidth: false
                    icon: "󰐕"
                    label: section.showAppPicker ? I18n.tr("Close App List") : I18n.tr("Add Installed App…")
                    onActivated: section.showAppPicker = !section.showAppPicker
                }
                Item { Layout.fillWidth: true }
            }

            // ── Installed Apps Search & Picker Grid (Expanded on demand) ──────
            Rectangle {
                visible: section.showAppPicker
                Layout.fillWidth: true
                Layout.preferredHeight: Design.s(Design.width.list)
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
                        Layout.preferredHeight: Design.s(Design.size.md)
                        radius: Design.s(Design.radius.ctl)
                        color: Design.surface
                        border.color: appSearchInput.activeFocus ? Design.accent : Design.tint(Design.line, 0.4)
                        border.width: 1

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: Design.s(Design.space.xs)
                            spacing: Design.s(Design.space.xs)

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
                                    text: I18n.tr("Search installed applications...")
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
                        spacing: Design.s(Design.space.xs)
                        model: section.allInstalledApps

                        delegate: Rectangle {
                            id: appPickerItem
                            required property var model
                            required property int index

                            visible: section.appSearchQuery === "" ||
                                     appPickerItem.model.name.toLowerCase().includes(section.appSearchQuery) ||
                                     appPickerItem.model.exec.toLowerCase().includes(section.appSearchQuery)

                            width: ListView.view ? ListView.view.width : 0
                            height: visible ? Design.s(Design.size.header) : 0
                            radius: Design.s(Design.radius.ctl)
                            color: pickerMa.containsMouse ? Design.glassHover : "transparent"

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: Design.s(Design.space.xs)
                                spacing: Design.s(Design.space.sm)

                                Image {
                                    Layout.preferredWidth: Design.s(Design.size.mini)
                                    Layout.preferredHeight: Design.s(Design.size.mini)
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
                                    color: Design.accent
                                }

                                Label {
                                    text: appPickerItem.model.name
                                    weight: Design.weight.semibold
                                    role: "caption"
                                    elide: Text.ElideRight
                                    Layout.preferredWidth: Design.s(Design.width.field)
                                }

                                Label {
                                    text: appPickerItem.model.exec
                                    role: "caption"
                                    dim: true
                                    isMono: true
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                }

                                Button {
                                    icon: "󰐕"
                                    label: I18n.tr("Add")
                                    onActivated: section.addCustomApp(appPickerItem.model.name, appPickerItem.model.exec, appPickerItem.model.icon)
                                }
                            }

                            Clickable {
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
                    Layout.preferredWidth: Design.s(Design.width.field)
                    placeholder: I18n.tr("Name")
                }

                Field {
                    mono: true
                    id: customCmdInput
                    Layout.fillWidth: true
                    placeholder: I18n.tr("Command, e.g. syncthing or steam -silent")
                    onAccepted: v => section.addCustomApp(customNameInput.text, v, "")
                }

                // Sized to its own text: it shares the row with the command
                // field, which needs the space to be usable.
                Button {
                    Layout.fillWidth: false
                    icon: "󰐕"
                    label: I18n.tr("Add Binary")
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
        }

        // ── Active Startup Apps List ─────────────────────────────────────────
        Repeater {
            model: section.autostartCustom || []

            SettingsRow {
                id: customAppItem
                required property var modelData
                required property int index

                label: customAppItem.modelData.name || I18n.tr("Custom App")
                note: customAppItem.modelData.command || ""

                Switch {
                    checked: customAppItem.modelData.enabled !== false
                    onToggled: section.toggleCustomApp(customAppItem.index)
                }
                // Icon-sized: a full-width button here took half the width
                // of every entry.
                IconButton {
                    icon: "󰆴"
                    hoverTone: Design.danger
                    onClicked: section.removeCustomApp(customAppItem.index)
                }
            }
        }
    }

    // ── 3. Welcome & User Guide ──────────────────────────────────────────────
    SettingsGroup {
        title: I18n.tr("Welcome & first-run setup")
        icon: "\u{f02d}"

        SwitchRow {
            label: I18n.tr("Show the welcome at login")
            note: I18n.tr("Where things are, and the keys for them. Super+H opens it any time.")
            checked: section.openGuideAtStartup
            onToggled: {
                const next = !section.openGuideAtStartup;
                section.openGuideAtStartup = next;
                Settings.set("openGuideAtStartup", next);
            }
        }

        // The first-run setup again, every step: language, Wi-Fi, theme,
        // wallpaper, account, fingerprint (SetupWizard.qml).
        SettingsRow {
            label: I18n.tr("First-run setup")
            Button {
                icon: "\u{f040a}"
                label: I18n.tr("Run it again")
                onActivated: Quickshell.execDetached(["b1air-settings", "setup"])
            }
        }
    }
}
