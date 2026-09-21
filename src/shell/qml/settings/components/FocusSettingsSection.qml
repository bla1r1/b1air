import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell.Io
import "../../Ui"
import "../../Services"

// =============================================================================
// Screen Time & Focus Settings Section
// =============================================================================

ColumnLayout {
    id: section
    spacing: Design.s(Design.space.lg)

    property int workDuration: Settings.focusWorkDuration || 25
    property int shortBreakDuration: Settings.focusShortBreak || 5
    property int longBreakDuration: Settings.focusLongBreak || 15
    property int dailyGoalHours: Settings.dailyScreenTimeGoal || 8
    property bool autoDnd: Settings.focusAutoDnd !== undefined ? Settings.focusAutoDnd : true
    property bool breakReminders: Settings.focusBreakReminders !== undefined ? Settings.focusBreakReminders : true
    property bool daemonAutoStart: Settings.focusDaemonAutoStart !== undefined ? Settings.focusDaemonAutoStart : true

    property var notifRules: Settings.notificationRules || {}

    // ── Screen time ──────────────────────────────────────────────────────────
    //
    // Both figures below used to come from Power.upHours/upMins — the system's
    // uptime. That is not screen time and not "today": a machine left running
    // overnight reported a full day of use nobody spent, and the daily-goal
    // percentage was computed from the same number. The FocusTime window,
    // reading the same day out of the same database, showed 3h 57m while this
    // card said 5h 10m.
    //
    // This is the tracker's own total for today, which is what the card claims
    // to be showing.
    property int screenSeconds: 0

    readonly property int screenHours: Math.floor(section.screenSeconds / 3600)
    readonly property int screenMins: Math.floor((section.screenSeconds % 3600) / 60)

    Process {
        id: screenTimeQuery
        running: true
        command: ["b1air-daemon", "focustime"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(this.text);
                    if (typeof d.total === "number")
                        section.screenSeconds = d.total;
                } catch (e) {
                    // Daemon not up yet. Keep the last figure rather than
                    // flashing a zero at someone reading the page.
                }
            }
        }
    }

    // Cheap and only while this page is on screen: one process a minute.
    Timer {
        interval: 60000
        repeat: true
        running: section.visible
        onTriggered: {
            screenTimeQuery.running = false;
            screenTimeQuery.running = true;
        }
    }

    function isRuleEnabled(app) {
        if (!app) return true;
        let key = app.toLowerCase().trim();
        return section.notifRules && section.notifRules[key] !== undefined ? section.notifRules[key] : true;
    }

    function toggleRule(app) {
        if (!app) return;
        let key = app.toLowerCase().trim();
        var rules = Object.assign({}, section.notifRules || {});
        rules[key] = !section.isRuleEnabled(key);
        section.notifRules = rules;
        Settings.set("notificationRules", rules);
    }

    // Dynamically detected notification sources
    readonly property var activeApps: {
        let _t = Notifications.trackedApps;
        let _h = Notifications.history.count;
        let list = [];
        let seen = {};

        if (Notifications.trackedApps && Notifications.trackedApps.length > 0) {
            for (let app of Notifications.trackedApps) {
                let key = (app.name || "").toLowerCase().trim();
                if (key && !seen[key]) {
                    seen[key] = true;
                    list.push({ name: app.name, icon: app.icon || "", subtitle: "Active notification source" });
                }
            }
        }

        for (let i = 0; i < Notifications.history.count; i++) {
            let item = Notifications.history.get(i);
            let key = (item.appName || "").toLowerCase().trim();
            if (key && !seen[key]) {
                seen[key] = true;
                list.push({ name: item.appName, icon: item.icon || "", subtitle: "Recent notification in history" });
            }
        }

        if (list.length === 0) {
            list.push({ name: "System", icon: "", subtitle: "System and hardware alerts" });
        }

        return list;
    }

    // (The page title is in the Settings header bar now.)

    // ── 2. Today's Wellbeing Overview ────────────────────────────────────────
    Card {
        title: "Today's Activity"
        subtitle: "Real-time summary of your computer usage and focus intervals"
        icon: "\u{f051e}"
        accentColor: Design.teal

        RowLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.md)

            // Screen time stat box
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Design.s(72)
                radius: Design.s(Design.radius.card)
                color: Design.sunken

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 2
                    Label {
                        text: "Screen Time Today"
                        role: "caption"
                        dim: true
                    }
                    Label {
                        text: (section.screenHours > 0 ? section.screenHours + "h " : "") + section.screenMins + "m"
                        role: "subhead"
                        weight: Design.weight.bold
                        color: Design.teal
                    }
                }
            }

            // Daily goal progress box
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Design.s(72)
                radius: Design.s(Design.radius.card)
                color: Design.sunken

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 2
                    Label {
                        text: "Daily Goal (" + section.dailyGoalHours + "h)"
                        role: "caption"
                        dim: true
                    }
                    Label {
                        readonly property real pct: Math.min(100, Math.round((section.screenSeconds / (section.dailyGoalHours * 3600)) * 100))
                        text: pct + "% used"
                        role: "subhead"
                        weight: Design.weight.bold
                        color: pct > 100 ? Design.danger : Design.sapphire
                    }
                }
            }

            // Focus status box
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Design.s(72)
                radius: Design.s(Design.radius.card)
                color: Design.sunken

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 2
                    Label {
                        text: "Focus Status"
                        role: "caption"
                        dim: true
                    }
                    Label {
                        // Say which of the reasons is holding banners back.
                        text: Focus.wantsDnd ? "Focusing (DND)"
                            : Notifications.quietHours ? "Quiet hours"
                            : Notifications.dnd ? "Do Not Disturb" : "Active"
                        role: "subhead"
                        weight: Design.weight.bold
                        color: Notifications.dnd ? Design.peach : Design.green
                    }
                }
            }
        }
    }

    // ── 3. Application Notification Filters ──────────────────────────────────
    Card {
        title: "Application Notification Filters"
        subtitle: "Control banner popups and sound alerts for individual apps"
        icon: "\u{f0f3}"
        accentColor: Design.mauve

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.md)

            Repeater {
                model: section.activeApps

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Design.s(Design.space.xs)

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Design.s(Design.space.md)

                        Rectangle {
                            width: Design.s(32); height: Design.s(32)
                            radius: Design.s(Design.radius.ctl)
                            color: Design.sunken

                            Icon {
                                anchors.centerIn: parent
                                text: "\u{f0f3}"
                                role: "caption"
                                color: section.isRuleEnabled(modelData.name) ? Design.accent : Design.textDim
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Design.s(2)

                            Label {
                                text: modelData.name
                                weight: Design.weight.semibold
                            }

                            Label {
                                text: modelData.subtitle
                                role: "caption"
                                dim: true
                            }
                        }

                        Toggle {
                            checked: section.isRuleEnabled(modelData.name)
                            onToggled: section.toggleRule(modelData.name)
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 1
                        color: Design.tint(Design.line, 0.4)
                        visible: index < section.activeApps.length - 1
                    }
                }
            }
        }
    }

    // ── 4. Pomodoro & Interval Durations ─────────────────────────────────────
    Card {
        title: "Focus & Break Intervals"
        subtitle: "Customize work cycles and rest duration for FocusTime timer"
        icon: "\u{f0520}"
        accentColor: Design.sapphire

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.sm)

            Stepper {
                label: "Focus Work Duration"
                valueText: section.workDuration + " min"
                onDecrement: {
                    const v = Math.max(5, section.workDuration - 5);
                    section.workDuration = v;
                    Settings.set("focusWorkDuration", v);
                }
                onIncrement: {
                    const v = Math.min(120, section.workDuration + 5);
                    section.workDuration = v;
                    Settings.set("focusWorkDuration", v);
                }
            }

            Stepper {
                label: "Short Break Duration"
                valueText: section.shortBreakDuration + " min"
                onDecrement: {
                    const v = Math.max(1, section.shortBreakDuration - 1);
                    section.shortBreakDuration = v;
                    Settings.set("focusShortBreak", v);
                }
                onIncrement: {
                    const v = Math.min(30, section.shortBreakDuration + 1);
                    section.shortBreakDuration = v;
                    Settings.set("focusShortBreak", v);
                }
            }

            Stepper {
                label: "Long Break Duration"
                valueText: section.longBreakDuration + " min"
                onDecrement: {
                    const v = Math.max(5, section.longBreakDuration - 5);
                    section.longBreakDuration = v;
                    Settings.set("focusLongBreak", v);
                }
                onIncrement: {
                    const v = Math.min(60, section.longBreakDuration + 5);
                    section.longBreakDuration = v;
                    Settings.set("focusLongBreak", v);
                }
            }

            Stepper {
                label: "Daily Screen Time Limit Goal"
                valueText: section.dailyGoalHours + " hours"
                onDecrement: {
                    const v = Math.max(1, section.dailyGoalHours - 1);
                    section.dailyGoalHours = v;
                    Settings.set("dailyScreenTimeGoal", v);
                }
                onIncrement: {
                    const v = Math.min(24, section.dailyGoalHours + 1);
                    section.dailyGoalHours = v;
                    Settings.set("dailyScreenTimeGoal", v);
                }
            }
        }
    }

    // ── Quiet hours ──────────────────────────────────────────────────────────
    function _hhmm(m) {
        const h = Math.floor(m / 60), mm = m % 60;
        return (h < 10 ? "0" : "") + h + ":" + (mm < 10 ? "0" : "") + mm;
    }
    function _stepTime(key, m, delta) {
        Settings.set(key, (m + delta + 1440) % 1440);
    }

    Card {
        title: "Quiet hours"
        subtitle: Notifications.quietHours ? "On now — banners and sounds are held until " + section._hhmm(Settings.dndScheduleEnd)
                                           : "Do Not Disturb on a schedule, every day"
        icon: "\u{f00a0}"
        accentColor: Design.lavender

        Toggle {
            label: "Quiet hours"
            subtitle: "Notifications still arrive and wait in the list; they just do not pop up or play a sound"
            checked: Settings.dndScheduleEnabled === true
            onToggled: Settings.set("dndScheduleEnabled", !(Settings.dndScheduleEnabled === true))
        }

        Stepper {
            visible: Settings.dndScheduleEnabled === true
            label: "From"
            valueText: section._hhmm(Settings.dndScheduleStart)
            onDecrement: section._stepTime("dndScheduleStart", Settings.dndScheduleStart, -30)
            onIncrement: section._stepTime("dndScheduleStart", Settings.dndScheduleStart, 30)
        }

        Stepper {
            visible: Settings.dndScheduleEnabled === true
            label: "Until"
            valueText: section._hhmm(Settings.dndScheduleEnd)
            onDecrement: section._stepTime("dndScheduleEnd", Settings.dndScheduleEnd, -30)
            onIncrement: section._stepTime("dndScheduleEnd", Settings.dndScheduleEnd, 30)
        }
    }

    // ── 5. Focus Automation & Distraction Control ────────────────────────────
    Card {
        title: "Focus Automation"
        subtitle: "Automatic notification suppression and health reminders"
        icon: "\u{f009b}"
        accentColor: Design.peach

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.sm)

            Toggle {
                label: "Auto-Silence Notifications in Focus Mode"
                subtitle: "Automatically activate Do Not Disturb during active focus sessions"
                checked: section.autoDnd
                onToggled: {
                    const v = !section.autoDnd;
                    section.autoDnd = v;
                    Settings.set("focusAutoDnd", v);
                }
            }

            Toggle {
                label: "Hourly Eye Care & Break Reminders"
                subtitle: "Send a gentle notification when continuous screen time reaches 60 minutes"
                checked: section.breakReminders
                onToggled: {
                    const v = !section.breakReminders;
                    section.breakReminders = v;
                    Settings.set("focusBreakReminders", v);
                }
            }

            Toggle {
                label: "Auto-Start FocusTime Daemon"
                subtitle: "Launch background activity tracker automatically on login"
                checked: section.daemonAutoStart
                onToggled: {
                    const v = !section.daemonAutoStart;
                    section.daemonAutoStart = v;
                    Settings.set("focusDaemonAutoStart", v);
                }
            }
        }
    }
}
