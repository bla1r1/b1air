import QtQuick
import QtQuick.Window
import QtQuick.Controls as QQC
import QtQuick.Layouts
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import "../Ui"
import "../Services"
import B1air.Daemon

PopupShell {
    id: root


    // Durations that are choreography, not styling: a staged entrance, ambient
    // loops and slow tint crossfades. Deliberately off the motion scale.
    // PauseAnimation delays are left as they are — that spread is the stagger.
    readonly property int introDuration: 800
    readonly property int tintDuration: 1000
    readonly property int pulsePeriod: 1500
    readonly property int driftPeriod: 90000



    // The window used to paint itself in lavender and mauve, which are roles
    // no other surface in the shell uses as its primary. Opened next to the
    // Control Center or the Clipboard it read as a different application that
    // happened to be running inside this one. These names stay — the file is
    // full of them — but the two that carried the identity now resolve to the
    // accent everything else follows.
    readonly property color lavender: Design.accent
    readonly property color mauve: Design.accent
    readonly property color pink: Design.pink
    readonly property color red: Design.red
    readonly property color yellow: Design.yellow

    // Data State Properties
    property var musicData: {
        "title": "Loading...", "artist": "", "status": "Stopped", "percent": 0,
        "lengthStr": "00:00", "positionStr": "00:00", "timeStr": "--:-- / --:--",
        "source": "Offline", "playerName": "", "blur": "", "grad": "",
        "deviceIcon": "󰓃", "deviceName": "Speaker",
        "artUrl": ""
    }

    property var eqData: {
        "b1": 0, "b2": 0, "b3": 0, "b4": 0, "b5": 0,
        "b6": 0, "b7": 0, "b8": 0, "b9": 0, "b10": 0,
        "preset": "Flat", "pending": false
    }

    // MultiEffect needs a shader. Under the software rasterizer — a VM,
    // llvmpipe, or this session's own "turn effects off on a software
    // rasterizer" tuning — an item carrying layer.enabled plus a shader effect
    // renders as nothing at all: not a missing glow, a missing item. That is
    // how the ten equaliser tracks and the seek bar vanished outright, leaving
    // bare handles floating in an empty box. Every layer below that decorates
    // something the user needs to see is gated on this.
    readonly property bool canShade: GraphicsInfo.api !== GraphicsInfo.Software

    // ── Wiring to Services/Media ─────────────────────────────────────────────
    //
    // musicData and eqData above are the shapes this window draws, and nothing
    // ever wrote to them. Services/Media was built for exactly this window —
    // its own header says "MusicPopup reads Media.track.*" — but the window
    // was never moved onto it, so it drew its own defaults forever: the title
    // stayed "Loading...", the clock stayed 00:00, the source stayed
    // "Offline", and every EQ band sat at 0 no matter what the daemon held.
    // The transport buttons were already calling Media.playPause() and friends,
    // so the window could drive a player it could not show.
    //
    // Kept as writes rather than bindings because the seek bar and the play
    // button still echo their change locally for the moment before MPRIS
    // reports it back.

    function _syncFromService() {
        const t = Media.track || {};
        const merged = Object.assign({}, root.musicData, t);

        merged.status = Media.status || "Stopped";
        merged.title = t.title && String(t.title).trim() !== ""
            ? t.title
            : (Media.hasPlayer ? "Nothing playing" : "No media player");
        merged.source = t.source || (Media.hasPlayer ? (t.playerName || "") : "Offline");
        merged.positionStr = t.positionStr || "00:00";
        merged.lengthStr = t.lengthStr || "00:00";
        merged.percent = t.percent !== undefined ? t.percent : 0;

        root.musicData = merged;
    }

    function _syncEqFromService() {
        const e = Media.eq || {};
        if (Object.keys(e).length === 0)
            return;
        root.eqData = Object.assign({}, root.eqData, e);
    }

    Connections {
        target: Media
        function onTrackChanged()  { root._syncFromService(); }
        function onStatusChanged() { root._syncFromService(); }
        function onEqChanged()     { root._syncEqFromService(); }
    }

    Component.onCompleted: {
        Media.acquire();
        root._syncFromService();
        root._syncEqFromService();
        Media.refresh();
    }

    Component.onDestruction: Media.release()

    // Accumulators for Process standard output
    property string accumulatedMusicOut: ""
    property string accumulatedEqOut: ""

    // UI State for debouncing the slider and play button
    property bool userIsSeeking: false
    property bool userToggledPlay: false
    
    // ANTI-JITTER LOCK: Prevents background polling from reverting UI during processing
    property real lastEqUpdate: 0

    // Decoupled Global Animation States
    property real catppuccinFlowOffset: 0
    NumberAnimation on catppuccinFlowOffset {
        from: 0; to: 1.0
        duration: root.introDuration // Slowed down significantly for a graceful, constant flow
        loops: Animation.Infinite
        running: root.visible
    }

    property real globalOrbitAngle: 0
    NumberAnimation on globalOrbitAngle {
        from: 0; to: Math.PI * 2
        duration: root.driftPeriod
        loops: Animation.Infinite
        running: false
    }

    // --- CANVAS LIGHTNING ANIMATION STATE ---
    property real eqLightningProgress: 0.0
    property real eqLightningFade: 1.0 // 1.0 = fully faded out

    SequentialAnimation {
        id: eqLightningAnim
        running: false
        ScriptAction { script: { root.eqLightningFade = 0.0; root.eqLightningProgress = 0.0; } }
        NumberAnimation { 
            target: root; property: "eqLightningProgress"; 
            from: 0.0; to: 10.0; // 10 points = 9 segments
            duration: root.introDuration; // Fast, snappy, energetic strike
            easing.type: Easing.OutSine 
        }
        PauseAnimation { duration: Design.duration.fast } // Hold the core flash at the end
        NumberAnimation { 
            target: root; property: "eqLightningFade"; 
            from: 0.0; to: 1.0; 
            duration: root.introDuration; // Smooth dissipation
            easing.type: Easing.OutQuad 
        }
        ScriptAction { script: { root.eqLightningProgress = 0.0; } }
    }

    function triggerEqLightning() {
        eqLightningAnim.restart();
    }

    // --- GLOBAL PLAY/PAUSE EVENT LISTENER ---
    property string lastMusicStatus: "Stopped"
    onMusicDataChanged: {
        if (musicData && musicData.status && musicData.status !== lastMusicStatus) {
            if (musicData.status === "Playing") {
                playPulse.trigger();
            }
            lastMusicStatus = musicData.status;
        }
    }

    // --- ENHANCED STARTUP ANIMATION STATES ---
    property real introMain: 0
    property real introCover: 0
    property real introText: 0
    property real introControls: 0
    property real introSeparator: 0
    property real introEqHeader: 0
    property real introEqSliders: 0
    property real introPresets: 0

    ParallelAnimation {
        running: true

        // 1. Base window fades, scales, and lifts smoothly (sped up by ~40ms)
        NumberAnimation { target: root; property: "introMain"; from: 0; to: 1.0; duration: root.introDuration; easing.type: Easing.OutQuart }

        // 2. Cover art snaps in with a premium elastic feel
        SequentialAnimation {
            PauseAnimation { duration: 70 }
            NumberAnimation { target: root; property: "introCover"; from: 0; to: 1.0; duration: root.introDuration; easing.type: Easing.OutBack; easing.overshoot: 1.0 }
        }

        // 3. Text block glides in smoothly
        SequentialAnimation {
            PauseAnimation { duration: Design.duration.fast }
            NumberAnimation { target: root; property: "introText"; from: 0; to: 1.0; duration: root.introDuration; easing.type: Easing.OutQuart }
        }

        // 4. Progress bar and Media Controls bounce in
        SequentialAnimation {
            PauseAnimation { duration: 230 }
            NumberAnimation { target: root; property: "introControls"; from: 0; to: 1.0; duration: root.introDuration; easing.type: Easing.OutBack; easing.overshoot: 0.8 }
        }

        // 5. Separator line drops and fades
        SequentialAnimation {
            PauseAnimation { duration: 310 }
            NumberAnimation { target: root; property: "introSeparator"; from: 0; to: 1.0; duration: root.introDuration; easing.type: Easing.OutQuart }
        }

        // 6. EQ header follows down seamlessly
        SequentialAnimation {
            PauseAnimation { duration: 370 }
            NumberAnimation { target: root; property: "introEqHeader"; from: 0; to: 1.0; duration: root.introDuration; easing.type: Easing.OutQuart }
        }

        // 7. EQ Sliders sweep up in a sequential waterfall wave
        SequentialAnimation {
            PauseAnimation { duration: 430 }
            NumberAnimation { target: root; property: "introEqSliders"; from: 0; to: 1.0; duration: root.introDuration; easing.type: Easing.OutExpo }
        }

        // 8. Presets finish the orchestration with a final pop
        SequentialAnimation {
            PauseAnimation { duration: 550 }
            NumberAnimation { target: root; property: "introPresets"; from: 0; to: 1.0; duration: root.introDuration; easing.type: Easing.OutBack; easing.overshoot: 0.8 }
        }
    }

    // --- FIXED COLOR PARSING LOGIC ---
    property var borderColors: {
        var defaultColors = [Design.accentAlt, Design.accent, Design.danger, Design.accentAlt];
        if (!root.musicData || !root.musicData.grad) return defaultColors;
        
        var hexRegex = /#[0-9a-fA-F]{6}/g;
        var matches = root.musicData.grad.match(hexRegex);
        
        if (matches && matches.length >= 3) {
            return [matches[0], matches[1], matches[2], matches[0]]; // Wrap around for looping
        }
        return defaultColors;
    }

    // PROPER EXCEPTION-FREE FIX: Explicit bindings so GradientStop actually repaints
    property color bc1: borderColors[0] || Design.accentAlt
    property color bc2: borderColors[1] || Design.accent
    property color bc3: borderColors[2] || Design.danger
    property color bc4: borderColors[3] || Design.accentAlt

    property color dynamicTextColor: {
        if (root.musicData && root.musicData.textColor) {
            var c = String(root.musicData.textColor).trim();
            // Securely extract exactly #RRGGBB, ignoring any alpha leak from the shell
            var match = c.match(/^(#[0-9a-fA-F]{6})/);
            if (match) return match[1];
        }
        return Design.text;
    }


    function applyPresetOptimistically(presetName) {
        var presets = {
            "Flat": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
            "Bass": [5, 7, 5, 2, 1, 0, 0, 0, 1, 2],
            "Treble": [-2, -1, 0, 1, 2, 3, 4, 5, 6, 6],
            "Vocal": [-2, -1, 1, 3, 5, 5, 4, 2, 1, 0],
            "Pop": [2, 4, 2, 0, 1, 2, 4, 2, 1, 2],
            "Rock": [5, 4, 2, -1, -2, -1, 2, 4, 5, 6],
            "Jazz": [3, 3, 1, 1, 1, 1, 2, 1, 2, 3],
            "Classic": [0, 1, 2, 2, 2, 2, 1, 2, 3, 4]
        };
        if (presets[presetName]) {
            var temp = Object.assign({}, root.eqData);
            for (var i = 0; i < 10; i++) {
                temp["b" + (i + 1)] = presets[presetName][i];
            }
            temp.preset = presetName;
            temp.pending = false; 
            root.eqData = temp; 
            
            // Blind the polling process to stop it from fetching old data
            root.lastEqUpdate = Date.now(); 
            
            root.triggerEqLightning();
            Media.setEqPreset(presetName, presets[presetName]);
        }
    }

    // --- DATA POLLING ---
    Timer {
        id: seekDebounceTimer
        interval: 2500 
        onTriggered: root.userIsSeeking = false
    }

    Timer {
        id: playDebounceTimer
        interval: 1500
        onTriggered: root.userToggledPlay = false
    }

    // --- UI LAYOUT ---
    Item {
        id: mainWrapper
        anchors.fill: parent
        
        // Deepened scale effect and introduced a gentle Y-axis translation for the main container
        scale: 0.92 + (0.08 * root.introMain)
        opacity: root.introMain
        transform: Translate { y: Design.s(15) * (1 - root.introMain) }

        // OUTER ANIMATED BORDER WITH PROPER CLIPPING
        Item {
            anchors.fill: parent

            Shape {
                id: maskRectOuter
                anchors.fill: parent
                visible: false // Hidden because MultiEffect will render it as a mask
                layer.enabled: root.canShade
                preferredRendererType: Shape.GeometryRenderer // Fixes lag by hardware accelerating the stroke

                property real sw: Design.s(6)
                property real inset: (sw / 2) + Design.s(0.5) 
                property real w: width
                property real h: height
                property real r: Design.s(14) - inset
                
                // Mathematical perimeter
                property real straightLines: 2 * (w - 2 * inset - 2 * r) + 2 * (h - 2 * inset - 2 * r)
                property real arcLines: 2 * Math.PI * r
                property real perimeter: straightLines + arcLines

                property real drawProgress: 0

                NumberAnimation on drawProgress {
                    id: chargeAnim
                    from: 0
                    to: maskRectOuter.perimeter
                    duration: root.introDuration // The time it takes to "charge" the whole wick
                    easing.type: Easing.OutCubic
                    running: true // Ensure it starts reliably
                }

                ShapePath {
                    strokeWidth: maskRectOuter.sw
                    strokeColor: "black" 
                    fillColor: "transparent"
                    capStyle: ShapePath.FlatCap 

                    // QML Shape dash patterns are measured in units of strokeWidth! 
                    dashPattern: [maskRectOuter.perimeter / maskRectOuter.sw, maskRectOuter.perimeter / maskRectOuter.sw]
                    dashOffset: (maskRectOuter.perimeter - maskRectOuter.drawProgress) / maskRectOuter.sw

                    // Start exactly at Bottom-Left corner, going UP clockwise
                    startX: maskRectOuter.inset
                    startY: maskRectOuter.h - maskRectOuter.inset - maskRectOuter.r

                    // 1. Up to top-left corner
                    PathLine { x: maskRectOuter.inset; y: maskRectOuter.inset + maskRectOuter.r }
                    // 2. Arc top-left
                    PathArc { 
                        x: maskRectOuter.inset + maskRectOuter.r; y: maskRectOuter.inset 
                        radiusX: maskRectOuter.r; radiusY: maskRectOuter.r; direction: PathArc.Clockwise 
                    }
                    // 3. Right to top-right corner
                    PathLine { x: maskRectOuter.w - maskRectOuter.inset - maskRectOuter.r; y: maskRectOuter.inset }
                    // 4. Arc top-right
                    PathArc { 
                        x: maskRectOuter.w - maskRectOuter.inset; y: maskRectOuter.inset + maskRectOuter.r 
                        radiusX: maskRectOuter.r; radiusY: maskRectOuter.r; direction: PathArc.Clockwise 
                    }
                    // 5. Down to bottom-right corner
                    PathLine { x: maskRectOuter.w - maskRectOuter.inset; y: maskRectOuter.h - maskRectOuter.inset - maskRectOuter.r }
                    // 6. Arc bottom-right
                    PathArc { 
                        x: maskRectOuter.w - maskRectOuter.inset - maskRectOuter.r; y: maskRectOuter.h - maskRectOuter.inset 
                        radiusX: maskRectOuter.r; radiusY: maskRectOuter.r; direction: PathArc.Clockwise 
                    }
                    // 7. Left to bottom-left corner
                    PathLine { x: maskRectOuter.inset + maskRectOuter.r; y: maskRectOuter.h - maskRectOuter.inset }
                    // 8. Arc bottom-left to finish
                    PathArc { 
                        x: maskRectOuter.inset; y: maskRectOuter.h - maskRectOuter.inset - maskRectOuter.r 
                        radiusX: maskRectOuter.r; radiusY: maskRectOuter.r; direction: PathArc.Clockwise 
                    }
                }
            }

            Item {
                id: gradContainer
                anchors.fill: parent
                visible: false // Hidden for MultiEffect mapping
                clip: true // Prevents the rotated gradient bounding box from bulging out the sides!

                Rectangle {
                    width: Math.max(parent.width, parent.height) * 2
                    height: width
                    anchors.centerIn: parent
                    
                    NumberAnimation on rotation {
                        from: 0; to: 360; duration: root.introDuration
                        loops: Animation.Infinite
                        running: true
                    }

                    gradient: Gradient {
                        // FIXED: Using securely unpacked color bindings
                        GradientStop { position: 0.0; color: root.bc1; Behavior on color { ColorAnimation { duration: root.tintDuration; easing.type: Easing.InOutQuad } } }
                        GradientStop { position: 0.33; color: root.bc2; Behavior on color { ColorAnimation { duration: root.tintDuration; easing.type: Easing.InOutQuad } } }
                        GradientStop { position: 0.66; color: root.bc3; Behavior on color { ColorAnimation { duration: root.tintDuration; easing.type: Easing.InOutQuad } } }
                        GradientStop { position: 1.0; color: root.bc4; Behavior on color { ColorAnimation { duration: root.tintDuration; easing.type: Easing.InOutQuad } } }
                    }
                }
            }

            MultiEffect {
                source: gradContainer
                anchors.fill: parent
                maskEnabled: true
                maskSource: maskRectOuter
            }
        }

        // INNER WINDOW BOX
        Rectangle {
            id: innerBg
            anchors.fill: parent
            anchors.margins: Design.s(3)
            color: Design.surface
            radius: Design.s(10)

            // FIX: This forces the entire background to render as a single hardware texture,
            // preventing the UI from dragging and causing "shadow boxes" during the StackView transition!
            layer.enabled: root.canShade

            // Provide a perfectly rounded mask for the inner content
            Rectangle {
                id: innerBgMask
                anchors.fill: parent
                radius: Design.s(10)
                visible: false
                
                // FIX: Masks in MultiEffect strictly require layer.enabled to correctly capture the radius during scaling!
                layer.enabled: root.canShade 
            }

            Item {
                id: bgEffectsLayer
                anchors.fill: parent
                
                // This correctly clamps the blur and orbit circles to the 10px radius corners
                layer.enabled: root.canShade
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: innerBgMask
                }

                // LAYER 1: Background Blur (Smooth fade-in)
                Image {
                    anchors.fill: parent
                    // Decoded at the size drawn, not the file's (a 4K picture is 33 MB of pixels).
                    sourceSize: Qt.size(512, 512)
                    source: root.musicData.blur ? "file://" + root.musicData.blur : ""
                    fillMode: Image.PreserveAspectCrop
                    
                    // Fixed: Ensures blur is completely hidden when stopped so the pure base color matches the calendar
                    opacity: (status === Image.Ready && root.musicData.status !== "Stopped" && root.musicData.status !== "Offline") ? 0.9 : 0.0
                    Behavior on opacity { NumberAnimation { duration: root.introDuration; easing.type: Easing.InOutQuad } }
                }

                // LAYER 1.5: Ambient Accents
                Rectangle {
                    width: parent.width * 0.8; height: width; radius: width / 2
                    anchors.centerIn: parent
                    
                    opacity: root.musicData.status === "Playing" ? 0.08 : (root.musicData.status === "Paused" ? 0.04 : 0.0)
                    color: root.musicData.status === "Playing" ? Design.accent : Design.active
                    Behavior on color { ColorAnimation { duration: root.tintDuration } }
                    Behavior on opacity { NumberAnimation { duration: root.introDuration } }
                }
                
                Rectangle {
                    width: parent.width * 0.9; height: width; radius: width / 2
                    anchors.centerIn: parent
                    
                    opacity: root.musicData.status === "Playing" ? 0.08 : (root.musicData.status === "Paused" ? 0.02 : 0.0)
                    color: root.musicData.status === "Playing" ? Design.accent : Design.hover
                    Behavior on color { ColorAnimation { duration: root.tintDuration } }
                    Behavior on opacity { NumberAnimation { duration: root.introDuration } }
                }
            }

            // LAYER 2: UI Content
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Design.s(20)
                spacing: 0

                // ==========================================
                // TOP INFO SECTION
                // ==========================================
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Design.s(220)
                    spacing: Design.s(25)

                    // Cover Art Wrapper
                    Item {
                        Layout.preferredWidth: Design.s(220)
                        Layout.preferredHeight: Design.s(220)
                        Layout.alignment: Qt.AlignVCenter

                        opacity: root.introCover
                        // Enhanced 2D drift animation
                        transform: Translate { x: Design.s(-40) * (1 - root.introCover); y: Design.s(10) * (1 - root.introCover) }

                        // Elastic response to play/pause state
                        scale: root.musicData.status === "Playing" ? 1.0 : 0.90
                        Behavior on scale { NumberAnimation { duration: root.introDuration; easing.type: Easing.OutElastic; easing.overshoot: 1.2 } }

                        Rectangle {
                            anchors.fill: parent
                            radius: Design.s(110)
                            color: Design.hover
                            border.width: Design.s(4)
                            border.color: root.musicData.status === "Playing" ? Design.accent : Design.textFaint
                            Behavior on border.color { ColorAnimation { duration: Design.duration.slow } }

                            // Glow Effect surrounding the thumbnail
                            Rectangle {
                                z: -1
                                anchors.centerIn: parent
                                width: parent.width + Design.s(20)
                                height: parent.height + Design.s(20)
                                radius: width / 2
                                color: Design.accent
                                opacity: root.musicData.status === "Playing" ? 0.5 : 0.0
                                Behavior on opacity { NumberAnimation { duration: Design.duration.slow } }
                                layer.enabled: root.canShade
                                layer.effect: MultiEffect {
                                    blurEnabled: true
                                    blurMax: 32
                                    blur: 1.0
                                }
                            }

                            Item {
                                anchors.fill: parent
                                anchors.margins: Design.s(4)
                                Image {
                                    id: artImg
                                    anchors.fill: parent
                                    // Decoded at the size drawn, not the file's (a 4K picture is 33 MB of pixels).
                                    sourceSize: Qt.size(512, 512)
                                    source: root.musicData.artUrl ? "file://" + root.musicData.artUrl : ""
                                    fillMode: Image.PreserveAspectCrop
                                    visible: false 
                                }
                                Rectangle {
                                    id: maskRect
                                    anchors.fill: parent
                                    radius: width / 2
                                    visible: false
                                    layer.enabled: root.canShade 
                                }
                                MultiEffect {
                                    anchors.fill: parent
                                    source: artImg
                                    maskEnabled: true
                                    maskSource: maskRect
                                    opacity: artImg.status === Image.Ready ? 1.0 : 0.0
                                    Behavior on opacity { NumberAnimation { duration: root.introDuration } }
                                }
                                
                                // NEW: Dimmed slightly by tinting with the primary mauve accent, as requested
                                Rectangle {
                                    anchors.fill: parent
                                    radius: width / 2
                                    color: Qt.rgba(Design.accent.r, Design.accent.g, Design.accent.b, 0.2)
                                    opacity: artImg.status === Image.Ready ? 1.0 : 0.0
                                    Behavior on opacity { NumberAnimation { duration: root.introDuration } }
                                }

                                Rectangle {
                                    width: Design.s(40); height: Design.s(40)
                                    radius: Design.s(20); color: "#000000"
                                    opacity: 0.8; anchors.centerIn: parent
                                }
                            }
                            
                            NumberAnimation on rotation {
                                from: 0; to: 360; duration: root.introDuration
                                loops: Animation.Infinite
                                running: true
                                paused: root.musicData.status !== "Playing"
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: Design.s(15)

                        // TEXT INFO CHUNK
                        ColumnLayout {
                            spacing: Design.s(6)
                            opacity: root.introText
                            transform: Translate { x: Design.s(30) * (1 - root.introText) }
                            
                            // HARD-LOCKED SEAMLESS INFINITE MARQUEE
                            Item {
                                id: titleClipRect
                                Layout.fillWidth: true
                                Layout.preferredHeight: Design.s(28) 
                                clip: true

                                // This is the distance between the end of the text and the clone
                                property int marqueeSpacing: Design.s(60)

                                Item {
                                    id: marqueeContainer
                                    height: parent.height

                                    Row {
                                        spacing: titleClipRect.marqueeSpacing
                                        Text {
                                            id: titleTextMain
                                            text: root.musicData.title
                                            color: root.dynamicTextColor
                                            font.family: Design.font.sans
                                            font.pixelSize: Design.s(20)
                                            font.bold: true
                                            Behavior on color { ColorAnimation { duration: root.tintDuration } }

                                            // Only animate if the text is physically wider than our container
                                            onTextChanged: {
                                                marqueeContainer.x = 0;
                                                if (implicitWidth > titleClipRect.width) {
                                                    titleAnim.restart();
                                                } else {
                                                    titleAnim.stop();
                                                }
                                            }
                                        }
                                        // The clone that creates the seamless endless loop
                                        Text {
                                            id: titleTextClone
                                            text: root.musicData.title
                                            color: root.dynamicTextColor
                                            font.family: Design.font.sans
                                            font.pixelSize: Design.s(20)
                                            font.bold: true
                                            visible: titleTextMain.implicitWidth > titleClipRect.width
                                        }
                                    }

                                    SequentialAnimation on x {
                                        id: titleAnim
                                        loops: Animation.Infinite
                                        running: titleTextMain.implicitWidth > titleClipRect.width

                                        // 1. Stop for a few seconds in the initial position
                                        PauseAnimation { duration: root.introDuration }
                                        
                                        // 2. Smoothly run left until the clone is exactly where the original started
                                        NumberAnimation {
                                            from: 0
                                            to: -(titleTextMain.implicitWidth + titleClipRect.marqueeSpacing)
                                            // The duration calculates dynamically to maintain a constant scroll speed
                                            duration: (titleTextMain.implicitWidth + titleClipRect.marqueeSpacing) * 25
                                        }
                                        
                                        // 3. Instantly snap back to 0 without stopping (creating the seamless loop)
                                        PropertyAction { target: marqueeContainer; property: "x"; value: 0 }
                                    }
                                }
                            }

                            Text {
                                text: root.musicData.artist ? "BY " + root.musicData.artist : ""
                                color: Design.textDim // Better matugen match
                                font.family: Design.font.sans
                                font.pixelSize: Design.s(14)
                                font.bold: true
                                elide: Text.ElideRight
                                maximumLineCount: 1 // Strict 1 line
                                Layout.fillWidth: true
                                Layout.preferredHeight: Design.s(20)
                            }
                            RowLayout {
                                spacing: Design.s(10)
                                Rectangle {
                                    color: Design.raised
                                    radius: Design.s(4)
                                    Layout.preferredHeight: Design.s(24)
                                    Layout.preferredWidth: pillContent.width + Design.s(20)
                                    RowLayout {
                                        id: pillContent
                                        anchors.centerIn: parent
                                        spacing: Design.s(6)
                                        Icon { role: "body"; text: root.musicData.deviceIcon || "󰓃"; color: Design.accent }
                                        Text { text: root.musicData.deviceName || "Speaker"; color: Design.textFaint; font.family: Design.font.sans; font.pixelSize: Design.s(12); font.bold: true }
                                    }
                                }
                                Text {
                                    text: "VIA " + (root.musicData.source || "Offline")
                                    color: Design.textFaint // Better matugen match
                                    font.family: Design.font.mono
                                    font.pixelSize: Design.s(12)
                                    font.bold: true
                                    font.italic: true
                                }
                            }
                        }

                        // PROGRESS AREA CHUNK
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Design.s(5)
                            opacity: root.introControls
                            transform: Translate { x: Design.s(20) * (1 - root.introControls); y: Design.s(10) * (1 - root.introControls) }

                            QQC.Slider {
                                id: progBar
                                Layout.fillWidth: true
                                Layout.preferredHeight: Design.s(20) 
                                from: 0; to: 100

                                Connections {
                                    target: root
                                    function onMusicDataChanged() {
                                        if (!progBar.pressed && !root.userIsSeeking) {
                                            if (root.musicData && root.musicData.percent !== undefined) {
                                                var p = Number(root.musicData.percent);
                                                if (!isNaN(p)) progBar.value = p;
                                            }
                                        }
                                    }
                                }

                                Behavior on value {
                                    enabled: !progBar.pressed && !root.userIsSeeking
                                    NumberAnimation { duration: Design.duration.slow; easing.type: Easing.OutSine }
                                }

                                onPressedChanged: {
                                    if (pressed) {
                                        root.userIsSeeking = true;
                                        seekDebounceTimer.stop();
                                    } else {
                                        var temp = Object.assign({}, root.musicData);
                                        temp.percent = value;
                                        root.musicData = temp;

                                        var safePlayer = root.musicData.playerName ? root.musicData.playerName : "";
                                        Media.seek(value.toFixed(2));
                                        
                                        seekDebounceTimer.restart();
                                    }
                                }

                                background: Item {
                                    x: progBar.leftPadding
                                    y: progBar.topPadding + (progBar.availableHeight - Design.s(12)) / 2
                                    width: progBar.availableWidth
                                    height: Design.s(12)

                                    // Shadows mimicking the EQ slider background
                                    Rectangle {
                                        anchors.fill: parent
                                        radius: Design.s(6)
                                        // Dynamic tint: surface0 with 70% opacity for a softer dark look
                                        color: Qt.rgba(Design.raised.r, Design.raised.g, Design.raised.b, 0.7)

                                        layer.enabled: root.canShade
                                        layer.effect: MultiEffect {
                                            shadowEnabled: true
                                            shadowColor: "#000000"
                                            shadowOpacity: 0.9
                                            shadowBlur: 0.5
                                            shadowVerticalOffset: 1
                                        }
                                    }

                                    // Masked Gradient Fill (Completely redesigned for smooth, light, synergistic palette)
                                    Item {
                                        width: progBar.handle.x - progBar.leftPadding + (progBar.handle.width / 2)
                                        height: parent.height

                                        // The fill inside is a 2000px gradient that slides; the mask
                                        // was the only thing keeping it inside this Item. With no
                                        // shader to run the mask, that gradient painted straight
                                        // across the whole popup, over the cover art and out past
                                        // the card. clip is what actually bounds it; the mask only
                                        // rounds the corners.
                                        clip: true

                                        layer.enabled: root.canShade
                                        layer.effect: MultiEffect {
                                            maskEnabled: true
                                            maskSource: sliderFillMask
                                        }

                                        Rectangle {
                                            id: sliderFillMask
                                            width: parent.width
                                            height: parent.height
                                            radius: Design.s(6)
                                            visible: false
                                            layer.enabled: root.canShade 
                                        }

                                        Rectangle {
                                            width: Design.s(2000)
                                            height: parent.height
                                            // Sliding the gradient perfectly by exactly half its width (1000px)
                                            x: -(root.catppuccinFlowOffset * Design.s(1000)) 
                                            gradient: Gradient {
                                                orientation: Gradient.Horizontal
                                                // Mathematically precise loops with lighter, cooler colors & theme change support
                                                GradientStop { position: 0.0000; color: Qt.lighter(Design.accent, 1.2); Behavior on color { ColorAnimation { duration: root.tintDuration } } }
                                                GradientStop { position: 0.1666; color: Qt.lighter(Design.accentSoft, 1.15); Behavior on color { ColorAnimation { duration: root.tintDuration } } }
                                                GradientStop { position: 0.3333; color: Qt.lighter(Design.accentAlt, 1.15); Behavior on color { ColorAnimation { duration: root.tintDuration } } }
                                                GradientStop { position: 0.5000; color: Qt.lighter(Design.accent, 1.2); Behavior on color { ColorAnimation { duration: root.tintDuration } } }
                                                GradientStop { position: 0.6666; color: Qt.lighter(Design.accentSoft, 1.15); Behavior on color { ColorAnimation { duration: root.tintDuration } } }
                                                GradientStop { position: 0.8333; color: Qt.lighter(Design.accentAlt, 1.15); Behavior on color { ColorAnimation { duration: root.tintDuration } } }
                                                GradientStop { position: 1.0000; color: Qt.lighter(Design.accent, 1.2); Behavior on color { ColorAnimation { duration: root.tintDuration } } }
                                            }
                                        }
                                    }
                                }

                                handle: Rectangle {
                                    x: progBar.leftPadding + progBar.visualPosition * (progBar.availableWidth - width)
                                    y: progBar.topPadding + (progBar.availableHeight - height) / 2
                                    implicitWidth: Design.s(18) 
                                    implicitHeight: Design.s(18)
                                    width: Design.s(18); height: Design.s(18)
                                    // A knob on an accent track, not a cream
                                    // dot: the handles were Design.text, the
                                    // near-white used for prose, which is the
                                    // one colour in the palette that says
                                    // "this is a letter, not a control".
                                    radius: Design.s(9)
                                    color: Design.raised
                                    border.width: Math.max(1, Design.s(2))
                                    border.color: Design.accent
                                    scale: progBar.pressed ? 1.3 : 1.0
                                    Behavior on scale { NumberAnimation { duration: Design.duration.fast; easing.type: Easing.OutBack } }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Text { text: root.musicData.positionStr || "00:00"; color: Design.textFaint; font.family: Design.font.mono; font.bold: true; font.pixelSize: Design.s(13) }
                                Item { Layout.fillWidth: true }
                                Text { text: root.musicData.lengthStr || "00:00"; color: Design.textFaint; font.family: Design.font.mono; font.bold: true; font.pixelSize: Design.s(13) }
                            }
                        }

                        // MEDIA CONTROLS CHUNK
                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: Design.s(30)
                            opacity: root.introControls
                            transform: Translate { y: Design.s(20) * (1 - root.introControls) }

                            MouseArea {
                                width: Design.s(30); height: Design.s(30)
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Media.previous()
                                Icon { role: "title"; anchors.centerIn: parent; text: ""; color: parent.pressed ? Design.text : Design.textFaint }
                            }
                            MouseArea {
                                id: playPauseBtn
                                width: Design.s(50); height: Design.s(50)
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.userToggledPlay = true;
                                    playDebounceTimer.restart();
                                    var temp = Object.assign({}, root.musicData);
                                    temp.status = (temp.status === "Playing" ? "Paused" : "Playing");
                                    root.musicData = temp;
                                    Media.playPause();
                                }

                                // Fluid Ripple Animation Element
                                Rectangle {
                                    id: playPulse
                                    anchors.centerIn: parent
                                    width: parent.width
                                    height: parent.height
                                    radius: width / 2
                                    color: Design.accent
                                    opacity: 0
                                    scale: 1

                                    NumberAnimation {
                                        id: playPulseScaleAnim
                                        target: playPulse
                                        property: "scale"
                                        from: 1.0; to: 1.8
                                        duration: Design.duration.slow
                                        easing.type: Easing.OutQuart
                                    }
                                    NumberAnimation {
                                        id: playPulseFadeAnim
                                        target: playPulse
                                        property: "opacity"
                                        from: 0.5; to: 0.0
                                        duration: Design.duration.slow
                                        easing.type: Easing.OutQuart
                                    }

                                    function trigger() {
                                        playPulseScaleAnim.restart();
                                        playPulseFadeAnim.restart();
                                    }
                                }

                                Text { 
                                    anchors.centerIn: parent
                                    text: root.musicData.status === "Playing" ? "" : ""
                                    color: parent.pressed ? Design.accent : Design.accent
                                    font.family: Design.font.icon
                                    font.pixelSize: Design.s(42) 
                                    scale: parent.pressed ? 0.8 : 1.0
                                    Behavior on color { ColorAnimation { duration: Design.duration.fast } }
                                    Behavior on scale { NumberAnimation { duration: Design.duration.fast; easing.type: Easing.OutBack } }
                                }
                            }
                            MouseArea {
                                width: Design.s(30); height: Design.s(30)
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Media.next()
                                Icon { role: "title"; anchors.centerIn: parent; text: ""; color: parent.pressed ? Design.text : Design.textFaint }
                            }
                        }
                    }
                }

                // ==========================================
                // SEPARATOR
                // ==========================================
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Design.s(2)
                    Layout.topMargin: Design.s(20)
                    Layout.bottomMargin: Design.s(20)
                    color: Design.line
                    radius: Design.s(1)

                    opacity: root.introSeparator
                    transform: Translate { y: Design.s(15) * (1 - root.introSeparator) }
                }

                // ==========================================
                // EQUALIZER
                // ==========================================
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Design.s(15)

                    // Header Row
                    RowLayout {
                        Layout.fillWidth: true
                        opacity: root.introEqHeader
                        transform: Translate { y: Design.s(15) * (1 - root.introEqHeader) }

                        Text { text: "Equalizer"; color: Design.accent; font.family: Design.font.sans; font.pixelSize: Design.s(16); font.bold: true; Layout.fillWidth: true }
                        
                        // Ui/ActionButton, like every other button in the
                        // shell. This was a bespoke rectangle with its own
                        // radius, a mauve fill and a drop shadow, sitting
                        // beside a bare word for the current preset — so the
                        // row read as the two-word phrase "Saved Flat" rather
                        // than a button and a value.
                        Label {
                            text: "Preset: " + (root.eqData.preset || "Flat")
                            role: "caption"
                            dim: true
                            Layout.rightMargin: Design.s(Design.space.sm)
                        }

                        ActionButton {
                            Layout.fillWidth: false
                            enabled: root.eqData.pending
                            icon: "\u{f012c}"
                            label: root.eqData.pending ? "Apply" : "Saved"
                            onActivated: {
                                if (!root.eqData.pending)
                                    return;
                                var temp = Object.assign({}, root.eqData);
                                temp.pending = false;
                                root.eqData = temp;

                                // Blind the polling process to stop it from fetching old data
                                root.lastEqUpdate = Date.now();

                                root.triggerEqLightning();
                                Daemon.eqApply();
                            }
                        }
                    }

                    // Eq Sliders Container with Canvas Lightning Overlay
                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Design.s(180)

                        Row {
                            id: eqSliderRow
                            anchors.fill: parent
                            z: 1 // Ensures sliders (and their handles) render over the lightning

                            Repeater {
                                model: [
                                    {"idx": 1, "lbl": "31"}, {"idx": 2, "lbl": "63"}, {"idx": 3, "lbl": "125"},
                                    {"idx": 4, "lbl": "250"}, {"idx": 5, "lbl": "500"}, {"idx": 6, "lbl": "1k"},
                                    {"idx": 7, "lbl": "2k"}, {"idx": 8, "lbl": "4k"}, {"idx": 9, "lbl": "8k"},
                                    {"idx": 10, "lbl": "16k"}
                                ]
                                delegate: Item {
                                    id: sliderDelegate
                                    width: eqSliderRow.width / 10 
                                    height: eqSliderRow.height

                                    // --- ENHANCED SLIDER CASCADING ANIMATION ---
                                    opacity: root.introEqSliders
                                    transform: Translate {
                                        y: Design.s(30) * (1 - root.introEqSliders) + (index * Design.s(8) * (1 - root.introEqSliders))
                                    }

                                    // Mathematical evaluation mapping to the exact timeline of the strike
                                    property real dist: root.eqLightningProgress - (modelData.idx - 1)
                                    property real hitPulse: dist >= 0 && dist < 1.0 ? Math.sin((dist) * Math.PI) : 0.0
                                    
                                    // Massive Energy Pulses
                                    property real trackPulse: 0.0
                                    property real ringPulse: 0.0
                                    property real flashFade: 0.0
                                    property bool hasFired: false

                                    onDistChanged: {
                                        // Reset the fire lock when the animation sweeps past or starts over
                                        if (dist <= 0.05) {
                                            hasFired = false;
                                        } else if (dist > 0.4 && !hasFired) {
                                            // Trigger strictly once per bolt passing over
                                            hasFired = true;
                                            trackPulseAnim.restart();
                                            ringPulseAnim.restart();
                                            flashFadeAnim.restart();
                                        }
                                    }

                                    SequentialAnimation {
                                        id: trackPulseAnim
                                        // Animates the bolt perfectly down the track
                                        NumberAnimation { target: sliderDelegate; property: "trackPulse"; from: 0.0; to: 1.0; duration: root.introDuration; easing.type: Easing.OutQuart }
                                    }
                                    SequentialAnimation {
                                        id: ringPulseAnim
                                        // Explodes outward creating a physical shockwave
                                        NumberAnimation { target: sliderDelegate; property: "ringPulse"; from: 1.0; to: 0.0; duration: root.introDuration; easing.type: Easing.OutExpo }
                                    }
                                    SequentialAnimation {
                                        id: flashFadeAnim
                                        // Slowly cools the inner track gradient back to normal
                                        NumberAnimation { target: sliderDelegate; property: "flashFade"; from: 1.0; to: 0.0; duration: root.introDuration; easing.type: Easing.OutSine }
                                    }

                                    ColumnLayout {
                                        anchors.fill: parent
                                        spacing: Design.s(5)
                                        QQC.Slider {
                                            id: eqSlider
                                            Layout.fillHeight: true
                                            Layout.alignment: Qt.AlignHCenter
                                            orientation: Qt.Vertical
                                            from: -12; to: 12
                                            stepSize: 1

                                            Connections {
                                                target: root
                                                function onEqDataChanged() {
                                                    if (!eqSlider.pressed) {
                                                        if (root.eqData && root.eqData["b" + modelData.idx] !== undefined) {
                                                            var p = Number(root.eqData["b" + modelData.idx]);
                                                            if (!isNaN(p)) eqSlider.value = p;
                                                        }
                                                    }
                                                }
                                            }

                                            Behavior on value {
                                                enabled: !eqSlider.pressed
                                                NumberAnimation {
                                                    duration: Design.duration.base
                                                    easing.type: Easing.OutQuart
                                                }
                                            }

                                            onPressedChanged: {
                                                if (!pressed) {
                                                    var temp = Object.assign({}, root.eqData);
                                                    temp["b" + modelData.idx] = Math.round(value);
                                                    temp.preset = "Custom";
                                                    temp.pending = true;
                                                    root.eqData = temp;
                                                    
                                                    // Set lock here too to protect individual slider tweaks
                                                    root.lastEqUpdate = Date.now();
                                                    
                                                    Daemon.eqSetBand(modelData.idx, Math.round(value));
                                                }
                                            }

                                            background: Rectangle {
                                                id: trackBg
                                                x: eqSlider.leftPadding + (eqSlider.availableWidth - width) / 2
                                                y: eqSlider.topPadding
                                                implicitWidth: Design.s(10) 
                                                implicitHeight: Design.s(150)
                                                width: Design.s(10); height: eqSlider.availableHeight
                                                radius: Design.s(4); 
                                                
                                                // Dynamic tint: surface0 with 70% opacity for a softer dark look
                                                color: Qt.rgba(Design.raised.r, Design.raised.g, Design.raised.b, 0.7)

                                                layer.enabled: root.canShade
                                                layer.effect: MultiEffect {
                                                    id: trackEffect
                                                    shadowEnabled: true
                                                    shadowColor: "#000000"
                                                    shadowOpacity: 0.9
                                                    shadowBlur: 0.5
                                                    shadowVerticalOffset: 1
                                                }

                                                // MASSIVE Outer Energy Shockwave Ring 
                                                Rectangle {
                                                    z: -1
                                                    anchors.centerIn: parent
                                                    // Geometry is fixed at the pulse peak and the pulse drives
                                                    // scale instead: resizing a blurred layer re-renders and
                                                    // re-blurs its FBO every frame, scaling one does not.
                                                    width: parent.width + Design.s(60)
                                                    height: parent.height + Design.s(80)
                                                    radius: parent.radius + Design.s(30)
                                                    color: "transparent"
                                                    border.color: Design.accent
                                                    border.width: Design.s(6)
                                                    opacity: sliderDelegate.ringPulse * 0.8 * (1.0 - root.eqLightningFade)
                                                    scale: 0.7 + sliderDelegate.ringPulse * 0.3

                                                    layer.enabled: root.canShade
                                                    layer.effect: MultiEffect { blurEnabled: true; blurMax: 32; blur: 1.0 }
                                                }

                                                // The Track Fill Base (FIXED THE SQUARE CORNERS ISSUE)
                                                Item {
                                                    width: parent.width
                                                    height: (1 - eqSlider.visualPosition) * parent.height
                                                    y: eqSlider.visualPosition * parent.height

                                                    // Same reason as the seek bar: the surge bolt
                                                    // inside is taller than this Item and rides
                                                    // past both ends of it.
                                                    clip: true

                                                    layer.enabled: root.canShade
                                                    layer.effect: MultiEffect {
                                                        maskEnabled: true
                                                        maskSource: eqFillMask
                                                    }

                                                    Rectangle {
                                                        id: eqFillMask
                                                        anchors.fill: parent
                                                        radius: Design.s(4)
                                                        visible: false
                                                        layer.enabled: root.canShade 
                                                    }

                                                    Rectangle {
                                                        anchors.fill: parent
                                                        color: Design.accent

                                                        // Track Override: Changes entire gradient of track
                                                        Rectangle {
                                                            anchors.fill: parent
                                                            opacity: sliderDelegate.flashFade
                                                            gradient: Gradient {
                                                                orientation: Gradient.Vertical
                                                                GradientStop { position: 0.0; color: Design.accentAlt }
                                                                GradientStop { position: 0.5; color: Design.accent }
                                                                GradientStop { position: 1.0; color: "transparent" }
                                                            }
                                                        }

                                                        // The Internal Charging Surge Bolt 
                                                        Rectangle {
                                                            width: parent.width
                                                            height: Design.s(80) // Massive physical bolt
                                                            y: (sliderDelegate.trackPulse * (parent.height + height)) - height
                                                            opacity: Math.sin(sliderDelegate.trackPulse * Math.PI) * 2.0 * (1.0 - root.eqLightningFade)
                                                            
                                                            gradient: Gradient {
                                                                orientation: Gradient.Vertical
                                                                GradientStop { position: 0.0; color: "transparent" }
                                                                GradientStop { position: 0.2; color: Design.accent }
                                                                GradientStop { position: 0.5; color: Design.text } // Theme integrated bright center
                                                                GradientStop { position: 0.8; color: Design.accentAlt }
                                                                GradientStop { position: 1.0; color: "transparent" }
                                                            }
                                                            
                                                            layer.enabled: root.canShade
                                                            layer.effect: MultiEffect {
                                                                shadowEnabled: true; shadowColor: Design.accent; shadowBlur: 1.0; shadowOpacity: 1.0
                                                            }
                                                        }
                                                    }
                                                }
                                            }

                                            handle: Rectangle {
                                                x: eqSlider.leftPadding + (eqSlider.availableWidth - width) / 2
                                                y: eqSlider.topPadding + eqSlider.visualPosition * (eqSlider.availableHeight - height)
                                                implicitWidth: Design.s(18)
                                                implicitHeight: Design.s(18)
                                                width: Design.s(18); height: Design.s(18)
                                                radius: Design.s(9)
                                                color: Design.raised
                                                border.width: Math.max(1, Design.s(2))
                                                border.color: Design.accent

                                                property var catColors: [Design.accent, Design.accent, root.lavender, Design.accent, Design.accent]

                                                // Core glow flare that cleanly fades out matching the canvas
                                                Rectangle {
                                                    anchors.centerIn: parent
                                                    // Fixed size + scale: see the shockwave ring above.
                                                    width: parent.width + Design.s(36)
                                                    height: width
                                                    radius: width / 2
                                                    color: parent.catColors[index % parent.catColors.length]
                                                    opacity: sliderDelegate.hitPulse * (1.0 - root.eqLightningFade)
                                                    scale: 0.5 + sliderDelegate.hitPulse * 0.5
                                                    layer.enabled: root.canShade
                                                    layer.effect: MultiEffect { blurEnabled: true; blurMax: 32; blur: 1.0 }
                                                }

                                                // Pop the handle itself slightly as the beam passes
                                                scale: 1.0 + (sliderDelegate.hitPulse * 0.4 * (1.0 - root.eqLightningFade))
                                            }
                                        }
                                        Text {
                                            text: modelData.lbl
                                            color: Design.textFaint
                                            font.family: Design.font.mono
                                            font.pixelSize: Design.s(10)
                                            font.bold: true
                                            Layout.alignment: Qt.AlignHCenter
                                        }
                                    }
                                }
                            }
                        }

                        // --- THE FLUID CANVAS LIGHTNING (Optimized for Realism and multiple waves) ---
                        Canvas {
                            id: lightningCanvas
                            anchors.fill: parent
                            opacity: 1.0 - root.eqLightningFade
                            z: 0 // Draw securely behind the sliders

                            // Force hardware FBO backend instead of slow software rendering
                            renderTarget: Canvas.FramebufferObject 

                            // GPU Layer effect to provide bloom WITHOUT locking up the CPU via ctx.shadowBlur
                            layer.enabled: root.canShade
                            layer.effect: MultiEffect {
                                shadowEnabled: true
                                shadowColor: Design.accent
                                shadowBlur: 1.0 // 1.0 is max blur in MultiEffect
                                shadowOpacity: 0.6
                                shadowVerticalOffset: 0
                                shadowHorizontalOffset: 0
                            }

                            Timer {
                                interval: 16 // ~60fps for silky smooth arcs
                                running: root.eqLightningFade < 1.0 && root.eqLightningProgress > 0.0
                                repeat: true
                                onTriggered: lightningCanvas.requestPaint()
                            }

                            onPaint: {
                                var ctx = getContext("2d");
                                ctx.clearRect(0, 0, width, height);

                                if (root.eqLightningProgress <= 0.0 || root.eqLightningFade >= 1.0) return;

                                var time = Date.now() / 1000;
                                var maxIdx = root.eqLightningProgress; // 0 to 9

                                ctx.lineJoin = "round";
                                ctx.lineCap = "round";

                                // Step 1: Map the spatial coordinates of the 10 handles
                                var pts = [];
                                for (var i = 1; i <= 10; i++) {
                                    var val = root.eqData["b" + i] !== undefined ? Number(root.eqData["b" + i]) : 0;
                                    var norm = 1.0 - ((val + 12) / 24);
                                    
                                    // Py uses margins rough mapping to the handles visible track
                                    var py = Design.s(10) + norm * (height - Design.s(35)); 
                                    var px = (i - 0.5) * (width / 10);
                                    pts.push({ x: px, y: py });
                                }

                                // Step 2: Draw the multi-wave arcing structure
                                // Strand 0: Slow erratic mauve glow/wave
                                // Strand 1: Complex pink glow
                                // Strand 2: Crackling secondary core
                                // Strand 3: Hot white center core
                                for (var s = 0; s < 4; s++) { 
                                    ctx.beginPath();
                                    ctx.moveTo(pts[0].x, pts[0].y);

                                    for (var i = 0; i < pts.length - 1; i++) {
                                        if (i > maxIdx) break; // Stop drawing ahead of current progress

                                        var p1 = pts[i];
                                        var p2 = pts[i+1];

                                        var fraction = 1.0;
                                        if (maxIdx < i + 1) {
                                            fraction = maxIdx - i;
                                        }

                                        // Subdivision steps create the crackle noise
                                        var steps = s === 3 ? 6 : 8; // Ultra smooth subdivision, s=3 core has less subdiv for straighter look
                                        for (var j = 1; j <= steps; j++) {
                                            var t = j / steps;
                                            if (t > fraction) t = fraction;

                                            var cx = p1.x + (p2.x - p1.x) * t;
                                            var cy = p1.y + (p2.y - p1.y) * t;

                                            // Wave calculations: create distinct arcs and noise branching
                                            var envelope = Math.sin(t * Math.PI);

                                            // s=3 core noise (straightest) to s=0 outer glow noise (most waves)
                                            var noiseAmpX = s === 3 ? 1.0 : (4 - s) * 4; 
                                            var noiseAmpY = s === 3 ? 1.0 : (4 - s) * 5; 
                                            
                                            // Combine multiple frequencies for complex branching/crackle appearance
                                            // Glow strands (0, 1) also get a sweeping sine wave applied to create distinct separating waves
                                            var sepWaveX = (s < 2) ? Math.sin(time * 3 + i + j + s) * Design.s(10) * envelope : 0;
                                            var sepWaveY = (s < 2) ? Math.cos(time * 2.5 + i - j - s) * Design.s(15) * envelope : 0;

                                            // Primary erratic crackle noise using high frequency combined sine/cos
                                            var noiseX = Math.sin(time * (10+s) + i + j) * Math.cos(time * 8 - i + j) * noiseAmpX * envelope * (1 - root.eqLightningFade);
                                            var noiseY = Math.cos(time * (9-s) + i - j) * Math.sin(time * 7 + i - j) * noiseAmpY * envelope * (1 - root.eqLightningFade);

                                            ctx.lineTo(cx + sepWaveX + noiseX, cy + sepWaveY + noiseY);

                                            if (t === fraction) break;
                                        }
                                    }

                                    // Step 3: Theme and render each distinct strand
                                    if (s === 0) { // Massive Sweeping Outer Glow (Mauve)
                                        ctx.lineWidth = Design.s(20);
                                        ctx.strokeStyle = Design.accent;
                                        ctx.globalAlpha = 0.2;
                                    } else if (s === 1) { // Medium Sweeping Wave (Pink)
                                        ctx.lineWidth = Design.s(8);
                                        ctx.strokeStyle = Design.accent;
                                        ctx.globalAlpha = 0.45;
                                    } else if (s === 2) { // Tight erratic core (Lavender)
                                        ctx.lineWidth = Design.s(3.5);
                                        ctx.strokeStyle = root.lavender;
                                        ctx.globalAlpha = 0.85;
                                    } else if (s === 3) { // Pure white straight hot core - heavily transparent
                                        ctx.lineWidth = Design.s(1.0);
                                        ctx.strokeStyle = Design.text;
                                        ctx.globalAlpha = 0.1;
                                    }

                                    ctx.stroke();
                                }
                            }
                        }
                    }

                    // Presets Grid
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Design.s(8)
                        
                        opacity: root.introPresets
                        transform: Translate { y: Design.s(20) * (1 - root.introPresets) }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Design.s(10)
                            Repeater {
                                model: ["Flat", "Bass", "Treble", "Vocal"]
                                delegate: PresetButton { name: modelData }
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: Design.s(10)
                            Repeater {
                                model: ["Pop", "Rock", "Jazz", "Classic"]
                                delegate: PresetButton { name: modelData }
                            }
                        }
                    }
                }
            }
        }
    }

    // --- HELPER COMPONENT FOR PRESETS ---
    //
    // Ui/Pill, which is what every other exclusive option group in the shell
    // is made of. This was a hand-built rectangle with its own radius, its own
    // mono type, its own 1.05 hover pop and Design.accent for the selected
    // state — eight buttons that matched nothing else on screen.
    component PresetButton : Pill {
        property string name: ""
        Layout.fillWidth: true
        label: name
        active: root.eqData && root.eqData.preset === name
        onClicked: root.applyPresetOptimistically(name)
    }
}
