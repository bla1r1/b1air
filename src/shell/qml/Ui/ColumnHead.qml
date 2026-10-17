import QtQuick
import QtQuick.Layouts

// =============================================================================
// A sortable column heading: the label, and an arrow when the list is sorted
// by it. Files had one for its list view and Monitor a row of bare Text over
// its process table; one heading for both.
//
//   ColumnHead { label: I18n.tr("Size"); sorted: model.sortField === "size"
//                ascending: model.ascending; onClicked: model.sortBy("size") }
// =============================================================================

Item {
    id: root

    property string label: ""
    property bool sorted: false
    property bool ascending: true
    property bool alignRight: false
    // Room at the start, to line up with the rows' text past their icon.
    property real inset: 0
    property bool sortable: true
    signal clicked()

    implicitHeight: Design.s(Design.size.md)
    implicitWidth: row.implicitWidth + root.inset

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: root.alignRight ? parent.right : undefined
        anchors.left: root.alignRight ? undefined : parent.left
        anchors.leftMargin: root.alignRight ? 0 : root.inset
        spacing: Design.s(Design.space.xs)
        Label {
            text: root.label
            role: "caption"
            weight: Design.weight.semibold
            color: root.sorted ? Design.text : Design.textDim
        }
        Icon {
            visible: root.sorted
            text: root.ascending ? "\u{f005d}" : "\u{f0045}"
            role: "caption"
            color: Design.text
        }
    }

    Clickable {
        anchors.fill: parent
        enabled: root.sortable
        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.clicked()
    }
}
