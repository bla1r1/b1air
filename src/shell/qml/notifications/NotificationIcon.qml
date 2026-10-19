import QtQuick
import QtQuick.Effects
import "../Ui"

// =============================================================================
// Who a notification is from, as a picture: the sender's (the image a
// messenger sends with it), round, with the app's icon as a badge on its
// corner — or the app's icon alone. A picture that is not a face (a
// screenshot, a cover: wide, or large) is not squeezed in here: `isPicture`
// says so, and the card shows it as a picture under the text.
//
//   NotificationIcon { image: item.image; appIcon: item.appIcon; size: … }
// =============================================================================
Item {
    id: root

    property string image: ""
    property string appIcon: ""
    property real size: Design.s(Design.size.art)
    property bool critical: false

    // Wide, or bigger than any avatar is sent: a picture, not a face.
    readonly property bool isPicture: probe.status === Image.Ready
        && (probe.implicitWidth > probe.implicitHeight * 1.25 || probe.implicitWidth > 512)
    readonly property bool hasAvatar: root.image !== "" && probe.status === Image.Ready && !root.isPicture

    implicitWidth: root.size
    implicitHeight: root.size

    // Only to learn the picture's shape.
    Picture {
        id: probe
        visible: false
        source: root.image
        sourceSize: Qt.size(1024, 1024)
        asynchronous: true
    }

    // ── The sender, round ────────────────────────────────────────────────────
    Picture {
        id: face
        anchors.fill: parent
        visible: false
        source: root.hasAvatar ? root.image : ""
        sourceSize: Qt.size(128, 128)
        fillMode: Image.PreserveAspectCrop
        layer.enabled: true
    }
    Box {
        id: round
        anchors.fill: parent
        radius: width / 2
        visible: false
        layer.enabled: true
    }
    // Rounded by a shader; where Qt draws without one (the software
    // renderer, in a VM with no GPU), square.
    readonly property bool shaders: root.GraphicsInfo.api !== GraphicsInfo.Software
    Effect {
        anchors.fill: parent
        visible: root.hasAvatar && root.shaders
        source: face
        maskEnabled: true
        maskSource: round
    }
    Picture {
        anchors.fill: parent
        visible: root.hasAvatar && !root.shaders
        source: visible ? root.image : ""
        sourceSize: Qt.size(128, 128)
        fillMode: Image.PreserveAspectCrop
    }

    // ── Or the app ───────────────────────────────────────────────────────────
    Box {
        anchors.fill: parent
        visible: !root.hasAvatar
        radius: Design.s(Design.radius.card)
        color: root.critical ? Design.warn : (appImage.status === Image.Ready ? "transparent" : Design.glassTile)

        Picture {
            id: appImage
            anchors.fill: parent
            anchors.margins: root.critical ? root.size * 0.2 : 0
            source: root.appIcon
            sourceSize: Qt.size(128, 128)
            fillMode: Image.PreserveAspectFit
            mipmap: true
            visible: status === Image.Ready
        }
        Icon {
            anchors.centerIn: parent
            visible: appImage.status !== Image.Ready
            text: root.critical ? "\u{f0026}" : "\u{f009a}"
            role: root.size >= Design.s(Design.size.art) ? "title" : "body"
            color: root.critical ? "white" : Design.textDim
        }
    }

    // ── The app, as a badge on the sender ────────────────────────────────────
    Surface {
        kind: "glass"
        border.width: 0
        visible: root.hasAvatar && root.appIcon !== ""
        width: root.size * 0.42
        height: width
        radius: width / 4
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: -width * 0.12
        anchors.bottomMargin: -width * 0.12
        Picture {
            anchors.fill: parent
            anchors.margins: Design.border
            source: root.hasAvatar ? root.appIcon : ""
            sourceSize: Qt.size(64, 64)
            fillMode: Image.PreserveAspectFit
            mipmap: true
        }
    }
}
