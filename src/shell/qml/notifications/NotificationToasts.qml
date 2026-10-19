import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import "../Ui"
import "../Services"

// =============================================================================
// Notification banners, top right.
//
// Who it is from first: the sender's picture (with the app's icon on its
// corner) or the app's icon, the title, two or three lines, "now" or "5 min"
// and the app's name. Nothing else until the pointer is on it: then the
// close button on its corner and the app's actions. Several from one app and
// sender (a chat going on) are one banner with the newest on it and the rest
// as edges under it (Services/Notifications stacks them).
//
// What a notification brings is used: a messenger's reply is typed right
// here; a picture (a screenshot) is shown as one, with its actions; something
// urgent (Critical) is marked in the warning colour and stays until it is
// dismissed. A click on a banner does what the app means by it (its default
// action); right click, or the close button, dismisses it.
//
// No countdown bar: a banner leaves after a few seconds unless it is pointed
// at or being answered.
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
    // The keyboard only while a reply is being typed.
    property int replying: 0
    focusable: toastWindow.replying > 0

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
            spacing: Design.s(Design.space.md)

            Repeater {
                model: Notifications.activeToasts

                delegate: Item {
                    id: toast
                    required property var model
                    required property int index

                    readonly property var actions: (toast.model.obj && toast.model.obj.actions
                        ? toast.model.obj.actions : []).filter(a => a.identifier !== "default")
                    readonly property bool canReply: !!(toast.model.obj && toast.model.obj.hasInlineReply)
                    readonly property bool critical: !!toast.model.critical
                    readonly property bool hovered: hover.hovered
                    // The others of the stack, as edges under it.
                    readonly property int under: Math.min(2, (toast.model.count || 1) - 1)

                    Layout.fillWidth: true
                    implicitHeight: card.implicitHeight + toast.under * Design.s(Design.space.xs)

                    function dismiss() { Notifications.dismissToast(toast.index); }
                    // Gone while its reply had the keyboard: give it back.
                    Component.onDestruction: if (reply.focused) toastWindow.replying = Math.max(0, toastWindow.replying - 1)

                    // Leaves after a while, unless pointed at, answered or urgent;
                    // a newer one stacked on it starts the time again.
                    Timer {
                        id: life
                        interval: Notifications.toastTimeoutMs
                        running: !toast.critical && !toast.hovered && !reply.focused
                        onTriggered: toast.dismiss()
                    }
                    property double stamp: toast.model.ts || 0
                    onStampChanged: life.restart()

                    HoverHandler { id: hover }

                    // ── The stack's edges ────────────────────────────────────
                    Item {
                        y: card.implicitHeight
                        width: parent.width
                        height: toast.under * Design.s(Design.space.xs)
                        clip: true
                        Repeater {
                            model: toast.under
                            Surface {
                                kind: "glass"
                                border.width: 0
                                required property int index
                                x: Design.s(Design.space.md) * (index + 1)
                                width: card.width - 2 * x
                                y: -Design.s(Design.size.xs) + Design.s(Design.space.xs) * (index + 1)
                                height: Design.s(Design.size.xs)
                                radius: Design.s(Design.radius.panel)
                                opacity: 0.8 - index * 0.25
                            }
                        }
                    }

                    // ── The banner ───────────────────────────────────────────
                    Surface {
                        kind: "glass"
                        id: card
                        width: parent.width
                        implicitHeight: content.implicitHeight + Design.s(Design.space.md) * 2
                        radius: Design.s(Design.radius.panel)
                        border.color: toast.critical ? Design.tint(Design.warn, 0.6) : "transparent"
                        border.width: toast.critical ? Design.border : 0
                        // Urgent: the warning colour over the glass, not instead of it.
                        Box {
                            anchors.fill: parent
                            visible: toast.critical
                            radius: parent.radius
                            color: Design.warnSoft
                        }

                        // A click is the app's own action for it; right click dismisses.
                        PointerArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            cursorShape: Qt.PointingHandCursor
                            onClicked: mouse => {
                                if (mouse.button === Qt.RightButton || Notifications.activate(toast.model))
                                    toast.dismiss();
                            }
                        }

                        ColumnLayout {
                            id: content
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: Design.s(Design.space.md)
                            spacing: Design.s(Design.space.sm)

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: Design.s(Design.space.md)

                                NotificationIcon {
                                    id: icon
                                    Layout.alignment: Qt.AlignTop
                                    image: toast.model.image || ""
                                    appIcon: toast.model.appIcon || toast.model.icon || ""
                                    critical: toast.critical
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: Design.s(Design.space.xxs)
                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Design.s(Design.space.sm)
                                        Label {
                                            Layout.fillWidth: true
                                            text: toast.model.summary
                                            weight: Design.weight.semibold
                                            elide: Text.ElideRight
                                        }
                                        Label {
                                            text: toast.model.appName + " · " + Notifications.relTime(toast.model.ts)
                                            role: "caption"
                                            dim: true
                                        }
                                    }
                                    Label {
                                        Layout.fillWidth: true
                                        visible: toast.model.body !== ""
                                        text: toast.model.body
                                        color: Design.textDim
                                        wrapMode: Text.WordWrap
                                        maximumLineCount: 3
                                        elide: Text.ElideRight
                                    }
                                    Label {
                                        visible: (toast.model.count || 1) > 1
                                        text: I18n.trn("%1 more from %2", "%1 more from %2", toast.model.count - 1, toast.model.appName)
                                        role: "caption"
                                        color: Design.textFaint
                                    }
                                }
                            }

                            // A picture sent with it, as a picture.
                            Picture {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Math.min(width * 9 / 16, Design.s(Design.size.thumb) * 1.5)
                                visible: icon.isPicture
                                source: icon.isPicture ? toast.model.image : ""
                                sourceSize: Qt.size(640, 360)
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                            }

                            ReplyField {
                                id: reply
                                Layout.fillWidth: true
                                visible: toast.canReply
                                item: toast.model
                                onSent: toast.dismiss()
                                onFocusedChanged: toastWindow.replying += focused ? 1 : -1
                            }

                            // The app's actions: while pointed at, or always for
                            // a picture or something urgent.
                            RowLayout {
                                Layout.fillWidth: true
                                visible: toast.actions.length > 0 && (toast.hovered || toast.critical || icon.isPicture)
                                spacing: Design.s(Design.space.xs)
                                Repeater {
                                    model: toast.actions
                                    delegate: Button {
                                        required property var modelData
                                        Layout.fillWidth: true
                                        size: "sm"
                                        label: modelData.text || I18n.tr("Open")
                                        onActivated: {
                                            if (typeof modelData.invoke === "function") modelData.invoke();
                                            toast.dismiss();
                                        }
                                    }
                                }
                            }
                        }

                        // Close, on its corner, while pointed at.
                        Surface {
                            kind: "glass"
                            visible: toast.hovered
                            width: Design.s(Design.size.mini)
                            height: width
                            radius: width / 2
                            x: -width / 3
                            y: -width / 3
                            Icon { anchors.centerIn: parent; text: "\u{f0156}"; role: "caption"; color: Design.text }
                            PointerArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: toast.dismiss()
                            }
                        }
                    }
                }
            }
        }
    }
}
