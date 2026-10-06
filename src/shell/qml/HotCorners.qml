import QtQuick
import Quickshell
import Quickshell.Wayland
import B1air.Daemon
import "Ui"
import "Services"

// Hot corners: the pointer pushed into a corner of a screen and held there a
// moment does what Settings → Mouse & Touchpad says for that corner — the
// workspace overview, the Launchpad, the notifications, the Control Center,
// or locking the screen. A two-pixel surface in each corner that is set,
// above everything, and nothing where the corner does nothing.
Scope {
    id: root
    // Asks the shell's own window to open something (Main.qml).
    signal requestCommand(string cmd)

    readonly property var corners: [
        { key: "hotCornerTopLeft",     top: true,  left: true },
        { key: "hotCornerTopRight",    top: true,  left: false },
        { key: "hotCornerBottomLeft",  top: false, left: true },
        { key: "hotCornerBottomRight", top: false, left: false }
    ]

    function run(action) {
        switch (action) {
        case "overview": Sway.command("overview toggle"); break;
        case "launchpad": root.requestCommand("toggle:launchpad:"); break;
        case "notifications": root.requestCommand("toggle:notifications:"); break;
        case "control": root.requestCommand("toggle:control:"); break;
        case "lock": Daemon.lock(); break;
        }
    }

    Variants {
        model: Quickshell.screens
        delegate: Scope {
            id: perScreen
            required property var modelData
            // Variants, not a Repeater: a Repeater makes nothing outside an Item.
            Variants {
                model: root.corners
                delegate: Scope {
                    id: corner
                    required property var modelData
                    readonly property string action: Settings[corner.modelData.key] || "none"
                    LazyLoader {
                        active: corner.action !== "none"
                        PanelWindow {
                            screen: perScreen.modelData
                            color: "transparent"
                            WlrLayershell.namespace: "b1air-hotcorner"
                            WlrLayershell.layer: WlrLayer.Overlay
                            exclusionMode: ExclusionMode.Ignore
                            anchors.top: corner.modelData.top
                            anchors.bottom: !corner.modelData.top
                            anchors.left: corner.modelData.left
                            anchors.right: !corner.modelData.left
                            implicitWidth: 2
                            implicitHeight: 2

                            MouseArea {
                                anchors.fill: parent
                                hoverEnabled: true
                                // Held a moment, so passing through the corner on
                                // the way somewhere does nothing.
                                onEntered: if (!cooldown.running) dwell.restart()
                                onExited: dwell.stop()
                            }
                            Timer {
                                id: dwell
                                interval: 180
                                onTriggered: { root.run(corner.action); cooldown.restart(); }
                            }
                            // And not again at once while the pointer stays there.
                            Timer { id: cooldown; interval: 1200 }
                        }
                    }
                }
            }
        }
    }
}
