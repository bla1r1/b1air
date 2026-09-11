pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// =============================================================================
// Weather, from the one place that fetches it.
//
// This ran its own `curl https://wttr.in/?format=%t|%C|%l` on a 30-minute
// timer, while the daemon separately fetched the full forecast for the
// calendar panel. Two requests, two caches, two schedules — so the bar and the
// calendar showed different numbers at the same moment: +18°C in the bar,
// 21°C in the panel beside it. Worse, the second fetch ignored the
// OpenWeather key on the Weather settings page, so configuring a key changed
// the calendar and left the bar on wttr.in.
//
// Everything now comes from `b1air-daemon weather json`, which is the fetch
// that already honours that setting and already caches. "Current" is the last
// hourly slot at or before now — the same rule the daemon's own
// weather_get_current_info uses, so the bar and the panel cannot disagree.
// =============================================================================

Singleton {
    id: root

    property string temp: "--°"
    property string condition: ""
    property string icon: "\u{f0590}"
    property string location: "Weather"
    property bool loaded: false

    /** The whole forecast, so callers do not each spawn their own fetch. */
    property var forecast: []

    /** The hourly slot that is current now, or null before the first fetch. */
    readonly property var currentHour: {
        if (!root.forecast || root.forecast.length === 0)
            return null;
        const hours = root.forecast[0].hourly || [];
        if (hours.length === 0)
            return null;

        const now = Qt.formatDateTime(new Date(), "hh:mm");
        let pick = hours[0];
        for (const h of hours) {
            if (String(h.time) <= now)
                pick = h;
        }
        return pick;
    }

    function _iconFor(desc) {
        const cond = String(desc || "").toLowerCase();
        if (cond.includes("sun") || cond.includes("clear")) return "\u{f0599}";
        if (cond.includes("rain") || cond.includes("drizzle") || cond.includes("shower")) return "\u{f0597}";
        if (cond.includes("snow") || cond.includes("ice")) return "\u{f0598}";
        if (cond.includes("thunder") || cond.includes("storm")) return "\u{f0593}";
        if (cond.includes("cloud") || cond.includes("overcast")) return "\u{f0590}";
        return "\u{f0599}";
    }

    /** "C" or "F", from the forecast, which carries the unit it was fetched in. */
    property string unit: "C"

    /** @param force skip the daemon's 15-minute cache — after a settings change. */
    function refresh(force) {
        fetcher.command = ["b1air-daemon", "weather", force ? "refresh" : "json"];
        fetcher.running = false;
        fetcher.running = true;
    }

    Process {
        id: fetcher
        running: true
        command: ["b1air-daemon", "weather", "json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const doc = JSON.parse(this.text);
                    if (!doc || !Array.isArray(doc.forecast) || doc.forecast.length === 0)
                        return;
                    root.forecast = doc.forecast;
                    root.unit = doc.unit === "F" ? "F" : "C";

                    const today = doc.forecast[0];
                    const hour = root.currentHour;
                    root.temp = (hour ? hour.temp : today.max) + "\u00B0" + root.unit;
                    root.condition = today.desc || "";
                    root.icon = root._iconFor(root.condition);
                    if (doc.location)
                        root.location = doc.location;
                    root.loaded = true;
                } catch (e) {
                    // A daemon that is not up yet, or a fetch that failed.
                    // Keep whatever was shown rather than blanking the bar.
                }
            }
        }
    }

    // The daemon caches, so this is a read of that cache rather than a network
    // request; the fetch behind it has its own, longer, expiry.
    Timer {
        interval: 900000 // 15 minutes
        running: true
        repeat: true
        onTriggered: root.refresh()
    }
}
