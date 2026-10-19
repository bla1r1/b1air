import QtQuick

// One line of text to type into, bare: the inside of a field that draws its
// own frame. In the desktop's type, colour and selection unless told
// otherwise. A field with its frame is Ui/Field.
TextInput {
    color: Design.text
    selectionColor: Design.stateSelectedStrong
    selectedTextColor: Design.text
    font.family: Design.font.sans
    font.pixelSize: Design.s(Design.font.body)
    clip: true
}
