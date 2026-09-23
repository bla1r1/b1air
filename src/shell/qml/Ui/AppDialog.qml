import QtQuick
import QtQuick.Controls as C

// A modal dialog in the desktop's own colours.
//
// The apps used a bare Controls Dialog, which the Basic style draws white
// with grey slab buttons — the one light rectangle on a dark desktop, and it
// looked like a different program had put it up. This keeps Dialog's API
// (title, standardButtons, accepted/rejected/discarded, contentItem) and only
// draws it. Short confirmations set `message`; anything else sets
// contentItem as before.
C.Dialog {
    id: root

    // Body text for a plain confirmation. Ignored when contentItem is set.
    property string message: ""
    // Tone of the accepting button: Design.danger for "Delete", "Clear".
    property color acceptTone: Design.accent

    modal: true
    focus: true
    anchors.centerIn: C.Overlay.overlay

    // Enter takes the dialog's default answer, as every desktop dialog does;
    // Escape already rejects (Popup closes on it). A Shortcut, because Keys
    // on a Popup — which is not an Item — never sees a key.
    Shortcut {
        sequences: ["Return", "Enter"]
        enabled: root.opened
        onActivated: root.accept()
    }
    padding: Design.s(Design.space.lg)
    topPadding: Design.s(Design.space.sm)

    C.Overlay.modal: Rectangle { color: Qt.rgba(0, 0, 0, 0.45) }

    background: Rectangle {
        color: Design.surface
        radius: Design.s(Design.radius.card)
        border.width: 1
        border.color: Design.line
    }

    header: Label {
        text: root.title
        visible: text.length > 0
        weight: Design.weight.semibold
        padding: Design.s(Design.space.lg)
        bottomPadding: 0
        elide: Text.ElideRight
    }

    // An explicit implicit size on an Item, with the wrapping label inside it:
    // a wrapping label as contentItem sizes from the dialog while the dialog
    // sizes from it, which Qt reports as a binding loop on every open.
    contentItem: Item {
        implicitWidth: Design.s(340)
        implicitHeight: msg.implicitHeight
        Label {
            id: msg
            width: parent.width
            text: root.message
            wrapMode: Text.WordWrap
            dim: true
        }
    }

    footer: C.DialogButtonBox {
        alignment: Qt.AlignRight
        spacing: Design.s(Design.space.sm)
        padding: Design.s(Design.space.lg)
        topPadding: 0
        background: Item {}

        delegate: C.Button {
            id: btn
            readonly property bool accepting: C.DialogButtonBox.buttonRole === C.DialogButtonBox.AcceptRole
                                              || C.DialogButtonBox.buttonRole === C.DialogButtonBox.YesRole
            implicitHeight: Design.s(30)
            implicitWidth: Math.max(Design.s(76), label.implicitWidth + Design.s(28))
            hoverEnabled: true
            contentItem: Text {
                id: label
                // Cancel, OK, Save…: the standard buttons are named by Qt,
                // whose own translations the suite does not ship.
                text: I18n.tr(btn.text)
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                font.family: Design.font.sans
                font.pixelSize: Design.s(Design.font.body)
                font.weight: Design.weight.medium
                color: btn.accepting ? Design.accentText : Design.text
            }
            background: Rectangle {
                radius: Design.s(Design.radius.ctl)
                color: btn.accepting
                       ? (btn.hovered ? Qt.lighter(root.acceptTone, 1.12) : root.acceptTone)
                       : (btn.hovered ? Design.hover : Design.raised)
                border.width: btn.visualFocus ? 2 : 0
                border.color: Design.accent
            }
        }
    }
}
