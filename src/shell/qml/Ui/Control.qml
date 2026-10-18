import QtQuick

// =============================================================================
// Base interactive control with keyboard focus, accessibility, and click handling.
//
// Implements keyboard navigation (Tab / Shift+Tab), Space and Enter activation,
// hover and pressed state tracking, and focus ring visualization.
// =============================================================================

Item {
    id: root

    property bool hovered: mouseArea.containsMouse
    property bool pressed: mouseArea.pressed
    property real radius: Design.s(Design.radius.ctl)
    property bool showFocusRing: true
    property int cursorShape: Qt.PointingHandCursor

    property string accessibleName: ""
    property int accessibleRole: Accessible.Button

    Accessible.name: root.accessibleName
    Accessible.role: root.accessibleRole
    Accessible.focusable: root.enabled

    activeFocusOnTab: enabled

    signal activated()
    signal clicked()

    Keys.onReturnPressed: function(event) {
        if (root.enabled) {
            root.activated();
            root.clicked();
            event.accepted = true;
        }
    }

    Keys.onSpacePressed: function(event) {
        if (root.enabled) {
            root.activated();
            root.clicked();
            event.accepted = true;
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.enabled ? root.cursorShape : Qt.ArrowCursor
        onClicked: {
            if (root.enabled) {
                root.forceActiveFocus(Qt.MouseFocusReason);
                root.activated();
                root.clicked();
            }
        }
    }

    FocusRing {
        visible: root.showFocusRing && root.activeFocus
        cornerRadius: root.radius + Design.s(Design.space.xxs)
    }
}
