import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import QtQuick.Controls
import QtMultimedia
import "Ui"

// =============================================================================
// Camera — preview, stills and video.
//
// QtMultimedia's CaptureSession does the work: a Camera feeding a VideoOutput,
// with ImageCapture for stills and MediaRecorder for video. Everything lands in
// ~/Pictures/Camera (CameraDir, made by main.cpp before the window loads).
// =============================================================================

ApplicationWindow {
    id: window

    title: "Camera"
    width: Design.s(900)
    height: Design.s(620)
    minimumWidth: 560
    minimumHeight: 420
    visible: true
    color: "transparent"

    readonly property string shotsDir: typeof CameraDir !== "undefined" ? CameraDir : ""

    // Not a property binding: an object declaration assigned to `property var`
    // is legal but evaluates once and hides the change signals, and the device
    // list has to stay live — plugging a webcam in must light up the picker.
    MediaDevices { id: devices }

    property string lastShot: ""
    property string status: ""
    property bool mirrored: true
    property bool showGrid: false
    property int timerSeconds: 0        // 0, 3 or 10
    property int countdown: 0

    function note(text) {
        window.status = text;
        noteTimer.restart();
    }
    Timer { id: noteTimer; interval: 3500; onTriggered: window.status = "" }

    function stamp() {
        return Qt.formatDateTime(new Date(), "yyyy-MM-dd_hh-mm-ss");
    }

    // The shutter, with the self-timer in front of it when one is set.
    function shoot() {
        if (window.countdown > 0)
            return;
        if (window.timerSeconds > 0) {
            window.countdown = window.timerSeconds;
            countdownTimer.start();
            return;
        }
        capture.captureToFile(window.shotsDir + "/Photo_" + window.stamp() + ".jpg");
    }

    Timer {
        id: countdownTimer
        interval: 1000
        repeat: true
        onTriggered: {
            window.countdown--;
            if (window.countdown <= 0) {
                countdownTimer.stop();
                capture.captureToFile(window.shotsDir + "/Photo_" + window.stamp() + ".jpg");
            }
        }
    }

    function toggleRecording() {
        if (recorder.recorderState === MediaRecorder.RecordingState) {
            recorder.stop();
        } else {
            recorder.outputLocation = "file://" + window.shotsDir + "/Video_" + window.stamp() + ".mp4";
            recorder.record();
        }
    }

    readonly property bool recording: recorder.recorderState === MediaRecorder.RecordingState

    CaptureSession {
        id: session
        camera: Camera {
            id: camera
            active: true
            onErrorOccurred: (error, errorString) => window.note(errorString)
        }
        imageCapture: ImageCapture {
            id: capture
            onImageSaved: (id, path) => {
                window.lastShot = path;
                window.note("Saved " + path.split("/").pop());
            }
            onErrorOccurred: (id, error, message) => window.note(message)
        }
        recorder: MediaRecorder {
            id: recorder
            quality: MediaRecorder.HighQuality
            onRecorderStateChanged: {
                if (recorder.recorderState === MediaRecorder.StoppedState && recorder.actualLocation != "") {
                    window.lastShot = String(recorder.actualLocation).replace("file://", "");
                    window.note("Saved " + window.lastShot.split("/").pop());
                }
            }
            onErrorOccurred: (error, errorString) => window.note(errorString)
        }
        videoOutput: preview
    }

    Shortcut { sequence: "Space"; onActivated: window.shoot() }
    Shortcut { sequence: "R"; onActivated: window.toggleRecording() }
    Shortcut { sequence: "G"; onActivated: window.showGrid = !window.showGrid }
    Shortcut { sequence: "M"; onActivated: window.mirrored = !window.mirrored }
    Shortcut { sequence: "Ctrl+O"; onActivated: Qt.openUrlExternally("file://" + window.shotsDir) }
    Shortcut { sequence: "Escape"; onActivated: window.close() }

    Rectangle {
        id: windowFrame
        anchors.fill: parent
        // No corners or outline of our own: sway draws both (see the app
        // windows' frames elsewhere in this suite).
        radius: 0
        color: Design.ground

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // ── Title bar ────────────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Design.s(36)
                color: Design.surface

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Design.s(10)
                    anchors.rightMargin: Design.s(10)
                    spacing: Design.s(8)

                    Icon { text: "\u{f03d}"; role: "body"; color: Design.sapphire }
                    Label { text: "Camera"; weight: Design.weight.bold }

                    Item { Layout.fillWidth: true }

                    // Which camera, when the machine has more than one.
                    Pill {
                        visible: devices.videoInputs.length > 1
                        label: camera.cameraDevice.description || "Camera"
                        onClicked: {
                            const list = devices.videoInputs;
                            let i = 0;
                            for (let n = 0; n < list.length; n++)
                                if (list[n].id === camera.cameraDevice.id) i = n;
                            camera.cameraDevice = list[(i + 1) % list.length];
                        }
                    }

                    IconButton {
                        icon: "\u{f0b45}"      // folder
                        hoverTone: Design.accent
                        onClicked: Qt.openUrlExternally("file://" + window.shotsDir)
                    }
                }
            }

            // ── Preview ──────────────────────────────────────────────────────
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                VideoOutput {
                    id: preview
                    anchors.fill: parent
                    fillMode: VideoOutput.PreserveAspectFit
                    // Mirrored by default: a preview of yourself that moves the
                    // other way is the one thing everyone notices.
                    transform: Scale { origin.x: preview.width / 2; xScale: window.mirrored ? -1 : 1 }
                }

                // Nothing to show: no camera, or it refused to start.
                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: Design.s(Design.space.sm)
                    visible: devices.videoInputs.length === 0
                    Icon { Layout.alignment: Qt.AlignHCenter; text: "\u{f0567}"; role: "title"; color: Design.textDim }
                    Label { Layout.alignment: Qt.AlignHCenter; text: "No camera found"; dim: true }
                }

                // Rule of thirds.
                Item {
                    anchors.fill: parent
                    visible: window.showGrid
                    Repeater {
                        model: 2
                        Rectangle {
                            width: 1
                            height: parent.height
                            x: parent.width * (index + 1) / 3
                            color: Design.tint(Design.text, 0.25)
                        }
                    }
                    Repeater {
                        model: 2
                        Rectangle {
                            height: 1
                            width: parent.width
                            y: parent.height * (index + 1) / 3
                            color: Design.tint(Design.text, 0.25)
                        }
                    }
                }

                // Recording badge.
                Rectangle {
                    visible: window.recording
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.margins: Design.s(12)
                    width: recRow.implicitWidth + Design.s(16)
                    height: Design.s(26)
                    radius: height / 2
                    color: Design.tint(Design.danger, 0.85)

                    RowLayout {
                        id: recRow
                        anchors.centerIn: parent
                        spacing: Design.s(6)
                        Rectangle {
                            width: Design.s(8); height: Design.s(8); radius: width / 2
                            color: Design.accentText
                            SequentialAnimation on opacity {
                                running: window.recording
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.2; duration: 600 }
                                NumberAnimation { to: 1.0; duration: 600 }
                            }
                        }
                        Label { text: "REC"; weight: Design.weight.bold; color: Design.accentText; isMono: true }
                    }
                }

                // Self-timer count.
                Label {
                    anchors.centerIn: parent
                    visible: window.countdown > 0
                    text: window.countdown
                    font.pixelSize: Design.s(96)
                    weight: Design.weight.bold
                    color: Design.text
                }
            }

            // ── Controls ─────────────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Design.s(76)
                color: Design.surface

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Design.s(16)
                    anchors.rightMargin: Design.s(16)
                    spacing: Design.s(Design.space.md)

                    // The last shot, and the way back to it.
                    Rectangle {
                        Layout.preferredWidth: Design.s(52)
                        Layout.preferredHeight: Design.s(52)
                        radius: Design.s(Design.radius.ctl)
                        color: Design.sunken
                        border.color: Design.line
                        border.width: 1
                        clip: true

                        Image {
                            anchors.fill: parent
                            source: window.lastShot !== "" && window.lastShot.endsWith(".jpg") ? "file://" + window.lastShot : ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            sourceSize: Qt.size(104, 104)
                        }
                        Icon {
                            anchors.centerIn: parent
                            visible: window.lastShot === ""
                            text: "\u{f0210}"
                            role: "body"
                            color: Design.textFaint
                        }
                        MouseArea {
                            anchors.fill: parent
                            enabled: window.lastShot !== ""
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: Qt.openUrlExternally("file://" + window.lastShot)
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // Shutter.
                    Rectangle {
                        Layout.preferredWidth: Design.s(58)
                        Layout.preferredHeight: Design.s(58)
                        radius: width / 2
                        color: shutterMa.containsMouse ? Design.hover : Design.raised
                        border.color: Design.text
                        border.width: 2
                        scale: shutterMa.pressed ? 0.94 : 1.0
                        Behavior on scale { NumberAnimation { duration: Design.duration.fast } }

                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width - Design.s(12)
                            height: width
                            radius: width / 2
                            color: Design.text
                        }
                        MouseArea {
                            id: shutterMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: window.shoot()
                        }
                    }

                    // Record.
                    Rectangle {
                        Layout.preferredWidth: Design.s(46)
                        Layout.preferredHeight: Design.s(46)
                        radius: width / 2
                        color: window.recording ? Design.danger : (recMa.containsMouse ? Design.hover : Design.raised)
                        border.color: window.recording ? Design.danger : Design.line
                        border.width: 1

                        Rectangle {
                            anchors.centerIn: parent
                            width: window.recording ? Design.s(16) : Design.s(20)
                            height: width
                            radius: window.recording ? Design.s(3) : width / 2
                            color: window.recording ? Design.accentText : Design.danger
                            Behavior on width { NumberAnimation { duration: Design.duration.fast } }
                            Behavior on radius { NumberAnimation { duration: Design.duration.fast } }
                        }
                        MouseArea {
                            id: recMa
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: window.toggleRecording()
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // Self-timer, mirror, grid.
                    RowLayout {
                        spacing: Design.s(Design.space.xs)

                        Pill {
                            label: window.timerSeconds === 0 ? "Timer off" : window.timerSeconds + "s"
                            active: window.timerSeconds > 0
                            onClicked: window.timerSeconds = window.timerSeconds === 0 ? 3
                                     : (window.timerSeconds === 3 ? 10 : 0)
                        }
                        Pill {
                            label: "Mirror"
                            active: window.mirrored
                            onClicked: window.mirrored = !window.mirrored
                        }
                        Pill {
                            label: "Grid"
                            active: window.showGrid
                            onClicked: window.showGrid = !window.showGrid
                        }
                    }
                }
            }

            // ── Status bar ───────────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Design.s(26)
                color: Design.ground

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Design.s(12)
                    anchors.rightMargin: Design.s(12)

                    Label {
                        Layout.fillWidth: true
                        text: window.status !== "" ? window.status : window.shotsDir
                        role: "caption"
                        color: window.status !== "" ? Design.accent : Design.textDim
                        elide: Text.ElideMiddle
                    }

                    Label { text: "Space Shoot · R Record · G Grid · M Mirror"; role: "caption"; dim: true; isMono: true }
                }
            }
        }
    }
}
