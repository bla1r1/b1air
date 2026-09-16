import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "../Ui"
import "../Services"

// =============================================================================
// Native Polkit Authentication Dialog
//
// Modal Tokyo Night privilege escalation dialog for root / administrative tasks.
// =============================================================================

PanelWindow {
    id: polkitWin
    color: "transparent"

    WlrLayershell.namespace: "qs-polkit"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    
    exclusionMode: ExclusionMode.Ignore
    focusable: true
    
    // A password prompt belongs on the screen being used, not always on the
    // first one.
    screen: Screens.focused
    width: Screen.width
    height: Screen.height

    property string actionId: Quickshell.env("POLKIT_ACTION") || "org.freedesktop.policykit.exec"
    property string actionMessage: Quickshell.env("POLKIT_MESSAGE") || "Authentication is required to perform this action."
    property string targetUser: Quickshell.env("POLKIT_USER") || Quickshell.env("USER") || "root"
    property string cookie: Quickshell.env("POLKIT_COOKIE") || ""
    property string responseFile: Quickshell.env("POLKIT_RESP_FILE") || ((Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/b1air/polkit-response")

    property bool isSubmitting: false
    property string errorMessage: ""
    property real shakeOffset: 0
    property string pendingResponse: ""
    property bool pendingCancel: false

    Process {
        id: responseWriter
        stdinEnabled: true
        command: ["b1air-daemon", "polkit-write", polkitWin.responseFile]
        onStarted: {
            write(polkitWin.pendingCancel ? "CANCELLED\n" : polkitWin.pendingResponse + "\n");
            stdinEnabled = false;
        }
    }

    // Backdrop dimmer
    Rectangle {
        anchors.fill: parent
        color: Qt.alpha(Design.ground, 0.70)

        MouseArea {
            anchors.fill: parent
            onClicked: polkitWin.cancelAuth()
        }
    }

    SequentialAnimation {
        id: shakeAnim
        NumberAnimation { target: polkitWin; property: "shakeOffset"; from: 0; to: -12; duration: 50; easing.type: Easing.OutQuad }
        NumberAnimation { target: polkitWin; property: "shakeOffset"; from: -12; to: 12; duration: 50; easing.type: Easing.InOutQuad }
        NumberAnimation { target: polkitWin; property: "shakeOffset"; from: 12; to: -8; duration: 50; easing.type: Easing.InOutQuad }
        NumberAnimation { target: polkitWin; property: "shakeOffset"; from: -8; to: 8; duration: 50; easing.type: Easing.InOutQuad }
        NumberAnimation { target: polkitWin; property: "shakeOffset"; from: 8; to: 0; duration: 50; easing.type: Easing.OutQuad }
    }

    // Modal Card
    Rectangle {
        id: dialogCard
        anchors.centerIn: parent
        anchors.horizontalCenterOffset: polkitWin.shakeOffset

        implicitWidth: Design.s(420)
        implicitHeight: dialogContent.implicitHeight + Design.s(32)

        radius: Design.s(Design.radius.card)
        color: Design.surface
        border.color: Design.glassBorder
        border.width: 1

        ColumnLayout {
            id: dialogContent
            anchors.fill: parent
            anchors.margins: Design.s(20)
            spacing: Design.s(16)

            // ── Top Header: Security Shield Icon & Title ─────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: Design.s(12)

                Rectangle {
                    Layout.preferredWidth: Design.s(44)
                    Layout.preferredHeight: Design.s(44)
                    radius: Design.s(22)
                    color: Design.sunken

                    Icon {
                        anchors.centerIn: parent
                        text: "\u{f04a4}" // Security Shield lock
                        color: Design.sapphire
                        role: "title"
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Design.s(2)

                    Label {
                        text: "Authentication Required"
                        weight: Design.weight.bold
                        role: "subhead"
                    }

                    Label {
                        text: polkitWin.actionId
                        role: "caption"
                        dim: true
                        elide: Text.ElideMiddle
                        Layout.fillWidth: true
                    }
                }
            }

            // ── Description Message ──────────────────────────────────────────
            Label {
                text: polkitWin.actionMessage
                role: "body"
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            // ── User Identity Pill ───────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: Design.s(44)
                radius: Design.s(10)
                color: Design.ground
                border.color: Design.glassBorder
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: Design.s(8)
                    spacing: Design.s(10)

                    Image {
                        Layout.preferredWidth: Design.s(28)
                        Layout.preferredHeight: Design.s(28)
                        // Decoded at the size drawn, not the file's (a 4K picture is 33 MB of pixels).
                        sourceSize: Qt.size(128, 128)
                        source: "file://" + Quickshell.env("HOME") + "/.face.icon"
                        fillMode: Image.PreserveAspectCrop
                        mipmap: true
                        visible: status === Image.Ready

                        Rectangle {
                            anchors.fill: parent
                            color: "transparent"
                            border.color: Design.glassBorder
                            border.width: 1
                            radius: Design.s(14)
                        }
                    }

                    Icon {
                        visible: !parent.children[0].visible
                        text: "\u{f007}"
                        color: Design.accentAlt
                        role: "caption"
                    }

                    Label {
                        text: polkitWin.targetUser
                        weight: Design.weight.semibold
                        role: "body"
                        Layout.fillWidth: true
                    }

                    Badge {
                        text: "Admin"
                        tone: Design.sapphire
                    }
                }
            }

            // ── Password Input Field ─────────────────────────────────────────
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Design.s(6)

                Rectangle {
                    id: inputFrame
                    Layout.fillWidth: true
                    implicitHeight: Design.s(44)
                    radius: Design.s(10)
                    color: Design.ground
                    border.color: pwdInput.activeFocus ? Design.sapphire : (polkitWin.errorMessage !== "" ? Design.red : Design.glassBorder)
                    border.width: pwdInput.activeFocus ? 2 : 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Design.s(12)
                        anchors.rightMargin: Design.s(12)
                        spacing: Design.s(8)

                        Icon {
                            text: "\u{f023}"
                            color: Design.textDim
                            role: "caption"
                        }

                        TextInput {
                            id: pwdInput
                            Layout.fillWidth: true
                            echoMode: showPwdToggle.checked ? TextInput.Normal : TextInput.Password
                            font.family: Design.font.mono
                            font.pixelSize: Design.s(14)
                            color: Design.text
                            focus: true
                            clip: true

                            Keys.onReturnPressed: polkitWin.submitAuth()
                            Keys.onEscapePressed: polkitWin.cancelAuth()
                        }

                        IconButton {
                            id: showPwdToggle
                            property bool checked: false
                            icon: checked ? "\u{f06e}" : "\u{f070}"
                            role: "caption"
                            onClicked: checked = !checked
                        }
                    }
                }

                Label {
                    visible: polkitWin.errorMessage !== ""
                    text: polkitWin.errorMessage
                    color: Design.red
                    role: "caption"
                }
            }

            // ── Dialog Actions ───────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: Design.s(10)

                ActionButton {
                    label: "Cancel"
                    Layout.fillWidth: true
                    onActivated: polkitWin.cancelAuth()
                }

                ActionButton {
                    label: polkitWin.isSubmitting ? "Authenticating..." : "Authenticate"
                    tone: Design.sapphire
                    Layout.fillWidth: true
                    enabled: pwdInput.text.length > 0 && !polkitWin.isSubmitting
                    onActivated: polkitWin.submitAuth()
                }
            }
        }
    }

    Component.onCompleted: {
        Screens.refresh();
        pwdInput.forceActiveFocus();
    }

    function submitAuth() {
        if (pwdInput.text.length === 0) return;
        polkitWin.isSubmitting = true;
        polkitWin.errorMessage = "";

        // Send through stdin; never expose the password in argv or shell text.
        polkitWin.pendingResponse = pwdInput.text;
        polkitWin.pendingCancel = false;
        responseWriter.running = true;
        
        // Short delay before closing dialog
        closeTimer.start();
    }

    Timer {
        id: closeTimer
        interval: 150
        repeat: false
        onTriggered: {
            Qt.quit();
        }
    }

    function cancelAuth() {
        polkitWin.pendingResponse = "";
        polkitWin.pendingCancel = true;
        responseWriter.running = true;
        closeTimer.start();
    }
}
