import QtQuick
import QtQuick.Controls
import QtQuick.Window
import QtQuick.Layouts
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
    title: ViewBackend.fileName ? ("Image Viewer — " + ViewBackend.fileName) : "Image Viewer"

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
            Keys.onLeftPressed: ViewBackend.previous()
            Keys.onRightPressed: ViewBackend.next()
            Keys.onEscapePressed: window.close()
            Keys.onSpacePressed: ViewBackend.next()
            // Zoom and rotate had buttons and the wheel, and no keys.
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Plus || event.key === Qt.Key_Equal) {
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
                spacing: Design.s(Design.space.sm)

                Text {
                    text: "\u{f02e9}"
                    font.family: Design.font.icon
                    font.pixelSize: Design.s(20)
                    color: Design.accent
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Label {
                        Layout.fillWidth: true
                        text: ViewBackend.fileName || "No image open"
                        weight: Design.weight.semibold
                        elide: Text.ElideMiddle
                    }
                    Label {
                        visible: ViewBackend.imageResolution !== "" && ViewBackend.imageResolution !== "Unknown"
                        text: ViewBackend.imageResolution + "  ·  " + ViewBackend.fileSize
                              + (ViewBackend.totalFiles > 1 ? "  ·  " + (ViewBackend.fileIndex + 1) + " of " + ViewBackend.totalFiles : "")
                        role: "caption"
                        dim: true
                    }
                }

                CtrlBtn { icon: "\u{f0374}"; tip: "Zoom out (−)"; onClicked: window.zoomFactor = Math.max(0.2, window.zoomFactor - 0.25) }
                Label {
                    Layout.preferredWidth: Design.s(48)
                    horizontalAlignment: Text.AlignHCenter
                    text: Math.round(window.zoomFactor * 100) + "%"
                    isMono: true
                    role: "caption"
                    dim: true
                }
                CtrlBtn { icon: "\u{f0415}"; tip: "Zoom in (+)"; onClicked: window.zoomFactor = Math.min(5.0, window.zoomFactor + 0.25) }
                CtrlBtn { icon: "\u{f0450}"; tip: "Reset view (0)"; onClicked: { window.zoomFactor = 1.0; window.rotationAngle = 0; } }
                CtrlBtn { icon: "\u{f0467}"; tip: "Rotate 90° (R)"; onClicked: window.rotationAngle = (window.rotationAngle + 90) % 360 }
                CtrlBtn { visible: window.hasSiblings; icon: "\u{f0570}"; tip: "Filmstrip"; active: window.showFilmstrip; onClicked: window.showFilmstrip = !window.showFilmstrip }
                BarButton { glyph: "\u{f0e09}"; label: "Set as wallpaper"; onClicked: ViewBackend.setWallpaper() }
            }

            // ── Main Image Canvas ────────────────────────────────────────────
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true

                Flickable {
                    id: imageFlick
                    anchors.fill: parent
                    contentWidth: Math.max(width, mainImage.width * window.zoomFactor)
                    contentHeight: Math.max(height, mainImage.height * window.zoomFactor)
                    boundsBehavior: Flickable.StopAtBounds

                    Item {
                        width: imageFlick.contentWidth
                        height: imageFlick.contentHeight

                        Image {
                            id: mainImage
                            anchors.centerIn: parent
                            source: Paths.fileUrl(ViewBackend.currentPath)
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
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

                EmptyState {
                    anchors.centerIn: parent
                    width: parent.width - Design.s(Design.space.xl) * 2
                    visible: !window.hasImage
                    icon: "\u{f02e9}"
                    title: "No image open"
                    hint: "Open one from Files, or pass a path: b1air-view picture.png"
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

                    delegate: Rectangle {
                        width: Design.s(58); height: Design.s(58); radius: Design.s(6)
                        color: isCur ? Design.tint(Design.accent, 0.25) : (thumbArea.containsMouse ? Design.tint(Design.text, 0.08) : "transparent")
                        border.color: isCur ? window.colBlue : "transparent"
                        border.width: 1

                        readonly property bool isCur: modelData.path === ViewBackend.currentPath

                        Image {
                            anchors.fill: parent
                            anchors.margins: Design.s(3)
                            source: Paths.fileUrl(modelData.path)
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            sourceSize: Qt.size(60, 60)
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

    // The suite's toolbar button; `tip` was declared here and never shown.
    component CtrlBtn: BarButton {
        property string icon: ""
        property bool active: false
        glyph: icon
        checked: active
    }
}
