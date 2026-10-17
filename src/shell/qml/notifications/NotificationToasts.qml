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
    
    // Toasts belong on the screen in use, not always the first one — unless
    // Settings → Displays sends them all to the main display.
    screen: Settings.notificationsOnMain ? Screens.primary : Screens.focused

    anchors.top: true
    anchors.right: true

    readonly property int topOffset: (Settings.barPosition === "bottom") ? Design.s(Design.space.lg) : Design.s(Design.size.tile)

    implicitWidth: Design.s(Design.width.dialog)
    implicitHeight: toastColumn.implicitHeight + topOffset + Design.s(Design.size.mini)

    // Only toasts that got through are queued (Services/Notifications): a focus
    // mode lets some apps through, so it cannot hide the layer.
    visible: Notifications.activeToasts.count > 0
    onVisibleChanged: if (visible) Screens.refresh()

    Item {
        anchors.fill: parent
        anchors.topMargin: toastWindow.topOffset
        anchors.rightMargin: Design.s(Design.space.lg)
        anchors.bottomMargin: Design.s(Design.space.lg)
        anchors.leftMargin: Design.s(Design.space.lg)

        ColumnLayout {
            id: toastColumn
            width: parent.width
            spacing: Design.s(Design.space.sm)

        Repeater {
            model: Notifications.activeToasts

            delegate: Rectangle {
                id: toastCard
                required property var model
                required property int index

                Layout.fillWidth: true
                implicitHeight: cardContent.implicitHeight + Design.s(Design.space.lg)

                radius: Design.s(Design.radius.card)
                color: Design.ground
                // One quiet edge for every toast. Critical ones had a 2px red
                // ring and a red timer bar, which read as an error frame
                // round anything urgent (a low battery, a failed call).
                border.color: Design.glassBorder
                border.width: 1

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
                    anchors.margins: Design.s(Design.space.sm)
                    spacing: Design.s(Design.space.sm)

                    // ── Header Row ───────────────────────────────────────────
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Design.s(Design.space.sm)

                        Rectangle {
                            Layout.preferredWidth: Design.s(Design.size.sm)
                            Layout.preferredHeight: Design.s(Design.size.sm)
                            radius: Design.s(Design.radius.sm)
                            color: Design.glassCard

                            Image {
                                id: toastIcon
                                anchors.centerIn: parent
                                width: Design.s(Design.size.micro)
                                height: width
                                // Decoded at the size drawn, not the file's (a 4K picture is 33 MB of pixels).
                                sourceSize: Qt.size(128, 128)
                                source: toastCard.model.icon || ""
                                visible: status === Image.Ready
                                fillMode: Image.PreserveAspectFit
                            }

                            Icon {
                                anchors.centerIn: parent
                                visible: !toastIcon.visible
                                text: "\u{f009a}"
                                color: Design.textDim
                                role: "caption"
                            }
                        }

                        Label {
                            text: toastCard.model.appName
                            weight: Design.weight.semibold
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
                        spacing: Design.s(Design.space.xxs)

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
                        spacing: Design.s(Design.space.xs)
                        visible: toastCard.model.obj && toastCard.model.obj.actions && toastCard.model.obj.actions.length > 0

                        Repeater {
                            model: toastCard.model.obj ? (toastCard.model.obj.actions || []) : []

                            delegate: Button {
                                required property var modelData
                                label: modelData.text || modelData.id || I18n.tr("Action")
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
                        Layout.preferredHeight: Design.s(Design.space.xxs)
                        radius: 1
                        color: Design.well

                        Rectangle {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: parent.width * toastCard.progress
                            radius: 1
                            color: Design.accentAlt
                        }
                    }
                }
            }
        }
    }
}
}
