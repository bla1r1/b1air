import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import B1air.Daemon
import Quickshell.Io
import Quickshell.Widgets
import "../Ui"
import "../Services"
import "../Services" as Services

// =============================================================================
// The application grid.
//
// The layout before this one put a title, an app count, the search field and
// eight category pills on a single row. The pills have natural widths and the
// field only had fillWidth, so the pills won: at 1280x800 the search box came
// out about 110px wide, showing "Search ap", while filters for Games, Office
// and Multimedia — none of which had a single app on the machine — took more
// than half the header. The one control anybody uses was the smallest thing on
// screen.
//
// So: search is the header now, full width, and nothing shares the row with it.
// The count moved into the "All" chip, where it is still an answer to "how many
// are there" without costing the field any room. The category strip below it
// lists only categories that actually contain something, each with its count,
// and gains a Pinned chip when anything is pinned — pinning already drives the
// top bar's app island and had no payoff in here at all.
//
// Two more things the old grid got wrong:
//
// Every icon sat inside a rounded, bordered, category-tinted square. Real app
// icons come with their own shape and palette — Firefox, GitHub and Kate are
// all circular logos — so the box drew a second shape around the first and the
// pair read as a rendering mistake. The tile's own hover and selection
// backgrounds carry that structure now, and the icon is just the icon.
//
// Labels were one elided line in a sixth of the width, so half of them ended in
// an ellipsis: "Advanced Networ…", "Avahi SSH Server …", "Fcitx 5 Configurat…".
// Names wrap to two lines and the columns are computed from the width instead
// of being fixed at six.
//
// And it can be driven from the keyboard, which for a launcher is most of the
// point: arrows move the selection, Enter opens it, Escape clears the query
// before it closes the window.
// =============================================================================

