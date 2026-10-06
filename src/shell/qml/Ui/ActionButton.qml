import QtQuick
import QtQuick.Layouts

// =============================================================================
// Wide icon + label button — the Lock / Sleep / Reboot / Off row.
//
// `destructive` adds the step that row was missing: one stray click in a popup
// that opens under the cursor should not power the machine off. The first click
// arms, the second commits, and it disarms itself after a few seconds.
// =============================================================================

Rectangle {
    id: root

    property string icon: ""
    property string label: ""
    property color tone: Design.text
    property color iconTone: Design.textDim
    property bool destructive: false
    property string confirmLabel: "Sure?"
    // Only the icon: for a row that cannot fit every label (the Control
    // Center's Lock / Sleep / Reboot / Off in Ukrainian or Russian, where the
    // last one was pushed out of the panel). The label is still read out as
    // the accessible name.
    property bool iconOnly: false
    // Narrower padding: the step before iconOnly, for a row whose labels fit
    // only just.
    property bool snug: false
    readonly property real _pad: Design.s(root.snug ? Design.space.sm : Design.space.lg)
    // The width the button would take with its label, whatever iconOnly says —
    // for a row to decide whether its labels fit; snugWidth with the narrow
    // padding.
    readonly property real fullWidth: _labelWidth + Design.s(Design.space.lg) * 2
    readonly property real snugWidth: _labelWidth + Design.s(Design.space.sm) * 2
    readonly property real _labelWidth: fullText.width + (root.icon !== "" ? Design.s(18) + Design.s(Design.space.xs) : 0)
    TextMetrics {
        id: fullText
        text: root.label
        font.family: Design.font.sans
        font.pixelSize: Design.s(Design.font.body)
    }
    Accessible.name: root.label

    signal activated()

    property bool _armed: false

    Layout.fillWidth: true
    // Field height, so a button next to a text field lines up with it.
    Layout.preferredHeight: Design.s(Design.size.field)

    // The icon and label are centred with anchors, and anchored children
    // contribute nothing to a parent's implicit size — so this button reported
    // no width of its own and a RowLayout was free to squeeze it below its own
    // text. That is how "Add Installed App…" ended up sliced off by the edge of
    // its card. Now the button asks for at least the room its content needs;
    // fillWidth still lets it grow past that wherever it is used alone.
    implicitWidth: content.implicitWidth + root._pad * 2
    Layout.minimumWidth: root.implicitWidth

    radius: height / 2
    color: root._armed ? Design.tint(root.tone, 0.28)
                       : (ma.containsMouse ? (root.destructive ? Design.tint(root.tone, 0.18) : Design.glassHover)
                                           : Design.glassCard)
    // The same capsule as BarButton and Pill: no outline, the fill is the shape.
    border.color: root._armed ? Design.tint(root.tone, 0.7) : "transparent"
    border.width: Design.border

    Behavior on color { ColorAnimation { duration: Design.duration.fast } }
    Behavior on border.color { ColorAnimation { duration: Design.duration.fast } }

    scale: ma.pressed ? 0.97 : 1.0
    Behavior on scale { NumberAnimation { duration: Design.duration.fast; easing.type: Design.easing } }

    // `enabled` already stops the click — Item.enabled cascades to the
    // MouseArea below — but nothing showed it, so a button that would do
    // nothing looked exactly like one that would. QuickLook had two of them
    // sitting over an empty preview, offering to copy a path that was "".
    opacity: root.enabled ? 1.0 : 0.45
    Behavior on opacity { NumberAnimation { duration: Design.duration.fast } }

    Timer {
        id: disarm
        interval: 3000
        onTriggered: root._armed = false
    }

    RowLayout {
        id: content
        anchors.centerIn: parent
        spacing: Design.s(Design.space.xs)

        Icon {
            id: glyph
            visible: text !== ""
            text: root._armed ? "\u{f0026}" : root.icon   // alert glyph while armed
            role: "body"
            color: root._armed ? root.tone : root.iconTone
        }

        Label {
            visible: !root.iconOnly
            // A squeezed button shortens its label rather than spilling it.
            Layout.maximumWidth: Math.max(0, root.width - root._pad * 2
                                          - (glyph.visible ? glyph.implicitWidth + content.spacing : 0))
            elide: Text.ElideRight
            text: root._armed ? root.confirmLabel : root.label
            weight: root._armed ? Design.weight.semibold : Design.weight.regular
            // Colour is for the "Sure?" step. Until then every action reads
            // in the text colour, whatever tint its card has.
            color: root._armed ? root.tone : Design.text
        }
    }

    Clickable {
        id: ma
        onClicked: {
            if (!root.destructive || root._armed) {
                root._armed = false;
                disarm.stop();
                root.activated();
                return;
            }
            root._armed = true;
            disarm.restart();
        }
    }

    onVisibleChanged: if (!visible) { _armed = false; disarm.stop(); }
}
