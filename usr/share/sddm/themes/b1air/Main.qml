import QtQuick
import QtQuick.Window
import QtQuick.Effects
import "components"
import "components/Words.js" as Words

// =============================================================================
// b1air's login screen: the desktop's lock screen (src/lock), before login.
//
// The wallpaper the desktop last showed (/var/cache/wallpaper/current.jpg,
// shared with sddm through the `wallpaper` group), blurred under a light
// veil; the time and the date at the top; the account's picture and name
// and the password in a glass pill below the middle; Sleep, Restart and
// Shut down at the foot, the session and the other accounts at its left
// and the keyboard layout at its right. Colours are the desktop's
// (components/ThemeColors.qml), the words Russian, Ukrainian or English.
//
// The password field has the focus from the start: type and press Enter.
// Keys typed anywhere go into it. Every other screen shows the picture and
// the clock only, until it is the one the keyboard types into: then it shows
// the password there, with what was typed.
// =============================================================================
Rectangle {
    id: root
    width: 1920
    height: 1080
    color: ThemeColors.ground

    readonly property real u: Math.min(width, height) / 1080
    // The language Settings speaks on the desktop, else the system's.
    readonly property string lang: (ThemeColors.lang || Qt.locale().name).substring(0, 2)
    function tr(text) { return Words.tr(root.lang, text); }
    function setting(key, fallback) {
        const v = config[key];
        return v !== undefined && v !== null && String(v) !== "" ? String(v) : fallback;
    }

    // sddm draws one of these a screen; `primaryScreen` says which is the
    // one to log in on.
    readonly property bool primary: typeof primaryScreen === "undefined" || primaryScreen
    // The login shows where the keyboard types, which with no window manager
    // is the screen under the pointer, not always the primary one.
    property bool typedHere: false
    readonly property bool here: primary || typedHere

    focus: true
    Component.onCompleted: root.here ? password.forceActiveFocus() : root.forceActiveFocus()
    Window.onActiveChanged: if (Window.active && root.here && !password.activeFocus) password.forceActiveFocus()

    // A key the field did not take, because it did not have the focus: into
    // the field it goes.
    Keys.onPressed: event => {
        if (!root.user || !root.user.needsPassword || root.busy) return;
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.typedHere = true;
            password.forceActiveFocus();
            root.login();
            event.accepted = true;
        } else if (event.text !== "" && event.text.charCodeAt(0) >= 32 && !(event.modifiers & (Qt.ControlModifier | Qt.MetaModifier))) {
            root.typedHere = true;
            root.menu = "";
            password.forceActiveFocus();
            password.insert(password.cursorPosition, event.text);
            root.failed = false;
            event.accepted = true;
        }
    }

    // ── Accounts and sessions, out of sddm's models ──────────────────────────
    property var users: []
    property int userIndex: userModel.lastIndex >= 0 ? userModel.lastIndex : 0
    readonly property var user: users.length ? users[Math.min(userIndex, users.length - 1)] : null
    readonly property string userName: user ? (user.realName || user.login) : ""
    Instantiator {
        model: userModel
        delegate: QtObject {
            required property string name
            required property string realName
            required property string icon
            required property bool needsPassword
            readonly property string login: name
        }
        onObjectAdded: (index, object) => { const a = root.users.slice(); a.splice(index, 0, object); root.users = a; }
        onObjectRemoved: (index, object) => { const a = root.users.slice(); a.splice(index, 1); root.users = a; }
    }

    property var sessions: []
    property int sessionIndex: sessionModel.lastIndex >= 0 ? sessionModel.lastIndex : 0
    Instantiator {
        model: sessionModel
        delegate: QtObject {
            required property string name
        }
        onObjectAdded: (index, object) => { const a = root.sessions.slice(); a.splice(index, 0, object); root.sessions = a; }
        onObjectRemoved: (index, object) => { const a = root.sessions.slice(); a.splice(index, 1); root.sessions = a; }
    }

    // ── Logging in ───────────────────────────────────────────────────────────
    property bool busy: false
    property bool failed: false
    property string menu: ""     // "session", "user", or none open
    property bool menuUnderAvatar: false   // the accounts, opened from the picture

    function login() {
        if (!root.user || root.busy) return;
        if (root.user.needsPassword && password.text === "") return;
        root.busy = true;
        root.failed = false;
        sddm.login(root.user.login, password.text, root.sessionIndex);
    }
    Connections {
        target: sddm
        function onLoginFailed() {
            root.busy = false;
            root.failed = true;
            password.text = "";
            shake.restart();
            password.forceActiveFocus();
        }
    }

    property date now: new Date()
    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.now = new Date()
    }

    // ── The picture ──────────────────────────────────────────────────────────
    Image {
        id: wallpaper
        readonly property string fallback: Qt.resolvedUrl("backgrounds/default.jpg")
        anchors.fill: parent
        source: {
            const s = root.setting("background", "/var/cache/wallpaper/current.jpg");
            return s.startsWith("/") ? "file://" + s : Qt.resolvedUrl(s);
        }
        onStatusChanged: if (status === Image.Error && source != fallback) source = fallback
        // A small copy drawn up to the screen is already soft, as on the lock
        // screen, and needs no shader; the blur smooths it where there is one.
        sourceSize: Qt.size(Math.max(32, root.width / 12), Math.max(18, root.height / 12))
        fillMode: Image.PreserveAspectCrop
        smooth: true
        layer.enabled: GraphicsInfo.api !== GraphicsInfo.Software
        layer.effect: MultiEffect {
            blurEnabled: true
            blur: 1.0
            blurMax: 48
            autoPaddingEnabled: false
        }
    }
    Rectangle { anchors.fill: parent; color: "#29000000" }
    Rectangle {   // deeper behind the clock
        width: parent.width
        height: parent.height * 0.45
        gradient: Gradient {
            GradientStop { position: 0; color: "#42000000" }
            GradientStop { position: 1; color: "#00000000" }
        }
    }
    Rectangle {   // and behind the password and the buttons
        y: parent.height * 0.55
        width: parent.width
        height: parent.height * 0.45
        gradient: Gradient {
            GradientStop { position: 0; color: "#00000000" }
            GradientStop { position: 1; color: "#38000000" }
        }
    }

    // A click anywhere else closes a menu.
    MouseArea {
        anchors.fill: parent
        enabled: root.menu !== ""
        onClicked: root.menu = ""
    }

    // ── The time and the date ────────────────────────────────────────────────
    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        y: 92 * root.u
        spacing: 2 * root.u
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.formatTime(root.now, root.setting("clock-format", "hh:mm"))
            color: "white"
            font.family: ThemeColors.sans
            font.weight: Font.Bold
            font.pixelSize: 128 * root.u
            style: Text.Raised
            styleColor: "#38000000"
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: Qt.locale(root.lang).toString(root.now, root.setting("date-format", "dddd, d MMMM"))
            color: "#e6ffffff"
            font.family: ThemeColors.sans
            font.pixelSize: 22 * root.u
            style: Text.Raised
            styleColor: "#38000000"
        }
    }

    // ── Who, and the password ────────────────────────────────────────────────
    Column {
        id: login
        visible: root.here && root.user !== null
        anchors.horizontalCenter: parent.horizontalCenter
        y: parent.height / 2 + 54 * root.u
        spacing: 0

        Avatar {
            anchors.horizontalCenter: parent.horizontalCenter
            size: 84 * root.u
            source: root.user ? root.user.icon : ""
            name: root.userName
            onClicked: if (root.users.length > 1) { root.menuUnderAvatar = true; root.menu = root.menu === "user" ? "" : "user"; }
        }
        Item { width: 1; height: 14 * root.u }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.userName
            color: "white"
            font.family: ThemeColors.sans
            font.weight: Font.Bold
            font.pixelSize: 20 * root.u
            style: Text.Raised
            styleColor: "#38000000"
        }
        Item { width: 1; height: 16 * root.u }

        // The field, a glass pill: the eye at its left once something is
        // typed, the arrow (or the wait) at its right.
        Item {
            width: field.width
            height: field.height
            anchors.horizontalCenter: parent.horizontalCenter

            Glass {
                id: field
                width: 300 * root.u
                height: 44 * root.u
                radius: height / 2
                tint: root.failed ? ThemeColors.error : "white"
                level: root.failed ? 0.30 : password.text !== "" ? 0.20 : 0.16
                rim: root.failed ? 0.85 : root.busy ? 0.7 : password.text !== "" ? 0.42 : 0.28
                visible: root.user !== null && root.user.needsPassword

                SequentialAnimation on x {
                    id: shake
                    running: false
                    loops: 1
                    NumberAnimation { to: -10 * root.u; duration: 50 }
                    NumberAnimation { to: 9 * root.u; duration: 70 }
                    NumberAnimation { to: -6 * root.u; duration: 70 }
                    NumberAnimation { to: 3 * root.u; duration: 60 }
                    NumberAnimation { to: 0; duration: 50 }
                }

                property bool reveal: false

                Item {
                    id: eye
                    visible: password.text !== ""
                    x: 6 * root.u
                    anchors.verticalCenter: parent.verticalCenter
                    width: 32 * root.u
                    height: width
                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: "#29ffffff"
                        visible: eyeMouse.containsMouse
                    }
                    Glyph {
                        anchors.centerIn: parent
                        name: field.reveal ? "eye-off" : "eye"
                        size: 17 * root.u
                        opacity: field.reveal ? 0.95 : 0.7
                    }
                    MouseArea {
                        id: eyeMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: { field.reveal = !field.reveal; password.forceActiveFocus(); }
                    }
                }

                TextInput {
                    id: password
                    objectName: "password"
                    anchors.fill: parent
                    anchors.leftMargin: 44 * root.u
                    anchors.rightMargin: 44 * root.u
                    verticalAlignment: TextInput.AlignVCenter
                    horizontalAlignment: TextInput.AlignHCenter
                    echoMode: field.reveal ? TextInput.Normal : TextInput.Password
                    passwordCharacter: "●"
                    color: "white"
                    selectionColor: ThemeColors.primary
                    selectedTextColor: ThemeColors.primaryText
                    font.family: ThemeColors.sans
                    font.pixelSize: (field.reveal ? 16 : 12) * root.u
                    font.letterSpacing: field.reveal ? 0 : 3 * root.u
                    clip: true
                    focus: root.here
                    readOnly: root.busy
                    onAccepted: root.login()
                    onTextEdited: root.failed = false
                    Keys.onEscapePressed: { text = ""; root.menu = ""; }
                }
                Text {
                    anchors.centerIn: parent
                    visible: password.text === ""
                    text: root.tr("Enter password")
                    color: "#9effffff"
                    font.family: ThemeColors.sans
                    font.pixelSize: 15 * root.u
                }

                Item {
                    id: go
                    visible: password.text !== "" || root.busy
                    anchors.right: parent.right
                    anchors.rightMargin: 6 * root.u
                    anchors.verticalCenter: parent.verticalCenter
                    width: 32 * root.u
                    height: width
                    Rectangle {
                        anchors.fill: parent
                        radius: width / 2
                        color: goMouse.containsMouse ? "#47ffffff" : "#29ffffff"
                    }
                    Glyph {
                        anchors.centerIn: parent
                        name: root.busy ? "loader" : "arrow-right"
                        size: 17 * root.u
                        RotationAnimation on rotation {
                            running: root.busy
                            from: 0
                            to: 360
                            duration: 900
                            loops: Animation.Infinite
                        }
                        rotation: 0
                    }
                    MouseArea {
                        id: goMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.login()
                    }
                }
            }

            // An account without a password: a button, no field.
            Pill {
                anchors.centerIn: parent
                visible: root.user !== null && !root.user.needsPassword
                u: root.u
                icon: root.busy ? "loader" : "arrow-right"
                text: root.busy ? root.tr("Logging in…") : root.tr("Log in")
                onClicked: root.login()
            }
        }

        Item { width: 1; height: 14 * root.u }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: text !== ""
            text: root.failed ? root.tr("Wrong password") : root.busy ? root.tr("Logging in…") : ""
            color: "#ebffffff"
            font.family: ThemeColors.sans
            font.pixelSize: 15 * root.u
            style: Text.Raised
            styleColor: "#38000000"
        }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: keyboard.capsLock
            spacing: 6 * root.u
            topPadding: 6 * root.u
            Glyph { anchors.verticalCenter: parent.verticalCenter; name: "caps"; size: 15 * root.u }
            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: root.tr("Caps Lock is on")
                color: "#d9ffffff"
                font.family: ThemeColors.sans
                font.pixelSize: 14 * root.u
                style: Text.Raised
                styleColor: "#38000000"
            }
        }
    }

    // ── The foot ─────────────────────────────────────────────────────────────
    Row {
        id: power
        visible: root.here
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 28 * root.u
        spacing: 28 * root.u
        RoundButton {
            visible: sddm.canSuspend
            u: root.u
            icon: "sleep"
            label: root.tr("Sleep")
            onClicked: sddm.suspend()
        }
        RoundButton {
            visible: sddm.canReboot
            u: root.u
            icon: "restart"
            label: root.tr("Restart")
            onClicked: sddm.reboot()
        }
        RoundButton {
            visible: sddm.canPowerOff
            u: root.u
            icon: "power"
            label: root.tr("Shut down")
            onClicked: sddm.powerOff()
        }
    }

    Row {
        id: footLeft
        visible: root.here
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 28 * root.u
        anchors.bottomMargin: 56 * root.u   // level with the power circles
        spacing: 10 * root.u
        Pill {
            id: sessionPill
            visible: root.sessions.length > 1
            u: root.u
            icon: "session"
            text: root.sessions.length ? root.sessions[Math.min(root.sessionIndex, root.sessions.length - 1)].name : ""
            active: root.menu === "session"
            onClicked: root.menu = root.menu === "session" ? "" : "session"
        }
        Pill {
            id: userPill
            visible: root.users.length > 1
            u: root.u
            icon: "users"
            text: root.tr("Users")
            active: root.menu === "user"
            onClicked: { root.menuUnderAvatar = false; root.menu = root.menu === "user" ? "" : "user"; }
        }
    }

    Pill {
        visible: root.here && keyboard.layouts.length > 1
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 28 * root.u
        anchors.bottomMargin: 56 * root.u   // level with the power circles
        u: root.u
        icon: "keyboard"
        text: {
            const l = keyboard.layouts[keyboard.currentLayout];
            return l ? String(l.shortName).toUpperCase() : "";
        }
        onClicked: {
            keyboard.currentLayout = (keyboard.currentLayout + 1) % keyboard.layouts.length;
            password.forceActiveFocus();
        }
    }

    // ── The menus ────────────────────────────────────────────────────────────
    Menu {
        visible: root.menu === "session"
        u: root.u
        x: footLeft.x + sessionPill.x
        y: footLeft.y - height - 8 * root.u
        items: root.sessions.map(s => ({ text: s.name }))
        current: root.sessionIndex
        onPicked: index => { root.sessionIndex = index; root.menu = ""; password.forceActiveFocus(); }
    }
    Menu {
        visible: root.menu === "user"
        u: root.u
        x: root.menuUnderAvatar ? (root.width - width) / 2 : footLeft.x + userPill.x
        y: root.menuUnderAvatar ? login.y + 84 * root.u + 8 * root.u : footLeft.y - height - 8 * root.u
        items: root.users.map(u => ({ text: u.realName || u.login }))
        current: root.userIndex
        onPicked: index => {
            root.userIndex = index;
            root.menu = "";
            root.failed = false;
            password.text = "";
            password.forceActiveFocus();
        }
    }
}
