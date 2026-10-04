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
    Card {
        RowLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.lg)

            Rectangle {
                Layout.preferredWidth: Design.s(88)
                Layout.preferredHeight: Design.s(88)
                radius: width / 2
                color: Design.tint(Design.accent, 0.14)
                clip: true

                Image {
                    anchors.fill: parent
                    visible: section.userInfo.avatar !== ""
                    // Decoded at the size drawn, not the file's (a 4K picture is 33 MB of pixels).
                    sourceSize: Qt.size(256, 256)
                    source: section.userInfo.avatar ? Paths.fileUrl(section.userInfo.avatar) : ""
                    fillMode: Image.PreserveAspectCrop
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

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: avatarFileDialog.open()
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

                    ActionButton {
                        Layout.fillWidth: false
                        icon: "\u{f03e}"
                        label: I18n.tr("Change Avatar")
                        onActivated: avatarFileDialog.open()
                    }

                    ActionButton {
                        Layout.fillWidth: false
                        icon: "\u{f084}"
                        label: I18n.tr("Change Password")
                        onActivated: Quickshell.execDetached([section.daemonCmd, "user", "change-password"])
                    }
                }
            }
        }
    }

    Card {
        title: I18n.tr("Fingerprint")
        subtitle: section.fp.available ? section.fp.device : I18n.tr("Open the lock screen with a touch")
        icon: "\u{f0237}"
        accentColor: Design.teal

        EmptyState {
            visible: !section.fp.available
            Layout.fillWidth: true
            icon: "\u{f0237}"
            title: section.fp.service ? I18n.tr("No fingerprint reader") : I18n.tr("Fingerprint support is not installed")
            hint: section.fp.service ? I18n.tr("fprintd is running, but it found no reader it can drive.")
                                     : I18n.tr("Install fprintd (and its PAM module) to use a fingerprint reader.")
        }

        // The fingers already saved, each with a way to remove it.
        Repeater {
            model: section.fp.available ? (section.fp.enrolled || []) : []
            RowLayout {
                required property var modelData
                Layout.fillWidth: true
                Icon { text: "\u{f0237}"; color: Design.teal }
                Label { text: section.fingerNames[modelData] || modelData; Layout.fillWidth: true }
                ActionButton {
                    icon: "\u{f0a7a}"
                    label: I18n.tr("Remove")
                    destructive: true
                    confirmLabel: I18n.tr("Remove?")
                    onActivated: {
                        fpDelete.command = [section.daemonCmd, "fingerprint", "delete", modelData];
                        fpDelete.running = true;
                    }
                }
            }
        }

        Label {
            visible: section.fp.available && !section.fpEnrolling
            text: (section.fp.enrolled || []).length === 0 ? I18n.tr("No finger saved yet. Pick one to add:")
                                                           : I18n.tr("Add another finger:")
            role: "caption"
            dim: true
        }

        Flow {
            visible: section.fp.available && !section.fpEnrolling
            Layout.fillWidth: true
            spacing: Design.s(Design.space.xs)
            Repeater {
                model: section.fingerOrder.filter(f => (section.fp.enrolled || []).indexOf(f) < 0)
                Pill {
                    required property var modelData
                    label: section.fingerNames[modelData]
                    active: section.fpFinger === modelData
                    onClicked: section.fpFinger = modelData
                }
            }
        }

        RowLayout {
            visible: section.fp.available
            Layout.fillWidth: true
            spacing: Design.s(Design.space.sm)
            ActionButton {
                visible: !section.fpEnrolling && section.fpFinger !== ""
                icon: "\u{f0415}"
                label: I18n.tr("Add %1", section.fingerNames[section.fpFinger] || "")
                onActivated: {
                    section.fpDone = 0;
                    section.fpMessage = section.fp.scanType === "swipe" ? I18n.tr("Swipe your finger across the reader")
                                                                         : I18n.tr("Touch the reader");
                    section.fpMessageBad = false;
                    section.fpEnrolling = true;
                    fpEnroll.running = true;
                }
            }
            ActionButton {
                visible: section.fpEnrolling
                icon: "\u{f0156}"
                label: I18n.tr("Cancel")
                onActivated: fpEnroll.running = false
            }
            ActionButton {
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
                spacing: Design.s(6)
                Repeater {
                    model: section.fp.stages
                    Rectangle {
                        required property int index
                        width: Design.s(14); height: width; radius: width / 2
                        color: index < section.fpDone ? Design.teal : Design.hover
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

        Toggle {
            visible: section.fp.available
            label: I18n.tr("Unlock with a fingerprint")
            subtitle: I18n.tr("On the lock screen, a touch on the reader works as well as the password")
            checked: Settings.fingerprintUnlock !== false
            onToggled: Settings.set("fingerprintUnlock", !(Settings.fingerprintUnlock !== false))
        }
    }

    // ── 3. Account Details Card ──────────────────────────────────────────────
    Card {
        title: I18n.tr("Account Details & Shell")
        subtitle: I18n.tr("System user configurations and login preferences")
        icon: "\u{f013}"
        accentColor: Design.blue

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.md)

            // Full Name Input
            RowLayout {
                Layout.fillWidth: true
                spacing: Design.s(Design.space.md)

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Design.s(Design.space.xs)

                    Label {
                        text: I18n.tr("Display / Full Name")
                        weight: Design.weight.medium
                    }
                    Label {
                        text: I18n.tr("Real name shown on lockscreen and greeter")
                        dim: true
                    }
                }

                Field {
                    id: nameField
                    Layout.preferredWidth: Design.s(220)
                    text: section.userInfo.name || ""
                    placeholder: I18n.tr("Enter full name...")
                    onCommitted: v => {
                        if (v.trim().length > 0) {
                            Quickshell.execDetached([section.daemonCmd, "user", "set-name", v.trim()]);
                            section.loadUserInfo();
                        }
                    }
                }

                ActionButton {
                    Layout.fillWidth: false
                    icon: "\u{f00c}"
                    label: I18n.tr("Save")
                    tone: Design.sapphire
                    onActivated: {
                        if (nameField.text.trim().length > 0) {
                            Quickshell.execDetached([section.daemonCmd, "user", "set-name", nameField.text.trim()]);
                            section.loadUserInfo();
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Design.s(1)
                color: Design.line
            }

            // Default Shell
            RowLayout {
                Layout.fillWidth: true
                spacing: Design.s(Design.space.md)

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Design.s(Design.space.xs)

                    Label {
                        text: I18n.tr("Default Shell")
                        weight: Design.weight.medium
                    }
                    Label {
                        text: I18n.tr("Login shell executed for terminals and virtual consoles")
                        dim: true
                    }
                }

                RowLayout {
                    spacing: Design.s(Design.space.xs)

                    Repeater {
                        model: section.availableShells

                        Pill {
                            label: modelData.label
                            active: section.userInfo.shell && (section.userInfo.shell === modelData.path || section.userInfo.shell.endsWith("/" + modelData.label))
                            onClicked: {
                                Quickshell.execDetached([section.daemonCmd, "user", "set-shell", modelData.path]);
                                section.loadUserInfo();
                            }
                        }
                    }
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

    Card {
        title: I18n.tr("Session & Login Screen")
        subtitle: I18n.tr("What draws this desktop, and what greets you before it")
        icon: "\u{f108}"
        accentColor: Design.green

        RowLayout {
            Layout.fillWidth: true
            Label { text: I18n.tr("Compositor"); Layout.fillWidth: true }
            Badge { text: section.compositorName; color: Design.green }
        }

        RowLayout {
            Layout.fillWidth: true
            Label { text: I18n.tr("Login screen theme"); Layout.fillWidth: true }
            Badge { text: section.greeterTheme; color: Design.sapphire }
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

    readonly property var fingerNames: ({
        "right-thumb": I18n.tr("Right thumb"), "right-index-finger": I18n.tr("Right index finger"),
        "right-middle-finger": I18n.tr("Right middle finger"), "right-ring-finger": I18n.tr("Right ring finger"),
        "right-little-finger": I18n.tr("Right little finger"), "left-thumb": I18n.tr("Left thumb"),
        "left-index-finger": I18n.tr("Left index finger"), "left-middle-finger": I18n.tr("Left middle finger"),
        "left-ring-finger": I18n.tr("Left ring finger"), "left-little-finger": I18n.tr("Left little finger")
    })
    readonly property var fingerOrder: ["right-index-finger", "right-thumb", "right-middle-finger", "right-ring-finger",
        "right-little-finger", "left-index-finger", "left-thumb", "left-middle-finger", "left-ring-finger",
        "left-little-finger"]

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

    // ── 5. File Dialog for Avatar Selection ──────────────────────────────────
    FileDialog {
        id: avatarFileDialog
        title: I18n.tr("Select Avatar Image")
        nameFilters: [I18n.tr("Image files") + " (*.png *.jpg *.jpeg *.svg)"]
        onAccepted: {
            let path = selectedFile.toString().replace(/^file:\/\//, "");
            Quickshell.execDetached([section.daemonCmd, "user", "set-avatar", path]);
            section.loadUserInfo();
        }
    }
}
