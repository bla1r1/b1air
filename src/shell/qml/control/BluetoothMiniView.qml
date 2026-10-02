import QtQuick
import QtQuick.Layouts
import "../Ui"
import "../Services"
import "."

// =============================================================================
// Bluetooth mini-settings.
//
// Two things were wrong beyond the invented "AirPods Pro" list: BlueZ reports an
// icon *name* ("audio-headset"), which was being printed straight into a
// nerd-font Text and came out as the literal string, and a device row gave no
// sign that a connect was in flight.
// =============================================================================

MiniView {
    id: root

    title: I18n.tr("Bluetooth")
    icon: "\u{f00af}"
    tone: Design.mauve
    footerLabel: I18n.tr("Bluetooth Settings…")

    readonly property bool isOn: Network.bluetooth.power === "on"
    readonly property var connectedDev: Network.bluetooth.connected || null
    readonly property var devices: (Network.bluetooth.devices || [])
        .filter(d => !d.connected)
        .sort((a, b) => (b.paired ? 1 : 0) - (a.paired ? 1 : 0))

    function glyphFor(name) {
        const i = String(name || "").toLowerCase();
        if (i.indexOf("headset") >= 0 || i.indexOf("headphone") >= 0) return "\u{f0025}";
        if (i.indexOf("audio") >= 0 || i.indexOf("speaker") >= 0) return "\u{f057e}";
        if (i.indexOf("keyboard") >= 0) return "\u{f030c}";
        if (i.indexOf("mouse") >= 0 || i.indexOf("pointing") >= 0) return "\u{f087b}";
        if (i.indexOf("display") >= 0 || i.indexOf("video") >= 0) return "\u{f0379}";
        return "\u{f00af}";
    }

    trailing: Switch {
        checked: root.isOn
        activeColor: Design.mauve
        onToggled: Network.toggleBluetooth()
    }

    EmptyState {
        anchors.centerIn: parent
        width: parent.width
        visible: !root.isOn
        icon: "\u{f00b0}"
        title: I18n.tr("Bluetooth is off")
        hint: I18n.tr("Turn it on to connect headphones, a keyboard or a mouse.")
    }

    EmptyState {
        anchors.centerIn: parent
        width: parent.width
        visible: root.isOn && !root.connectedDev && root.devices.length === 0
        icon: "\u{f00af}"
        title: I18n.tr("No devices yet")
        hint: I18n.tr("Put a device in pairing mode and it will show up here.")
    }

    ListView {
        id: devList
        anchors.fill: parent
        visible: root.isOn && (root.connectedDev || root.devices.length > 0)
        clip: true
        spacing: Design.s(Design.space.xs)
        model: root.devices

        header: ColumnLayout {
            width: devList.width
            spacing: Design.s(Design.space.xs)

            SectionLabel {
                text: I18n.tr("Connected")
                visible: root.connectedDev !== null
            }

            Rectangle {
                visible: root.connectedDev !== null
                Layout.fillWidth: true
                Layout.preferredHeight: Design.s(Design.size.row)
                radius: Design.s(Design.radius.ctl)
                color: connMa.containsMouse ? Design.tint(Design.mauve, 0.22) : Design.tint(Design.mauve, 0.15)
                border.color: Design.tint(Design.mauve, 0.35)
                border.width: Design.border

                Behavior on color { ColorAnimation { duration: Design.duration.fast } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Design.s(Design.space.sm)
                    anchors.rightMargin: Design.s(Design.space.sm)
                    spacing: Design.s(Design.space.sm)

                    Icon {
                        text: root.glyphFor(root.connectedDev ? root.connectedDev.icon : "")
                        role: "body"
                        color: Design.mauve
                    }

                    Label {
                        text: root.connectedDev ? root.connectedDev.name : ""
                        role: "body"
                        weight: Design.weight.semibold
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                    }

                    Label {
                        visible: root.connectedDev && root.connectedDev.battery >= 0
                        text: (root.connectedDev ? root.connectedDev.battery : 0) + "%"
                        role: "caption"
                        isMono: true
                        dim: true
                    }

                    Label {
                        text: connMa.containsMouse ? I18n.tr("Disconnect") : ""
                        role: "caption"
                        color: Design.mauve
                    }

                    Icon {
                        visible: !connMa.containsMouse
                        text: "\u{f012c}"
                        role: "caption"
                        color: Design.mauve
                    }
                }

                Clickable {
                    id: connMa
                    onClicked: if (root.connectedDev) Network.disconnectDevice(root.connectedDev.mac)
                }
            }

            Item {
                Layout.preferredHeight: Design.s(Design.space.xs)
                visible: root.connectedDev !== null
            }

            SectionLabel {
                text: I18n.tr("Other devices")
                visible: root.devices.length > 0
            }
        }

        delegate: Rectangle {
            id: devRow
            required property var modelData

            width: devList.width
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
                    text: root.glyphFor(devRow.modelData.icon)
                    role: "body"
                    color: Design.textDim
                }

                Label {
                    text: devRow.modelData.name || devRow.modelData.mac
                    role: "body"
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }

                Label {
                    visible: devRow.modelData.battery >= 0
                    text: devRow.modelData.battery + "%"
                    role: "caption"
                    isMono: true
                    dim: true
                }

                Label {
                    text: Network.isBusy(devRow.modelData.mac) ? I18n.tr("Connecting…")
                        : (devRow.modelData.paired ? I18n.tr("Paired") : I18n.tr("Pair"))
                    role: "caption"
                    dim: !rowMa.containsMouse
                    color: rowMa.containsMouse ? Design.mauve : Design.textDim
                }
            }

            Clickable {
                id: rowMa
                onClicked: Network.connectDevice(devRow.modelData.mac)
            }
        }
    }
}
