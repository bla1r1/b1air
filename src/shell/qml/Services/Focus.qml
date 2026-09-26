pragma Singleton

import QtQuick
import Quickshell
import B1air.Daemon
import Quickshell.Io

// =============================================================================
// The focus timer the settings page has always described.
//
// Settings → Screen Time & DND offers "Focus Work Duration", "Short Break
// Duration", "Long Break Duration" and "Auto-Silence Notifications in Focus
// Mode", under a card subtitled "Customize work cycles and rest duration for
// FocusTime timer". There was no timer. The four controls wrote four numbers
// into settings.json and nothing anywhere read them, so the page configured a
// feature that did not exist.
//
// This is that feature, and nothing more than the page promises: work, short
// break, work, short break, and a long break after the fourth work interval.
// Durations come from the settings the page already writes, so the controls
// mean what they say.
//
// It lives in a singleton rather than in the FocusTime popup because a timer
// that stops when you close the window is not a timer. Main.qml instantiates
// it at startup for the same reason.
// =============================================================================

Singleton {
    id: root

    // "idle" | "work" | "shortBreak" | "longBreak"
    property string phase: "idle"
    property bool running: false

    /** Seconds left in the current phase. */
    property int remaining: 0

    /** Completed work intervals in this run, for the long-break count. */
    property int completedWork: 0

    /** Work intervals before a long break. The classic Pomodoro figure. */
    readonly property int intervalsPerLongBreak: 4

    readonly property bool active: root.phase !== "idle"
    readonly property bool onBreak: root.phase === "shortBreak" || root.phase === "longBreak"

    /** What the top bar and the popup show: "24:30". */
    readonly property string remainingText: {
        const m = Math.floor(root.remaining / 60);
        const s = root.remaining % 60;
        return m + ":" + (s < 10 ? "0" + s : String(s));
    }

    readonly property string phaseLabel: {
        switch (root.phase) {
        case "work":       return "Focus";
        case "shortBreak": return "Short break";
        case "longBreak":  return "Long break";
        default:           return "";
        }
    }

    /** 0..1 through the current phase, for a progress ring. */
    readonly property real progress: {
        const total = root._phaseSeconds(root.phase);
        return total > 0 ? (total - root.remaining) / total : 0;
    }

    // ── Settings ─────────────────────────────────────────────────────────────

    function _minutes(value, fallback) {
        const n = Number(value);
        return (isFinite(n) && n > 0) ? Math.round(n) : fallback;
    }

    // Exposed as minutes so callers do not have to reach for Settings.
    //
    // FocusTimePopup in particular cannot: it imports QtCore, which brings its
    // own `Settings` type, and that shadows Services/Settings — `Settings.foo`
    // there is a type reference and reads `undefined`. Lock.qml hit the same
    // thing and aliased its import; this way the popup does not have to know.
    readonly property int workMinutes: root._minutes(Settings.focusWorkDuration, 25)
    readonly property int shortBreakMinutes: root._minutes(Settings.focusShortBreak, 5)
    readonly property int longBreakMinutes: root._minutes(Settings.focusLongBreak, 15)

    /** "Daily Screen Time Limit Goal", in hours. Same shadowing reason. */
    readonly property int dailyGoalHours: root._minutes(Settings.dailyScreenTimeGoal, 8)

    function _phaseSeconds(p) {
        switch (p) {
        case "work":       return root.workMinutes * 60;
        case "shortBreak": return root.shortBreakMinutes * 60;
        case "longBreak":  return root.longBreakMinutes * 60;
        default:           return 0;
        }
    }

    // ── Control ──────────────────────────────────────────────────────────────

    function start() {
        if (root.phase === "idle")
            root._enter("work");
        root.running = true;
    }

    function pause() { root.running = false; }

    function toggle() {
        if (root.running)
            root.pause();
        else
            root.start();
    }

    /** End the run: back to idle, count reset, notifications un-silenced. */
    function stop() {
        root.running = false;
        root.phase = "idle";
        root.remaining = 0;
        root.completedWork = 0;
    }

    /** Finish this phase now and move to the next. */
    function skip() {
        root._advance(false);
    }

    function _enter(next) {
        root.phase = next;
        root.remaining = root._phaseSeconds(next);
    }

    function _advance(byTimeout) {
        if (root.phase === "work") {
            root.completedWork += 1;
            const long_ = (root.completedWork % root.intervalsPerLongBreak) === 0;
            root._enter(long_ ? "longBreak" : "shortBreak");
            if (byTimeout)
                root._announce("Time for a break",
                               long_ ? "Long break — " + root.longBreakMinutes + " minutes."
                                     : "Short break — " + root.shortBreakMinutes + " minutes.");
        } else {
            root._enter("work");
            if (byTimeout)
                root._announce("Back to it",
                               root.workMinutes + " minutes of focus.");
        }
        root.running = true;
    }

    function _announce(title, body) {
        // Over D-Bus like any app's, rather than into the shell's own service:
        // this has to arrive while "Auto-Silence Notifications in Focus Mode"
        // is suppressing everything else, and the whole point of the timer is
        // that it tells you when the interval is over.
        Sys.notify("FocusTime", title, body, "alarm-symbolic");
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.running && root.phase !== "idle"
        onTriggered: {
            if (root.remaining > 1) {
                root.remaining -= 1;
                return;
            }
            root._advance(true);
        }
    }

    // ── Auto-silence ─────────────────────────────────────────────────────────

    /**
     * "Auto-Silence Notifications in Focus Mode" — read by Services/
     * Notifications, which folds it into its `dnd` property alongside the
     * manual switch and Game Mode.
     *
     * Only during a work interval: silencing the break as well would hide the
     * notification that says the break is over.
     */
    readonly property bool wantsDnd:
        root.phase === "work" && root.running && Settings.focusAutoDnd === true
}
