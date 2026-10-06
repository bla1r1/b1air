import QtQuick
import QtQuick.Layouts
import Quickshell
import "../Ui"
import "../Services"

// The short menu under a status icon in the bar — Wi-Fi, sound, battery — the
// way a desktop's menu bar opens one: a switch, the few choices that matter
// (networks, outputs, the power mode), and the settings page at the bottom.
// The Control Center keeps the full pages; this is the quick look.
//
// page: "wifi" | "sound" | "battery" (Main.qml's pageFor).
PopupShell {
    id: menu
    padding: Design.space.md
    cornerRadius: Design.radius.card

    // Main.qml fits the window to this.
    readonly property real contentHeight: col.implicitHeight + Design.s(menu.padding) * 2

    Component.onCompleted: { Network.acquire(); Audio.acquire(); Power.acquire(); }
    Component.onDestruction: { Network.release(); Audio.release(); Power.release(); }

    function openSettings(page) {
        menu.close();
        Quickshell.execDetached(["b1air-settings", page]);
    }

    ColumnLayout {
        id: col
        width: parent.width
        spacing: Design.s(Design.space.xs)

        // ── Wi-Fi ───────────────────────────────────────────────────────────
        ColumnLayout {
            id: wifiCol
            visible: menu.page === "wifi"
            Layout.fillWidth: true
            spacing: Design.s(2)
            readonly property bool on: Network.wifi.power === "on"
            readonly property var connected: Network.wifi.connected || null
            readonly property var others: (Network.wifi.networks || []).filter(n => !n.connected)
                                           .sort((a, b) => b.signal - a.signal).slice(0, 7)

            MenuHeader {
                title: I18n.tr("Wi-Fi")
                Switch { checked: wifiCol.on; onToggled: Network.toggleWifi() }
            }
            MenuRow {
                visible: !!wifiCol.connected
                glyph: wifiCol.connected ? Network._wifiIcon(wifiCol.connected.signal) : ""
                lit: true
                text: wifiCol.connected ? wifiCol.connected.ssid : ""
                detail: I18n.tr("Connected")
                onClicked: Network.disconnectWifi()
            }
            MenuSeparator { visible: wifiCol.on && wifiCol.others.length > 0 }
            MenuCaption { visible: wifiCol.on && wifiCol.others.length > 0; text: I18n.tr("Other networks") }
            Repeater {
                model: wifiCol.on ? wifiCol.others : []
                delegate: MenuRow {
                    required property var modelData
                    glyph: Network._wifiIcon(modelData.signal)
                    text: modelData.ssid
                    trailing: modelData.security && modelData.security !== "open" ? "\u{f033e}" : ""
                    detail: Network.isBusy(modelData.ssid) ? I18n.tr("Connecting…") : ""
                    onClicked: {
                        const secured = modelData.security && modelData.security !== "open";
                        // A password to type: on the Control Center's page, which has the field.
                        if (secured && !modelData.known) menu.openPanel("toggle:wifi:");
                        else Network.connectWifi(modelData.ssid);
                    }
                }
            }
            MenuSeparator {}
            MenuRow { text: I18n.tr("Wi-Fi Settings…"); onClicked: menu.openSettings("network") }
        }

        // ── Sound ───────────────────────────────────────────────────────────
        ColumnLayout {
            visible: menu.page === "sound"
            Layout.fillWidth: true
            spacing: Design.s(2)

            MenuHeader { title: I18n.tr("Sound") }
            Slider {
                Layout.fillWidth: true
                Layout.preferredHeight: Design.s(Design.size.ctl)
                value: Audio.volumePercent
                muted: Audio.muted
                icon: Audio.muted ? "\u{f075f}" : "\u{f057e}"
                iconClickable: true
                onIconClicked: Audio.toggleMasterMute()
                onMoved: pct => Audio.setMasterVolume(pct)
            }
            MenuSeparator {}
            MenuCaption { text: I18n.tr("Output") }
            Repeater {
                model: Audio.outputs
                delegate: MenuRow {
                    required property var model
                    glyph: model.is_default ? "\u{f012c}" : ""
                    text: model.description
                    onClicked: Audio.setDefault("sink", model.name)
                }
            }
            MenuSeparator {}
            MenuRow { text: I18n.tr("Sound Settings…"); onClicked: menu.openSettings("audio") }
        }

        // ── Focus ───────────────────────────────────────────────────────────
        ColumnLayout {
            visible: menu.page === "focus"
            Layout.fillWidth: true
            spacing: Design.s(2)
            MenuHeader { title: I18n.tr("Focus") }
            Repeater {
                model: Notifications.modes.filter(m => m.id !== "game")
                delegate: MenuRow {
                    required property var modelData
                    glyph: modelData.glyph
                    lit: Notifications.mode === modelData.id
                    text: modelData.name
                    detail: Notifications.mode === modelData.id && Settings.focusMode === "" ? I18n.tr("Scheduled") : ""
                    onClicked: Notifications.setMode(Settings.focusMode === modelData.id ? "" : modelData.id)
                }
            }
            MenuSeparator {}
            MenuRow { text: I18n.tr("Focus Settings…"); onClicked: menu.openSettings("notifications") }
        }

        // ── Battery ─────────────────────────────────────────────────────────
        ColumnLayout {
            visible: menu.page === "battery"
            Layout.fillWidth: true
            spacing: Design.s(2)

            MenuHeader {
                title: I18n.tr("Battery")
                Label { text: Power.capacity + "%"; weight: Design.weight.semibold; tabular: true }
            }
            MenuCaption {
                text: Power.charging ? I18n.tr("Charging") + (Power.timeRemainingText ? " · " + Power.timeRemainingText : "")
                    : Power.timeRemainingText || Power.status
            }
            MenuSeparator { visible: Power.hasProfiles }
            MenuCaption { visible: Power.hasProfiles; text: I18n.tr("Power Mode") }
            Repeater {
                model: Power.hasProfiles ? [
                    { id: "power-saver", label: I18n.tr("Power Saver"), glyph: "\u{f032a}" },
                    { id: "balanced", label: I18n.tr("Balanced"), glyph: "\u{f05d1}" },
                    { id: "performance", label: I18n.tr("Performance"), glyph: "\u{f04c5}" }
                ] : []
                delegate: MenuRow {
                    required property var modelData
                    glyph: modelData.glyph
                    lit: Power.profile === modelData.id
                    text: modelData.label
                    trailing: Power.profile === modelData.id ? "\u{f012c}" : ""
                    onClicked: Power.setProfile(modelData.id)
                }
            }
            MenuSeparator {}
            MenuRow { text: I18n.tr("Battery Settings…"); onClicked: menu.openSettings("power") }
        }
    }

    function openPanel(cmd) {
        if (typeof masterWindow !== "undefined" && masterWindow.handleIpcCommand) masterWindow.handleIpcCommand(cmd, true);
    }

    // ── Parts ────────────────────────────────────────────────────────────────
    component MenuHeader: RowLayout {
        property string title: ""
        default property alias trailing: tail.data
        Layout.fillWidth: true
        Layout.leftMargin: Design.s(Design.space.sm)
        Layout.rightMargin: Design.s(Design.space.xs)
        Layout.bottomMargin: Design.s(Design.space.xs)
        Label { Layout.fillWidth: true; text: parent.title; weight: Design.weight.semibold }
        RowLayout { id: tail }
    }
    component MenuCaption: Label {
        Layout.fillWidth: true
        Layout.leftMargin: Design.s(Design.space.sm)
        Layout.topMargin: Design.s(2)
        role: "caption"
        weight: Design.weight.semibold
        color: Design.textFaint
        elide: Text.ElideRight
    }
    component MenuSeparator: Rectangle {
        Layout.fillWidth: true
        Layout.leftMargin: Design.s(Design.space.sm)
        Layout.rightMargin: Design.s(Design.space.sm)
        Layout.topMargin: Design.s(Design.space.xs)
        Layout.bottomMargin: Design.s(Design.space.xs)
        Layout.preferredHeight: 1
        color: Design.glassBorder
    }
    component MenuRow: Rectangle {
        id: mrow
        property string glyph: ""
        property string text: ""
        property string detail: ""
        property string trailing: ""
        property bool lit: false
        signal clicked()
        Layout.fillWidth: true
        implicitHeight: Design.s(30)
        radius: Design.s(6)
        color: mrowMa.containsMouse ? Design.accent : "transparent"
        readonly property color ink: mrowMa.containsMouse ? Design.accentText : Design.text
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Design.s(Design.space.sm)
            anchors.rightMargin: Design.s(Design.space.sm)
            spacing: Design.s(Design.space.sm)
            // A disc behind the glyph for what is on, as a menu bar draws it.
            Rectangle {
                visible: mrow.glyph !== ""
                Layout.preferredWidth: Design.s(22)
                Layout.preferredHeight: Design.s(22)
                radius: width / 2
                color: mrow.lit ? Design.accent : Design.tint(Design.text, 0.10)
                Icon {
                    anchors.centerIn: parent
                    text: mrow.glyph
                    role: "body"
                    color: mrow.lit ? Design.accentText : mrow.ink
                }
            }
            Label { Layout.fillWidth: true; text: mrow.text; color: mrow.ink; elide: Text.ElideRight }
            Label { visible: mrow.detail !== ""; text: mrow.detail; role: "caption"; color: mrowMa.containsMouse ? mrow.ink : Design.textDim }
            Icon { visible: mrow.trailing !== ""; text: mrow.trailing; role: "caption"; color: mrowMa.containsMouse ? mrow.ink : Design.textDim }
        }
        MouseArea {
            id: mrowMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: mrow.clicked()
        }
    }
}
