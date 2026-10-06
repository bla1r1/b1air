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
    // the battery popup), that Mod+D was a calendar (it was Discord's key then), that
    // Mod+C was a code editor (it is the Control Center) and that Mod+Return
    // opened the terminal (nothing is bound to it — the terminal is Mod+T).
    // Ten of twenty-five rows named the wrong action.
    //
    // KEEP IN SYNC with conf.d/keybinds.conf. There is no runtime parser yet,
    // so an edit there is an edit here.
    readonly property var categories: [
        {
            title: I18n.tr("Launchers & Apps"),
            icon: "\u{f0e59}",
            color: Design.sapphire,
            items: [
                { key: "Mod + Space", label: I18n.tr("Launchpad"), desc: I18n.tr("Full-screen grid of every installed application") },
                { key: "Mod + K", label: I18n.tr("Spotlight"), desc: I18n.tr("Fuzzy app search, clipboard history and inline math") },
                { key: "Mod + /", label: I18n.tr("Spotlight"), desc: I18n.tr("Same launcher, second binding") },
                { key: "Mod + Shift + Space", label: I18n.tr("Spotlight"), desc: I18n.tr("Same launcher, third binding") },
                { key: "Mod + T", label: I18n.tr("Terminal"), desc: I18n.tr("The terminal chosen in Default Apps (b1air-term out of the box)") },
                { key: "Mod + `", label: I18n.tr("Drop-down terminal"), desc: I18n.tr("Slides a terminal down from the top; the same key hides it") },
                { key: "Mod + E", label: I18n.tr("Files"), desc: I18n.tr("The file manager chosen in Default Apps (b1air-files out of the box)") },
                { key: "Mod + F", label: I18n.tr("Browser"), desc: I18n.tr("The browser chosen in Default Apps") },
                { key: "Mod + G", label: I18n.tr("Git"), desc: I18n.tr("Open the Git client (b1air-git)") },
                { key: "Ctrl + Shift + Esc", label: I18n.tr("System Monitor"), desc: I18n.tr("Processes, memory and disks; end a stuck program") },
                { key: "Mod + I", label: I18n.tr("Code editor"), desc: I18n.tr("Open Zed") },
                { key: "Mod + X", label: I18n.tr("Text Editor"), desc: I18n.tr("Open the text editor") },
                { key: "Mod + Ctrl + C", label: I18n.tr("Camera"), desc: I18n.tr("Open the camera") }
            ]
        },
        {
            title: I18n.tr("Panels & Popups"),
            icon: "\u{f0335}",
            color: Design.blue,
            items: [
                { key: "Mod + C", label: I18n.tr("Control Center"), desc: I18n.tr("Quick tiles, volume, brightness and media") },
                { key: "Mod + Shift + N", label: I18n.tr("Notification Center"), desc: I18n.tr("Everything that has arrived, and the per-app mutes") },
                { key: "Mod + Ctrl + V", label: I18n.tr("Clipboard History"), desc: I18n.tr("Search and paste previously copied text") },
                { key: "Mod + .", label: I18n.tr("Emoji Picker"), desc: I18n.tr("Search emoji and paste into the focused window") },
                { key: "Mod + B", label: I18n.tr("Battery"), desc: I18n.tr("Charge, health and energy-mode popup") },
                { key: "Mod + N", label: I18n.tr("Network"), desc: I18n.tr("Scan and connect to Wi-Fi") },
                { key: "Mod + M", label: I18n.tr("Displays"), desc: I18n.tr("Arrange monitors, resolution and refresh rate") },
                { key: "Mod + Z", label: I18n.tr("Fancy Zones"), desc: I18n.tr("Snap the focused window into a layout zone") },
                { key: "Mod + Shift + D", label: I18n.tr("Drop Shelf"), desc: I18n.tr("Temporary holding area for dragged files") },
                { key: "Mod + Shift + K", label: I18n.tr("Keyboard"), desc: I18n.tr("Switch input source and on-screen keyboard") },
                { key: "Mod + Shift + M", label: I18n.tr("Screen Ruler"), desc: I18n.tr("Measure distances on screen in pixels") },
                { key: "Mod + Shift + T", label: I18n.tr("Screen Time"), desc: I18n.tr("Daily app usage and focus timer") },
                { key: "Mod + Shift + E", label: I18n.tr("Session Menu"), desc: I18n.tr("Lock, sleep, reboot or power off") },
                { key: "Mod + Shift + L", label: I18n.tr("Log Out"), desc: I18n.tr("Leave the session, after a confirmation") },
                { key: "Mod + Shift + S", label: I18n.tr("Settings"), desc: I18n.tr("Open the settings hub") },
                { key: "Mod + W", label: I18n.tr("Wallpaper Settings"), desc: I18n.tr("Jump straight to the wallpaper page") },
                { key: "Mod + H", label: I18n.tr("Shortcuts"), desc: I18n.tr("This list") }
            ]
        },
        {
            title: I18n.tr("Windows & Workspaces"),
            icon: "\u{f05b0}",
            color: Design.mauve,
            items: [
                { key: "Mod + Q", label: I18n.tr("Close Window"), desc: I18n.tr("Close the focused window") },
                { key: "Alt + Tab", label: I18n.tr("Next Window"), desc: I18n.tr("Focus the next window on the workspace") },
                { key: "Alt + Shift + Tab", label: I18n.tr("Previous Window"), desc: I18n.tr("Focus the previous window") },
                { key: "Mod + V", label: I18n.tr("Toggle Floating"), desc: I18n.tr("Switch the window between tiling and floating (also Mod + Ctrl + Space)") },
                { key: "Mod + Alt + Space", label: I18n.tr("Float Workspace"), desc: I18n.tr("Float every window on the workspace, or tile them all again") },
                { key: "Mod + Shift + F", label: I18n.tr("Smart Fullscreen"), desc: I18n.tr("Fullscreen with auto-centering") },
                { key: "Mod + Ctrl + F", label: I18n.tr("Maximize"), desc: I18n.tr("Fill the workspace, keeping the bar and gaps") },
                { key: "Mod + Ctrl + Shift + F", label: I18n.tr("Global Fullscreen"), desc: I18n.tr("Fullscreen across every output") },
                { key: "Mod + Ctrl + O", label: I18n.tr("Opaque"), desc: I18n.tr("Make a see-through window solid, and back") },
                { key: "Mod + Ctrl + G", label: I18n.tr("Tabs"), desc: I18n.tr("Turn the window's container into tabs, and back") },
                { key: "Mod + Tab", label: I18n.tr("Next Tab"), desc: I18n.tr("Step through the windows in a tab group (Shift goes back)") },
                { key: "Mod + -", label: I18n.tr("Minimize"), desc: I18n.tr("Send the focused window out of the way") },
                { key: "Mod + Shift + -", label: I18n.tr("Restore"), desc: I18n.tr("Bring the last minimized window back") },
                { key: "Mod + Shift + I", label: I18n.tr("Split Direction"), desc: I18n.tr("Toggle horizontal / vertical split") },
                { key: "Mod + J", label: I18n.tr("Layout Toggle"), desc: I18n.tr("Cycle the container layout") },
                { key: "Mod + Arrows", label: I18n.tr("Focus Navigation"), desc: I18n.tr("Move focus left / right / up / down") },
                { key: "Mod + Ctrl + Arrows", label: I18n.tr("Move Window"), desc: I18n.tr("Relocate the window within its container") },
                { key: "Mod + Alt + Arrows", label: I18n.tr("Swap Window"), desc: I18n.tr("Trade places with the window on that side") },
                { key: "Mod + Shift + Arrows", label: I18n.tr("Resize Window"), desc: I18n.tr("Grow or shrink the container by 50 px") },
                { key: "Mod + 1 .. 0", label: I18n.tr("Switch Workspace"), desc: I18n.tr("Jump to a numbered workspace") },
                { key: "Mod + Shift + 1 .. 0", label: I18n.tr("Move to Workspace"), desc: I18n.tr("Send the focused window to a workspace") },
                { key: "Mod + Scroll", label: I18n.tr("Cycle Workspaces"), desc: I18n.tr("Wheel down for the next workspace, up for the previous") },
                { key: "Mod + S", label: I18n.tr("Scratchpad Show"), desc: I18n.tr("Reveal the scratchpad window") },
                { key: "Mod + Ctrl + Shift + S", label: I18n.tr("Scratchpad Move"), desc: I18n.tr("Send the focused window to the scratchpad") },
                { key: "Mod + Escape", label: I18n.tr("Force Quit"), desc: I18n.tr("Kill an unresponsive application") }
            ]
        },
        {
            title: I18n.tr("Capture & Tools"),
            icon: "\u{f0a0f}",
            color: Design.pink,
            items: [
                { key: "Print", label: I18n.tr("Region Screenshot"), desc: I18n.tr("Select an area, copy and save it") },
                { key: "Shift + Print", label: I18n.tr("Region + Annotate"), desc: I18n.tr("Same, then open the annotation editor") },
                { key: "Mod + Print", label: I18n.tr("Full Screenshot"), desc: I18n.tr("Capture the whole output") },
                { key: "Mod + Shift + Print", label: I18n.tr("Window Screenshot"), desc: I18n.tr("Capture only the focused window (also Alt + Print)") },
                { key: "Mod + Alt + Print", label: I18n.tr("Full Screenshot"), desc: I18n.tr("The whole screen, same as Mod + Print") },
                { key: "Mod + Ctrl + Print", label: I18n.tr("Delayed Screenshot"), desc: I18n.tr("The whole screen after 5 seconds (add Shift for 10)") },
                { key: "Mod + Alt + R", label: I18n.tr("Record GIF"), desc: I18n.tr("Record a screen region to an animated GIF") },
                { key: "Mod + Shift + C", label: I18n.tr("Color Picker"), desc: I18n.tr("Eyedropper a screen pixel to the clipboard") },
                { key: "Mod + Shift + O", label: "OCR", desc: I18n.tr("Read text out of a selected screen region") },
                { key: "Mod + Shift + Q", label: I18n.tr("QR Scanner"), desc: I18n.tr("Decode a QR code shown on screen") },
                { key: "Mod + Shift + V", label: I18n.tr("Voice Memo"), desc: I18n.tr("Record a quick audio note") },
                { key: "Mod + P", label: I18n.tr("Picture in Picture"), desc: I18n.tr("Pin the focused video above other windows") },
                { key: "Mod + Shift + A", label: I18n.tr("Audio Output"), desc: I18n.tr("Cycle to the next sound output device") },
                { key: "Mod + Shift + G", label: I18n.tr("Game Mode"), desc: I18n.tr("Drop compositor effects and pin the performance governor") },
                { key: "Ctrl + Alt + L", label: I18n.tr("Lock Screen"), desc: I18n.tr("Lock the session immediately") }
            ]
        },
        {
            title: I18n.tr("Media & Hardware Keys"),
            icon: "\u{f075a}",
            color: Design.teal,
            items: [
                { key: "Volume Up / Down", label: I18n.tr("Volume"), desc: I18n.tr("Raise or lower the master output by 5%") },
                { key: "Mute", label: I18n.tr("Mute Output"), desc: I18n.tr("Toggle speakers and headphones") },
                { key: "Mic Mute", label: I18n.tr("Mute Microphone"), desc: I18n.tr("Toggle the capture device") },
                { key: "Brightness Up / Down", label: I18n.tr("Screen Brightness"), desc: I18n.tr("Adjust the laptop backlight by 5%") },
                { key: "Kbd Brightness Up / Down", label: I18n.tr("Keyboard Backlight"), desc: I18n.tr("Adjust the keyboard backlight") },
                { key: "Play / Pause", label: I18n.tr("Playback"), desc: I18n.tr("Toggle the active media player") },
                { key: "Next / Previous", label: I18n.tr("Track"), desc: I18n.tr("Skip forward or back in the playlist") }
            ]
        }
    ]

    // ── Search & Filter ──────────────────────────────────────────────────────
    Card {
        title: I18n.tr("Keyboard Shortcuts Reference")
        subtitle: I18n.tr("Complete cheatsheet of desktop keybindings and global triggers")
        icon: "\u{f11c}"
        accentColor: Design.sapphire

        Field {
            Layout.fillWidth: true
            placeholder: I18n.tr("Filter: fullscreen, volume, space…")
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
