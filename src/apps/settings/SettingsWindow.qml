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

    // Colours for every stock control in the window — tooltips, scroll bars,
    // combo boxes, text fields — from the desktop palette. Left to the Basic
    // style they were its own: a pale-yellow tooltip, light-grey bars.
    palette.window: Design.surface
    palette.windowText: Design.text
    palette.base: Design.sunken
    palette.alternateBase: Design.raised
    palette.text: Design.text
    palette.button: Design.raised
    palette.buttonText: Design.text
    palette.brightText: Design.text
    palette.highlight: Design.accent
    palette.highlightedText: Design.accentText
    palette.toolTipBase: Design.raised
    palette.toolTipText: Design.text
    palette.placeholderText: Design.textFaint
    palette.light: Design.active
    palette.midlight: Design.hover
    palette.mid: Design.line
    palette.dark: Design.sunken
    palette.shadow: Design.ground
    title: I18n.tr("System Settings")
    width: Design.s(Design.window.standardWidth)
    height: Design.s(Design.window.standardHeight)
    minimumWidth: Design.s(Design.window.minWidth)
    minimumHeight: Design.s(Design.window.minHeight)
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

    Surface {
        kind: "glass"
        border.width: 0
        id: windowFrame
        anchors.fill: parent
        // No corners or outline of our own: sway draws both, and only sway
        // knows which window has focus. The app drew a fixed 1px line and sway
        // was told `border none` for it, so ours were the only windows on the
        // desktop that did not light up when focused. SwayFX's corner_radius
        // rounds the surface; a 14px radius inside its 10px one left slivers.
        radius: 0
        clip: true

        SettingsApp {
            id: settings
            anchors.fill: parent
            framed: false
            standalone: true
            onCloseRequested: window.close()
            page: window.initialPage !== "" ? window.initialPage : "monitors"
        }
    }

    Shortcut {
        sequence: "Escape"
        onActivated: window.close()
    }
}
