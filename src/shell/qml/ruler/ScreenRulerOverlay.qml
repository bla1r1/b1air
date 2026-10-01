import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import B1air.Daemon
import "../Ui"
import "../Services"

// =============================================================================
// Screen Ruler & Pixel Inspector HUD (Super + Shift + M)
// =============================================================================

PopupShell {
    id: root

    padding: Design.s(Design.space.md)

    property int startX: 0
    property int startY: 0
    property int curX: 0
    property int curY: 0
    property bool isDragging: false

    readonly property int measureW: Math.abs(curX - startX)
    readonly property int measureH: Math.abs(curY - startY)
    readonly property int measureX: Math.min(startX, curX)
    readonly property int measureY: Math.min(startY, curY)
    readonly property int diagonal: Math.round(Math.sqrt(measureW * measureW + measureH * measureH))
    readonly property string aspect: measureH > 0 ? (measureW / measureH).toFixed(2) + ":1" : "N/A"

    function copyDimensions() {
        Quickshell.execDetached(["wl-copy", measureW + "x" + measureH]);
        Osd.show("edit-copy", measureW + " × " + measureH + " px copied", "Screen ruler");
        root.close();
    }

    focus: true
    Keys.onEscapePressed: root.close()
    Keys.onDownPressed: copyDimensions()
    Keys.onReturnPressed: copyDimensions()

    ColumnLayout {
        anchors.fill: parent
        spacing: Design.s(Design.space.md)

        // ── Header ────────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.sm)

            Icon {
                text: "\u{f046d}" // ruler
                role: "subhead"
                color: Design.accent
            }

            Label {
                text: "Screen Ruler & Dimension Inspector"
                role: "subhead"
                weight: Design.weight.bold
            }

            Item { Layout.fillWidth: true }

            Badge {
                text: "Drag anywhere below to measure"
                tone: Design.accent
            }
        }

        // ── Interactive Measurement Canvas ────────────────────────────────────
        Rectangle {
            id: canvas
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Design.s(Design.radius.card)
            color: Design.sunken
            border.color: Design.glassBorder
            border.width: 1
            clip: true

            // Grid Lines Pattern
            Repeater {
                model: Math.floor(canvas.width / 50)
                Rectangle {
                    x: index * 50
                    y: 0
                    width: 1
                    height: canvas.height
                    color: Design.veil
                }
            }
            Repeater {
                model: Math.floor(canvas.height / 50)
                Rectangle {
                    x: 0
                    y: index * 50
                    width: canvas.width
                    height: 1
                    color: Design.veil
                }
            }

            // Drawn Measurement Box
            Rectangle {
                visible: root.measureW > 0 && root.measureH > 0
                x: root.measureX
                y: root.measureY
                width: root.measureW
                height: root.measureH
                color: Design.tint(Design.accent, 0.25)
                border.color: Design.accent
                border.width: 2

                Label {
                    anchors.centerIn: parent
                    text: root.measureW + " × " + root.measureH + " px"
                    role: "body"
                    weight: Design.weight.bold
                    color: Design.accent
                }
            }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.CrossCursor

                onPressed: mouse => {
                    root.startX = mouse.x;
                    root.startY = mouse.y;
                    root.curX = mouse.x;
                    root.curY = mouse.y;
                    root.isDragging = true;
                }

                onPositionChanged: mouse => {
                    if (root.isDragging) {
                        root.curX = mouse.x;
                        root.curY = mouse.y;
                    }
                }

                onReleased: {
                    root.isDragging = false;
                }
            }
        }

        // ── Info Bar ──────────────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.lg)

            RowLayout {
                spacing: Design.s(Design.space.xs)
                Label { text: "Width:"; role: "caption"; dim: true }
                Label { text: root.measureW + " px"; role: "body"; weight: Design.weight.bold }
            }

            RowLayout {
                spacing: Design.s(Design.space.xs)
                Label { text: "Height:"; role: "caption"; dim: true }
                Label { text: root.measureH + " px"; role: "body"; weight: Design.weight.bold }
            }

            RowLayout {
                spacing: Design.s(Design.space.xs)
                Label { text: "Diagonal:"; role: "caption"; dim: true }
                Label { text: root.diagonal + " px"; role: "body"; weight: Design.weight.bold }
            }

            RowLayout {
                spacing: Design.s(Design.space.xs)
                Label { text: "Aspect:"; role: "caption"; dim: true }
                Label { text: root.aspect; role: "body"; weight: Design.weight.bold }
            }

            Item { Layout.fillWidth: true }

            ActionButton {
                icon: "\u{f0c5}"
                label: "Copy Dimensions"
                onActivated: root.copyDimensions()
            }
        }
    }
}
