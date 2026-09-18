import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import QtQuick.Dialogs
import Quickshell
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

    property string daemonCmd: Quickshell.env("HOME") + "/.local/bin/b1air-daemon"
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

    // ── 2. Profile Overview Card ─────────────────────────────────────────────
    Card {
        title: section.userInfo.name || section.userInfo.username
        subtitle: "@" + section.userInfo.username + " • UID " + section.userInfo.uid + " • " + section.userInfo.home
        icon: "\u{f007}"
        accentColor: Design.mauve

        RowLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.lg)

            // Circular Avatar with Accent Frame
            Rectangle {
                Layout.preferredWidth: Design.s(72)
                Layout.preferredHeight: Design.s(72)
                radius: width / 2
                color: Design.surface
                border.width: Design.s(2)
                border.color: Design.accent
                clip: true

                Image {
                    anchors.fill: parent
                    anchors.margins: Design.s(2)
                    visible: section.userInfo.avatar !== ""
                    // Decoded at the size drawn, not the file's (a 4K picture is 33 MB of pixels).
                    sourceSize: Qt.size(256, 256)
                    source: section.userInfo.avatar ? Paths.fileUrl(section.userInfo.avatar) : ""
                    fillMode: Image.PreserveAspectCrop
                }

                Icon {
                    anchors.centerIn: parent
                    visible: section.userInfo.avatar === ""
                    text: "\u{f007}"
                    role: "hero"
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
                spacing: Design.s(Design.space.sm)

                ButtonRow {
                    spacing: Design.s(Design.space.sm)

                    ActionButton {
                        icon: "\u{f03e}"
                        label: "Change Avatar"
                        onActivated: avatarFileDialog.open()
                    }

                    ActionButton {
                        icon: "\u{f084}"
                        label: "Change Password"
                        tone: Design.sapphire
                        onActivated: {
                            Quickshell.execDetached([section.daemonCmd, "user", "change-password"]);
                        }
                    }
                }

                Label {
                    text: "Synchronized with SDDM and ~/.face.icon automatically"
                    dim: true
                }
            }
        }
    }

    // ── 3. Account Details Card ──────────────────────────────────────────────
    Card {
        title: "Account Details & Shell"
        subtitle: "System user configurations and login preferences"
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
                        text: "Display / Full Name"
                        weight: Design.weight.medium
                    }
                    Label {
                        text: "Real name shown on lockscreen and greeter"
                        dim: true
                    }
                }

                Field {
                    id: nameField
                    Layout.preferredWidth: Design.s(220)
                    text: section.userInfo.name || ""
                    placeholder: "Enter full name..."
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
                    label: "Save"
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
                        text: "Default Shell"
                        weight: Design.weight.medium
                    }
                    Label {
                        text: "Login shell executed for terminals and virtual consoles"
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

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Design.s(1)
                color: Design.line
            }

            // Assigned Groups
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Design.s(Design.space.xs)

                Label {
                    text: "Assigned Groups"
                    weight: Design.weight.medium
                }

                Label {
                    text: section.userInfo.groups || "wheel, input, audio, video, storage"
                    dim: true
                    wrapMode: Text.Wrap
                }
            }
        }
    }

    // ── 4. Session & login screen ────────────────────────────────────────────
    //
    // Both badges were constants — "b1air (SwayFX)" and "b1air SDDM Theme" —
    // shown whatever was running, plain sway included. They are read now.
    property string compositorName: "…"
    property string greeterTheme: "…"
    Process {
        running: true
        command: ["sh", "-c",
            "p=$(pgrep -x sway | head -n1); " +
            "if [ -n \"$p\" ]; then \"$(readlink -f /proc/$p/exe)\" --version 2>/dev/null | head -n1; else echo 'not sway'; fi; " +
            "cat /etc/sddm.conf /etc/sddm.conf.d/*.conf 2>/dev/null | sed -n 's/^Current=//p' | tail -n1"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.trim().split("\n");
                const v = (lines[0] || "").trim();
                section.compositorName = v.toLowerCase().startsWith("swayfx") ? "swayFX " + (v.split(" ")[2] || "")
                                       : v.startsWith("sway") ? "sway " + (v.split(" ")[2] || "")
                                       : "—";
                section.greeterTheme = (lines[1] || "").trim() || "SDDM default";
            }
        }
    }

    Card {
        title: "Session & Login Screen"
        subtitle: "What draws this desktop, and what greets you before it"
        icon: "\u{f108}"
        accentColor: Design.green

        RowLayout {
            Layout.fillWidth: true
            Label { text: "Compositor"; Layout.fillWidth: true }
            Badge { text: section.compositorName; color: Design.green }
        }

        RowLayout {
            Layout.fillWidth: true
            Label { text: "Login screen theme"; Layout.fillWidth: true }
            Badge { text: section.greeterTheme; color: Design.sapphire }
        }
    }

    // ── 5. File Dialog for Avatar Selection ──────────────────────────────────
    FileDialog {
        id: avatarFileDialog
        title: "Select Avatar Image"
        nameFilters: ["Image files (*.png *.jpg *.jpeg *.svg)"]
        onAccepted: {
            let path = selectedFile.toString().replace(/^file:\/\//, "");
            Quickshell.execDetached([section.daemonCmd, "user", "set-avatar", path]);
            section.loadUserInfo();
        }
    }
}
