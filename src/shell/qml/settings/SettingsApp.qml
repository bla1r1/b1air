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
    // Where "Back" goes from a page the setup's news opened ("setup.news").
    property string returnPage: ""
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
    // The pages: settings/SettingsPages.qml, shared with Spotlight.
    SettingsPages { id: pageIndex }
    readonly property var pages: pageIndex.list

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
        if (app.page === "setup" || app.page.indexOf("setup.") === 0) app.returnPage = "";
        if (pageScroll.contentItem) pageScroll.contentItem.contentY = 0;
    }

    // Unlike every other popup this doesn't extend PopupShell (it also has to
    // load inside its own standalone window, which never had one), so it
    // never got PopupShell's background Rectangle — the panel rendered fully
    // see-through with just its individual rows drawing anything at all.
    // In its own window the page is opaque and only the sidebar is glass, as
    // in the other apps; in the shell the whole panel is glass.
    Rectangle {
        anchors.fill: parent
        anchors.leftMargin: app.standalone && Design.translucent ? Design.s(224) + Design.border : 0
        radius: app.standalone ? 0 : Design.s(Design.radius.panel)
        color: app.standalone ? Design.surface : Design.glassBg
        border.color: app.standalone ? "transparent" : Design.glassBorder
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
                onOpenPage: id => { app.returnPage = "setup.news"; app.open(id); }
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
            color: Design.glassSidebar
            radius: app.standalone ? 0 : Design.s(Design.radius.panel)

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
                    ScrollBar.vertical: OverflowBar { id: railBar }

                    delegate: Loader {
                        id: railDelegate
                        required property var modelData
                        required property int index
                        // Clear of the scroll bar, which is drawn over the list:
                        // a long name ("Віддалений робочий стіл") ran under it.
                        width: railList.width - (railBar.visible && railList.contentHeight > railList.height ? Design.s(10) : 0)
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
                    // Back to the news this page was opened from.
                    Pill {
                        visible: app.returnPage !== ""
                        icon: "\u{f0141}"
                        label: I18n.tr("What's new")
                        onClicked: { app.page = app.returnPage; app.returnPage = ""; }
                    }
                    Label {
                        Layout.fillWidth: true
                        text: app.current.label || ""
                        role: "display"
                        weight: Design.weight.bold
                        elide: Text.ElideRight
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
