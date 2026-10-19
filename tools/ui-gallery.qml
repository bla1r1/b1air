import QtQuick
import QtQuick.Window
import QtQuick.Layouts
import B1air.Daemon
import "../src/shell/qml/Ui"

// =============================================================================
// ui-gallery — the design system on one page, rendered to a picture.
//
// The main components in the containers they live in — an app's sidebar and
// its rows, a settings card with its rows, buttons, fields and a segmented
// control, a toolbar's glass groups, tiles — so a change to Ui/ shows on all
// of them at once, and the corner rule (Shape) can be seen working: what sits
// near a container's edge concentric with it, what sits far in its own.
//
// Needs no screen and no GPU (glass draws its plain fallback then):
//
//   QT_QPA_PLATFORM=offscreen QML_IMPORT_PATH=src/build/qml \
//       qml tools/ui-gallery.qml -- out.png
//
// (the B1air.Daemon module from a build, for Shape: an installed one older
// than the build has none.)
// =============================================================================

Window {
    id: page
    width: 1300
    height: 820
    visible: true
    color: Design.ground

    readonly property string out: Qt.application.arguments[Qt.application.arguments.length - 1]

    // The window's own colour is not in a grab of its content.
    Rectangle { anchors.fill: parent; color: Design.ground }

    RowLayout {
        anchors.fill: parent
        spacing: 0

        // An app's sidebar, set into the window as the apps set it.
        AppSidebar {
            Layout.fillHeight: true
            SidebarHeading { text: "Places" }
            SidebarItem { label: "Home"; glyph: "\u{f02dc}"; active: true }
            SidebarItem { label: "Documents"; glyph: "\u{f0219}" }
            SidebarItem { label: "Downloads"; glyph: "\u{f01da}"; badge: "3" }
            SidebarItem { label: "Pictures"; glyph: "\u{f02e9}" }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.margins: Design.s(Design.space.xl)
            spacing: Design.s(Design.space.lg)

            // A toolbar: its controls on glass groups.
            RowLayout {
                spacing: Design.s(Design.space.sm)
                ToolbarGroup {
                    backdrop: null
                    Button { variant: "ghost"; iconOnly: true; icon: "\u{f004d}" }
                    Button { variant: "ghost"; iconOnly: true; icon: "\u{f0054}" }
                    Button { variant: "ghost"; iconOnly: true; icon: "\u{f005d}" }
                }
                ToolbarGroup {
                    backdrop: null
                    Button { variant: "ghost"; iconOnly: true; icon: "\u{f02fd}"; checked: true }
                    Button { variant: "ghost"; iconOnly: true; icon: "\u{f01d9}" }
                }
                Item { Layout.fillWidth: true }
                SegmentedControl {
                    size: "sm"
                    model: [{ id: "a", label: "Icons" }, { id: "b", label: "List" }, { id: "c", label: "Columns" }]
                    current: "a"
                }
            }

            SettingsGroup {
                Layout.fillWidth: true
                title: "A settings card"
                SettingsRow {
                    label: "A field"
                    Field { Layout.preferredWidth: Design.s(Design.width.control); placeholder: "Type here" }
                }
                SettingsRow {
                    label: "Buttons"
                    Button { label: "Secondary" }
                    Button { label: "Primary"; variant: "primary" }
                    Button { label: "Delete"; variant: "danger" }
                }
                SwitchRow { label: "A switch"; checked: true }
            }

            // A list: rows set in from its sides, a quiet stripe, one chosen,
            // one a drop target.
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: listCol.implicitHeight + Design.s(Design.space.xs) * 2
                radius: Design.s(Design.radius.card)
                color: Design.glassCard
                border.color: Design.glassBorder
                // The list runs to the card's sides; its rows set themselves
                // in, and take the card's radius less that.
                Shape.radius: radius
                Shape.inset: 0
                Column {
                    id: listCol
                    anchors.fill: parent
                    anchors.topMargin: Design.s(Design.space.xs)
                    Repeater {
                        model: ["Selected", "Striped", "Plain", "Drop target"]
                        ListRow {
                            width: listCol.width
                            selected: index === 0
                            striped: index === 1
                            highlight: index === 3
                            RowLayout {
                                anchors.fill: parent
                                spacing: Design.s(Design.space.sm)
                                CheckBox { checked: index < 2; mixed: index === 1 }
                                Label { Layout.fillWidth: true; text: modelData }
                                Label { text: "12 KB"; dim: true }
                            }
                        }
                    }
                }
            }

            RowLayout {
                spacing: Design.s(Design.space.sm)
                Button { label: "Commit to main"; variant: "primary"; size: "lg" }
                Button { label: "Committing…"; variant: "primary"; size: "lg"; busy: true }
                Button { label: "Ghost"; variant: "ghost"; checked: true }
                Scrubber { Layout.fillWidth: true; from: 0; to: 100; value: 40 }
            }

            RowLayout {
                spacing: Design.s(Design.space.md)
                Repeater {
                    model: 3
                    Tile {
                        Layout.preferredWidth: Design.s(Design.size.canvas) / 1.3
                        Layout.preferredHeight: Design.s(Design.size.stat)
                        on: index === 0
                        Label { anchors.centerIn: parent; text: "Tile " + (index + 1) }
                    }
                }
            }

            Item { Layout.fillHeight: true }
        }

        // An inspector: the sidebar's shape on the right.
        WindowPane {
            edge: Qt.RightEdge
            Layout.fillHeight: true
            implicitWidth: Design.s(Design.width.sidebar) + inset
            padding: Design.s(Design.space.md)
            ColumnLayout {
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: Design.s(Design.space.sm)
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: Design.s(Design.size.canvas) / 2
                    radius: Design.corner(Shape.radius, Design.s(Design.radius.ctl))
                    color: Design.well
                }
                Label { text: "Inspector"; role: "subhead"; weight: Design.weight.semibold }
                Label { text: "Its corners from the pane"; dim: true }
            }
        }
    }

    Timer {
        interval: 600
        running: true
        onTriggered: page.contentItem.grabToImage(r => { r.saveToFile(page.out); Qt.quit(); })
    }
}
