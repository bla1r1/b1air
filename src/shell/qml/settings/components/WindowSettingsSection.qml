import QtQuick
import QtQuick.Layouts
import Quickshell
import B1air.Daemon
import "../../Ui"
import "../../Services"

// =============================================================================
// Window Management, Tiling & Gaps
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
    readonly property bool hasSwayfx: Sway.swayfx

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

    // ── Tiling ───────────────────────────────────────────────────────────────
    SettingsGroup {
        title: I18n.tr("Tiling")

        SwitchRow {
            label: I18n.tr("Automatic split (like Hyprland)")
            note: section.autotiling
                ? I18n.tr("Each new window halves the focused one along its longer side, in a spiral")
                : I18n.tr("New windows line up in one row; Mod+J and Mod+Shift+I change the direction")
            checked: section.autotiling
            onToggled: Settings.set("autotiling", !section.autotiling)
        }
    }

    // ── Spacing (Gaps) ───────────────────────────────────────────────────────
    SettingsGroup {
        title: I18n.tr("Window Spacing (Gaps)")

        SettingsRow {
            label: I18n.tr("Inner Gaps (between windows)")

            Stepper {
                valueText: section.gapsInner + " px"
                onDecrement: section.setGapsInner(Math.max(0, section.gapsInner - 2))
                onIncrement: section.setGapsInner(Math.min(40, section.gapsInner + 2))
            }
        }

        SettingsRow {
            label: I18n.tr("Outer Gaps (screen edges)")

            Stepper {
                valueText: section.gapsOuter + " px"
                onDecrement: section.setGapsOuter(Math.max(0, section.gapsOuter - 2))
                onIncrement: section.setGapsOuter(Math.min(40, section.gapsOuter + 2))
            }
        }
    }

    // ── Borders & Layout Rules ───────────────────────────────────────────────
    SettingsGroup {
        title: I18n.tr("Borders & Layout Rules")

        SettingsRow {
            label: I18n.tr("Border Width")

            Stepper {
                valueText: section.borderWidth + " px"
                onDecrement: section.setBorderWidth(Math.max(0, section.borderWidth - 1))
                onIncrement: section.setBorderWidth(Math.min(8, section.borderWidth + 1))
            }
        }

        SwitchRow {
            label: I18n.tr("Smart Borders")
            note: I18n.tr("Hide border when there is only one window")
            checked: section.smartBorders
            onToggled: section.toggleSmartBorders(!section.smartBorders)
        }

        SwitchRow {
            label: I18n.tr("Smart Gaps")
            note: I18n.tr("Remove gaps when there is only one window")
            checked: section.smartGaps
            onToggled: section.toggleSmartGaps(!section.smartGaps)
        }
    }

    // ── Effects ──────────────────────────────────────────────────────────────
    SettingsGroup {
        title: I18n.tr("Effects")
        description: section.hasSwayfx
            ? I18n.tr("Rounded corners, blur and shadows")
            : I18n.tr("Needs swayFX — this session runs plain sway, which has no rounding, blur or shadows")
        enabled: section.hasSwayfx
        opacity: section.hasSwayfx ? 1.0 : Design.opacity.disabled

        SettingsRow {
            label: I18n.tr("Corner Radius")

            Stepper {
                valueText: section.cornerRadius + " px"
                onDecrement: section.setCornerRadius(Math.max(0, section.cornerRadius - 2))
                onIncrement: section.setCornerRadius(Math.min(24, section.cornerRadius + 2))
            }
        }

        SwitchRow {
            label: I18n.tr("Window Blur")
            note: I18n.tr("Frosted glass behind translucent windows and panels")
            checked: section.blurEnabled
            onToggled: section.toggleBlur(!section.blurEnabled)
        }

        SwitchRow {
            label: I18n.tr("Window Shadows")
            note: I18n.tr("A soft shadow under every window")
            checked: section.shadowsEnabled
            onToggled: section.toggleShadows(!section.shadowsEnabled)
        }
    }

    // ── Unfocused windows ────────────────────────────────────────────────────
    SettingsGroup {
        title: I18n.tr("Unfocused Windows")

        SwitchRow {
            label: I18n.tr("Dim Inactive Windows")
            note: I18n.tr("Darken the windows you are not using by 20%")
            checked: Settings.dimInactive
            onToggled: section.toggleDimInactive(!Settings.dimInactive)
        }

        SwitchRow {
            label: I18n.tr("Fade unfocused windows")
            note: Settings.inactiveOpacityPercent < 100 ? I18n.tr("Opacity %1%", Settings.inactiveOpacityPercent) : ""
            checked: Settings.inactiveOpacityPercent < 100
            onToggled: Settings.set("inactiveOpacityPercent", Settings.inactiveOpacityPercent < 100 ? 100 : 50)
        }

        SettingsRow {
            visible: Settings.inactiveOpacityPercent < 100
            label: I18n.tr("Opacity")
            note: I18n.tr("%1%", Settings.inactiveOpacityPercent)

            Slider {
                Layout.preferredWidth: Design.s(Design.width.control)
                minimum: 20
                maximum: 95
                value: Settings.inactiveOpacityPercent
                onMoved: pct => Settings.set("inactiveOpacityPercent", Math.round(pct))
            }
        }
    }

    // ── Workspaces & Navigation ──────────────────────────────────────────────
    SettingsGroup {
        title: I18n.tr("Workspaces & Navigation")

        SwitchRow {
            label: I18n.tr("Mod+S calls up the special workspace")
            note: Settings.specialWorkspace
                ? I18n.tr("Mod+S shows and hides it; Mod+Ctrl+Shift+S sends the focused window there")
                : I18n.tr("Mod+S shows the scratchpad instead")
            checked: Settings.specialWorkspace
            onToggled: Settings.set("specialWorkspace", !Settings.specialWorkspace)
        }

        SwitchRow {
            label: I18n.tr("Mod+O shows the overview")
            note: I18n.tr("Click a workspace, or pick one with arrows and Enter; drag a window onto another to move it; Escape leaves. 4 fingers swipe on touchpad brings it in")
            checked: Settings.workspaceOverview
            onToggled: Settings.set("workspaceOverview", !Settings.workspaceOverview)
        }

        SwitchRow {
            label: I18n.tr("Snap floating windows to the screen's edges")
            note: I18n.tr("Drag a window to the left or right edge for half the screen, near a corner for a quarter, to the top for all of it")
            checked: Settings.windowSnap
            onToggled: Settings.set("windowSnap", !Settings.windowSnap)
        }
    }

    InlineStatus {
        visible: !Sway.swayfx
        status: "warning"
        text: I18n.tr("The compositor running now is plain sway: effects and the special workspace and overview take effect with b1air's own swayFX.")
    }
}
