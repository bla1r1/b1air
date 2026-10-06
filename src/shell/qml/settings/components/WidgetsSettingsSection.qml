import QtQuick
import QtQuick.Layouts
import "../../Ui"
import "../../Services"

// =============================================================================
// What the bar shows.
//
// The Control Center's tiles and the calendar's panels used to be listed here
// too, as three cards of switches. They are arranged in the panels themselves
// now — a "tune" button in each header turns the panel into something you drag
// tiles around in, resize them and take them out of, with the result in front
// of you. A list of nineteen switches in another window, where the only way to
// see what one did was to close it and open the panel, was the wrong place for
// it however carefully the labels were written.
//
// The bar stays. It is a strip of islands a few pixels tall with nowhere to
// put a badge, and it is the one surface whose modules were already switchable
// from here.
// =============================================================================

ColumnLayout {
    id: section

    Layout.fillWidth: true
    spacing: Design.s(Design.space.lg)


    // One row, so that seven switches are seven declarations of what they
    // switch rather than seven copies of the same layout.
    component WidgetRow: RowLayout {
        id: row

        property string boolKey: ""
        property bool boolValue: true
        property string title: ""
        property string subtitle: ""

        readonly property bool shown: row.boolValue

        Layout.fillWidth: true
        spacing: Design.s(Design.space.md)

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Design.s(2)
            // Both fill: a ColumnLayout whose children only state an implicit
            // width stays that wide, so the description column never took the
            // slack and the picker beside it started wherever each subtitle
            // happened to end.
            Label { Layout.fillWidth: true; text: row.title; weight: Design.weight.semibold }
            Label { Layout.fillWidth: true; text: row.subtitle; role: "caption"; dim: true
                    elide: Text.ElideRight }
        }


        Toggle {
            checked: row.shown
            onToggled: Settings.set(row.boolKey, !row.shown)
        }
    }




    // ── Top bar ──────────────────────────────────────────────────────────────
    Card {
        title: I18n.tr("Top Bar Modules")
        subtitle: I18n.tr("Which islands the bar draws")

        WidgetRow {
            boolKey: "barShowApps"; boolValue: Settings.barShowApps
            title: I18n.tr("Apps Button"); subtitle: I18n.tr("Opens the launcher; right-click opens Spotlight")
        }
        WidgetRow {
            boolKey: "barShowPinned"; boolValue: Settings.barShowPinned
            title: I18n.tr("Pinned Apps"); subtitle: I18n.tr("The apps pinned from the launcher")
        }
        WidgetRow {
            boolKey: "barShowWorkspaces"; boolValue: Settings.barShowWorkspaces
            title: I18n.tr("Workspaces"); subtitle: I18n.tr("The numbered workspace strip")
        }
        WidgetRow {
            boolKey: "barShowMedia"; boolValue: Settings.barShowMedia
            title: I18n.tr("Now Playing"); subtitle: I18n.tr("Track title from the active media player")
        }
        WidgetRow {
            boolKey: "barShowWeather"; boolValue: Settings.barShowWeather
            title: I18n.tr("Weather"); subtitle: I18n.tr("Temperature and condition badge")
        }
        WidgetRow {
            boolKey: "barShowStats"; boolValue: Settings.barShowStats
            title: I18n.tr("CPU & Memory"); subtitle: I18n.tr("Processor load and memory in use")
        }
        WidgetRow {
            boolKey: "barShowTray"; boolValue: Settings.barShowTray
            title: I18n.tr("System Tray"); subtitle: I18n.tr("Icons from applications running in the background")
        }
    }

    // The Control Center's tiles and cards. The panel can already hide them
    // in its own edit mode (the pencil); this is the same list
    // (ccHiddenTiles, ccHiddenCards), where Settings is looked for it — the
    // Widgets page promised it and had only the bar.
    component CcRow: RowLayout {
        id: ccRow
        property string listKey: ""
        property string list: ""
        property string itemId: ""
        property string title: ""
        readonly property bool shown: !Settings.isWidgetHidden(ccRow.list, ccRow.itemId)
        Layout.fillWidth: true
        spacing: Design.s(Design.space.md)
        Label { Layout.fillWidth: true; text: ccRow.title; weight: Design.weight.semibold }
        Toggle {
            checked: ccRow.shown
            onToggled: Settings.setWidgetHidden(ccRow.listKey, ccRow.itemId, ccRow.shown)
        }
    }

    Card {
        title: I18n.tr("Control Center")
        subtitle: I18n.tr("Which tiles and cards the panel shows. Their order is changed in the panel itself, with the pencil")
        icon: "\u{f062e}"
        accentColor: Design.blue

        Repeater {
            model: [
                { id: "wifi",       title: I18n.tr("Wi-Fi") },
                { id: "bluetooth",  title: I18n.tr("Bluetooth") },
                { id: "dnd",        title: I18n.tr("Do Not Disturb") },
                { id: "nightlight", title: I18n.tr("Night Light") },
                { id: "powermode",  title: I18n.tr("Power Mode") },
                { id: "gamemode",   title: I18n.tr("Game Mode") },
                { id: "caffeine",   title: I18n.tr("Caffeine") },
                { id: "screenshot", title: I18n.tr("Screenshot") },
                { id: "dropper",    title: I18n.tr("Color Dropper") },
                { id: "remote",     title: I18n.tr("Remote Desktop") }
            ]
            delegate: CcRow {
                required property var modelData
                listKey: "ccHiddenTiles"; list: Settings.ccHiddenTiles
                itemId: modelData.id; title: modelData.title
            }
        }

        SectionLabel { text: I18n.tr("Cards") }

        Repeater {
            model: [
                { id: "sliders", title: I18n.tr("Volume and brightness") },
                { id: "weather", title: I18n.tr("Weather") },
                { id: "media",   title: I18n.tr("Media player") },
                { id: "session", title: I18n.tr("Lock, sleep, reboot and power off") }
            ]
            delegate: CcRow {
                required property var modelData
                listKey: "ccHiddenCards"; list: Settings.ccHiddenCards
                itemId: modelData.id; title: modelData.title
            }
        }
    }
}
