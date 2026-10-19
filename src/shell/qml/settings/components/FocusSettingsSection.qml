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

    // "notifications": the Notifications page (per-app filters, quiet
    // hours); "": Screen Time & Focus (activity, intervals, automation).
    // They were one page, half of it about something else.
    property string part: ""
    spacing: Design.s(Design.space.lg)

    property int workDuration: Settings.focusWorkDuration || 25
    property int shortBreakDuration: Settings.focusShortBreak || 5
    property int longBreakDuration: Settings.focusLongBreak || 15
    property int dailyGoalHours: Settings.dailyScreenTimeGoal || 8
    property bool autoDnd: Settings.focusAutoDnd !== undefined ? Settings.focusAutoDnd : true
    property bool breakReminders: Settings.focusBreakReminders !== undefined ? Settings.focusBreakReminders : true

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

    // The apps heard from (Services/Notifications.sources), for the focus
    // modes' lists of who gets through.
    readonly property var activeApps: Notifications.sources.length > 0
        ? Notifications.sources.map(a => ({ name: a.name, icon: a.icon }))
        : [{ name: "System", icon: "" }]

    // An app's row, then one per channel it has used, for the levels below.
    readonly property var levelRows: {
        const _ = Settings.notificationRules;
        const rows = [];
        for (const app of Notifications.sources) {
            rows.push({ app: app.name, channel: "", label: app.name,
                        note: app.channels.length > 0
                            ? I18n.trn("%1 channel", "%1 channels", app.channels.length) : "" });
            for (const ch of app.channels)
                rows.push({ app: app.name, channel: ch, label: Notifications.channelName(ch),
                            note: I18n.tr("Channel of %1", app.name) });
        }
        return rows;
    }
    function levelChoices(app, channel) {
        const all = Notifications.levels.map(l => ({ id: l, label: Notifications.levelName(l) }));
        return channel
            ? [{ id: "", label: I18n.tr("As the app (%1)", Notifications.levelName(Notifications.levelOf(app, ""))) }].concat(all)
            : all;
    }

    function _clock(ms) { return Qt.formatTime(new Date(ms), "hh:mm"); }

    // (The page title is in the Settings header bar now.)

    // ── 2. Today's Wellbeing Overview ────────────────────────────────────────
    SettingsGroup {
        visible: section.part === ""
        title: I18n.tr("Today's Activity")
        icon: "\u{f051e}"

        RowLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.md)

            // Screen time stat box
            Surface {
                kind: "well"
                Layout.fillWidth: true
                Layout.preferredHeight: Design.s(Design.size.stat)
                radius: Design.s(Design.radius.card)

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: Design.s(Design.space.xxs)
                    Label {
                        text: I18n.tr("Screen Time Today")
                        role: "caption"
                        dim: true
                    }
                    Label {
                        text: (section.screenHours > 0 ? section.screenHours + "h " : "") + section.screenMins + "m"
                        role: "subhead"
                        weight: Design.weight.semibold
                        color: Design.text
                    }
                }
            }

            // Daily goal progress box
            Surface {
                kind: "well"
                Layout.fillWidth: true
                Layout.preferredHeight: Design.s(Design.size.stat)
                radius: Design.s(Design.radius.card)

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: Design.s(Design.space.xxs)
                    Label {
                        text: I18n.tr("Daily Goal (%1h)", section.dailyGoalHours)
                        role: "caption"
                        dim: true
                    }
                    Label {
                        readonly property real pct: Math.min(100, Math.round((section.screenSeconds / (section.dailyGoalHours * 3600)) * 100))
                        text: I18n.tr("%1% used", pct)
                        role: "subhead"
                        weight: Design.weight.semibold
                        color: pct > 100 ? Design.danger : Design.accent
                    }
                }
            }

            // Focus status box
            Surface {
                kind: "well"
                Layout.fillWidth: true
                Layout.preferredHeight: Design.s(Design.size.stat)
                radius: Design.s(Design.radius.card)

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: Design.s(Design.space.xxs)
                    Label {
                        text: I18n.tr("Focus Status")
                        role: "caption"
                        dim: true
                    }
                    Label {
                        // Say which of the reasons is holding banners back.
                        text: Focus.wantsDnd ? I18n.tr("Focusing (DND)")
                            : Notifications.quietHours ? I18n.tr("Quiet hours")
                            : Notifications.dnd ? I18n.tr("Do Not Disturb") : I18n.tr("Active")
                        role: "subhead"
                        weight: Design.weight.semibold
                        color: Notifications.dnd ? Design.warn : Design.ok
                    }
                }
            }
        }
    }

    // ── 3. Priorities and channels ───────────────────────────────────────────
    SettingsGroup {
        visible: section.part === "notifications"
        title: I18n.tr("Notifications by app")
        subtitle: I18n.tr("Priority comes through focus modes and quiet hours, Quiet goes straight to the list, Off is not kept. A channel is the kind of notification an app says it sends; it follows its app unless set here")
        icon: "\u{f0f3}"

        Repeater {
            model: section.levelRows

            SettingsRow {
                required property var modelData
                label: modelData.label
                note: modelData.note
                Select {
                    Layout.preferredWidth: Design.s(Design.width.control)
                    model: section.levelChoices(modelData.app, modelData.channel)
                    current: modelData.channel ? Notifications.ownLevel(modelData.app, modelData.channel)
                                               : Notifications.levelOf(modelData.app, "")
                    onPicked: id => Notifications.setLevel(modelData.app, modelData.channel, id)
                }
            }
        }
        Label {
            visible: section.levelRows.length === 0
            Layout.fillWidth: true
            text: I18n.tr("Apps appear here once they have sent a notification.")
            role: "caption"
            dim: true
            wrapMode: Text.WordWrap
        }
    }

    // ── 4. Pomodoro & Interval Durations ─────────────────────────────────────
    SettingsGroup {
        visible: section.part === ""
        title: I18n.tr("Focus & Break Intervals")
        icon: "\u{f0520}"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.sm)

            SettingsRow {
                label: I18n.tr("Focus Work Duration")
                Stepper {
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
            }

            SettingsRow {
                label: I18n.tr("Short Break Duration")
                Stepper {
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
            }

            SettingsRow {
                label: I18n.tr("Long Break Duration")
                Stepper {
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
            }

            SettingsRow {
                label: I18n.tr("Daily Screen Time Limit Goal")
                Stepper {
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
    }

    // ── Quiet hours ──────────────────────────────────────────────────────────
    function _hhmm(m) {
        const h = Math.floor(m / 60), mm = m % 60;
        return (h < 10 ? "0" : "") + h + ":" + (mm < 10 ? "0" : "") + mm;
    }
    function _stepTime(key, m, delta) {
        Settings.set(key, (m + delta + 1440) % 1440);
    }

    // ── Focus modes ──────────────────────────────────────────────────────────
    SettingsGroup {
        id: modesCard
        visible: section.part === "notifications"
        title: I18n.tr("Focus modes")
        subtitle: I18n.tr("Each one holds back banners and sounds, except from the apps you let through. Sleep also comes on with quiet hours, Meeting with your calendar, Work with the focus timer, Gaming with Game Mode")
        icon: "\u{f0594}"
        property string editing: "dnd"

        Flow {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.xs)
            Repeater {
                model: Notifications.modes
                delegate: Chip {
                    required property var modelData
                    icon: modelData.glyph
                    label: modelData.name + (Notifications.mode === modelData.id ? " · " + I18n.tr("on") : "")
                    active: modesCard.editing === modelData.id
                    onClicked: modesCard.editing = modelData.id
                }
            }
        }
        SwitchRow {
            visible: modesCard.editing !== "game"
            label: I18n.tr("On now")
            checked: Settings.focusMode === modesCard.editing
            onToggled: Notifications.setMode(Settings.focusMode === modesCard.editing ? "" : modesCard.editing)
        }
        Label { text: I18n.tr("Let through"); role: "caption"; weight: Design.weight.semibold; dim: true }
        Flow {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.xs)
            Repeater {
                model: section.activeApps
                delegate: Chip {
                    required property var modelData
                    readonly property bool on: ((Settings.focusAllow || {})[modesCard.editing] || [])
                        .some(a => String(a).toLowerCase() === String(modelData.name).toLowerCase())
                    icon: on ? "\u{f012c}" : ""
                    label: modelData.name
                    active: on
                    onClicked: Notifications.toggleAllowed(modesCard.editing, modelData.name)
                }
            }
        }
        Label {
            visible: section.activeApps.length === 0
            text: I18n.tr("Apps appear here once they have sent a notification.")
            role: "caption"
            dim: true
        }
    }

    SettingsGroup {
        visible: section.part === "notifications"
        // No title over the switch of the same name. Its note says what is
        // held back, and while in force, until when.
        icon: "\u{f00a0}"

        SwitchRow {
            label: I18n.tr("Quiet hours")
            note: Notifications.quietHours
                ? I18n.tr("On now — banners and sounds are held until %1", section._hhmm(Settings.dndScheduleEnd))
                : I18n.tr("Notifications still arrive and wait in the list; they just do not pop up or play a sound")
            checked: Settings.dndScheduleEnabled === true
            onToggled: Settings.set("dndScheduleEnabled", !(Settings.dndScheduleEnabled === true))
        }

        SettingsRow {
            visible: Settings.dndScheduleEnabled === true
            label: I18n.tr("From")
            Stepper {
                valueText: section._hhmm(Settings.dndScheduleStart)
                onDecrement: section._stepTime("dndScheduleStart", Settings.dndScheduleStart, -30)
                onIncrement: section._stepTime("dndScheduleStart", Settings.dndScheduleStart, 30)
            }
        }

        SettingsRow {
            visible: Settings.dndScheduleEnabled === true
            label: I18n.tr("Until")
            Stepper {
                valueText: section._hhmm(Settings.dndScheduleEnd)
                onDecrement: section._stepTime("dndScheduleEnd", Settings.dndScheduleEnd, -30)
                onIncrement: section._stepTime("dndScheduleEnd", Settings.dndScheduleEnd, 30)
            }
        }
    }

    // ── Meetings ─────────────────────────────────────────────────────────────
    //
    // The Meeting mode while an event in a calendar is under way
    // (Services/Notifications, b1air-daemon calendar); the calendars, and
    // adding one, in CalendarAccounts.
    SettingsGroup {
        visible: section.part === "notifications"
        icon: "\u{f0ed7}"

        SwitchRow {
            label: I18n.tr("During meetings")
            note: Notifications.meetingNow
                ? I18n.tr("On now — %1, until %2", Notifications.meetingNow.title, section._clock(Notifications.meetingNow.end))
                : Notifications.calendarOn && Notifications.nextMeeting
                ? I18n.tr("Next: %1 at %2", Notifications.nextMeeting.title, section._clock(Notifications.nextMeeting.start))
                : I18n.tr("The Meeting mode comes on while an event in your calendar is under way. All-day events and ones marked free do not count")
            checked: Settings.focusDuringMeetings === true
            onToggled: Settings.set("focusDuringMeetings", !(Settings.focusDuringMeetings === true))
        }

        CalendarAccounts {
            visible: Settings.focusDuringMeetings === true
            Layout.fillWidth: true
        }
    }

    // ── 5. Focus Automation & Distraction Control ────────────────────────────
    SettingsGroup {
        visible: section.part === ""
        title: I18n.tr("Focus Automation")
        subtitle: I18n.tr("Do Not Disturb while focusing, and break reminders. Recording screen time is on Privacy")
        icon: "\u{f009b}"

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.sm)

            SwitchRow {
                label: I18n.tr("Auto-Silence Notifications in Focus Mode")
                subtitle: I18n.tr("Automatically activate Do Not Disturb during active focus sessions")
                checked: section.autoDnd
                onToggled: {
                    const v = !section.autoDnd;
                    section.autoDnd = v;
                    Settings.set("focusAutoDnd", v);
                }
            }

            SwitchRow {
                label: I18n.tr("Hourly Eye Care & Break Reminders")
                subtitle: I18n.tr("Send a gentle notification when continuous screen time reaches 60 minutes")
                checked: section.breakReminders
                onToggled: {
                    const v = !section.breakReminders;
                    section.breakReminders = v;
                    Settings.set("focusBreakReminders", v);
                }
            }
        }
    }
}
