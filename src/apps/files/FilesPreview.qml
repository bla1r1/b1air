import QtQuick
import QtQuick.Layouts
import "Ui"

// What is selected, large: a picture shown, anything else as its icon, with
// its name and what it is under it. The column view's last column and the
// gallery's upper part.
Item {
    id: root
    // A row of FilesBackend.files (FileListModel.get): name, path, isImage, …
    property var item: ({})
    property string glyph: ""
    property color tone: Design.accent
    // The gallery: the picture fills the space, the words go in one line.
    property bool large: false

    readonly property bool has: !!root.item && !!root.item.path

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Design.s(root.large ? Design.space.lg : Design.space.xl)
        spacing: Design.s(Design.space.md)
        visible: root.has

        Item { Layout.fillHeight: !root.large; visible: !root.large }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: root.large
            Layout.preferredHeight: root.large ? -1 : Math.min(width, Design.s(220))
            Image {
                id: pic
                anchors.fill: parent
                // A video by a frame from it (the thumbnail the grid made).
                readonly property bool video: root.has && root.item.category === "video"
                visible: root.has && (root.item.isImage || video) && status === Image.Ready
                source: !root.has ? ""
                      : root.item.isImage ? Paths.fileUrl(root.item.path)
                      : video ? "image://thumb/" + encodeURIComponent(root.item.path) : ""
                sourceSize: Qt.size(Design.s(root.large ? 1600 : 520), Design.s(root.large ? 1200 : 520))
                fillMode: Image.PreserveAspectFit
                asynchronous: true
                smooth: true
            }
            Text {
                anchors.centerIn: parent
                visible: !pic.visible
                text: root.glyph
                font.family: Design.font.icon
                font.pixelSize: Design.s(root.large ? 120 : 96)
                color: root.tone
            }
        }

        Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: root.has ? root.item.name : ""
            role: root.large ? "body" : "subhead"
            weight: Design.weight.semibold
            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
            maximumLineCount: 2
            elide: Text.ElideMiddle
        }
        Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: !root.has ? ""
                : [I18n.tr(root.item.kind || ""), root.item.isDir ? "" : root.item.sizeText, root.item.modifiedText]
                    .filter(s => !!s).join("  ·  ")
            role: "caption"
            dim: true
            wrapMode: Text.WordWrap
        }

        Item { Layout.fillHeight: !root.large; visible: !root.large }
    }

    Label {
        anchors.centerIn: parent
        visible: !root.has
        text: I18n.tr("Select a file to see it here")
        role: "caption"
        color: Design.textFaint
    }
}
