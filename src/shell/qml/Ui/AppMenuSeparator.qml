import QtQuick
import QtQuick.Controls as C

C.MenuSeparator {
    topPadding: Design.s(Design.space.xs)
    bottomPadding: Design.s(Design.space.xs)
    contentItem: Rectangle { implicitHeight: 1; color: Design.line }
}
