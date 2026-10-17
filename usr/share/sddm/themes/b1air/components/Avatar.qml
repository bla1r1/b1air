import QtQuick

// The account's picture, round, in a fine white ring — or its initial on
// glass when it has none.
Item {
    id: avatar
    property string source: ""
    property string name: ""
    property real size: 84
    signal clicked

    width: size
    height: size

    Rectangle {   // a soft shadow under it
        anchors.centerIn: parent
        anchors.verticalCenterOffset: 3
        width: parent.width + 12
        height: width
        radius: width / 2
        color: "#1f000000"
    }
    Rectangle {
        anchors.fill: parent
        anchors.margins: -2
        radius: width / 2
        color: "#99ffffff"
    }
    Rectangle {
        anchors.fill: parent
        radius: width / 2
        color: Qt.tint(ThemeColors.ground, "#33ffffff")
        Text {
            anchors.centerIn: parent
            text: avatar.name.length ? avatar.name.charAt(0).toUpperCase() : ""
            color: "white"
            font.family: "Inter"
            font.weight: Font.Bold
            font.pixelSize: avatar.size * 0.42
        }
    }

    // The photo, cut round and cropped to fill it. Drawn on a canvas rather
    // than masked by a shader: a mask comes out empty on some renderers
    // (Mesa's software one among them), and a login screen must not lose
    // the face on a machine whose GPU driver is not there yet.
    Image {
        id: probe   // only to learn the picture's size
        source: avatar.url
        visible: false
    }
    Canvas {
        id: photo
        anchors.fill: parent
        visible: probe.status === Image.Ready
        onVisibleChanged: requestPaint()
        onWidthChanged: requestPaint()
        Component.onCompleted: if (avatar.url) loadImage(avatar.url)
        onImageLoaded: requestPaint()
        onPaint: {
            const c = getContext("2d");
            c.reset();
            if (!visible || !isImageLoaded(avatar.url)) return;
            const iw = probe.implicitWidth, ih = probe.implicitHeight;
            const side = Math.min(iw, ih);
            c.beginPath();
            c.arc(width / 2, height / 2, width / 2, 0, 2 * Math.PI);
            c.closePath();
            c.clip();
            c.drawImage(avatar.url, (iw - side) / 2, (ih - side) / 2, side, side, 0, 0, width, height);
        }
    }
    readonly property string url: source.startsWith("/") ? "file://" + source : source
    onUrlChanged: if (url) photo.loadImage(url); else photo.requestPaint()

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: avatar.clicked()
    }
}
