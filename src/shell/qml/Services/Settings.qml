pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// =============================================================================
// The settings store. Schema, typed reads, one writer.
//
// Replaces three separate `bash -c "jq -c . settings.json"` subprocess reads
// (Main.qml, Ui/Design.qml, SettingsPopup) and one shell write that was neither
// atomic nor safe:
//
//     echo '" + JSON.stringify(config) + "' > ~/.config/sway/settings.json
//
// That breaks on any single quote inside a value, and an interrupt mid-write
// leaves truncated JSON with no valid state to fall back to.
//
// THE PROPERTY DECLARATIONS BELOW ARE THE SCHEMA. Every default lives here
// once. Previously each consumer carried its own fallback — Design.qml had one
// idea of uiScale, Main.qml another — and they were free to disagree, exactly
// the way the colour fallbacks did before Ui/Design.
//
// Like GSettings over dconf: the file holds values, this holds the schema, and
// changes arrive as a signal rather than by anyone re-reading on a timer.
// =============================================================================

Singleton {
    id: root

    readonly property string path: Quickshell.env("HOME") + "/.config/sway/settings.json"

    // ── Schema ───────────────────────────────────────────────────────────────
    // Type and default declared once. Reads are typed: no parseInt at the call
    // site, no `|| 1.0` scattered through the shell.

    readonly property alias openGuideAtStartup: data.openGuideAtStartup
    readonly property alias topbarHelpIcon: data.topbarHelpIcon
    readonly property alias guideShortcut: data.guideShortcut
    readonly property alias language: data.language
    readonly property alias kbOptions: data.kbOptions
    // Keybindings changed on the Keyboard page: a JSON object of binding id to
    // key combo, rendered into conf.d/custom_keybinds.conf. A string because
    // the adapter round-trips strings faithfully and the page owns the shape.
    readonly property alias keybindOverrides: data.keybindOverrides
    readonly property alias wallpaperDir: data.wallpaperDir
    readonly property alias workspaceCount: data.workspaceCount
    readonly property alias monitors: data.monitors

    // Key step sizes — how far one press of a media key moves the value.
    readonly property alias audioStep: data.audioStep
    readonly property alias audioNotifications: data.audioNotifications

    // Lock and idle
    readonly property alias batteryLowWarning: data.batteryLowWarning
    readonly property alias batteryLowPercent: data.batteryLowPercent
    readonly property alias batteryCriticalPercent: data.batteryCriticalPercent
    readonly property alias batteryCriticalAction: data.batteryCriticalAction
    // Charge control, as KDE's power applet has it: the percentage the packs
    // stop charging at, and what the charger does while plugged in. Stored so
    // the desktop can put them back after a reboot — sysfs forgets both.
    readonly property alias chargeLimit: data.chargeLimit
    readonly property alias chargeBehaviour: data.chargeBehaviour
    readonly property alias dimOnLock: data.dimOnLock
    readonly property alias dimTimeout: data.dimTimeout
    readonly property alias lockTimeout: data.lockTimeout
    readonly property alias dpmsTimeout: data.dpmsTimeout
    readonly property alias autoSuspend: data.autoSuspend
    readonly property alias suspendTimeout: data.suspendTimeout

    // Weather. The API key lives here rather than in scripts/.env so there is
    // one store rather than two.
    readonly property alias weatherApiKey: data.weatherApiKey
    readonly property alias weatherCityId: data.weatherCityId
    readonly property alias weatherUnit: data.weatherUnit

    // Window Management & Gaps
    readonly property alias gapsInner: data.gapsInner
    readonly property alias gapsOuter: data.gapsOuter
    readonly property alias borderWidth: data.borderWidth
    readonly property alias smartBorders: data.smartBorders
    readonly property alias smartGaps: data.smartGaps
    // Hyprland-style dwindle splitting: b1air's swayfx does it itself
    // (`autotile`, src/swayfx/patches); on any other sway the daemon does.
    readonly property alias autotiling: data.autotiling
    // Settings → Animations (applied by the daemon over IPC).
    readonly property alias workspaceAnimation: data.workspaceAnimation
    readonly property alias windowAnimation: data.windowAnimation
    readonly property alias popinPercent: data.popinPercent
    readonly property alias animationDuration: data.animationDuration
    readonly property alias inactiveOpacityPercent: data.inactiveOpacityPercent
    readonly property alias specialWorkspace: data.specialWorkspace
    readonly property alias notificationsOnMain: data.notificationsOnMain

    // Appearance & compositor effects. Defaults mirror conf.d/look-and-feel.conf
    // so the UI shows what the session actually booted with.
    readonly property alias themeName: data.themeName
    // How other applications (GTK, Qt) are coloured: "auto" follows the
    // theme, "dark" and "light" pin them. Applied by `b1air-daemon appearance`.
    readonly property alias appColorScheme: data.appColorScheme
    readonly property alias accentName: data.accentName
    readonly property alias cornerRadius: data.cornerRadius
    readonly property alias blurEnabled: data.blurEnabled
    readonly property alias shadowsEnabled: data.shadowsEnabled
    readonly property alias dimInactive: data.dimInactive

    // Screenshots & Screen Recording
    readonly property alias screenshotDir: data.screenshotDir
    readonly property alias screenshotFormat: data.screenshotFormat
    readonly property alias screenshotCopyToClipboard: data.screenshotCopyToClipboard
    readonly property alias screenshotSaveToFile: data.screenshotSaveToFile
    readonly property alias screenshotDelay: data.screenshotDelay

    // Default applications are not here: they live in xdg-mime, which is what
    // everything else asks. Five keys stood here that the Default Apps page
    // wrote and nothing read.

    // Game Mode
    readonly property alias gameModeEnabled: data.gameModeEnabled
    readonly property alias gameModeAdaptiveSync: data.gameModeAdaptiveSync
    readonly property alias gameModeHideBar: data.gameModeHideBar
    readonly property alias gameModeDND: data.gameModeDND

    // Native Top Bar
    readonly property alias barPosition: data.barPosition
    readonly property alias barShowWeather: data.barShowWeather
    readonly property alias barShowMedia: data.barShowMedia
    readonly property alias barShowTray: data.barShowTray
    readonly property alias barClock24h: data.barClock24h
    readonly property alias barShowApps: data.barShowApps
    readonly property alias barShowPinned: data.barShowPinned
    readonly property alias barShowWorkspaces: data.barShowWorkspaces
    readonly property alias barShowStats: data.barShowStats

    // Which output carries the full bar. Empty means the first screen the
    // compositor reports, which is the conventional primary; naming one pins it
    // across replugs.
    readonly property alias barPrimaryOutput: data.barPrimaryOutput
    // Whether the other screens get a shortened bar or a copy of the full one.
    readonly property alias barSecondaryReduced: data.barSecondaryReduced

    // Which individual buttons and cards a surface leaves out, as a
    // comma-separated list of ids. A list rather than a boolean each because
    // the Control Center alone has nine tiles, and nine schema keys that are
    // all `true` by default is nine chances for one of them to be declared and
    // never read — the single most common defect in this repository's history.
    // Empty means everything is shown, which is what an unconfigured desktop
    // should do.
    readonly property alias ccHiddenTiles: data.ccHiddenTiles
    readonly property alias ccHiddenCards: data.ccHiddenCards
    readonly property alias calHiddenCards: data.calHiddenCards

    // The Control Center's tile grid, as "id:span" pairs in the order they are
    // laid out — "dnd:2,wifi:1,bluetooth:1". A span of 2 is a tile across both
    // columns. Ids missing from the list keep their declared position at the
    // end, so an empty string is the shipped arrangement and a list written by
    // hand does not have to be complete.
    readonly property alias ccTileLayout: data.ccTileLayout
    // Order of the cards under the Control Center's tiles (sliders, weather,
    // media, power buttons), in the same "id:size" form as the tiles.
    readonly property alias ccCardLayout: data.ccCardLayout

    // The calendar's parts, in the same "id:size" shape. No order in it — the
    // four are a fixed arrangement, a month grid beside a dashboard, not a set
    // of interchangeable cells — but each has a size that means something of
    // its own: how wide the month is, how tall the metric pills are, how many
    // days of forecast there is room for.
    readonly property alias calCardLayout: data.calCardLayout

    // Sound Feedback
    readonly property alias soundVolumeFeedback: data.soundVolumeFeedback
    readonly property alias soundScreenshotFeedback: data.soundScreenshotFeedback
    readonly property alias soundDeviceFeedback: data.soundDeviceFeedback

    // Touchpad & Gestures
    readonly property alias touchpadSwipeWorkspace: data.touchpadSwipeWorkspace
    readonly property alias touchpadNaturalSwipe: data.touchpadNaturalSwipe
    readonly property alias touchpadFourFinger: data.touchpadFourFinger

    // Pointer & touchpad. Defaults mirror conf.d/input.conf.
    readonly property alias naturalScroll: data.naturalScroll
    readonly property alias tapToClick: data.tapToClick
    // Two fingers pressed together click right (libinput "clickfinger"),
    // rather than the bottom-right corner of the pad ("button_areas").
    readonly property alias touchpadClickfinger: data.touchpadClickfinger
    readonly property alias dwt: data.dwt
    readonly property alias pointerAccel: data.pointerAccel
    readonly property alias accelProfile: data.accelProfile
    readonly property alias leftHanded: data.leftHanded

    // Autostart & Notifications
    readonly property alias autostartApps: data.autostartApps
    readonly property alias autostartCustom: data.autostartCustom
    readonly property alias notificationRules: data.notificationRules
    readonly property alias notificationsDnd: data.notificationsDnd

    // Night Light. These two were declared in the adapter but had no public
    // alias, so Settings.nightLightEnabled / .nightLightTemp read back as
    // undefined and the page's `!== undefined ? … : default` fallbacks always
    // won — the saved values persisted to disk and were never shown again.
    readonly property alias nightLightEnabled: data.nightLightEnabled
    readonly property alias nightLightTemp: data.nightLightTemp

    // Focus time / pomodoro.
    readonly property alias focusWorkDuration: data.focusWorkDuration
    readonly property alias focusShortBreak: data.focusShortBreak
    readonly property alias focusLongBreak: data.focusLongBreak
    readonly property alias dailyScreenTimeGoal: data.dailyScreenTimeGoal
    readonly property alias focusAutoDnd: data.focusAutoDnd
    readonly property alias focusBreakReminders: data.focusBreakReminders
    readonly property alias focusDaemonAutoStart: data.focusDaemonAutoStart
    // Quiet hours: Do Not Disturb between two times of day, in minutes since
    // midnight. The range may wrap past midnight (22:00 → 07:00).
    readonly property alias dndScheduleEnabled: data.dndScheduleEnabled
    readonly property alias dndScheduleStart: data.dndScheduleStart
    readonly property alias dndScheduleEnd: data.dndScheduleEnd

    // Device management
    readonly property alias disabledAudioDevices: data.disabledAudioDevices

    /** True once the file has been read at least once. */
    property bool loaded: false

    signal changed()

    // Whether the secret store holds a weather key. The key itself stays out
    // of this process: the field on the Weather page is always empty (the
    // alias above is blanked on purpose), and without this there was no way
    // to tell "no key" from "key saved" — the page said wttr.in either way.
    property bool weatherKeyStored: false

    property string pendingWeatherApiKey: ""
    Process {
        id: secretWriter
        stdinEnabled: true
        command: ["b1air-secret-service", "set", "weather-api-key"]
        onStarted: {
            write(root.pendingWeatherApiKey);
            root.pendingWeatherApiKey = "";
            stdinEnabled = false;
        }
        onExited: root.probeWeatherKey()
    }

    Process {
        id: secretRemover
        command: ["b1air-secret-service", "remove", "weather-api-key"]
        onExited: root.probeWeatherKey()
    }

    // Exit status only; no stdout handler, so the value is never read here.
    Process {
        id: secretProbe
        running: true
        command: ["b1air-secret-service", "get", "weather-api-key"]
        onExited: code => root.weatherKeyStored = code === 0
    }

    function probeWeatherKey() {
        secretProbe.running = false;
        secretProbe.running = true;
    }

    // ── Writes ───────────────────────────────────────────────────────────────
    // One writer. Assign through this, never touch the file.
    //
    //   Settings.set("uiScale", 1.25)
    //   Settings.apply({ language: "us", kbOptions: "grp:alt_shift_toggle" })

    function set(key, value) {
        if (data[key] === undefined) {
            // Refuse silently-new keys: an unknown key means a typo, and a typo
            // that writes is a setting nobody can ever read back.
            console.warn("Settings: unknown key", key, "— add it to the schema first");
            return;
        }
        if (data[key] === value)
            return;
        data[key] = value;
        root.flush();
    }

    // ── Hidden-widget lists ──────────────────────────────────────────────────
    //
    // The parsing lives here so that every surface asking "am I switched off?"
    // and every toggle writing the answer agree about what the string means.
    // Split on commas, ignore blanks, compare trimmed — a list edited by hand
    // in settings.json should still work.

    // Takes the list *value*, not its key: a caller writes
    // `Settings.isWidgetHidden(Settings.ccHiddenTiles, "wifi")`, so the binding
    // that asks reads the property directly and re-evaluates when it changes.
    // Passing the key instead would hide that read inside a lookup and leave
    // every switched-off widget stuck at whatever it was when first drawn.
    function isWidgetHidden(list, id) {
        return String(list || "").split(",").map(s => s.trim())
                                 .filter(s => s.length > 0).indexOf(id) >= 0;
    }

    function setWidgetHidden(listKey, id, hidden) {
        const raw = data[listKey];
        if (raw === undefined) {
            console.warn("Settings: unknown key", listKey, "— add it to the schema first");
            return;
        }
        let ids = String(raw).split(",").map(s => s.trim()).filter(s => s.length > 0);
        const at = ids.indexOf(id);
        if (hidden && at < 0)
            ids.push(id);
        else if (!hidden && at >= 0)
            ids.splice(at, 1);
        else
            return;
        root.set(listKey, ids.join(","));
    }

    // ── Tile arrangement ─────────────────────────────────────────────────────

    /** Parsed "id:span" list, in order, restricted to and completed from `all`. */
    /**
     * @param fallback the size for an id the list does not mention. The Control
     *        Center ships all-small and the calendar ships all-medium, so the
     *        default cannot be one constant: taking it as small everywhere
     *        quietly halved the calendar's metric pills on any machine that had
     *        never touched the setting.
     */
    function tileArrangement(list, all, fallback) {
        const missing = root.tileSizeName(fallback || "small");
        let order = [];
        let spans = ({});
        for (const part of String(list || "").split(",")) {
            const bits = part.trim().split(":");
            const id = (bits[0] || "").trim();
            if (!id || all.indexOf(id) < 0 || order.indexOf(id) >= 0)
                continue;
            order.push(id);
            spans[id] = root.tileSizeName(bits[1]);
        }
        // Anything the list does not mention keeps its declared place, at the
        // end: a new tile added to the shell later appears rather than
        // disappearing because an old saved arrangement had never heard of it.
        for (const id of all)
            if (order.indexOf(id) < 0) {
                order.push(id);
                spans[id] = missing;
            }
        return { order: order, spans: spans };
    }

    // Three sizes on a two-column grid, which is as many as two columns can
    // carry and still mean something:
    //
    //   small   1 x 1   half the width, one row  — the shipped look
    //   medium  2 x 1   the full width, one row
    //   large   2 x 2   the full width, two rows
    //
    // Names rather than numbers in the saved string, so a file edited by hand
    // reads as what it is; "1" and "2" are still understood because that is
    // what the first version of this wrote.
    function tileSizeName(raw) {
        const v = String(raw || "").trim().toLowerCase();
        if (v === "large" || v === "3") return "large";
        if (v === "medium" || v === "2") return "medium";
        return "small";
    }

    function tileSizeCells(name) {
        if (name === "large") return { cols: 2, rows: 2 };
        if (name === "medium") return { cols: 2, rows: 1 };
        return { cols: 1, rows: 1 };
    }

    function setTileArrangement(key, order, spans) {
        let parts = [];
        for (const id of order)
            parts.push(id + ":" + root.tileSizeName(spans[id]));
        root.set(key, parts.join(","));
    }

    /**
     * Store a weather key, or remove it when given an empty one.
     *
     * The second key saved in a session used to be stored empty: the writer
     * turns stdinEnabled off once it has written, and nothing turned it back
     * on, so the next run had no stdin to write to. It also wrote a trailing
     * newline, which the daemon then put into the request URL.
     */
    function setWeatherApiKey(value) {
        root.data.weatherApiKey = "";
        const key = String(value || "").trim();
        if (key === "") {
            secretRemover.running = false;
            secretRemover.running = true;
        } else {
            root.pendingWeatherApiKey = key;
            secretWriter.running = false;
            secretWriter.stdinEnabled = true;
            secretWriter.running = true;
        }
        root.changed();
    }

    function apply(obj) {
        let touched = false;
        for (const key in obj) {
            if (data[key] === undefined) {
                console.warn("Settings: unknown key", key, "— add it to the schema first");
                continue;
            }
            if (data[key] !== obj[key]) {
                data[key] = obj[key];
                touched = true;
            }
        }
        if (touched)
            root.flush();
    }

    /**
     * Drop every key back to its schema default.
     *
     * About → "Reset Defaults" has called this since it was written and it did
     * not exist, so the button threw a TypeError and reset nothing. The button
     * is destructive-styled, so it already arms once before firing.
     */
    function resetDefaults() {
        root.apply(root.defaults);
    }

    /** Drop a key back to its schema default. */
    function reset(key) {
        if (defaults[key] !== undefined)
            root.set(key, defaults[key]);
    }

    function flush() {
        file.writeAdapter();
        root.changed();
    }

    // The schema defaults, kept separately so reset() has something to go back
    // to — the same reason dconf stores only deltas.
    readonly property var defaults: ({
        openGuideAtStartup: false,
        topbarHelpIcon: true,
        guideShortcut: "Mod+H",
        language: "us,ua",
        kbOptions: "grp:alt_shift_toggle",
        keybindOverrides: "{}",
        wallpaperDir: Quickshell.env("HOME") + "/.wallpapers",
        workspaceCount: 10,
        audioStep: 5,
        audioNotifications: true,
        batteryLowWarning: true,
        batteryLowPercent: 15,
        batteryCriticalPercent: 5,
        batteryCriticalAction: "suspend",
        chargeLimit: 100,
        chargeBehaviour: "auto",
        dimOnLock: true,
        dimTimeout: 240,
        lockTimeout: 300,
        dpmsTimeout: 600,
        autoSuspend: false,
        suspendTimeout: 1800,
        weatherApiKey: "",
        weatherCityId: "",
        weatherUnit: "metric",
        gapsInner: 5,
        gapsOuter: 10,
        borderWidth: 2,
        smartBorders: true,
        smartGaps: false,
        autotiling: true,
        workspaceAnimation: "slide",
        windowAnimation: "popin",
        popinPercent: 80,
        animationDuration: 200,
        inactiveOpacityPercent: 50,
        specialWorkspace: true,
        notificationsOnMain: false,
        themeName: "catppuccin-mocha",
        appColorScheme: "auto",
        accentName: "",
        cornerRadius: 10,
        blurEnabled: true,
        shadowsEnabled: true,
        dimInactive: true,
        screenshotDir: Quickshell.env("HOME") + "/Pictures/Screenshots",
        screenshotFormat: "png",
        screenshotCopyToClipboard: true,
        screenshotSaveToFile: true,
        screenshotDelay: 0,
        gameModeEnabled: false,
        gameModeAdaptiveSync: false,
        gameModeHideBar: true,
        gameModeDND: false,
        barPosition: "top",
        barShowWeather: true,
        barShowMedia: true,
        barShowTray: true,
        barClock24h: true,
        barShowApps: true,
        barShowPinned: true,
        barShowWorkspaces: true,
        barShowStats: true,
        barPrimaryOutput: "",
        barSecondaryReduced: true,
        ccHiddenTiles: "",
        ccHiddenCards: "",
        calHiddenCards: "",
        ccTileLayout: "",
        ccCardLayout: "",
        calCardLayout: "",
        nightLightEnabled: false,
        nightLightTemp: 4000,
        soundVolumeFeedback: true,
        soundScreenshotFeedback: true,
        soundDeviceFeedback: true,
        touchpadSwipeWorkspace: true,
        touchpadNaturalSwipe: true,
        touchpadFourFinger: true,
        naturalScroll: false,
        tapToClick: true,
        touchpadClickfinger: true,
        dwt: true,
        pointerAccel: 0.0,
        accelProfile: "flat",
        leftHanded: false,
        autostartApps: ["polkit", "quickshell"],
        autostartCustom: [],
        notificationRules: {},
        notificationsDnd: false,
        focusWorkDuration: 25,
        focusShortBreak: 5,
        focusLongBreak: 15,
        dailyScreenTimeGoal: 8,
        focusAutoDnd: true,
        focusBreakReminders: true,
        focusDaemonAutoStart: true,
        dndScheduleEnabled: false,
        dndScheduleStart: 1320,
        dndScheduleEnd: 420,
        monitors: [],
        disabledAudioDevices: [],
    })

    // ── Store ────────────────────────────────────────────────────────────────
    FileView {
        id: file
        path: root.path
        watchChanges: true
        printErrors: false
        atomicWrites: true

        onFileChanged: reload()
        onLoaded: {
            // Credentials are owned by b1air-secret-service, never retained in
            // the general settings JSON or exposed to QML after load.
            data.weatherApiKey = "";
            root.loaded = true;
            root.changed();
        }
        onLoadFailed: root.loaded = true

        JsonAdapter {
            id: data
            property bool openGuideAtStartup: false
            property bool topbarHelpIcon: true
            property string guideShortcut: "Mod+H"
            property string language: "us,ua"
            property string kbOptions: "grp:alt_shift_toggle"
            property string keybindOverrides: "{}"
            property string wallpaperDir: Quickshell.env("HOME") + "/.wallpapers"
            property int workspaceCount: 10
            property var monitors: []
            property var disabledAudioDevices: []
            property int audioStep: 5
            property bool audioNotifications: true

            property bool batteryLowWarning: true
            property int batteryLowPercent: 15
            property int batteryCriticalPercent: 5
            property string batteryCriticalAction: "suspend"
            property int chargeLimit: 100
            property string chargeBehaviour: "auto"
            property bool dimOnLock: true
            property int dimTimeout: 240
            property int lockTimeout: 300
            property int dpmsTimeout: 600
            property bool autoSuspend: false
            property int suspendTimeout: 1800

            property string weatherApiKey: ""
            property string weatherCityId: ""
            property string weatherUnit: "metric"

            property int gapsInner: 5
            property int gapsOuter: 10
            property int borderWidth: 2
            property bool smartBorders: true
            property bool smartGaps: false
            property bool autotiling: true
            property string workspaceAnimation: "slide"
            property string windowAnimation: "popin"
            property int popinPercent: 80
            property int animationDuration: 200
            property int inactiveOpacityPercent: 50
            property bool specialWorkspace: true
            property bool notificationsOnMain: false
            property string themeName: "catppuccin-mocha"
            property string appColorScheme: "auto"
            property string accentName: ""
            property int cornerRadius: 10
            property bool blurEnabled: true
            property bool shadowsEnabled: true
            property bool dimInactive: true

            property string screenshotDir: Quickshell.env("HOME") + "/Pictures/Screenshots"
            property string screenshotFormat: "png"
            property bool screenshotCopyToClipboard: true
            property bool screenshotSaveToFile: true
            property int screenshotDelay: 0

            property bool gameModeEnabled: false
            property bool gameModeAdaptiveSync: false
            property bool gameModeHideBar: true
            property bool gameModeDND: false

            property string barPosition: "top"
            property bool barShowWeather: true
            property bool barShowMedia: true
            property bool barShowTray: true
            property bool barClock24h: true
            property bool barShowApps: true
            property bool barShowPinned: true
            property bool barShowWorkspaces: true
            property bool barShowStats: true
            property string barPrimaryOutput: ""
            property bool barSecondaryReduced: true
            property string ccHiddenTiles: ""
            property string ccHiddenCards: ""
            property string calHiddenCards: ""
            property string ccTileLayout: ""
            property string ccCardLayout: ""
            property string calCardLayout: ""

            property bool nightLightEnabled: false
            property int nightLightTemp: 4000

            property bool soundVolumeFeedback: true
            property bool soundScreenshotFeedback: true
            property bool soundDeviceFeedback: true

            property bool touchpadSwipeWorkspace: true
            property bool touchpadNaturalSwipe: true
            property bool touchpadFourFinger: true
            property bool naturalScroll: false
            property bool tapToClick: true
            property bool touchpadClickfinger: true
            property bool dwt: true
            property real pointerAccel: 0.0
            property string accelProfile: "flat"
            property bool leftHanded: false

            property var autostartApps: ["polkit", "quickshell"]
            property var autostartCustom: []
            property var notificationRules: ({})
            property bool notificationsDnd: false
            property int focusWorkDuration: 25
            property int focusShortBreak: 5
            property int focusLongBreak: 15
            property int dailyScreenTimeGoal: 8
            property bool focusAutoDnd: true
            property bool focusBreakReminders: true
            property bool focusDaemonAutoStart: true
            property bool dndScheduleEnabled: false
            property int dndScheduleStart: 1320
            property int dndScheduleEnd: 420
        }
    }
}
