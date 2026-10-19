import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../Ui"
import "../../Services"

// =============================================================================
// The calendars whose meetings bring the Meeting focus mode in
// (Settings.calendarSources, read by b1air-daemon calendar), and adding one
// the way a mail app adds an account:
//
//   Google, Microsoft  their own sign-in page, in the browser, where this
//                      build was registered with them (calendar-account
//                      providers); else the calendar's private link, step
//                      by step.
//   iCloud, CalDAV     an app-specific password (iCloud has no other way in
//                      for anyone), checked at once, its calendars listed.
//   Link or file       a .ics file, a folder of them, a webcal/https link.
//
// An account's calendars can be picked: the ones left out are kept in its
// source after "#hide=". Its password or sign-in is in the secret store as
// calendar-<md5 of the source before the #>, never in settings.json.
// =============================================================================

ColumnLayout {
    id: root
    spacing: Design.s(Design.space.sm)

    // ── State ────────────────────────────────────────────────────────────────

    property var providers: ({ google: false, microsoft: false })
    // What is being added ("" none), and how far: "form", "busy", "choose".
    property string adding: ""
    property string phase: "form"
    property string error: ""
    // An account signed in or checked, waiting for its calendars to be picked;
    // editing >= 0: an existing source's calendars.
    property string pendingSource: ""
    property var found: []
    property int editing: -1

    function start(kind) {
        root.cancel();
        root.adding = kind;
    }
    function cancel() {
        // An account checked but not added takes its password back out.
        if (root.pendingSource !== "" && root.editing < 0) root._storeSecret(root._secretName(root.pendingSource), "", null);
        if (accountProc.running) accountProc.running = false;
        root.adding = "";
        root.phase = "form";
        root.error = "";
        root.pendingSource = "";
        root.found = [];
        root.editing = -1;
        where.text = ""; user.text = ""; password.text = "";
    }

    // ── Sources ──────────────────────────────────────────────────────────────

    function _key(src) { const i = src.indexOf("#"); return i < 0 ? src : src.slice(0, i); }
    function _secretName(src) { return "calendar-" + Qt.md5(root._key(src)); }
    function isAccount(src) { return /^(icloud|caldav|google|microsoft):/.test(src); }
    function hiddenOf(src) {
        const i = src.indexOf("#hide=");
        return i < 0 ? [] : decodeURIComponent(src.slice(i + 6)).split("\n").filter(x => x !== "");
    }
    function label(src) {
        const k = root._key(src);
        if (/^(icloud|google|microsoft):/.test(k)) return k.slice(k.indexOf(":") + 1);
        if (k.startsWith("caldav:")) return k.slice(7).replace(/^https?:\/\/(.*@)?([^/]+).*$/, "$2");
        if (k.indexOf("calendar.google.com") >= 0) return "Google Calendar";
        if (k.indexOf("outlook.") >= 0) return "Outlook";
        return k.indexOf("://") > 0 ? k.replace(/^[a-z]+:\/\/([^/]+).*$/, "$1") : k;
    }
    function kind(src) {
        const k = root._key(src);
        const hidden = root.hiddenOf(src).length;
        const base = k.startsWith("icloud:") ? "iCloud" : k.startsWith("google:") ? "Google"
                   : k.startsWith("microsoft:") ? "Microsoft" : k.startsWith("caldav:") ? I18n.tr("CalDAV account")
                   : k.indexOf("calendar.google.com") >= 0 ? I18n.tr("Google, by its secret address")
                   : k.indexOf("://") > 0 ? I18n.tr("Calendar link") : I18n.tr("Calendar file or folder");
        return hidden > 0 ? base + " · " + I18n.trn("%1 calendar hidden", "%1 calendars hidden", hidden) : base;
    }
    function glyph(src) {
        const k = root._key(src);
        return k.startsWith("icloud:") ? "\u{f0035}" : k.startsWith("google:") || k.indexOf("google.com") >= 0 ? "\u{f02ad}"
             : k.startsWith("microsoft:") || k.indexOf("outlook.") >= 0 ? "\u{f0d22}"
             : k.startsWith("caldav:") ? "\u{f048b}" : k.indexOf("://") > 0 ? "\u{f0339}" : "\u{f09ee}";
    }
    // What the daemon's word for a failure means, in a sentence.
    function errorText(code) {
        const c = String(code || "");
        return c === "refused" ? I18n.tr("The password or sign-in was not accepted")
             : c === "unreachable" ? I18n.tr("Could not reach the server")
             : c === "no-password" ? I18n.tr("No password is saved for this account")
             : c === "signed-out" ? I18n.tr("Signed out — remove the account and sign in again")
             : c === "no-calendars" ? I18n.tr("This account has no calendars")
             : c === "timeout" ? I18n.tr("The sign-in in the browser was not finished in time")
             : c === "cancelled" ? I18n.tr("The sign-in was cancelled")
             : c === "not-configured" ? I18n.tr("Signing in is not set up in this build")
             : c.startsWith("status ") ? I18n.tr("The server answered with an error (%1)", c.slice(7))
             : c.startsWith("could not fetch") ? I18n.tr("Could not download the calendar")
             : c.startsWith("no such calendar") ? I18n.tr("The file or folder is not there")
             : c;
    }
    // "icloud:me@x: refused" → the account's name and the reason in words.
    function sourceError(line) {
        const i = line.lastIndexOf(": ");
        return i < 0 ? root.errorText(line) : root.label(line.slice(0, i)) + " — " + root.errorText(line.slice(i + 2));
    }

    function _save(list) { Settings.set("calendarSources", list); }
    function remove(i) {
        const list = (Settings.calendarSources || []).slice();
        const src = list[i];
        if (src && root.isAccount(src)) root._storeSecret(root._secretName(src), "", null);
        list.splice(i, 1);
        root._save(list);
    }
    function addPlain(src) {
        src = String(src).trim();
        if (src === "" || (Settings.calendarSources || []).indexOf(src) >= 0) { root.cancel(); return; }
        root._save((Settings.calendarSources || []).concat([src]));
        root.cancel();
    }

    // ── Signing in and checking ──────────────────────────────────────────────

    function signIn(provider) {
        root.error = "";
        root.phase = "busy";
        root._run(["signin", provider], r => {
            if (!r.ok) { root.phase = "form"; root.error = root.errorText(r.error); return; }
            root.pendingSource = r.source;
            root._choose(r.calendars.map(c => Object.assign({ hidden: false }, c)));
        });
    }
    function checkPassword(kind) {
        const id = user.text.trim();
        let src = "icloud:" + id;
        if (kind === "caldav") {
            const url = /^https?:\/\//.test(where.text.trim()) ? where.text.trim() : "https://" + where.text.trim();
            src = "caldav:" + url.replace(/^(https?:\/\/)/, "$1" + id + "@");
        }
        root.error = "";
        root.phase = "busy";
        root.pendingSource = src;
        // The password first, where the daemon reads it; then the check.
        root._storeSecret(root._secretName(src), password.text, () => {
            root._run(["check", src], r => {
                if (!r.ok) { root.phase = "form"; root.error = root.errorText(r.error); return; }
                password.text = "";
                root._choose(r.calendars);
            });
        });
    }
    function editCalendars(i) {
        root.cancel();
        const src = Settings.calendarSources[i];
        root.editing = i;
        root.adding = "edit";
        root.phase = "busy";
        root.pendingSource = src;
        root._run(["check", src], r => {
            if (!r.ok) { root.phase = "form"; root.error = root.errorText(r.error); return; }
            root._choose(r.calendars);
        });
    }
    function _choose(cals) {
        root.found = cals.map(c => ({ id: c.id, name: c.name, color: c.color || "", on: !c.hidden }));
        root.phase = "choose";
    }
    function toggle(i) {
        const list = root.found.slice();
        list[i] = Object.assign({}, list[i], { on: !list[i].on });
        root.found = list;
    }
    function finish() {
        const hidden = root.found.filter(c => !c.on).map(c => c.id);
        const src = root._key(root.pendingSource) + (hidden.length > 0 ? "#hide=" + encodeURIComponent(hidden.join("\n")) : "");
        const list = (Settings.calendarSources || []).slice();
        if (root.editing >= 0) list[root.editing] = src;
        else {
            // Signed in again with an account already here: the new one in its place.
            const at = list.findIndex(s => root._key(s) === root._key(src));
            if (at >= 0) list[at] = src; else list.push(src);
        }
        root.pendingSource = "";   // kept: not to be taken back out by cancel()
        root._save(list);
        root.cancel();
        Notifications.refreshCalendar();
    }

    // b1air-daemon calendar-account …, its JSON to `done`.
    property var _done: null
    function _run(args, done) {
        root._done = done;
        accountProc.running = false;
        accountProc.command = ["b1air-daemon", "calendar-account"].concat(args);
        accountProc.running = true;
    }
    Process {
        id: accountProc
        stdout: StdioCollector {
            onStreamFinished: {
                const done = root._done;
                root._done = null;
                if (!done) return;
                let r = null;
                try { r = JSON.parse(this.text); } catch (e) { r = { ok: false, error: "unreachable" }; }
                done(r);
            }
        }
    }

    // The secret store, then `then`.
    property var _then: null
    function _storeSecret(name, value, then) {
        secretWriter.value = value;
        root._then = then;
        secretWriter.running = false;
        secretWriter.command = ["b1air-secret-service", "set", name];
        secretWriter.running = true;
    }
    Process {
        id: secretWriter
        property string value: ""
        stdinEnabled: true
        onStarted: { write(secretWriter.value); secretWriter.value = ""; stdinEnabled = false; }
        onExited: {
            stdinEnabled = true;
            const then = root._then;
            root._then = null;
            if (then) then();
        }
    }

    Process {
        running: true
        command: ["b1air-daemon", "calendar-account", "providers"]
        stdout: StdioCollector {
            onStreamFinished: { try { root.providers = JSON.parse(this.text); } catch (e) {} }
        }
    }

    // ── The calendars there are ──────────────────────────────────────────────

    Repeater {
        model: Settings.calendarSources || []
        SettingsRow {
            required property string modelData
            required property int index
            label: root.label(modelData)
            note: root.kind(modelData)
            icon: root.glyph(modelData)
            RowLayout {
                spacing: Design.s(Design.space.xxs)
                IconButton {
                    visible: root.isAccount(modelData)
                    icon: "\u{f0756}"
                    label: I18n.tr("Choose calendars")
                    onClicked: root.editCalendars(index)
                }
                IconButton {
                    icon: "\u{f0156}"
                    label: I18n.tr("Remove")
                    onClicked: root.remove(index)
                }
            }
        }
    }

    Repeater {
        model: Notifications.calendarErrors
        InlineStatus {
            required property string modelData
            Layout.fillWidth: true
            status: "warning"
            showRetry: false
            text: root.sourceError(modelData)
        }
    }

    // ── Adding one ───────────────────────────────────────────────────────────

    Label {
        visible: root.adding === ""
        Layout.topMargin: Design.s(Design.space.xs)
        text: I18n.tr("Add a calendar")
        role: "caption"
        weight: Design.weight.semibold
        dim: true
    }
    Flow {
        visible: root.adding === ""
        Layout.fillWidth: true
        spacing: Design.s(Design.space.xs)
        Repeater {
            model: [
                { id: "google", name: "Google", glyph: "\u{f02ad}" },
                { id: "microsoft", name: "Outlook", glyph: "\u{f0d22}" },
                { id: "icloud", name: "iCloud", glyph: "\u{f0035}" },
                { id: "caldav", name: "CalDAV", glyph: "\u{f048b}" },
                { id: "link", name: I18n.tr("Link or file"), glyph: "\u{f0339}" }
            ]
            delegate: Surface {
                id: tile
                required property var modelData
                kind: "control"
                implicitWidth: Design.s(Design.size.tile) * 1.6
                implicitHeight: Design.s(Design.size.tile) * 1.25
                color: tileArea.containsMouse ? Design.controlHover : Design.controlFill
                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: Design.s(Design.space.xs)
                    Icon {
                        Layout.alignment: Qt.AlignHCenter
                        text: tile.modelData.glyph
                        role: "title"
                        color: Design.text
                    }
                    Label {
                        Layout.alignment: Qt.AlignHCenter
                        text: tile.modelData.name
                        role: "footnote"
                        weight: Design.weight.medium
                    }
                }
                PointerArea {
                    id: tileArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.start(tile.modelData.id)
                }
                Accessible.role: Accessible.Button
                Accessible.name: tile.modelData.name
            }
        }
    }

    // The sheet for the one being added: who it is, what to do, and the
    // one thing to press.
    Surface {
        id: sheet
        visible: root.adding !== ""
        Layout.fillWidth: true
        implicitHeight: sheetBody.implicitHeight + Design.s(Design.space.lg) * 2

        readonly property bool oauth: (root.adding === "google" || root.adding === "microsoft")
                                      && root.providers[root.adding] === true
        readonly property bool password: root.adding === "icloud" || root.adding === "caldav"
        readonly property bool link: root.adding === "link"
            || ((root.adding === "google" || root.adding === "microsoft") && !sheet.oauth)

        ColumnLayout {
            id: sheetBody
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Design.s(Design.space.lg)
            spacing: Design.s(Design.space.md)

            RowLayout {
                Layout.fillWidth: true
                spacing: Design.s(Design.space.md)
                Icon {
                    text: root.adding === "edit" ? root.glyph(root.pendingSource)
                        : ({ google: "\u{f02ad}", microsoft: "\u{f0d22}", icloud: "\u{f0035}", caldav: "\u{f048b}", link: "\u{f0339}" })[root.adding] || ""
                    role: "hero"
                    color: Design.text
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Label {
                        Layout.fillWidth: true
                        text: root.phase === "choose" || root.adding === "edit" ? I18n.tr("Choose calendars")
                            : root.adding === "google" ? (sheet.oauth ? I18n.tr("Sign in to Google") : I18n.tr("Google Calendar"))
                            : root.adding === "microsoft" ? (sheet.oauth ? I18n.tr("Sign in to Microsoft") : "Outlook")
                            : root.adding === "icloud" ? I18n.tr("Sign in to iCloud")
                            : root.adding === "caldav" ? I18n.tr("CalDAV account")
                            : I18n.tr("A calendar link or file")
                        role: "title"
                        weight: Design.weight.semibold
                    }
                    Label {
                        Layout.fillWidth: true
                        visible: text !== ""
                        text: root.phase === "choose" ? root.label(root.pendingSource)
                            : sheet.oauth ? I18n.tr("Only reading your calendars is asked for. Your password stays with %1.",
                                                    root.adding === "google" ? "Google" : "Microsoft")
                            : root.adding === "icloud" ? I18n.tr("iCloud lets other apps in with an app-specific password, not your Apple ID password")
                            : ""
                        role: "caption"
                        dim: true
                        wrapMode: Text.WordWrap
                    }
                }
            }

            // Step by step, where there is more to it than signing in.
            Repeater {
                model: root.phase !== "form" ? []
                     : root.adding === "icloud" ? [
                        I18n.tr("Open account.apple.com and sign in with your Apple ID"),
                        I18n.tr("In Sign-In and Security, choose App-Specific Passwords and make a new one, named b1air"),
                        I18n.tr("Copy it here, with your Apple ID")]
                     : root.adding === "google" && !sheet.oauth ? [
                        I18n.tr("Open Google Calendar's settings in the browser"),
                        I18n.tr("Under Settings for my calendars, choose your calendar, then Integrate calendar"),
                        I18n.tr("Copy the Secret address in iCal format and paste it here")]
                     : root.adding === "microsoft" && !sheet.oauth ? [
                        I18n.tr("Open Outlook's calendar settings in the browser"),
                        I18n.tr("Under Shared calendars, publish your calendar with Can view all details"),
                        I18n.tr("Copy the ICS link and paste it here")]
                     : []
                delegate: RowLayout {
                    required property string modelData
                    required property int index
                    Layout.fillWidth: true
                    spacing: Design.s(Design.space.sm)
                    Badge { text: String(index + 1) }
                    Label {
                        Layout.fillWidth: true
                        text: modelData
                        wrapMode: Text.WordWrap
                    }
                }
            }
            Button {
                visible: root.phase === "form" && (root.adding === "icloud" || sheet.link && root.adding !== "link")
                variant: "secondary"
                icon: "\u{f03cc}"
                label: root.adding === "icloud" ? I18n.tr("Open account.apple.com")
                     : root.adding === "google" ? I18n.tr("Open Google Calendar settings")
                     : I18n.tr("Open Outlook settings")
                onClicked: Quickshell.execDetached(["xdg-open",
                    root.adding === "icloud" ? "https://account.apple.com/account/manage/section/security"
                    : root.adding === "google" ? "https://calendar.google.com/calendar/r/settings"
                    : "https://outlook.live.com/calendar/0/options/calendar/SharedCalendars"])
            }

            // What it needs.
            ColumnLayout {
                visible: root.phase === "form"
                Layout.fillWidth: true
                spacing: Design.s(Design.space.sm)
                Field {
                    id: where
                    Layout.fillWidth: true
                    visible: sheet.link || root.adding === "caldav"
                    placeholder: root.adding === "google" ? "https://calendar.google.com/calendar/ical/…/basic.ics"
                               : root.adding === "microsoft" ? "https://outlook.live.com/owa/calendar/…/calendar.ics"
                               : root.adding === "caldav" ? I18n.tr("Server, e.g. cloud.example.org/remote.php/dav")
                               : I18n.tr("A link (webcal, https), a .ics file or a folder of them")
                }
                Field {
                    id: user
                    Layout.fillWidth: true
                    visible: sheet.password
                    placeholder: root.adding === "icloud" ? I18n.tr("Apple ID") : I18n.tr("User name")
                }
                Field {
                    id: password
                    Layout.fillWidth: true
                    visible: sheet.password
                    echoMode: TextInput.Password
                    placeholder: root.adding === "icloud" ? "xxxx-xxxx-xxxx-xxxx" : I18n.tr("Password")
                }
            }

            // The account's calendars, to pick from.
            Repeater {
                model: root.phase === "choose" ? root.found : []
                delegate: RowLayout {
                    required property var modelData
                    required property int index
                    Layout.fillWidth: true
                    spacing: Design.s(Design.space.sm)
                    CheckBox {
                        checked: modelData.on
                        onToggled: root.toggle(index)
                    }
                    Box {
                        visible: modelData.color !== ""
                        implicitWidth: Design.s(Design.space.sm)
                        implicitHeight: Design.s(Design.space.sm)
                        radius: width / 2
                        color: modelData.color || "transparent"
                    }
                    Label {
                        Layout.fillWidth: true
                        text: modelData.name
                        elide: Text.ElideRight
                    }
                }
            }

            InlineStatus {
                Layout.fillWidth: true
                visible: root.error !== ""
                status: "error"
                showRetry: false
                text: root.error
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Design.s(Design.space.sm)
                Label {
                    Layout.fillWidth: true
                    visible: root.phase === "busy"
                    text: sheet.oauth && root.pendingSource === "" ? I18n.tr("Waiting for the browser…") : I18n.tr("Checking…")
                    role: "caption"
                    dim: true
                }
                Item { Layout.fillWidth: true; visible: root.phase !== "busy" }
                Button {
                    variant: "ghost"
                    label: I18n.tr("Cancel")
                    onClicked: root.cancel()
                }
                Button {
                    variant: "primary"
                    busy: root.phase === "busy"
                    label: root.phase === "choose" ? (root.editing >= 0 ? I18n.tr("Done") : I18n.tr("Add"))
                         : sheet.oauth ? (root.adding === "google" ? I18n.tr("Sign in with Google") : I18n.tr("Sign in with Microsoft"))
                         : sheet.password ? I18n.tr("Sign in")
                         : I18n.tr("Add")
                    enabled: root.phase === "choose" ? root.found.some(c => c.on)
                           : root.phase === "busy" ? false
                           : sheet.oauth ? true
                           : sheet.password ? user.text.trim() !== "" && password.text !== ""
                                             && (root.adding !== "caldav" || where.text.trim() !== "")
                           : where.text.trim() !== ""
                    onClicked: {
                        if (root.phase === "choose") root.finish();
                        else if (sheet.oauth) root.signIn(root.adding);
                        else if (sheet.password) root.checkPassword(root.adding);
                        else root.addPlain(where.text);
                    }
                }
            }
        }
    }
}
