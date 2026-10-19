import QtQuick

// =============================================================================
// Text on the type scale.
//
// The single biggest duplication in the shell: 374 of 419 Text blocks repeat
// the same family + pixelSize + colour triplet by hand. Four lines each.
//
//   Label { text: "Microphone" }                      // mono, body, text
//   Label { text: "82%"; role: "caption"; dim: true }
//   Label { text: "Displays"; role: "title"; weight: Design.weight.semibold }
//
// Extends Text, so wrapMode / elide / Layout.* all still work.
// =============================================================================

Text {
    id: root

    // caption | body | subhead | title | display
    property string role: "body"

    // Shortcut for the most common colour choice after `text` itself.
    property bool dim: false

    readonly property int _size: {
        switch (root.role) {
        case "caption":  return Design.font.caption;
        case "footnote": return Design.font.footnote;
        case "subhead":  return Design.font.subhead;
        case "title":    return Design.font.title;
        case "display":  return Design.font.display;
        case "body":     return Design.font.body;
        default:
            // An unknown role used to fall through to body without a word.
            console.warn("Label: unknown role \"" + root.role + "\", drawn as body");
            return Design.font.body;
        }
    }

    // isMono: false uses Inter for clean, modern UI; true uses JetBrainsMono Nerd Font for numbers/stats/code
    property bool isMono: false
    // Off the scale, where the text is not a text style: the bar's own
    // font, a colour emoji, a size computed from what it sits in. `size`
    // is in pixels, scaled already; `family` a font family. Either one
    // drops Inter's tracking, which is only right for Inter on the scale.
    property real size: 0
    property string family: ""
    readonly property bool _onScale: root.size <= 0 && root.family === ""

    property int weight: Design.weight.regular
    // Figures of one width, for numbers that change in place — a clock, a
    // percentage, a counter — so the text beside them does not shuffle.
    property bool tabular: false

    font.weight: root.weight
    font.features: root.tabular ? Design.tabular : ({})
    font.family: root.family !== "" ? root.family : root.isMono ? Design.font.mono : Design.font.sans
    font.pixelSize: root.size > 0 ? root.size : Design.s(root._size)
    // Inter's tracking for the size; none for the mono face.
    // From the size, not from font.pixelSize: that is the same font group,
    // and Qt took reading it here for a binding loop.
    font.letterSpacing: root.isMono || !root._onScale ? 0 : Design.tracking(Design.s(root._size))
    // Apple's line height for the style, where the text wraps; a single
    // line keeps the font's own, so nothing laid out around it moves.
    readonly property int _line: Design.font.lineHeight[root._size] || 0
    lineHeightMode: root._onScale && root.wrapMode !== Text.NoWrap && root._line > 0 ? Text.FixedHeight : Text.ProportionalHeight
    lineHeight: root._onScale && root.wrapMode !== Text.NoWrap && root._line > 0 ? Design.s(root._line) : 1.0
    color: root.dim ? Design.textDim : Design.text
}
