pragma Singleton

import QtQuick
import "../Ui"
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

// =============================================================================
// Desktop Notifications Service
//
// Native Freedesktop notification daemon (org.freedesktop.Notifications).
// Replaces external daemons (swaync, dunst, mako).
// =============================================================================

Singleton {
    id: root

    // Notification Server instance
    NotificationServer {
        id: server

        bodySupported: true
        actionsSupported: true
        imageSupported: true
        persistenceSupported: true
        // A messenger's "reply here": the toast and the list show a field.
        inlineReplySupported: true
        // Hints outside the spec arrive only when named here.
        extraHints: ["x-b1air-osd", "x-canonical-private-synchronous", "value"]

        onNotification: notif => {
            root._handleIncoming(notif);
        }
    }

    // Active notifications model (for live OSD toasts)
    readonly property ListModel activeToasts: ListModel {}

    // Notification History model (for Control Center history panel)
    readonly property ListModel history: ListModel {}

    // Do Not Disturb.
    //
    // `dnd` used to be a plain runtime bool: toggling it never touched
    // Settings.notificationsDnd, and nothing ever read that key back, so the
    // switch forgot itself on every shell restart while the setting sat in the
    // file doing nothing.
    //
    // Game Mode's "Do Not Disturb (DND) — mute all popups and toast
    // notifications while in game" was inert for the same reason: the switch
    // stored a value and no notification path consulted it.
    property bool manualDnd: false

    // ── Focus modes ──────────────────────────────────────────────────────────
    //
    // Not one Do Not Disturb but a few, each silencing banners and sounds
    // except from the apps it lets through (Settings → Notifications): Do Not
    // Disturb and Personal are picked by hand, Sleep is also on through quiet
    // hours, Work while the focus timer runs (when that silences), Gaming
    // while Game Mode does. One at a time: the one picked by hand first.
    readonly property var modes: [
        { id: "dnd",      name: I18n.tr("Do Not Disturb"), glyph: "\u{f0594}" },
        { id: "work",     name: I18n.tr("Work"),           glyph: "\u{f00d6}" },
        { id: "personal", name: I18n.tr("Personal"),       glyph: "\u{f0004}" },
        { id: "sleep",    name: I18n.tr("Sleep"),          glyph: "\u{f04b2}" },
        { id: "game",     name: I18n.tr("Gaming"),         glyph: "\u{f0eb5}" }
    ]
    function modeById(id) { return root.modes.find(m => m.id === id) || null; }
    readonly property string mode: Settings.focusMode !== "" ? Settings.focusMode
        : root.quietHours ? "sleep"
        : (Settings.gameModeEnabled === true && Settings.gameModeDND === true) ? "game"
        : Focus.wantsDnd ? "work" : ""
    readonly property var modeInfo: root.modeById(root.mode)
    function setMode(id) {
        Settings.set("focusMode", id || "");
        if (id) Settings.set("focusLastMode", id);
    }
    // Whether the mode in effect lets this app's banners through.
    function allowedNow(appName) {
        if (!root.mode) return true;
        const allow = (Settings.focusAllow || {})[root.mode] || [];
        const key = String(appName || "").toLowerCase();
        return allow.some(a => String(a).toLowerCase() === key);
    }
    function toggleAllowed(modeId, appName) {
        const all = Object.assign({}, Settings.focusAllow || {});
        const list = (all[modeId] || []).slice();
        const i = list.findIndex(a => String(a).toLowerCase() === String(appName).toLowerCase());
        if (i >= 0) list.splice(i, 1); else list.push(appName);
        all[modeId] = list;
        Settings.set("focusAllow", all);
    }

    /**
     * Whether a surface showing the notification list is on screen.
     *
     * Refcounted the way Services/Power and Services/Network are: a view
     * acquires it while it is up and releases it when it goes away, so two
     * views open at once cannot switch it off for each other.
     */
    property int _listViewers: 0
    readonly property bool listVisible: root._listViewers > 0
    function acquireList() { root._listViewers++; }
    function releaseList() { if (root._listViewers > 0) root._listViewers--; }

    // Any focus mode in effect (see above). Game Mode's DND, the focus
    // timer's auto-silence and quiet hours each bring their own mode in.
    readonly property bool dnd: root.mode !== ""

    // Quiet hours (Settings → Screen Time & DND). Re-read every half minute:
    // the boundary is a time of day, and nothing else signals it.
    property bool quietHours: false
    function _checkQuietHours() {
        if (Settings.dndScheduleEnabled !== true) {
            root.quietHours = false;
            return;
        }
        const d = new Date();
        const now = d.getHours() * 60 + d.getMinutes();
        const from = Settings.dndScheduleStart, until = Settings.dndScheduleEnd;
        root.quietHours = from === until ? false
            : from < until ? (now >= from && now < until)
            : (now >= from || now < until);      // wraps past midnight
    }
    Timer {
        interval: 30000
        running: Settings.dndScheduleEnabled === true
        repeat: true
        triggeredOnStart: true
        onTriggered: root._checkQuietHours()
    }
    Connections {
        target: Settings
        function onDndScheduleEnabledChanged() { root._checkQuietHours(); }
        function onDndScheduleStartChanged() { root._checkQuietHours(); }
        function onDndScheduleEndChanged() { root._checkQuietHours(); }
    }
    property int toastTimeoutMs: 6000
    readonly property int unreadCount: history.count

    // ── Time, in words ───────────────────────────────────────────────────────
    //
    // "now", "5 min", "21:04", "yesterday 21:04": what the toasts and the list
    // show instead of a clock time, and the list's sections. `now` moves on
    // every half minute, so "now" becomes "1 min" without a new notification.
    property double now: Date.now()
    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: root.now = Date.now()
    }
    function relTime(ts) {
        if (!ts) return "";
        const mins = Math.floor((root.now - ts) / 60000);
        if (mins < 1) return I18n.tr("now");
        if (mins < 60) return I18n.tr("%1 min", mins);
        const d = new Date(ts), today = new Date(root.now);
        const hm = d.toLocaleTimeString(I18n.locale, "hh:mm");
        if (d.toDateString() === today.toDateString()) return hm;
        const y = new Date(root.now - 86400000);
        if (d.toDateString() === y.toDateString()) return I18n.tr("yesterday %1", hm);
        return d.toLocaleDateString(I18n.locale, "d MMM") + " " + hm;
    }
    // "now" (the last hour), "today", "yesterday", "earlier".
    function sectionOf(ts) {
        if (!ts) return "earlier";
        if (root.now - ts < 3600000) return "now";
        const d = new Date(ts).toDateString();
        if (d === new Date(root.now).toDateString()) return "today";
        if (d === new Date(root.now - 86400000).toDateString()) return "yesterday";
        return "earlier";
    }

    // Dynamically tracked applications that have sent notifications
    property var trackedApps: []

    function _recordApp(name, icon) {
        if (!name) return;
        let found = false;
        let list = (root.trackedApps || []).slice();
        for (let app of list) {
            if (app.name.toLowerCase() === name.toLowerCase()) {
                found = true;
                if (!app.icon && icon) app.icon = icon;
                break;
            }
        }
        if (!found) {
            list.push({ name: name, icon: icon || "dialog-information" });
            root.trackedApps = list;
        }
    }

    function isAppMuted(appName) {
        if (!appName) return false;
        let rules = Settings.notificationRules || {};
        let key = appName.toLowerCase().trim();
        return rules[key] === false;
    }

    // What to draw for a notification: its image (a picture sent with it),
    // else its app icon, which is a path, a URL or an icon theme name. The
    // model used to read `notif.icon`, which a notification does not have,
    // so no notification ever showed an icon or a screenshot's thumbnail.
    function _iconSource(notif) {
        return root._resolveIcon(notif.image || notif.appIcon || "");
    }
    // A path, a URL or an icon theme name, as something an Image can load.
    function _resolveIcon(src) {
        src = String(src || "");
        if (src === "") return "";
        if (src.startsWith("/")) return "file://" + src;
        if (src.indexOf("://") >= 0) return src;
        return Quickshell.iconPath(src, true);
    }
    // The app's own icon, apart from any picture sent with the notification:
    // the badge on a sender's picture. From the notification, or the icon of
    // the desktop entry it names (Services/Apps).
    function _appIconSource(notif) {
        if (notif.appIcon) return root._resolveIcon(notif.appIcon);
        const icon = Apps.iconFor(notif.desktopEntry || notif.appName || "");
        return icon ? Apps.iconSource(icon) : "";
    }

    function _handleIncoming(notif) {
        // A status line (a mode switched, something copied) goes to the OSD
        // and is not kept: Services/Osd.qml.
        const hints = notif.hints || {};
        if (hints["x-b1air-osd"] !== undefined || hints["x-canonical-private-synchronous"] !== undefined) {
            const value = hints["value"];
            Osd.show(notif.appIcon || notif.image || "", notif.summary || "", notif.body || "",
                     value === undefined ? -1 : Number(value));
            return;
        }

        const item = {
            id: notif.id,
            appName: notif.appName || I18n.tr("System"),
            summary: notif.summary || "",
            body: notif.body || "",
            icon: root._iconSource(notif),
            // Apart: a sender's picture (or a screenshot), and the app's icon.
            image: root._resolveIcon(notif.image || ""),
            appIcon: root._appIconSource(notif),
            urgency: notif.urgency,
            critical: notif.urgency === NotificationUrgency.Critical,
            time: new Date().toLocaleTimeString(I18n.locale, "hh:mm"),
            ts: Date.now(),
            count: 1,
            obj: notif
        };

        // Record app to trackedApps list
        root._recordApp(item.appName, notif.appIcon || "");

        // Add to history
        root.history.insert(0, item);
        if (root.history.count > 50) root.history.remove(50);
        root._save();

        // Show a toast only if DND is off, the app is not muted, and the list
        // is not already on screen. A toast that repeats a line the user is
        // looking at in the notification centre is noise, and it used to land
        // on top of that very list.
        if ((!root.dnd || root.allowedNow(item.appName)) && !root.isAppMuted(item.appName) && !root.listVisible) {
            // Another from the same app and sender while one is up (a chat
            // going on): one toast, the newest on it and how many under it,
            // not a column of them.
            for (let i = 0; i < root.activeToasts.count; i++) {
                const t = root.activeToasts.get(i);
                if (t.appName === item.appName && t.summary === item.summary && !t.critical) {
                    item.count = (t.count || 1) + 1;
                    root.activeToasts.set(i, item);
                    return;
                }
            }
            root.activeToasts.append(item);
        }
    }

    // A messenger's reply, typed in a toast or the list. False when the
    // notification is gone (its app closed it, or the shell restarted).
    function reply(item, text) {
        const n = item ? item.obj : null;
        if (!n || !n.hasInlineReply || typeof n.sendInlineReply !== "function" || String(text).trim() === "")
            return false;
        n.sendInlineReply(String(text));
        return true;
    }
    // The action a click on the notification itself means, where the app
    // offers one ("default", in the specification).
    function activate(item) {
        const n = item ? item.obj : null;
        const acts = n && n.actions ? n.actions : [];
        const def = acts.find(a => a.identifier === "default");
        if (def && typeof def.invoke === "function") {
            def.invoke();
            return true;
        }
        return false;
    }

    function dismissToast(index) {
        if (index >= 0 && index < root.activeToasts.count) {
            const item = root.activeToasts.get(index);
            if (item && item.obj && typeof item.obj.dismiss === "function") {
                item.obj.dismiss();
            }
            root.activeToasts.remove(index);
        }
    }

    function dismissToastById(id) {
        for (let i = 0; i < root.activeToasts.count; i++) {
            if (root.activeToasts.get(i).id === id) {
                root.dismissToast(i);
                break;
            }
        }
    }

    function dismissHistoryItem(index) {
        if (index >= 0 && index < root.history.count) {
            root.history.remove(index);
            root._save();
        }
    }

    function clearAllHistory() {
        root.history.clear();
        root.activeToasts.clear();
        root._save();
    }

    // ── Persistence ──────────────────────────────────────────────────────────
    //
    // The history was a ListModel and nothing else, so a shell restart — an
    // update, a crash, the supervisor bringing it back — took everything
    // unread with it. The clipboard learned to survive that; notifications had
    // not.
    //
    // Same store and the same shape of mistake to avoid: a save must not go
    // out before the load has come back, or the first notification of the
    // session replaces the file with a single entry. Measured on the clipboard
    // when that guard was missing: ten records became one.
    property bool _loaded: false
    property bool _saveWanted: false
    property string _pendingSave: ""

    function _applyStored(raw) {
        if (root._loaded)
            return;
        try {
            const list = JSON.parse((raw || "").trim() || "[]");
            if (Array.isArray(list)) {
                // Appended, not inserted: anything that arrived while the read
                // was in flight is newer and already at the top.
                for (const entry of list) {
                    if (entry && entry.summary !== undefined)
                        root.history.append(entry);
                }
                while (root.history.count > 50) root.history.remove(50);
            }
        } catch (e) {
            console.log("Notification history load error:", e);
        }
        root._loaded = true;
        if (root._saveWanted)
            root._save();
    }

    function _save() {
        if (!root._loaded) {
            root._saveWanted = true;
            return;
        }
        const arr = [];
        for (let i = 0; i < root.history.count; i++) {
            const it = root.history.get(i);
            // `obj` is the live Quickshell notification; it cannot be
            // serialised and means nothing after a restart, so only the fields
            // the list actually draws are stored.
            // A picture from the bus is an image provider URL that means
            // nothing after a restart; a file stays.
            const keep = s => String(s || "").startsWith("file://") ? s : "";
            arr.push({
                id: it.id, appName: it.appName, summary: it.summary,
                body: it.body, icon: keep(it.icon), image: keep(it.image), appIcon: keep(it.appIcon),
                urgency: it.urgency, critical: !!it.critical, time: it.time, ts: it.ts || 0
            });
        }
        root._pendingSave = JSON.stringify(arr);
        saveDebounce.restart();
    }

    Process {
        id: historyLoader
        running: true
        command: ["b1air-secret-service", "get", "notification-history"]
        stdout: StdioCollector {
            onStreamFinished: root._applyStored(this.text)
        }
    }

    // If the store never answers — no daemon, a broken keyring — recording has
    // to start anyway rather than staying frozen for the session.
    Timer {
        interval: 4000
        running: !root._loaded
        onTriggered: root._applyStored("")
    }

    Process {
        id: historySaver
        stdinEnabled: true
        command: ["b1air-secret-service", "set", "notification-history"]
        onStarted: {
            write(root._pendingSave);
            stdinEnabled = false;
        }
    }

    // `stdinEnabled` is a property, not a one-shot: left false it closes the
    // pipe for every later run too, and the store freezes at whatever the
    // first save held. Re-opened on each write, and debounced because a burst
    // of notifications would otherwise spawn a helper apiece.
    Timer {
        id: saveDebounce
        interval: 400
        onTriggered: {
            historySaver.running = false;
            historySaver.stdinEnabled = true;
            historySaver.running = true;
        }
    }

    // The tile's switch: the last mode picked by hand, or off.
    function toggleDnd() {
        root.setMode(Settings.focusMode !== "" ? "" : (Settings.focusLastMode || "dnd"));
    }

    // Restored once Settings has actually read the file; reading it earlier
    // gets the schema default rather than the saved choice.
    Connections {
        target: Settings
        function onLoadedChanged() {
            // The old single switch, on from before modes: Do Not Disturb.
            if (Settings.loaded && Settings.notificationsDnd === true) {
                Settings.set("notificationsDnd", false);
                if (Settings.focusMode === "") root.setMode("dnd");
            }
        }
    }
}
