import QtQuick
import QtQuick.Layouts

// =============================================================================
// A check box and its label: for a yes or no that sits beside other buttons
// ("Show at login" at the foot of the welcome), where a Switch would read as
// a setting of the page rather than of the window.
//
//   CheckBox { text: I18n.tr("Show at login"); checked: …; onToggled: … }
//
// `toggled` is asked for, not done: the owner flips what `checked` is bound
// to, as with Switch.
// =============================================================================

Item {
    id: root

    property bool checked: false
    property string text: ""
    signal toggled()

    implicitWidth: row.implicitWidth
    implicitHeight: Math.max(row.implicitHeight, Design.s(Design.size.sm))
    opacity: enabled ? Design.opacity.full : Design.opacity.disabled

    activeFocusOnTab: true
    Keys.onSpacePressed: root.toggled()
    Keys.onReturnPressed: root.toggled()

    RowLayout {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: Design.s(Design.space.sm)

        Rectangle {
            Layout.preferredWidth: Design.s(Design.space.lg)
            Layout.preferredHeight: Design.s(Design.space.lg)
            radius: Design.s(Design.radius.sm)
            color: root.checked ? Design.accent : "transparent"
            border.width: root.checked ? 0 : Design.border
            border.color: Design.glassBorderStrong
            Behavior on color { ColorAnimation { duration: Design.duration.fast } }

            Icon {
                anchors.centerIn: parent
                visible: root.checked
                text: "\u{f012c}"
                role: "caption"
                color: Design.accentText
            }
        }

        Label {
            text: root.text
            role: "body"
        }
    }

    FocusRing { target: root; cornerRadius: Design.s(Design.radius.ctl) }

    Clickable {
        keyboard: false
        onClicked: root.toggled()
    }
}
