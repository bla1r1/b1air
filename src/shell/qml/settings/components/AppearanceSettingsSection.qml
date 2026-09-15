import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../Ui"
import "../../Services"
import "../../Services" as Services

// =============================================================================
// Appearance & Window Tweaks
//
// Allows live customization of:
// 1. Accent colors and theme palettes
// 2. Corner radius, blur, shadows, and inactive-window dimming
//
// Gaps and border width are NOT here. They used to be, in a card duplicated
// from Window & Gaps that wrote innerGaps/outerGaps while the compositor and
// the other page read gapsInner/gapsOuter — two pages, two key names, two
// different values on screen, and only one of them doing anything. One
// setting belongs to one page.
// =============================================================================

ColumnLayout {
    id: section

    Layout.fillWidth: true
    spacing: Design.s(Design.space.lg)

    readonly property int cornerRadius: Settings.cornerRadius
    readonly property bool blurEnabled: Settings.blurEnabled
    readonly property bool shadowsEnabled: Settings.shadowsEnabled
    readonly property bool dimInactive: Settings.dimInactive




    // swaymsg changes this session; SwayConfig writes conf.d/custom_look.conf
    // so the change is still there after a logout. All four of these were
    // applied and then forgotten — see Services/SwayConfig.
    function setCornerRadius(val) {
        Settings.set("cornerRadius", val);
        Quickshell.execDetached(["swaymsg", "corner_radius", String(val)]);
        SwayConfig.writeLook();
    }

    function toggleBlur(enabled) {
        Settings.set("blurEnabled", enabled);
        Quickshell.execDetached(["swaymsg", "blur", enabled ? "enable" : "disable"]);
        SwayConfig.writeLook();
    }

    function toggleShadows(enabled) {
        Settings.set("shadowsEnabled", enabled);
        Quickshell.execDetached(["swaymsg", "shadows", enabled ? "enable" : "disable"]);
        SwayConfig.writeLook();
    }

    function toggleDimInactive(enabled) {
        Settings.set("dimInactive", enabled);
        Quickshell.execDetached(["swaymsg", "default_dim_inactive", enabled ? "0.20" : "0.0"]);
        SwayConfig.writeLook();
    }

    // ── 1. Color Scheme & Accents ────────────────────────────────────────────
    Card {
        title: "Accent & Theme"
        subtitle: "Customize the primary accent color across Quickshell and Sway"
        icon: "\u{f0376}"
        accentColor: Design.mauve

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.md)

            Label { text: "Accent Color"; role: "caption"; dim: true }

            RowLayout {
                Layout.fillWidth: true
                spacing: Design.s(Design.space.sm)

                Repeater {
                    // Each swatch previews the palette role the name selects,
                    // rather than a copy of that role's current hex. The copies
                    // happened to match today, so a palette edit would have
                    // shown one colour in the picker and applied another.
                    model: [
                        { name: "Sapphire", color: Design.sapphire },
                        { name: "Mauve",    color: Design.mauve },
                        { name: "Teal",     color: Design.teal },
                        { name: "Peach",    color: Design.peach },
                        { name: "Pink",     color: Design.pink },
                        { name: "Green",    color: Design.green },
                        { name: "Lavender", color: Design.lavender },
                        { name: "Yellow",   color: Design.yellow },
                        { name: "Red",      color: Design.red }
                    ]

                    Rectangle {
                        id: accentDot
                        required property var modelData
                        width: Design.s(32)
                        height: width
                        radius: width / 2
                        color: accentDot.modelData.color
                        border.color: (Settings.accentName === accentDot.modelData.name) ? "#ffffff" : "transparent"
                        border.width: 2

                        Behavior on scale { NumberAnimation { duration: Design.duration.fast } }
                        scale: accentDotMa.pressed ? 0.9 : (accentDotMa.containsMouse ? 1.15 : 1.0)

                        Icon {
                            visible: (Settings.accentName === accentDot.modelData.name)
                            anchors.centerIn: parent
                            text: "\u{f012c}"
                            role: "caption"
                            color: "#11111b"
                        }

                        Clickable {
                            id: accentDotMa
                            onClicked: Settings.set("accentName", accentDot.modelData.name)
                        }
                    }
                }
            }
        }
    }


    // ── 2. Compositor Effects ────────────────────────────────────────────────
    // Other applications: GTK and Qt programs are not drawn by the shell, and
    // did not follow the theme at all — they came up in stock Adwaita and a
    // fixed Kvantum theme whatever was picked. The daemon recolours them from
    // the palette, or pins them dark or light so nothing flashes white on a
    // dark desktop (or the reverse). Programs already open need a restart to
    // pick it up; GTK apps mostly follow at once.
    Card {
        title: "Other Applications"
        subtitle: "Browsers, GTK and Qt programs: follow the theme, or stay dark or light"
        icon: "\u{f0d73}"
        accentColor: Design.sapphire

        RowLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.sm)

            Repeater {
                model: [
                    { id: "auto",  label: "Follow theme" },
                    { id: "dark",  label: "Always dark" },
                    { id: "light", label: "Always light" }
                ]
                Pill {
                    required property var modelData
                    Layout.fillWidth: true
                    label: modelData.label
                    active: (Settings.appColorScheme || "auto") === modelData.id
                    onClicked: {
                        Settings.set("appColorScheme", modelData.id);
                        appsApply.restart();
                    }
                }
            }
        }

        Timer {
            id: appsApply
            interval: 400   // Settings.set() is not on disk yet at the click
            onTriggered: Quickshell.execDetached(["b1air-daemon", "appearance", "apply"])
        }
    }

    // These four are swayFX commands. Plain sway — what Debian and Ubuntu
    // ship, or an Arch install made with --no-aur — has none of them, so the
    // switches moved and nothing on screen changed. Ask the running
    // compositor (its binary, not whichever `sway` is first on PATH: swayfx
    // installs itself as `sway`).
    property bool hasSwayfx: true
    Process {
        running: true
        command: ["sh", "-c", "p=$(pgrep -x sway | head -n1); [ -n \"$p\" ] && \"$(readlink -f /proc/$p/exe)\" --version 2>&1 | grep -qi swayfx && echo yes || echo no"]
        stdout: StdioCollector { onStreamFinished: section.hasSwayfx = this.text.trim() !== "no" }
    }

    Card {
        title: "Compositor Effects"
        subtitle: section.hasSwayfx
                  ? "Corner rounding, blur, shadows, and inactive window dimming"
                  : "Needs swayFX — this session runs plain sway, which has no rounding, blur or shadows"
        icon: "\u{f02db}"
        accentColor: Design.teal

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.md)
            enabled: section.hasSwayfx
            opacity: section.hasSwayfx ? 1.0 : 0.5


            Stepper {
                label: "Corner Radius"
                valueText: section.cornerRadius + " px"
                onDecrement: section.setCornerRadius(Math.max(0, section.cornerRadius - 2))
                onIncrement: section.setCornerRadius(Math.min(24, section.cornerRadius + 2))
            }

            // Ui/Toggle, not a hand-built row around a bare Ui/Switch. Ten other
            // settings pages use the shared row; these three built their own and
            // came out visibly different — a smaller switch sitting right against
            // the label instead of at the end of the row, so the same control
            // looked like two different controls depending on which page you
            // were on.
            Toggle {
                label: "Window Blur"
                subtitle: "Frosted glass behind translucent windows and panels"
                checked: section.blurEnabled
                onToggled: section.toggleBlur(!section.blurEnabled)
            }

            Toggle {
                label: "Window Shadows"
                subtitle: "A soft shadow under every window"
                checked: section.shadowsEnabled
                onToggled: section.toggleShadows(!section.shadowsEnabled)
            }

            Toggle {
                label: "Dim Inactive Windows"
                subtitle: "Darken the windows you are not using by 20%"
                checked: section.dimInactive
                onToggled: section.toggleDimInactive(!section.dimInactive)
            }
        }
    }
}
