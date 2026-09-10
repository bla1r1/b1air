import QtQuick
import QtQuick.Layouts
import Quickshell
import "../../Ui"
import "../../Services"
import "../../Services" as Services

// =============================================================================
// Themes — the whole palette, and making your own.
//
// This began as a card on the Appearance page, wedged above the accent picker.
// It outgrew that: choosing a theme, creating one from the current palette,
// editing it and moving it between machines is a job of its own, and burying it
// under "Appearance" made it something you had to already know was there.
// =============================================================================

ColumnLayout {
    id: section

    Layout.fillWidth: true
    spacing: Design.s(Design.space.lg)

    Card {
        title: "Theme"
        subtitle: "The whole palette — surfaces, text and accents — in one file"
        icon: "\u{f0765}"
        accentColor: Design.mauve

        // From the wallpaper.
        //
        // Not in the Repeater above it, because it is not a file in the themes
        // directory — it is generated from whatever picture is on the desktop
        // right now, and re-generated whenever it is asked for.
        RowLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.md)

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Design.s(2)
                Label {
                    Layout.fillWidth: true
                    text: "From the wallpaper"
                    weight: Design.weight.semibold
                    color: Settings.themeName === "wallpaper" ? Design.accent : Design.text
                }
                Label {
                    Layout.fillWidth: true
                    text: "Takes the picture's dominant colour and builds the palette around it. Warnings and errors keep their own colours."
                    role: "caption"; dim: true; wrapMode: Text.WordWrap
                }
            }

            ActionButton {
                label: Settings.themeName === "wallpaper" ? "Regenerate" : "Apply"
                icon: "\u{f0765}"
                onActivated: Services.Theme.applyFromWallpaper()
            }
        }

        Repeater {
            model: Services.Theme.available

            Rectangle {
                id: themeRow
                required property var modelData
                readonly property bool isCurrent: Settings.themeName === themeRow.modelData.id

                Layout.fillWidth: true
                Layout.preferredHeight: Design.s(Design.size.rowTall)
                radius: Design.s(Design.radius.ctl)
                color: themeRow.isCurrent ? Design.tint(Design.accent, 0.15)
                                          : (themeMa.containsMouse ? Design.glassHover : "transparent")
                border.color: themeRow.isCurrent ? Design.tint(Design.accent, 0.35) : "transparent"
                border.width: Design.border

                Behavior on color { ColorAnimation { duration: Design.duration.fast } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Design.s(Design.space.sm)
                    anchors.rightMargin: Design.s(Design.space.sm)
                    spacing: Design.s(Design.space.sm)

                    Icon {
                        text: themeRow.modelData.builtin ? "\u{f0765}" : "\u{f0224}"
                        role: "body"
                        color: themeRow.isCurrent ? Design.accent : Design.textDim
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        Label {
                            text: themeRow.modelData.name
                            weight: Design.weight.semibold
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                        }

                        Label {
                            text: themeRow.modelData.builtin
                                ? "Built in"
                                : themeRow.modelData.path
                            role: "caption"
                            dim: true
                            Layout.fillWidth: true
                            elide: Text.ElideMiddle
                        }
                    }

                    Icon {
                        visible: themeRow.isCurrent
                        text: "\u{f012c}"
                        role: "caption"
                        color: Design.accent
                    }
                }

                Clickable {
                    id: themeMa
                    onClicked: Services.Theme.apply(themeRow.modelData.id)
                }
            }
        }

        SectionLabel {
            text: "Create your own"
            Layout.topMargin: Design.s(Design.space.sm)
        }

        Label {
            text: "A new theme starts as a copy of the palette on screen, so it "
                  + "renders correctly from the first save and you only change what "
                  + "you want to change."
            role: "caption"
            dim: true
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.sm)

            Field {
                id: newThemeName
                Layout.fillWidth: true
                placeholder: "Name for the new theme"
                onAccepted: value => {
                    if (Services.Theme.createFrom(value) !== "")
                        newThemeName.text = "";
                }
            }

            Pill {
                label: "Create"
                icon: "\u{f0415}"
                activeColor: Design.mauve
                onClicked: {
                    if (Services.Theme.createFrom(newThemeName.text) !== "")
                        newThemeName.text = "";
                }
            }

            Pill {
                label: "Edit"
                icon: "\u{f03eb}"
                // Ui/Pill has no disabled state of its own; `enabled` blocks the
                // clicks and the opacity says so.
                enabled: Services.Theme.currentFile !== ""
                opacity: enabled ? 1.0 : 0.45
                activeColor: Design.sapphire
                onClicked: Services.Theme.editCurrent()
            }
        }

        Label {
            text: Services.Theme.currentFile !== ""
                ? "Edit opens the theme in the text editor. Saving there re-applies it straight away."
                : "Built-in themes cannot be edited — create a copy first."
            role: "caption"
            dim: true
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        SectionLabel {
            text: "Import & export"
            Layout.topMargin: Design.s(Design.space.sm)
        }

        Label {
            text: "Export writes the palette you are looking at into "
                  + Services.Theme.themesDir + ", where it shows up in the list above "
                  + "and can be copied to another machine."
            role: "caption"
            dim: true
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.sm)

            Field {
                id: importPath
                Layout.fillWidth: true
                placeholder: "Path to a theme .json to import"
                onAccepted: value => {
                    if (Services.Theme.importFrom(value))
                        importPath.text = "";
                }
            }

            Pill {
                label: "Import"
                icon: "\u{f0552}"
                activeColor: Design.ok
                onClicked: {
                    if (Services.Theme.importFrom(importPath.text))
                        importPath.text = "";
                }
            }

            Pill {
                label: "Export"
                icon: "\u{f0554}"
                activeColor: Design.sapphire
                onClicked: Services.Theme.exportTo("")
            }
        }

        Label {
            visible: Services.Theme.lastError !== "" || Services.Theme.lastExportPath !== ""
            text: Services.Theme.lastError !== ""
                ? Services.Theme.lastError
                : "Exported to " + Services.Theme.lastExportPath
            role: "caption"
            color: Services.Theme.lastError !== "" ? Design.danger : Design.ok
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
    }

}
