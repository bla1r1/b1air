import QtQuick

// =============================================================================
// Single-line text field.
//
// 21 bare TextInputs across the popups, each restating family, size, colour and
// its own idea of a focus ring — or having none at all. The wifi password field
// and the lock screen both live on this, so echoMode matters.
//
//   Field {
//       text: model.resW
//       validator: IntValidator { bottom: 320; top: 10000 }
//       onEdited: v => monitorModel.setProperty(index, "resW", parseInt(v || "1920"))
//   }
// =============================================================================

Rectangle {
    id: root

    property alias text: input.text
    property alias validator: input.validator
    property alias echoMode: input.echoMode
    property alias readOnly: input.readOnly
    property alias horizontalAlignment: input.horizontalAlignment
    property string placeholder: ""

    // Fires on every keystroke that passes the validator.
    signal edited(string value)
    // Fires on Enter.
    signal accepted(string value)
    // Fires when the value is settled — Enter, or focus leaving the field.
    // Settings sections were saving on every keystroke, so typing "600" wrote
    // 6, then 60, then 600, and a cleared field wrote the fallback.
    signal committed(string value)

    readonly property alias focused: input.activeFocus

    // For a dialog that opens on this field: the caret in it, text selected.
    function focusInput() {
        input.forceActiveFocus();
        input.selectAll();
    }

    implicitHeight: Design.s(Design.size.field)
    implicitWidth: Design.s(120)

    radius: Design.s(Design.radius.ctl)
    color: Design.sunken
    border.width: Design.border
    border.color: input.activeFocus ? Design.accent : (area.containsMouse ? Design.veilStrong : Design.line)

    Behavior on border.color { ColorAnimation { duration: Design.duration.fast } }

    // Hover tracking only. Declared before the input and with NoButton so it
    // can never swallow a click — a MouseArea stacked over a TextInput makes
    // the caret unplaceable, which is the whole point of a text field.
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        cursorShape: Qt.IBeamCursor
    }

    TextInput {
        id: input
        anchors.fill: parent
        anchors.leftMargin: Design.s(Design.space.md)
        anchors.rightMargin: Design.s(Design.space.md)
        verticalAlignment: TextInput.AlignVCenter
        clip: true

        font.family: Design.font.mono
        font.pixelSize: Design.s(Design.font.body)
        color: Design.text
        selectionColor: Design.accent
        selectedTextColor: Design.accentText

        // A field the pointer can reach but the keyboard cannot is a dead end.
        activeFocusOnPress: true

        onTextEdited: root.edited(text)
        onAccepted: {
            root.accepted(text);
            root.committed(text);
        }
        onActiveFocusChanged: if (!activeFocus) root.committed(text)
    }

    Label {
        anchors.left: input.left
        anchors.verticalCenter: parent.verticalCenter
        text: root.placeholder
        visible: input.text.length === 0 && !input.activeFocus
        color: Design.textFaint
    }
}
