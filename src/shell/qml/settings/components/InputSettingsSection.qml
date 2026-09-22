import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../Ui"
import "../../Services"

// =============================================================================
// Mouse & Touchpad Settings
// =============================================================================

ColumnLayout {
    id: section

    Layout.fillWidth: true
    spacing: Design.s(Design.space.lg)

    readonly property bool naturalScroll: Settings.naturalScroll
    readonly property bool tapToClick: Settings.tapToClick
    readonly property bool dwt: Settings.dwt
    readonly property bool clickfinger: Settings.touchpadClickfinger
    readonly property real pointerAccel: Settings.pointerAccel
    readonly property string accelProfile: Settings.accelProfile
    readonly property bool leftHanded: Settings.leftHanded

    readonly property bool touchpadSwipeWorkspace: Settings.touchpadSwipeWorkspace
    readonly property bool touchpadNaturalSwipe: Settings.touchpadNaturalSwipe

    // Applying and keeping.
    //
    // Every control on this page ran a `swaymsg input ...`, which changes the
    // running compositor and nothing else: sway rebuilds its input config from
    // conf.d at startup, and nothing read the saved values back. Natural
    // scrolling, tap-to-click, the pointer speed, the acceleration profile and
    // the left-handed swap all reverted at the next login, every time, with
    // the toggle still showing what the user had chosen.
    //
    // Services/SwayConfig writes the same state into conf.d/custom_input.conf,
    // which sway includes after its defaults. Live application stays: swaymsg
    // for this session, the file for the next.
    function _persist() { SwayConfig.writeInput(); }

    function setNaturalScroll(on) {
        Settings.set("naturalScroll", on);
        Quickshell.execDetached(["swaymsg", "input", "type:touchpad", "natural_scroll", on ? "enabled" : "disabled"]);
        section._persist();
    }

    function setTapToClick(on) {
        Settings.set("tapToClick", on);
        Quickshell.execDetached(["swaymsg", "input", "type:touchpad", "tap", on ? "enabled" : "disabled"]);
        section._persist();
    }

    // A clickpad has no buttons, so libinput decides what a press is. Its
    // default here was "button_areas" — right click only in the bottom-right
    // corner — which made a two-finger press a left click, and no right-click
    // menu anywhere could be opened the way people expect to open it.
    function setClickfinger(on) {
        Settings.set("touchpadClickfinger", on);
        Quickshell.execDetached(["swaymsg", "input", "type:touchpad", "click_method",
                                 on ? "clickfinger" : "button_areas"]);
        section._persist();
    }

    function setDwt(on) {
        Settings.set("dwt", on);
        Quickshell.execDetached(["swaymsg", "input", "type:touchpad", "dwt", on ? "enabled" : "disabled"]);
        section._persist();
    }

    function setPointerAccel(val) {
        Settings.set("pointerAccel", val);
        Quickshell.execDetached(["swaymsg", "input", "type:pointer", "pointer_accel", String(val)]);
        Quickshell.execDetached(["swaymsg", "input", "type:touchpad", "pointer_accel", String(val)]);
        section._persist();
    }

    function setAccelProfile(prof) {
        Settings.set("accelProfile", prof);
        Quickshell.execDetached(["swaymsg", "input", "type:pointer", "accel_profile", prof]);
        section._persist();
    }

    function setLeftHanded(on) {
        Settings.set("leftHanded", on);
        Quickshell.execDetached(["swaymsg", "input", "type:pointer", "left_handed", on ? "enabled" : "disabled"]);
        section._persist();
    }

    /**
     * Three-finger workspace swipe, and its direction.
     *
     * Both toggles only wrote a setting: no binding was ever created, in this
     * session or the next, so the gesture did nothing whichever way they were
     * set. sway takes `bindgesture` at runtime as well as from the config, so
     * the switch takes effect at once and survives the next login.
     */
    function setSwipeWorkspace(on) {
        Settings.set("touchpadSwipeWorkspace", on);
        section._applyGestures(on, Settings.touchpadNaturalSwipe);
        section._persist();
    }

    function setNaturalSwipe(on) {
        Settings.set("touchpadNaturalSwipe", on);
        section._applyGestures(Settings.touchpadSwipeWorkspace, on);
        section._applyFourFinger(Settings.touchpadFourFinger, on);
        section._persist();
    }

    function setFourFinger(on) {
        Settings.set("touchpadFourFinger", on);
        section._applyFourFinger(on, Settings.touchpadNaturalSwipe);
        section._persist();
    }

    function _applyFourFinger(enabled, natural) {
        for (const g of SwayConfig.fourFingerGestures(natural)) {
            if (enabled)
                // Quoted for swaymsg: bare, sway splits a chained command
                // at the ";" before the binding sees it and runs the second
                // half on the spot. (A config file is the other way round —
                // there the quotes would be kept and the binding would fail.)
                Quickshell.execDetached(["swaymsg", "bindgesture " + g[0] + " \"" + g[1] + "\""]);
            else
                Quickshell.execDetached(["swaymsg", "unbindgesture", g[0]]);
        }
    }

    function _applyGestures(enabled, natural) {
        if (!enabled) {
            Quickshell.execDetached(["swaymsg", "unbindgesture", "swipe:3:left"]);
            Quickshell.execDetached(["swaymsg", "unbindgesture", "swipe:3:right"]);
            return;
        }
        Quickshell.execDetached(["swaymsg", "bindgesture", "swipe:3:left", "workspace",
                                 natural ? "prev" : "next"]);
        Quickshell.execDetached(["swaymsg", "bindgesture", "swipe:3:right", "workspace",
                                 natural ? "next" : "prev"]);
    }

    // ── 1. Touchpad Card ─────────────────────────────────────────────────────
    Card {
        title: "Touchpad Basics"
        subtitle: "Scrolling direction and tapping behavior"
        icon: "\u{f0523}"
        accentColor: Design.peach

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.md)

            // Natural Scrolling
            RowLayout {
                Layout.fillWidth: true
                spacing: Design.s(Design.space.md)

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Label { text: "Natural Scrolling"; weight: Design.weight.semibold }
                    Label { text: "Content moves in direction of fingers (macOS style)"; role: "caption"; dim: true }
                }

                Toggle {
                    checked: section.naturalScroll
                    onToggled: section.setNaturalScroll(!section.naturalScroll)
                }
            }

            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Design.tint(Design.line, 0.4) }

            // Tap to click
            RowLayout {
                Layout.fillWidth: true
                spacing: Design.s(Design.space.md)

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Label { text: "Tap to Click"; weight: Design.weight.semibold }
                    Label { text: "Tap touchpad with 1 finger for primary click, 2 for right click"; role: "caption"; dim: true }
                }

                Toggle {
                    checked: section.tapToClick
                    onToggled: section.setTapToClick(!section.tapToClick)
                }
            }

            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Design.tint(Design.line, 0.4) }

            RowLayout {
                Layout.fillWidth: true
                spacing: Design.s(Design.space.md)

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Label { text: "Two-Finger Click for Right Click"; weight: Design.weight.semibold }
                    Label { text: section.clickfinger ? "Press with two fingers anywhere for a right click, three for middle"
                                                      : "Right click is the bottom-right corner of the pad"
                            role: "caption"; dim: true }
                }

                Toggle {
                    checked: section.clickfinger
                    onToggled: section.setClickfinger(!section.clickfinger)
                }
            }

            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Design.tint(Design.line, 0.4) }

            // Disable while typing
            RowLayout {
                Layout.fillWidth: true
                spacing: Design.s(Design.space.md)

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Label { text: "Disable While Typing (DWT)"; weight: Design.weight.semibold }
                    Label { text: "Avoid accidental cursor moves while typing on keyboard"; role: "caption"; dim: true }
                }

                Toggle {
                    checked: section.dwt
                    onToggled: section.setDwt(!section.dwt)
                }
            }
        }
    }

    // ── 2. Multi-Touch Gestures ──────────────────────────────────────────────
    Card {
        title: "Multi-Touch Gestures"
        subtitle: "Three- and four-finger swipes"
        icon: "\u{f0048}"
        accentColor: Design.teal

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.md)

            RowLayout {
                Layout.fillWidth: true
                spacing: Design.s(Design.space.md)

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Label { text: "3-Finger Workspace Swipe"; weight: Design.weight.semibold }
                    Label { text: "Swipe 3 fingers horizontally to smoothly transition between workspaces"; role: "caption"; dim: true }
                }

                Toggle {
                    checked: section.touchpadSwipeWorkspace
                    onToggled: section.setSwipeWorkspace(!section.touchpadSwipeWorkspace)
                }
            }

            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Design.tint(Design.line, 0.4) }

            RowLayout {
                Layout.fillWidth: true
                spacing: Design.s(Design.space.md)

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Label { text: "Natural Gesture Direction"; weight: Design.weight.semibold }
                    Label { text: "Invert swipe motion to match direct touch manipulation"; role: "caption"; dim: true }
                }

                Toggle {
                    checked: section.touchpadNaturalSwipe
                    enabled: section.touchpadSwipeWorkspace || Settings.touchpadFourFinger
                    onToggled: section.setNaturalSwipe(!section.touchpadNaturalSwipe)
                }
            }

            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Design.tint(Design.line, 0.4) }

            RowLayout {
                Layout.fillWidth: true
                spacing: Design.s(Design.space.md)

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Label { text: "4-Finger Gestures"; weight: Design.weight.semibold }
                    Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: "Up opens the Launchpad, down closes it; left and right carry the window to the next workspace"
                        role: "caption"
                        dim: true
                    }
                }

                Toggle {
                    checked: Settings.touchpadFourFinger === true
                    onToggled: section.setFourFinger(!(Settings.touchpadFourFinger === true))
                }
            }

            // "Pinch to Zoom — allow 2-finger pinch in browsers and document
            // viewers" was here. It wrote a setting nothing read, and there was
            // nothing for it to read: a compositor forwards pinch to the
            // focused client unless something binds it, and nothing binds it
            // here, so pinch already reaches the browser and the toggle
            // described a state that is simply always on.
        }
    }

    // ── 3. Mouse & Pointer Card ──────────────────────────────────────────────
    Card {
        title: "Mouse & Pointer"
        subtitle: "Tracking speed, acceleration profiles, and primary button"
        icon: "\u{f037d}"
        accentColor: Design.sapphire

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.md)

            // Ui/Slider carries its own label and percentage — that is how the
            // Control Center's brightness and volume rows are built. This one
            // put a hand-made header above it with the same number in it, so
            // the page showed "50%" twice, once over the slider and once
            // inside it.
            Slider {
                Layout.fillWidth: true
                Layout.preferredHeight: Design.s(Design.size.ctl)
                value: Math.round((section.pointerAccel + 1.0) * 50)
                tone: Design.sapphire
                icon: "\u{f037d}"
                label: "Pointer Speed / Sensitivity"
                onMoved: pct => {
                    const val = ((pct / 50) - 1.0).toFixed(2);
                    section.setPointerAccel(parseFloat(val));
                }
            }

            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Design.tint(Design.line, 0.4) }

            // Acceleration Profile
            RowLayout {
                Layout.fillWidth: true
                spacing: Design.s(Design.space.md)

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Label { text: "Acceleration Profile"; weight: Design.weight.semibold }
                    Label { text: section.accelProfile === "flat" ? "Flat: 1:1 linear tracking" : "Adaptive: faster flicks travel further"; role: "caption"; dim: true }
                }

                RowLayout {
                    spacing: Design.s(Design.space.xs)

                    Pill {
                        label: "Flat (Linear)"
                        active: section.accelProfile === "flat"
                        onClicked: section.setAccelProfile("flat")
                    }

                    Pill {
                        label: "Adaptive"
                        active: section.accelProfile === "adaptive"
                        onClicked: section.setAccelProfile("adaptive")
                    }
                }
            }

            Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Design.tint(Design.line, 0.4) }

            // Left-handed Mode
            RowLayout {
                Layout.fillWidth: true
                spacing: Design.s(Design.space.md)

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Label { text: "Left-Handed Mouse Mode"; weight: Design.weight.semibold }
                    Label { text: "Swap left and right mouse buttons"; role: "caption"; dim: true }
                }

                Toggle {
                    checked: section.leftHanded
                    onToggled: section.setLeftHanded(!section.leftHanded)
                }
            }
        }
    }
}
