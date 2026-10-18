import QtQuick

// =============================================================================
// MouseArea with the shell's defaults already set, and the keyboard's way in.
//
// 121 MouseAreas across the popups; 96 set hoverEnabled and 75 set the pointer
// cursor, always the same three lines. Everything MouseArea does still works —
// this only stops the three lines from being retyped.
//
// It is also reachable with Tab: Return, Enter or Space click it, and the
// focus ring shows where Tab has gone. Forty-five things in the shell — the
// Control Center's toggle circles, the calendar's arrows, the media buttons —
// were Clickables and so could only be used with a pointer. Something that
// drags rather than clicks (a slider's track) sets `keyboard: false`.
//
//   Clickable { onClicked: window.close() }
// =============================================================================

MouseArea {
    id: root

    property bool keyboard: true
    // The ring's corner follows what the Clickable covers.
    property real ringRadius: parent && parent.radius !== undefined ? parent.radius : Design.s(Design.radius.ctl)

    anchors.fill: parent
    hoverEnabled: true
    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor

    activeFocusOnTab: root.keyboard && root.enabled && root.visible
    Keys.onReturnPressed: event => { root.clicked(null); event.accepted = true; }
    Keys.onEnterPressed: event => { root.clicked(null); event.accepted = true; }
    Keys.onSpacePressed: event => { root.clicked(null); event.accepted = true; }

    FocusRing {
        target: root
        cornerRadius: root.ringRadius + Design.s(Design.space.xxs)
        visible: root.keyboard && opacity > 0
    }
}
