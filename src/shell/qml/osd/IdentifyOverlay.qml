import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import B1air.Daemon
import "../Ui"
import "../Services"

// =============================================================================
// Identify displays
//
// Settings → Displays → Identify: every screen shows, for a few seconds, the
// number it has on the layout canvas there, big in its middle, with its name
// and mode under it. It used to be one notification listing them all, which
// says nothing about which physical screen is which.
//
// The numbers are the order sway reports the outputs in, which is the order
// Settings numbers them in. Asked for with `b1air-shell open identify`, so
// the standalone Settings app (another process) can ask for it too.
// =============================================================================

Scope {
    id: root

    property bool shown: false
    // name -> {number, mode}
    property var labels: ({})

    function show() {
        Sway.query("outputs", outs => {
            if (!Array.isArray(outs)) return;
            const map = {};
            let n = 0;
            for (const o of outs) {
                // Counted even when off, as Settings counts it.
                n++;
                if (o.active === false) continue;
                const m = o.current_mode || {};
                const hz = Math.round((m.refresh || 0) / 1000);
                map[o.name] = {
                    number: n,
                    mode: (m.width && m.height)
                        ? m.width + "×" + m.height + (hz > 0 ? " · " + hz + " Hz" : "")
                        : ""
                };
            }
            root.labels = map;
            root.shown = true;
            hideTimer.restart();
        });
    }

    Timer {
        id: hideTimer
        interval: 3000
        onTriggered: root.shown = false
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: card
            required property var modelData
            readonly property var label: root.labels[modelData.name] || null

            screen: modelData
            visible: root.shown && label !== null
            color: "transparent"
            WlrLayershell.namespace: "qs-identify"
            WlrLayershell.layer: WlrLayer.Overlay
            exclusionMode: ExclusionMode.Ignore
            focusable: false

            implicitWidth: box.implicitWidth
            implicitHeight: box.implicitHeight

            Rectangle {
                id: box
                implicitWidth: Math.max(Design.s(220), column.implicitWidth + Design.s(64))
                implicitHeight: column.implicitHeight + Design.s(48)
                radius: Design.s(28)
                color: Design.ground
                border.color: Design.glassBorder
                border.width: 1

                ColumnLayout {
                    id: column
                    anchors.centerIn: parent
                    spacing: Design.s(2)

                    Text {
                        Layout.alignment: Qt.AlignHCenter
                        text: card.label ? card.label.number : ""
                        font.family: Design.font.mono
                        font.weight: Font.Bold
                        font.pixelSize: Design.s(120)
                        color: Screens.primaryName === card.modelData.name ? Design.accent : Design.text
                    }
                    Label {
                        Layout.alignment: Qt.AlignHCenter
                        text: card.modelData.name
                            + (Screens.primaryName === card.modelData.name && Quickshell.screens.length > 1
                               ? "  ·  " + I18n.tr("Main display") : "")
                        role: "subhead"
                        weight: Design.weight.semibold
                    }
                    Label {
                        Layout.alignment: Qt.AlignHCenter
                        visible: text !== ""
                        text: card.label ? card.label.mode : ""
                        role: "caption"; dim: true
                    }
                }
            }
        }
    }
}
