import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import B1air.Daemon
import "Ui"
import "Services"

// The dock, at the bottom of each screen: the pinned apps, then whatever else
// has a window open, a dot under each that is running. Icons grow as the
// pointer passes over them. A click on a running app goes to its window (a
// second click to the next one), on one that is not, starts it.
//
// Off until Settings → Top Bar turns it on: it changes how the desktop is
// used. Auto-hide leaves a strip at the bottom edge that brings it back.
Scope {
    id: root

    // Running windows: {id, appId, focused}, from sway's tree.
    property var windows: []
    function refresh() {
        Sway.query("tree", tree => {
            if (!tree) return;
            const out = [];
            const walk = nodes => {
                for (const n of (nodes || [])) {
                    const appId = n.app_id || (n.window_properties ? n.window_properties.class : "") || "";
                    const kids = (n.nodes || []).concat(n.floating_nodes || []);
                    if (appId && n.pid && n.type !== "workspace") out.push({ id: n.id, appId: appId, focused: !!n.focused });
                    else if (kids.length) walk(kids);
                }
            };
            walk([tree]);
            root.windows = out;
        });
    }
    Component.onCompleted: refresh()
    Connections {
        target: Sway
        function onWindowEvent(e) { coalesce.restart(); }
        function onReconnected() { root.refresh(); }
    }
    Timer { id: coalesce; interval: 150; onTriggered: root.refresh() }

    function sameApp(a, b) {
        a = String(a || "").toLowerCase(); b = String(b || "").toLowerCase();
        return a !== "" && b !== "" && (a === b || a.endsWith("." + b) || b.endsWith("." + a));
    }
    // Pinned first, in their order; then each other app with a window, once.
    readonly property var items: {
        const out = [];
        for (const p of PinnedApps.pinnedList)
            out.push({ appId: p.id, name: p.name, icon: p.icon, cmd: p.cmd, pinned: true,
                       wins: root.windows.filter(w => root.sameApp(w.appId, p.id)) });
        for (const w of root.windows) {
            if (out.some(o => root.sameApp(o.appId, w.appId))) continue;
            out.push({ appId: w.appId, name: w.appId, icon: "", cmd: "", pinned: false,
                       wins: root.windows.filter(x => root.sameApp(x.appId, w.appId)) });
        }
        return out;
    }

    function iconFor(item) {
        const fromEntry = Apps.iconFor(item.appId);
        if (fromEntry !== "") return Apps.iconSource(fromEntry);
        return Apps.iconSource(item.icon || item.appId);
    }

    function activate(item) {
        if (item.wins.length > 0) {
            // Already in front: the next of its windows.
            const at = item.wins.findIndex(w => w.focused);
            const next = item.wins[(at + 1) % item.wins.length];
            Sway.command("[con_id=" + Number(next.id) + "] focus");
            return;
        }
        const cmd = String(item.cmd || "").replace(/%[a-zA-Z]/g, "").trim();
        const forbidden = [";", "&", "|", "`", "$", "<", ">", "\\", "\n", "(", ")", "{", "}"];
        if (!cmd || forbidden.some(c => cmd.includes(c))) return;
        Sway.command("exec " + cmd);
    }

    Variants {
        model: Settings.dockEnabled ? Quickshell.screens : []
        delegate: PanelWindow {
            id: dock
            required property var modelData
            screen: modelData
            color: "transparent"
            WlrLayershell.namespace: "b1air-dock"
            WlrLayershell.layer: WlrLayer.Top
            anchors.bottom: true
            anchors.left: true
            anchors.right: true

            readonly property real base: Design.s(Settings.dockIconSize || 48)
            readonly property real zoom: Settings.dockMagnify !== false ? 1.6 : 1.0
            readonly property real bar: dock.base + Design.s(18)
            // Room above for the icons that grow.
            implicitHeight: dock.bar + dock.base * (dock.zoom - 1) + Design.s(8)
            exclusiveZone: Settings.dockAutohide ? 0 : dock.bar + Design.s(8)
            exclusionMode: Settings.dockAutohide ? ExclusionMode.Ignore : ExclusionMode.Normal

            // Shown unless hiding: when the pointer is near the bottom edge or on it.
            property bool hovered: false
            readonly property bool shown: !Settings.dockAutohide || dock.hovered
            // Input only where the dock is (or the strip at the edge while hidden).
            mask: Region { item: dock.shown ? plate : edge }

            // Where the pointer is, in the window: independent of how wide the
            // dock has grown, so the sizes do not chase their own positions.
            HoverHandler { id: pointer }

            Item {
                id: edge
                anchors.bottom: parent.bottom
                width: parent.width
                height: 2
                HoverHandler { onHoveredChanged: if (hovered) dock.hovered = true }
            }

            Rectangle {
                id: plate
                anchors.horizontalCenter: parent.horizontalCenter
                y: dock.shown ? parent.height - height - Design.s(8) : parent.height + Design.s(4)
                Behavior on y { NumberAnimation { duration: Design.duration.fast + 60; easing.type: Easing.OutCubic } }
                width: row.width + Design.s(16)
                height: dock.bar
                radius: Design.s(18)
                color: Design.glassBg
                border.color: Design.glassBorder
                border.width: 1
                // The lit top edge of the glass.
                Rectangle {
                    visible: Design.translucent
                    anchors.top: parent.top; anchors.topMargin: 1
                    anchors.left: parent.left; anchors.right: parent.right
                    anchors.leftMargin: parent.radius; anchors.rightMargin: parent.radius
                    height: 1
                    color: Design.glassEdge
                }

                HoverHandler {
                    id: hover
                    onHoveredChanged: if (!hovered && Settings.dockAutohide) hideSoon.restart()
                    onPointChanged: hideSoon.stop()
                }
                Timer { id: hideSoon; interval: 600; onTriggered: if (!hover.hovered) dock.hovered = false }

                Row {
                    id: row
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: Design.s(9)
                    spacing: Design.s(6)

                    Repeater {
                        model: root.items
                        delegate: Item {
                            id: cell
                            required property var modelData
                            required property int index
                            // How much it grows: by the pointer's distance from
                            // its centre, over two and a half icons each side.
                            // Measured where the icon would be at rest, in a row of
                            // equal icons centred on the screen.
                            readonly property real restX: {
                                const n = root.items.length, sp = row.spacing;
                                const left = dock.width / 2 - (n * dock.base + (n - 1) * sp) / 2;
                                return left + cell.index * (dock.base + sp) + dock.base / 2;
                            }
                            readonly property real grow: {
                                if (!hover.hovered || dock.zoom <= 1) return 0;
                                const d = Math.abs(pointer.point.position.x - cell.restX) / (dock.base * 2.5);
                                return Math.max(0, 1 - d * d);
                            }
                            width: dock.base * (1 + (dock.zoom - 1) * cell.grow)
                            height: width
                            Behavior on width { enabled: !hover.hovered; NumberAnimation { duration: Design.duration.fast } }

                            IconImage {
                                anchors.fill: parent
                                source: root.iconFor(cell.modelData)
                                mipmap: true
                            }
                            // Running.
                            Rectangle {
                                visible: cell.modelData.wins.length > 0
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.top: parent.bottom
                                anchors.topMargin: Design.s(2)
                                width: Design.s(4); height: width; radius: width / 2
                                color: Design.text
                                opacity: 0.8
                            }
                            // Its name above it while pointed at.
                            Rectangle {
                                visible: tipArea.containsMouse
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.top
                                anchors.bottomMargin: Design.s(8)
                                width: tipText.implicitWidth + Design.s(16)
                                height: tipText.implicitHeight + Design.s(8)
                                radius: height / 2
                                color: Design.glassBg
                                border.color: Design.glassBorder
                                border.width: 1
                                Label { id: tipText; anchors.centerIn: parent; text: cell.modelData.name; role: "caption" }
                            }
                            MouseArea {
                                id: tipArea
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                cursorShape: Qt.PointingHandCursor
                                onClicked: mouse => {
                                    if (mouse.button === Qt.RightButton) {
                                        // Keep in the dock, or let go of it.
                                        PinnedApps.togglePin({ name: cell.modelData.name, desktopFile: cell.modelData.appId,
                                                               icon: cell.modelData.icon || cell.modelData.appId,
                                                               cmd: cell.modelData.cmd || cell.modelData.appId });
                                    } else {
                                        root.activate(cell.modelData);
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
