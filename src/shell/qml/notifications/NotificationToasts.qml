import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import "../Ui"
import "../Services"

// =============================================================================
// Desktop Notification Toasts (Floating Popups)
// =============================================================================

PanelWindow {
    id: toastWindow
    color: "transparent"

    WlrLayershell.namespace: "qs-notifications"

    // Below the shell's own popups, above ordinary windows.
    //
    // Toasts were on the overlay layer, the same as the popup host — and
    // within a layer the surface created last is on top, which is this one.
    // So a notification arriving while the Control Center was open landed
    // across it. WlrLayer.Top still puts toasts above every application
    // window, which is the whole point of them, while a shell surface the
    // user has deliberately opened stays in front.
    WlrLayershell.layer: WlrLayer.Top
    
    exclusionMode: ExclusionMode.Ignore
    focusable: false
    
    // Toasts belong on the screen in use, not always the first one.
    screen: Screens.focused

    anchors.top: true
    anchors.right: true

    readonly property int topOffset: (Settings.barPosition === "bottom") ? Design.s(16) : Design.s(56)

    implicitWidth: Design.s(390)
    implicitHeight: toastColumn.implicitHeight + topOffset + Design.s(20)

    visible: Notifications.activeToasts.count > 0 && !Notifications.dnd
    onVisibleChanged: if (visible) Screens.refresh()

    Item {
        anchors.fill: parent
        anchors.topMargin: toastWindow.topOffset
        anchors.rightMargin: Design.s(16)
        anchors.bottomMargin: Design.s(16)
        anchors.leftMargin: Design.s(16)

        ColumnLayout {
            id: toastColumn
            width: parent.width
            spacing: Design.s(10)

        Repeater {
            model: Notifications.activeToasts

            delegate: Rectangle {
                id: toastCard
                required property var model
                required property int index

                Layout.fillWidth: true
                implicitHeight: cardContent.implicitHeight + Design.s(16)

                radius: Design.s(Design.radius.card)
                color: Design.ground
                border.color: model.urgency === 2 ? Design.red : Design.glassBorder
                border.width: model.urgency === 2 ? 2 : 1

                property bool isHovered: hoverArea.containsMouse
                property real progress: 1.0

                // Progress animation / timer
                NumberAnimation on progress {
                    id: dismissAnim
                    from: 1.0
                    to: 0.0
                    duration: Notifications.toastTimeoutMs
                    running: !toastCard.isHovered
                    onFinished: Notifications.dismissToast(toastCard.index)
                }

                MouseArea {
                    id: hoverArea
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: mouse => {
                        if (mouse.button === Qt.RightButton) {
                            Notifications.dismissToast(toastCard.index)
                        }
                    }
                }

                ColumnLayout {
                    id: cardContent
                    anchors.fill: parent
                    anchors.margins: Design.s(10)
                    spacing: Design.s(8)

                    // ── Header Row ───────────────────────────────────────────
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Design.s(8)

                        Rectangle {
                            Layout.preferredWidth: Design.s(28)
                            Layout.preferredHeight: Design.s(28)
                            radius: Design.s(6)
                            color: Design.surface

                            Image {
                                anchors.centerIn: parent
                                width: Design.s(18)
                                height: width
                                // Decoded at the size drawn, not the file's (a 4K picture is 33 MB of pixels).
                                sourceSize: Qt.size(128, 128)
                                source: toastCard.model.icon ? (toastCard.model.icon.startsWith("/") ? "file://" + toastCard.model.icon : toastCard.model.icon) : ""
                                visible: source.toString() !== ""
                                fillMode: Image.PreserveAspectFit
                            }

                            Icon {
                                anchors.centerIn: parent
                                visible: !toastCard.model.icon || toastCard.model.icon === ""
                                text: "\u{f009a}"
                                color: Design.sapphire
                                role: "caption"
                            }
                        }

                        Label {
                            text: toastCard.model.appName
                            weight: Design.weight.bold
                            role: "caption"
                            dim: true
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        Label {
                            text: toastCard.model.time
                            role: "caption"
                            dim: true
                        }

                        IconButton {
                            icon: "\u{f0156}"
                            role: "caption"
                            onClicked: Notifications.dismissToast(toastCard.index)
                        }
                    }

                    // ── Summary & Body ───────────────────────────────────────
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: Design.s(2)

                        Label {
                            text: toastCard.model.summary
                            weight: Design.weight.semibold
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }

                        Label {
                            visible: toastCard.model.body !== ""
                            text: toastCard.model.body
                            role: "caption"
                            dim: true
                            wrapMode: Text.WordWrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                        }
                    }

                    // ── Action Buttons ───────────────────────────────────────
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Design.s(6)
                        visible: toastCard.model.obj && toastCard.model.obj.actions && toastCard.model.obj.actions.length > 0

                        Repeater {
                            model: toastCard.model.obj ? (toastCard.model.obj.actions || []) : []

                            delegate: ActionButton {
                                required property var modelData
                                label: modelData.text || modelData.id || "Action"
                                onActivated: {
                                    if (typeof modelData.invoke === "function") {
                                        modelData.invoke();
                                    }
                                    Notifications.dismissToast(toastCard.index);
                                }
                            }
                        }
                    }

                    // ── Progress Bar ─────────────────────────────────────────
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Design.s(2)
                        radius: 1
                        color: Design.sunken

                        Rectangle {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: parent.width * toastCard.progress
                            radius: 1
                            color: toastCard.model.urgency === 2 ? Design.red : Design.accentAlt
                        }
                    }
                }
            }
        }
    }
}
}
