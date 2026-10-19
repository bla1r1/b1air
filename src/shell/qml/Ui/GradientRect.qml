import QtQuick

// =============================================================================
// A rounded rectangle filled with a gradient, its edge smooth in either
// renderer.
//
// Qt's software renderer — every app window here (QT_QUICK_BACKEND=software)
// — draws a Rectangle that has both a gradient and a radius with hard,
// stair-stepped edges: the avatar circles and a slider's ends came out
// jagged. A plain colour it smooths, and so it does a Canvas path, which is
// what this is.
//
//   GradientRect { anchors.fill: parent; radius: width / 2; from: "#ff9a5a"; to: "#e8573f" }
// =============================================================================

Canvas {
    id: root

    property real radius: 0
    property color from: "white"
    property color to: "black"
    // Left to right; top to bottom when false.
    property bool horizontal: false

    onRadiusChanged: requestPaint()
    onFromChanged: requestPaint()
    onToChanged: requestPaint()
    onHorizontalChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    onPaint: {
        const c = getContext("2d");
        c.reset();
        if (width <= 0 || height <= 0) return;
        const r = Math.min(root.radius, width / 2, height / 2);
        const g = root.horizontal ? c.createLinearGradient(0, 0, width, 0)
                                  : c.createLinearGradient(0, 0, 0, height);
        g.addColorStop(0, root.from);
        g.addColorStop(1, root.to);
        c.fillStyle = g;
        c.beginPath();
        c.roundedRect(0, 0, width, height, r, r);
        c.fill();
    }
}
