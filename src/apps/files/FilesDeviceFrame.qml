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
                    Layout.preferredWidth: Design.s(64)
                    Layout.preferredHeight: Design.s(100)
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Design.s(Design.space.xs)
                    RowLayout {
                        spacing: Design.s(Design.space.xs)
                        Label {
                            text: frame.name
                            font.pixelSize: Design.s(26)
                            weight: Design.weight.bold
                            elide: Text.ElideRight
                            Layout.maximumWidth: Design.s(520)
                        }
                        BarButton {
                            visible: frame.renamable
                            glyph: "\u{f03eb}"; small: true
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

            // Segmented tabs, centred.
            Rectangle {
                visible: frame.tabs.length > 1
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: segRow.implicitWidth + Design.s(4)
                implicitHeight: Design.s(30)
                radius: Design.s(8)
                color: Design.tint(Design.text, 0.06)
                border.color: Design.line
                border.width: 1

                Row {
                    id: segRow
                    anchors.centerIn: parent
                    spacing: 0
                    Repeater {
                        model: frame.tabs
                        delegate: Rectangle {
                            id: seg
                            required property var modelData
                            required property int index
                            readonly property bool on: frame.tab === modelData.id
                            width: segLabel.implicitWidth + Design.s(28)
                            height: Design.s(26)
                            radius: Design.s(6)
                            color: seg.on ? Design.raised
                                 : segMa.containsMouse ? Design.tint(Design.text, 0.05) : "transparent"
                            border.color: seg.on ? Design.line : "transparent"
                            border.width: 1
                            // A hairline between two unselected neighbours.
                            Rectangle {
                                visible: seg.index > 0 && !seg.on && frame.tabs[seg.index - 1].id !== frame.tab
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                width: 1; height: parent.height * 0.5
                                color: Design.line
                            }
                            Text {
                                id: segLabel
                                anchors.centerIn: parent
                                text: seg.modelData.label
                                font.family: Design.font.sans
                                font.pixelSize: Design.s(Design.font.body)
                                font.weight: seg.on ? Design.weight.semibold : Design.weight.regular
                                color: seg.on ? Design.text : Design.textDim
                            }
                            MouseArea {
                                id: segMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: frame.tabClicked(seg.modelData.id)
                            }
                        }
                    }
                }
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
            Layout.preferredHeight: Design.s(40)
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
                    Layout.preferredWidth: Design.s(220)
                    Layout.preferredHeight: Design.s(6)
                    radius: height / 2
                    color: Design.tint(Design.text, 0.1)
                    Rectangle {
                        width: parent.width * Math.max(0.02, Math.min(1, frame.progress))
                        height: parent.height; radius: height / 2; color: Design.accent
                        Behavior on width { NumberAnimation { duration: Design.duration.fast } }
                    }
                }
                BarButton {
                    visible: frame.stoppable
                    glyph: "\u{f0156}"; small: true; tip: I18n.tr("Stop")
                    onClicked: frame.stopRequested()
                }
            }
        }

        // ── Storage and the page's buttons ──────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Design.s(68)
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
                        Layout.preferredHeight: Design.s(20)
                        radius: Design.s(5)
                        color: Design.tint(Design.text, 0.07)
                        border.color: Design.line
                        border.width: 1
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
                                    width: Math.max(Design.s(3), (parent.width) * modelData.bytes / Math.max(1, frame.totalBytes))
                                    height: parent.height
                                    color: modelData.color
                                    Text {
                                        anchors.centerIn: parent
                                        visible: implicitWidth + Design.s(12) < block.width
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
                                Rectangle { width: Design.s(8); height: width; radius: width / 2; color: modelData.color }
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
        readonly property color body: pic.kind === "ipod"
            ? (pic.light ? "#e9eaec" : "#2b2d31")
            : Design.tint(Design.text, 0.14)

        Rectangle {
            id: shell
            anchors.centerIn: parent
            width: pic.kind === "ipod" ? parent.width : parent.width * 0.86
            height: parent.height
            radius: pic.kind === "ipod" ? Design.s(9) : Design.s(13)
            color: pic.body
            border.color: Design.tint(Design.text, 0.22)
            border.width: 1

            // iPod: the screen and the wheel.
            Rectangle {
                visible: pic.kind === "ipod"
                x: Design.s(6); y: Design.s(7)
                width: parent.width - Design.s(12); height: parent.height * 0.42
                radius: Design.s(3)
                gradient: Gradient {
                    GradientStop { position: 0; color: Qt.lighter(Design.accent, 1.25) }
                    GradientStop { position: 1; color: Qt.darker(Design.accent, 1.4) }
                }
            }
            Rectangle {
                visible: pic.kind === "ipod"
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.height * 0.52
                width: parent.width * 0.68; height: width; radius: width / 2
                color: pic.light ? "#ffffff" : "#3a3c41"
                border.color: Design.tint(Design.text, 0.18)
                border.width: 1
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width * 0.36; height: width; radius: width / 2
                    color: pic.body
                    border.color: Design.tint(Design.text, 0.12)
                    border.width: 1
                }
            }

            // Phone: the screen, and its notch or camera.
            Rectangle {
                visible: pic.kind !== "ipod"
                anchors.fill: parent
                anchors.margins: Design.s(3)
                radius: Design.s(10)
                gradient: Gradient {
                    GradientStop { position: 0; color: pic.kind === "iphone" ? Qt.lighter(Design.blue, 1.15) : Qt.lighter(Design.green, 1.1) }
                    GradientStop { position: 1; color: pic.kind === "iphone" ? Qt.darker(Design.mauve, 1.3) : Qt.darker(Design.teal, 1.4) }
                }
                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: Design.s(4)
                    width: pic.kind === "iphone" ? parent.width * 0.38 : Design.s(5)
                    height: Design.s(5); radius: height / 2
                    color: "#101114"
                }
            }
        }
    }
}
