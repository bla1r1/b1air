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
        title: "Top Bar Modules"
        subtitle: "Which islands the bar draws"

        WidgetRow {
            boolKey: "barShowApps"; boolValue: Settings.barShowApps
            title: "Apps Button"; subtitle: "Opens the launcher; right-click opens Spotlight"
        }
        WidgetRow {
            boolKey: "barShowPinned"; boolValue: Settings.barShowPinned
            title: "Pinned Apps"; subtitle: "The apps pinned from the launcher"
        }
        WidgetRow {
            boolKey: "barShowWorkspaces"; boolValue: Settings.barShowWorkspaces
            title: "Workspaces"; subtitle: "The numbered workspace strip"
        }
        WidgetRow {
            boolKey: "barShowMedia"; boolValue: Settings.barShowMedia
            title: "Now Playing"; subtitle: "Track title from the active media player"
        }
        WidgetRow {
            boolKey: "barShowWeather"; boolValue: Settings.barShowWeather
            title: "Weather"; subtitle: "Temperature and condition badge"
        }
        WidgetRow {
            boolKey: "barShowStats"; boolValue: Settings.barShowStats
            title: "CPU & Load"; subtitle: "Processor usage and load average"
        }
        WidgetRow {
            boolKey: "barShowTray"; boolValue: Settings.barShowTray
            title: "System Tray"; subtitle: "Icons from applications running in the background"
        }
    }
}
