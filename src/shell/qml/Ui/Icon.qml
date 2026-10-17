import QtQuick

// =============================================================================
// A nerd-font glyph, on the same size scale as Label.
//
// Separate from Label only because the family differs — but that difference is
// exactly what kept breaking: 120 call sites asked for "Iosevka Nerd Font",
// which the installer never ships. One token, one place to be wrong.
//
//   Icon { text: "󰕾"; role: "subhead"; color: Design.accent }
// =============================================================================

Text {
    id: root

    property string role: "subhead"

    readonly property int _size: {
        switch (root.role) {
        case "caption": return Design.font.caption;
        case "body":    return Design.font.body;
        case "title":   return Design.font.title;
        case "display": return Design.font.display;
        case "subhead": return Design.font.subhead;
        default:
            // SessionMenu asked for "hero", which never existed: its icons
            // came out at subhead size and nothing said so.
            console.warn("Icon: unknown role \"" + root.role + "\", drawn as subhead");
            return Design.font.subhead;
        }
    }

    // `weight` was used at 9 call sites and never declared here — Text has no
    // such property, so every one of them would have failed. Caught by qmllint,
    // not by reading.
    property int weight: Design.weight.regular

    font.weight: root.weight
    font.family: Design.font.icon
    font.pixelSize: Design.s(root._size)
    color: Design.text
    horizontalAlignment: Text.AlignHCenter
}