PopupShell {
    id: window

    padding: Design.space.lg
    background: Design.glassBg
    borderColor: Design.glassBorder
    cornerRadius: Design.radius.panel

    property string query: ""
    property string activeCategory: "All"
    property int selectedIndex: 0
    readonly property var systemApps: window.systemAppsMapped
    // ── Dynamic System Applications Scanner ──────────────────────────────────
    // The scan itself lives in Services/Apps, shared with SpotlightLauncher;
    // only the mapping to this launcher's row shape is here.
    readonly property var systemAppsMapped: Services.Apps.list.map(app => ({
        name: app.name,
        desc: app.comment || I18n.tr("Installed Application"),
        icon: app.iconPath || app.icon || "application-x-executable",
        app_id: app.icon || "application-x-executable",
        cmd: app.exec,
        cat: window.categoryName(app.category),
        terminal: app.terminal === true
    }))


    // ── System Core Essentials ───────────────────────────────────────────────
    // Names here MUST match src/apps/*/b1air-*.desktop and the
    // apps' own window titles. They had drifted into three different sets:
    // the launcher said "Media Viewer"/"Settings"/"Git", the desktop entries
    // said "Image Viewer"/"System Settings"/"Git Diff Tool", and the windows
    // themselves were titled "b1air-view"/"b1air-git" — so the same app went by
    // a different name in the launcher, the Alt+Tab switcher and the taskbar.
    // Applications only.
    //
    // Seven of the entries that used to live here were not applications at all:
    // the Control Center, Clipboard, Calendar and Power popups, the colour
    // dropper and lock-screen one-shots, and Spotlight — the other launcher,
    // offered as a tile inside this one. A Launchpad is a grid of programs; a
    // popup that toggles has no place being "launched" from it, and each of
    // those already has a keybinding and a home in the Control Center.
    //
    // They remain in SpotlightLauncher, which is a command palette rather than
    // an application grid, so searching "clipboard" there still finds it.
    readonly property var baseApps: [
        { name: "Files", desc: I18n.tr("Native File Manager & Gallery"), icon: "b1air-files", app_id: "system-file-manager", cmd: "b1air-files", cat: "Utilities" },
        { name: "Terminal", desc: I18n.tr("Multi-tab Native Terminal"), icon: "b1air-term", app_id: "utilities-terminal", cmd: "b1air-term", cat: "System" },
        { name: "Git", desc: I18n.tr("GitHub Desktop Style Git Client"), icon: "b1air-git", app_id: "git", cmd: "b1air-git", cat: "Development" },
        { name: "System Monitor", desc: I18n.tr("Process & Hardware Monitor"), icon: "b1air-monitor", app_id: "utilities-system-monitor", cmd: "b1air-monitor", cat: "System" },
        { name: "Image Viewer", desc: I18n.tr("Lightweight Image & Media Viewer"), icon: "b1air-view", app_id: "image-x-generic", cmd: "b1air-view", cat: "Graphics" },
        { name: "Text Editor", desc: I18n.tr("Minimal Text & Config Editor"), icon: "b1air-text", app_id: "text-editor", cmd: "b1air-text", cat: "Utilities" },
        { name: "System Settings", desc: I18n.tr("Desktop Preferences & Appearance"), icon: "b1air-settings", app_id: "preferences-system", cmd: "b1air-settings", cat: "System" },
        { name: "Camera", desc: I18n.tr("Photos and video from the built-in camera"), icon: "b1air-camera", app_id: "b1air-camera", cmd: "b1air-camera", cat: "Multimedia" },
    ]

    function categoryName(raw) {
        const c = (raw || "").toLowerCase();
        if (c.includes("development") || c.includes("ide") || c.includes("programming")) return "Development";
        if (c.includes("graphics") || c.includes("viewer") || c.includes("image")) return "Graphics";
        if (c.includes("audio") || c.includes("video") || c.includes("player")) return "Multimedia";
        if (c.includes("game")) return "Games";
        if (c.includes("office") || c.includes("wordprocessor")) return "Office";
        if (c.includes("system") || c.includes("settings") || c.includes("hardware")) return "System";
        return "Utilities";
    }

    function iconSource(icon) { return Services.Apps.iconSource(icon); }

    function categoryColor(category) {
        switch (categoryName(category)) {
        case "System": return Design.blue;
        case "Development": return Design.teal;
        case "Graphics": return Design.peach;
        case "Multimedia": return Design.mauve;
        case "Games": return Design.red;
        case "Office": return Design.yellow;
        default: return Design.sapphire;
        }
    }

    readonly property var allApps: {
        let combined = [];
        let seen = {};
        for (let a of window.baseApps) {
            seen[a.name.toLowerCase()] = true;
            combined.push(a);
        }
        for (let a of window.systemApps) {
            if (!seen[a.name.toLowerCase()]) {
                seen[a.name.toLowerCase()] = true;
                combined.push(a);
            }
        }
        combined.sort((a, b) => a.name.localeCompare(b.name, undefined, { sensitivity: 'base' }));
        return combined;
    }

    function safeLaunchCommand(cmd) {
        const value = (cmd || "").trim();
        const forbidden = [";", "&", "|", "`", "$", "<", ">", "\\", "\n", "\r", "(", ")", "{", "}", "[", "]", "*", "?", "!", "~"];
        if (!value || value.length > 512 || forbidden.some(c => value.includes(c))) return false;

        // Settings has no standalone window anymore: the QML it would load
        // (shell/qml/SettingsWindow.qml) imports Services, which imports
        // Quickshell types that only exist inside the running quickshell
        // process — a separate QQmlApplicationEngine can't resolve them.
        // SettingsApp.qml already exists as an in-shell panel for exactly
        // this reason; open that instead of spawning a binary that can only
        // ever fail to load.
        if (value === "b1air-settings") {
            if (typeof masterWindow !== "undefined" && masterWindow.handleIpcCommand) {
                masterWindow.handleIpcCommand("open:settings:", true);
            }
            return true;
        }

        // Launch our own applications directly.  Sending them through
        // `swaymsg exec` makes failures invisible to the UI and depends on the
        // compositor's shell environment.  External desktop entries still use
        // Sway's launcher path below, after the strict character allowlist.
        const nativeApps = [
            "b1air-files", "b1air-term", "b1air-git",
            "b1air-monitor", "b1air-view", "b1air-text"
        ];
        if (nativeApps.includes(value)) {
            // execvp resolves a bare name via PATH, and this whole suite
            // installs to ~/.local/bin — not guaranteed to be on it (it
            // wasn't, for every session already running before that got
            // fixed). Absolute path sidesteps PATH entirely.
            Quickshell.execDetached([Quickshell.env("HOME") + "/.local/bin/" + value]);
            return true;
        }

        Sway.command("exec " + value);
        return true;
    }

    function cleanExec(cmd) {
        return cmd.replace(/%[a-zA-Z]/g, "").trim();
    }

    function launchApp(app) {
        window.close();
        if (!app || !app.cmd) return;
        let cmd = cleanExec(app.cmd.trim());

        // A desktop entry with Terminal=true is a console program: htop, btop++,
        // vim. Executed directly it has no terminal to draw in and exits at
        // once, so clicking those tiles did nothing whatsoever. They open in
        // b1air-term instead — which is what the entry is asking for.
        if (app.terminal === true) {
            Quickshell.execDetached(["b1air-term", "-e", cmd]);
            return;
        }
        safeLaunchCommand(cmd);
    }

    // ── Categories that exist, with how much is in them ──────────────────────
    readonly property var categoryCounts: {
        let counts = {};
        for (let a of window.allApps) {
            const c = a.cat || "Utilities";
            counts[c] = (counts[c] || 0) + 1;
        }
        return counts;
    }

    // An empty filter is worse than no filter: it offers a category, takes the
    // click and shows the empty state. Only what has something behind it, in a
    // fixed order so the strip does not reshuffle as apps are installed.
    readonly property var categories: {
        const order = ["System", "Utilities", "Development", "Graphics", "Multimedia", "Games", "Office"];
        let out = [{ key: "All", count: window.allApps.length }];
        if (PinnedApps.pinnedList.length > 0)
            out.push({ key: "Pinned", count: PinnedApps.pinnedList.length });
        for (const c of order)
            if (window.categoryCounts[c] > 0)
                out.push({ key: c, count: window.categoryCounts[c] });
        return out;
    }

    readonly property var filteredApps: {
        let list = window.allApps;
        if (window.activeCategory === "Pinned") {
            // Reading the list itself, not just calling isPinned(), so this
            // re-runs when something is pinned while the filter is open.
            const pins = PinnedApps.pinnedList;
            list = list.filter(a => PinnedApps.isPinned(a.name));
        } else if (window.activeCategory !== "All") {
            list = list.filter(a => (a.cat || "").toLowerCase().includes(window.activeCategory.toLowerCase()));
        }
        const q = window.query.trim().toLowerCase();
        if (q) {
            list = list.filter(a => {
                return a.name.toLowerCase().includes(q) ||
                       (a.desc && a.desc.toLowerCase().includes(q)) ||
                       (a.cmd && a.cmd.toLowerCase().includes(q));
            });
        }
        return list;
    }

    readonly property var selectedApp:
        (window.selectedIndex >= 0 && window.selectedIndex < window.filteredApps.length)
            ? window.filteredApps[window.selectedIndex] : null

    onQueryChanged: window.selectedIndex = 0
    onActiveCategoryChanged: window.selectedIndex = 0

    // Filtering can drop the selection off the end — typing one more letter
    // usually does. Land on the last surviving row rather than on nothing.
    onFilteredAppsChanged: {
        if (window.selectedIndex >= window.filteredApps.length)
            window.selectedIndex = Math.max(0, window.filteredApps.length - 1);
    }

    // All four arrows drive the grid, including left and right, which in a text
    // field would normally move the caret. That is the trade every launcher
    // makes — rofi, wofi, Spotlight — because the field holds a word or two and
    // is edited with backspace, while the grid is the thing being aimed at.
    function moveSelection(dx, dy) {
        const total = window.filteredApps.length;
        if (total === 0)
            return;
        let i = window.selectedIndex;
        if (dx !== 0) {
            i = (i + dx + total) % total;
        } else {
            i = Math.max(0, Math.min(total - 1, i + dy * appGrid.columns));
        }
        window.selectedIndex = i;
        appGrid.positionViewAtIndex(i, GridView.Contain);
    }

    Component.onCompleted: launchSearchInput.forceActiveFocus()

    ColumnLayout {
        anchors.fill: parent
        spacing: Design.s(Design.space.md)

        // ── Search ───────────────────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Design.s(44)
            radius: Design.s(Design.radius.ctl)
            color: Design.well
            border.color: launchSearchInput.activeFocus ? Design.accent : Design.glassBorder
            border.width: Design.border

            Behavior on border.color { ColorAnimation { duration: Design.duration.fast } }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Design.s(Design.space.md)
                anchors.rightMargin: Design.s(Design.space.sm)
                spacing: Design.s(Design.space.sm)

                Icon {
                    text: "\u{f002}"
                    role: "body"
                    color: launchSearchInput.activeFocus ? Design.accent : Design.textDim
                    Behavior on color { ColorAnimation { duration: Design.duration.fast } }
                }

                TextInput {
                    id: launchSearchInput
                    Layout.fillWidth: true
                    verticalAlignment: TextInput.AlignVCenter
                    color: Design.text
                    font.family: Design.font.sans
                    font.pixelSize: Design.s(Design.font.subhead)
                    selectByMouse: true
                    clip: true

                    text: window.query
                    onTextChanged: window.query = text

                    // Every one of these accepts its event, which is not
                    // decoration. Keys attached to an Item run *before* the
                    // Item's own handling, so an unaccepted Right would move
                    // the selection and the caret; and an unaccepted Escape
                    // carries on to PopupShell's own handler, which closes the
                    // window — so clearing the query would have closed the
                    // launcher at the same time.
                    Keys.onEscapePressed: event => {
                        event.accepted = true;
                        // Escape means "undo the typing" while there is any,
                        // and only then "put the launcher away" — the order
                        // the shell's other paged popups use for going back.
                        if (launchSearchInput.text.length > 0)
                            launchSearchInput.text = "";
                        else
                            window.close();
                    }
                    Keys.onLeftPressed: event => { event.accepted = true; window.moveSelection(-1, 0); }
                    Keys.onRightPressed: event => { event.accepted = true; window.moveSelection(1, 0); }
                    Keys.onUpPressed: event => { event.accepted = true; window.moveSelection(0, -1); }
                    Keys.onDownPressed: event => { event.accepted = true; window.moveSelection(0, 1); }
                    // Guarded, because launchApp() closes the window before it
                    // looks at what it was given: Enter on a query that matches
                    // nothing would otherwise dismiss the launcher.
                    Keys.onReturnPressed: event => { event.accepted = true; if (window.selectedApp) window.launchApp(window.selectedApp); }
                    Keys.onEnterPressed: event => { event.accepted = true; if (window.selectedApp) window.launchApp(window.selectedApp); }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: I18n.tr("Search applications")
                        color: Design.textDim
                        font: parent.font
                        visible: !launchSearchInput.text
                    }
                }

                IconButton {
                    visible: launchSearchInput.text.length > 0
                    icon: "\u{f00d}"
                    role: "caption"
                    onClicked: {
                        launchSearchInput.text = "";
                        launchSearchInput.forceActiveFocus();
                    }
                }
            }
        }

        // ── Category strip ───────────────────────────────────────────────────
        Flickable {
            Layout.fillWidth: true
            Layout.preferredHeight: chipRow.implicitHeight
            contentWidth: chipRow.implicitWidth
            flickableDirection: Flickable.HorizontalFlick
            clip: true

            Row {
                id: chipRow
                spacing: Design.s(Design.space.xs)

                Repeater {
                    model: window.categories
                    delegate: Pill {
                        required property var modelData
                        label: I18n.tr(modelData.key) + "  " + modelData.count
                        active: window.activeCategory === modelData.key
                        onClicked: window.activeCategory = modelData.key
                    }
                }
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Design.tint(Design.line, 0.4)
        }

        // ── The grid ─────────────────────────────────────────────────────────
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            GridView {
                id: appGrid
                anchors.fill: parent
                // The overflow bar draws inside the view, so without this it
                // sits on top of the rightmost column of tiles.
                anchors.rightMargin: Design.s(Design.space.sm)
                clip: true
                reuseItems: true
                model: window.filteredApps

                // Six columns whatever the width meant a 96px cell on a 1280px
                // screen, which is narrower than most application names. The
                // count follows the room available, with a floor so a narrow
                // screen gets fewer, larger cells rather than a row of slivers.
                readonly property int columns: Math.max(3, Math.floor(width / Design.s(124)))
                cellWidth: Math.floor(width / appGrid.columns)

                // Rows divide the viewport exactly instead of being a fixed
                // height that rarely fits a whole number of times. With the
                // fixed height the grid ended mid-row: the bottom of the card
                // showed a strip of half-drawn icons, which reads as a
                // rendering fault rather than as "there is more below". The
                // row height flexes by a few pixels instead — the delegate is
                // a centred icon over the name, so it absorbs that without
                // moving anything visible.
                readonly property int rowCount: Math.max(1, Math.round(height / Design.s(112)))
                cellHeight: Math.floor(height / appGrid.rowCount)

                ScrollBar.vertical: OverflowBar {}

                delegate: Item {
                    id: gridCell
                    required property var modelData
                    required property int index

                    width: appGrid.cellWidth
                    height: appGrid.cellHeight

                    readonly property bool selected: window.selectedIndex === index
                    readonly property bool lit: itemHover.containsMouse || gridCell.selected

                    Rectangle {
                        id: cardBox
                        anchors.centerIn: parent
                        width: parent.width - Design.s(Design.space.sm)
                        height: parent.height - Design.s(Design.space.xs)
                        radius: Design.s(Design.radius.card)
                        color: gridCell.lit ? Design.tint(Design.accent, itemHover.containsMouse ? 0.18 : 0.12)
                                            : "transparent"
                        border.color: gridCell.selected ? Design.accent : "transparent"
                        border.width: Design.border

                        scale: itemHover.containsMouse ? 1.04 : 1.0
                        Behavior on scale { NumberAnimation { duration: Design.duration.fast; easing.type: Design.easing } }
                        Behavior on color { ColorAnimation { duration: Design.duration.fast } }

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.margins: Design.s(Design.space.sm)
                            spacing: Design.s(Design.space.xs)

                            Item { Layout.fillHeight: true }

                            Item {
                                Layout.alignment: Qt.AlignHCenter
                                implicitWidth: Design.s(44)
                                implicitHeight: Design.s(44)

                                IconImage {
                                    anchors.fill: parent
                                    source: window.iconSource(modelData.icon)
                                    mipmap: true
                                }

                                // Pinned is a badge on the icon, not a chip in
                                // the tile's corner. A tile has no background
                                // of its own until it is hovered, so the mark
                                // used to float in the gap between two rows and
                                // read as a stray artifact rather than as
                                // belonging to anything.
                                Rectangle {
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.margins: -Design.s(2)
                                    width: Design.s(12)
                                    height: Design.s(12)
                                    radius: width / 2
                                    visible: PinnedApps.isPinned(modelData.name)
                                    color: Design.sapphire
                                    border.color: window.background
                                    border.width: Design.s(2)
                                }
                            }

                            Label {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignHCenter
                                text: modelData.name
                                horizontalAlignment: Text.AlignHCenter
                                weight: gridCell.lit ? Design.weight.semibold : Design.weight.regular
                                color: gridCell.lit ? Design.accent : Design.text
                                font.pixelSize: Design.s(12)
                                // Two lines, because one was not enough for
                                // most of them: at six fixed columns half the
                                // grid ended in an ellipsis.
                                wrapMode: Text.Wrap
                                maximumLineCount: 2
                                elide: Text.ElideRight
                            }

                            Item { Layout.fillHeight: true }
                        }

                        // The pin toggle, shown only under the pointer — the
                        // pinned *state* is the badge on the icon above.
                        Rectangle {
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.margins: Design.s(Design.space.xs)
                            width: Design.s(20)
                            height: Design.s(20)
                            radius: Design.s(Design.radius.sm)
                            visible: itemHover.containsMouse
                            color: pinArea.containsMouse ? Design.tint(Design.accent, 0.30) : Design.tint(Design.text, 0.10)
                            z: 10

                            Icon {
                                anchors.centerIn: parent
                                text: PinnedApps.isPinned(modelData.name) ? "\u{f0932}" : "\u{f0931}"
                                role: "caption"
                                color: PinnedApps.isPinned(modelData.name) ? Design.sapphire : Design.textDim
                            }

                            MouseArea {
                                id: pinArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: PinnedApps.togglePin({
                                    name: modelData.name,
                                    icon: modelData.icon,
                                    cmd: modelData.cmd
                                })
                            }
                        }

                        MouseArea {
                            id: itemHover
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            cursorShape: Qt.PointingHandCursor
                            // Moving the pointer moves the selection, so the
                            // footer describes whatever is under it and Enter
                            // opens what the eye is on.
                            onEntered: window.selectedIndex = gridCell.index
                            onClicked: (mouse) => {
                                if (mouse.button === Qt.RightButton) {
                                    PinnedApps.togglePin({
                                        name: modelData.name,
                                        icon: modelData.icon,
                                        cmd: modelData.cmd
                                    });
                                } else {
                                    window.launchApp(modelData);
                                }
                            }
                        }
                    }
                }
            }

            EmptyState {
                anchors.centerIn: parent
                width: parent.width
                visible: window.filteredApps.length === 0
                icon: "\u{f002}"
                title: window.query.trim() ? I18n.tr("Nothing matches “%1”", window.query.trim())
                                           : I18n.tr("No applications in %1", I18n.tr(window.activeCategory))
                hint: window.query.trim() ? I18n.tr("Try fewer letters, or clear the category filter.")
                                          : I18n.tr("Install something, or pick another category above.")
            }
        }

        // ── Footer ───────────────────────────────────────────────────────────
        //
        // Every app carries a description from its desktop entry and the grid
        // had nowhere to show one, so the field was read, mapped and thrown
        // away. It belongs here: one line about whatever is selected, which is
        // also what tells you the keyboard is doing something.
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: Design.s(18)
            spacing: Design.s(Design.space.md)

            Label {
                Layout.fillWidth: true
                text: window.selectedApp ? window.selectedApp.desc : ""
                role: "caption"
                color: Design.textDim
                elide: Text.ElideRight
            }

            Label {
                text: I18n.tr("↑↓←→ move    ↵ open    right-click pin")
                role: "caption"
                color: Design.textFaint
            }
        }
    }
}
