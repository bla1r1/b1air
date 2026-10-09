import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "Ui"
import "Services"

// =============================================================================
// Sign in with a phone: the QR code b1air-passkey (src/passkey) puts up when a
// website asks the phone-as-a-security-key for a passkey.
//
// Run by b1air-passkey as `quickshell -p` for one request, as the polkit
// dialog is, and spoken to over the socket it names in PASSKEY_SOCKET (the
// lines are listed in src/passkey/src/prompt.rs). It shows; it decides
// nothing. Closing it says "cancel", and the browser is told no.
// =============================================================================

PanelWindow {
    id: win
    color: "transparent"

    WlrLayershell.namespace: "qs-passkey"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    exclusionMode: ExclusionMode.Ignore
    focusable: true

    screen: Screens.focused
    anchors { top: true; bottom: true; left: true; right: true }

    readonly property string rpId: Quickshell.env("PASSKEY_RP") || ""
    readonly property bool creating: Quickshell.env("PASSKEY_OP") === "create"

    // waiting | connecting | connected; "" until the code is in.
    property string phase: ""
    property string problem: ""        // bluetooth | failed | timeout
    property int qrWidth: 0
    property string qrBits: ""

    Socket {
        id: link
        path: Quickshell.env("PASSKEY_SOCKET") || ""
        connected: path !== ""
        parser: SplitParser {
            onRead: line => win.take(line)
        }
        // b1air-passkey closes it when the phone has answered, or the
        // browser gave up: nothing is left to show.
        onConnectionStateChanged: if (!connected) Qt.quit()
    }

    function take(line) {
        const sp = line.indexOf(" ");
        const word = sp < 0 ? line : line.substring(0, sp);
        const rest = sp < 0 ? "" : line.substring(sp + 1);
        if (word === "qr") {
            const parts = rest.split(" ");
            win.qrWidth = parseInt(parts[0]);
            win.qrBits = parts[1] || "";
            qr.requestPaint();
        } else if (word === "state") {
            win.phase = rest;
        } else if (word === "error") {
            win.problem = rest;
        }
    }

    function cancel() {
        if (link.connected) {
            link.write("cancel\n");
            link.flush();
        }
        quitTimer.start();
    }
    Timer { id: quitTimer; interval: 100; onTriggered: Qt.quit() }

    Shortcut { sequence: "Escape"; onActivated: win.cancel() }

    // The desktop behind, dimmed. A stray click does not cancel: the code is
    // what someone is pointing a phone at.
    Rectangle {
        anchors.fill: parent
        color: Qt.alpha(Design.ground, 0.70)
        MouseArea { anchors.fill: parent }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        implicitWidth: Design.s(400)
        implicitHeight: body.implicitHeight + Design.s(40)
        radius: Design.s(Design.radius.card)
        color: Design.surface
        border.color: Design.glassBorder
        border.width: 1

        ColumnLayout {
            id: body
            anchors.fill: parent
            anchors.margins: Design.s(20)
            spacing: Design.s(14)

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Design.s(2)
                Label {
                    Layout.fillWidth: true
                    text: win.creating ? I18n.tr("Save a passkey on your phone") : I18n.tr("Sign in with your phone")
                    weight: Design.weight.bold
                    role: "subhead"
                    wrapMode: Text.WordWrap
                }
                Label {
                    Layout.fillWidth: true
                    text: win.rpId
                    role: "caption"
                    dim: true
                    elide: Text.ElideMiddle
                }
            }

            // The code, dark on white whatever the theme: a phone's camera
            // reads a light code on dark far less reliably.
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: Design.s(248)
                Layout.preferredHeight: Design.s(248)
                radius: Design.s(Design.radius.ctl)
                color: "#ffffff"
                visible: win.problem === ""

                Canvas {
                    id: qr
                    anchors.fill: parent
                    anchors.margins: Design.s(14)
                    onPaint: {
                        const ctx = getContext("2d");
                        ctx.reset();
                        const n = win.qrWidth;
                        if (n <= 0 || win.qrBits.length !== n * n) return;
                        // Whole pixels per module, centred: a fractional
                        // module blurs its edges and slows the scan.
                        const m = Math.floor(Math.min(width, height) / n);
                        const off = Math.floor((Math.min(width, height) - m * n) / 2);
                        ctx.fillStyle = "#000000";
                        for (let y = 0; y < n; ++y)
                            for (let x = 0; x < n; ++x)
                                if (win.qrBits.charCodeAt(y * n + x) === 49)
                                    ctx.fillRect(off + x * m, off + y * m, m, m);
                    }
                }

                // Over the code once the phone has it: scanning it again
                // does nothing.
                Rectangle {
                    anchors.fill: parent
                    radius: parent.radius
                    color: Qt.alpha(Design.surface, 0.9)
                    visible: win.phase === "connecting" || win.phase === "connected"
                    Icon {
                        anchors.centerIn: parent
                        text: "\u{f011c}"
                        role: "display"
                        color: Design.accent
                    }
                }
            }

            Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                text: win.problem === "bluetooth"
                      ? I18n.tr("Bluetooth is off, or this computer has none. The phone proves it is nearby over Bluetooth: turn it on and try again.")
                      : win.problem === "timeout"
                      ? I18n.tr("The code was not scanned in time.")
                      : win.problem !== ""
                      ? I18n.tr("The phone could not be reached. Try again; if it keeps failing, turn Bluetooth off and on on the phone.")
                      : win.phase === "connected"
                      ? I18n.tr("Confirm on the phone.")
                      : win.phase === "connecting"
                      ? I18n.tr("Connecting to the phone…")
                      : I18n.tr("Scan the code with your phone's camera. Bluetooth has to be on, on the phone and on this computer.")
                color: win.problem !== "" ? Design.dangerText : Design.text
            }

            ActionButton {
                Layout.fillWidth: true
                label: win.problem !== "" ? I18n.tr("Close") : I18n.tr("Cancel")
                onActivated: win.cancel()
            }
        }
    }

    Component.onCompleted: Screens.refresh()
}
