import QtQuick
import QtQuick.Layouts
import "Ui"

// The frame every device page shares, laid out as a desktop shows a
// connected device rather than a folder:
//
//   ┌────────────────────────────────────────────────────────────┐
//   │ [picture]  Name                                  [actions] │
//   │            model · capacity (free) · battery               │
//   │           ( General | Music | Playlists )                  │
//   ├────────────────────────────────────────────────────────────┤
//   │                     the tab's content                      │
//   ├────────────────────────────────────────────────────────────┤
//   │ ▕██ Music ██▏▕ Other ▏          free        ▏  [buttons]    │
//   └────────────────────────────────────────────────────────────┘
//
// The pages (FilesDevicePane, FilesPhonePane) fill in the parts.
Item {
    id: frame

    property string kind: "ipod"          // ipod | iphone | android — the picture
    property string tint: ""              // the iPod's colour ("Black", "Silver"…)
    property string name: ""
    property string subtitle: ""
    property bool renamable: false
    signal renameRequested()

    // [{id, label}]; one tab or none: no tab bar.
    property var tabs: []
    property string tab: ""
    signal tabClicked(string id)

    // The storage bar: [{label, bytes, color}] out of totalBytes; what is
    // left is free.
    property var segments: []
    property real totalBytes: 0
    property real freeBytes: 0
    // A passing message, in place of the legend; a quiet line where there
    // is no storage to show.
    property string note: ""
    property string hint: ""

    // A line above the storage bar while something runs: text and 0…1, or
    // a negative fraction for "busy, no percent".
    property string progressText: ""
    property real progress: -1
    signal stopRequested()
    property bool stoppable: false

    default property alias content: body.data
    property alias actions: actionRow.data
    property alias footer: footerRow.data

    function size(bytes) {
        const u = ["B", "KB", "MB", "GB", "TB"];
        let v = Number(bytes) || 0, i = 0;
        while (v >= 1000 && i < u.length - 1) { v /= 1000; i++; }
        return (i === 0 ? v.toFixed(0) : v.toFixed(v < 10 ? 1 : 0)) + " " + u[i];
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ── Header ──────────────────────────────────────────────────────────
        ColumnLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Design.s(Design.space.xl)
            Layout.rightMargin: Design.s(Design.space.xl)
            Layout.topMargin: Design.s(Design.space.xl)
            Layout.bottomMargin: Design.s(Design.space.md)
            spacing: Design.s(Design.space.lg)

            RowLayout {
                Layout.fillWidth: true
                spacing: Design.s(Design.space.lg)

                DevicePicture {
                    kind: frame.kind
                    tint: frame.tint
                    Layout.preferredWidth: Design.s(Design.size.tile)
                    Layout.preferredHeight: Design.s(Design.size.avatar)
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Design.s(Design.space.xs)
                    RowLayout {
                        spacing: Design.s(Design.space.xs)
                        Label {
                            text: frame.name
                            font.pixelSize: Design.s(Design.font.display)
                            weight: Design.weight.semibold
                            elide: Text.ElideRight
                            Layout.maximumWidth: Design.s(Design.width.menuMax)
                        }
                        Button {
                            variant: "ghost"
                            iconOnly: true
                            visible: frame.renamable
                            icon: "\u{f03eb}"; size: "sm"
                            tip: I18n.tr("Rename")
                            onClicked: frame.renameRequested()
                        }
                    }
                    Label {
                        Layout.fillWidth: true
                        text: frame.subtitle
                        dim: true
                        elide: Text.ElideRight
                    }
                }

                RowLayout {
                    id: actionRow
                    spacing: Design.s(Design.space.sm)
                }
            }

            // The device's tabs: Ui's segmented control, which this was a
            // hand-built copy of.
            SegmentedControl {
                visible: frame.tabs.length > 1
                Layout.alignment: Qt.AlignHCenter
                model: frame.tabs.map(t => ({ id: t.id, label: t.label }))
                current: frame.tab
                onPicked: id => frame.tabClicked(id)
            }
        }

        Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Design.line }

        // ── The tab ─────────────────────────────────────────────────────────
        Item {
            id: body
            Layout.fillWidth: true
            Layout.fillHeight: true
        }

        // ── Something running ───────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Design.s(Design.size.row)
            visible: frame.progressText !== ""
            color: Design.tint(Design.accent, 0.08)
            Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: Design.line }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Design.s(Design.space.xl)
                anchors.rightMargin: Design.s(Design.space.xl)
                spacing: Design.s(Design.space.md)
                Icon {
                    text: "\u{f0450}"
                    color: Design.accent
                    RotationAnimator on rotation { from: 0; to: 360; duration: 1200; loops: Animation.Infinite; running: frame.progressText !== "" }
                }
                Label { Layout.fillWidth: true; text: frame.progressText; elide: Text.ElideMiddle }
                Rectangle {
                    visible: frame.progress >= 0
                    Layout.preferredWidth: Design.s(Design.width.control)
                    Layout.preferredHeight: Design.s(Design.space.xs)
                    radius: height / 2
                    color: Design.tint(Design.text, 0.1)
                    Rectangle {
                        width: parent.width * Math.max(0.02, Math.min(1, frame.progress))
                        height: parent.height; radius: height / 2; color: Design.accent
                        Behavior on width { NumberAnimation { duration: Design.duration.fast } }
                    }
                }
                Button {
                    variant: "ghost"
                    iconOnly: true
                    visible: frame.stoppable
                    icon: "\u{f0156}"; size: "sm"; tip: I18n.tr("Stop")
                    onClicked: frame.stopRequested()
                }
            }
        }

        // ── Storage and the page's buttons ──────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Design.s(Design.size.stat)
            color: Design.sunken
            Rectangle { anchors.top: parent.top; width: parent.width; height: 1; color: Design.line }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Design.s(Design.space.xl)
                anchors.rightMargin: Design.s(Design.space.xl)
                spacing: Design.s(Design.space.lg)

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Design.s(Design.space.xs)
                    visible: frame.totalBytes > 0

                    // The bar: one block per kind, labelled inside when the
                    // block is wide enough, then what is free.
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: Design.s(Design.size.mini)
                        radius: Design.s(Design.radius.sm)
                        color: Design.tint(Design.text, 0.07)
                        border.color: Design.line
                        border.width: Design.border
                        clip: true
                        Row {
                            anchors.fill: parent
                            anchors.margins: 1
                            spacing: 1
                            Repeater {
                                model: frame.segments.filter(s => s.bytes > 0)
                                delegate: Rectangle {
                                    id: block
                                    required property var modelData
                                    width: Math.max(Design.s(Design.space.xxs), (parent.width) * modelData.bytes / Math.max(1, frame.totalBytes))
                                    height: parent.height
                                    color: modelData.color
                                    Text {
                                        anchors.centerIn: parent
                                        visible: implicitWidth + Design.s(Design.space.md) < block.width
                                        text: block.modelData.label
                                        font.family: Design.font.sans
                                        font.pixelSize: Design.s(Design.font.caption)
                                        font.weight: Design.weight.semibold
                                        color: Design.readableOn(block.modelData.color)
                                    }
                                }
                            }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Design.s(Design.space.lg)
                        Label {
                            visible: frame.note !== ""
                            Layout.fillWidth: true
                            text: frame.note
                            role: "caption"
                            color: Design.accent
                            elide: Text.ElideRight
                        }
                        Repeater {
                            model: frame.note !== "" ? [] : frame.segments.filter(s => s.bytes > 0)
                            delegate: RowLayout {
                                required property var modelData
                                spacing: Design.s(Design.space.xs)
                                Rectangle { width: Design.s(Design.space.sm); height: width; radius: width / 2; color: modelData.color }
                                Label { text: modelData.label + "  " + frame.size(modelData.bytes); role: "caption"; dim: true }
                            }
                        }
                        Item { Layout.fillWidth: true; visible: frame.note === "" }
                        Label {
                            role: "caption"; dim: true
                            text: I18n.tr("%1 free of %2", frame.size(frame.freeBytes), frame.size(frame.totalBytes))
                        }
                    }
                }
                Label {
                    visible: frame.totalBytes <= 0
                    Layout.fillWidth: true
                    text: frame.note || frame.hint
                    role: "caption"
                    color: frame.note ? Design.accent : Design.textDim
                    elide: Text.ElideRight
                }

                RowLayout {
                    id: footerRow
                    spacing: Design.s(Design.space.sm)
                }
            }
        }
    }

    // ── The device, drawn ───────────────────────────────────────────────────
    component DevicePicture: Item {
        id: pic
        property string kind: "ipod"
        property string tint: ""
        readonly property bool light: /silver|white|pink|blue|green|yellow|red|gold/i.test(pic.tint)
        // A schematic of the device in the theme's colours: a light case is a
        // lighter shade of the text colour, a dark one a darker. It was drawn
        // in fixed greys and two gradients, the only ones left in the apps.
        readonly property color body: pic.kind === "ipod"
            ? Design.tint(Design.text, pic.light ? 0.30 : 0.10)
            : Design.tint(Design.text, 0.14)

        Rectangle {
            id: shell
            anchors.centerIn: parent
            width: pic.kind === "ipod" ? parent.width : parent.width * 0.86
            height: parent.height
            radius: pic.kind === "ipod" ? Design.s(Design.radius.ctl) : Design.s(Design.space.md)
            color: pic.body
            border.color: Design.tint(Design.text, 0.22)
            border.width: Design.border

            // iPod: the screen and the wheel.
            Rectangle {
                visible: pic.kind === "ipod"
                x: Design.s(Design.space.xs); y: Design.s(Design.space.sm)
                width: parent.width - Design.s(Design.space.md); height: parent.height * 0.42
                radius: Design.s(Design.radius.sm)
                color: Design.tint(Design.accent, 0.55)
            }
            Rectangle {
                visible: pic.kind === "ipod"
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height * 0.52
                width: parent.width * 0.68; height: width; radius: width / 2
                color: Design.tint(Design.text, pic.light ? 0.45 : 0.20)
                border.color: Design.tint(Design.text, 0.18)
                border.width: Design.border
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width * 0.36; height: width; radius: width / 2
                    color: pic.body
                    border.color: Design.tint(Design.text, 0.12)
                    border.width: Design.border
                }
            }

            // Phone: the screen, and its notch or camera.
            Rectangle {
                visible: pic.kind !== "ipod"
                anchors.fill: parent
                anchors.margins: Design.s(Design.space.xxs)
                radius: Design.s(Design.radius.ctl)
                color: Design.tint(pic.kind === "iphone" ? Design.blue : Design.green, 0.55)
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: Design.s(Design.space.xs)
                    width: pic.kind === "iphone" ? parent.width * 0.38 : Design.s(Design.space.xs)
                    height: Design.s(Design.space.xs); radius: height / 2
                    color: Design.ground
                }
            }
        }
    }
}
