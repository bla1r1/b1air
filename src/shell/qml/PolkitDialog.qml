import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "Ui"
import "Services"

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
    anchors { top: true; bottom: true; left: true; right: true }

    property string actionId: Quickshell.env("POLKIT_ACTION") || "org.freedesktop.policykit.exec"
    property string actionMessage: Quickshell.env("POLKIT_MESSAGE") || I18n.tr("Authentication is required to perform this action.")
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

        Clickable {
            anchors.fill: parent
            keyboard: false
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

        implicitWidth: Design.s(Design.width.menuMax)
        implicitHeight: dialogContent.implicitHeight + Design.s(Design.space.xxl)

        radius: Design.s(Design.radius.card)
        color: Design.surface
        border.color: Design.glassBorder
        border.width: 1

        ColumnLayout {
            id: dialogContent
            anchors.fill: parent
            anchors.margins: Design.s(Design.space.lg)
            spacing: Design.s(Design.space.lg)

            // ── Top Header: Security Shield Icon & Title ─────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: Design.s(Design.space.md)

                Rectangle {
                    Layout.preferredWidth: Design.s(Design.size.row)
                    Layout.preferredHeight: Design.s(Design.size.row)
                    radius: Design.s(Design.radius.panel)
                    color: Design.well

                    Icon {
                        anchors.centerIn: parent
                        text: "\u{f099d}" // a shield with a lock
                        color: Design.accent
                        role: "title"
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Design.s(Design.space.xxs)

                    Label {
                        text: I18n.tr("Authentication Required")
                        weight: Design.weight.semibold
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
                implicitHeight: Design.s(Design.size.row)
                radius: Design.s(Design.radius.ctl)
                color: Design.ground
                border.color: Design.glassBorder
                border.width: 1

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: Design.s(Design.space.sm)
                    spacing: Design.s(Design.space.sm)

                    Image {
                        Layout.preferredWidth: Design.s(Design.size.sm)
                        Layout.preferredHeight: Design.s(Design.size.sm)
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
                            radius: Design.s(Design.radius.card)
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
                        text: I18n.tr("Admin")
                    }
                }
            }

            // ── Password Input Field ─────────────────────────────────────────
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Design.s(Design.space.xs)

                Rectangle {
                    id: inputFrame
                    Layout.fillWidth: true
                    implicitHeight: Design.s(Design.size.row)
                    radius: Design.s(Design.radius.ctl)
                    color: Design.ground
                    border.color: pwdInput.activeFocus ? Design.accent : (polkitWin.errorMessage !== "" ? Design.danger : Design.glassBorder)
                    border.width: pwdInput.activeFocus ? 2 : 1

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Design.s(Design.space.md)
                        anchors.rightMargin: Design.s(Design.space.md)
                        spacing: Design.s(Design.space.sm)

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
                            font.pixelSize: Design.s(Design.font.glyphSm)
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
                    color: Design.danger
                    role: "caption"
                }
            }

            // ── Dialog Actions ───────────────────────────────────────────────
            RowLayout {
                Layout.fillWidth: true
                spacing: Design.s(Design.space.sm)

                Button {
                    label: I18n.tr("Cancel")
                    Layout.fillWidth: true
                    onActivated: polkitWin.cancelAuth()
                }

                Button {
                    label: polkitWin.isSubmitting ? I18n.tr("Authenticating...") : I18n.tr("Authenticate")
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
