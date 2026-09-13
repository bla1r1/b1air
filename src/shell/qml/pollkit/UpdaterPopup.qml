import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import "../Ui"
import B1air.Daemon

PopupShell {
    id: window

    property string currentTab: "dotfiles" // "dotfiles" | "system"
    property string localVersion: "..."
    property string remoteVersion: "..."
    property bool updateAvailable: false
    property string fullCommitMessage: ""
    property string displayedCommitMessage: "Fetching changelog..."
    property int typeIndex: 0

    readonly property int holdDuration: 1200
    readonly property int drainDuration: 800
    readonly property int glowPeriod: 1500
    readonly property int wavePeriod: 1000
    readonly property int typeInterval: 12

    // The status check and both update buttons used to run
    // ~/.config/sway/scripts/system/dotfiles-update.sh, which does not exist
    // anywhere in this repository or the installer. This popup has never
    // actually worked — every action here was a silent no-op ("bash: no such
    // file"). Wired to the daemon's real dotfiles_status_json()/dotfiles_sync()/
    // dotfiles_sys(), which already return and do exactly what this UI expects.
    Connections {
        target: Daemon
        function onDotfilesStatusReady(tag, json) {
            try {
                let data = JSON.parse(json);
                if (!data.ok) {
                    window.localVersion = "local";
                    window.remoteVersion = "unavailable";
                    window.updateAvailable = false;
                    window.displayedCommitMessage = "Repository not found.";
                    return;
                }
                window.localVersion = data.branch + "@" + data.local_hash;
                window.remoteVersion = data.remote_hash ? (data.branch + "@" + data.remote_hash) : "up to date";
                window.updateAvailable = !!data.update_available;

                window.fullCommitMessage = data.remote_message || "No changelog available.";
                window.displayedCommitMessage = "";
                window.typeIndex = 0;
                commitTypeTimer.start();
            } catch (e) {
                window.localVersion = "local";
                window.remoteVersion = "unavailable";
                window.updateAvailable = false;
                window.displayedCommitMessage = "Failed to parse update status.";
            }
        }
    }
    Component.onCompleted: Daemon.requestDotfilesStatus()

    Timer {
        id: commitTypeTimer
        interval: window.typeInterval
        repeat: true
        onTriggered: {
            if (window.typeIndex < window.fullCommitMessage.length) {
                window.displayedCommitMessage += window.fullCommitMessage.charAt(window.typeIndex);
                window.typeIndex++;
            } else {
                stop();
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Design.s(Design.space.md)

        // ── Header ────────────────────────────────────────────────────────────
        //
        // This window was the only surface in the shell that did not say what
        // it was: it opened straight onto two unlabelled pills. Control Center,
        // Clipboard History, Launchpad and Power & Session all name themselves
        // in the same icon-plus-title row, and so does this now.
        RowLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.sm)

            Icon {
                text: "\u{f06b0}" // download
                role: "subhead"
                color: Design.accent
            }

            Label {
                text: "Updates"
                role: "subhead"
                weight: Design.weight.bold
            }

            Item { Layout.fillWidth: true }
        }

        // ── Tab Switcher ──────────────────────────────────────────────────────
        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            spacing: Design.s(Design.space.sm)

            Pill {
                label: "Desktop & UI"
                icon: "󰚰"
                active: window.currentTab === "dotfiles"
                onClicked: window.currentTab = "dotfiles"
            }

            Pill {
                label: "System Packages"
                icon: "󰏗"
                active: window.currentTab === "system"
                onClicked: window.currentTab = "system"
            }
        }

        // ── Mode 1: Dotfiles / Desktop Environment ────────────────────────────
        ColumnLayout {
            visible: window.currentTab === "dotfiles"
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Design.s(Design.space.md)

            Badge {
                Layout.alignment: Qt.AlignHCenter
                tone: window.updateAvailable ? Design.ok : Design.accent
                text: window.updateAvailable ? "NEW UI UPDATE AVAILABLE" : "ENVIRONMENT UP TO DATE"
            }

            // ── Version transition ────────────────────────────────────────────
            Item {
                id: versionContainer
                Layout.fillWidth: true
                Layout.preferredHeight: Design.s(36)

                readonly property real finalNewX: (width - newVer.implicitWidth) / 2
                readonly property real finalArrowX: finalNewX - arrowIcon.implicitWidth - Design.s(Design.space.xl)
                readonly property real finalOldX: finalArrowX - oldVer.implicitWidth - Design.s(Design.space.xl)
                readonly property real initialOldX: (width - oldVer.implicitWidth) / 2

                Label {
                    role: "subhead"
                    id: oldVer
                    visible: window.updateAvailable
                    text: window.localVersion
                    dim: true
                    anchors.verticalCenter: parent.verticalCenter
                    x: versionContainer.initialOldX
                }

                // Hidden when there is nothing to move to: with no update
                // pending both sides of the arrow hold the same commit, and
                // "main@cc1c7dd → main@cc1c7dd" reads as a transition that is
                // not happening.
                Icon {
                    id: arrowIcon
                    visible: window.updateAvailable
                    text: "󰁕"
                    color: Design.accent
                    anchors.verticalCenter: parent.verticalCenter
                    x: versionContainer.finalOldX + oldVer.implicitWidth
                    opacity: 0
                }

                Label {
                    role: "display"
                    id: newVer
                    text: window.remoteVersion
                    weight: Design.weight.semibold
                    color: Design.ok
                    anchors.verticalCenter: parent.verticalCenter
                    x: versionContainer.finalNewX
                    opacity: 0
                    scale: 0.9
                }

                MultiEffect {
                    id: newVerEffect
                    source: newVer
                    anchors.fill: newVer
                    shadowEnabled: true
                    shadowColor: Design.ok
                    shadowBlur: 0.0
                    shadowHorizontalOffset: 0
                    shadowVerticalOffset: 0
                    opacity: newVer.opacity
                }

                SequentialAnimation {
                    id: versionAnim
                    PauseAnimation { duration: Design.duration.fast }
                    ParallelAnimation {
                        NumberAnimation { target: oldVer; property: "x"; to: versionContainer.finalOldX; duration: Design.duration.slow; easing.type: Design.easing }
                        NumberAnimation { target: oldVer; property: "opacity"; to: 0.2; duration: Design.duration.slow; easing.type: Design.easing }
                    }
                    ParallelAnimation {
                        NumberAnimation { target: arrowIcon; property: "opacity"; to: 1; duration: Design.duration.base }
                        NumberAnimation { target: arrowIcon; property: "x"; to: versionContainer.finalArrowX; duration: Design.duration.slow; easing.type: Design.easing }
                    }
                    ParallelAnimation {
                        NumberAnimation { target: newVer; property: "opacity"; to: 1; duration: Design.duration.slow }
                        NumberAnimation { target: newVer; property: "scale"; to: 1.0; duration: Design.duration.slow; easing.type: Design.easing }
                        ScriptAction { script: glowAnim.start() }
                    }
                }

                SequentialAnimation {
                    id: glowAnim
                    loops: Animation.Infinite
                    NumberAnimation { target: newVerEffect; property: "shadowBlur"; to: 0.8; duration: window.glowPeriod; easing.type: Easing.InOutSine }
                    NumberAnimation { target: newVerEffect; property: "shadowBlur"; to: 0.2; duration: window.glowPeriod; easing.type: Easing.InOutSine }
                }

                Connections {
                    target: window
                    function onRemoteVersionChanged() {
                        if (window.remoteVersion !== "..." && window.remoteVersion !== "")
                            versionAnim.start();
                    }
                }
            }

            // ── Changelog ─────────────────────────────────────────────────────
            ScrollArea {
                id: changelog
                Layout.fillWidth: true
                Layout.fillHeight: true

                Label {
                    width: changelog.availableWidth
                    text: window.displayedCommitMessage
                    wrapMode: Text.WordWrap
                    horizontalAlignment: Text.AlignLeft
                    verticalAlignment: Text.AlignTop
                    lineHeight: 1.4
                }
            }

            // ── Hold to update ────────────────────────────────────────────────
            Rectangle {
                id: updateBtn
                Layout.fillWidth: true
                Layout.preferredHeight: Design.s(48)
                radius: Design.s(Design.radius.card)
                color: Design.raised
                border.color: btnMa.containsMouse ? Design.ok : Design.accent
                border.width: 1
                clip: true

                scale: btnMa.pressed ? 0.98 : (btnMa.containsMouse ? 1.01 : 1.0)
                Behavior on scale { NumberAnimation { duration: Design.duration.base; easing.type: Design.easing } }
                Behavior on border.color { ColorAnimation { duration: Design.duration.base } }

                property real fillLevel: 0.0
                property bool triggered: false
                readonly property bool filled: fillLevel > 0.5

                Canvas {
                    id: waveCanvas
                    anchors.fill: parent

                    property real wavePhase: 0.0
                    NumberAnimation on wavePhase {
                        running: updateBtn.fillLevel > 0.0 && updateBtn.fillLevel < 1.0
                        loops: Animation.Infinite
                        from: 0; to: Math.PI * 2
                        duration: window.wavePeriod
                    }

                    onWavePhaseChanged: requestPaint()
                    Connections { target: updateBtn; function onFillLevelChanged() { waveCanvas.requestPaint() } }

                    onPaint: {
                        var ctx = getContext("2d");
                        ctx.clearRect(0, 0, width, height);
                        if (updateBtn.fillLevel <= 0.001) return;

                        var currentW = width * updateBtn.fillLevel;
                        var r = Design.s(Design.radius.card);

                        ctx.save();
                        ctx.beginPath();
                        ctx.moveTo(0, 0);

                        if (updateBtn.fillLevel < 0.99) {
                            var waveAmp = Design.s(Design.space.sm) * Math.sin(updateBtn.fillLevel * Math.PI);
                            var cp1x = currentW + Math.sin(wavePhase) * waveAmp;
                            var cp2x = currentW + Math.cos(wavePhase + Math.PI) * waveAmp;
                            ctx.lineTo(currentW, 0);
                            ctx.bezierCurveTo(cp2x, height * 0.33, cp1x, height * 0.66, currentW, height);
                            ctx.lineTo(0, height);
                        } else {
                            ctx.lineTo(width, 0);
                            ctx.lineTo(width, height);
                            ctx.lineTo(0, height);
                        }
                        ctx.closePath();
                        ctx.clip();

                        ctx.beginPath();
                        ctx.roundedRect(0, 0, width, height, r, r);
                        var grad = ctx.createLinearGradient(0, 0, width, 0);
                        grad.addColorStop(0, Qt.darker(Design.ok, 1.1).toString());
                        grad.addColorStop(1, Design.ok.toString());
                        ctx.fillStyle = grad;
                        ctx.fill();

                        ctx.restore();
                    }
                }

                RowLayout {
                    anchors.centerIn: parent
                    spacing: Design.s(Design.space.md)

                    Icon {
                        text: "󰚰"
                        color: updateBtn.filled ? Design.ground : Design.ok
                        Behavior on color { ColorAnimation { duration: Design.duration.fast } }
                    }

                    Label {
                        text: updateBtn.fillLevel > 0 ? "HOLDING..." : "HOLD TO PULL & SYNC UI"
                        weight: Design.weight.semibold
                        color: updateBtn.filled ? Design.ground : Design.ok
                        Behavior on color { ColorAnimation { duration: Design.duration.fast } }
                    }
                }

                Clickable {
                    id: btnMa
                    cursorShape: updateBtn.triggered ? Qt.ArrowCursor : Qt.PointingHandCursor
                    onPressed: {
                        if (!updateBtn.triggered) {
                            drainAnim.stop();
                            fillAnim.start();
                        }
                    }
                    onReleased: {
                        if (!updateBtn.triggered && updateBtn.fillLevel < 1.0) {
                            fillAnim.stop();
                            drainAnim.start();
                        }
                    }
                }

                NumberAnimation {
                    id: fillAnim
                    target: updateBtn
                    property: "fillLevel"
                    to: 1.0
                    duration: window.holdDuration * (1.0 - updateBtn.fillLevel)
                    easing.type: Easing.InSine
                    onFinished: {
                        updateBtn.triggered = true;
                        Daemon.dotfilesSync();
                        window.close();
                    }
                }

                NumberAnimation {
                    id: drainAnim
                    target: updateBtn
                    property: "fillLevel"
                    to: 0.0
                    duration: window.drainDuration * updateBtn.fillLevel
                    easing.type: Design.easing
                }
            }
        }

        // ── Mode 2: Full System Packages (Arch / AUR) ─────────────────────────
        ColumnLayout {
            visible: window.currentTab === "system"
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Design.s(Design.space.md)

            Badge {
                Layout.alignment: Qt.AlignHCenter
                tone: Design.accent
                text: "ARCH LINUX & AUR PACKAGES"
            }

            Card {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Design.s(Design.space.md)
                    spacing: Design.s(Design.space.sm)

                    RowLayout {
                        spacing: Design.s(Design.space.md)
                        Icon { text: "󰏗"; role: "title"; color: Design.accent }
                        ColumnLayout {
                            spacing: Design.s(Design.space.xxs)
                            Label { text: "System-wide Upgrade"; role: "subhead"; weight: Design.weight.semibold }
                            Label { text: "Runs your package manager (and the AUR helper on Arch) to update every package"; dim: true }
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 1
                        color: Design.tint(Design.line, 0.4)
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Design.s(Design.space.xs)
                        Label { text: "• Upgrades Linux kernel, drivers, and libraries"; role: "caption"; dim: true }
                        Label { text: "• Rebuilds outdated AUR packages safely in terminal"; role: "caption"; dim: true }
                        Label { text: "• Shows interactive terminal for sudo authentication"; role: "caption"; dim: true }
                    }

                    Item { Layout.fillHeight: true }
                }
            }

            ActionButton {
                Layout.fillWidth: true
                Layout.preferredHeight: Design.s(48)
                label: "RUN SYSTEM UPGRADE (YAY / PACMAN)"
                icon: "󰓦"
                onActivated: {
                    Daemon.dotfilesSys();
                    window.close();
                }
            }
        }
    }
}
