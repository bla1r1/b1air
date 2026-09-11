import QtQuick
import QtQuick.Layouts
import Quickshell
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
    // `inactiveOpacity` was read here into a property no control bound to and
    // nothing else ever looked at; it is gone from the schema — see the note
    // in Services/SwayConfig for why it could not simply be adopted.

    // swaymsg changes this session; SwayConfig writes conf.d/custom_look.conf
    // so the change is still there after a logout. Every one of these settings
    // was applied and then forgotten — see Services/SwayConfig.
    function setGapsInner(val) {
        Settings.set("gapsInner", val);
        Quickshell.execDetached(["swaymsg", "gaps", "inner", "all", "set", String(val)]);
        SwayConfig.writeLook();
    }

    function setGapsOuter(val) {
        Settings.set("gapsOuter", val);
        Quickshell.execDetached(["swaymsg", "gaps", "outer", "all", "set", String(val)]);
        SwayConfig.writeLook();
    }

    function setBorderWidth(val) {
        Settings.set("borderWidth", val);
        Quickshell.execDetached(["swaymsg", "default_border", "pixel", String(val)]);
        SwayConfig.writeLook();
    }

    function toggleSmartBorders(val) {
        Settings.set("smartBorders", val);
        Quickshell.execDetached(["swaymsg", "smart_borders", val ? "on" : "off"]);
        SwayConfig.writeLook();
    }

    function toggleSmartGaps(val) {
        Settings.set("smartGaps", val);
        Quickshell.execDetached(["swaymsg", "smart_gaps", val ? "on" : "off"]);
        SwayConfig.writeLook();
    }

    // ── 1. Gaps Configuration ────────────────────────────────────────────────
    // The daemon reads this on every focus change, so it takes effect from the
    // next window opened — nothing to reload.
    Card {
        title: "Tiling"
        subtitle: "How a new window finds its place"
        icon: "\u{f0e5e}"
        accentColor: Design.sapphire

        Toggle {
            label: "Automatic split (like Hyprland)"
            subtitle: section.autotiling
                ? "Each new window halves the focused one along its longer side, in a spiral"
                : "New windows line up in one row; Mod+J and Mod+Shift+I change the direction"
            checked: section.autotiling
            onToggled: Settings.set("autotiling", !section.autotiling)
        }
    }

    Card {
        title: "Window Spacing (Gaps)"
        subtitle: "Adjust the inner and outer spacing between tiled windows"
        icon: "\u{f0379}"
        accentColor: Design.sapphire

        Stepper {
            label: "Inner Gaps (between windows)"
            valueText: section.gapsInner + " px"
            onDecrement: section.setGapsInner(Math.max(0, section.gapsInner - 2))
            onIncrement: section.setGapsInner(Math.min(40, section.gapsInner + 2))
        }

        Stepper {
            label: "Outer Gaps (screen edges)"
            valueText: section.gapsOuter + " px"
            onDecrement: section.setGapsOuter(Math.max(0, section.gapsOuter - 2))
            onIncrement: section.setGapsOuter(Math.min(40, section.gapsOuter + 2))
        }
    }

    // ── 2. Borders & Smart Behavior ──────────────────────────────────────────
    Card {
        title: "Borders & Layout Rules"
        subtitle: "Window border styling and smart fullscreen/single window behaviors"
        icon: "\u{f016d}"
        accentColor: Design.mauve

        Stepper {
            label: "Border Width"
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
                Label { text: "Smart Borders"; weight: Design.weight.semibold }
                Label { text: "Automatically hide window borders when only one window is open"; role: "caption"; dim: true }
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
                Label { text: "Smart Gaps"; weight: Design.weight.semibold }
                Label { text: "Remove outer gaps when a workspace has only one window"; role: "caption"; dim: true }
            }

            Toggle {
                checked: section.smartGaps
                onToggled: section.toggleSmartGaps(!section.smartGaps)
            }
        }
    }
}
