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



    // The window used to paint itself in lavender and mauve, which are roles
    // no other surface in the shell uses as its primary. Opened next to the
    // Control Center or the Clipboard it read as a different application that
    // happened to be running inside this one. These names stay — the file is
    // full of them — but the two that carried the identity now resolve to the
    // accent everything else follows.
    readonly property color lavender: Design.accent
    readonly property color mauve: Design.accent

    // Data State Properties
    property var musicData: {
        "title": "", "artist": "", "status": "Stopped", "percent": 0,
        "lengthStr": "00:00", "positionStr": "00:00", "timeStr": "--:-- / --:--",
        "source": "Offline", "playerName": "", "blur": "", "grad": "",
        "deviceIcon": "󰓃", "deviceName": "Speaker",
        "artUrl": ""
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
    // musicData above is the shape this window draws, and nothing
    // ever wrote to it. Services/Media was built for exactly this window —
    // its own header says "MusicPopup reads Media.track.*" — but the window
    // was never moved onto it, so it drew its own defaults forever: the title
    // stayed "Loading...", the clock stayed 00:00, the source stayed
    // "Offline".
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
        // With no player at all the empty state below speaks instead.
        merged.title = t.title && String(t.title).trim() !== "" ? t.title : I18n.tr("Nothing playing");
        merged.source = t.source || (Media.hasPlayer ? (t.playerName || "") : "Offline");
        merged.positionStr = t.positionStr || "00:00";
        merged.lengthStr = t.lengthStr || "00:00";
        merged.percent = t.percent !== undefined ? t.percent : 0;

        root.musicData = merged;
    }

    Connections {
        target: Media
        function onTrackChanged()  { root._syncFromService(); }
        function onStatusChanged() { root._syncFromService(); }
    }

    Component.onCompleted: {
        Media.acquire();
        root._syncFromService();
        Media.refresh();
    }

    Component.onDestruction: {
        Media.release();
        if (root.showLyrics) Lyrics.release();
    }

    // Lyrics in place of the title and artist (Services/Lyrics): the line
    // being sung, and the next one under it.
    property bool showLyrics: false
    onShowLyricsChanged: root.showLyrics ? Lyrics.acquire() : Lyrics.release()

    // Accumulators for Process standard output
    property string accumulatedMusicOut: ""

    // UI State for debouncing the slider and play button
    property bool userIsSeeking: false
    property bool userToggledPlay: false
    
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

    }

    // --- FIXED COLOR PARSING LOGIC ---
    property color dynamicTextColor: {
        if (root.musicData && root.musicData.textColor) {
            var c = String(root.musicData.textColor).trim();
            // Securely extract exactly #RRGGBB, ignoring any alpha leak from the shell
            var match = c.match(/^(#[0-9a-fA-F]{6})/);
            if (match) return match[1];
        }
        return Design.text;
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
        transform: Translate { y: Design.s(Design.space.lg) * (1 - root.introMain) }

        // An animated border stood here: a rotating four-colour gradient,
        // masked to a stroke that "charged" round the edge on open. The
        // popup's own frame is the border now, as on every other popup.

        // INNER WINDOW BOX
        Box {
            id: innerBg
            anchors.fill: parent
            // No fill of its own: a glass card inset in the popup's glass
            // drew a second frame inside the first. It is the clip and the
            // cover's blur, no more.
            anchors.margins: Design.s(Design.border)
            color: "transparent"
            // Inside the rim, so the rim's radius less the rim: the same
            // radius a pixel in drew a crescent at each corner.
            radius: Design.s(Design.radius.panel) - Design.s(Design.border)

            // FIX: This forces the entire background to render as a single hardware texture,
            // preventing the UI from dragging and causing "shadow boxes" during the StackView transition!
            layer.enabled: root.canShade

            // Provide a perfectly rounded mask for the inner content
            Box {
                id: innerBgMask
                anchors.fill: parent
                radius: innerBg.radius
                visible: false
                
                // FIX: Masks in MultiEffect strictly require layer.enabled to correctly capture the radius during scaling!
                layer.enabled: root.canShade 
            }

            Item {
                id: bgEffectsLayer
                anchors.fill: parent
                
                // This correctly clamps the blur and orbit circles to the 10px radius corners
                layer.enabled: root.canShade
                layer.effect: Effect {
                    maskEnabled: true
                    maskSource: innerBgMask
                }

                // LAYER 1: Background Blur (Smooth fade-in)
                Picture {
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
                Box {
                    width: parent.width * 0.8; height: width; radius: width / 2
                    anchors.centerIn: parent
                    
                    opacity: root.musicData.status === "Playing" ? 0.08 : (root.musicData.status === "Paused" ? 0.04 : 0.0)
                    color: root.musicData.status === "Playing" ? Design.accent : Design.active
                    Behavior on color { ColorAnimation { duration: root.tintDuration } }
                    Behavior on opacity { NumberAnimation { duration: root.introDuration } }
                }
                
                Box {
                    width: parent.width * 0.9; height: width; radius: width / 2
                    anchors.centerIn: parent
                    
                    opacity: root.musicData.status === "Playing" ? 0.08 : (root.musicData.status === "Paused" ? 0.02 : 0.0)
                    color: root.musicData.status === "Playing" ? Design.accent : Design.hover
                    Behavior on color { ColorAnimation { duration: root.tintDuration } }
                    Behavior on opacity { NumberAnimation { duration: root.introDuration } }
                }
            }

            // With no player there is nothing to show or drive: the cover,
            // seek bar and transport went on offering controls that did
            // nothing, under "No media player" set as if it were a song.
            EmptyState {
                anchors.centerIn: parent
                width: parent.width - Design.s(Design.space.lg) * 2
                visible: !Media.hasPlayer
                opacity: root.introText
                icon: "\u{f075a}"
                title: I18n.tr("No media player")
                hint: I18n.tr("Start playing in any app to control it here.")
            }

            // LAYER 2: UI Content
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: Design.s(Design.space.lg)
                spacing: 0
                visible: Media.hasPlayer

                // ==========================================
                // TOP INFO SECTION
                // ==========================================
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Design.s(Design.width.control)
                    spacing: Design.s(Design.space.xl)

                    // Cover Art Wrapper
                    Item {
                        Layout.preferredWidth: Design.s(Design.width.control)
                        Layout.preferredHeight: Design.s(Design.width.control)
                        Layout.alignment: Qt.AlignVCenter

                        opacity: root.introCover
                        // Enhanced 2D drift animation
                        transform: Translate { x: -Design.s(Design.space.xxl) * (1 - root.introCover); y: Design.s(Design.space.sm) * (1 - root.introCover) }

                        // Elastic response to play/pause state
                        scale: root.musicData.status === "Playing" ? 1.0 : 0.90
                        Behavior on scale { NumberAnimation { duration: root.introDuration; easing.type: Easing.OutElastic; easing.overshoot: 1.2 } }

                        Box {
                            anchors.fill: parent
                            radius: width / 2
                            color: Design.hover
                            border.width: Design.s(Design.focusWidth)
                            border.color: root.musicData.status === "Playing" ? Design.accent : Design.textFaint
                            Behavior on border.color { ColorAnimation { duration: Design.duration.slow } }

                            // Glow Effect surrounding the thumbnail
                            Box {
                                z: -1
                                anchors.centerIn: parent
                                width: parent.width + Design.s(Design.space.lg)
                                height: parent.height + Design.s(Design.space.lg)
                                radius: width / 2
                                color: Design.accent
                                opacity: root.musicData.status === "Playing" ? 0.5 : 0.0
                                Behavior on opacity { NumberAnimation { duration: Design.duration.slow } }
                                layer.enabled: root.canShade
                                layer.effect: Effect {
                                    blurEnabled: true
                                    blurMax: 32
                                    blur: 1.0
                                }
                            }

                            Item {
                                anchors.fill: parent
                                anchors.margins: Design.s(Design.space.xs)
                                Picture {
                                    id: artImg
                                    anchors.fill: parent
                                    // Decoded at the size drawn, not the file's (a 4K picture is 33 MB of pixels).
                                    sourceSize: Qt.size(512, 512)
                                    source: root.musicData.artUrl ? "file://" + root.musicData.artUrl : ""
                                    fillMode: Image.PreserveAspectCrop
                                    visible: false 
                                }
                                Box {
                                    id: maskRect
                                    anchors.fill: parent
                                    radius: width / 2
                                    visible: false
                                    layer.enabled: root.canShade 
                                }
                                Effect {
                                    anchors.fill: parent
                                    source: artImg
                                    maskEnabled: true
                                    maskSource: maskRect
                                    opacity: artImg.status === Image.Ready ? 1.0 : 0.0
                                    Behavior on opacity { NumberAnimation { duration: root.introDuration } }
                                }
                                
                                // NEW: Dimmed slightly by tinting with the primary mauve accent, as requested
                                Box {
                                    anchors.fill: parent
                                    radius: width / 2
                                    color: Qt.rgba(Design.accent.r, Design.accent.g, Design.accent.b, 0.2)
                                    opacity: artImg.status === Image.Ready ? 1.0 : 0.0
                                    Behavior on opacity { NumberAnimation { duration: root.introDuration } }
                                }

                                Box {
                                    width: Design.s(Design.size.row); height: Design.s(Design.size.row)
                                    radius: width / 2; color: "#000000"
                                    opacity: 0.8; anchors.centerIn: parent
                                }
                            }
                            
                            NumberAnimation on rotation {
                                from: 0; to: 360; duration: root.introDuration
                                loops: Animation.Infinite
                                // Only while the player is on screen: closed with
                                // music playing, it kept the shell ticking for a
                                // record nobody could see. The shell closes a
                                // panel by hiding its window (Main.qml), which
                                // leaves the item itself "visible".
                                running: root.visible && root.Window.visibility !== Window.Hidden
                                paused: root.musicData.status !== "Playing"
                            }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: Design.s(Design.space.lg)

                        // TEXT INFO CHUNK
                        ColumnLayout {
                            spacing: Design.s(Design.space.xs)
                            opacity: root.introText
                            transform: Translate { x: Design.s(Design.space.xxl) * (1 - root.introText) }
                            
                            // HARD-LOCKED SEAMLESS INFINITE MARQUEE
                            Item {
                                id: titleClipRect
                                visible: !root.showLyrics
                                Layout.fillWidth: true
                                Layout.preferredHeight: Design.s(Design.size.sm) 
                                clip: true

                                // This is the distance between the end of the text and the clone
                                property int marqueeSpacing: Design.s(Design.size.tile)

                                Item {
                                    id: marqueeContainer
                                    height: parent.height

                                    Row {
                                        spacing: titleClipRect.marqueeSpacing
                                        Label {
                                            id: titleTextMain
                                            text: root.musicData.title
                                            color: root.dynamicTextColor
                                            role: "title"
                                            weight: Design.weight.semibold
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
                                        Label {
                                            id: titleTextClone
                                            text: root.musicData.title
                                            color: root.dynamicTextColor
                                            role: "title"
                                            weight: Design.weight.semibold
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

                            // ── Lyrics, in the title's place ──────────────────
                            Item {
                                id: lyricsView
                                visible: root.showLyrics
                                Layout.fillWidth: true
                                Layout.preferredHeight: Design.s(Design.size.sm) + Design.s(Design.size.mini)
                                                        + Design.s(Design.space.xs)
                                readonly property bool synced: Lyrics.state === "found" && Lyrics.synced
                                readonly property int at: Lyrics.current
                                readonly property string now: !synced ? ""
                                    : at < 0 ? "\u2026" : (Lyrics.lines[at].text || "\u266a")
                                readonly property string after: !synced || at + 1 >= Lyrics.lines.length ? ""
                                    : (Lyrics.lines[at + 1].text || "\u266a")
                                onNowChanged: lineIn.restart()

                                ColumnLayout {
                                    anchors.fill: parent
                                    visible: lyricsView.synced
                                    spacing: Design.s(Design.space.xxs)
                                    Label {
                                        id: lyricNow
                                        Layout.fillWidth: true
                                        text: lyricsView.now
                                        color: root.dynamicTextColor
                                        role: "title"
                                        weight: Design.weight.semibold
                                        elide: Text.ElideRight
                                        NumberAnimation on opacity {
                                            id: lineIn
                                            from: 0.3; to: 1
                                            duration: Design.reduceMotion ? 0 : Design.duration.base
                                            easing.type: Easing.OutCubic
                                        }
                                    }
                                    Label {
                                        Layout.fillWidth: true
                                        text: lyricsView.after
                                        role: "footnote"
                                        color: Design.textDim
                                        elide: Text.ElideRight
                                    }
                                }

                                // Plain lyrics: the words, to scroll through.
                                ScrollArea {
                                    anchors.fill: parent
                                    framed: false
                                    visible: Lyrics.state === "found" && !Lyrics.synced
                                    Label {
                                        width: parent.width
                                        text: Lyrics.lines.map(l => l.text).join("\n")
                                        role: "footnote"
                                        color: Design.textDim
                                        wrapMode: Text.WordWrap
                                    }
                                }

                                ColumnLayout {
                                    anchors.fill: parent
                                    visible: Lyrics.state !== "found"
                                    spacing: Design.s(Design.space.xxs)
                                    Label {
                                        Layout.fillWidth: true
                                        text: Lyrics.state === "loading" ? I18n.tr("Looking for lyrics…")
                                            : I18n.tr("No lyrics for this track")
                                        role: "body"
                                        color: Design.textDim
                                        elide: Text.ElideRight
                                    }
                                    Button {
                                        visible: Lyrics.state === "ask"
                                        size: "sm"
                                        variant: "ghost"
                                        label: I18n.tr("Look on LRCLIB")
                                        tip: I18n.tr("Sends the title and artist to lrclib.net, for this and later tracks")
                                        onClicked: Lyrics.allowOnline()
                                    }
                                }
                            }

                            Label {
                                visible: !root.showLyrics
                                text: root.musicData.artist ? I18n.tr("BY %1", root.musicData.artist) : ""
                                color: Design.textDim // Better matugen match
                                size: Design.s(Design.font.glyphSm)
                                weight: Design.weight.semibold
                                elide: Text.ElideRight
                                maximumLineCount: 1 // Strict 1 line
                                Layout.fillWidth: true
                                Layout.preferredHeight: Design.s(Design.size.mini)
                            }
                            RowLayout {
                                spacing: Design.s(Design.space.sm)
                                Surface {
                                    border.width: 0
                                    radius: Design.s(Design.radius.sm)
                                    Layout.preferredHeight: Design.s(Design.size.xs)
                                    Layout.preferredWidth: pillContent.width + Design.s(Design.space.lg)
                                    RowLayout {
                                        id: pillContent
                                        anchors.centerIn: parent
                                        spacing: Design.s(Design.space.xs)
                                        Icon { role: "body"; text: root.musicData.deviceIcon || "󰓃"; color: Design.accent }
                                        Label {
                                            text: root.musicData.deviceName || I18n.tr("Speaker")
                                            color: Design.textFaint
                                            role: "footnote"
                                            weight: Design.weight.semibold
                                        }
                                    }
                                }
                                IconButton {
                                    icon: "\u{f0370}"
                                    label: root.showLyrics ? I18n.tr("Hide lyrics") : I18n.tr("Lyrics")
                                    tone: root.showLyrics ? Design.accent : Design.textDim
                                    onClicked: root.showLyrics = !root.showLyrics
                                }
                                Label {
                                    text: I18n.tr("VIA %1", I18n.tr(root.musicData.source || "Offline"))
                                    color: Design.textFaint // Better matugen match
                                    isMono: true
                                    role: "footnote"
                                    weight: Design.weight.semibold
                                    font.italic: true
                                }
                            }
                        }

                        // PROGRESS AREA CHUNK
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: Design.s(Design.space.xs)
                            opacity: root.introControls
                            transform: Translate { x: Design.s(Design.space.lg) * (1 - root.introControls); y: Design.s(Design.space.sm) * (1 - root.introControls) }

                            Scrubber {
                                id: progBar
                                Layout.fillWidth: true
                                Layout.preferredHeight: Design.s(Design.size.mini) 
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

                                        // The bar is in percent, the player in seconds:
                                        // it was handed the percent, so every seek
                                        // landed in the first hundred seconds.
                                        Media.seek(value / 100 * (Media.player ? Media.player.length : 0));
                                        
                                        seekDebounceTimer.restart();
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Label {
                                    text: root.musicData.positionStr || "00:00"
                                    color: Design.textFaint
                                    isMono: true
                                    weight: Design.weight.semibold
                                }
                                Item { Layout.fillWidth: true }
                                Label {
                                    text: root.musicData.lengthStr || "00:00"
                                    color: Design.textFaint
                                    isMono: true
                                    weight: Design.weight.semibold
                                }
                            }
                        }

                        // MEDIA CONTROLS CHUNK
                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: Design.s(Design.space.xxl)
                            opacity: root.introControls
                            transform: Translate { y: Design.s(Design.space.lg) * (1 - root.introControls) }

                            PointerArea {
                                width: Design.s(Design.size.sm); height: Design.s(Design.size.sm)
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Media.previous()
                                Icon { role: "title"; anchors.centerIn: parent; text: ""; color: parent.pressed ? Design.text : Design.textFaint }
                            }
                            PointerArea {
                                id: playPauseBtn
                                width: Design.s(Design.size.art); height: Design.s(Design.size.art)
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
                                Box {
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

                                Icon { 
                                    anchors.centerIn: parent
                                    text: root.musicData.status === "Playing" ? "" : ""
                                    color: parent.pressed ? Design.accent : Design.accent
                                    role: "hero"
                                    Behavior on color { ColorAnimation { duration: Design.duration.fast } }
                                }
                            }
                            PointerArea {
                                width: Design.s(Design.size.sm); height: Design.s(Design.size.sm)
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Media.next()
                                Icon { role: "title"; anchors.centerIn: parent; text: ""; color: parent.pressed ? Design.text : Design.textFaint }
                            }
                        }
                    }
                }

            }
        }
    }

}
