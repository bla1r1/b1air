import QtQuick

// One of icons/, white, at a size.
Image {
    property string name: ""
    property real size: 18

    source: name ? Qt.resolvedUrl("../icons/" + name + ".svg") : ""
    width: size
    height: size
    sourceSize: Qt.size(size * 2, size * 2)
    smooth: true
}
