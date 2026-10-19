import QtQuick
import QtQuick.Controls as QQC

// =============================================================================
// Where a song or a film is, to drag: a track in the well, how far along in
// the accent, and a knob that swells under the finger. A setting's level
// (volume, brightness) is Ui/Slider; this is a position in time.
//
//   Scrubber { from: 0; to: 100; onPressedChanged: if (!pressed) seek(value) }
// =============================================================================

QQC.Slider {
    id: root
    implicitHeight: Design.s(Design.size.mini)

    background: Item {
        x: root.leftPadding
        y: root.topPadding + (root.availableHeight - height) / 2
        width: root.availableWidth
        height: Design.s(Design.space.md)

        Surface {
            kind: "well"
            anchors.fill: parent
            radius: height / 2
        }
        Box {
            width: root.handle.x - root.leftPadding + root.handle.width / 2
            height: parent.height
            radius: height / 2
            color: Design.accent
        }
    }

    // A knob on an accent track, not a cream dot: text's near-white says
    // "a letter", not "a control".
    handle: Surface {
        x: root.leftPadding + root.visualPosition * (root.availableWidth - width)
        y: root.topPadding + (root.availableHeight - height) / 2
        implicitWidth: Design.s(Design.size.micro)
        implicitHeight: Design.s(Design.size.micro)
        radius: Design.s(Design.radius.ctl)
        border.width: Math.max(1, Design.s(Design.focusWidth))
        border.color: Design.accent
        scale: root.pressed ? 1.3 : 1.0
        Behavior on scale {
            enabled: !Design.reduceMotion
            NumberAnimation { duration: Design.duration.fast; easing.type: Easing.OutBack }
        }
    }
}
