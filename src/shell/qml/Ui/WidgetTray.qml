import QtQuick
import QtQuick.Layouts

// =============================================================================
// "Add a widget": everything that has been taken out of a panel, as chips.
//
// Removed widgets used to stay in place while arranging, drawn at a third of
// their opacity with a small green + in one corner. On a panel that is mostly
// dark glass a faded card reads as disabled, not as "put me back", and on the
// calendar the + sat inside a squeezed row where it was easy to miss — so a
// widget, once removed, looked gone for good. They live here now, labelled.
// =============================================================================

Rectangle {
    id: tray

    /** [{ id, title, icon }] — the widgets that are switched off. */
    property var items: []
    property bool active: false
    signal add(string id)

    visible: tray.active
    implicitHeight: col.implicitHeight + Design.s(Design.space.sm) * 2
    radius: Design.s(Design.radius.card)
    color: Design.tint(Design.accent, 0.08)
    border.color: Design.tint(Design.accent, 0.45)
    border.width: 1

    ColumnLayout {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Design.s(Design.space.sm)
        spacing: Design.s(Design.space.xs)

        Label {
            text: tray.items.length > 0 ? I18n.tr("Add a widget") : I18n.tr("Every widget is on the panel")
            role: "caption"
            weight: Design.weight.bold
            color: tray.items.length > 0 ? Design.accent : Design.textDim
        }

        Flow {
            Layout.fillWidth: true
            visible: tray.items.length > 0
            spacing: Design.s(Design.space.xs)

            Repeater {
                model: tray.items

                Rectangle {
                    required property var modelData
                    height: Design.s(26)
                    width: chipRow.implicitWidth + Design.s(16)
                    radius: height / 2
                    color: chipMa.containsMouse ? Design.tint(Design.accent, 0.30) : Design.raised
                    border.color: Design.tint(Design.accent, 0.5)
                    border.width: 1

                    Row {
                        id: chipRow
                        anchors.centerIn: parent
                        spacing: Design.s(6)
                        Icon { text: "\u{f0415}"; role: "caption"; color: Design.accent; anchors.verticalCenter: parent.verticalCenter }
                        Icon {
                            visible: text !== ""
                            text: modelData.icon || ""
                            role: "caption"
                            color: Design.textDim
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Label { text: modelData.title; role: "caption"; weight: Design.weight.semibold; anchors.verticalCenter: parent.verticalCenter }
                    }

                    MouseArea {
                        id: chipMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: tray.add(modelData.id)
                    }
                }
            }
        }
    }
}
