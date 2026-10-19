import QtQuick
import QtQuick.Layouts

// =============================================================================
// InlineStatus component for loading, error, empty, and success feedback.
//
// Usage:
//   InlineStatus {
//       status: "error"
//       message: "Failed to connect to network"
//       onRetry: network.reconnect()
//   }
// =============================================================================

RowLayout {
    id: root

    property string status: "loading" // "loading" | "error" | "empty" | "ok" | "warning"
    property string message: ""
    property alias text: root.message
    property string retryText: "Retry"
    property bool showRetry: status === "error"

    signal retry()

    spacing: Design.s(Design.space.sm)
    Layout.fillWidth: true

    // Spinner for loading status
    Item {
        visible: root.status === "loading"
        implicitWidth: Design.s(Design.size.micro)
        implicitHeight: Design.s(Design.size.micro)
        Layout.alignment: Qt.AlignVCenter

        Text {
            anchors.centerIn: parent
            text: "\u{f0357}" // nerd font spinner / circle notch
            font.family: Design.font.icon
            font.pixelSize: Design.s(Design.font.glyphSm)
            color: Design.accent
            transformOrigin: Item.Center

            RotationAnimation on rotation {
                from: 0
                to: 360
                duration: Design.duration.spin
                loops: Animation.Infinite
                running: root.status === "loading" && root.visible
            }
        }
    }

    // Static icon for error, empty, ok
    Icon {
        visible: root.status !== "loading"
        text: {
            switch (root.status) {
            case "error":   return "\u{f0028}"; // circle-exclamation
            case "warning": return "\u{f0028}"; // warning
            case "ok":      return "\u{f012c}"; // check-circle
            case "empty":   return "\u{f01c8}"; // folder-open / info
            default:        return "\u{f02fd}"; // info-circle
            }
        }
        role: "body"
        color: {
            switch (root.status) {
            case "error":   return Design.danger;
            case "warning": return Design.warn;
            case "ok":      return Design.ok;
            default:        return Design.textDim;
            }
        }
        Layout.alignment: Qt.AlignVCenter
    }

    Label {
        text: root.message
        role: "footnote"
        color: root.status === "error" ? Design.danger : Design.textDim
        Layout.fillWidth: true
        elide: Text.ElideRight
        Layout.alignment: Qt.AlignVCenter
    }

    Button {
        visible: root.showRetry
        size: "sm"
        text: root.retryText
        variant: "ghost"
        onClicked: root.retry()
        Layout.alignment: Qt.AlignVCenter
    }
}
