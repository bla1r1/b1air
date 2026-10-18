import QtQuick

// The Air material on the wallpaper: white at a low opacity, a hairline of
// white round it. `level` is how much white: 0.16 at rest, more on hover.
Rectangle {
    property real level: 0.16
    property real rim: 0.28
    property color tint: "white"

    color: Qt.rgba(tint.r, tint.g, tint.b, level)
    border.width: 1
    border.color: Qt.rgba(tint.r, tint.g, tint.b, rim)
    Behavior on color { ColorAnimation { duration: 120 } }
}
