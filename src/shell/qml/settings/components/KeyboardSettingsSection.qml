import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import B1air.Daemon
import Quickshell.Io
import "../../Ui"
import "../../Services"

// =============================================================================
// Keyboard: input layouts, the shortcut that switches between them, and
// rebinding the desktop's own shortcuts.
//
// Layouts and the switch shortcut are saved to settings.json and nothing else;
// the daemon turns them into conf.d/custom_keyboard.conf and tells the running
// sway (settings_manager.cpp, apply_keyboard). Before that, what this page did
// was:
//
//   - Remove a layout: nothing. The chip sent its *index* and SettingsApp
//     filtered the list for a *code* equal to it, which no code is, so the
//     list was written back unchanged. Layouts could be added and never taken
//     away — including the two that ship.
//   - Add a layout: rewrote input.conf and did not tell sway, so it appeared
//     at the next login, if install.sh had not copied input.conf back first.
//   - The "Layout shortcut" dropdown opened onto an empty list: toggleOptions
//     and shortcutLabel were declared here and never given a value by anyone.
//   - The layout list could not be reordered, and the first layout is the one
//     every login starts in.
//
// The page reads Settings directly now rather than being handed copies of it
// by SettingsApp, which is how the index/code mismatch got in between.
// =============================================================================

ColumnLayout {
    id: section

    Layout.fillWidth: true
    spacing: Design.s(Design.space.lg)

    readonly property var layouts: String(Settings.language || "").split(",")
        .map(x => x.trim()).filter(x => x !== "")

    readonly property var knownLayouts: [
        { code: "us", name: "English (US)" },
        { code: "gb", name: "English (UK)" },
        { code: "ua", name: "Ukrainian" },
        { code: "ru", name: "Russian" },
        { code: "by", name: "Belarusian" },
        { code: "de", name: "German" },
        { code: "fr", name: "French" },
        { code: "es", name: "Spanish" },
        { code: "it", name: "Italian" },
        { code: "pt", name: "Portuguese" },
        { code: "br", name: "Portuguese (Brazil)" },
        { code: "latam", name: "Spanish (Latin America)" },
        { code: "pl", name: "Polish" },
        { code: "cz", name: "Czech" },
        { code: "sk", name: "Slovak" },
        { code: "se", name: "Swedish" },
        { code: "no", name: "Norwegian" },
        { code: "fi", name: "Finnish" },
        { code: "dk", name: "Danish" },
        { code: "nl", name: "Dutch" },
        { code: "be", name: "Belgian" },
        { code: "ch", name: "Swiss" },
        { code: "ca", name: "Canadian (French)" },
        { code: "tr", name: "Turkish" },
        { code: "gr", name: "Greek" },
        { code: "il", name: "Hebrew" },
        { code: "ara", name: "Arabic" },
        { code: "hu", name: "Hungarian" },
        { code: "ro", name: "Romanian" },
        { code: "bg", name: "Bulgarian" },
        { code: "rs", name: "Serbian" },
        { code: "hr", name: "Croatian" },
        { code: "si", name: "Slovenian" },
        { code: "lt", name: "Lithuanian" },
        { code: "lv", name: "Latvian" },
        { code: "ee", name: "Estonian" },
        { code: "ge", name: "Georgian" },
        { code: "am", name: "Armenian" },
        { code: "kz", name: "Kazakh" },
        { code: "jp", name: "Japanese" },
        { code: "kr", name: "Korean" },
        { code: "cn", name: "Chinese" },
        { code: "in", name: "Indian" }
    ]

    function layoutName(code) {
        const l = section.knownLayouts.find(k => k.code === code);
        return l ? l.name : code.toUpperCase();
    }

    function saveLayouts(list) {
        if (list.length > 0) {
            Settings.set("language", list.join(","));
            applySoon.restart();
        }
    }

    // Apply through a one-shot `b1air-daemon settings apply` as well as the
    // session daemon's file watcher. The watcher lives in the session daemon,
    // and when that was not running — it crashed on XWayland windows until
    // recently — layouts removed here were saved and never reached sway.
    // Deferred because Settings.set() is not on disk yet at this point. When
    // the session daemon is up as well, sway just gets the same layouts twice.
    Timer {
        id: applySoon
        interval: 400
        onTriggered: Quickshell.execDetached(["b1air-daemon", "settings", "apply"])
    }

    function addLayout(code) {
        if (section.layouts.indexOf(code) < 0)
            section.saveLayouts(section.layouts.concat(code));
    }

    function removeLayout(code) {
        // Never the last one: an empty xkb_layout leaves sway on whatever
        // it compiled last, which is not something this page can then show.
        if (section.layouts.length > 1)
            section.saveLayouts(section.layouts.filter(c => c !== code));
    }

    function makeFirst(code) {
        section.saveLayouts([code].concat(section.layouts.filter(c => c !== code)));
    }

    property string layoutQuery: ""

    readonly property var layoutResults: {
        const q = section.layoutQuery.trim().toLowerCase();
        return section.knownLayouts.filter(l =>
            section.layouts.indexOf(l.code) < 0
            && (q === "" || l.code.includes(q) || l.name.toLowerCase().includes(q)));
    }

    // ── The switch shortcut ──────────────────────────────────────────────────
    //
    // kbOptions can hold more than the grp: option (caps:escape, compose:...);
    // choosing a shortcut replaces only the grp: part, where the old dropdown
    // would have replaced the whole string.

    readonly property var switchOptions: [
        { val: "grp:alt_shift_toggle",  label: I18n.tr("Alt + Shift") },
        { val: "grp:ctrl_shift_toggle", label: I18n.tr("Ctrl + Shift") },
        { val: "grp:alt_space_toggle",  label: I18n.tr("Alt + Space") },
        { val: "grp:caps_toggle",       label: I18n.tr("Caps Lock") },
        { val: "grp:toggle",            label: I18n.tr("Right Alt") },
        { val: "grp:rctrl_toggle",      label: I18n.tr("Right Ctrl") },
        { val: "grp:menu_toggle",       label: I18n.tr("Menu key") },
        { val: "",                      label: I18n.tr("None") }
    ]
    // Not offered: Super + Space. sway gives that key to the launcher first.

    readonly property var otherOptions: String(Settings.kbOptions || "").split(",")
        .map(x => x.trim()).filter(x => x !== "" && !x.startsWith("grp:"))
    readonly property string switchOption: {
        const g = String(Settings.kbOptions || "").split(",").map(x => x.trim())
            .find(x => x.startsWith("grp:"));
        return g || "";
    }

    function setSwitch(val) {
        Settings.set("kbOptions", section.otherOptions.concat(val ? [val] : []).join(","));
        applySoon.restart();
    }

    // ── Layouts ──────────────────────────────────────────────────────────────
    // The language of the desktop and its apps (Ui/I18n.qml). Read when a
    // program starts, so the shell restarts to show it.
    Card {
        title: I18n.tr("Interface language")
        subtitle: I18n.tr("Menus, settings and apps; the shell restarts to switch")
        icon: "\u{f05ca}"
        accentColor: Design.blue

        Flow {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.xs)
            Repeater {
                model: [
                    { id: "auto", label: I18n.tr("Like the system") },
                    { id: "en",   label: "English" },
                    { id: "uk",   label: "Українська" },
                    { id: "ru",   label: "Русский" }
                ]
                delegate: Pill {
                    required property var modelData
                    label: modelData.label
                    active: (Settings.uiLanguage || "auto") === modelData.id
                    onClicked: {
                        if ((Settings.uiLanguage || "auto") === modelData.id) return;
                        Settings.set("uiLanguage", modelData.id);
                        restartSoon.restart();
                    }
                }
            }
        }
        Timer {
            id: restartSoon
            // After settings.json is written.
            interval: 600
            onTriggered: Quickshell.execDetached(["b1air-shell", "forceReload"])
        }
    }

    Card {
        title: I18n.tr("Input layouts")
        subtitle: I18n.tr("The first one is what every login starts in")
        icon: "\u{f030c}"
        accentColor: Design.peach

        Flow {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.xs)

            Repeater {
                model: section.layouts

                Rectangle {
                    id: chip
                    required property string modelData
                    required property int index
                    readonly property bool first: chip.index === 0

                    width: chipRow.implicitWidth + Design.s(Design.space.md) * 2
                    height: Design.s(36)
                    radius: Design.s(Design.radius.ctl)
                    color: chip.first ? Design.tint(Design.peach, 0.14) : Design.raised
                    border.color: chip.first ? Design.tint(Design.peach, 0.5) : Design.line
                    border.width: 1

                    RowLayout {
                        id: chipRow
                        anchors.centerIn: parent
                        spacing: Design.s(Design.space.sm)

                        Label {
                            text: chip.modelData.toUpperCase()
                            isMono: true
                            weight: Design.weight.bold
                            color: chip.first ? Design.peach : Design.text
                        }

                        Label {
                            text: section.layoutName(chip.modelData)
                            role: "caption"
                            dim: true
                        }

                        Badge {
                            visible: chip.first
                            text: "default"
                            tone: Design.peach
                        }

                        IconButton {
                            visible: !chip.first
                            icon: "\u{f005d}" // arrow up: make it the first
                            role: "caption"
                            hoverTone: Design.peach
                            onClicked: section.makeFirst(chip.modelData)
                        }

                        IconButton {
                            visible: section.layouts.length > 1
                            icon: "\u{f0156}" // close
                            role: "caption"
                            hoverTone: Design.danger
                            onClicked: section.removeLayout(chip.modelData)
                        }
                    }
                }
            }
        }

        Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            role: "caption"
            dim: true
            text: section.layouts.length > 1
                ? "\u{f005d} makes a layout the default, \u{f0156} removes it. Changes apply immediately."
                : I18n.tr("Add a second layout below to switch between them.")
        }

        Field {
            id: layoutField
            Layout.fillWidth: true
            placeholder: I18n.tr("Add a layout — type a language or a code (de, pl, jp…)")
            onEdited: v => section.layoutQuery = v
            // Enter takes the first match, so typing "pol" + Enter is enough.
            onAccepted: v => {
                if (section.layoutResults.length > 0) {
                    section.addLayout(section.layoutResults[0].code);
                    layoutField.text = "";
                    section.layoutQuery = "";
                }
            }
        }

        // Shown while the field has focus, with every layout not yet added
        // when nothing is typed: the old list stayed shut until you guessed a
        // name, so there was no way to see what could be added.
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: visible
                ? Math.min(Design.s(220), section.layoutResults.length * Design.s(32) + Design.s(8))
                : 0
            visible: (layoutField.focused || section.layoutQuery !== "") && section.layoutResults.length > 0
            radius: Design.s(Design.radius.ctl)
            color: Design.sunken
            border.color: Design.line
            border.width: 1
            clip: true

            ListView {
                anchors.fill: parent
                anchors.margins: Design.s(4)
                model: section.layoutResults
                boundsBehavior: Flickable.StopAtBounds
                ScrollBar.vertical: OverflowBar {}

                delegate: Rectangle {
                    required property var modelData
                    width: ListView.view.width
                    height: Design.s(32)
                    radius: Design.s(Design.radius.ctl)
                    color: resultArea.containsMouse ? Design.hover : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Design.s(Design.space.sm)
                        anchors.rightMargin: Design.s(Design.space.sm)
                        spacing: Design.s(Design.space.sm)

                        Label {
                            Layout.preferredWidth: Design.s(48)
                            text: modelData.code.toUpperCase()
                            isMono: true
                            weight: Design.weight.semibold
                        }
                        Label {
                            Layout.fillWidth: true
                            text: I18n.tr(modelData.name)
                            dim: true
                            elide: Text.ElideRight
                        }
                        Icon { text: "\u{f0415}"; role: "caption"; color: Design.textDim } // plus
                    }

                    MouseArea {
                        id: resultArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            section.addLayout(modelData.code);
                            layoutField.text = "";
                            section.layoutQuery = "";
                        }
                    }
                }
            }
        }
    }

    Card {
        title: I18n.tr("Switching layouts")
        subtitle: section.layouts.length > 1
            ? I18n.tr("The key that cycles through the layouts above")
            : I18n.tr("Only matters once there is more than one layout")
        icon: "\u{f04e1}"
        accentColor: Design.peach

        Flow {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.xs)

            Repeater {
                model: section.switchOptions
                delegate: Pill {
                    required property var modelData
                    label: modelData.label
                    active: section.switchOption === modelData.val
                    onClicked: section.setSwitch(modelData.val)
                }
            }
        }

        Label {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            role: "caption"
            dim: true
            text: I18n.tr("The layout indicator in the bar switches too, with a click.")
        }
    }

    // ── Rebinding shortcuts ──────────────────────────────────────────────────
    //
    // Rebinding used to append `bindsym <new> <cmd>` to custom_keybinds.conf
    // and reload. Three problems: the old key stayed bound, so a "rebind" was
    // really a second binding; every edit appended another line and none were
    // ever removed; and the format check rejected "$", so the example the field
    // itself showed ("$mod+t") and the value it was pre-filled with were both
    // "Unsupported key format" — nothing could be saved without already knowing
    // to write Mod4. It also sat as a card nested inside the Keyboard card.
    //
    // Now the changes are kept as a map in settings (keybindOverrides) and the
    // whole file is regenerated from it: unbind the default, bind the new key.
    // A change can be put back with Reset, and "Super+Shift+T" is understood
    // as well as sway's own spelling.

    Card {
        id: bindCard
        title: I18n.tr("Desktop shortcuts")
        subtitle: I18n.tr("Change the key for any of these. The full list is on the Shortcuts page.")
        icon: "\u{f11c}"
        accentColor: Design.sapphire

        property string filter: ""
        property string editingId: ""
        property string editKeys: ""
        property string status: ""
        property bool statusBad: false

        readonly property var overrides: {
            try {
                const o = JSON.parse(Settings.keybindOverrides || "{}");
                return (o && typeof o === "object") ? o : {};
            } catch (e) {
                return {};
            }
        }

        // keys: exactly as keybinds.conf binds it (with --to-code), because
        // that is what unbindsym has to name. KEEP IN SYNC with keybinds.conf.
        readonly property var bindings: [
            { id: "terminal",   cat: "Apps",    keys: "$mod+t",          desc: I18n.tr("Terminal"),                cmd: "exec $terminal" },
            { id: "files",      cat: "Apps",    keys: "$mod+e",          desc: I18n.tr("File manager"),            cmd: "exec $fileManager" },
            { id: "browser",    cat: "Apps",    keys: "$mod+f",          desc: I18n.tr("Web browser"),             cmd: "exec $browser" },
            { id: "menu",       cat: "Apps",    keys: "$mod+space",      desc: I18n.tr("Launchpad"),               cmd: "exec $menu" },
            { id: "spotlight",  cat: "Apps",    keys: "$mod+k",          desc: I18n.tr("Spotlight search"),        cmd: "exec $spotlight" },
            { id: "github",     cat: "Apps",    keys: "$mod+g",          desc: I18n.tr("Git"),                     cmd: "exec b1air-git" },
            { id: "dropdown",   cat: "Apps",    keys: "$mod+grave",      desc: I18n.tr("Drop-down terminal"),      cmd: "exec swaymsg '[app_id=\"b1air-dropdown\"] scratchpad show' || b1air-term --dropdown" },
            { id: "settings",   cat: "System",  keys: "$mod+shift+s",    desc: I18n.tr("Settings"),                cmd: "exec b1air-shell toggle settings" },
            { id: "control",    cat: "System",  keys: "$mod+c",          desc: I18n.tr("Control Center"),          cmd: "exec b1air-shell toggle control" },
            { id: "clipboard",  cat: "System",  keys: "$mod+ctrl+v",          desc: I18n.tr("Clipboard history"),       cmd: "exec b1air-shell toggle clipboard" },
            { id: "emoji",      cat: "System",  keys: "$mod+period",     desc: I18n.tr("Emoji picker"),            cmd: "exec b1air-shell toggle emoji" },
            { id: "keyboard",   cat: "System",  keys: "$mod+shift+k",    desc: I18n.tr("Keyboard popup"),          cmd: "exec b1air-shell toggle keyboard" },
            { id: "session",    cat: "System",  keys: "$mod+shift+e",    desc: I18n.tr("Session menu"),            cmd: "exec b1air-shell toggle session" },
            { id: "guide",      cat: "System",  keys: "$mod+h",          desc: I18n.tr("Shortcut list"),           cmd: "exec b1air-shell toggle guide" },
            { id: "wallpaper",  cat: "System",  keys: "$mod+w",          desc: I18n.tr("Wallpaper settings"),      cmd: "exec b1air-shell open settings wallpaper" },
            { id: "battery",    cat: "System",  keys: "$mod+b",          desc: I18n.tr("Battery popup"),           cmd: "exec b1air-shell toggle battery" },
            { id: "network",    cat: "System",  keys: "$mod+n",          desc: I18n.tr("Network popup"),           cmd: "exec b1air-shell toggle network" },
            { id: "monitors",   cat: "System",  keys: "$mod+m",          desc: I18n.tr("Displays popup"),          cmd: "exec b1air-shell toggle monitors" },
            { id: "focustime",  cat: "System",  keys: "$mod+shift+t",    desc: I18n.tr("Screen time"),             cmd: "exec b1air-shell toggle focustime" },
            { id: "close",      cat: "Windows", keys: "$mod+q",          desc: I18n.tr("Close window"),            cmd: "kill" },
            { id: "floating",   cat: "Windows", keys: "$mod+ctrl+space", desc: I18n.tr("Toggle floating"),         cmd: "floating toggle" },
            { id: "fullscreen", cat: "Windows", keys: "$mod+shift+f",    desc: I18n.tr("Fullscreen"),              cmd: "exec $b1airBin/b1air-daemon fullscreen-toggle" }
        ]

        function keysOf(b) { return bindCard.overrides[b.id] || b.keys; }

        /** "$mod+shift+t" -> "Super + Shift + T" */
        function pretty(keys) {
            const names = { "$mod": "Super", "mod4": "Super", "mod1": "Alt", "ctrl": "Ctrl",
                            "control": "Ctrl", "shift": "Shift", "space": "Space",
                            "period": ".", "comma": ",", "slash": "/", "minus": "-",
                            "return": "Enter", "escape": "Esc", "delete": "Del",
                            "backspace": "Backspace" };
            return String(keys).split("+").map(k => {
                const n = names[k.toLowerCase()];
                return n ? n : (k.length === 1 ? k.toUpperCase() : k);
            }).join(" + ");
        }

        /** What someone types -> sway's spelling, or "" if it is not a combo. */
        function normalize(text) {
            const map = { "super": "$mod", "win": "$mod", "mod": "$mod", "$mod": "$mod",
                          "mod4": "$mod", "alt": "Mod1", "mod1": "Mod1", "ctrl": "ctrl",
                          "control": "ctrl", "shift": "shift", "enter": "Return",
                          "return": "Return", "esc": "Escape", "escape": "Escape",
                          "space": "space", ".": "period", ",": "comma", "/": "slash",
                          "-": "minus", "del": "Delete", "delete": "Delete", "tab": "Tab",
                          "backspace": "BackSpace", "print": "Print" };
            const parts = String(text).split("+").map(p => p.trim()).filter(p => p !== "");
            if (parts.length === 0)
                return "";
            const out = parts.map(p => map[p.toLowerCase()] || (p.length === 1 ? p.toLowerCase() : p));
            // Nothing but letters, digits and underscores in a key name, so
            // what reaches the generated file cannot be anything but a key.
            if (!out.every(p => p === "$mod" || /^[A-Za-z0-9_]+$/.test(p)))
                return "";
            const mods = ["$mod", "Mod1", "ctrl", "shift"];
            if (mods.indexOf(out[out.length - 1]) >= 0)
                return ""; // modifiers alone
            return out.join("+");
        }

        function say(text, bad) {
            bindCard.status = text;
            bindCard.statusBad = bad;
            statusTimer.restart();
        }

        function save(b, typed) {
            const keys = bindCard.normalize(typed);
            if (keys === "") {
                bindCard.say(I18n.tr("Write it as keys joined by +, for example Super+Shift+T."), true);
                return;
            }
            const clash = bindCard.bindings.find(o => o.id !== b.id
                && bindCard.keysOf(o).toLowerCase() === keys.toLowerCase());
            if (clash) {
                bindCard.say(I18n.tr("%1 is already %2.", bindCard.pretty(keys), clash.desc), true);
                return;
            }
            const o = Object.assign({}, bindCard.overrides);
            if (keys.toLowerCase() === b.keys.toLowerCase())
                delete o[b.id];
            else
                o[b.id] = keys;
            bindCard.write(o);
            bindCard.editingId = "";
            bindCard.say(I18n.tr("%1 is now %2.", b.desc, bindCard.pretty(keys)), false);
        }

        function reset(b) {
            const o = Object.assign({}, bindCard.overrides);
            delete o[b.id];
            bindCard.write(o);
            bindCard.say(I18n.tr("%1 is back on %2.", b.desc, bindCard.pretty(b.keys)), false);
        }

        function write(o) {
            Settings.set("keybindOverrides", JSON.stringify(o));
            let out = "# Generated by b1air Settings -> Keyboard -> Desktop shortcuts.\n"
                    + "# Rewritten on every change there; edits here do not survive.\n\n";
            for (const b of bindCard.bindings) {
                const keys = o[b.id];
                if (!keys)
                    continue;
                out += "unbindsym --to-code " + b.keys + "\n";
                out += "bindsym --to-code " + keys + " " + b.cmd + "\n";
            }
            // Written whole (temporary file, then renamed) before sway reads it.
            if (Sys.writeFile("~/.config/sway/conf.d/custom_keybinds.conf", out))
                Sway.command("reload");
        }

        Timer {
            id: statusTimer
            interval: 5000
            onTriggered: bindCard.status = ""
        }

        Field {
            Layout.fillWidth: true
            placeholder: I18n.tr("Filter — terminal, settings, window…")
            onEdited: v => bindCard.filter = v.toLowerCase()
        }

        Label {
            visible: bindCard.status !== ""
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            role: "caption"
            weight: Design.weight.semibold
            text: bindCard.status
            color: bindCard.statusBad ? Design.danger : Design.ok
        }

        Repeater {
            model: bindCard.bindings.filter(b => bindCard.filter === ""
                || b.desc.toLowerCase().includes(bindCard.filter)
                || b.cat.toLowerCase().includes(bindCard.filter)
                || bindCard.pretty(bindCard.keysOf(b)).toLowerCase().includes(bindCard.filter))

            Rectangle {
                id: bindRow
                required property var modelData
                readonly property bool editing: bindCard.editingId === bindRow.modelData.id
                readonly property bool changed: bindCard.overrides[bindRow.modelData.id] !== undefined

                Layout.fillWidth: true
                Layout.preferredHeight: bindCol.implicitHeight + Design.s(Design.space.sm) * 2
                radius: Design.s(Design.radius.ctl)
                color: bindRow.editing ? Design.tint(Design.sapphire, 0.1) : Design.sunken
                border.color: bindRow.editing ? Design.sapphire : "transparent"
                border.width: 1

                ColumnLayout {
                    id: bindCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.margins: Design.s(Design.space.sm)
                    spacing: Design.s(Design.space.sm)

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Design.s(Design.space.md)

                        Label {
                            text: bindRow.modelData.desc
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }

                        Badge {
                            visible: bindRow.changed
                            text: "changed"
                            tone: Design.sapphire
                        }

                        Label {
                            text: bindCard.pretty(bindCard.keysOf(bindRow.modelData))
                            role: "caption"
                            isMono: true
                            weight: Design.weight.bold
                            color: Design.sapphire
                        }

                        IconButton {
                            icon: "\u{f03eb}" // pencil
                            role: "caption"
                            hoverTone: Design.sapphire
                            onClicked: {
                                if (bindRow.editing) {
                                    bindCard.editingId = "";
                                } else {
                                    bindCard.editingId = bindRow.modelData.id;
                                    keyField.text = bindCard.pretty(bindCard.keysOf(bindRow.modelData));
                                }
                            }
                        }
                    }

                    RowLayout {
                        visible: bindRow.editing
                        Layout.fillWidth: true
                        spacing: Design.s(Design.space.sm)

                        Field {
                            mono: true
                            id: keyField
                            Layout.fillWidth: true
                            placeholder: I18n.tr("e.g. Super+Shift+T or Ctrl+Alt+Return")
                            onAccepted: v => bindCard.save(bindRow.modelData, v)
                        }

                        ActionButton {
                            Layout.fillWidth: false
                            icon: "\u{f012c}"
                            label: I18n.tr("Save")
                            tone: Design.sapphire
                            onActivated: bindCard.save(bindRow.modelData, keyField.text)
                        }

                        ActionButton {
                            Layout.fillWidth: false
                            visible: bindRow.changed
                            icon: "\u{f0450}"
                            label: I18n.tr("Reset")
                            onActivated: {
                                bindCard.reset(bindRow.modelData);
                                bindCard.editingId = "";
                            }
                        }
                    }
                }
            }
        }
    }
}
