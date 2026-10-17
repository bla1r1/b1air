import QtQuick
import QtQuick.Layouts
import "../Ui"
import "../Services"

// =============================================================================
// Charge pill — the same badge the header and the power page each built by hand.
//
// Both set `height:` and `implicitWidth:` on a RowLayout child. A layout takes
// height from implicitHeight, which on a bare Rectangle is zero, so the pill was
// drawn at whatever height the row happened to hand it.
// =============================================================================

Item {
    id: root

    property bool clickable: true
    signal clicked()

    readonly property color tone: Power.charging ? Design.ok
        : (Power.capacity <= 20 ? Design.danger : Design.text)

    visible: Power.hasBattery
    implicitHeight: Design.s(Design.size.sm)   // same height as the gear beside it
    implicitWidth: pill.implicitWidth

    Rectangle {
        id: pill
        anchors.fill: parent
        radius: height / 2
        implicitWidth: row.implicitWidth + Design.s(Design.space.md)

        color: Design.tint(root.tone, ma.containsMouse ? 0.2 : 0.12)
        border.color: Design.tint(root.tone, 0.25)
        border.width: Design.border

        Behavior on color { ColorAnimation { duration: Design.duration.fast } }

        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: Design.s(Design.space.xs)

            Icon {
                text: Power.charging ? "\u{f0084}"
                    : (Power.capacity > 80 ? "\u{f0079}"
                    : (Power.capacity > 30 ? "\u{f007c}" : "\u{f0083}"))
                role: "caption"
                color: root.tone
            }

            Label {
                text: Power.capacity + "%"
                role: "caption"
                isMono: true
                weight: Design.weight.semibold
                color: root.tone
            }
        }
    }

    Clickable {
        id: ma
        enabled: root.clickable
        onClicked: root.clicked()
    }
}
