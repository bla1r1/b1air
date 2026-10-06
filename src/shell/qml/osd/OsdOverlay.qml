import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import "../Ui"
import "../Services"

// =============================================================================
// On-Screen Display (OSD) Overlay
//
// Shows volume, microphone, and screen brightness changes with smooth animations,
// and the status lines of Services/Osd.qml (a mode turned on, something
// copied): a title and a detail, with a level bar only when they carry one.
// =============================================================================

PanelWindow {
    id: osdWindow
    color: "transparent"

    WlrLayershell.namespace: "qs-osd"
    WlrLayershell.layer: WlrLayer.Overlay
    
    exclusionMode: ExclusionMode.Ignore
    focusable: false
    
    // Follows the focused output. Refreshed when the OSD is about to appear
    // rather than on a timer: a volume key is the only thing that opens it.
    screen: Screens.focused

    anchors.top: false
    anchors.right: false
    anchors.bottom: true
    anchors.left: false

    implicitWidth: osdCard.implicitWidth + Design.s(32)
    implicitHeight: osdCard.implicitHeight + Design.s(90)

    visible: osdOpacity > 0.0
    onVisibleChanged: if (visible) Screens.refresh()

    property real osdOpacity: 0.0
    property string osdIcon: "\u{f057e}"
    // English, as the code names it; translated where it is drawn, so the
    // daemon's status lines (sent in English) are translated too.
    property string osdTitle: "Volume"
    property int osdValue: 0
    property bool osdMuted: false
    property color osdColor: Design.sapphire
    property string osdDetail: ""       // a status line's second line
    property bool osdHasLevel: true     // false: a status line without a bar

    // Flag to ignore initial bindings on startup
    property bool _ready: false

    Timer {
        id: hideTimer
        interval: 1800
        repeat: false
        onTriggered: {
            osdWindow.osdOpacity = 0.0;
        }
    }

    function showOsd(icon, title, value, muted, color) {
        if (!osdWindow._ready) return;
        // "Volume notifications" in Sound settings. It wrote
        // `audioNotifications` and nothing read it, so the on-screen display
        // appeared on every volume and microphone change however it was set.
        // Brightness is not what the setting is about and is left alone.
        if (Settings.audioNotifications === false
                && (title === "Volume" || title === "Muted"
                    || title === "Microphone" || title === "Mic Muted"))
            return;
        osdWindow.osdIcon = icon;
        osdWindow.osdTitle = title;
        osdWindow.osdValue = Math.max(0, Math.min(100, Math.round(value)));
        osdWindow.osdMuted = muted;
        osdWindow.osdColor = color || Design.sapphire;
        osdWindow.osdDetail = "";
        osdWindow.osdHasLevel = true;
        osdWindow.osdOpacity = 1.0;
        hideTimer.interval = 1800;
        hideTimer.restart();
    }

    Connections {
        target: Osd
        function onShown(glyph, title, detail, tone, value) {
            osdWindow.osdIcon = glyph;
            osdWindow.osdTitle = title;
            osdWindow.osdDetail = detail;
            osdWindow.osdHasLevel = value >= 0;
            osdWindow.osdValue = Math.max(0, Math.min(100, value));
            osdWindow.osdMuted = false;
            osdWindow.osdColor = tone;
            osdWindow.osdOpacity = 1.0;
            // A line to read stays a little longer than a level to glance at.
            hideTimer.interval = detail !== "" ? 2600 : 1800;
            hideTimer.restart();
        }
    }

    // ── Track Volume Changes ─────────────────────────────────────────────────
    readonly property var currentSink: Pipewire.defaultAudioSink
    readonly property real currentVol: currentSink && currentSink.audio ? currentSink.audio.volume : 0
    readonly property bool currentMute: currentSink && currentSink.audio ? currentSink.audio.muted : false

    onCurrentVolChanged: {
        if (!osdWindow._ready) return;
        let v = Math.round(currentVol * 100);
        let ic = "\u{f057e}";
        if (currentMute || v === 0) ic = "\u{f0581}";
        else if (v < 35) ic = "\u{f057f}";
        else if (v < 70) ic = "\u{f0580}";
        showOsd(ic, "Volume", v, currentMute, currentMute ? Design.red : Design.sapphire);
    }

    onCurrentMuteChanged: {
        if (!osdWindow._ready) return;
        let v = Math.round(currentVol * 100);
        let ic = currentMute ? "\u{f0581}" : "\u{f057e}";
        showOsd(ic, currentMute ? "Muted" : "Volume", v, currentMute, currentMute ? Design.red : Design.sapphire);
    }

    // ── Track Microphone Changes ─────────────────────────────────────────────
    readonly property var currentSource: Pipewire.defaultAudioSource
    readonly property real currentMicVol: currentSource && currentSource.audio ? currentSource.audio.volume : 0
    readonly property bool currentMicMute: currentSource && currentSource.audio ? currentSource.audio.muted : false

    onCurrentMicVolChanged: {
        if (!osdWindow._ready) return;
        let v = Math.round(currentMicVol * 100);
        let ic = currentMicMute ? "\u{f036d}" : "\u{f036c}";
        showOsd(ic, "Microphone", v, currentMicMute, currentMicMute ? Design.red : Design.peach);
    }

    onCurrentMicMuteChanged: {
        if (!osdWindow._ready) return;
        let v = Math.round(currentMicVol * 100);
        let ic = currentMicMute ? "\u{f036d}" : "\u{f036c}";
        showOsd(ic, currentMicMute ? "Mic Muted" : "Microphone", v, currentMicMute, currentMicMute ? Design.red : Design.peach);
    }

    // ── Track Brightness Changes ─────────────────────────────────────────────
    readonly property int currentBrightness: Power.brightness

    onCurrentBrightnessChanged: {
        if (!osdWindow._ready || !Power.hasBacklight) return;
        showOsd("\u{f00df}", "Brightness", currentBrightness, false, Design.yellow);
    }

    Timer {
        interval: 1000
        repeat: false
        running: true
        onTriggered: {
            osdWindow._ready = true;
        }
    }

    // ── OSD Card UI ──────────────────────────────────────────────────────────
    Rectangle {
        id: osdCard
        opacity: osdWindow.osdOpacity
        scale: osdWindow.osdOpacity > 0 ? 1.0 : 0.92

        Behavior on opacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }

        implicitWidth: osdWindow.osdHasLevel ? Design.s(260)
            : Math.min(Design.s(440), Math.max(Design.s(260), statusText.implicitWidth + Design.s(84)))
        implicitHeight: Design.s(60)

        radius: Design.s(30)
        color: Design.ground
        border.color: Design.glassBorder
        border.width: 1

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: Design.s(16)
            anchors.rightMargin: Design.s(18)
            spacing: Design.s(12)

            // Icon circle
            Rectangle {
                Layout.preferredWidth: Design.s(36)
                Layout.preferredHeight: Design.s(36)
                radius: Design.s(18)
                color: Design.glassCard

                Icon {
                    anchors.centerIn: parent
                    text: osdWindow.osdIcon
                    color: osdWindow.osdColor
                    role: "body"
                }
            }

            // Label & Bar Column
            ColumnLayout {
                Layout.fillWidth: true
                spacing: Design.s(4)

                // A status line: title, and the detail under it.
                ColumnLayout {
                    id: statusText
                    visible: !osdWindow.osdHasLevel
                    Layout.fillWidth: true
                    spacing: 0
                    Label {
                        Layout.fillWidth: true
                        text: I18n.tr(osdWindow.osdTitle)
                        weight: Design.weight.semibold
                        role: "caption"
                        elide: Text.ElideRight
                    }
                    Label {
                        Layout.fillWidth: true
                        visible: osdWindow.osdDetail !== ""
                        text: I18n.tr(osdWindow.osdDetail)
                        role: "caption"; dim: true
                        elide: Text.ElideMiddle
                    }
                }

                RowLayout {
                    visible: osdWindow.osdHasLevel
                    Layout.fillWidth: true
                    Label {
                        text: I18n.tr(osdWindow.osdTitle)
                        weight: Design.weight.semibold
                        role: "caption"
                        Layout.fillWidth: true
                    }
                    Label {
                        text: osdWindow.osdMuted ? I18n.tr("MUTED") : (osdWindow.osdValue + "%")
                        weight: Design.weight.bold
                        role: "caption"
                        color: osdWindow.osdMuted ? Design.red : Design.text
                    }
                }

                // Progress Level Bar
                Rectangle {
                    visible: osdWindow.osdHasLevel
                    Layout.fillWidth: true
                    Layout.preferredHeight: Design.s(6)
                    radius: Design.s(3)
                    color: Design.well

                    Rectangle {
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: osdWindow.osdMuted ? 0 : (parent.width * (osdWindow.osdValue / 100.0))
                        radius: Design.s(3)
                        color: osdWindow.osdColor

                        Behavior on width {
                            NumberAnimation { duration: 80; easing.type: Easing.OutQuad }
                        }
                    }
                }
            }
        }
    }
}
