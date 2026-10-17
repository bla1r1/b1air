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

    // Colours for every stock control in the window — tooltips, scroll bars,
    // combo boxes, text fields — from the desktop palette. Left to the Basic
    // style they were its own: a pale-yellow tooltip, light-grey bars.
    palette.window: Design.surface
    palette.windowText: Design.text
    palette.base: Design.sunken
    palette.alternateBase: Design.raised
    palette.text: Design.text
    palette.button: Design.raised
    palette.buttonText: Design.text
    palette.brightText: Design.text
    palette.highlight: Design.accent
    palette.highlightedText: Design.accentText
    palette.toolTipBase: Design.raised
    palette.toolTipText: Design.text
    palette.placeholderText: Design.textFaint
    palette.light: Design.highest
    palette.midlight: Design.high
    palette.mid: Design.line
    palette.dark: Design.sunken
    palette.shadow: Design.ground

    title: I18n.tr("Camera")
    width: Design.s(Design.window.compactWidth)
    height: Design.s(Design.window.compactHeight)
    minimumWidth: Design.s(Design.window.minWidth)
    minimumHeight: Design.s(Design.window.minHeight)
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
    // What the shutter does: one button in the middle, photo or video, chosen
    // in the toolbar. There were two side by side, a white one and a red one.
    property string captureMode: "photo"
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
    // Shutter and record do nothing without a camera, and look it.
    readonly property bool hasCamera: devices.videoInputs.length > 0

    function shoot() {
        if (!window.hasCamera || window.countdown > 0)
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
        if (!window.hasCamera) return;
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
                window.note(I18n.tr("Saved %1", path.split("/").pop()));
            }
            onErrorOccurred: (id, error, message) => window.note(message)
        }
        recorder: MediaRecorder {
            id: recorder
            quality: MediaRecorder.HighQuality
            onRecorderStateChanged: {
                if (recorder.recorderState === MediaRecorder.StoppedState && recorder.actualLocation != "") {
                    window.lastShot = String(recorder.actualLocation).replace("file://", "");
                    window.note(I18n.tr("Saved %1", window.lastShot.split("/").pop()));
                }
            }
            onErrorOccurred: (error, errorString) => window.note(errorString)
        }
        videoOutput: preview
    }

    // Space is the shutter of the mode in use; R records from either.
    Shortcut { sequence: "Space"; onActivated: window.captureMode === "video" ? window.toggleRecording() : window.shoot() }
    Shortcut { sequence: "R"; onActivated: { window.captureMode = "video"; window.toggleRecording(); } }
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
            AppToolbar {
                Layout.fillWidth: true

                SegmentedControl {
                    size: "sm"
                    enabled: !window.recording
                    model: [
                        { id: "photo", label: I18n.tr("Photo"), icon: "\u{f0100}" },
                        { id: "video", label: I18n.tr("Video"), icon: "\u{f0567}" }
                    ]
                    current: window.captureMode
                    onPicked: id => window.captureMode = id
                }
                Item { Layout.fillWidth: true }
                // Self-timer, mirror and grid: settings of the shot, so with the
                // mode, not beside the shutter.
                Button {
                    variant: "ghost"
                    icon: "\u{f051b}"
                    iconOnly: window.timerSeconds === 0
                    label: window.timerSeconds === 0 ? I18n.tr("Self-timer") : window.timerSeconds + " s"
                    tip: I18n.tr("Self-timer: off, 3 s, 10 s")
                    checked: window.timerSeconds > 0
                    onClicked: window.timerSeconds = window.timerSeconds === 0 ? 3
                             : (window.timerSeconds === 3 ? 10 : 0)
                }
                Button { variant: "ghost"; iconOnly: true; icon: "\u{f10e7}"; tip: I18n.tr("Mirror (M)"); checked: window.mirrored; onClicked: window.mirrored = !window.mirrored }
                Button { variant: "ghost"; iconOnly: true; icon: "\u{f02c1}"; tip: I18n.tr("Grid (G)"); checked: window.showGrid; onClicked: window.showGrid = !window.showGrid }
                // Which camera, when the machine has more than one.
                Button {
                    variant: "ghost"
                    iconOnly: true
                    visible: devices.videoInputs.length > 1
                    icon: "\u{f0567}"
                    tip: I18n.tr("Switch camera") + " · " + (camera.cameraDevice.description || I18n.tr("Camera"))
                    onClicked: {
                        const list = devices.videoInputs;
                        let i = 0;
                        for (let n = 0; n < list.length; n++)
                            if (list[n].id === camera.cameraDevice.id) i = n;
                        camera.cameraDevice = list[(i + 1) % list.length];
                    }
                }
                Button {
                    variant: "ghost"
                    iconOnly: true
                    icon: "\u{f024b}"
                    tip: I18n.tr("Where photos and videos go (Ctrl+O)")
                    onClicked: Qt.openUrlExternally(Paths.fileUrl(window.shotsDir))
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
                AppState {
                    anchors.fill: parent
                    readonly property bool none: devices.videoInputs.length === 0
                    mode: none ? "empty" : camera.error !== Camera.NoError ? "error" : ""
                    icon: none ? "\u{f0567}" : ""
                    title: none ? I18n.tr("No camera found") : I18n.tr("Camera unavailable")
                    hint: none ? I18n.tr("Plug one in; it shows up here without restarting.") : camera.errorString
                    actionText: none ? "" : I18n.tr("Try again")
                    // Another app letting go of the camera is the usual fix,
                    // and the device is only asked again when it is reopened.
                    onAction: { camera.stop(); camera.start(); }
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
                    anchors.margins: Design.s(Design.space.md)
                    width: recRow.implicitWidth + Design.s(Design.space.lg)
                    height: Design.s(Design.size.xs)
                    radius: height / 2
                    color: Design.tint(Design.danger, 0.85)

                    RowLayout {
                        id: recRow
                        anchors.centerIn: parent
                        spacing: Design.s(Design.space.xs)
                        Rectangle {
                            width: Design.s(Design.space.sm); height: Design.s(Design.space.sm); radius: width / 2
                            color: Design.accentText
                            SequentialAnimation on opacity {
                                running: window.recording
                                loops: Animation.Infinite
                                NumberAnimation { to: 0.2; duration: 600 }
                                NumberAnimation { to: 1.0; duration: 600 }
                            }
                        }
                        Label { text: I18n.tr("REC"); weight: Design.weight.semibold; color: Design.accentText; isMono: true }
                    }
                }

                // Self-timer count.
                Label {
                    anchors.centerIn: parent
                    visible: window.countdown > 0
                    text: window.countdown
                    font.pixelSize: Design.s(Design.font.hero)
                    weight: Design.weight.bold
                    color: Design.text
                }
            }

            // ── Controls ─────────────────────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Design.s(Design.size.media)
                color: Design.surface

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Design.s(Design.space.lg)
                    anchors.rightMargin: Design.s(Design.space.lg)
                    spacing: Design.s(Design.space.md)

                    // The last shot, and the way back to it.
                    Rectangle {
                        Layout.preferredWidth: Design.s(Design.size.rowTall)
                        Layout.preferredHeight: Design.s(Design.size.rowTall)
                        radius: Design.s(Design.radius.ctl)
                        color: Design.sunken
                        border.color: Design.line
                        border.width: Design.border
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
                            text: "\u{f02e9}"
                            role: "body"
                            color: Design.textFaint
                        }
                        Clickable {
                            anchors.fill: parent
                            enabled: window.lastShot !== ""
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: Qt.openUrlExternally("file://" + window.lastShot)
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // Shutter.
                    Rectangle {
                        visible: window.captureMode === "photo"
                        Layout.preferredWidth: Design.s(Design.size.tile)
                        Layout.preferredHeight: Design.s(Design.size.tile)
                        radius: width / 2
                        color: shutterMa.containsMouse ? Design.hover : Design.raised
                        border.color: Design.text
                        border.width: Design.focusWidth
                        scale: shutterMa.pressed ? 0.94 : 1.0
                        opacity: window.hasCamera ? 1.0 : Design.opacity.disabled
                        Behavior on scale { NumberAnimation { duration: Design.duration.fast } }

                        Rectangle {
                            anchors.centerIn: parent
                            width: parent.width - Design.s(Design.space.md)
                            height: width
                            radius: width / 2
                            color: Design.text
                        }
                        Clickable {
                            id: shutterMa
                            anchors.fill: parent
                            enabled: window.hasCamera
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: window.shoot()
                        }
                    }

                    // Record: the shutter in video mode, as large.
                    Rectangle {
                        visible: window.captureMode === "video"
                        Layout.preferredWidth: Design.s(Design.size.tile)
                        Layout.preferredHeight: Design.s(Design.size.tile)
                        radius: width / 2
                        color: window.recording ? Design.danger : (recMa.containsMouse ? Design.hover : Design.raised)
                        opacity: window.hasCamera ? 1.0 : Design.opacity.disabled
                        border.color: window.recording ? Design.danger : Design.line
                        border.width: Design.border

                        Rectangle {
                            anchors.centerIn: parent
                            width: window.recording ? Design.s(Design.size.micro) : Design.s(Design.space.lg)
                            height: width
                            radius: window.recording ? Design.s(Design.radius.sm) : width / 2
                            color: window.recording ? Design.accentText : Design.danger
                            Behavior on width { NumberAnimation { duration: Design.duration.fast } }
                            Behavior on radius { NumberAnimation { duration: Design.duration.fast } }
                        }
                        Clickable {
                            id: recMa
                            anchors.fill: parent
                            enabled: window.hasCamera
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: window.toggleRecording()
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // As wide as the thumbnail, so the shutter sits in the middle.
                    Item { Layout.preferredWidth: Design.s(Design.size.rowTall); Layout.preferredHeight: 1 }
                }
            }

            // ── Status bar ───────────────────────────────────────────────────
            AppStatusBar {
                Layout.fillWidth: true

                Label {
                    Layout.fillWidth: true
                    text: window.status !== "" ? window.status : window.shotsDir
                    role: "caption"
                    color: window.status !== "" ? Design.accent : Design.textDim
                    elide: Text.ElideMiddle
                }

                Label { text: I18n.tr("Space shutter · R record · G grid · M mirror"); role: "caption"; color: Design.textFaint }
            }
        }
    }
}
