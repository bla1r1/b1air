import QtQuick

// =============================================================================
// The frame a widget wears while its panel is being arranged.
//
//   Item {                       // the widget, whatever it is
//       …content…
//       EditFrame {
//           anchors.fill: parent
//           active: panel.editing
//           sizeLabel: "M"
//           onRemove: …; onCycleSize: …; onDropped: pos => …
//       }
//   }
//
// It sits *over* the widget, never in its layout. The Control Center and the
// calendar used to put their remove badge and size chip into the widget's own
// row as extra cells, so switching arrange mode on pushed the contents about:
// the calendar's four weather pills were squeezed into the last two columns of
// a grid whose first two had become a badge and a letter.
//
// While active, the widget underneath stops taking input — you are moving the
// thing, not using it — and the whole frame is the drag handle, which is what
// people try first; the grip in the toolbar is there to say so.
// =============================================================================

Item {
    id: frame

    property bool active: false
    /** "S", "M", "L", or "" for a widget with one size. */
    property string sizeLabel: ""
    property bool removable: true
    property bool draggable: true
    /** Lit by the panel when something is being dragged over this widget. */
    property bool dropTarget: false

    signal remove()
    signal cycleSize()
    signal dragMoved(point scenePos)
    signal dropped(point scenePos)

    property bool dragging: false

    visible: frame.active
    z: 30

    // One MouseArea does both jobs. It swallows what the widget would get — a
    // tap on the Wi-Fi tile while arranging must not switch Wi-Fi off — and it
    // is the drag. A DragHandler on the frame never saw a press: the
    // MouseArea, being a child and on top, accepted it first.
    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        preventStealing: true
        cursorShape: frame.draggable ? (frame.dragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor)
                                     : Qt.ArrowCursor
        property point pressAt

        onPressed: mouse => area.pressAt = Qt.point(mouse.x, mouse.y)
        onPositionChanged: mouse => {
            if (!pressed || !frame.draggable)
                return;
            if (!frame.dragging && Math.hypot(mouse.x - area.pressAt.x, mouse.y - area.pressAt.y) > Design.s(6))
                frame.dragging = true;
            if (frame.dragging)
                frame.dragMoved(area.mapToItem(null, mouse.x, mouse.y));
        }
        onReleased: mouse => {
            if (!frame.dragging)
                return;
            frame.dragging = false;
            frame.dropped(area.mapToItem(null, mouse.x, mouse.y));
        }
        onCanceled: frame.dragging = false
    }

    Rectangle {
        anchors.fill: parent
        radius: Design.s(Design.radius.card)
        color: frame.dropTarget ? Design.tint(Design.accent, 0.22)
                                : (frame.dragging ? Design.tint(Design.accent, 0.12) : "transparent")
        border.color: frame.dropTarget || frame.dragging ? Design.accent : Design.tint(Design.accent, 0.55)
        border.width: frame.dropTarget ? 2 : 1
        Behavior on color { ColorAnimation { duration: Design.duration.fast } }
    }

    // Toolbar: grip, size, remove. Sitting on the top edge rather than inside
    // the corner: inside, it covered the widget's title ("Do Not Dis…"), and
    // the title is how you know which widget you are about to remove. The
    // panels open their spacing up while arranging to leave it room.
    Rectangle {
        id: bar
        anchors.top: parent.top
        anchors.topMargin: -height / 2
        anchors.right: parent.right
        anchors.rightMargin: Design.s(8)
        height: Design.s(20)
        width: tools.implicitWidth + Design.s(6)
        radius: height / 2
        color: Design.tint(Design.raised, 0.95)
        border.color: Design.line
        border.width: 1

        Row {
            id: tools
            anchors.centerIn: parent
            spacing: Design.s(2)

            Icon {
                visible: frame.draggable
                width: Design.s(16); height: Design.s(16)
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                text: "\u{f01db}"   // drag
                role: "caption"
                color: Design.textDim
            }

            Rectangle {
                visible: frame.sizeLabel !== ""
                width: Design.s(16); height: Design.s(16)
                radius: width / 2
                color: sizeMa.containsMouse ? Design.tint(Design.accent, 0.35) : Design.tint(Design.accent, 0.18)
                Label {
                    anchors.centerIn: parent
                    text: frame.sizeLabel
                    role: "caption"
                    weight: Design.weight.bold
                    color: Design.accent
                }
                MouseArea {
                    id: sizeMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: frame.cycleSize()
                }
            }

            Rectangle {
                visible: frame.removable
                width: Design.s(16); height: Design.s(16)
                radius: width / 2
                color: removeMa.containsMouse ? Design.danger : Design.tint(Design.danger, 0.75)
                Icon {
                    anchors.centerIn: parent
                    text: "\u{f0156}"
                    role: "caption"
                    color: Design.accentText
                }
                MouseArea {
                    id: removeMa
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: frame.remove()
                }
            }
        }
    }
}
