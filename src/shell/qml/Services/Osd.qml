pragma Singleton

import QtQuick
import Quickshell
import "../Ui"

// =============================================================================
// Status lines on the on-screen display
//
// A switch flipped, something copied, a mode turned on: the answer to what
// the user just did, seen once and gone. These used to be desktop
// notifications and so piled up in the notification centre's history, each
// with a toast in the corner. They go to the OSD capsule instead, where the
// volume and brightness show.
//
// From QML: Osd.show("caffeine", "Caffeine on", "Screen stays awake").
// From the daemon, or any program: a notification carrying the hint
// x-b1air-osd (or x-canonical-private-synchronous, the hint volume and
// brightness scripts use for the same purpose) is shown here and not kept;
// an int `value` hint draws the level bar (Services/Notifications.qml).
// =============================================================================

Singleton {
    id: root

    // glyph, title, detail, tone, value (0-100, or -1 for none)
    signal shown(string glyph, string title, string detail, color tone, int value)

    // Freedesktop icon names, as the daemon sends them, and our own short
    // names, to a glyph and a colour. Anything else gets the info glyph.
    readonly property var _kinds: ({
        "caffeine":                ["\u{f0f4}",  "peach"],
        "weather-clear-night":     ["\u{f0594}", "mauve"],
        "night-light":             ["\u{f0594}", "mauve"],
        "weather-clear":           ["\u{f0599}", "yellow"],
        "input-gaming":            ["\u{f11b}",  "green"],
        "input-keyboard":          ["\u{f030c}", "yellow"],
        "color-picker":            ["\u{f0592}", "pink"],
        "edit-copy":               ["\u{f018f}", "sapphire"],
        "audio-speakers":          ["\u{f04c3}", "sapphire"],
        "audio-input-microphone":  ["\u{f036c}", "peach"],
        "media-record":            ["\u{f044a}", "red"],
        "media-playback-stop":     ["\u{f04db}", "red"],
        "window":                  ["\u{f05b6}", "teal"],
        "window-close":            ["\u{f05ad}", "red"],
        "cursor":                  ["\u{f01bf}", "sapphire"],
        "display":                 ["\u{f0379}", "blue"]
    })

    function show(icon, title, detail, value) {
        // notify-send -i sends the icon as an image ("image://icon/caffeine").
        const name = String(icon || "").replace(/^image:\/\/icon\//, "").replace(/\?.*$/, "");
        const kind = root._kinds[name] || ["\u{f02fc}", "sapphire"];
        root.shown(kind[0], title || "", detail || "", Design[kind[1]] || Design.sapphire,
                   value === undefined || value === null ? -1 : value);
    }
}
