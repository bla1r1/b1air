import QtQuick
import QtQuick.Controls

// Several lines of text to type into, bare, as TextLine is one: the inside
// of a description box or an editor that draws its own frame.
TextArea {
    color: Design.text
    selectionColor: Design.stateSelectedStrong
    selectedTextColor: Design.text
    placeholderTextColor: Design.textFaint
    font.family: Design.font.sans
    font.pixelSize: Design.s(Design.font.body)
    background: null
}
