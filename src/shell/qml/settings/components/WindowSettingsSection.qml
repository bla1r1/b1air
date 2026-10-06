import QtQuick
import QtQuick.Layouts
import Quickshell
import B1air.Daemon
import "../../Ui"
import "../../Services"

// =============================================================================
// Window Management & Gaps
//
// Live controls for:
// 1. Inner and Outer Gaps
// 2. Window Borders and Smart Borders
// 3. Smart Gaps and Inactive Window Opacity
// =============================================================================

ColumnLayout {
    id: section

    Layout.fillWidth: true
    spacing: Design.s(Design.space.lg)

    readonly property int gapsInner: Settings.gapsInner
    readonly property int gapsOuter: Settings.gapsOuter
    readonly property int borderWidth: Settings.borderWidth
    readonly property bool smartBorders: Settings.smartBorders
    readonly property bool smartGaps: Settings.smartGaps
    readonly property bool autotiling: Settings.autotiling
    readonly property int cornerRadius: Settings.cornerRadius
    readonly property bool blurEnabled: Settings.blurEnabled
    readonly property bool shadowsEnabled: Settings.shadowsEnabled
    // `inactiveOpacity` was read here into a property no control bound to and
    // nothing else ever looked at; it is gone from the schema — see the note
    // in Services/SwayConfig for why it could not simply be adopted.

    // swaymsg changes this session; SwayConfig writes conf.d/custom_look.conf
    // so the change is still there after a logout. Every one of these settings
    // was applied and then forgotten — see Services/SwayConfig.
    function setGapsInner(val) {
        Settings.set("gapsInner", val);
        Sway.command("gaps inner all set " + Number(val));
        SwayConfig.writeLook();
    }

    function setGapsOuter(val) {
        Settings.set("gapsOuter", val);
        Sway.command("gaps outer all set " + Number(val));
        SwayConfig.writeLook();
    }

    function setBorderWidth(val) {
        Settings.set("borderWidth", val);
        Sway.command("default_border pixel " + Number(val));
        SwayConfig.writeLook();
    }

    function toggleSmartBorders(val) {
        Settings.set("smartBorders", val);
        Sway.command("smart_borders " + (val ? "on" : "off"));
        SwayConfig.writeLook();
    }

    function toggleSmartGaps(val) {
        Settings.set("smartGaps", val);
        Sway.command("smart_gaps " + (val ? "on" : "off"));
        SwayConfig.writeLook();
    }

    // ── 1. Gaps Configuration ────────────────────────────────────────────────
    // The daemon reads this on every focus change, so it takes effect from the
    // next window opened — nothing to reload.
    function setCornerRadius(val) {
        Settings.set("cornerRadius", val);
        Sway.command("corner_radius " + Number(val));
        SwayConfig.writeLook();
    }

    function toggleBlur(enabled) {
        Settings.set("blurEnabled", enabled);
        Sway.command("blur " + (enabled ? "enable" : "disable"));
        SwayConfig.writeLook();
    }

    function toggleShadows(enabled) {
        Settings.set("shadowsEnabled", enabled);
        Sway.command("shadows " + (enabled ? "enable" : "disable"));
        SwayConfig.writeLook();
    }

    function toggleDimInactive(enabled) {
        Settings.set("dimInactive", enabled);
        Sway.command("default_dim_inactive " + (enabled ? "0.20" : "0.0"));
        SwayConfig.writeLook();
    }

    // ── 1. Color Scheme & Accents ────────────────────────────────────────────
    Card {
        title: I18n.tr("Tiling")
        subtitle: I18n.tr("How a new window finds its place")
        icon: "\u{f0e5e}"
        accentColor: Design.sapphire

        Toggle {
            label: I18n.tr("Automatic split (like Hyprland)")
            subtitle: section.autotiling
                ? I18n.tr("Each new window halves the focused one along its longer side, in a spiral")
                : I18n.tr("New windows line up in one row; Mod+J and Mod+Shift+I change the direction")
            checked: section.autotiling
            onToggled: Settings.set("autotiling", !section.autotiling)
        }
    }

    Card {
        title: I18n.tr("Window Spacing (Gaps)")
        subtitle: I18n.tr("Adjust the inner and outer spacing between tiled windows")
        icon: "\u{f0379}"
        accentColor: Design.sapphire

        Stepper {
            label: I18n.tr("Inner Gaps (between windows)")
            valueText: section.gapsInner + " px"
            onDecrement: section.setGapsInner(Math.max(0, section.gapsInner - 2))
            onIncrement: section.setGapsInner(Math.min(40, section.gapsInner + 2))
        }

        Stepper {
            label: I18n.tr("Outer Gaps (screen edges)")
            valueText: section.gapsOuter + " px"
            onDecrement: section.setGapsOuter(Math.max(0, section.gapsOuter - 2))
            onIncrement: section.setGapsOuter(Math.min(40, section.gapsOuter + 2))
        }
    }

    // ── 2. Borders & Smart Behavior ──────────────────────────────────────────
    Card {
        title: I18n.tr("Borders & Layout Rules")
        subtitle: I18n.tr("Window border styling and smart fullscreen/single window behaviors")
        icon: "\u{f016d}"
        accentColor: Design.mauve

        Stepper {
            label: I18n.tr("Border Width")
            valueText: section.borderWidth + " px"
            onDecrement: section.setBorderWidth(Math.max(0, section.borderWidth - 1))
            onIncrement: section.setBorderWidth(Math.min(8, section.borderWidth + 1))
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.md)

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Design.s(2)
                Label { text: I18n.tr("Smart Borders"); weight: Design.weight.semibold }
                Label { text: I18n.tr("Automatically hide window borders when only one window is open"); role: "caption"; dim: true }
            }

            Toggle {
                checked: section.smartBorders
                onToggled: section.toggleSmartBorders(!section.smartBorders)
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.md)

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Design.s(2)
                Label { text: I18n.tr("Smart Gaps"); weight: Design.weight.semibold }
                Label { text: I18n.tr("Remove outer gaps when a workspace has only one window"); role: "caption"; dim: true }
            }

            Toggle {
                checked: section.smartGaps
                onToggled: section.toggleSmartGaps(!section.smartGaps)
            }
        }
    }

    readonly property bool hasSwayfx: Sway.swayfx

    Card {
        title: I18n.tr("Effects")
        subtitle: section.hasSwayfx
                  ? I18n.tr("Rounded corners, blur and shadows")
                  : I18n.tr("Needs swayFX — this session runs plain sway, which has no rounding, blur or shadows")
        icon: "\u{f02db}"
        accentColor: Design.teal

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.md)
            enabled: section.hasSwayfx
            opacity: section.hasSwayfx ? 1.0 : 0.5


            Stepper {
                label: I18n.tr("Corner Radius")
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
                label: I18n.tr("Window Blur")
                subtitle: I18n.tr("Frosted glass behind translucent windows and panels")
                checked: section.blurEnabled
                onToggled: section.toggleBlur(!section.blurEnabled)
            }

            Toggle {
                label: I18n.tr("Window Shadows")
                subtitle: I18n.tr("A soft shadow under every window")
                checked: section.shadowsEnabled
                onToggled: section.toggleShadows(!section.shadowsEnabled)
            }

        }
    }

    Card {
        title: I18n.tr("Unfocused windows")
        subtitle: I18n.tr("Darker or see-through, so the focused one stands out")
        icon: "\u{f0208}"
        accentColor: Design.blue

        Toggle {
            label: I18n.tr("Dim Inactive Windows")
            subtitle: I18n.tr("Darken the windows you are not using by 20%")
            checked: Settings.dimInactive
            onToggled: section.toggleDimInactive(!Settings.dimInactive)
        }

        Toggle {
            label: I18n.tr("Fade unfocused windows")
            checked: Settings.inactiveOpacityPercent < 100
            onToggled: Settings.set("inactiveOpacityPercent", Settings.inactiveOpacityPercent < 100 ? 100 : 50)
        }
        Slider {
            Layout.fillWidth: true
            visible: Settings.inactiveOpacityPercent < 100
            label: I18n.tr("Opacity")
            minimum: 20
            maximum: 95
            value: Settings.inactiveOpacityPercent
            tone: Design.blue
            onMoved: pct => Settings.set("inactiveOpacityPercent", pct)
        }
    }

    Card {
        title: I18n.tr("Special workspace")
        subtitle: I18n.tr("A workspace of its own, called up over the one in front of you")
        icon: "\u{f0bc8}"
        accentColor: Design.peach

        Toggle {
            label: I18n.tr("Mod+S calls up the special workspace")
            subtitle: Settings.specialWorkspace
                ? I18n.tr("Mod+S shows and hides it; Mod+Ctrl+Shift+S sends the focused window there")
                : I18n.tr("Mod+S shows the scratchpad instead")
            checked: Settings.specialWorkspace
            onToggled: Settings.set("specialWorkspace", !Settings.specialWorkspace)
        }
    }

    Card {
        title: I18n.tr("Workspace overview")
        subtitle: I18n.tr("Every workspace of the screen side by side, live")
        icon: "\u{f0570}"
        accentColor: Design.green

        Toggle {
            label: I18n.tr("Mod+O shows the overview")
            subtitle: I18n.tr("Click a workspace, or pick one with the arrows and Enter, to go there; Escape leaves. Four fingers up on the touchpad bring it in too")
            checked: Settings.workspaceOverview
            onToggled: Settings.set("workspaceOverview", !Settings.workspaceOverview)
        }
    }

    Label {
        Layout.fillWidth: true
        visible: !Sway.swayfx
        text: I18n.tr("The compositor running now is plain sway: effects and the special workspace and overview take effect with b1air's own swayFX.")
        role: "caption"; color: Design.peach; wrapMode: Text.WordWrap
    }
}
