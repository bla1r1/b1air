import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Controls
import "Ui"
import "Services"
import "settings"
import Quickshell

Window {
    id: window
    title: "System Settings"
    width: Design.s(960)
    height: Design.s(640)
    minimumWidth: Design.s(760)
    minimumHeight: Design.s(500)
    visible: true
    color: "transparent"

    property string initialPage: {
        try {
            if (typeof Quickshell !== "undefined" && Quickshell.env("INITIAL_SETTINGS_PAGE")) {
                return Quickshell.env("INITIAL_SETTINGS_PAGE");
            }
        } catch (e) {}
        if (typeof InitialSettingsPage !== "undefined" && InitialSettingsPage !== "") {
            return InitialSettingsPage;
        }
        return "monitors";
    }

    // The settings window has its own root, so it needs the same
    // Settings → Design join Main.qml does; without it the accent picker
    // would preview nothing in the very window you pick it from.
    Binding {
        target: Design
        property: "accentName"
        value: Settings.accentName
    }

    onClosing: Qt.quit()

    Rectangle {
        id: windowFrame
        anchors.fill: parent
        // No corners or outline of our own: sway draws both, and only sway
        // knows which window has focus. The app drew a fixed 1px line and sway
        // was told `border none` for it, so ours were the only windows on the
        // desktop that did not light up when focused. SwayFX's corner_radius
        // rounds the surface; a 14px radius inside its 10px one left slivers.
        radius: 0
        color: Design.base
        clip: true

        SettingsApp {
            id: settings
            anchors.fill: parent
            framed: false
            page: window.initialPage !== "" ? window.initialPage : "monitors"
        }
    }

    Shortcut {
        sequence: "Escape"
        onActivated: window.close()
    }
}
