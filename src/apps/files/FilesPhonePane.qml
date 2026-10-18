import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as C
import "Ui"

// An iPhone or an Android phone, shown as a device (FilesDeviceFrame): what
// it is, its battery and storage, and what can be done with it from here —
// back it up, import its photos, open the files its apps share.
//
// Devices (devices.cpp) does the work: libimobiledevice for iPhones, gvfs
// (MTP) and adb for Android.
Item {
    id: pane

    property var device: ({})
    readonly property string id: pane.device.id || ""
    readonly property bool iphone: pane.device.kind === "iphone"
    readonly property string state: pane.device.state || "ready"
    readonly property bool ready: pane.state === "ready"
    readonly property var task: Devices.tasks[pane.id] || null
    property string statusNote: ""
    property string tab: "general"          // general | photos | files
    signal note(string text)
    signal openFolder(string path)

    // ── The apps that share files (iPhone) ──────────────────────────────────
    property var apps: []
    property bool appsLoading: false
    function loadApps() {
        if (!pane.iphone || !pane.ready || pane.appsLoading) return;
        pane.appsLoading = true;
        Devices.listApps(pane.id);
    }
    onReadyChanged: loadApps()
    Component.onCompleted: loadApps()

    Connections {
        target: Devices
        function onMounted(id, path) { if (id === pane.id) pane.openFolder(path); }
        function onAppsListed(id, apps) { if (id === pane.id) { pane.apps = apps; pane.appsLoading = false; } }
        function onFinished(id, op, ok, message, result) {
            if (id !== pane.id) return;
            if (!ok) {
                pane.note(op === "browse" ? I18n.tr("Could not open the phone: %1", message)
                        : op === "pair" ? I18n.tr("Could not pair: %1", message)
                        : I18n.tr("Could not finish: %1", message));
                return;
            }
            if (op === "import") pane.note(I18n.tr("Photos imported to %1", result.dir));
            else if (op === "backup") pane.note(I18n.tr("Backed up to %1", result.dir));
            else if (op === "eject") pane.note(I18n.tr("It is safe to disconnect “%1”", pane.device.name));
        }
    }

    readonly property string battery: (pane.device.battery ?? -1) < 0 ? ""
        : pane.device.charging ? I18n.tr("%1%, charging", pane.device.battery)
        : I18n.tr("%1%", pane.device.battery)

    FilesDeviceFrame {
        id: frame
        anchors.fill: parent
        kind: pane.iphone ? "iphone" : "android"
        name: pane.device.name || (pane.iphone ? "iPhone" : "Android")
        subtitle: [pane.device.model,
                   (pane.device.total_bytes || 0) > 0
                       ? I18n.tr("%1 (%2 free)", frame.size(pane.device.total_bytes), frame.size(pane.device.free_bytes)) : "",
                   pane.battery ? I18n.tr("Battery %1", pane.battery) : ""].filter(s => !!s).join("  ·  ")

        tabs: pane.ready ? [{ id: "general", label: I18n.tr("General") },
                            { id: "photos", label: I18n.tr("Photos") },
                            { id: "files", label: I18n.tr("Files") }] : []
        tab: pane.tab
        onTabClicked: id => pane.tab = id

        segments: [{ label: I18n.tr("Used"), bytes: Math.max(0, (pane.device.total_bytes || 0) - (pane.device.free_bytes || 0)), color: Design.accent }]
        totalBytes: pane.device.total_bytes || 0
        freeBytes: pane.device.free_bytes || 0
        note: pane.statusNote
        hint: pane.iphone ? I18n.tr("Connected by USB") : I18n.tr("Connected by USB · file transfer")

        progressText: !pane.task ? ""
            : pane.task.op === "backup" ? I18n.tr("Backing up — keep the iPhone connected")
            : I18n.tr("Importing photos and videos…")
        progress: pane.task && pane.task.percent >= 0 ? pane.task.percent / 100 : -1
        stoppable: !!pane.task
        onStopRequested: Devices.cancelTask(pane.id)

        actions: [
            Chip {
                visible: pane.state === "trust"
                active: true
                icon: "\u{f0565}"
                label: I18n.tr("Trust")
                onClicked: Devices.pair(pane.id)
            },
            Button {
                variant: "secondary"
                icon: "\u{f01ea}"
                label: I18n.tr("Eject")
                enabled: !pane.task
                onClicked: Devices.eject(pane.id)
            }
        ]
        footer: [
            Button {
                variant: (!pane.iphone) ? "primary" : "secondary"
                visible: pane.ready
                icon: "\u{f01da}"
                label: I18n.tr("Import Photos")
                enabled: !pane.task
                onClicked: Devices.importPhotos(pane.id)
            },
            Button {
                variant: "primary"
                visible: pane.ready && pane.iphone
                icon: "\u{f006f}"
                label: I18n.tr("Back Up Now")
                enabled: !pane.task
                onClicked: Devices.backup(pane.id)
            }
        ]

        // ── Before it trusts this computer ──────────────────────────────────
        ColumnLayout {
            visible: !pane.ready
            anchors.centerIn: parent
            width: Math.min(parent.width - Design.s(Design.size.art), Design.s(Design.width.menuMax))
            spacing: Design.s(Design.space.md)
            Text {
                Layout.alignment: Qt.AlignHCenter
                text: pane.state === "locked" ? "\u{f033e}" : pane.state === "connecting" ? "\u{f0450}" : "\u{f0565}"
                font.family: Design.font.icon
                font.pixelSize: Design.s(Design.font.hero)
                color: Design.textFaint
            }
            Label {
                Layout.alignment: Qt.AlignHCenter
                role: "subhead"; weight: Design.weight.semibold
                text: pane.state === "locked" ? I18n.tr("Unlock your iPhone")
                    : pane.state === "pending" ? I18n.tr("Tap “Trust” on your iPhone")
                    : pane.state === "connecting" ? I18n.tr("Connecting…")
                    : I18n.tr("Trust this computer?")
            }
            Label {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                dim: true
                text: pane.state === "locked" ? I18n.tr("It answers only while unlocked. Unlock it, and it will show up here.")
                    : pane.state === "pending" ? I18n.tr("Your iPhone asks whether to trust this computer. Tap Trust and enter its passcode.")
                    : pane.state === "connecting" ? ""
                    : I18n.tr("Before its photos, files and backups can be reached, the iPhone has to trust this computer. Click Trust, then answer on the iPhone.")
            }
        }

        // ── General ─────────────────────────────────────────────────────────
        Page {
            visible: pane.ready && pane.tab === "general"
            FilesDeviceRow {
                label: I18n.tr("Software")
                Label { text: pane.device.os ? (pane.iphone ? "iOS " : "Android ") + pane.device.os : I18n.tr("Unknown") }
                Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    dim: true
                    text: pane.iphone ? I18n.tr("The iPhone updates itself, in Settings → General → Software Update.")
                        : pane.device.os ? I18n.tr("The phone updates itself, in its own settings.")
                        : I18n.tr("Its version and battery show when USB debugging is on (Developer options) and adb is installed.")
                }
            }
            Divider {}
            FilesDeviceRow {
                visible: pane.iphone
                label: I18n.tr("Backups")
                Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: I18n.tr("Everything on the iPhone, backed up to this computer, in %1",
                                  (pane.device.backupDir || "~/Backups").replace(FilesBackend.homePath, "~"))
                }
                Label {
                    dim: true
                    text: pane.device.lastBackup
                        ? I18n.tr("Last backup to this computer: %1", I18n.date(new Date(pane.device.lastBackup), "d MMMM yyyy, HH:mm"))
                        : I18n.tr("Never backed up to this computer")
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Design.s(Design.space.sm)
                    Item { Layout.fillWidth: true }
                    Button {
                        variant: "secondary"
                        visible: !!pane.device.lastBackup
                        label: I18n.tr("Show Backups")
                        onClicked: pane.openFolder(pane.device.backupDir)
                    }
                    Button {
                        variant: "secondary"
                        label: I18n.tr("Back Up Now")
                        enabled: !pane.task
                        onClicked: Devices.backup(pane.id)
                    }
                }
            }
            Divider { visible: pane.iphone }
            FilesDeviceRow {
                label: I18n.tr("About")
                GridLayout {
                    columns: 2
                    columnSpacing: Design.s(Design.space.lg)
                    rowSpacing: Design.s(Design.space.xs)
                    Label { text: I18n.tr("Model"); dim: true }
                    Label { text: [pane.device.model, pane.device.productType].filter((s, i, a) => !!s && a.indexOf(s) === i).join(" · ") }
                    Label { text: I18n.tr("Battery"); dim: true; visible: !!pane.battery }
                    Label { text: pane.battery; visible: !!pane.battery }
                    Label { text: I18n.tr("Serial number"); dim: true; visible: !!pane.device.serial }
                    Label { text: pane.device.serial || ""; visible: !!pane.device.serial; font.family: Design.font.mono }
                    Label { text: I18n.tr("Phone number"); dim: true; visible: !!pane.device.phoneNumber }
                    Label { text: pane.device.phoneNumber || ""; visible: !!pane.device.phoneNumber }
                }
            }
        }

        // ── Photos ──────────────────────────────────────────────────────────
        Page {
            visible: pane.ready && pane.tab === "photos"
            FilesDeviceRow {
                label: I18n.tr("Import")
                Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    text: I18n.tr("Photos and videos are copied to Pictures/%1. What was imported before is skipped, so importing again adds only the new ones.", pane.device.name || "")
                }
                Label {
                    visible: pane.iphone
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    dim: true
                    text: I18n.tr("An iPhone takes photos as HEIC; they open here like any other picture.")
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Design.s(Design.space.sm)
                    Item { Layout.fillWidth: true }
                    Button { variant: "secondary"; label: I18n.tr("Show Imported"); onClicked: pane.openFolder(FilesBackend.homePath + "/Pictures/" + (pane.device.name || "")) }
                    Button { variant: "secondary"; label: I18n.tr("Import Photos"); enabled: !pane.task; onClicked: Devices.importPhotos(pane.id) }
                }
            }
            Divider {}
            FilesDeviceRow {
                label: I18n.tr("On the phone")
                Label {
                    Layout.fillWidth: true
                    wrapMode: Text.WordWrap
                    dim: true
                    text: I18n.tr("Its camera folder, as it is: to pick a few by hand, or copy some back.")
                }
                RowLayout {
                    Layout.fillWidth: true
                    spacing: Design.s(Design.space.sm)
                    Item { Layout.fillWidth: true }
                    Button { variant: "secondary"; label: I18n.tr("Browse"); onClicked: Devices.browse(pane.id, "media") }
                }
            }
        }

        // ── Files ───────────────────────────────────────────────────────────
        Page {
            visible: pane.ready && pane.tab === "files"
            Label {
                Layout.fillWidth: true
                wrapMode: Text.WordWrap
                dim: true
                text: pane.iphone ? I18n.tr("Apps on the iPhone that share files. Open one to copy files to it or from it.")
                                  : I18n.tr("The phone's storage, as folders.")
            }
            AppState {
                Layout.fillWidth: true
                // A column that sizes to its content has no height to fill;
                // this keeps the message clear of the paragraph above it.
                Layout.preferredHeight: Design.s(Design.size.canvas)
                mode: !pane.iphone ? "" : pane.appsLoading ? "loading" : pane.apps.length === 0 ? "empty" : ""
                icon: "\u{f003b}"
                title: pane.appsLoading ? I18n.tr("Looking…") : I18n.tr("No app on this iPhone shares files.")
            }
            Rectangle {
                Layout.fillWidth: true
                visible: list.count > 0
                implicitHeight: listColumn.implicitHeight
                radius: Design.s(Design.radius.card)
                color: Design.glassCard
                border.color: Design.line
                border.width: Design.border
                ColumnLayout {
                    id: listColumn
                    width: parent.width
                    spacing: 0
                    Repeater {
                        id: list
                        // The phone's shared storage first (photos, downloads,
                        // what other programs put there), then each app's.
                        model: pane.iphone ? [{ id: "media", name: I18n.tr("All files"), version: "" }].concat(pane.apps)
                             : (pane.device.storages && pane.device.storages.length
                                ? pane.device.storages.map(s => ({ id: s, name: s }))
                                : [{ id: "media", name: I18n.tr("Phone storage") }])
                        delegate: Rectangle {
                            id: appRow
                            required property var modelData
                            required property int index
                            Layout.fillWidth: true
                            implicitHeight: Design.s(Design.size.row)
                            color: appMa.containsMouse ? Design.hover : "transparent"
                            radius: Design.s(Design.radius.card)
                            Rectangle {
                                visible: appRow.index > 0
                                anchors.top: parent.top
                                x: Design.s(Design.size.rowTall); width: parent.width - x; height: 1
                                color: Design.line
                            }
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: Design.s(Design.space.md)
                                anchors.rightMargin: Design.s(Design.space.md)
                                spacing: Design.s(Design.space.md)
                                Rectangle {
                                    Layout.preferredWidth: Design.s(Design.size.sm); Layout.preferredHeight: Design.s(Design.size.sm)
                                    radius: Design.s(Design.radius.ctl)
                                    color: Design.well
                                    Icon { anchors.centerIn: parent; text: pane.iphone ? "\u{f003b}" : "\u{f02ca}"; color: Design.textDim }
                                }
                                Label { Layout.fillWidth: true; text: appRow.modelData.name; elide: Text.ElideRight }
                                Label { visible: !!appRow.modelData.version; text: appRow.modelData.version || ""; dim: true; role: "caption" }
                                Icon { text: "\u{f0142}"; color: Design.textFaint }
                            }
                            Clickable {
                                id: appMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Devices.browse(pane.id, appRow.modelData.id)
                            }
                        }
                    }
                }
            }
        }
    }

    // A tab's page: a centred column that scrolls.
    component Page: Flickable {
        id: page
        default property alias content: column.data
        anchors.fill: parent
        contentHeight: column.implicitHeight + Design.s(Design.space.xl) * 2
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        C.ScrollBar.vertical: OverflowBar {}
        ColumnLayout {
            id: column
            x: Math.max(Design.s(Design.space.xl), (page.width - width) / 2)
            y: Design.s(Design.space.xl)
            width: Math.min(page.width - Design.s(Design.space.xl) * 2, Design.s(Design.width.menuMax))
            spacing: Design.s(Design.space.xl)
        }
    }
    component Divider: Rectangle { Layout.fillWidth: true; Layout.preferredHeight: 1; color: Design.line }
}
