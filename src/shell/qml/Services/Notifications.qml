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

    readonly property bool dnd: root.manualDnd
        || (Settings.gameModeEnabled === true && Settings.gameModeDND === true)
        // "Auto-Silence Notifications in Focus Mode" on the Screen Time page,
        // which had the same shape as the two above: a switch, a stored value
        // and no reader. Services/Focus decides when it applies — during a
        // work interval and not during a break, or the notification saying the
        // break is over would be the one thing suppressed.
        || Focus.wantsDnd
        || root.quietHours

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
    property int toastTimeoutMs: 5000
    readonly property int unreadCount: history.count

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
        const src = notif.image || notif.appIcon || "";
        if (src === "") return "";
        if (src.startsWith("/")) return "file://" + src;
        if (src.indexOf("://") >= 0) return src;
        return Quickshell.iconPath(src, true);
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
            urgency: notif.urgency,
            time: new Date().toLocaleTimeString(Qt.locale(), "hh:mm"),
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
        if (!root.dnd && !root.isAppMuted(item.appName) && !root.listVisible) {
            root.activeToasts.append(item);
        }
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
            arr.push({
                id: it.id, appName: it.appName, summary: it.summary,
                body: it.body, icon: it.icon, urgency: it.urgency, time: it.time
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

    function toggleDnd() {
        root.manualDnd = !root.manualDnd;
        Settings.set("notificationsDnd", root.manualDnd);
    }

    // Restored once Settings has actually read the file; reading it earlier
    // gets the schema default rather than the saved choice.
    Connections {
        target: Settings
        function onLoadedChanged() {
            if (Settings.loaded)
                root.manualDnd = Settings.notificationsDnd === true;
        }
    }

    Component.onCompleted: {
        if (Settings.loaded)
            root.manualDnd = Settings.notificationsDnd === true;
    }
}
