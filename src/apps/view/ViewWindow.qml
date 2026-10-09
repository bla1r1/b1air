import QtQuick
import QtQuick.Controls
import QtQuick.Window
import QtQuick.Layouts
import QtMultimedia
import Ui

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
    title: ViewBackend.fileName ? ViewBackend.fileName : I18n.tr("Viewer")

    // Pictures are shown; films and music are played, in this same window.
    readonly property string kind: ViewBackend.kind
    readonly property bool isMedia: window.kind === "video" || window.kind === "audio"
    // A "film" with no picture in it (an .mp4 or .webm of sound only) is
    // played as a song; known once the player has read the file.
    readonly property bool showsVideo: window.kind === "video"
        && !(player.mediaStatus >= MediaPlayer.LoadedMedia && player.mediaStatus !== MediaPlayer.InvalidMedia
             && !player.hasVideo)
    property real volume: 0.8
    property bool muted: false
    function togglePlay() {
        if (player.playbackState === MediaPlayer.PlayingState) player.pause();
        else player.play();
    }
    function seekBy(ms) { player.position = Math.max(0, Math.min(player.duration, player.position + ms)); }
    function clock(ms) {
        const t = Math.max(0, Math.floor(ms / 1000));
        const h = Math.floor(t / 3600), m = Math.floor(t / 60) % 60, sec = t % 60;
        const two = n => (n < 10 ? "0" : "") + n;
        return (h > 0 ? h + ":" + two(m) : m) + ":" + two(sec);
    }
    function toggleFullScreen() {
        window.visibility = window.visibility === Window.FullScreen ? Window.Windowed : Window.FullScreen;
    }

    // With nothing open this window was a plain empty rectangle: the title bar
    // said "No Image Open" and the canvas said nothing at all, while the zoom,
    // rotate and next/previous controls all sat there enabled with nothing to
    // act on. Every other surface in the suite states an empty view.
    readonly property bool hasImage: ViewBackend.currentPath !== ""

    // How many pictures are in the folder this one came from. Everything that
    // moves between them — the two arrows and the filmstrip — used to be shown
    // whenever an image was open, so a folder holding exactly one picture still
    // got arrows offering to go somewhere and a 70px strip across the whole
    // window holding a single thumbnail of the image already filling the
    // screen.
    readonly property int siblingCount: ViewBackend.filesInDir ? ViewBackend.filesInDir.length : 0
    readonly property bool hasSiblings: window.siblingCount > 1
    width: Design.s(960)
    height: Design.s(640)
    minimumWidth: 500
    minimumHeight: 400
    visible: true
    color: "transparent"
    flags: Qt.Window

    // A second, hand-rolled Tokyo Night palette used to live here alongside the
    // Catppuccin one in Ui/Design.qml, so this window never followed the theme.
    // The names stay — they are used throughout the file — but each now resolves
    // to a design-system role, exactly as FilesWindow.qml was already migrated.
    readonly property color colBg: Design.surface
    readonly property color colDark: Design.ground
    readonly property color colSidebar: Design.sunken
    readonly property color colSunken: Design.sunken
    readonly property color colBorder: Design.glassBorder
    readonly property color colBorderSubtle: Design.line
    readonly property color colBlue: Design.accent
    readonly property color colPurple: Design.mauve
    readonly property color colCyan: Design.sapphire
    readonly property color colGreen: Design.ok
    readonly property color colOrange: Design.warn
    readonly property color colFg: Design.text
    readonly property color colDim: Design.textDim

    // The box a picture is fitted into at 100%: the canvas, or the picture's
    // own size when that is smaller — a small picture is not blown up.
    readonly property size fitSize: {
        const w = imageFlick.width, h = imageFlick.height, dpr = Screen.devicePixelRatio || 1;
        const iw = ViewBackend.imageSize.width / dpr, ih = ViewBackend.imageSize.height / dpr;
        if (!(iw > 0 && ih > 0)) return Qt.size(w, h);
        const k = Math.min(1, w / iw, h / ih);
        return Qt.size(iw * k, ih * k);
    }
    property real zoomFactor: 1.0
    property int rotationAngle: 0
    property bool showFilmstrip: true

    Rectangle {
        id: windowFrame
        anchors.fill: parent
        // No corners or outline of our own: sway draws both, and only sway
        // knows which window has focus. The app drew a fixed 1px line and sway
        // was told `border none` for it, so ours were the only windows on the
        // desktop that did not light up when focused. SwayFX's corner_radius
        // rounds the surface; a 14px radius inside its 10px one left slivers.
        radius: 0
        color: window.colBg
        clip: true

        // Keyboard Shortcuts
        Item {
            focus: true
            Keys.onEscapePressed: {
                if (window.visibility === Window.FullScreen) window.visibility = Window.Windowed;
                else window.close();
            }
            // Zoom and rotate had buttons and the wheel, and no keys. A film
            // or a song takes the keys a player has: space, arrows to seek,
            // up and down for the volume; Ctrl+arrows or Page keys go on to
            // the next file.
            Keys.onPressed: event => {
                const ctrl = event.modifiers & Qt.ControlModifier;
                if (event.key === Qt.Key_PageUp || (ctrl && event.key === Qt.Key_Left)) {
                    ViewBackend.previous();
                } else if (event.key === Qt.Key_PageDown || (ctrl && event.key === Qt.Key_Right)) {
                    ViewBackend.next();
                } else if (window.isMedia) {
                    if (event.key === Qt.Key_Space || event.key === Qt.Key_K) window.togglePlay();
                    else if (event.key === Qt.Key_Left) window.seekBy(-5000);
                    else if (event.key === Qt.Key_Right) window.seekBy(5000);
                    else if (event.key === Qt.Key_J) window.seekBy(-10000);
                    else if (event.key === Qt.Key_L) window.seekBy(10000);
                    else if (event.key === Qt.Key_Up) window.volume = Math.min(1, window.volume + 0.05);
                    else if (event.key === Qt.Key_Down) window.volume = Math.max(0, window.volume - 0.05);
                    else if (event.key === Qt.Key_M) window.muted = !window.muted;
                    else if (event.key === Qt.Key_F) window.toggleFullScreen();
                    else return;
                } else if (event.key === Qt.Key_Left) {
                    ViewBackend.previous();
                } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Space) {
                    ViewBackend.next();
                } else if (event.key === Qt.Key_F) {
                    window.toggleFullScreen();
                } else if (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal) {
                    window.zoomFactor = Math.min(5.0, window.zoomFactor + 0.25);
                } else if (event.key === Qt.Key_Minus) {
                    window.zoomFactor = Math.max(0.2, window.zoomFactor - 0.25);
                } else if (event.key === Qt.Key_0) {
                    window.zoomFactor = 1.0;
                    window.rotationAngle = 0;
                } else if (event.key === Qt.Key_R) {
                    window.rotationAngle = (window.rotationAngle + 90) % 360;
                } else {
                    return;
                }
                event.accepted = true;
            }
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // ── Top Header Toolbar (40px) ────────────────────────────────────
            AppToolbar {
                Layout.fillWidth: true
                z: 10

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Label {
                        Layout.fillWidth: true
                        text: ViewBackend.fileName || I18n.tr("No image open")
                        weight: Design.weight.semibold
                        elide: Text.ElideMiddle
                    }
                    Label {
                        visible: window.hasImage
                        text: [window.kind === "video" && video.sourceRect.width > 0
                                   ? video.sourceRect.width + " × " + video.sourceRect.height : ViewBackend.imageResolution,
                               ViewBackend.fileSize,
                               ViewBackend.totalFiles > 1 ? I18n.tr("%1 of %2", ViewBackend.fileIndex + 1, ViewBackend.totalFiles) : ""]
                              .filter(x => x).join("  ·  ")
                        role: "caption"
                        color: Design.textFaint
                    }
                }
                BarGroup {
                    visible: !window.isMedia
                    CtrlBtn { icon: "\u{f0374}"; tip: I18n.tr("Zoom out (−)"); onClicked: window.zoomFactor = Math.max(0.2, window.zoomFactor - 0.25) }
                    Label {
                        Layout.preferredWidth: Design.s(46)
                        horizontalAlignment: Text.AlignHCenter
                        text: Math.round(window.zoomFactor * 100) + "%"
                        isMono: true
                        role: "caption"
                        dim: true
                    }
                    CtrlBtn { icon: "\u{f0415}"; tip: I18n.tr("Zoom in (+)"); onClicked: window.zoomFactor = Math.min(5.0, window.zoomFactor + 0.25) }
                }
                BarGroup {
                    visible: !window.isMedia
                    CtrlBtn { icon: "\u{f0450}"; tip: I18n.tr("Reset view (0)"); onClicked: { window.zoomFactor = 1.0; window.rotationAngle = 0; } }
                    CtrlBtn { icon: "\u{f0467}"; tip: I18n.tr("Rotate 90° (R)"); onClicked: window.rotationAngle = (window.rotationAngle + 90) % 360 }
                }
                BarGroup {
                    CtrlBtn { visible: window.hasSiblings; icon: "\u{f0570}"; tip: I18n.tr("Filmstrip"); active: window.showFilmstrip; onClicked: window.showFilmstrip = !window.showFilmstrip }
                    CtrlBtn { icon: "\u{f0293}"; tip: I18n.tr("Full screen (F)"); active: window.visibility === Window.FullScreen; onClicked: window.toggleFullScreen() }
                }
                BarButton { visible: !window.isMedia; glyph: "\u{f0e09}"; label: I18n.tr("Set as wallpaper"); onClicked: ViewBackend.setWallpaper() }
            }

            // ── Main Image Canvas ────────────────────────────────────────────
            Item {
                id: controlsArea
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                Flickable {
                    id: imageFlick
                    anchors.fill: parent
                    visible: !window.isMedia
                    contentWidth: width * Math.max(1, window.zoomFactor)
                    contentHeight: height * Math.max(1, window.zoomFactor)
                    boundsBehavior: Flickable.StopAtBounds

                    Item {
                        width: imageFlick.contentWidth
                        height: imageFlick.contentHeight

                        // Fitted into the window, never past its own size:
                        // the item used to take the size it was decoded at —
                        // the screen's — and a window smaller than the screen
                        // showed the middle of the picture.
                        Image {
                            id: mainImage
                            anchors.centerIn: parent
                            width: window.fitSize.width
                            height: window.fitSize.height
                            visible: !ViewBackend.animated
                            source: window.isMedia || ViewBackend.animated ? "" : Paths.fileUrl(ViewBackend.currentPath)
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            autoTransform: true   // a phone's photo the way it was held
                            // Decoded at the size it is shown, not the size of
                            // the file: a 3840x2160 picture was 33 MB of pixels
                            // per copy, kept in the pixmap cache after moving on
                            // to the next one, on top of its texture — 172 MB
                            // for the window with a single wallpaper open.
                            // Zooming in past 100% asks for the full image.
                            sourceSize: window.zoomFactor > 1.05
                                ? undefined
                                : Qt.size(Screen.width * Screen.devicePixelRatio,
                                          Screen.height * Screen.devicePixelRatio)
                            cache: false
                            smooth: true
                            mipmap: window.zoomFactor < 0.9
                            rotation: window.rotationAngle
                            scale: window.zoomFactor

                            Behavior on scale { NumberAnimation { duration: 120 } }
                            Behavior on rotation { NumberAnimation { duration: 150 } }
                        }
                        // A GIF or an animated WebP, played; Image showed the
                        // first frame and stopped there.
                        AnimatedImage {
                            anchors.centerIn: parent
                            width: window.fitSize.width
                            height: window.fitSize.height
                            visible: ViewBackend.animated
                            source: ViewBackend.animated && !window.isMedia ? Paths.fileUrl(ViewBackend.currentPath) : ""
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            cache: false
                            rotation: window.rotationAngle
                            scale: window.zoomFactor
                            Behavior on scale { NumberAnimation { duration: 120 } }
                            Behavior on rotation { NumberAnimation { duration: 150 } }
                        }
                    }

                    // Mouse Wheel Zoom
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.NoButton
                        onWheel: (wheel) => {
                            if (wheel.angleDelta.y > 0) window.zoomFactor = Math.min(5.0, window.zoomFactor + 0.15);
                            else window.zoomFactor = Math.max(0.2, window.zoomFactor - 0.15);
                        }
                    }
                }

                // ── Films and music ──────────────────────────────────────────
                MediaPlayer {
                    id: player
                    source: window.isMedia ? Paths.fileUrl(ViewBackend.currentPath) : ""
                    // The slider as the ear hears it: linear gain put the
                    // whole audible range in the slider's first third. Cubed,
                    // as PulseAudio's own volume slider is.
                    audioOutput: AudioOutput {
                        volume: Math.pow(window.volume, 3)
                        muted: window.muted
                    }
                    videoOutput: video
                    // Open is play: a song or a film opened is one to hear.
                    onSourceChanged: if (source.toString() !== "") play()
                    // The album plays on: at a song's end, the next song.
                    onMediaStatusChanged: {
                        if (mediaStatus !== MediaPlayer.EndOfMedia || window.kind !== "audio") return;
                        const next = ViewBackend.nextOfKind();
                        if (next) ViewBackend.openFile(next);
                    }
                }

                Rectangle {
                    anchors.fill: parent
                    visible: window.showsVideo
                    color: "black"
                    VideoOutput {
                        id: video
                        anchors.fill: parent
                        fillMode: VideoOutput.PreserveAspectFit
                    }
                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onClicked: window.togglePlay()
                        onDoubleClicked: window.toggleFullScreen()
                        onPositionChanged: controls.wake()
                    }
                }

                // A song: its cover, and what the tags call it.
                ColumnLayout {
                    anchors.centerIn: parent
                    width: Math.min(parent.width - Design.s(48), Design.s(420))
                    visible: window.isMedia && !window.showsVideo
                    spacing: Design.s(Design.space.md)
                    Rectangle {
                        Layout.alignment: Qt.AlignHCenter
                        readonly property real side: Math.min(Design.s(300), parent.width, controlsArea.height - Design.s(150))
                        Layout.preferredWidth: side
                        Layout.preferredHeight: side
                        radius: Design.s(Design.radius.card)
                        color: Design.raised
                        clip: true
                        Icon {
                            anchors.centerIn: parent
                            visible: cover.status !== Image.Ready
                            text: "\u{f075a}"
                            font.pixelSize: parent.side / 3
                            color: Design.textFaint
                        }
                        Image {
                            id: cover
                            anchors.fill: parent
                            source: window.isMedia && !window.showsVideo ? "image://thumb/" + encodeURIComponent(ViewBackend.currentPath) : ""
                            sourceSize: Qt.size(512, 512)
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                        }
                    }
                    Label {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        role: "title"
                        weight: Design.weight.semibold
                        elide: Text.ElideRight
                        text: (player.metaData, player.metaData.stringValue(MediaMetaData.Title)) || ViewBackend.fileName
                    }
                    Label {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        dim: true
                        elide: Text.ElideRight
                        text: (player.metaData, [player.metaData.stringValue(MediaMetaData.ContributingArtist)
                                                 || player.metaData.stringValue(MediaMetaData.AlbumArtist),
                                                 player.metaData.stringValue(MediaMetaData.AlbumTitle)].filter(x => x).join(" — "))
                    }
                }

                EmptyState {
                    anchors.centerIn: parent
                    width: parent.width - Design.s(Design.space.xl) * 2
                    visible: !window.hasImage
                    icon: "\u{f02e9}"
                    title: I18n.tr("Nothing open")
                    hint: I18n.tr("Open a picture, a film or a song from Files, or pass a path: b1air-view file")
                }

                // Left Arrow Overlay (Prev)
                Rectangle {
                    anchors.left: parent.left
                    anchors.leftMargin: Design.s(16)
                    anchors.verticalCenter: parent.verticalCenter
                    width: Design.s(36); height: Design.s(36); radius: Design.s(18)
                    color: prevArrArea.containsMouse ? Design.tint(Design.ground, 0.85) : Design.tint(Design.ground, 0.45)
                    border.color: window.colBorder
                    border.width: 1
                    visible: window.hasImage && window.hasSiblings
                    Text { anchors.centerIn: parent; text: "󰁍"; font.family: Design.font.mono; font.pixelSize: Design.s(14); color: window.colFg }
                    MouseArea { id: prevArrArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ViewBackend.previous() }
                }

                // Right Arrow Overlay (Next)
                Rectangle {
                    anchors.right: parent.right
                    anchors.rightMargin: Design.s(16)
                    anchors.verticalCenter: parent.verticalCenter
                    width: Design.s(36); height: Design.s(36); radius: Design.s(18)
                    visible: window.hasImage && window.hasSiblings
                    color: nextArrArea.containsMouse ? Design.tint(Design.ground, 0.85) : Design.tint(Design.ground, 0.45)
                    border.color: window.colBorder
                    border.width: 1
                    Text { anchors.centerIn: parent; text: "󰁔"; font.family: Design.font.mono; font.pixelSize: Design.s(14); color: window.colFg }
                    MouseArea { id: nextArrArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: ViewBackend.next() }
                }
            }

            // ── Transport: play, seek, volume ────────────────────────────────
            Rectangle {
                id: controls
                Layout.fillWidth: true
                Layout.preferredHeight: Design.s(52)
                color: window.colSidebar
                // In a full-screen film it steps aside until the mouse moves.
                property bool awake: true
                function wake() { awake = true; sleepTimer.restart(); }
                Timer {
                    id: sleepTimer
                    interval: 2500
                    onTriggered: if (window.visibility === Window.FullScreen && window.showsVideo
                                     && player.playbackState === MediaPlayer.PlayingState) controls.awake = false
                }
                visible: window.isMedia && (controls.awake || window.visibility !== Window.FullScreen || !window.showsVideo)
                Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: window.colBorder }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Design.s(Design.space.md)
                    anchors.rightMargin: Design.s(Design.space.md)
                    spacing: Design.s(Design.space.sm)

                    BarGroup {
                        CtrlBtn { icon: "\u{f04ae}"; tip: I18n.tr("Previous (Page Up)"); enabled: ViewBackend.hasPrevious; onClicked: ViewBackend.previous() }
                        CtrlBtn {
                            icon: player.playbackState === MediaPlayer.PlayingState ? "\u{f03e4}" : "\u{f040a}"
                            tip: player.playbackState === MediaPlayer.PlayingState ? I18n.tr("Pause (Space)") : I18n.tr("Play (Space)")
                            onClicked: window.togglePlay()
                        }
                        CtrlBtn { icon: "\u{f04ad}"; tip: I18n.tr("Next (Page Down)"); enabled: ViewBackend.hasNext; onClicked: ViewBackend.next() }
                    }

                    Label {
                        text: window.clock(seek.dragging ? seek.dragPosition : player.position)
                        isMono: true
                        role: "caption"
                        dim: true
                    }

                    // Where in the file: a thin line, thicker under the pointer.
                    Item {
                        id: seek
                        Layout.fillWidth: true
                        Layout.preferredHeight: Design.s(24)
                        property bool dragging: false
                        property real dragPosition: 0
                        readonly property real ratio: player.duration > 0
                            ? (dragging ? dragPosition : player.position) / player.duration : 0
                        Rectangle {
                            id: groove
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width
                            height: seekArea.containsMouse || seek.dragging ? Design.s(6) : Design.s(4)
                            radius: height / 2
                            color: Design.tint(Design.text, 0.14)
                            Rectangle {
                                width: parent.width * seek.ratio
                                height: parent.height
                                radius: parent.radius
                                color: Design.accent
                            }
                        }
                        Rectangle {
                            visible: seekArea.containsMouse || seek.dragging
                            x: Math.round(seek.width * seek.ratio - width / 2)
                            anchors.verticalCenter: parent.verticalCenter
                            width: Design.s(12); height: width; radius: width / 2
                            color: Design.text
                        }
                        MouseArea {
                            id: seekArea
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: player.seekable
                            cursorShape: Qt.PointingHandCursor
                            function at(x) { return Math.max(0, Math.min(1, x / width)) * player.duration; }
                            onPressed: mouse => { seek.dragging = true; seek.dragPosition = at(mouse.x); }
                            onPositionChanged: mouse => { if (seek.dragging) seek.dragPosition = at(mouse.x); }
                            onReleased: mouse => { player.position = at(mouse.x); seek.dragging = false; }
                        }
                    }

                    Label {
                        text: window.clock(player.duration)
                        isMono: true
                        role: "caption"
                        dim: true
                    }

                    // A film with more than one language, or with subtitles:
                    // which to hear and which to read. Shown only then.
                    CtrlBtn {
                        id: tracksBtn
                        visible: player.audioTracks.length > 1 || player.subtitleTracks.length > 0
                        icon: "\u{f05ca}"
                        tip: I18n.tr("Audio and subtitles")
                        onClicked: tracksMenu.popup(tracksBtn, 0, -tracksMenu.implicitHeight)
                    }

                    Slider {
                        Layout.preferredWidth: Design.s(130)
                        Layout.preferredHeight: Design.s(30)
                        value: Math.round(window.volume * 100)
                        muted: window.muted
                        icon: window.muted || window.volume === 0 ? "\u{f0581}" : "\u{f057e}"
                        iconClickable: true
                        showPercent: false
                        onMoved: pct => { window.volume = pct / 100; window.muted = false; }
                        onIconClicked: window.muted = !window.muted
                    }
                }
            }

            // ── Bottom Filmstrip Thumbnail Strip (Optional, 70px) ─────────────
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Design.s(70)
                color: window.colSidebar
                visible: window.showFilmstrip && window.hasSiblings

                // One rule where the strip meets the picture, not a box: a full
                // border on a bar this wide draws its side edges on top of the
                // window frame's own.
                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    height: 1
                    color: window.colBorder
                }

                ListView {
                    id: filmstripList
                    anchors.fill: parent
                    anchors.margins: Design.s(6)
                    orientation: ListView.Horizontal
                    spacing: Design.s(6)
                    clip: true
                    model: ViewBackend.filesInDir
                    // Delegates kept and refilled while scrolling a long
                    // folder, and the open file kept in sight.
                    reuseItems: true
                    cacheBuffer: Design.s(64) * 6
                    currentIndex: ViewBackend.fileIndex
                    highlightFollowsCurrentItem: false
                    onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)

                    delegate: Rectangle {
                        width: Design.s(58); height: Design.s(58); radius: Design.s(6)
                        color: isCur ? Design.tint(Design.accent, 0.25) : (thumbArea.containsMouse ? Design.tint(Design.text, 0.08) : "transparent")
                        border.color: isCur ? window.colBlue : "transparent"
                        border.width: 1

                        readonly property bool isCur: modelData.path === ViewBackend.currentPath

                        // A film by a frame of it, a song by its cover, a
                        // picture small — all from the thumbnail cache Files
                        // fills, made off this thread. Each picture of the
                        // folder used to be read whole for its 60px square,
                        // again every time.
                        Image {
                            id: stripThumb
                            anchors.fill: parent
                            anchors.margins: Design.s(3)
                            source: "image://thumb/" + encodeURIComponent(modelData.path)
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            sourceSize: Qt.size(Design.s(64), Design.s(64))
                        }
                        Icon {
                            anchors.centerIn: parent
                            visible: modelData.kind !== "image"
                            text: modelData.kind === "video" ? "\u{f0567}" : "\u{f075a}"
                            color: stripThumb.status === Image.Ready ? "white" : Design.textFaint
                            style: Text.Outline
                            styleColor: stripThumb.status === Image.Ready ? Qt.alpha("black", 0.5) : "transparent"
                        }

                        MouseArea {
                            id: thumbArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: ViewBackend.openFile(modelData.path)
                        }
                    }
                }
            }
        }
    }

    // A track by what its tags say: its title and language, else its number.
    function trackName(meta, i) {
        const lang = meta ? meta.stringValue(MediaMetaData.Language) : "";
        const title = meta ? meta.stringValue(MediaMetaData.Title) : "";
        const name = [title, lang === "C" || lang === "Default" ? "" : lang].filter(x => x).join(" · ");
        return name || I18n.tr("Track %1", i + 1);
    }

    AppMenu {
        id: tracksMenu
        AppMenu {
            id: audioMenu
            title: I18n.tr("Audio")
            enabled: player.audioTracks.length > 1
            Instantiator {
                model: player.audioTracks
                delegate: AppMenuItem {
                    required property var modelData
                    required property int index
                    text: window.trackName(modelData, index)
                    glyph: player.activeAudioTrack === index ? "\u{f012c}" : ""
                    onTriggered: player.activeAudioTrack = index
                }
                onObjectAdded: (i, o) => audioMenu.insertItem(i, o)
                onObjectRemoved: (i, o) => audioMenu.removeItem(o)
            }
        }
        AppMenu {
            id: subtitleMenu
            title: I18n.tr("Subtitles")
            enabled: player.subtitleTracks.length > 0
            AppMenuItem {
                text: I18n.tr("Off")
                glyph: player.activeSubtitleTrack < 0 ? "\u{f012c}" : ""
                onTriggered: player.activeSubtitleTrack = -1
            }
            Instantiator {
                model: player.subtitleTracks
                delegate: AppMenuItem {
                    required property var modelData
                    required property int index
                    text: window.trackName(modelData, index)
                    glyph: player.activeSubtitleTrack === index ? "\u{f012c}" : ""
                    onTriggered: player.activeSubtitleTrack = index
                }
                // After "Off".
                onObjectAdded: (i, o) => subtitleMenu.insertItem(i + 1, o)
                onObjectRemoved: (i, o) => subtitleMenu.removeItem(o)
            }
        }
    }

    // The suite's toolbar button; `tip` was declared here and never shown.
    component CtrlBtn: BarButton {
        property string icon: ""
        property bool active: false
        glyph: icon
        checked: active
    }
}
