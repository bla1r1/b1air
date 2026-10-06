import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import "../Ui"
import "../Services"
import "components" as Sections

Item {
    id: app

    property bool framed: false
    property string page: "monitors"
    // Set by the standalone window (SettingsWindow.qml); inside the shell the
    // panel is closed through b1air-shell instead.
    property bool standalone: false
    signal closeRequested()

    // "setup" (or "setup.<step>.<step>…") is the first-run wizard, in place
    // of the rail and the page.
    readonly property bool setupMode: app.page === "setup" || app.page.indexOf("setup.") === 0
    function close() {
        if (app.standalone) app.closeRequested();
        else Quickshell.execDetached(["b1air-shell", "close"]);
    }
    property string searchQuery: ""

    Component.onCompleted: {
        if (!app.page) app.page = "monitors";
        else if (app.moved[app.page]) app.page = app.moved[app.page];
    }

    // Grouped by what a person looks for: connecting, the hardware, how it
    // looks, the apps, their time, and the system and its data.
    readonly property var pages: [
        { isHeader: true, label: I18n.tr("CONNECTIONS") },
        { id: "network",     icon: "\u{f0928}", label: I18n.tr("Network & Wi-Fi"), desc: I18n.tr("Wi-Fi, wired connections and VPNs"),  color: Design.lavender, tags: "wifi internet connection ethernet ssid ip address vpn network" },
        { id: "bluetooth",   icon: "\u{f00af}", label: I18n.tr("Bluetooth"), desc: I18n.tr("Pair and connect headphones, mice, keyboards and controllers"),        color: Design.mauve,    tags: "bluetooth bt pair devices headset connect mouse keyboard controller" },
        { id: "remote",      icon: "\u{f0379}", label: I18n.tr("Remote Desktop"), desc: I18n.tr("Let another computer see or control this one"),   color: Design.blue,     tags: "remote desktop vnc rdp ssh anydesk screen sharing wayvnc" },
        { isHeader: true, label: I18n.tr("DEVICES") },
        { id: "monitors",    icon: "\u{f0379}", label: I18n.tr("Displays"), desc: I18n.tr("Resolution, refresh rate, scaling, brightness and arrangement of your screens"),         color: Design.sapphire, tags: "display resolution refresh rate scaling monitor screen mirror hdr brightness backlight ddc" },
        { id: "audio",       icon: "\u{f057e}", label: I18n.tr("Sound & Volume"), desc: I18n.tr("Output and input devices, volumes and per-app levels"),   color: Design.teal,     tags: "sound volume sink source mic microphone devices wireplumber equalizer audio output input" },
        { id: "power",       icon: "\u{f0084}", label: I18n.tr("Power & Battery"), desc: I18n.tr("Power profile, battery charging and when the screen sleeps"),  color: Design.green,    tags: "battery sleep suspend hibernate timeout charge energy power lid button profile" },
        { id: "keyboard",    icon: "\u{f030c}", label: I18n.tr("Keyboard"), desc: I18n.tr("Input layouts and switching between them"),         color: Design.peach,    tags: "keyboard layout switch xkb input sources alt shift caps" },
        { id: "input",       icon: "\u{f0523}", label: I18n.tr("Mouse & Touchpad"), desc: I18n.tr("Pointer speed, scrolling and touchpad gestures"), color: Design.peach,    tags: "mouse touchpad sensitivity scroll tap acceleration natural pointer click magic apple gestures swipe" },
        { isHeader: true, label: I18n.tr("PERSONALIZATION") },
        { id: "appearance",  icon: "\u{f0765}", label: I18n.tr("Appearance"), desc: I18n.tr("The theme, the accent colour, and how other apps follow them"),       color: Design.mauve,    tags: "theme themes palette colours colors breeze adwaita dark light accent color gtk qt apps import export create custom wallpaper" },
        { id: "wallpaper",   icon: "\u{f02ca}", label: I18n.tr("Wallpaper"), desc: I18n.tr("The picture behind your windows and on the login screen"),        color: Design.pink,     tags: "background wallpaper pictures desktop image slideshow photos" },
        { id: "bar",         icon: "\u{f07e}",  label: I18n.tr("Top Bar"), desc: I18n.tr("What the bar and the Control Center show, the clock, and the weather"), color: Design.blue,     tags: "weather temperature forecast city control center tiles cards top bar panel modules widgets islands tray weather media stats icons workspaces clock 24 hour monitors show hide" },
        { id: "windows",     icon: "\u{f0379}", label: I18n.tr("Windows"), desc: I18n.tr("Tiling, gaps, borders, effects, unfocused windows and workspaces"),    color: Design.sapphire, tags: "gaps border padding tiling sway layout inner outer smart borders smart gaps autotiling dwindle split hyprland spiral blur shadows corners rounded effects dim inactive opacity transparency unfocused special workspace scratchpad overview expose" },
        { id: "animations",  icon: "\u{f0e1e}", label: I18n.tr("Animations"), desc: I18n.tr("How windows and workspaces move, and how fast"), color: Design.mauve, tags: "animation animations motion slide fade popin duration speed swipe hyprland" },
        { id: "nightlight",  icon: "\u{f0599}", label: I18n.tr("Night Light"), desc: I18n.tr("Warmer screen colours at night, and how warm"),      color: Design.yellow,   tags: "night light blue light temperature schedule eye protect" },
        { isHeader: true, label: I18n.tr("APPS") },
        { id: "defaultapps", icon: "\u{f0ac}",  label: I18n.tr("Default Apps"), desc: I18n.tr("Which app opens links, folders, text and media"),     color: Design.teal,     tags: "default applications browser terminal file manager editor mime types" },
        { id: "startup",     icon: "\u{f0459}", label: I18n.tr("Startup Apps"), desc: I18n.tr("Apps that start when you log in"),     color: Design.yellow,   tags: "startup autostart boot launch apps systemd login" },
        { id: "notifications", icon: "\u{f009a}", label: I18n.tr("Notifications"), desc: I18n.tr("Which apps may show banners and sounds, and quiet hours"), color: Design.teal, tags: "notifications banners popups sounds apps filters dnd do not disturb quiet hours night silence" },
        { id: "capture",     icon: "\u{f016d}", label: I18n.tr("Screenshots"), desc: I18n.tr("Where screenshots and recordings go, and how they are taken"),      color: Design.pink,     tags: "screenshot capture grim slurp record screen area video gif" },
        { id: "gamemode",    icon: "\u{f11b}",  label: I18n.tr("Game Mode"), desc: I18n.tr("One switch for less latency and fewer effects while playing"),        color: Design.red,      tags: "game mode performance vr fstrim process priority latency boost" },
        { isHeader: true, label: I18n.tr("TIME & FOCUS") },
        { id: "focus",       icon: "\u{f051e}", label: I18n.tr("Screen Time & Focus"), desc: I18n.tr("Screen time today, focus and break intervals, reminders"),color: Design.teal,     tags: "screen time timer focus pomodoro analytics breaks reminders eye care dnd" },
        { isHeader: true, label: I18n.tr("SYSTEM") },
        { id: "region",      icon: "\u{f05ca}", label: I18n.tr("Language & Region"), desc: I18n.tr("The interface language, the system's language, and the formats of dates and numbers"), color: Design.blue, tags: "language interface translation locale lang system region formats date time number currency units measurement" },
        { id: "user",        icon: "\u{f007}",  label: I18n.tr("User Profile"), desc: I18n.tr("Your name, picture and login shell"),     color: Design.mauve,    tags: "user profile avatar name username password account hostname fingerprint fprint" },
        { id: "lock",        icon: "\u{f033e}", label: I18n.tr("Lock & Login"), desc: I18n.tr("When the screen locks, the fingerprint, and the login screen"), color: Design.blue, tags: "lock screen login sddm greeter fingerprint fprint unlock session password sleep" },
        { id: "privacy",     icon: "\u{f0483}", label: I18n.tr("Privacy"), desc: I18n.tr("Screen time, clipboard history, trash and locations: what is kept, and wiping it"), color: Design.green, tags: "privacy screen time history clipboard trash delete forget location camera microphone record" },
        { id: "shortcuts",   icon: "\u{f11c}",  label: I18n.tr("Shortcuts"), desc: I18n.tr("Every key binding, and changing them"),        color: Design.sapphire, tags: "shortcuts keybinds keys hotkeys sway bindings commands remap change rebind" },
        { id: "updates",     icon: "\u{f06b0}", label: I18n.tr("Updates"), desc: I18n.tr("Updates for this desktop and the system packages"), color: Design.green, tags: "updates update upgrade packages pacman apt dnf zypper kernel dotfiles git pull" },
        { id: "maintenance", icon: "\u{f0187}", label: I18n.tr("Storage & Backup"), desc: I18n.tr("Backups, cleanup, restore points, vaults, and resetting the desktop"),      color: Design.green,    tags: "maintenance clean disk cache logs cleanup packages pacman apt dnf zypper trim system" },
        { id: "about",       icon: "\u{f035b}", label: I18n.tr("About System"), desc: I18n.tr("This computer, this desktop, and the services behind it"),     color: Design.mauve,    tags: "about system version kernel arch sway quickshell specs hardware cpu ram" }
    ]

    // An empty rail with the previous page still rendered beside it reads as a
    // broken window, not as "no matches".
    readonly property bool noResults: app.searchQuery.trim() !== "" && app.filteredPages.length === 0

    readonly property var filteredPages: {
        const q = app.searchQuery.trim().toLowerCase();
        if (!q) return app.pages;
        return app.pages.filter(p => {
            if (p.isHeader) return false;
            return (p.label && p.label.toLowerCase().includes(q)) ||
                   (p.id && p.id.toLowerCase().includes(q)) ||
                   (p.tags && p.tags.toLowerCase().includes(q));
        });
    }

    onSearchQueryChanged: {
        const list = app.filteredPages;
        if (list.length > 0 && !list.some(p => p.id === app.page)) {
            app.page = list[0].id;
        }
    }

    // Pages that were merged into others, for links still naming them.
    readonly property var moved: ({ theme: "appearance", widgets: "bar", weather: "bar" })

    function open(id) {
        if (app.moved[id]) id = app.moved[id];
        if (app.pages.some(p => !p.isHeader && p.id === id))
            app.page = id;
    }

    // All 23 sections live in one ColumnLayout inside one ScrollView and are
    // toggled with `visible`, so the scroll offset is shared: scrolling to the
    // bottom of Displays and then opening Weather left you staring at empty
    // space below a two-line page.
    onPageChanged: {
        if (app.moved[app.page]) { app.page = app.moved[app.page]; return; }
        if (pageScroll.contentItem) pageScroll.contentItem.contentY = 0;
    }

    // Unlike every other popup this doesn't extend PopupShell (it also has to
    // load inside its own standalone window, which never had one), so it
    // never got PopupShell's background Rectangle — the panel rendered fully
    // see-through with just its individual rows drawing anything at all.
    Rectangle {
        anchors.fill: parent
        radius: Design.s(Design.radius.panel)
        color: Design.glassBg
        border.color: Design.glassBorder
        border.width: Design.border
    }

    // The current page's entry, for the header.
    readonly property var current: app.pages.find(p => !p.isHeader && p.id === app.page) || ({})

    // Ctrl+F goes to the search field, as in Files and Monitor.
    Shortcut {
        sequence: "Ctrl+F"
        onActivated: searchBox.focusInput()
    }

    // ── Frame ────────────────────────────────────────────────────────────────
    //
    // The same frame as Files, Git and Monitor: a sunken sidebar behind a
    // hairline, a header bar naming the page, the page in a column of
    // readable width, and a status bar along the bottom. Settings used to be
    // the odd one out — one flat surface with the rail floating on it, no
    // page title (the window said "Settings" and nothing said which page),
    // and every card and button stretched across the whole window, so a page
    // with three switches was mostly empty grey.
    Loader {
        anchors.fill: parent
        active: app.setupMode
        sourceComponent: Component {
            Sections.SetupWizard {
                page: app.page
                onFinished: app.close()
                onOpenPage: id => app.open(id)
                onRestarting: if (app.standalone) app.closeRequested()
            }
        }
    }

    RowLayout {
        visible: !app.setupMode
        anchors.fill: parent
        anchors.margins: Design.border
        spacing: 0

        // ── Sidebar ──────────────────────────────────────────────────────────
        Rectangle {
            Layout.fillHeight: true
            Layout.preferredWidth: Design.s(224)
            color: Design.sunken
            radius: Design.s(Design.radius.panel)

            // Square the right-hand corners: only the window's outer corners
            // are round.
            Rectangle {
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                width: parent.radius
                color: parent.color
            }
            Rectangle {
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.right: parent.right
                width: 1
                color: Design.line
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.topMargin: Design.s(Design.space.md)
                anchors.bottomMargin: Design.s(Design.space.md)
                anchors.leftMargin: Design.s(Design.space.sm)
                anchors.rightMargin: Design.s(Design.space.sm) + 1
                spacing: Design.s(Design.space.sm)

                // No "Settings" title: the window says it, and the apps'
                // sidebars start with what you navigate to.
                Field {
                    id: searchBox
                    Layout.fillWidth: true
                    Layout.preferredHeight: Design.s(36)
                    radius: height / 2
                    color: Design.raised
                    placeholder: I18n.tr("Search settings (Ctrl+F)")
                    text: app.searchQuery
                    onEdited: value => app.searchQuery = value
                }

                ListView {
                    id: railList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    model: app.filteredPages
                    clip: true
                    spacing: Design.s(2)
                    ScrollBar.vertical: OverflowBar {}

                    delegate: Loader {
                        id: railDelegate
                        required property var modelData
                        required property int index
                        width: railList.width
                        sourceComponent: modelData.isHeader ? headingRow : pageRow

                        Component {
                            id: headingRow
                            SidebarHeading { text: railDelegate.modelData.label || "" }
                        }
                        Component {
                            id: pageRow
                            SidebarItem {
                                label: railDelegate.modelData.label || ""
                                glyph: railDelegate.modelData.icon || ""
                                active: app.page === railDelegate.modelData.id
                                onClicked: app.open(railDelegate.modelData.id)
                            }
                        }
                    }
                }
            }
        }

        // ── Main ─────────────────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            EmptyState {
                visible: app.noResults
                Layout.fillWidth: true
                Layout.fillHeight: true
                icon: "\u{f002}"
                title: I18n.tr("No settings match \u201C%1\u201D", app.searchQuery.trim())
                hint: I18n.tr("Try a shorter word, or clear the search to get the full list back.")
            }

            ScrollView {
                id: pageScroll
                visible: !app.noResults
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                // The rail beside it shows an always-on bar and this pane did not,
                // so the longer half of the window was the one with no sign that
                // it scrolled — every page here is taller than the window.
                ScrollBar.vertical: OverflowBar { view: pageScroll }

            // A column of readable width, centred. Cards used to span the
            // whole pane: on a 1280 px window a row of three switches ran
            // 1000 px wide, its labels at one edge and its controls at the
            // other, and full-width buttons read as empty bars.
            ColumnLayout {
                id: pageCol
                readonly property real sidePad: Design.s(24)
                width: Math.min(pageScroll.availableWidth - sidePad * 2, Design.s(1040))
                x: Math.max(sidePad, (pageScroll.availableWidth - width) / 2)
                spacing: Design.s(Design.space.lg)

                // The page's name, as the first thing on the page and scrolling
                // with it. It was a 64px bar of its own — icon tile, name,
                // description, rule — a header strip of the kind the apps have
                // dropped: it took a band of every page to say what the rail,
                // with the same icon highlighted, already said.
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: Design.s(Design.space.xl)
                    Layout.bottomMargin: Design.s(Design.space.xs)
                    spacing: Design.s(Design.space.xs)
                    Label {
                        Layout.fillWidth: true
                        text: app.current.label || ""
                        role: "display"
                        weight: Design.weight.bold
                        elide: Text.ElideRight
                    }
                    Label {
                        Layout.fillWidth: true
                        text: app.current.desc || ""
                        dim: true
                        wrapMode: Text.WordWrap
                    }
                }

                // One page exists at a time. Every section used to be built
                // whenever Settings opened — all 25, 24 of them hidden — and a
                // section is not cheap: 13 do work on load, 8 hold processes,
                // and Wallpaper reads a directory of images. Measured on a fresh shell, opening
                // Settings added 48 MB that stayed after it closed. Leaving a
                // page now drops it; its values live in Settings, not in it.
                Loader {
                    Layout.fillWidth: true
                    active: app.page === "user"
                    visible: active
                    sourceComponent: Component {
                        Sections.UserSettingsSection {
                            width: parent ? parent.width : 0
                        }
                    }
                }

                Loader {
                    Layout.fillWidth: true
                    active: app.page === "animations"
                    visible: active
                    sourceComponent: Component {
                        Sections.AnimationSettingsSection {
                            width: parent ? parent.width : 0
                        }
                    }
                }

                Loader {
                    Layout.fillWidth: true
                    active: app.page === "windows"
                    visible: active
                    sourceComponent: Component {
                        Sections.WindowSettingsSection {
                            width: parent ? parent.width : 0
                        }
                    }
                }

                Loader {
                    Layout.fillWidth: true
                    active: app.page === "appearance"
                    visible: active
                    // The theme first, then what is set over it: the accent,
                    // and how other programs follow. They were two pages,
                    // Themes and Appearance, each half of the same choice.
                    sourceComponent: Component {
                        ColumnLayout {
                            width: parent ? parent.width : 0
                            spacing: Design.s(Design.space.lg)
                            Sections.ThemeSettingsSection { Layout.fillWidth: true }
                            Sections.AppearanceSettingsSection { Layout.fillWidth: true }
                        }
                    }
                }

                Loader {
                    Layout.fillWidth: true
                    active: app.page === "monitors"
                    visible: active
                    sourceComponent: Component {
                        Sections.MonitorSettingsSection {
                            width: parent ? parent.width : 0
                        }
                    }
                }

                Loader {
                    Layout.fillWidth: true
                    active: app.page === "bar"
                    visible: active
                    // What the bar shows (it was the Widgets page), then how.
                    sourceComponent: Component {
                        ColumnLayout {
                            width: parent ? parent.width : 0
                            spacing: Design.s(Design.space.lg)
                            Sections.WidgetsSettingsSection { Layout.fillWidth: true }
                            Sections.BarSettingsSection { Layout.fillWidth: true }
                            // The weather is shown in the bar (and the Control
                            // Center); its key and city were a page of their own.
                            Sections.WeatherSettingsSection {
                                Layout.fillWidth: true
                                apiKey: Settings.weatherApiKey
                                cityId: Settings.weatherCityId
                                unit: Settings.weatherUnit
                                onApiKeyChangedByUser: v => Settings.setWeatherApiKey(v)
                                onCityIdChangedByUser: v => Settings.set("weatherCityId", v)
                                onUnitChangedByUser: v => Settings.set("weatherUnit", v)
                            }
                        }
                    }
                }

                Loader {
                    Layout.fillWidth: true
                    active: app.page === "capture"
                    visible: active
                    sourceComponent: Component {
                        Sections.CaptureSettingsSection {
                            width: parent ? parent.width : 0
                        }
                    }
                }

                Loader {
                    Layout.fillWidth: true
                    active: app.page === "defaultapps"
                    visible: active
                    sourceComponent: Component {
                        Sections.DefaultAppsSettingsSection {
                            width: parent ? parent.width : 0
                        }
                    }
                }

                Loader {
                    Layout.fillWidth: true
                    active: app.page === "gamemode"
                    visible: active
                    sourceComponent: Component {
                        Sections.GameModeSettingsSection {
                            width: parent ? parent.width : 0
                        }
                    }
                }

                Loader {
                    Layout.fillWidth: true
                    active: app.page === "maintenance"
                    visible: active
                    sourceComponent: Component {
                        Sections.MaintenanceSettingsSection {
                            width: parent ? parent.width : 0
                        }
                    }
                }

                // Locking, the fingerprint and the login screen, gathered from
                // Power & Battery and User Profile.
                Loader {
                    Layout.fillWidth: true
                    active: app.page === "lock"
                    visible: active
                    sourceComponent: Component {
                        ColumnLayout {
                            width: parent ? parent.width : 0
                            spacing: Design.s(Design.space.lg)
                            Sections.PowerSettingsSection { Layout.fillWidth: true; part: "lock" }
                            Sections.UserSettingsSection { Layout.fillWidth: true; part: "lock" }
                        }
                    }
                }

                Loader {
                    Layout.fillWidth: true
                    active: app.page === "updates"
                    visible: active
                    sourceComponent: Component {
                        Sections.MaintenanceSettingsSection {
                            width: parent ? parent.width : 0
                            part: "updates"
                        }
                    }
                }

                Loader {
                    Layout.fillWidth: true
                    active: app.page === "privacy"
                    visible: active
                    sourceComponent: Component {
                        Sections.PrivacySettingsSection {
                            width: parent ? parent.width : 0
                        }
                    }
                }

                Loader {
                    Layout.fillWidth: true
                    active: app.page === "region"
                    visible: active
                    sourceComponent: Component {
                        Sections.RegionSettingsSection {
                            width: parent ? parent.width : 0
                        }
                    }
                }

                Loader {
                    Layout.fillWidth: true
                    active: app.page === "nightlight"
                    visible: active
                    sourceComponent: Component {
                        Sections.NightLightSettingsSection {
                            width: parent ? parent.width : 0
                        }
                    }
                }

                Loader {
                    Layout.fillWidth: true
                    active: app.page === "network"
                    visible: active
                    sourceComponent: Component {
                        Sections.NetworkSettingsSection {
                            width: parent ? parent.width : 0
                        }
                    }
                }

                Loader {
                    Layout.fillWidth: true
                    active: app.page === "remote"
                    visible: active
                    sourceComponent: Component {
                        Sections.RemoteSettingsSection {
                            width: parent ? parent.width : 0
                        }
                    }
                }

                Loader {
                    Layout.fillWidth: true
                    active: app.page === "bluetooth"
                    visible: active
                    sourceComponent: Component {
                        Sections.BluetoothSettingsSection {
                            width: parent ? parent.width : 0
                        }
                    }
                }

                Loader {
                    Layout.fillWidth: true
                    active: app.page === "audio"
                    visible: active
                    sourceComponent: Component {
                        Sections.AudioSettingsSection {
                            width: parent ? parent.width : 0
                        }
                    }
                }

                Loader {
                    Layout.fillWidth: true
                    active: app.page === "power"
                    visible: active
                    sourceComponent: Component {
                        Sections.PowerSettingsSection {
                            width: parent ? parent.width : 0
                        }
                    }
                }

                Loader {
                    Layout.fillWidth: true
                    active: app.page === "focus"
                    visible: active
                    sourceComponent: Component {
                        Sections.FocusSettingsSection {
                            width: parent ? parent.width : 0
                        }
                    }
                }

                Loader {
                    Layout.fillWidth: true
                    active: app.page === "notifications"
                    visible: active
                    sourceComponent: Component {
                        Sections.FocusSettingsSection {
                            part: "notifications"
                            width: parent ? parent.width : 0
                        }
                    }
                }

                Loader {
                    Layout.fillWidth: true
                    active: app.page === "input"
                    visible: active
                    sourceComponent: Component {
                        Sections.InputSettingsSection {
                            width: parent ? parent.width : 0
                        }
                    }
                }

                // Reads and writes Settings itself, like every other section.
                // Passing the values through here is how the remove button came
                // to send an index to a handler comparing layout codes.
                Loader {
                    Layout.fillWidth: true
                    active: app.page === "keyboard"
                    visible: active
                    sourceComponent: Component {
                        Sections.KeyboardSettingsSection {
                            width: parent ? parent.width : 0
                        }
                    }
                }

                Loader {
                    Layout.fillWidth: true
                    active: app.page === "shortcuts"
                    visible: active
                    // Changing a key, then the full list. Changing was on the
                    // Keyboard page, which sent you here to see the list.
                    sourceComponent: Component {
                        ColumnLayout {
                            width: parent ? parent.width : 0
                            spacing: Design.s(Design.space.lg)
                            Sections.KeyboardSettingsSection { Layout.fillWidth: true; shortcutsOnly: true }
                            Sections.ShortcutsSettingsSection { Layout.fillWidth: true }
                        }
                    }
                }

                Loader {
                    Layout.fillWidth: true
                    active: app.page === "wallpaper"
                    visible: active
                    sourceComponent: Component {
                        Sections.WallpaperSettingsSection {
                            width: parent ? parent.width : 0
                            wallpaperDir: Settings.wallpaperDir
                            onWallpaperDirChangedByUser: v => Settings.set("wallpaperDir", v)
                        }
                    }
                }

                Loader {
                    Layout.fillWidth: true
                    active: app.page === "startup"
                    visible: active
                    sourceComponent: Component {
                        Sections.StartupSettingsSection {
                            width: parent ? parent.width : 0
                        }
                    }
                }

                Loader {
                    Layout.fillWidth: true
                    active: app.page === "about"
                    visible: active
                    sourceComponent: Component {
                        Sections.AboutSettingsSection {
                            width: parent ? parent.width : 0
                            onNavigate: id => app.open(id)
                        }
                    }
                }

                Item { Layout.preferredHeight: Design.s(Design.space.xl) }
            }
            }

            // Status bar, the same strip as along the bottom of every app.
            AppStatusBar {
                Layout.fillWidth: true
                Label {
                    Layout.fillWidth: true
                    text: I18n.tr("Changes save automatically")
                    role: "caption"
                    dim: true
                    elide: Text.ElideRight
                }
                Label {
                    text: I18n.tr("Ctrl+F search  ·  Esc close")
                    role: "caption"
                    color: Design.textFaint
                }
            }
        }
    }
}
