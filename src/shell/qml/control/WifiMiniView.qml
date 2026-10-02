import QtQuick
import QtQuick.Layouts
import "../Ui"
import "../Services"
import "."

// =============================================================================
// Wi-Fi mini-settings.
//
// The invented network list is gone. It listed "Dmytro_WiFi" and "FRITZ!Box
// 5690 TF" whenever the real scan came back empty, which is exactly when the
// user most needs to be told the truth — and clicking one connected to nothing.
// =============================================================================

MiniView {
    id: root

    title: I18n.tr("Wi-Fi")
    icon: "\u{f0928}"
    tone: Design.blue
    footerLabel: I18n.tr("Network Settings…")

    // Connecting to a secured network needs a password field. It lived only in
    // NetworkPopup, so deleting that popup without this would have left no way
    // to join a network you have not joined before.
    property string askingFor: ""

    readonly property bool isOn: Network.wifi.power === "on"
    readonly property var connectedNet: Network.wifi.connected || null
    readonly property var networks: (Network.wifi.networks || [])
        .filter(n => !n.connected)
        .sort((a, b) => b.signal - a.signal)

    trailing: Switch {
        checked: root.isOn
        activeColor: Design.blue
        onToggled: Network.toggleWifi()
    }

    // ── Off ──────────────────────────────────────────────────────────────────
    EmptyState {
        anchors.centerIn: parent
        width: parent.width
        visible: !root.isOn
        icon: "\u{f092e}"
        title: I18n.tr("Wi-Fi is off")
        hint: I18n.tr("Turn it on to see the networks around you.")
    }

    // ── Scanning, nothing found yet ──────────────────────────────────────────
    EmptyState {
        anchors.centerIn: parent
        width: parent.width
        visible: root.isOn && !root.connectedNet && root.networks.length === 0
        icon: "\u{f0928}"
        title: I18n.tr("Looking for networks")
        hint: I18n.tr("No network in range yet. The list refreshes on its own.")
    }

    ListView {
        id: netList
        anchors.fill: parent
        visible: root.isOn && (root.connectedNet || root.networks.length > 0)
        clip: true
        spacing: Design.s(Design.space.xs)
        model: root.networks

        header: ColumnLayout {
            width: netList.width
            spacing: Design.s(Design.space.xs)

            SectionLabel {
                text: I18n.tr("Connected")
                visible: root.connectedNet !== null
            }

            Rectangle {
                visible: root.connectedNet !== null
                Layout.fillWidth: true
                Layout.preferredHeight: Design.s(Design.size.row)
                radius: Design.s(Design.radius.ctl)
                color: connMa.containsMouse ? Design.tint(Design.blue, 0.22) : Design.tint(Design.blue, 0.15)
                border.color: Design.tint(Design.blue, 0.35)
                border.width: Design.border

                Behavior on color { ColorAnimation { duration: Design.duration.fast } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Design.s(Design.space.sm)
                    anchors.rightMargin: Design.s(Design.space.sm)
                    spacing: Design.s(Design.space.sm)

                    Icon {
                        text: "\u{f0928}"
                        role: "body"
                        color: Design.blue
                    }

                    Label {
                        text: root.connectedNet ? root.connectedNet.ssid : ""
                        role: "body"
                        weight: Design.weight.semibold
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }

                    Label {
                        visible: !connMa.containsMouse
                        text: root.connectedNet ? root.connectedNet.signal + "%" : ""
                        role: "caption"
                        isMono: true
                        dim: true
                    }

                    // A row that silently disconnects on click is a trap; say so
                    // under the pointer.
                    Label {
                        visible: connMa.containsMouse
                        text: I18n.tr("Disconnect")
                        role: "caption"
                        color: Design.blue
                    }

                    Icon {
                        visible: !connMa.containsMouse
                        text: "\u{f012c}"   // check
                        role: "caption"
                        color: Design.blue
                    }
                }

                Clickable { id: connMa; onClicked: Network.disconnectWifi() }
            }

            Item {
                Layout.preferredHeight: Design.s(Design.space.xs)
                visible: root.connectedNet !== null
            }

            SectionLabel {
                text: I18n.tr("Available")
                visible: root.networks.length > 0
            }
        }

        delegate: Rectangle {
            id: rowItem
            required property var modelData

            width: netList.width
            height: Design.s(Design.size.row)
            radius: Design.s(Design.radius.ctl)
            color: rowMa.containsMouse ? Design.glassHover : "transparent"

            Behavior on color { ColorAnimation { duration: Design.duration.fast } }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Design.s(Design.space.sm)
                anchors.rightMargin: Design.s(Design.space.sm)
                spacing: Design.s(Design.space.sm)

                Icon {
                    text: rowItem.modelData.icon || "\u{f0928}"
                    role: "body"
                    color: Design.textDim
                }

                Label {
                    text: rowItem.modelData.ssid || I18n.tr("Hidden network")
                    role: "body"
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }

                Label {
                    // Says why this row is one click and another asks for a
                    // password, instead of leaving the difference invisible.
                    text: Network.isBusy(rowItem.modelData.ssid) ? I18n.tr("Connecting…")
                        : (rowItem.modelData.known ? I18n.tr("Saved") : "")
                    role: "caption"
                    dim: true
                }

                Icon {
                    visible: rowItem.modelData.security && rowItem.modelData.security !== "open"
                    text: "\u{f033e}"   // lock
                    role: "caption"
                    color: Design.textFaint
                }
            }

            Clickable {
                id: rowMa
                onClicked: {
                    const n = rowItem.modelData;
                    const secured = n.security && n.security !== "open";
                    if (secured && !n.known) {
                        root.askingFor = n.ssid;
                        return;
                    }
                    Network.connectWifi(n.ssid);
                }
            }
        }
    }

    // ── Password sheet ───────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        visible: root.askingFor !== ""
        color: Design.tint(Design.surface, 0.96)
        radius: Design.s(Design.radius.card)

        // Swallows clicks so the list underneath cannot be used while asking.
        MouseArea { anchors.fill: parent }

        ColumnLayout {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Design.s(Design.space.md)
            spacing: Design.s(Design.space.sm)

            Icon {
                Layout.alignment: Qt.AlignHCenter
                text: "\u{f033e}"
                role: "display"
                color: Design.blue
            }

            Label {
                Layout.fillWidth: true
                text: root.askingFor
                role: "subhead"
                weight: Design.weight.bold
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
            }

            Label {
                Layout.fillWidth: true
                text: I18n.tr("This network is secured. Enter its password to join.")
                role: "caption"
                dim: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
            }

            Field {
                id: pskField
                Layout.fillWidth: true
                Layout.topMargin: Design.s(Design.space.xs)
                echoMode: TextInput.Password
                placeholder: I18n.tr("Password")
                onAccepted: v => root.join(v)
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Design.s(Design.space.sm)

                Pill {
                    Layout.fillWidth: true
                    label: I18n.tr("Cancel")
                    onClicked: root.cancelJoin()
                }

                Pill {
                    Layout.fillWidth: true
                    label: I18n.tr("Join")
                    icon: "\u{f012c}"
                    active: pskField.text.length > 0
                    onClicked: root.join(pskField.text)
                }
            }
        }
    }

    function join(psk) {
        if (psk.length === 0)
            return;
        Network.connectWifi(root.askingFor, psk);
        root.cancelJoin();
    }

    function cancelJoin() {
        root.askingFor = "";
        pskField.text = "";
    }
}
