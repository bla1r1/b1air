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

    // ── 1. Touchpad Basics ───────────────────────────────────────────────────
    SettingsGroup {
        title: I18n.tr("Touchpad Basics")

        SwitchRow {
            title: I18n.tr("Natural Scrolling")
            checked: section.naturalScroll
            onToggled: section.setNaturalScroll(!section.naturalScroll)
        }

        SwitchRow {
            title: I18n.tr("Tap to Click")
            checked: section.tapToClick
            onToggled: section.setTapToClick(!section.tapToClick)
        }

        SwitchRow {
            title: I18n.tr("Two-Finger Click for Right Click")
            checked: section.clickfinger
            onToggled: section.setClickfinger(!section.clickfinger)
        }

        SwitchRow {
            title: I18n.tr("Disable While Typing (DWT)")
            checked: section.dwt
            onToggled: section.setDwt(!section.dwt)
        }
    }

    // ── 2. Multi-Touch Gestures ──────────────────────────────────────────────
    SettingsGroup {
        title: I18n.tr("Multi-Touch Gestures")

        SwitchRow {
            title: I18n.tr("3-Finger Workspace Swipe")
            checked: section.touchpadSwipeWorkspace
            onToggled: section.setSwipeWorkspace(!section.touchpadSwipeWorkspace)
        }

        SwitchRow {
            title: I18n.tr("Natural Gesture Direction")
            enabled: section.touchpadSwipeWorkspace || Settings.touchpadFourFinger
            checked: section.touchpadNaturalSwipe
            onToggled: section.setNaturalSwipe(!section.touchpadNaturalSwipe)
        }

        SwitchRow {
            title: I18n.tr("4-Finger Gestures")
            note: Sway.swayfx && Settings.workspaceOverview
                  ? I18n.tr("Up brings in the workspace overview with your fingers, down takes it away; pinch for the Launchpad; left and right carry the window to the next workspace")
                  : I18n.tr("Up opens the Launchpad, down closes it; left and right carry the window to the next workspace")
            checked: Settings.touchpadFourFinger === true
            onToggled: section.setFourFinger(!(Settings.touchpadFourFinger === true))
        }
    }

    // ── 3. Mouse & Pointer ───────────────────────────────────────────────────
    SettingsGroup {
        title: I18n.tr("Mouse & Pointer")

        Item {
            Layout.fillWidth: true
            Layout.leftMargin: Design.s(Design.space.rowPaddingX)
            Layout.rightMargin: Design.s(Design.space.rowPaddingX)
            Layout.topMargin: Design.s(Design.space.xs)
            Layout.bottomMargin: Design.s(Design.space.xs)
            implicitHeight: slider.implicitHeight

            Slider {
                id: slider
                anchors.fill: parent
                value: Math.round((section.pointerAccel + 1.0) * 50)
                icon: "\u{f037d}"
                label: I18n.tr("Pointer Speed / Sensitivity")
                onMoved: pct => {
                    const val = ((pct / 50) - 1.0).toFixed(2);
                    section.setPointerAccel(parseFloat(val));
                }
            }
        }

        SettingsRow {
            title: I18n.tr("Acceleration Profile")

            SegmentedControl {
                size: "sm"
                model: [
                    { id: "flat", label: I18n.tr("Flat (Linear)") },
                    { id: "adaptive", label: I18n.tr("Adaptive") }
                ]
                current: section.accelProfile
                onPicked: id => section.setAccelProfile(id)
            }
        }

        SwitchRow {
            title: I18n.tr("Left-Handed Mouse Mode")
            checked: section.leftHanded
            onToggled: section.setLeftHanded(!section.leftHanded)
        }
    }

    // ── 4. Magic Mouse ───────────────────────────────────────────────────────
    SettingsGroup {
        title: I18n.tr("Magic Mouse")
        description: section.magicMouseStatus

        SwitchRow {
            title: I18n.tr("Gestures on the mouse's surface")
            note: I18n.tr("Swipe two fingers sideways for the next workspace; tap twice with two fingers for the workspace overview")
            checked: Settings.magicMouseGestures !== false
            onToggled: Settings.set("magicMouseGestures", Settings.magicMouseGestures === false)
        }
    }

    // ── 5. Hot corners ───────────────────────────────────────────────────────
    SettingsGroup {
        id: cornersGroup
        title: I18n.tr("Hot corners")
        description: I18n.tr("The top corners are also where the top bar's first and last buttons are: a corner set here takes their outermost pixel.")

        readonly property var actions: [
            { id: "none", label: I18n.tr("Nothing") },
            { id: "overview", label: I18n.tr("Workspace overview"), swayfx: true },
            { id: "launchpad", label: I18n.tr("Launchpad") },
            { id: "notifications", label: I18n.tr("Notifications") },
            { id: "control", label: I18n.tr("Control Center") },
            { id: "lock", label: I18n.tr("Lock Screen") }
        ]

        readonly property var actionItems: cornersGroup.actions
            .filter(a => !a.swayfx || Sway.swayfx)
            .map(a => ({ id: a.id, label: a.label }))

        Repeater {
            model: [
                { key: "hotCornerTopLeft", label: I18n.tr("Top left") },
                { key: "hotCornerTopRight", label: I18n.tr("Top right") },
                { key: "hotCornerBottomLeft", label: I18n.tr("Bottom left") },
                { key: "hotCornerBottomRight", label: I18n.tr("Bottom right") }
            ]
            delegate: SettingsRow {
                id: cornerRow
                required property var modelData
                title: cornerRow.modelData.label

                Select {
                    Layout.preferredWidth: Design.s(Design.width.control)
                    model: cornersGroup.actionItems
                    current: Settings[cornerRow.modelData.key] || "none"
                    onPicked: id => Settings.set(cornerRow.modelData.key, id)
                }
            }
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
