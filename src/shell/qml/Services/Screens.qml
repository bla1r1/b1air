pragma Singleton

import QtQuick
import Quickshell
import B1air.Daemon

// =============================================================================
// Which screen to put a transient surface on.
//
// The toasts, the OSD and the polkit dialog each hard-coded
// Quickshell.screens[0], so on a two-monitor desktop a notification, a volume
// indicator and — worst of the three — a password prompt all appeared on the
// first monitor whatever the user was looking at.
//
// ScreenshotOverlay looked like it did better with `Quickshell.cursorScreen`,
// but that property does not exist: the Quickshell singleton exposes screens,
// and nothing else. The assignment evaluated to undefined and the window landed
// on the default screen anyway.
//
// Sway knows which output has focus, so ask it. Deliberately not a poller: a
// surface that is about to appear calls refresh(), which is a handful of
// processes a day rather than one every few seconds forever.
// =============================================================================

Singleton {
    id: root

    /** Name of the focused output, "" until the first refresh lands. */
    property string focusedName: ""

    /** The ShellScreen to place a surface on. Never null while a screen exists. */
    readonly property var focused: {
        for (const s of Quickshell.screens)
            if (s.name === root.focusedName) return s;
        return Quickshell.screens.length > 0 ? Quickshell.screens[0] : null;
    }

    /**
     * The main display: the one named in Settings → Displays (stored as
     * barPrimaryOutput) while it is connected, else the first one sway
     * reports. It carries the full bar, and the daemon gives it workspace 1
     * and, at login, the focus.
     */
    readonly property string primaryName: {
        const pinned = Settings.barPrimaryOutput || "";
        const all = Quickshell.screens;
        for (const s of all)
            if (s.name === pinned) return pinned;
        return all.length > 0 ? all[0].name : "";
    }
    /** True when the main display was chosen rather than taken as the first. */
    readonly property bool primaryChosen: (Settings.barPrimaryOutput || "") === root.primaryName
        && root.primaryName !== ""

    function refresh() {
        Sway.query("outputs", outs => {
            // Not under sway, or sway is not answering: `focused` falls back
            // to the first screen, which is where these surfaces used to be
            // pinned anyway.
            if (!Array.isArray(outs))
                return;
            for (const o of outs) {
                if (o.focused) { root.focusedName = o.name; return; }
            }
        });
    }

    Component.onCompleted: refresh()
}
