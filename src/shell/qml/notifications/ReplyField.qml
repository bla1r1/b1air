import QtQuick
import QtQuick.Layouts
import "../Ui"
import "../Services"

// =============================================================================
// A messenger's "reply here" (the notification's inline reply): a line to
// type in and a send button. Shown only where the app offers it; Enter sends.
//
//   ReplyField { item: model; onSent: … }
// =============================================================================
RowLayout {
    id: root

    property var item: null
    readonly property bool focused: field.focused
    signal sent()

    spacing: Design.s(Design.space.xs)

    function send() {
        if (Notifications.reply(root.item, field.text)) {
            field.text = "";
            root.sent();
        }
    }

    Field {
        id: field
        Layout.fillWidth: true
        placeholder: root.item && root.item.obj && root.item.obj.inlineReplyPlaceholder
                     ? root.item.obj.inlineReplyPlaceholder : I18n.tr("Reply…")
        onAccepted: root.send()
    }
    IconButton {
        icon: "\u{f048a}"
        tone: Design.accent
        enabled: field.text.trim() !== ""
        onClicked: root.send()
    }
}
