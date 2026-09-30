import QtQuick
import QtQuick.Window
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import QtCore
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import B1air.Daemon
import "./Ui"
// Aliased: QtCore's own `Settings` type collides with Services/Settings.qml's
// singleton of the same name, and an unaliased directory import made the
// engine refuse to create either — "Composite Singleton Type Settings is not
// creatable" — which crashed Lock.qml on every single launch. Nothing here
// rendered, ever; the lock "not appearing" was this, not a spawn problem.
import "./Services" as Services
import "WindowRegistry.js" as LayoutMath

ShellRoot {
    id: root

    // Durations that are choreography, not styling: a staged entrance, ambient
    // loops and slow tint crossfades. Deliberately off the motion scale.
    // PauseAnimation delays are left as they are — that spread is the stagger.
    readonly property int introDuration: 800
    readonly property int tintDuration: 1000
    readonly property int pulsePeriod: 1500
    readonly property int driftPeriod: 90000

    readonly property color base: Design.surface
    readonly property color crust: Design.ground
    readonly property color mantle: Design.sunken
    readonly property color text: Design.text
    readonly property color subtext0: Design.textDim
    readonly property color overlay0: Design.textFaint
    readonly property color overlay2: Design.textFaint
    readonly property color surface0: Design.raised
    readonly property color surface1: Design.hover
    readonly property color surface2: Design.active

    readonly property color mauve: Design.accentAlt
    readonly property color red: Design.danger
    readonly property color peach: Design.warn
    readonly property color blue: Design.accent
    readonly property color green: Design.ok

    // Persistent Settings
    Settings {
        id: lockSettings
        category: "QuickshellLockscreen"
        property bool hidePassword: false
        property int revealDuration: 300
    }

    // Shared state across all monitors
    QtObject {
        id: lockUI
        property bool failed: false
        property bool authenticating: false
        // The eye button: show what has been typed.
        property bool peek: false
        property string statusText: "Locked"
    }

    // System Authentication hook
    PamContext {
        id: pam

        // Measured, not assumed: with no config set, Quickshell uses the
        // "login" service from /etc/pam.d, which exists on Arch and prompts
        // for a password as expected. Nothing extra needs installing.
        Component.onCompleted: {
            if (!pam.start()) {
                lockUI.failed = true;
                lockUI.statusText = "Authentication unavailable";
            }
        }

        onCompleted: (result) => {
            lockUI.authenticating = false;
            if (result === PamResult.Success) {
                rootLock.locked = false;
                Qt.quit();
            } else {
                lockUI.failed = true;
                lockUI.statusText = "Access Denied";
                if (!pam.start()) {
                    lockUI.statusText = "Authentication unavailable";
                }
            }
        }

        // Nothing listened to this before. A PAM conversation that cannot even
        // start — a broken /etc/pam.d/login, a distribution that names the
        // service something else, a resource limit — left the screen reading
        // "Locked", accepting a password and doing nothing with it, with no
        // message and no hint that the lock was never going to open. It says
        // so now, which is the difference between a wrong password and a
        // machine that cannot check one.
        onError: (err) => {
            lockUI.authenticating = false;
            lockUI.failed = true;
            lockUI.statusText = "Authentication unavailable";
            console.warn("[b1air-lock] PAM error:", err, pam.message);
        }
    }

    Process {
        id: suspendProcess
        command: ["b1air-daemon", "power", "suspend"]
    }

    Process {
        id: poweroffProcess
        command: ["b1air-daemon", "power", "shutdown"]
    }

    Process {
        id: reloadProcess
        command: ["b1air-daemon", "power", "reboot"]
    }

    WlSessionLock {
        id: rootLock
        locked: true

        WlSessionLockSurface {
            id: surface

            Item {
                id: screenRoot
                anchors.fill: parent

                // --- Responsive Scaling Logic ---
                // We use a property binding instead of a function to ensure 
                // continuous updates even if surface width starts at 0.
                // `scaler` never existed, so this binding resolved to undefined and every
                // one of the 110 sizes derived from sc collapsed. Same scale maths as Design.
                readonly property real sc: LayoutMath.getScale(surface.width, 1.0, surface.height)
                // --------------------------------

                property string staticWallpaperPath: "file://" + (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/b1air/lock_bg.png"

                // Was its own `cat /sys/class/power_supply/BAT*/capacity` poller.
                // This machine has two BAT* nodes and the glob's first match
                // (BAT0) isn't the one UPower treats as the real battery, so the
                // lock screen always showed a stale 100% no matter the real
                // charge. Power already resolves the correct device for TopBar;
                // reuse it instead of re-guessing from sysfs.
                readonly property string batPct: Services.Power.hasBattery ? String(Services.Power.capacity) : "100"
                readonly property string batStatus: Services.Power.hasBattery ? (Services.Power.charging ? "Charging" : "Discharging") : "AC"
                property string currentUser: Quickshell.env("USER") || "User"
                // The account picture, where the login screen keeps it too.
                property string faceIconPath: Sys.exists("~/.face.icon") ? Paths.fileUrl(Quickshell.env("HOME") + "/.face.icon")
                                            : Sys.exists("~/.face") ? Paths.fileUrl(Quickshell.env("HOME") + "/.face") : ""
                property string kbLayout: "US"
                property string weatherIcon: ""
                property string weatherTemp: "--°C"

                // UI States
                property real introState: 0.0
                property bool powerMenuOpen: false
                property bool inputActive: false 
                property bool isPlayingIntro: true
                // No battery under power_supply: a desktop.
                property bool isDesktop: !Sys.listDir("/sys/class/power_supply").some(n => n.startsWith("BAT"))
                
                Component.onCompleted: {
                    introSequence.start();
                    readLayout();   // seed the layout; updates arrive by event
                }

                property real globalOrbitAngle: 0
                NumberAnimation on globalOrbitAngle {
                    from: 0; to: Math.PI * 2; duration: root.driftPeriod; loops: Animation.Infinite; running: false
                }

                // Auto-hide input field if empty and idle for 15 seconds
                Timer {
                    id: idleTimer
                    interval: 15000
                    running: screenRoot.inputActive && inputField.text.length === 0
                    repeat: false
                    onTriggered: screenRoot.inputActive = false
                }

                // ---------------------------------------------------------
                // BACKGROUND DATA POLLING 
                // ---------------------------------------------------------


                
                // The layout shown on the lock screen, asked of sway when it
                // locks and again when sway says the layout changed — never
                // polled: a locked, idle machine should be doing nothing.
                function readLayout() {
                    Sway.query("inputs", inputs => {
                        if (!Array.isArray(inputs))
                            return;   // sway not up yet; keep the last value
                        let name = "";
                        for (const dev of inputs) {
                            if (dev.type === "keyboard" && dev.xkb_active_layout_name) {
                                name = String(dev.xkb_active_layout_name);
                                break;
                            }
                        }
                        const layout = (name || "US").substring(0, 2).toUpperCase();
                        if (layout !== "")
                            screenRoot.kbLayout = layout;
                    });
                }
                Connections {
                    target: Sway
                    function onInputEvent(e) { if (e && e.change === "xkb_layout") screenRoot.readLayout(); }
                    function onReconnected() { screenRoot.readLayout(); }
                }

                Process {
                    id: weatherPoller
                    command: ["b1air-daemon", "weather", "current"]
                    stdout: StdioCollector {
                        onStreamFinished: {
                            let lines = this.text.trim().split("\n");
                            if (lines.length >= 2) {
                                screenRoot.weatherIcon = lines[0] || "";
                                screenRoot.weatherTemp = lines[1] || "--°C";
                            }
                        }
                    }
                }
                Timer { interval: 900000; running: true; repeat: true; triggeredOnStart: true; onTriggered: weatherPoller.running = true }

                // ---------------------------------------------------------
                // 1. LIVING BACKGROUND
                // ---------------------------------------------------------
                
                Rectangle {
                    anchors.fill: parent
                    color: Design.surface
                }

                Image {
                    id: bgWallpaper
                    anchors.fill: parent
                    // Decoded at the size drawn, not the file's (a 4K picture is 33 MB of pixels).
                    sourceSize: Qt.size(Screen.width * Screen.devicePixelRatio, Screen.height * Screen.devicePixelRatio)
                    source: screenRoot.staticWallpaperPath
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    visible: false 
                    cache: false 
                }

                MultiEffect {
                    source: bgWallpaper
                    anchors.fill: bgWallpaper
                    blurEnabled: true
                    blurMax: 64 * screenRoot.sc
                    blur: 1.0
                }
                
                Rectangle {
                    id: dimmer
                    anchors.fill: parent
                    color: "black"
                    opacity: 0.25 
                }

                Item {
                    anchors.fill: parent

                    Rectangle {
                        width: parent.width * 0.8; height: width; radius: width / 2
                        anchors.centerIn: parent
                        opacity: screenRoot.inputActive ? 0.04 : 0.08
                        color: Design.accentAlt
                        Behavior on color { ColorAnimation { duration: root.tintDuration } }
                        Behavior on opacity { NumberAnimation { duration: root.introDuration } }
                    }
                    
                    Rectangle {
                        width: parent.width * 0.9; height: width; radius: width / 2
                        anchors.centerIn: parent
                        opacity: screenRoot.inputActive ? 0.03 : 0.06
                        color: Design.accent
                        Behavior on color { ColorAnimation { duration: root.tintDuration } }
                        Behavior on opacity { NumberAnimation { duration: root.introDuration } }
                    }

                    Item {
                        anchors.fill: parent
                        opacity: screenRoot.introState
                        scale: 1.1 - (0.1 * screenRoot.introState)
                        
                        Repeater {
                            model: 4
                            Rectangle {
                                anchors.centerIn: parent
                                anchors.verticalCenterOffset: -40 * screenRoot.sc
                                width: (400 * screenRoot.sc) + (index * (220 * screenRoot.sc))
                                height: width
                                radius: width / 2
                                color: "transparent"
                                border.color: lockUI.failed ? Design.danger : Design.text
                                border.width: Math.max(1, 1 * screenRoot.sc)
                                opacity: lockUI.failed ? (0.1 - (index * 0.02)) : (screenRoot.inputActive ? (0.02 - (index * 0.005)) : (0.04 - (index * 0.01)))
                                Behavior on border.color { ColorAnimation { duration: root.tintDuration; easing.type: Easing.OutExpo } }
                                Behavior on opacity { NumberAnimation { duration: root.introDuration; easing.type: Easing.OutExpo } }
                            }
                        }
                    }
                }

                // ---------------------------------------------------------
                // 2. MAIN CONTENT LAYER
                // ---------------------------------------------------------
                MouseArea {
                    anchors.fill: parent
                    enabled: !screenRoot.isPlayingIntro
                    onClicked: {
                        if (screenRoot.powerMenuOpen) screenRoot.powerMenuOpen = false;
                        if (!screenRoot.inputActive) screenRoot.inputActive = true;
                        inputField.forceActiveFocus();
                    }
                }

                Item {
                    anchors.fill: parent
                    opacity: screenRoot.introState
                    transform: Translate { y: (30 * screenRoot.sc) * (1.0 - screenRoot.introState) }

                    // --- CLOCK MODULE (Idle State) ---
                    ColumnLayout {
                        id: clockModule
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: screenRoot.inputActive ? (-120 * screenRoot.sc) : (-40 * screenRoot.sc)
                        spacing: -10 * screenRoot.sc
                        
                        opacity: screenRoot.inputActive ? 0.0 : 1.0
                        scale: screenRoot.inputActive ? 0.9 : 1.0
                        visible: opacity > 0.01

                        Behavior on anchors.verticalCenterOffset { NumberAnimation { duration: root.introDuration; easing.type: Easing.OutExpo } }
                        Behavior on opacity { NumberAnimation { duration: Design.duration.slow; easing.type: Easing.OutCubic } }
                        Behavior on scale { NumberAnimation { duration: Design.duration.slow; easing.type: Easing.OutBack } }

                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: 0
                            
                            Text {
                                id: clockHours
                                font.family: Design.font.mono
                                font.pixelSize: 140 * screenRoot.sc
                                font.weight: Design.weight.semibold
                                color: Design.text
                                Behavior on color { ColorAnimation { duration: Design.duration.base } }
                            }
                            Text {
                                text: ":"
                                font.family: Design.font.mono
                                font.pixelSize: 140 * screenRoot.sc
                                font.weight: Design.weight.semibold
                                opacity: 0.5
                                color: Design.text
                                Behavior on color { ColorAnimation { duration: Design.duration.base } }
                            }
                            Text {
                                id: clockMinutes
                                font.family: Design.font.mono
                                font.pixelSize: 140 * screenRoot.sc
                                font.weight: Design.weight.semibold
                                color: Design.text
                                Behavior on color { ColorAnimation { duration: Design.duration.base } }
                            }
                        }

                        Text {
                            id: dateText
                            Layout.alignment: Qt.AlignHCenter
                            font.family: Design.font.mono
                            font.pixelSize: 22 * screenRoot.sc
                            font.weight: Design.weight.semibold
                            color: Design.text
                        }

                        Timer {
                            interval: 1000; running: true; repeat: true; triggeredOnStart: true
                            onTriggered: {
                                let d = new Date();
                                clockHours.text = Qt.formatDateTime(d, "hh");
                                clockMinutes.text = Qt.formatDateTime(d, "mm");
                                dateText.text = Qt.formatDateTime(d, "dddd, MMMM dd");
                            }
                        }
                    }

                    // --- AUTHENTICATION MODULE (Input State) ---
                    RowLayout {
                        id: authModule
                        anchors.centerIn: parent
                        anchors.verticalCenterOffset: screenRoot.inputActive ? (-40 * screenRoot.sc) : (40 * screenRoot.sc)
                        spacing: 32 * screenRoot.sc 
                        
                        opacity: screenRoot.inputActive ? 1.0 : 0.0
                        scale: screenRoot.inputActive ? 1.0 : 0.9
                        visible: opacity > 0.01

                        Behavior on anchors.verticalCenterOffset { NumberAnimation { duration: root.introDuration; easing.type: Easing.OutExpo } }
                        Behavior on opacity { NumberAnimation { duration: Design.duration.slow; easing.type: Easing.OutCubic } }
                        Behavior on scale { NumberAnimation { duration: Design.duration.slow; easing.type: Easing.OutBack } }

                        // Left: Enlarged Avatar
                        Item {
                            Layout.alignment: Qt.AlignVCenter
                            width: 170 * screenRoot.sc
                            height: width // Force square aspect ratio

                            Rectangle {
                                id: avatarMask
                                anchors.fill: parent
                                radius: height / 2 // Dynamic perfect radius
                                color: "black"
                                visible: false 
                                layer.enabled: true 
                            }

                            Rectangle {
                                anchors.fill: parent
                                radius: height / 2
                                color: Qt.rgba(Design.raised.r, Design.raised.g, Design.raised.b, 0.5)
                                visible: avatarImg.status !== Image.Ready
                                
                                Text {
                                    anchors.centerIn: parent
                                    text: "󰄽"
                                    font.family: Design.font.icon
                                    font.pixelSize: 64 * screenRoot.sc
                                    color: Design.textDim
                                }
                            }

                            Image {
                                id: avatarImg
                                anchors.fill: parent
                                // Decoded at the size drawn, not the file's (a 4K picture is 33 MB of pixels).
                                sourceSize: Qt.size(256, 256)
                                source: screenRoot.faceIconPath !== "" ? screenRoot.faceIconPath : ""
                                fillMode: Image.PreserveAspectCrop
                                visible: false 
                                cache: false
                                asynchronous: true
                            }

                            MultiEffect {
                                source: avatarImg
                                anchors.fill: avatarImg
                                maskEnabled: true
                                maskSource: avatarMask
                                visible: avatarImg.status === Image.Ready
                            }

                            Rectangle {
                                anchors.fill: parent
                                radius: height / 2
                                color: "transparent"
                                border.color: lockUI.failed ? Design.danger : (lockUI.authenticating ? Design.warn : Qt.rgba(Design.text.r, Design.text.g, Design.text.b, 0.5))
                                border.width: Math.max(1, 3 * screenRoot.sc)
                                Behavior on border.color { ColorAnimation { duration: Design.duration.base } }
                            }
                        }

                        // Right: Text Details & Input
                        ColumnLayout {
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 16 * screenRoot.sc

                            Text {
                                Layout.alignment: Qt.AlignLeft
                                text: screenRoot.currentUser
                                font.family: Design.font.mono
                                font.pixelSize: 28 * screenRoot.sc
                                font.weight: Design.weight.semibold
                                color: Design.text
                            }

                            RowLayout {
                                Layout.alignment: Qt.AlignLeft
                                spacing: 12 * screenRoot.sc

                                Rectangle {
                                    width: 36 * screenRoot.sc
                                    height: width // Force square
                                    radius: height / 2 // Perfect circle
                                    
                                    color: lockUI.failed
                                        ? Qt.rgba(Design.danger.r,   Design.danger.g,   Design.danger.b,   0.2)
                                        : (lockUI.authenticating
                                            ? Qt.rgba(Design.warn.r, Design.warn.g, Design.warn.b, 0.2)
                                            : Qt.rgba(Design.accentAlt.r, Design.accentAlt.g, Design.accentAlt.b, 0.15))
                                    border.color: lockUI.failed
                                        ? Design.danger
                                        : (lockUI.authenticating ? Design.warn : Design.accentAlt)
                                    border.width: Math.max(1, 1 * screenRoot.sc)
                                    Behavior on color { ColorAnimation { duration: Design.duration.base } }
                                    Behavior on border.color { ColorAnimation { duration: Design.duration.base } }

                                    Text {
                                        anchors.centerIn: parent
                                        text: lockUI.failed ? "󰌾" : (lockUI.authenticating ? "󰌿" : "󰌾")
                                        font.family: Design.font.icon
                                        font.pixelSize: 18 * screenRoot.sc
                                        color: lockUI.failed
                                            ? Design.danger
                                            : (lockUI.authenticating ? Design.warn : Design.accentAlt)
                                        Behavior on color { ColorAnimation { duration: Design.duration.base } }
                                    }
                                }

                                Text {
                                    font.family: Design.font.mono
                                    font.pixelSize: 14 * screenRoot.sc
                                    font.weight: Design.weight.medium
                                    font.letterSpacing: 2.0
                                    color: lockUI.failed
                                        ? Design.danger
                                        : (lockUI.authenticating ? Design.warn : Design.text)
                                    text: lockUI.statusText.toUpperCase()
                                    Behavior on color { ColorAnimation { duration: Design.duration.base } }
                                }
                            }

                            Rectangle {
                                id: pinPill
                                Layout.alignment: Qt.AlignLeft
                                width: 280 * screenRoot.sc
                                height: 60 * screenRoot.sc
                                radius: height / 2 // Perfect pill shape natively!
                                clip: true 
                                
                                color: lockUI.failed ? Qt.rgba(Design.danger.r, Design.danger.g, Design.danger.b, 0.1) : Qt.rgba(Design.raised.r, Design.raised.g, Design.raised.b, 0.5)
                                border.width: Math.max(1, 2 * screenRoot.sc)
                                border.color: {
                                    if (lockUI.failed) return Design.danger;
                                    if (lockUI.authenticating) return Design.warn;
                                    if (inputField.text.length > 0) return Design.text;
                                    return Qt.rgba(Design.text.r, Design.text.g, Design.text.b, 0.08);
                                }

                                Behavior on color { ColorAnimation { duration: Design.duration.base; easing.type: Easing.OutExpo } }
                                Behavior on border.color { ColorAnimation { duration: Design.duration.base; easing.type: Easing.OutExpo } }
                                
                                scale: lockUI.failed ? 1.05 : (lockUI.authenticating ? 0.98 : 1.0)
                                Behavior on scale { NumberAnimation { duration: Design.duration.base; easing.type: Easing.OutBack } }

                                transform: Translate { id: shakeTranslate; x: 0 }
                                
                                SequentialAnimation {
                                    id: shakeAnim
                                    NumberAnimation { target: shakeTranslate; property: "x"; from: 0; to: -8 * screenRoot.sc; duration: root.pulsePeriod; easing.type: Easing.InOutSine }
                                    NumberAnimation { target: shakeTranslate; property: "x"; from: -8 * screenRoot.sc; to: 8 * screenRoot.sc; duration: root.pulsePeriod; easing.type: Easing.InOutSine }
                                    NumberAnimation { target: shakeTranslate; property: "x"; from: 8 * screenRoot.sc; to: 0; duration: root.pulsePeriod; easing.type: Easing.InOutSine }
                                }

                                Connections {
                                    target: lockUI
                                    function onFailedChanged() {
                                        if (lockUI.failed) shakeAnim.restart();
                                    }
                                }

                                TextInput {
                                    id: inputField
                                    anchors.fill: parent
                                    opacity: 0 
                                    echoMode: TextInput.Password
                                    enabled: !screenRoot.isPlayingIntro
                                    
                                    property string oldText: ""
                                    
                                    Component.onCompleted: forceActiveFocus()
                                    
                                    onActiveFocusChanged: {
                                        if (!activeFocus && !screenRoot.powerMenuOpen && !screenRoot.isPlayingIntro) {
                                            forceActiveFocus();
                                        }
                                    }

                                    Keys.onPressed: (event) => {
                                        // A desktop shortcut pressed out of habit (Super+3 to
                                        // change workspace) is refused by sway while locked,
                                        // but its key still reached this field: "3" went into
                                        // the password and the next attempt failed.
                                        if (event.modifiers & Qt.MetaModifier) {
                                            event.accepted = true;
                                            return;
                                        }
                                        if (event.key === Qt.Key_Escape) {
                                            screenRoot.inputActive = false;
                                            lockUI.peek = false;
                                            text = "";
                                            passModel.clear();
                                            event.accepted = true;
                                        } 
                                        else if (!screenRoot.inputActive) {
                                            screenRoot.inputActive = true;
                                        }
                                    }
                                    
                                    onAccepted: {
                                        if (text.length > 0 && pam.responseRequired && !lockUI.authenticating) {
                                            lockUI.authenticating = true;
                                            lockUI.statusText = "Authenticating...";
                                            lockUI.failed = false;
                                            pam.respond(text);
                                            lockUI.peek = false;
                                            text = ""; 
                                            oldText = "";
                                            passModel.clear();
                                        }
                                    }
                                    
                                    onTextChanged: {
                                        if (lockUI.authenticating) return;

                                        if (text.length > 0 && !screenRoot.inputActive) {
                                            screenRoot.inputActive = true;
                                        }
                                        
                                        idleTimer.restart();
                                        
                                        if (text !== oldText) {
                                            if (text.length > oldText.length) {
                                                for (let i = oldText.length; i < text.length; i++) {
                                                    passModel.append({ "charStr": text.charAt(i), "isDot": lockSettings.hidePassword });
                                                }
                                            } else if (text.length < oldText.length) {
                                                let diff = oldText.length - text.length;
                                                for (let i = 0; i < diff; i++) {
                                                    passModel.remove(passModel.count - 1);
                                                }
                                            } else {
                                                passModel.clear();
                                                for (let i = 0; i < text.length; i++) {
                                                    passModel.append({ "charStr": text.charAt(i), "isDot": lockSettings.hidePassword });
                                                }
                                            }
                                            oldText = text;
                                        }

                                        if (text.length > 0) {
                                            lockUI.failed = false;
                                            lockUI.statusText = "Enter PIN";
                                        } else {
                                            if (!lockUI.failed) lockUI.statusText = "Locked";
                                        }
                                    }
                                }

                                ListModel {
                                    id: passModel
                                }

                                Item {
                                    anchors.fill: parent
                                    anchors.leftMargin: 20 * screenRoot.sc
                                    anchors.rightMargin: (peekBtn.visible ? 54 : 20) * screenRoot.sc
                                    clip: true

                                    Row {
                                        id: dotRow
                                        anchors.verticalCenter: parent.verticalCenter
                                        x: width > parent.width ? parent.width - width : (parent.width - width) / 2
                                        spacing: 4 * screenRoot.sc
                                        
                                        Behavior on x { NumberAnimation { duration: Design.duration.fast; easing.type: Easing.OutQuad } }

                                        Repeater {
                                            model: passModel
                                            // Render text directly as the delegate to avoid circular layout loops
                                            delegate: Text {
                                                readonly property bool dot: model.isDot && !lockUI.peek
                                                text: dot ? "•" : model.charStr
                                                font.family: Design.font.mono
                                                font.pixelSize: dot ? (32 * screenRoot.sc) : (24 * screenRoot.sc)
                                                font.weight: Design.weight.semibold
                                                color: lockUI.failed ? Design.danger : (lockUI.authenticating ? Design.warn : Design.text)
                                                verticalAlignment: Text.AlignVCenter
                                                height: pinPill.height
                                                
                                                NumberAnimation on opacity { from: 0; to: 1; duration: Design.duration.fast }
                                                
                                                Timer {
                                                    interval: lockSettings.revealDuration
                                                    running: !model.isDot && !lockSettings.hidePassword
                                                    onTriggered: {
                                                        if (index >= 0 && index < passModel.count) {
                                                            passModel.setProperty(index, "isDot", true);
                                                        }
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                Rectangle {
                                    id: peekBtn
                                    anchors.right: parent.right
                                    anchors.rightMargin: 10 * screenRoot.sc
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 40 * screenRoot.sc
                                    height: width
                                    radius: height / 2
                                    visible: inputField.text.length > 0 && !lockUI.authenticating
                                    color: peekMa.containsMouse ? Qt.rgba(Design.text.r, Design.text.g, Design.text.b, 0.10) : "transparent"
                                    Behavior on color { ColorAnimation { duration: Design.duration.fast } }

                                    Text {
                                        anchors.centerIn: parent
                                        text: lockUI.peek ? "\uf070" : "\uf06e"
                                        font.family: Design.font.icon
                                        font.pixelSize: 22 * screenRoot.sc
                                        color: lockUI.peek ? Design.accent : Design.textDim
                                        Behavior on color { ColorAnimation { duration: Design.duration.fast } }
                                    }

                                    MouseArea {
                                        id: peekMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: lockUI.peek = !lockUI.peek
                                    }
                                }
                            }
                        }
                    }
                }

                // ---------------------------------------------------------
                // 3. BOTTOM SYSTEM INFO PILLS
                // ---------------------------------------------------------
                RowLayout {
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 40 * screenRoot.sc
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 16 * screenRoot.sc

                    opacity: screenRoot.introState
                    transform: Translate { y: (20 * screenRoot.sc) * (1.0 - screenRoot.introState) }

                    // KB Layout Pill
                    Rectangle {
                        property bool isHovered: kbMouse.containsMouse
                        Layout.preferredHeight: 48 * screenRoot.sc
                        Layout.preferredWidth: kbLayoutRow.implicitWidth + (36 * screenRoot.sc)
                        radius: height / 2 // Dynamic pill shape
                        
                        color: isHovered ? Qt.rgba(Design.hover.r, Design.hover.g, Design.hover.b, 0.6) : Qt.rgba(Design.raised.r, Design.raised.g, Design.raised.b, 0.4)
                        border.color: isHovered ? Design.accentAlt : Qt.rgba(Design.text.r, Design.text.g, Design.text.b, 0.08)
                        border.width: Math.max(1, 1 * screenRoot.sc)
                        
                        scale: isHovered ? 1.05 : 1.0
                        Behavior on scale { NumberAnimation { duration: Design.duration.base; easing.type: Easing.OutExpo } }
                        Behavior on color { ColorAnimation { duration: Design.duration.base } }
                        Behavior on border.color { ColorAnimation { duration: Design.duration.base } }

                        RowLayout { 
                            id: kbLayoutRow; anchors.centerIn: parent; spacing: 8 * screenRoot.sc
                            Text { text: "󰌌"; font.family: Design.font.icon; font.pixelSize: 18 * screenRoot.sc; color: parent.parent.isHovered ? Design.accentAlt : Design.textFaint; Behavior on color { ColorAnimation { duration: Design.duration.base } } }
                            Text { text: screenRoot.kbLayout; font.family: Design.font.mono; font.pixelSize: 14 * screenRoot.sc; font.weight: Design.weight.bold; color: Design.text }
                        }
                        Clickable { id: kbMouse; enabled: !screenRoot.isPlayingIntro }
                    }

                    // Battery Pill
                    Rectangle {
                        property bool isHovered: batMouse.containsMouse
                        visible: !screenRoot.isDesktop
                        Layout.preferredHeight: 48 * screenRoot.sc
                        Layout.preferredWidth: batLayoutRow.implicitWidth + (36 * screenRoot.sc)
                        radius: height / 2
                        
                        color: isHovered ? Qt.rgba(Design.hover.r, Design.hover.g, Design.hover.b, 0.6) : Qt.rgba(Design.raised.r, Design.raised.g, Design.raised.b, 0.4)
                        border.color: isHovered ? batLayoutRow.dynamicBatColor : Qt.rgba(Design.text.r, Design.text.g, Design.text.b, 0.08)
                        border.width: Math.max(1, 1 * screenRoot.sc)

                        scale: isHovered ? 1.05 : 1.0
                        Behavior on scale { NumberAnimation { duration: Design.duration.base; easing.type: Easing.OutExpo } }
                        Behavior on color { ColorAnimation { duration: Design.duration.base } }
                        Behavior on border.color { ColorAnimation { duration: Design.duration.base } }

                        RowLayout { 
                            id: batLayoutRow; anchors.centerIn: parent; spacing: 8 * screenRoot.sc
                            
                            property color dynamicBatColor: {
                                if (screenRoot.batStatus === "Charging") return Design.ok;
                                let pct = parseInt(screenRoot.batPct);
                                if (pct >= 60) return Design.ok;
                                if (pct >= 25) return Design.warn;
                                return Design.danger;
                            }

                            Text { 
                                text: screenRoot.batStatus === "Charging" ? "󰂄" : (parseInt(screenRoot.batPct) < 20 ? "󰂃" : "󰁹")
                                font.family: Design.font.icon
                                font.pixelSize: 20 * screenRoot.sc
                                color: batLayoutRow.dynamicBatColor
                                Behavior on color { ColorAnimation { duration: Design.duration.base } }
                            }
                            Text { 
                                text: screenRoot.batPct + "%"
                                font.family: Design.font.mono
                                font.pixelSize: 14 * screenRoot.sc
                                font.weight: Design.weight.bold
                                color: batLayoutRow.dynamicBatColor
                                Behavior on color { ColorAnimation { duration: Design.duration.base } }
                            }
                        }
                        Clickable { id: batMouse; enabled: !screenRoot.isPlayingIntro }
                    }

                    // Weather Pill
                    Rectangle {
                        property bool isHovered: weatherMouse.containsMouse
                        Layout.preferredHeight: 48 * screenRoot.sc
                        Layout.preferredWidth: weatherLayoutRow.implicitWidth + (36 * screenRoot.sc)
                        radius: height / 2
                        
                        color: isHovered ? Qt.rgba(Design.hover.r, Design.hover.g, Design.hover.b, 0.6) : Qt.rgba(Design.raised.r, Design.raised.g, Design.raised.b, 0.4)
                        border.color: isHovered ? Design.accent : Qt.rgba(Design.text.r, Design.text.g, Design.text.b, 0.08)
                        border.width: Math.max(1, 1 * screenRoot.sc)

                        scale: isHovered ? 1.05 : 1.0
                        Behavior on scale { NumberAnimation { duration: Design.duration.base; easing.type: Easing.OutExpo } }
                        Behavior on color { ColorAnimation { duration: Design.duration.base } }
                        Behavior on border.color { ColorAnimation { duration: Design.duration.base } }

                        RowLayout { 
                            id: weatherLayoutRow; anchors.centerIn: parent; spacing: 8 * screenRoot.sc
                            Text { 
                                text: screenRoot.weatherIcon
                                font.family: Design.font.icon
                                font.pixelSize: 20 * screenRoot.sc
                                color: parent.parent.isHovered ? Design.accent : Design.text
                                Behavior on color { ColorAnimation { duration: Design.duration.base } }
                            }
                            Text { 
                                text: screenRoot.weatherTemp
                                font.family: Design.font.mono
                                font.pixelSize: 14 * screenRoot.sc
                                font.weight: Design.weight.bold
                                color: Design.text
                                Behavior on color { ColorAnimation { duration: Design.duration.base } }
                            }
                        }
                        Clickable { id: weatherMouse; enabled: !screenRoot.isPlayingIntro }
                    }
                }

                // ---------------------------------------------------------
                // 4. POWER MENU
                // ---------------------------------------------------------
                Rectangle {
                    id: powerMenu
                    anchors.bottom: powerBtn.top
                    anchors.right: parent.right
                    anchors.bottomMargin: 15 * screenRoot.sc
                    anchors.rightMargin: 40 * screenRoot.sc
                    width: 280 * screenRoot.sc
                    height: screenRoot.powerMenuOpen ? (menuLayout.implicitHeight + (20 * screenRoot.sc)) : 0
                    radius: 18 * screenRoot.sc
                    clip: true
                    opacity: screenRoot.powerMenuOpen ? 1 : 0
                    
                    color: Qt.rgba(Design.raised.r, Design.raised.g, Design.raised.b, 0.95)
                    border.color: Qt.rgba(Design.accentAlt.r, Design.accentAlt.g, Design.accentAlt.b, 0.25)
                    border.width: Math.max(1, 1 * screenRoot.sc)

                    Behavior on height { NumberAnimation { duration: Design.duration.base; easing.type: Easing.OutExpo } }
                    Behavior on opacity { NumberAnimation { duration: Design.duration.base } }

                    ColumnLayout {
                        id: menuLayout
                        anchors.top: parent.top
                        anchors.topMargin: 10 * screenRoot.sc
                        anchors.left: parent.left
                        anchors.right: parent.right
                        spacing: 6 * screenRoot.sc

                        // --- SETTINGS SECTION ---
                        Text { 
                            text: "SETTINGS"
                            font.family: Design.font.mono
                            font.weight: Design.weight.bold
                            font.pixelSize: 12 * screenRoot.sc
                            font.letterSpacing: 1.5
                            color: Design.accentAlt
                            Layout.leftMargin: 18 * screenRoot.sc; Layout.topMargin: 4 * screenRoot.sc; Layout.bottomMargin: 4 * screenRoot.sc 
                        }

                        // Hide Password Toggle
                        RowLayout {
                            Layout.fillWidth: true; Layout.leftMargin: 18 * screenRoot.sc; Layout.rightMargin: 18 * screenRoot.sc; Layout.topMargin: 4 * screenRoot.sc
                            Text {
                                text: "Hide password"
                                font.family: Design.font.mono
                                font.pixelSize: 14 * screenRoot.sc
                                font.weight: Design.weight.medium
                                color: Design.text
                                Layout.fillWidth: true
                            }
                            
                            Rectangle {
                                width: 40 * screenRoot.sc; height: 22 * screenRoot.sc; radius: height / 2
                                color: lockSettings.hidePassword ? Design.accentAlt : Design.active
                                Behavior on color { ColorAnimation { duration: Design.duration.base } }
                                
                                Rectangle {
                                    width: height; height: 18 * screenRoot.sc; radius: height / 2
                                    x: lockSettings.hidePassword ? parent.width - width - (2 * screenRoot.sc) : (2 * screenRoot.sc)
                                    y: (parent.height - height) / 2
                                    color: Design.surface
                                    Behavior on x { NumberAnimation { duration: Design.duration.base; easing.type: Easing.OutBack } }
                                }
                                MouseArea { 
                                    anchors.fill: parent; 
                                    onClicked: {
                                        lockSettings.hidePassword = !lockSettings.hidePassword;
                                        if (lockSettings.hidePassword) {
                                            for(let i = 0; i < passModel.count; i++) passModel.setProperty(i, "isDot", true);
                                        }
                                    }
                                }
                            }
                        }

                        // Reveal Delay Slider
                        ColumnLayout {
                            Layout.fillWidth: true; Layout.leftMargin: 18 * screenRoot.sc; Layout.rightMargin: 18 * screenRoot.sc; Layout.topMargin: 8 * screenRoot.sc; Layout.bottomMargin: 8 * screenRoot.sc; spacing: 8 * screenRoot.sc
                            opacity: lockSettings.hidePassword ? 0.3 : 1.0
                            Behavior on opacity { NumberAnimation { duration: Design.duration.base } }
                            
                            RowLayout {
                                Layout.fillWidth: true
                                Text {
                                    text: "Reveal delay"
                                    font.family: Design.font.mono
                                    font.pixelSize: 14 * screenRoot.sc
                                    font.weight: Design.weight.medium
                                    color: Design.accent
                                    Layout.fillWidth: true
                                }
                                Text { 
                                    text: lockSettings.revealDuration >= 1000 ? (lockSettings.revealDuration / 1000).toFixed(1) + " s" : lockSettings.revealDuration + " ms"
                                    font.family: Design.font.mono
                                    font.pixelSize: 13 * screenRoot.sc
                                    font.weight: Design.weight.semibold
                                    color: Design.warn
                                }
                            }
                            
                            Item {
                                Layout.fillWidth: true; Layout.preferredHeight: 28 * screenRoot.sc
                                
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width; height: 8 * screenRoot.sc; radius: height / 2; color: Design.active
                                    Rectangle {
                                        width: ((lockSettings.revealDuration - 100) / 2900) * parent.width
                                        height: parent.height; radius: height / 2; color: Design.accentAlt
                                    }
                                }
                                
                                Rectangle {
                                    id: sliderThumb
                                    width: 20 * screenRoot.sc
                                    height: width
                                    radius: height / 2
                                    color: Design.warn
                                    border.color: Design.ground; border.width: Math.max(1, 2 * screenRoot.sc)
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: Math.max(0, Math.min(((lockSettings.revealDuration - 100) / 2900) * parent.width - (width / 2), parent.width - width))
                                    
                                    scale: sliderMouse.pressed ? 1.3 : (sliderMouse.containsMouse ? 1.15 : 1.0)
                                    Behavior on scale { NumberAnimation { duration: Design.duration.fast; easing.type: Easing.OutBack } }
                                }
                                
                                MultiEffect {
                                    source: sliderThumb
                                    anchors.fill: sliderThumb
                                    shadowEnabled: true
                                    shadowBlur: 0.5
                                    shadowColor: "#000000"
                                    shadowOpacity: 0.4
                                    shadowVerticalOffset: 2 * screenRoot.sc
                                }

                                Clickable {
                                    id: sliderMouse
                                    enabled: !lockSettings.hidePassword
                                    preventStealing: true
                                    function updateVal(mouseX) {
                                        let pct = Math.max(0, Math.min(1, mouseX / width));
                                        let ms = Math.round(100 + (pct * 2900));
                                        if (ms % 100 < 10) ms -= (ms % 100);
                                        else if (ms % 100 > 90) ms += (100 - (ms % 100));
                                        lockSettings.revealDuration = ms;
                                    }
                                    onPositionChanged: (mouse) => {
                                        if (pressed) {
                                            updateVal(mouse.x);
                                        }
                                    }
                                    onPressed: (mouse) => updateVal(mouse.x)
                                }
                            }
                        }

                        // Separator
                        Rectangle {
                            Layout.fillWidth: true; Layout.preferredHeight: Math.max(1, 1 * screenRoot.sc)
                            color: Qt.rgba(Design.accentAlt.r, Design.accentAlt.g, Design.accentAlt.b, 0.2)
                            Layout.leftMargin: 18 * screenRoot.sc; Layout.rightMargin: 18 * screenRoot.sc; Layout.topMargin: 4 * screenRoot.sc; Layout.bottomMargin: 4 * screenRoot.sc
                        }

                        // --- SYSTEM ACTIONS SECTION ---
                        Text {
                            text: "SYSTEM"
                            font.family: Design.font.mono
                            font.weight: Design.weight.bold
                            font.pixelSize: 12 * screenRoot.sc
                            font.letterSpacing: 1.5
                            color: Design.accentAlt
                            Layout.leftMargin: 18 * screenRoot.sc; Layout.bottomMargin: 4 * screenRoot.sc
                        }

                        Rectangle {
                            Layout.fillWidth: true; Layout.preferredHeight: 48 * screenRoot.sc; Layout.leftMargin: 10 * screenRoot.sc; Layout.rightMargin: 10 * screenRoot.sc; radius: 12 * screenRoot.sc
                            color: ma1.containsMouse ? Qt.rgba(Design.accent.r, Design.accent.g, Design.accent.b, 0.1) : "transparent"
                            scale: ma1.pressed ? 0.95 : (ma1.containsMouse ? 1.02 : 1.0)
                            Behavior on color { ColorAnimation { duration: Design.duration.base } }
                            Behavior on scale { NumberAnimation { duration: Design.duration.base; easing.type: Easing.OutBack } }
                            
                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: 16 * screenRoot.sc; anchors.rightMargin: 16 * screenRoot.sc; spacing: 0
                                Text { text: "󰜉"; font.family: Design.font.icon; font.pixelSize: 18 * screenRoot.sc; color: ma1.containsMouse ? Design.accent : Qt.rgba(Design.accent.r, Design.accent.g, Design.accent.b, 0.6); Behavior on color { ColorAnimation { duration: Design.duration.base } } }
                                Item { Layout.fillWidth: true }
                                Text { text: "Reboot"; font.family: Design.font.mono; font.pixelSize: 15 * screenRoot.sc; font.weight: Design.weight.medium; color: ma1.containsMouse ? Design.accent : Qt.rgba(Design.accent.r, Design.accent.g, Design.accent.b, 0.6); Behavior on color { ColorAnimation { duration: Design.duration.base } } }
                            }
                            Clickable {
                                id: ma1
                                onClicked: {
                                    screenRoot.powerMenuOpen = false;
                                    reloadProcess.running = true;
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true; Layout.preferredHeight: 48 * screenRoot.sc; Layout.leftMargin: 10 * screenRoot.sc; Layout.rightMargin: 10 * screenRoot.sc; radius: 12 * screenRoot.sc
                            color: ma2.containsMouse ? Qt.rgba(Design.accentAlt.r, Design.accentAlt.g, Design.accentAlt.b, 0.1) : "transparent"
                            scale: ma2.pressed ? 0.95 : (ma2.containsMouse ? 1.02 : 1.0)
                            Behavior on color { ColorAnimation { duration: Design.duration.base } }
                            Behavior on scale { NumberAnimation { duration: Design.duration.base; easing.type: Easing.OutBack } }
                            
                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: 16 * screenRoot.sc; anchors.rightMargin: 16 * screenRoot.sc; spacing: 0
                                Text { text: "󰒲"; font.family: Design.font.icon; font.pixelSize: 18 * screenRoot.sc; color: ma2.containsMouse ? Design.accentAlt : Qt.rgba(Design.accentAlt.r, Design.accentAlt.g, Design.accentAlt.b, 0.6); Behavior on color { ColorAnimation { duration: Design.duration.base } } }
                                Item { Layout.fillWidth: true }
                                Text { text: "Suspend"; font.family: Design.font.mono; font.pixelSize: 15 * screenRoot.sc; font.weight: Design.weight.medium; color: ma2.containsMouse ? Design.accentAlt : Qt.rgba(Design.accentAlt.r, Design.accentAlt.g, Design.accentAlt.b, 0.6); Behavior on color { ColorAnimation { duration: Design.duration.base } } }
                            }
                            Clickable {
                                id: ma2
                                onClicked: {
                                    screenRoot.powerMenuOpen = false;
                                    suspendProcess.running = true;
                                }
                            }
                        }

                        Rectangle {
                            Layout.fillWidth: true; Layout.preferredHeight: 48 * screenRoot.sc; Layout.leftMargin: 10 * screenRoot.sc; Layout.rightMargin: 10 * screenRoot.sc; Layout.bottomMargin: 8 * screenRoot.sc; radius: 12 * screenRoot.sc
                            color: ma3.containsMouse ? Qt.rgba(Design.danger.r, Design.danger.g, Design.danger.b, 0.1) : "transparent"
                            scale: ma3.pressed ? 0.95 : (ma3.containsMouse ? 1.02 : 1.0)
                            Behavior on color { ColorAnimation { duration: Design.duration.base } }
                            Behavior on scale { NumberAnimation { duration: Design.duration.base; easing.type: Easing.OutBack } }
                            
                            RowLayout {
                                anchors.fill: parent; anchors.leftMargin: 16 * screenRoot.sc; anchors.rightMargin: 16 * screenRoot.sc; spacing: 0
                                Text { text: "󰐥"; font.family: Design.font.icon; font.pixelSize: 18 * screenRoot.sc; color: ma3.containsMouse ? Design.danger : Qt.rgba(Design.danger.r, Design.danger.g, Design.danger.b, 0.6); Behavior on color { ColorAnimation { duration: Design.duration.base } } }
                                Item { Layout.fillWidth: true }
                                Text { text: "Power Off"; font.family: Design.font.mono; font.pixelSize: 15 * screenRoot.sc; font.weight: Design.weight.medium; color: ma3.containsMouse ? Design.danger : Qt.rgba(Design.danger.r, Design.danger.g, Design.danger.b, 0.6); Behavior on color { ColorAnimation { duration: Design.duration.base } } }
                            }
                            Clickable {
                                id: ma3
                                onClicked: {
                                    screenRoot.powerMenuOpen = false;
                                    poweroffProcess.running = true;
                                }
                            }
                        }
                    }
                }

                // Enlarged Power Button
                Rectangle {
                    id: powerBtn
                    anchors.bottom: parent.bottom
                    anchors.right: parent.right
                    anchors.margins: 40 * screenRoot.sc
                    width: 52 * screenRoot.sc
                    height: width
                    radius: height / 2
                    
                    color: screenRoot.powerMenuOpen 
                            ? Design.active 
                            : (powerBtnMa.containsMouse ? Qt.rgba(Design.hover.r, Design.hover.g, Design.hover.b, 0.8) : Qt.rgba(Design.raised.r, Design.raised.g, Design.raised.b, 0.4))
                    border.color: screenRoot.powerMenuOpen ? Design.text : Qt.rgba(Design.text.r, Design.text.g, Design.text.b, 0.15)
                    border.width: Math.max(1, 1 * screenRoot.sc)

                    opacity: screenRoot.introState
                    transform: Translate { y: (20 * screenRoot.sc) * (1.0 - screenRoot.introState) }
                    
                    scale: powerBtnMa.pressed ? 0.9 : (powerBtnMa.containsMouse ? 1.08 : 1.0)

                    Behavior on color { ColorAnimation { duration: Design.duration.base } }
                    Behavior on border.color { ColorAnimation { duration: Design.duration.base } }
                    Behavior on scale { NumberAnimation { duration: Design.duration.base; easing.type: Easing.OutBack } }

                    Text {
                        anchors.centerIn: parent
                        text: "󰐥"
                        font.family: Design.font.icon
                        font.pixelSize: 22 * screenRoot.sc
                        color: screenRoot.powerMenuOpen ? Design.danger : (powerBtnMa.containsMouse ? Design.text : Design.textDim)
                        Behavior on color { ColorAnimation { duration: Design.duration.base } }
                    }

                    Clickable {
                        id: powerBtnMa
                        enabled: !screenRoot.isPlayingIntro
                        onClicked: {
                            screenRoot.powerMenuOpen = !screenRoot.powerMenuOpen;
                            if (!screenRoot.powerMenuOpen) inputField.forceActiveFocus();
                        }
                    }
                }

                // ---------------------------------------------------------
                // 5. INTRO ANIMATION OVERLAY
                // ---------------------------------------------------------
                Item {
                    id: introOverlay
                    anchors.fill: parent
                    z: 999
                    visible: screenRoot.isPlayingIntro || opacity > 0

                    Rectangle {
                        id: ring3
                        width: 360 * screenRoot.sc
                        height: width
                        radius: height / 2 
                        anchors.centerIn: parent
                        color: "transparent"
                        border.color: Design.accentAlt
                        border.width: Math.max(1, 1 * screenRoot.sc)
                        scale: 0.5
                        opacity: 0.0
                    }
                    Rectangle {
                        id: ring2
                        width: 300 * screenRoot.sc
                        height: width
                        radius: height / 2 
                        anchors.centerIn: parent
                        color: "transparent"
                        border.color: Design.text
                        border.width: Math.max(1, 1 * screenRoot.sc)
                        scale: 0.8
                        opacity: 0.0
                    }
                    Rectangle {
                        id: ring1
                        width: 240 * screenRoot.sc
                        height: width
                        radius: height / 2 
                        anchors.centerIn: parent
                        color: "transparent"
                        border.color: Design.text
                        border.width: Math.max(1, 2 * screenRoot.sc)
                        scale: 0.8
                        opacity: 0.0
                    }

                    Item {
                        id: introLockOrb
                        width: 170 * screenRoot.sc
                        height: width
                        anchors.centerIn: parent
                        scale: 0.0
                        opacity: 0.0
                        
                        Rectangle {
                            anchors.fill: parent
                            radius: height / 2
                            color: Qt.rgba(Design.raised.r, Design.raised.g, Design.raised.b, 0.9)
                            border.color: Design.text
                            border.width: Math.max(1, 2 * screenRoot.sc)
                        }

                        Text {
                            id: introIconUnlocked
                            anchors.centerIn: parent
                            text: "󰌿"
                            font.family: Design.font.icon
                            font.pixelSize: 64 * screenRoot.sc 
                            color: Design.text
                            opacity: 1.0
                            scale: 1.0
                            transformOrigin: Item.Center
                        }

                        Text {
                            id: introIconLocked
                            anchors.centerIn: parent
                            text: "󰌾"
                            font.family: Design.font.icon
                            font.pixelSize: 64 * screenRoot.sc 
                            color: Design.text
                            opacity: 0.0
                            scale: 1.6
                            transformOrigin: Item.Center
                        }
                    }

                    SequentialAnimation {
                        id: introSequence
                        
                        ParallelAnimation {
                            NumberAnimation { target: introLockOrb; property: "scale"; from: 0.0; to: 1.0; duration: Design.duration.base; easing.type: Easing.OutCubic }
                            NumberAnimation { target: introLockOrb; property: "opacity"; from: 0.0; to: 1.0; duration: Design.duration.base; easing.type: Easing.OutCubic }
                            
                            NumberAnimation { target: ring1; property: "scale"; from: 0.8; to: 1.25; duration: Design.duration.base; easing.type: Easing.OutCubic }
                            NumberAnimation { target: ring1; property: "opacity"; from: 0.6; to: 0.0; duration: Design.duration.base; easing.type: Easing.OutCubic }
                            
                            NumberAnimation { target: ring2; property: "scale"; from: 0.8; to: 1.4; duration: Design.duration.base; easing.type: Easing.OutCubic }
                            NumberAnimation { target: ring2; property: "opacity"; from: 0.4; to: 0.0; duration: Design.duration.base; easing.type: Easing.OutCubic }

                            NumberAnimation { target: ring3; property: "scale"; from: 0.5; to: 1.5; duration: Design.duration.base; easing.type: Easing.OutCubic }
                            NumberAnimation { target: ring3; property: "opacity"; from: 0.3; to: 0.0; duration: Design.duration.base; easing.type: Easing.OutCubic }
                            
                            SequentialAnimation {
                                PauseAnimation { duration: Design.duration.base } 
                                // Sub-fast on purpose: a 40ms bounce is a mechanical
                                // snap, not a UI transition. Putting these on the
                                // motion scale would flatten the click.
                                ParallelAnimation {
                                    NumberAnimation { target: introIconUnlocked; property: "scale"; from: 1.0; to: 0.5; duration: Design.duration.fast; easing.type: Easing.InCubic }
                                    NumberAnimation { target: introIconUnlocked; property: "opacity"; from: 1.0; to: 0.0; duration: 50 }
                                    
                                    NumberAnimation { target: introIconLocked; property: "scale"; from: 1.6; to: 1.0; duration: Design.duration.base; easing.type: Easing.OutBack }
                                    NumberAnimation { target: introIconLocked; property: "opacity"; from: 0.0; to: 1.0; duration: Design.duration.fast }
                                    
                                    SequentialAnimation {
                                        NumberAnimation { target: introLockOrb; property: "anchors.verticalCenterOffset"; from: 0; to: 3 * screenRoot.sc; duration: 40; easing.type: Easing.OutQuad }
                                        NumberAnimation { target: introLockOrb; property: "anchors.verticalCenterOffset"; from: 3 * screenRoot.sc; to: 0; duration: 120; easing.type: Easing.OutBack }
                                    }
                                }
                            }
                        }
                        
                        PauseAnimation { duration: 50 }

                        SequentialAnimation {
                            ParallelAnimation {
                                NumberAnimation { target: introLockOrb; property: "scale"; to: 1.8; duration: Design.duration.fast; easing.type: Easing.InCubic }
                                NumberAnimation { target: introOverlay; property: "opacity"; to: 0.0; duration: Design.duration.fast; easing.type: Easing.InCubic }
                            }
                            
                            NumberAnimation { target: screenRoot; property: "introState"; from: 0.0; to: 1.0; duration: Design.duration.fast; easing.type: Easing.OutCubic }
                        }

                        PropertyAction { target: screenRoot; property: "isPlayingIntro"; value: false }
                        ScriptAction { script: { inputField.text = ""; inputField.forceActiveFocus(); } }
                    }
                }
            }
        }
    }
}
