import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../Ui"
import "../../Services"
import B1air.Daemon

// =============================================================================
// Native Quickshell Top Bar Settings
// =============================================================================

ColumnLayout {
    id: section

    Layout.fillWidth: true
    spacing: Design.s(Design.space.lg)

    property string barPosition: Settings.barPosition || "top"
    property bool barClock24h: Settings.barClock24h !== undefined ? Settings.barClock24h : true

    function reloadTopBar() {
        Daemon.reload();
    }

    // ── 1. Position & Layout ─────────────────────────────────────────────────
    // The module switches that were here are on the Widgets page now,
    // alongside the four bar modules that had none and the Control Center
    // and calendar parts. Three of one list here and four of it there is
    // how two lists of the same thing drift apart. This page keeps how the
    // bar behaves — where it sits, how it tells the time; the other keeps
    // what it shows.

    // Used to live alone on its own "Interface Scale" page, back when it sat
    // next to a UI scale slider — that slider is gone (scale now follows the
    // display's own scale, set from Displays), leaving a page with nothing
    // but this one control. It's a bar setting; it belongs with the rest.
    Card {
        title: "Workspaces"
        subtitle: "How many workspace numbers the bar shows"
        icon: "\u{f0b60}"
        accentColor: Design.blue

        Stepper {
            label: "Workspace count"
            valueText: Settings.workspaceCount.toString()
            onDecrement: Settings.set("workspaceCount", Math.max(1, Settings.workspaceCount - 1))
            onIncrement: Settings.set("workspaceCount", Math.min(20, Settings.workspaceCount + 1))
        }
    }
}
