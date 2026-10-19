import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Dialogs
import Quickshell
import B1air.Daemon
import Quickshell.Io
import "../../Ui"
import "../../Services"

// =============================================================================
// User Profile & Account Settings Section (C++20 b1air-daemon backed)
// =============================================================================

ColumnLayout {
    id: section

    // Which part of the section to show. "" or "account": the User page —
    // name, picture, shell. "lock": the Lock & Login page — the fingerprint
    // and the login screen. "fingerprint": that card alone (the first-run
    // setup's step, there only when a reader is). "setup": the setup's
    // account step — the picture's choices, the name and the shell.
    property string part: ""
    // The picture's choices (AvatarPicker) under the profile, opened from
    // the picture or "Change Avatar"; the setup's step shows them anyway.
    property bool pickerOpen: false
    Layout.fillWidth: true
    spacing: Design.s(Design.space.lg)

    property var userInfo: ({
        username: "user",
        name: "User",
        uid: "1000",
        home: "/home/user",
        shell: "/usr/bin/fish",
        avatar: "",
        groups: "wheel, input, audio, video"
    })

    property string daemonCmd: "b1air-daemon"
    // The picture is always ~/.face.icon: a new one is the same path, and
    // the image cache would keep showing the old one without this in its key.
    property int avatarRev: 0
    property var availableShells: []

    function loadUserInfo() {
        userInfoProcess.running = true;
    }

    Process {
        id: shellsScanner
        command: ["cat", "/etc/shells"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                let lines = this.text.split("\n");
                let list = [];
                let seenNames = {};
                for (let line of lines) {
                    line = line.trim();
                    if (!line || line.startsWith("#")) continue;
                    if (line.includes("git-shell") || line.includes("nologin") || line.includes("false") || line.includes("rbash") || line.includes("systemd-home"))
                        continue;
                    let parts = line.split("/");
                    let baseName = parts[parts.length - 1];
                    if (!seenNames[baseName]) {
                        seenNames[baseName] = true;
                        list.push({ label: baseName, path: line });
                    }
                }
                if (list.length === 0) {
                    list = [{ label: "bash", path: "/bin/bash" }];
                }
                section.availableShells = list;
            }
        }
    }

    Process {
        id: userInfoProcess
        command: [section.daemonCmd, "user", "get"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    let raw = this.text.trim();
                    if (raw !== "") {
                        section.userInfo = JSON.parse(raw);
                        section.avatarRev++;
                    }
                } catch (e) {}
            }
        }
    }

    Component.onCompleted: {
        loadUserInfo();
    }

    // (The page title is in the Settings header bar now.)

    // ── 2. Profile ───────────────────────────────────────────────────────────
    // The person, not the account record: the picture, the name and the
    // login. The UID and the home directory that were the subtitle here are
    // nothing anyone changes from this page.
    SettingsGroup {
        visible: section.part === "" || section.part === "account"
        RowLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.lg)

            Box {
                Layout.preferredWidth: Design.s(Design.size.avatar)
                Layout.preferredHeight: Design.s(Design.size.avatar)
                radius: width / 2
                color: section.userInfo.avatar !== "" ? "transparent" : Design.stateSelectedSoft

                // Round: `clip` on this Rectangle cut it to a square.
                RoundImage {
                    anchors.fill: parent
                    visible: section.userInfo.avatar !== ""
                    source: section.userInfo.avatar ? Paths.fileUrl(section.userInfo.avatar) + "?" + section.avatarRev : ""
                    cache: false
                }

                // The initial, where there is no picture.
                Label {
                    anchors.centerIn: parent
                    visible: section.userInfo.avatar === ""
                    text: String(section.userInfo.name || section.userInfo.username || "?").charAt(0).toUpperCase()
                    role: "title"
                    weight: Design.weight.semibold
                    color: Design.accent
                }

                Clickable {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: section.pickerOpen = !section.pickerOpen
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Design.s(Design.space.xs)

                Label {
                    text: section.userInfo.name || section.userInfo.username
                    role: "title"
                    weight: Design.weight.semibold
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }
                Label {
                    text: "@" + section.userInfo.username
                    dim: true
                }

                // Under the name, not at the far end of the card.
                RowLayout {
                    Layout.topMargin: Design.s(Design.space.xs)
                    spacing: Design.s(Design.space.sm)

                    Button {
                        Layout.fillWidth: false
                        icon: "\u{f03e}"
                        label: I18n.tr("Change Avatar")
                        checked: section.pickerOpen
                        onActivated: section.pickerOpen = !section.pickerOpen
                    }

                    Button {
                        Layout.fillWidth: false
                        icon: "\u{f084}"
                        label: I18n.tr("Change Password")
                        onActivated: Quickshell.execDetached([section.daemonCmd, "user", "change-password"])
                    }
                }
            }
        }
    }

    SettingsGroup {
        visible: ((section.part === "" || section.part === "account") && section.pickerOpen) || section.part === "setup"
        title: I18n.tr("Picture")
        note: I18n.tr("Shown on the login and lock screens")
        icon: "\u{f03e}"
        AvatarPicker {
            Layout.fillWidth: true
            current: section.userInfo.avatar || ""
            name: section.userInfo.name || section.userInfo.username || ""
            onSaved: section.loadUserInfo()
        }
    }

    SettingsGroup {
        // No reader that fprintd can drive: no card, rather than one saying
        // what is missing on a machine that has nothing to put a finger on.
        visible: (section.part === "lock" || section.part === "fingerprint") && section.fp.available
        title: I18n.tr("Fingerprint")
        subtitle: section.fp.available ? section.fp.device : I18n.tr("Open the lock screen with a touch")
        icon: "\u{f0237}"

        EmptyState {
            visible: !section.fp.available
            Layout.fillWidth: true
            icon: "\u{f0237}"
            title: section.fp.service ? I18n.tr("No fingerprint reader") : I18n.tr("Fingerprint support is not installed")
            hint: section.fp.service ? I18n.tr("fprintd is running, but it found no reader it can drive.")
                                     : I18n.tr("Install fprintd (and its PAM module) to use a fingerprint reader.")
        }

        // The prints saved, numbered. fprintd files each under a finger's
        // name, and the page used to ask which finger — ten pills from
        // "Left thumb" to "Right little finger" — for what is, to whoever
        // uses it, just "another print". The finger is picked here, the
        // next free one, and the number is all that shows.
        Repeater {
            model: section.fp.available ? section.fpSaved : []
            RowLayout {
                required property var modelData
                required property int index
                Layout.fillWidth: true
                Icon { text: "\u{f0237}"; color: Design.textDim }
                Label { text: I18n.tr("Fingerprint %1", index + 1); Layout.fillWidth: true }
                Button {
                    icon: "\u{f0a7a}"
                    label: I18n.tr("Remove")
                    destructive: true
                    confirmText: I18n.tr("Remove?")
                    onActivated: {
                        fpDelete.command = [section.daemonCmd, "fingerprint", "delete", modelData];
                        fpDelete.running = true;
                    }
                }
            }
        }

        Label {
            visible: section.fp.available && !section.fpEnrolling && section.fpSaved.length === 0
            text: I18n.tr("No fingerprint saved yet.")
            role: "caption"
            dim: true
        }

        RowLayout {
            visible: section.fp.available
            Layout.fillWidth: true
            spacing: Design.s(Design.space.sm)
            Button {
                visible: !section.fpEnrolling && section.fpFinger !== ""
                icon: "\u{f0415}"
                label: I18n.tr("Add a fingerprint")
                onActivated: {
                    section.fpDone = 0;
                    section.fpMessage = section.fp.scanType === "swipe" ? I18n.tr("Swipe your finger across the reader")
                                                                         : I18n.tr("Touch the reader");
                    section.fpMessageBad = false;
                    section.fpEnrolling = true;
                    fpEnroll.running = true;
                }
            }
            Button {
                visible: section.fpEnrolling
                icon: "\u{f0156}"
                label: I18n.tr("Cancel")
                onActivated: fpEnroll.running = false
            }
            Button {
                visible: !section.fpEnrolling && (section.fp.enrolled || []).length > 0
                icon: "\u{f0237}"
                label: section.fpTest === "listening" ? I18n.tr("Touch the reader…") : I18n.tr("Test")
                onActivated: {
                    section.fpTest = "listening";
                    fpVerify.running = false;
                    fpVerify.running = true;
                }
            }
            Label {
                visible: section.fpTest === "match" || section.fpTest === "no-match"
                text: section.fpTest === "match" ? I18n.tr("Recognised") : I18n.tr("Not recognised")
                color: section.fpTest === "match" ? Design.ok : Design.danger
            }
            Item { Layout.fillWidth: true }
        }

        // Enrolling: a dot per touch the reader wants, filled as they come.
        ColumnLayout {
            visible: section.fpEnrolling || section.fpMessage !== ""
            Layout.fillWidth: true
            spacing: Design.s(Design.space.xs)
            Row {
                visible: section.fpEnrolling && section.fp.stages > 0
                spacing: Design.s(Design.space.xs)
                Repeater {
                    model: section.fp.stages
                    Box {
                        required property int index
                        width: Design.s(Design.space.md); height: width; radius: width / 2
                        color: index < section.fpDone ? Design.accent : Design.hover
                        Behavior on color { ColorAnimation { duration: Design.duration.base } }
                    }
                }
            }
            Label {
                text: section.fpMessage
                color: section.fpMessageBad ? Design.danger : Design.text
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }
        }

        SwitchRow {
            visible: section.fp.available
            label: I18n.tr("Unlock with a fingerprint")
            subtitle: I18n.tr("On the lock screen, a touch on the reader works as well as the password")
            checked: Settings.fingerprintUnlock !== false
            onToggled: Settings.set("fingerprintUnlock", !(Settings.fingerprintUnlock !== false))
        }

        // The login screen: a system file (/etc/pam.d/sddm, and only that
        // one), so it asks for the administrator password.
        SwitchRow {
            visible: section.fp.available && section.fpLogin.supported === true
            enabled: !fpLoginSet.running
            label: I18n.tr("Fingerprint at the login screen")
            note: I18n.tr("Leave the password empty, press Enter and touch the reader. Only the login screen; sudo and system prompts still want the password. The keyring stays locked until a password is typed.")
            checked: section.fpLogin.enabled === true
            onToggled: {
                fpLoginSet.command = ["pkexec", section.daemonCmd, "fingerprint", "login", checked ? "off" : "on"];
                fpLoginSet.running = true;
            }
        }
    }

    // ── 3. Account Details Card ──────────────────────────────────────────────
    SettingsGroup {
        visible: section.part === "" || section.part === "account" || section.part === "setup"
        title: I18n.tr("Account Details & Shell")
        icon: "\u{f013}"

        SettingsRow {
            label: I18n.tr("Display / Full Name")
            note: I18n.tr("Real name shown on lockscreen and greeter")
            Field {
                id: nameField
                Layout.preferredWidth: Design.s(Design.width.control)
                text: section.userInfo.name || ""
                placeholder: I18n.tr("Enter full name...")
                onCommitted: v => {
                    if (v.trim().length > 0) {
                        Quickshell.execDetached([section.daemonCmd, "user", "set-name", v.trim()]);
                        section.loadUserInfo();
                    }
                }
            }
            Button {
                icon: "\u{f00c}"
                label: I18n.tr("Save")
                onActivated: {
                    if (nameField.text.trim().length > 0) {
                        Quickshell.execDetached([section.daemonCmd, "user", "set-name", nameField.text.trim()]);
                        section.loadUserInfo();
                    }
                }
            }
        }

        // One shell of a few: a segmented control, as every other choice.
        SettingsRow {
            label: I18n.tr("Default Shell")
            note: I18n.tr("Login shell executed for terminals and virtual consoles")
            SegmentedControl {
                visible: section.availableShells.length > 0
                size: "sm"
                model: section.availableShells.map(sh => ({ id: sh.path, label: sh.label }))
                current: {
                    const cur = section.userInfo.shell || "";
                    const hit = section.availableShells.find(sh => cur === sh.path || cur.endsWith("/" + sh.label));
                    return hit ? hit.path : "";
                }
                onPicked: function(id) {
                    Quickshell.execDetached([section.daemonCmd, "user", "set-shell", id]);
                    section.loadUserInfo();
                }
            }
        }
    }

    // ── 4. Session & login screen ────────────────────────────────────────────
    //
    // Both badges were constants — "b1air (SwayFX)" and "b1air SDDM Theme" —
    // shown whatever was running, plain sway included. They are read now.
    readonly property string compositorName: Sway.compositorName || "—"
    // SDDM's theme: the last `Current=` in its config, conf.d files read in
    // name order after the main one, as SDDM reads them.
    readonly property string greeterTheme: {
        const files = ["/etc/sddm.conf"].concat(
            Sys.listDir("/etc/sddm.conf.d").filter(n => n.endsWith(".conf")).sort()
                .map(n => "/etc/sddm.conf.d/" + n));
        let theme = "";
        for (const f of files) {
            for (const line of Sys.readFile(f).split("\n")) {
                const m = line.match(/^Current=(.*)$/);
                if (m) theme = m[1].trim();
            }
        }
        return theme || I18n.tr("SDDM default");
    }

    // The phone as a security key (src/passkey): websites that ask for a
    // passkey get a QR code, and the phone that scans it signs in. On by
    // default, as on other desktops; only where there is Bluetooth, which
    // the phone needs to show it is nearby.
    SettingsGroup {
        visible: section.part === "lock" && !!Network.adapter
        title: I18n.tr("Passkeys")
        SwitchRow {
            label: I18n.tr("Sign in to websites with your phone")
            note: I18n.tr("When a website asks for a passkey, a QR code comes up; scan it with the phone that keeps the passkey. Works in every browser. Bluetooth has to be on.")
            checked: Settings.passkeyPhone !== false
            onToggled: Settings.set("passkeyPhone", Settings.passkeyPhone === false)
        }
    }

    SettingsGroup {
        visible: section.part === "lock"
        title: I18n.tr("Session & Login Screen")
        icon: "\u{f108}"

        // A value, not a status: plain text, as in About.
        SettingsRow {
            label: I18n.tr("Compositor")
            Label { text: section.compositorName || "—"; dim: true }
        }

        // A value, not a status: plain text, as in About.
        SettingsRow {
            label: I18n.tr("Login screen theme")
            Label { text: section.greeterTheme || "—"; dim: true }
        }
    }

    // ── Fingerprint ──────────────────────────────────────────────────────────
    //
    // fprintd (KDE and GNOME use the same), through the daemon
    // (src/daemon/fingerprint.cpp): which reader, which fingers, enrolling
    // one touch at a time, deleting. A touch then opens the lock screen,
    // beside the password.
    property var fp: ({ available: false, service: false, device: "", stages: 0, scanType: "", enrolled: [] })
    property string fpFinger: "right-index-finger"
    property bool fpEnrolling: false
    property int fpDone: 0              // touches taken in this enrolment
    property string fpMessage: ""
    property bool fpMessageBad: false
    property string fpTest: ""          // "", "listening", "match", "no-match"

    readonly property var fingerOrder: ["right-index-finger", "right-thumb", "right-middle-finger", "right-ring-finger",
        "right-little-finger", "left-index-finger", "left-thumb", "left-middle-finger", "left-ring-finger",
        "left-little-finger"]

    // The saved ones in a fixed order, so "Fingerprint 2" stays the same
    // print after another is added or removed before it.
    readonly property var fpSaved: section.fingerOrder.filter(f => (section.fp.enrolled || []).indexOf(f) >= 0)

    function fpRefresh() { fpStatus.running = false; fpStatus.running = true; }

    function fpEventText(result) {
        const swipe = section.fp.scanType === "swipe";
        switch (result) {
        case "enroll-stage-passed": return swipe ? I18n.tr("Good. Swipe again") : I18n.tr("Good. Lift and touch again");
        case "enroll-retry-scan": return I18n.tr("Try that again");
        case "enroll-swipe-too-short": return I18n.tr("The swipe was too short");
        case "enroll-finger-not-centered": return I18n.tr("Put the middle of your finger on the reader");
        case "enroll-remove-and-retry": return I18n.tr("Lift your finger and try again");
        case "enroll-duplicate": return I18n.tr("That finger is already saved");
        case "enroll-data-full": return I18n.tr("The reader has no room for more fingers");
        case "enroll-disconnected": return I18n.tr("The reader was disconnected");
        case "enroll-completed": return I18n.tr("Fingerprint saved");
        case "PermissionDenied": return I18n.tr("Not allowed to use the reader");
        case "AlreadyInUse": return I18n.tr("The reader is busy");
        default: return I18n.tr("The reader could not do that (%1)", result);
        }
    }

    Process {
        id: fpStatus
        running: true
        command: [section.daemonCmd, "fingerprint", "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try { section.fp = JSON.parse(this.text); } catch (e) { return; }
                // The finger offered is one not saved yet.
                const saved = section.fp.enrolled || [];
                if (saved.indexOf(section.fpFinger) >= 0)
                    section.fpFinger = section.fingerOrder.find(f => saved.indexOf(f) < 0) || "";
            }
        }
    }

    // One line a touch ("status …"), then "done …". stdin open: stopping
    // this Process closes it, and the daemon stops the scan and lets the
    // reader go.
    property var fpLogin: ({ supported: false, enabled: false })
    Process {
        id: fpLoginStatus
        running: true
        command: [section.daemonCmd, "fingerprint", "login", "status"]
        stdout: StdioCollector {
            onStreamFinished: { try { section.fpLogin = JSON.parse(this.text); } catch (e) {} }
        }
    }
    Process {
        id: fpLoginSet
        onExited: { fpLoginStatus.running = false; fpLoginStatus.running = true; }
    }

    Process {
        id: fpEnroll
        stdinEnabled: true
        command: [section.daemonCmd, "fingerprint", "enroll", section.fpFinger]
        stdout: SplitParser {
            onRead: line => {
                const parts = line.trim().split(" ");
                if (parts[0] === "status") {
                    if (parts[1] === "enroll-stage-passed") section.fpDone++;
                    section.fpMessage = section.fpEventText(parts[1]);
                    section.fpMessageBad = parts[1] !== "enroll-stage-passed" && parts[1] !== "enroll-completed";
                } else if (parts[0] === "done") {
                    const result = parts[1] === "error" ? parts[2] : parts[1];
                    if (result !== "cancelled") {
                        section.fpMessage = section.fpEventText(result);
                        section.fpMessageBad = result !== "enroll-completed";
                    }
                }
            }
        }
        onExited: { section.fpEnrolling = false; section.fpRefresh(); }
    }

    Process {
        id: fpVerify
        stdinEnabled: true
        command: [section.daemonCmd, "fingerprint", "verify"]
        stdout: SplitParser {
            onRead: line => {
                const parts = line.trim().split(" ");
                if (parts[0] === "done")
                    section.fpTest = parts[1] === "verify-match" ? "match" : "no-match";
            }
        }
    }

    Process { id: fpDelete; onExited: section.fpRefresh() }
}
