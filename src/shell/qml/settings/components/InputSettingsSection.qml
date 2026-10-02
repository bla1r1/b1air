import QtQuick
import QtQuick.Layouts
import Quickshell
import B1air.Daemon
import Quickshell.Io
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
    // which sway includes after its defaults. Live application stays: a sway
    // command for this session, the file for the next.
    function _persist() { SwayConfig.writeInput(); }
    function _en(on) { return on ? "enabled" : "disabled"; }

    function setNaturalScroll(on) {
        Settings.set("naturalScroll", on);
        Sway.command("input type:touchpad natural_scroll " + section._en(on));
        section._persist();
    }

    function setTapToClick(on) {
        Settings.set("tapToClick", on);
        Sway.command("input type:touchpad tap " + section._en(on));
        section._persist();
    }

    // A clickpad has no buttons, so libinput decides what a press is. Its
    // default here was "button_areas" — right click only in the bottom-right
    // corner — which made a two-finger press a left click, and no right-click
    // menu anywhere could be opened the way people expect to open it.
    function setClickfinger(on) {
        Settings.set("touchpadClickfinger", on);
        Sway.command("input type:touchpad click_method " + (on ? "clickfinger" : "button_areas"));
        section._persist();
    }

    function setDwt(on) {
        Settings.set("dwt", on);
        Sway.command("input type:touchpad dwt " + section._en(on));
        section._persist();
    }

    function setPointerAccel(val) {
        Settings.set("pointerAccel", val);
        Sway.command("input type:pointer pointer_accel " + Number(val)
                     + "; input type:touchpad pointer_accel " + Number(val));
        section._persist();
    }

    function setAccelProfile(prof) {
        Settings.set("accelProfile", prof);
        Sway.command("input type:pointer accel_profile " + (prof === "flat" ? "flat" : "adaptive"));
        section._persist();
    }

    function setLeftHanded(on) {
        Settings.set("leftHanded", on);
        Sway.command("input type:pointer left_handed " + section._en(on));
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
                // Quoted: bare, sway splits a chained command at the ";"
                // before the binding sees it and runs the second half on the
                // spot. (A config file is the other way round — there the
                // quotes would be kept and the binding would fail.)
                Sway.command("bindgesture " + g[0] + " " + Sway.quote(g[1]));
            else
                Sway.command("unbindgesture " + g[0]);
        }
    }

    function _applyGestures(enabled, natural) {
        if (!enabled) {
            Sway.command("unbindgesture swipe:3:left; unbindgesture swipe:3:right");
            return;
        }
        Sway.command("bindgesture swipe:3:left workspace " + (natural ? "prev" : "next")
                     + "; bindgesture swipe:3:right workspace " + (natural ? "next" : "prev"));
    }

    // ── 1. Touchpad Card ─────────────────────────────────────────────────────
    Card {
        title: I18n.tr("Touchpad Basics")
        subtitle: I18n.tr("Scrolling direction and tapping behavior")
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
                    Label { text: I18n.tr("Natural Scrolling"); weight: Design.weight.semibold }
                    Label { text: I18n.tr("Content moves in direction of fingers (macOS style)"); role: "caption"; dim: true }
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
                    Label { text: I18n.tr("Tap to Click"); weight: Design.weight.semibold }
                    Label { text: I18n.tr("Tap touchpad with 1 finger for primary click, 2 for right click"); role: "caption"; dim: true }
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
                    Label { text: I18n.tr("Two-Finger Click for Right Click"); weight: Design.weight.semibold }
                    Label { text: section.clickfinger ? I18n.tr("Press with two fingers anywhere for a right click, three for middle")
                                                      : I18n.tr("Right click is the bottom-right corner of the pad")
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
                    Label { text: I18n.tr("Disable While Typing (DWT)"); weight: Design.weight.semibold }
                    Label { text: I18n.tr("Avoid accidental cursor moves while typing on keyboard"); role: "caption"; dim: true }
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
        title: I18n.tr("Multi-Touch Gestures")
        subtitle: I18n.tr("Three- and four-finger swipes")
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
                    Label { text: I18n.tr("3-Finger Workspace Swipe"); weight: Design.weight.semibold }
                    Label { text: I18n.tr("Swipe 3 fingers horizontally to smoothly transition between workspaces"); role: "caption"; dim: true }
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
                    Label { text: I18n.tr("Natural Gesture Direction"); weight: Design.weight.semibold }
                    Label { text: I18n.tr("Invert swipe motion to match direct touch manipulation"); role: "caption"; dim: true }
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
                    Label { text: I18n.tr("4-Finger Gestures"); weight: Design.weight.semibold }
                    Label {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        text: Sway.swayfx && Settings.workspaceOverview
                              ? I18n.tr("Up brings in the workspace overview with your fingers, down takes it away; pinch for the Launchpad; left and right carry the window to the next workspace")
                              : I18n.tr("Up opens the Launchpad, down closes it; left and right carry the window to the next workspace")
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
        title: I18n.tr("Mouse & Pointer")
        subtitle: I18n.tr("Tracking speed, acceleration profiles, and primary button")
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
                label: I18n.tr("Pointer Speed / Sensitivity")
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
                    Label { text: I18n.tr("Acceleration Profile"); weight: Design.weight.semibold }
                    Label { text: section.accelProfile === "flat" ? I18n.tr("Flat: 1:1 linear tracking") : I18n.tr("Adaptive: faster flicks travel further"); role: "caption"; dim: true }
                }

                RowLayout {
                    spacing: Design.s(Design.space.xs)

                    Pill {
                        label: I18n.tr("Flat (Linear)")
                        active: section.accelProfile === "flat"
                        onClicked: section.setAccelProfile("flat")
                    }

                    Pill {
                        label: I18n.tr("Adaptive")
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
                    Label { text: I18n.tr("Left-Handed Mouse Mode"); weight: Design.weight.semibold }
                    Label { text: I18n.tr("Swap left and right mouse buttons"); role: "caption"; dim: true }
                }

                Toggle {
                    checked: section.leftHanded
                    onToggled: section.setLeftHanded(!section.leftHanded)
                }
            }
        }
    }

    // Two fingers on a Magic Mouse's surface, as on a Mac: read by the
    // session daemon straight from the device (src/daemon/magic_mouse.cpp),
    // since no compositor sees them. The status line asks it what it finds.
    Card {
        title: I18n.tr("Magic Mouse")
        subtitle: section.magicMouseStatus
        icon: "\u{f037d}"
        accentColor: Design.teal

        Toggle {
            label: I18n.tr("Gestures on the mouse's surface")
            subtitle: I18n.tr("Swipe two fingers sideways for the next workspace; tap twice with two fingers for the workspace overview")
            checked: Settings.magicMouseGestures !== false
            onToggled: Settings.set("magicMouseGestures", Settings.magicMouseGestures === false)
        }
    }

    property string magicMouseStatus: I18n.tr("Looking for one…")
    Process {
        id: magicMouseProbe
        command: ["b1air-daemon", "magic-mouse", "status"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = this.text.trim().split("\n");
                const found = lines.filter(l => l.indexOf("/dev/input/") === 0);
                if (found.length > 0)
                    section.magicMouseStatus = I18n.tr("Connected: %1", found[0].split("\t")[1] || "Magic Mouse");
                else if (lines.some(l => l.indexOf("input group") >= 0))
                    section.magicMouseStatus = I18n.tr("None found — and input devices are not readable: log in again after install.sh adds you to the input group");
                else
                    section.magicMouseStatus = I18n.tr("None connected; pair one in Bluetooth and it is picked up at once");
            }
        }
    }
}
