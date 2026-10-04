import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import "../Ui"
import "../Services"
import "components" as Sections

Item {
    id: app

    property bool framed: false
    property string page: "monitors"
    property string searchQuery: ""

    Component.onCompleted: if (!app.page) app.page = "monitors"

    readonly property var pages: [
        // ── Hardware & Connectivity ───────────────────────────────────────────
        { isHeader: true, label: I18n.tr("HARDWARE & NETWORK") },
        { id: "monitors",    icon: "\u{f0379}", label: I18n.tr("Displays"), desc: I18n.tr("Resolution, refresh rate, scaling and arrangement of your screens"),         color: Design.sapphire, tags: "display resolution refresh rate scaling monitor screen mirror hdr" },
        { id: "audio",       icon: "\u{f057e}", label: I18n.tr("Sound & Volume"), desc: I18n.tr("Output and input devices, volumes and per-app levels"),   color: Design.teal,     tags: "sound volume sink source mic microphone devices wireplumber equalizer audio output input" },
        { id: "network",     icon: "\u{f0928}", label: I18n.tr("Network & Wi-Fi"), desc: I18n.tr("Wi-Fi, wired connections and VPNs"),  color: Design.lavender, tags: "wifi internet connection ethernet ssid ip address vpn network" },
        { id: "bluetooth",   icon: "\u{f00af}", label: I18n.tr("Bluetooth"), desc: I18n.tr("Pair and connect headphones, mice, keyboards and controllers"),        color: Design.mauve,    tags: "bluetooth bt pair devices headset connect mouse keyboard controller" },
        { id: "power",       icon: "\u{f0084}", label: I18n.tr("Power & Battery"), desc: I18n.tr("Power profile, battery charging and when the screen sleeps"),  color: Design.green,    tags: "battery sleep suspend hibernate timeout brightness charge energy power" },

        // ── Personalization & Workspace ───────────────────────────────────────
        { isHeader: true, label: I18n.tr("PERSONALIZATION") },
        { id: "appearance",  icon: "\u{f0376}", label: I18n.tr("Appearance"), desc: I18n.tr("Accent colour, light and dark apps, and window effects"),       color: Design.mauve,    tags: "accent color font gtk icons cursor style blur shadows corners" },
        { id: "theme",       icon: "\u{f0765}", label: I18n.tr("Themes"), desc: I18n.tr("Colour palettes for the desktop and every app in it"),           color: Design.mauve,    tags: "theme palette colours colors catppuccin tokyo night import export create custom" },
        { id: "wallpaper",   icon: "\u{f02ca}", label: I18n.tr("Wallpaper"), desc: I18n.tr("The picture behind your windows and on the login screen"),        color: Design.pink,     tags: "background wallpaper pictures desktop image slideshow photos" },
        { id: "bar",         icon: "\u{f07e}",  label: I18n.tr("Native Top Bar"), desc: I18n.tr("What the top bar shows, where, and at what size"), color: Design.blue,     tags: "top bar panel position modules icons style workspaces scale ui dpi" },
        { id: "widgets",     icon: "\u{f0331}", label: I18n.tr("Widgets"), desc: I18n.tr("Tiles in the Control Center and modules in the top bar"),          color: Design.blue,     tags: "widgets buttons tiles modules control center calendar top bar show hide customize customise remove add panels" },
        // not "blur"/"corners": those live on Appearance, and listing them here
        // sent a search for either to a page that has neither.
        { id: "windows",     icon: "\u{f0379}", label: I18n.tr("Window & Gaps"), desc: I18n.tr("Gaps, borders and how new windows are tiled"),    color: Design.sapphire, tags: "gaps border padding tiling sway layout inner outer smart borders smart gaps autotiling dwindle split hyprland spiral" },
        { id: "animations",  icon: "\u{f0e1e}", label: I18n.tr("Animations"), desc: I18n.tr("How windows and workspaces move, and how faded unfocused ones are"), color: Design.mauve, tags: "animation animations motion slide fade popin duration speed swipe inactive opacity transparency special workspace scratchpad overview expose hyprland effects" },
        { id: "nightlight",  icon: "\u{f0599}", label: I18n.tr("Night Light"), desc: I18n.tr("Warmer screen colours at night, and how warm"),      color: Design.yellow,   tags: "night light blue light temperature schedule eye protect" },

        // ── Input & Navigation ────────────────────────────────────────────────
        { isHeader: true, label: I18n.tr("INPUT & SHORTCUTS") },
        { id: "keyboard",    icon: "\u{f030c}", label: I18n.tr("Keyboard"), desc: I18n.tr("Layouts, switching between them, and key remapping"),         color: Design.peach,    tags: "keyboard layout switch xkb remap shortcuts language input sources alt shift" },
        { id: "input",       icon: "\u{f0523}", label: I18n.tr("Mouse & Touchpad"), desc: I18n.tr("Pointer speed, scrolling and touchpad gestures"), color: Design.peach,    tags: "mouse touchpad sensitivity scroll tap acceleration natural pointer click magic apple gestures swipe" },
        { id: "shortcuts",   icon: "\u{f11c}",  label: I18n.tr("Shortcuts"), desc: I18n.tr("Every key binding, and changing them"),        color: Design.sapphire, tags: "shortcuts keybinds keys hotkeys sway bindings commands" },

        // ── Applications & Focus ──────────────────────────────────────────────
        { isHeader: true, label: I18n.tr("APPS & FOCUS") },
        { id: "defaultapps", icon: "\u{f0ac}",  label: I18n.tr("Default Apps"), desc: I18n.tr("Which app opens links, folders, text and media"),     color: Design.teal,     tags: "default applications browser terminal file manager editor mime types" },
        { id: "focus",       icon: "\u{f051e}", label: I18n.tr("Screen Time & DND"), desc: I18n.tr("Screen time, breaks and Do Not Disturb"),color: Design.teal,     tags: "screen time dnd do not disturb timer notifications focus pomodoro analytics" },
        { id: "startup",     icon: "\u{f0459}", label: I18n.tr("Startup Apps"), desc: I18n.tr("Apps that start when you log in"),     color: Design.yellow,   tags: "startup autostart boot launch apps systemd login" },
        { id: "capture",     icon: "\u{f016d}", label: I18n.tr("Screenshots"), desc: I18n.tr("Where screenshots and recordings go, and how they are taken"),      color: Design.pink,     tags: "screenshot capture grim slurp record screen area video gif" },
        { id: "weather",     icon: "\u{f0590}", label: I18n.tr("Weather"), desc: I18n.tr("Location and units for the weather in the top bar"),          color: Design.sapphire, tags: "weather temperature forecast location open-meteo city climate" },
        { id: "gamemode",    icon: "\u{f11b}",  label: I18n.tr("Game Mode"), desc: I18n.tr("One switch for less latency and fewer effects while playing"),        color: Design.red,      tags: "game mode performance vr fstrim process priority latency boost" },

        // ── System & Administration ───────────────────────────────────────────
        { isHeader: true, label: I18n.tr("SYSTEM") },
        { id: "user",        icon: "\u{f007}",  label: I18n.tr("User Profile"), desc: I18n.tr("Your name, picture and account"),     color: Design.mauve,    tags: "user profile avatar name username password account hostname fingerprint fprint" },
        { id: "remote",      icon: "\u{f0379}", label: I18n.tr("Remote Desktop"), desc: I18n.tr("Let another computer see or control this one"),   color: Design.blue,     tags: "remote desktop vnc rdp ssh anydesk screen sharing wayvnc" },
        { id: "maintenance", icon: "\u{f0187}", label: I18n.tr("Maintenance"), desc: I18n.tr("Updates, backups, cleanup and restore points"),      color: Design.green,    tags: "maintenance clean disk cache logs cleanup packages pacman apt dnf zypper trim system" },
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

    function open(id) {
        if (app.pages.some(p => !p.isHeader && p.id === id))
            app.page = id;
    }

    // All 23 sections live in one ColumnLayout inside one ScrollView and are
    // toggled with `visible`, so the scroll offset is shared: scrolling to the
    // bottom of Displays and then opening Weather left you staring at empty
    // space below a two-line page.
    onPageChanged: if (pageScroll.contentItem) pageScroll.contentItem.contentY = 0;

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
    RowLayout {
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
                ScrollBar.vertical: OverflowBar {}

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
                    sourceComponent: Component {
                        Sections.AppearanceSettingsSection {
                            width: parent ? parent.width : 0
                        }
                    }
                }

                Loader {
                    Layout.fillWidth: true
                    active: app.page === "theme"
                    visible: active
                    sourceComponent: Component {
                        Sections.ThemeSettingsSection {
                            width: parent ? parent.width : 0
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
                    sourceComponent: Component {
                        Sections.BarSettingsSection {
                            width: parent ? parent.width : 0
                        }
                    }
                }

                Loader {
                    Layout.fillWidth: true
                    active: app.page === "widgets"
                    visible: active
                    sourceComponent: Component {
                        Sections.WidgetsSettingsSection {
                            width: parent ? parent.width : 0
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
                    sourceComponent: Component {
                        Sections.ShortcutsSettingsSection {
                            width: parent ? parent.width : 0
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
                    active: app.page === "weather"
                    visible: active
                    sourceComponent: Component {
                        Sections.WeatherSettingsSection {
                            width: parent ? parent.width : 0
                            apiKey: Settings.weatherApiKey
                            cityId: Settings.weatherCityId
                            unit: Settings.weatherUnit
                            onApiKeyChangedByUser: v => Settings.setWeatherApiKey(v)
                            onCityIdChangedByUser: v => Settings.set("weatherCityId", v)
                            onUnitChangedByUser: v => Settings.set("weatherUnit", v)
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
