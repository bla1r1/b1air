import QtQuick
import QtQuick.Controls
import QtQuick.Window
import QtQuick.Layouts
import Ui

ApplicationWindow {
    id: window
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
        radius: (window.visibility === Window.Maximized) ? 0 : Design.s(14)
        color: window.colBg
        border.color: (window.visibility === Window.Maximized) ? "transparent" : window.colBorder
        border.width: 1
        clip: true

        // Keyboard Shortcuts
        Item {
            focus: true
            Keys.onLeftPressed: ViewBackend.previous()
            Keys.onRightPressed: ViewBackend.next()
            Keys.onEscapePressed: window.close()
            Keys.onSpacePressed: ViewBackend.next()
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // ── Top Header Toolbar (40px) ────────────────────────────────────
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: Design.s(40)
                color: window.colSidebar
                border.color: window.colBorder
                border.width: 1
                z: 10

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Design.s(12)
                    anchors.rightMargin: Design.s(12)
                    spacing: Design.s(8)

                    // App Icon & File Name
                    Row {
                        spacing: Design.s(8)
                        Layout.alignment: Qt.AlignVCenter
                        Text {
                            text: "󰋩"
                            font.family: Design.font.mono
                            font.pixelSize: Design.s(15)
                            color: window.colBlue
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: ViewBackend.fileName || "No Image Open"
                            font.family: Design.font.sans
                            font.pixelSize: Design.s(12)
                            font.bold: true
                            color: window.colFg
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }

                    // Image Dimensions Badge
                    Rectangle {
                        width: dimText.implicitWidth + Design.s(12)
                        height: Design.s(20)
                        radius: Design.s(4)
                        color: Design.tint(Design.text, 0.08)
                        visible: ViewBackend.imageResolution !== "" && ViewBackend.imageResolution !== "Unknown"

                        Text {
                            id: dimText
                            anchors.centerIn: parent
                            text: ViewBackend.imageResolution + "  •  " + ViewBackend.fileSize
                            font.family: Design.font.mono
                            font.pixelSize: Design.s(10)
                            color: window.colDim
                        }
                    }

                    Item { Layout.fillWidth: true }

                    // Viewer Controls: Zoom In, Zoom Out, Reset, Rotate, Filmstrip Toggle, Wallpaper
                    //
                    // Two of these were the wrong glyph, which in a row of
                    // unlabelled icon buttons is the whole message: Zoom Out
                    // was nf-md-close, so the control beside the zoom
                    // percentage was a ✕ that reads as "close the viewer", and
                    // Set Wallpaper was nf-md-music, a note. Checked by
                    // rendering the codepoints rather than by reading the
                    // names — that is how these two were found in the first
                    // place.
                    Row {
                        spacing: Design.s(4)
                        Layout.alignment: Qt.AlignVCenter

                        CtrlBtn { icon: "󰍴"; tip: "Zoom Out"; onClicked: window.zoomFactor = Math.max(0.2, window.zoomFactor - 0.25) }
                        Rectangle {
                            width: zoomText.implicitWidth + Design.s(10); height: Design.s(26); radius: Design.s(4)
                            color: "transparent"
                            Text { id: zoomText; anchors.centerIn: parent; text: Math.round(window.zoomFactor * 100) + "%"; font.family: Design.font.mono; font.pixelSize: Design.s(10); color: window.colDim }
                        }
                        CtrlBtn { icon: "󰐕"; tip: "Zoom In"; onClicked: window.zoomFactor = Math.min(5.0, window.zoomFactor + 0.25) }
                        CtrlBtn { icon: "󰑐"; tip: "Reset View"; onClicked: { window.zoomFactor = 1.0; window.rotationAngle = 0; } }
                        CtrlBtn { icon: "󰑓"; tip: "Rotate 90°"; onClicked: window.rotationAngle = (window.rotationAngle + 90) % 360 }
                        CtrlBtn { icon: "󰸉"; tip: "Set Wallpaper"; onClicked: ViewBackend.setWallpaper() }
                        // Nothing to toggle in a folder of one.
                        CtrlBtn { visible: window.hasSiblings; icon: "󰋩"; tip: "Toggle Filmstrip"; active: window.showFilmstrip; onClicked: window.showFilmstrip = !window.showFilmstrip }
                    }
                }
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
                            source: ViewBackend.currentPath ? ("file://" + ViewBackend.currentPath) : ""
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                            cache: true
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
                            source: "file://" + modelData.path
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

    component CtrlBtn: Rectangle {
        id: cb
        property string icon: ""
        property string tip: ""
        property bool active: false
        signal clicked()

        width: Design.s(26); height: Design.s(26); radius: Design.s(5)
        color: cb.active ? window.colBlue : (cbArea.containsMouse ? Design.tint(Design.text, 0.12) : "transparent")
        border.color: cb.active ? "transparent" : window.colBorder
        border.width: 1

        Text {
            anchors.centerIn: parent
            text: cb.icon
            font.family: Design.font.mono
            font.pixelSize: Design.s(12)
            color: cb.active ? Design.accentText : (cbArea.containsMouse ? "#ffffff" : window.colFg)
        }

        MouseArea {
            id: cbArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: cb.clicked()
        }
    }
}
