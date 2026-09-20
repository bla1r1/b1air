import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../Ui"
import "../../Services"

// =============================================================================
// Interactive Shortcuts & Keybindings Reference
// =============================================================================

ColumnLayout {
    id: section

    Layout.fillWidth: true
    spacing: Design.s(Design.space.lg)

    property string query: ""

    // Every row below is taken from .config/sway/conf.d/keybinds.conf. It had
    // drifted badly: this page told you Mod+Shift+Q closed the window (it runs
    // the QR scanner — close is Mod+Q), that Mod+B opened Bluetooth (it opens
    // the battery popup), that Mod+D was a calendar (it launches Discord), that
    // Mod+C was a code editor (it is the Control Center) and that Mod+Return
    // opened the terminal (nothing is bound to it — the terminal is Mod+T).
    // Ten of twenty-five rows named the wrong action.
    //
    // KEEP IN SYNC with conf.d/keybinds.conf. There is no runtime parser yet,
    // so an edit there is an edit here.
    readonly property var categories: [
        {
            title: "Launchers & Apps",
            icon: "\u{f0e59}",
            color: Design.sapphire,
            items: [
                { key: "Mod + Space", label: "Launchpad", desc: "Full-screen grid of every installed application" },
                { key: "Mod + K", label: "Spotlight", desc: "Fuzzy app search, clipboard history and inline math" },
                { key: "Mod + /", label: "Spotlight", desc: "Same launcher, second binding" },
                { key: "Mod + Shift + Space", label: "Spotlight", desc: "Same launcher, third binding" },
                { key: "Mod + T", label: "Terminal", desc: "The terminal chosen in Default Apps (b1air-term out of the box)" },
                { key: "Mod + E", label: "Files", desc: "The file manager chosen in Default Apps (b1air-files out of the box)" },
                { key: "Mod + F", label: "Browser", desc: "The browser chosen in Default Apps" },
                { key: "Mod + G", label: "GitHub Desktop", desc: "Open the Git client" },
                { key: "Mod + Ctrl + S", label: "Steam", desc: "Open the games library" },
                { key: "Mod + D", label: "Discord", desc: "Open the chat client" }
            ]
        },
        {
            title: "Panels & Popups",
            icon: "\u{f0335}",
            color: Design.blue,
            items: [
                { key: "Mod + C", label: "Control Center", desc: "Quick tiles, volume, brightness and media" },
                { key: "Mod + Shift + N", label: "Notification Center", desc: "Everything that has arrived, and the per-app mutes" },
                { key: "Mod + Ctrl + V", label: "Clipboard History", desc: "Search and paste previously copied text" },
                { key: "Mod + .", label: "Emoji Picker", desc: "Search emoji and paste into the focused window" },
                { key: "Mod + B", label: "Battery", desc: "Charge, health and energy-mode popup" },
                { key: "Mod + N", label: "Network", desc: "Scan and connect to Wi-Fi" },
                { key: "Mod + M", label: "Displays", desc: "Arrange monitors, resolution and refresh rate" },
                { key: "Mod + Z", label: "Fancy Zones", desc: "Snap the focused window into a layout zone" },
                { key: "Mod + Shift + D", label: "Drop Shelf", desc: "Temporary holding area for dragged files" },
                { key: "Mod + Shift + K", label: "Keyboard", desc: "Switch input source and on-screen keyboard" },
                { key: "Mod + Shift + M", label: "Screen Ruler", desc: "Measure distances on screen in pixels" },
                { key: "Mod + Shift + T", label: "Screen Time", desc: "Daily app usage and focus timer" },
                { key: "Mod + Shift + E", label: "Session Menu", desc: "Lock, sleep, reboot or power off" },
                { key: "Mod + Shift + L", label: "Log Out", desc: "Leave the session, after a confirmation" },
                { key: "Mod + Shift + S", label: "Settings", desc: "Open the settings hub" },
                { key: "Mod + W", label: "Wallpaper Settings", desc: "Jump straight to the wallpaper page" },
                { key: "Mod + H", label: "Shortcuts", desc: "This list" }
            ]
        },
        {
            title: "Windows & Workspaces",
            icon: "\u{f05b0}",
            color: Design.mauve,
            items: [
                { key: "Mod + Q", label: "Close Window", desc: "Close the focused window" },
                { key: "Alt + Tab", label: "Next Window", desc: "Focus the next window on the workspace" },
                { key: "Alt + Shift + Tab", label: "Previous Window", desc: "Focus the previous window" },
                { key: "Mod + V", label: "Toggle Floating", desc: "Switch the window between tiling and floating (also Mod + Ctrl + Space)" },
                { key: "Mod + Alt + Space", label: "Float Workspace", desc: "Float every window on the workspace, or tile them all again" },
                { key: "Mod + Shift + F", label: "Smart Fullscreen", desc: "Fullscreen with auto-centering" },
                { key: "Mod + Ctrl + F", label: "Maximize", desc: "Fill the workspace, keeping the bar and gaps" },
                { key: "Mod + Ctrl + Shift + F", label: "Global Fullscreen", desc: "Fullscreen across every output" },
                { key: "Mod + Ctrl + O", label: "Opaque", desc: "Make a see-through window solid, and back" },
                { key: "Mod + Ctrl + G", label: "Tabs", desc: "Turn the window's container into tabs, and back" },
                { key: "Mod + Tab", label: "Next Tab", desc: "Step through the windows in a tab group (Shift goes back)" },
                { key: "Mod + -", label: "Minimize", desc: "Send the focused window out of the way" },
                { key: "Mod + Shift + -", label: "Restore", desc: "Bring the last minimized window back" },
                { key: "Mod + Shift + I", label: "Split Direction", desc: "Toggle horizontal / vertical split" },
                { key: "Mod + J", label: "Layout Toggle", desc: "Cycle the container layout" },
                { key: "Mod + Arrows", label: "Focus Navigation", desc: "Move focus left / right / up / down" },
                { key: "Mod + Ctrl + Arrows", label: "Move Window", desc: "Relocate the window within its container" },
                { key: "Mod + Alt + Arrows", label: "Swap Window", desc: "Trade places with the window on that side" },
                { key: "Mod + Shift + Arrows", label: "Resize Window", desc: "Grow or shrink the container by 50 px" },
                { key: "Mod + 1 .. 0", label: "Switch Workspace", desc: "Jump to a numbered workspace" },
                { key: "Mod + Shift + 1 .. 0", label: "Move to Workspace", desc: "Send the focused window to a workspace" },
                { key: "Mod + Scroll", label: "Cycle Workspaces", desc: "Wheel down for the next workspace, up for the previous" },
                { key: "Mod + S", label: "Scratchpad Show", desc: "Reveal the scratchpad window" },
                { key: "Mod + Ctrl + Shift + S", label: "Scratchpad Move", desc: "Send the focused window to the scratchpad" },
                { key: "Mod + Escape", label: "Force Quit", desc: "Kill an unresponsive application" }
            ]
        },
        {
            title: "Capture & Tools",
            icon: "\u{f0a0f}",
            color: Design.pink,
            items: [
                { key: "Print", label: "Region Screenshot", desc: "Select an area, copy and save it" },
                { key: "Shift + Print", label: "Region + Annotate", desc: "Same, then open the annotation editor" },
                { key: "Mod + Print", label: "Full Screenshot", desc: "Capture the whole output" },
                { key: "Mod + Shift + Print", label: "Window Screenshot", desc: "Capture only the focused window (also Alt + Print)" },
                { key: "Mod + Alt + Print", label: "Full Screenshot", desc: "The whole screen, same as Mod + Print" },
                { key: "Mod + Ctrl + Print", label: "Delayed Screenshot", desc: "The whole screen after 5 seconds (add Shift for 10)" },
                { key: "Mod + Alt + R", label: "Record GIF", desc: "Record a screen region to an animated GIF" },
                { key: "Mod + Shift + C", label: "Color Picker", desc: "Eyedropper a screen pixel to the clipboard" },
                { key: "Mod + Shift + O", label: "OCR", desc: "Read text out of a selected screen region" },
                { key: "Mod + Shift + Q", label: "QR Scanner", desc: "Decode a QR code shown on screen" },
                { key: "Mod + Shift + V", label: "Voice Memo", desc: "Record a quick audio note" },
                { key: "Mod + P", label: "Picture in Picture", desc: "Pin the focused video above other windows" },
                { key: "Mod + Shift + A", label: "Audio Output", desc: "Cycle to the next sound output device" },
                { key: "Mod + Shift + G", label: "Game Mode", desc: "Drop compositor effects and pin the performance governor" },
                { key: "Ctrl + Alt + L", label: "Lock Screen", desc: "Lock the session immediately" }
            ]
        },
        {
            title: "Media & Hardware Keys",
            icon: "\u{f075a}",
            color: Design.teal,
            items: [
                { key: "Volume Up / Down", label: "Volume", desc: "Raise or lower the master output by 5%" },
                { key: "Mute", label: "Mute Output", desc: "Toggle speakers and headphones" },
                { key: "Mic Mute", label: "Mute Microphone", desc: "Toggle the capture device" },
                { key: "Brightness Up / Down", label: "Screen Brightness", desc: "Adjust the laptop backlight by 5%" },
                { key: "Kbd Brightness Up / Down", label: "Keyboard Backlight", desc: "Adjust the keyboard backlight" },
                { key: "Play / Pause", label: "Playback", desc: "Toggle the active media player" },
                { key: "Next / Previous", label: "Track", desc: "Skip forward or back in the playlist" }
            ]
        }
    ]

    // ── Search & Filter ──────────────────────────────────────────────────────
    Card {
        title: "Keyboard Shortcuts Reference"
        subtitle: "Complete cheatsheet of desktop keybindings and global triggers"
        icon: "\u{f11c}"
        accentColor: Design.sapphire

        Field {
            Layout.fillWidth: true
            placeholder: "Filter: fullscreen, volume, space…"
            onEdited: v => section.query = v.toLowerCase().trim()
        }
    }

    // ── Categories ───────────────────────────────────────────────────────────
    Repeater {
        model: section.categories
        delegate: ColumnLayout {
            id: catCol
            required property var modelData
            Layout.fillWidth: true
            spacing: Design.s(Design.space.sm)
            visible: categoryItems.count > 0

            Card {
                title: catCol.modelData.title
                icon: catCol.modelData.icon
                accentColor: catCol.modelData.color

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Design.s(Design.space.xs)

                    Repeater {
                        id: categoryItems
                        model: {
                            var items = catCol.modelData.items;
                            if (!section.query) return items;
                            return items.filter(function(item) {
                                return item.key.toLowerCase().indexOf(section.query) !== -1 ||
                                       item.label.toLowerCase().indexOf(section.query) !== -1 ||
                                       item.desc.toLowerCase().indexOf(section.query) !== -1;
                            });
                        }
                        delegate: RowLayout {
                            Layout.fillWidth: true
                            Layout.preferredHeight: Design.s(36)
                            spacing: Design.s(Design.space.md)

                            Rectangle {
                                Layout.preferredWidth: Design.s(160)
                                Layout.preferredHeight: Design.s(28)
                                radius: Design.s(Design.radius.pill)
                                color: Design.raised
                                border.color: Design.tint(catCol.modelData.color || Design.accent, 0.4)
                                border.width: 1

                                Label {
                                    anchors.centerIn: parent
                                    text: modelData.key
                                    role: "caption"
                                    weight: Design.weight.semibold
                                    color: catCol.modelData.color || Design.accent
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                Label { text: modelData.label; weight: Design.weight.semibold; role: "caption" }
                                Label { text: modelData.desc; role: "caption"; dim: true }
                            }
                        }
                    }
                }
            }
        }
    }
}
