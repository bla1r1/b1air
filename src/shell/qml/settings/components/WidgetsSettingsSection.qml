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
    component WidgetRow: SwitchRow {
        id: row
        property string boolKey: ""
        property bool boolValue: true
        readonly property bool shown: row.boolValue
        checked: row.shown
        onToggled: Settings.set(row.boolKey, !row.shown)
    }




    // ── Dock ─────────────────────────────────────────────────────────────────
    SettingsGroup {
        title: I18n.tr("Dock")
        icon: "\u{f0db}"

        SwitchRow {
            label: I18n.tr("Show the dock")
            subtitle: I18n.tr("Right-click an app in it to keep it there or let it go")
            checked: Settings.dockEnabled === true
            onToggled: Settings.set("dockEnabled", Settings.dockEnabled !== true)
        }
        SwitchRow {
            visible: Settings.dockEnabled === true
            label: I18n.tr("Hide it until the pointer reaches the bottom edge")
            checked: Settings.dockAutohide === true
            onToggled: Settings.set("dockAutohide", Settings.dockAutohide !== true)
        }
        SwitchRow {
            visible: Settings.dockEnabled === true
            label: I18n.tr("Magnify icons under the pointer")
            checked: Settings.dockMagnify !== false
            onToggled: Settings.set("dockMagnify", Settings.dockMagnify === false)
        }
        SettingsRow {
            visible: Settings.dockEnabled === true
            label: I18n.tr("Icon size")
            Stepper {
                valueText: (Settings.dockIconSize || 48) + " px"
                onDecrement: Settings.set("dockIconSize", Math.max(32, (Settings.dockIconSize || 48) - 4))
                onIncrement: Settings.set("dockIconSize", Math.min(72, (Settings.dockIconSize || 48) + 4))
            }
        }
    }

    // ── Top bar ──────────────────────────────────────────────────────────────
    SettingsGroup {
        title: I18n.tr("Top Bar Modules")

        WidgetRow {
            boolKey: "barShowApps"; boolValue: Settings.barShowApps
            title: I18n.tr("Apps Button"); note: I18n.tr("Opens the launcher; right-click opens Spotlight")
        }
        WidgetRow {
            boolKey: "barShowPinned"; boolValue: Settings.barShowPinned
            title: I18n.tr("Pinned Apps")
        }
        WidgetRow {
            boolKey: "barShowWorkspaces"; boolValue: Settings.barShowWorkspaces
            title: I18n.tr("Workspaces")
        }
        WidgetRow {
            boolKey: "barShowMedia"; boolValue: Settings.barShowMedia
            title: I18n.tr("Now Playing")
        }
        WidgetRow {
            boolKey: "barShowWeather"; boolValue: Settings.barShowWeather
            title: I18n.tr("Weather")
        }
        WidgetRow {
            boolKey: "barShowStats"; boolValue: Settings.barShowStats
            title: I18n.tr("CPU & Memory")
        }
        WidgetRow {
            boolKey: "barShowTray"; boolValue: Settings.barShowTray
            title: I18n.tr("System Tray")
        }
    }

    // The Control Center's tiles and cards. The panel can already hide them
    // in its own edit mode (the pencil); this is the same list
    // (ccHiddenTiles, ccHiddenCards), where Settings is looked for it — the
    // Widgets page promised it and had only the bar.
    component CcRow: SwitchRow {
        id: ccRow
        property string listKey: ""
        property string list: ""
        property string itemId: ""
        readonly property bool shown: !Settings.isWidgetHidden(ccRow.list, ccRow.itemId)
        checked: ccRow.shown
        onToggled: Settings.setWidgetHidden(ccRow.listKey, ccRow.itemId, ccRow.shown)
    }

    SettingsGroup {
        title: I18n.tr("Control Center")
        subtitle: I18n.tr("Which tiles and cards the panel shows. Their order is changed in the panel itself, with the pencil")
        icon: "\u{f062e}"

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
