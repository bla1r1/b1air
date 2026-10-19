import QtQuick

// =============================================================================
// A picture cut round (or to a rounded rectangle), cropped to fill, its edge
// smooth in either renderer.
//
// `clip: true` on a round Rectangle does not do it: Qt clips to the item's
// box, whatever its radius, and the avatars came out square. A shader mask
// is not drawn at all by the software renderer the apps use. A Canvas path,
// clipped, is smooth in both.
//
// The Canvas loads the picture itself (it draws no Image item that is not
// shown); the hidden Image is only asked its proportions, at a small size.
// Meant for pictures the size of an avatar.
//
//   RoundImage { anchors.fill: parent; source: Paths.fileUrl(path) }
// =============================================================================

Item {
    id: root

    property url source: ""
    property real radius: Math.min(width, height) / 2
    property bool cache: true
    readonly property int status: probe.status

    Image {
        id: probe
        visible: false
        source: root.source
        sourceSize: Qt.size(64, 64)
        cache: root.cache
        asynchronous: true
        onStatusChanged: canvas.requestPaint()
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        readonly property string url: String(root.source)
        onUrlChanged: if (url !== "") loadImage(url); else requestPaint()
        Component.onCompleted: if (url !== "") loadImage(url)
        onImageLoaded: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()
        onPaint: {
            const c = getContext("2d");
            c.reset();
            if (url === "" || !isImageLoaded(url) || probe.status !== Image.Ready) return;
            const iw = probe.implicitWidth, ih = probe.implicitHeight;
            if (iw <= 0 || ih <= 0 || width <= 0 || height <= 0) return;
            // Covering the box at the picture's proportions, centred; the
            // path cuts off what is outside it.
            const scale = Math.max(width / iw, height / ih);
            const dw = iw * scale, dh = ih * scale;
            const r = Math.min(root.radius, width / 2, height / 2);
            c.beginPath();
            c.roundedRect(0, 0, width, height, r, r);
            c.clip();
            c.drawImage(url, (width - dw) / 2, (height - dh) / 2, dw, dh);
        }
    }
    onRadiusChanged: canvas.requestPaint()
}
