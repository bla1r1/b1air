import QtQuick
import QtQuick.Layouts

// =============================================================================
// Centred icon + line + hint, for a list with nothing in it.
//
// The mini-views filled their empty lists with invented devices — "AirPods Pro",
// "FRITZ!Box 5690 TF" — which look real, click like nothing, and are the worst
// possible answer to "what is connected?". This says so instead.
//
//   EmptyState { icon: "\u{f092e}"; title: "Wi-Fi is off"; hint: "Turn it on…" }
// =============================================================================

ColumnLayout {
    id: root

    property string icon: ""
    property string title: ""
    property string hint: ""

    spacing: Design.s(Design.space.xs)

    // Full width by default, so the centred content is centred in whatever
    // holds it. Inside a Card (Settings → Sound: "Nothing is playing", "No
    // output devices") it sat against the card's left edge, as wide as its
    // hint: a layout's maximum width is its children's, and a child without
    // fillWidth maxes out at its preferred width — so with no stretching child
    // here, neither this nor a card holding only this could grow. The title
    // row stretches now (its text stays centred).
    Layout.fillWidth: true
    Layout.topMargin: Design.s(Design.space.sm)
    Layout.bottomMargin: Design.s(Design.space.sm)

    Icon {
        Layout.alignment: Qt.AlignHCenter
        Layout.bottomMargin: Design.s(Design.space.xs)
        visible: root.icon !== ""
        text: root.icon
        role: "display"
        color: Design.textFaint
    }

    Label {
        Layout.fillWidth: true
        text: root.title
        role: "body"
        weight: Design.weight.semibold
        color: Design.textDim
        horizontalAlignment: Text.AlignHCenter
    }

    Label {
        Layout.alignment: Qt.AlignHCenter
        Layout.maximumWidth: Design.s(320)
        visible: root.hint !== ""
        text: root.hint
        role: "caption"
        color: Design.textFaint
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
    }
}
