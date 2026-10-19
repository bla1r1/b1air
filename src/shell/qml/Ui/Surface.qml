import QtQuick
import B1air.Daemon

// =============================================================================
// A surface: a card, a recess, a control's fill, a pane of glass. Not a
// Rectangle typed out with its own fill, rim and corner in every app — they
// came in a dozen of each — but a kind, and the kind's look from Design:
//
//   Surface { kind: "card" }      // on a pane: glassCard, rim, a card's corner
//   Surface { kind: "well" }      // a recess: a field, a track, an icon's cell
//   Surface { kind: "control" }   // a control's own fill (a button-like cell)
//   Surface { kind: "glass" }     // a pane of glass: a toolbar, a popup's body
//
// Any of colour, rim and radius can still be set; the kind is the default.
// Its corner follows the corner rule (Shape) of what it sits in, and it is
// a container for the rule itself: what is inside `inset` in takes its
// radius less that. By default content sits as far in as its corner is
// round, where the rule says nothing — set `inset` for rows at its edge.
// A shape with no look of its own — a bar, a dot, a mask — is Ui/Box.
// =============================================================================

Rectangle {
    id: root
    property string kind: "card"   // card | well | control | glass
    property real inset: radius

    color: kind === "well" ? Design.well
         : kind === "control" ? Design.controlFill
         : kind === "glass" ? Design.glassBg
         : Design.glassCard
    border.width: kind === "well" ? 0 : Design.border
    border.color: Design.glassBorder
    radius: Design.corner(Shape.given, Design.s(kind === "card" || kind === "glass" ? Design.radius.card
                                                                                    : Design.radius.ctl))
    Shape.radius: root.radius
    Shape.inset: root.inset
}
