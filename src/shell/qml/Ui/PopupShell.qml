import QtQuick
import QtQuick.Window
import Quickshell
import "../Services"

// =============================================================================
// The frame every popup repeats by hand.
//
// Absorbs the boilerplate that opens all eleven popup files today: the Scaler
// instance, the MatugenColors instance and its colour re-exports, the scriptDir
// / mainQmlPath dance, the execDetached close call, the Escape handler, and the
// outer rounded Rectangle.
//
//   PopupShell {
//       ColumnLayout { anchors.fill: parent; spacing: Design.s(Design.space.xl) }
//   }
// =============================================================================

Item {
    id: root
    focus: true

    // Children land inside the padded frame, not on top of the border.
    default property alias content: body.data

    // A page inside the Control Center has no chrome of its own — the Center
    // owns the window. Lets the four popups be reused as pages unchanged.
    property bool framed: true
    property real globalScale: 1.0
    property string activeMode: ""
    property string page: ""
    property var notifModel: null

    property int padding: Design.space.xl
    property color background: Design.glassBg
    property color borderColor: Design.glassBorder
    property int cornerRadius: Design.radius.panel

    readonly property string configDir: Quickshell.env("QS_CONFIG_DIR")
        || (Quickshell.env("HOME") + "/.config/quickshell")

    // NOT Screen.devicePixelRatio — Qt Quick already renders this surface at
    // the compositor's real output scale on its own; binding uiScale to it
    // too doubled the effect, rendering everything roughly scale² as big.
    // See Main.qml's copy of this binding for the full explanation.
    Binding { target: Design; property: "uiScale"; value: 1.0 }

    // Every popup rebuilt this call with its own path juggling.
    function close() {
        if (typeof masterWindow !== "undefined" && masterWindow.handleIpcCommand) {
            masterWindow.handleIpcCommand("close", true);
        } else {
            Quickshell.execDetached(["b1air-shell", "close"]);
        }
    }

    // A shell with pages needs Escape to mean "back" before it means "close".
    // Return true from the hook to swallow the key.
    property var escapeHook: null

    Keys.onEscapePressed: event => {
        event.accepted = true;
        if (root.escapeHook && root.escapeHook())
            return;
        root.close();
    }

    Rectangle {
        anchors.fill: parent
        radius: root.framed ? Design.s(root.cornerRadius) : 0
        color: root.framed ? root.background : "transparent"
        border.color: root.framed ? root.borderColor : "transparent"
        border.width: root.framed ? Design.border : 0
        clip: true

        // The lit top edge of the glass.
        Rectangle {
            visible: root.framed && Design.translucent
            anchors.top: parent.top
            anchors.topMargin: Design.border
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: parent.radius
            anchors.rightMargin: parent.radius
            height: 1
            color: Design.glassEdge
        }

        Item {
            id: body
            anchors.fill: parent
            anchors.margins: root.framed ? Design.s(root.padding) : 0
        }
    }
}
