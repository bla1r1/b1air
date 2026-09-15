import QtQuick
import QtQuick.Layouts

// =============================================================================
// Labelled switch row.
//
// Promoted from settings/components/SettingToggle.qml. Lost: `scaleFactor` and
// five hex colours. The switch geometry follows Design.radius.pill instead of
// three separately-computed radii that had to stay in sync by hand.
// =============================================================================

// The text sits in its own column with the switch beside it, centred. The
// switch used to share a row with the label, which made that row as tall as
// the switch and pushed the subtitle well below its label — the same control
// looked loosely spaced here and tight on the pages that built their own row.
// The whole row toggles, not only the 40 px switch.
RowLayout {
    id: row

    property string icon: ""
    property string label: ""
    property string subtitle: ""
    property bool checked: false
    signal toggled()

    Layout.fillWidth: true
    spacing: Design.s(Design.space.md)

    HoverHandler { cursorShape: row.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor }
    TapHandler { onTapped: row.toggled() }

    Icon {
        text: row.icon
        visible: text.length > 0
        role: "title"
        color: Design.accent
        Layout.preferredWidth: Design.s(24)
        Layout.alignment: Qt.AlignVCenter
    }

    ColumnLayout {
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignVCenter
        spacing: Design.s(1)

        Label {
            text: row.label
            weight: Design.weight.semibold
            Layout.fillWidth: true
            elide: Text.ElideRight
        }

        Label {
            text: row.subtitle
            visible: text.length > 0
            role: "caption"
            dim: true
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
        }
    }

    Rectangle {
        id: track
        Layout.alignment: Qt.AlignVCenter
        Layout.preferredWidth: Design.s(40)
        Layout.preferredHeight: Design.s(24)
        radius: height / 2
        color: row.checked ? Design.accent : Design.hover

        Behavior on color { ColorAnimation { duration: Design.duration.base } }

        Rectangle {
            id: knob
            width: parent.height - Design.s(6)
            height: width
            radius: width / 2
            color: row.checked ? Design.accentText : Design.ground
            y: Design.s(3)
            x: row.checked ? parent.width - width - Design.s(3) : Design.s(3)

            Behavior on x { NumberAnimation { duration: Design.duration.base; easing.type: Design.easing } }
            Behavior on color { ColorAnimation { duration: Design.duration.base } }
        }
    }
}
