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

    // Leaving the page must not lose an edit still waiting to be written.
    Component.onDestruction: Services.Theme.finishEdit()

    Layout.fillWidth: true
    spacing: Design.s(Design.space.lg)

    // ── Light by day, dark by night ─────────────────────────────────────────
    SettingsGroup {
        title: I18n.tr("Light and dark")
        description: Settings.themeAuto && Services.Theme.nightFrom !== ""
            ? I18n.tr("Dark from sunset (%1) to sunrise (%2), at the place set for the night light",
                      Services.Theme.nightFrom, Services.Theme.nightTo)
            : I18n.tr("One theme all day, or light by day and dark after sunset")

        SettingsRow {
            title: I18n.tr("Schedule")

            SegmentedControl {
                size: "sm"
                Layout.preferredWidth: Design.s(Design.width.select)
                model: [
                    { id: "manual", label: I18n.tr("Always one theme") },
                    { id: "auto",   label: I18n.tr("Automatically") }
                ]
                current: Settings.themeAuto ? "auto" : "manual"
                onPicked: id => Settings.set("themeAuto", id === "auto")
            }
        }

        Repeater {
            model: Settings.themeAuto ? [{ key: "themeDay", label: I18n.tr("Day") },
                                         { key: "themeNight", label: I18n.tr("Night") }] : []
            delegate: SettingsRow {
                id: autoRow
                required property var modelData
                title: autoRow.modelData.label

                Select {
                    Layout.preferredWidth: Design.s(Design.width.control)
                    model: Services.Theme.available.map(t => ({ id: t.id, label: t.name }))
                    current: Settings[autoRow.modelData.key]
                    onPicked: id => Settings.set(autoRow.modelData.key, id)
                }
            }
        }
    }

    SettingsGroup {
        title: I18n.tr("Theme")
        icon: "\u{f0765}"

        // From the wallpaper.
        //
        // Not in the Repeater above it, because it is not a file in the themes
        // directory — it is generated from whatever picture is on the desktop
        // right now, and re-generated whenever it is asked for.
        // In use, it says so by its command: Regenerate instead of Apply.
        SettingsRow {
            label: I18n.tr("From the wallpaper")
            note: I18n.tr("Takes the picture's dominant colour and builds the palette around it. Warnings and errors keep their own colours.")

            Button {
                size: "sm"
                checked: Settings.themeName === "wallpaper"
                text: Settings.themeName === "wallpaper" ? I18n.tr("Regenerate") : I18n.tr("Apply")
                icon: "\u{f0765}"
                onClicked: Services.Theme.applyFromWallpaper()
            }

            // Keeps this palette as a theme, so the next wallpaper doesn't replace it.
            Button {
                size: "sm"
                text: I18n.tr("Save as theme")
                icon: "\u{f0193}"
                onClicked: {
                    if (Services.Theme.saveWallpaperAs(newThemeName.text) !== "")
                        newThemeName.text = "";
                }
            }
        }

        Repeater {
            model: Services.Theme.available

            ListRow {
                selected: themeRow.isCurrent
                handlesMouse: false
                hovered: themeMa.containsMouse
                id: themeRow
                required property var modelData
                readonly property bool isCurrent: Settings.themeName === themeRow.modelData.id

                Layout.fillWidth: true
                Layout.preferredHeight: Design.s(Design.size.rowTall)


                RowLayout {
                    anchors.fill: parent
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
                                ? I18n.tr("Built in")
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

                    IconButton {
                        visible: !themeRow.modelData.builtin
                        icon: "\u{f03eb}"
                        onClicked: Services.Theme.beginEdit(themeRow.modelData.id)
                    }

                    Button {
                        visible: !themeRow.modelData.builtin
                        Layout.fillWidth: false
                        size: "sm"
                        variant: "danger"
                        text: I18n.tr("Delete")
                        icon: "\u{f01b4}"
                        onClicked: Services.Theme.deleteTheme(themeRow.modelData.id)
                    }
                }

                overlay: Clickable {
                    id: themeMa
                    z: -1
                    onClicked: Services.Theme.apply(themeRow.modelData.id)
                }
            }
        }

        // ── Editor ──────────────────────────────────────────────────────────
        ColumnLayout {
            id: editor
            Layout.fillWidth: true
            Layout.topMargin: Design.s(Design.space.md)
            spacing: Design.s(Design.space.sm)
            visible: Services.Theme.editingId !== ""

            property string selected: ""

            readonly property var groups: [
                { title: I18n.tr("Surfaces"), roles: [["ground", "Background"], ["lowest", "Deepest"], ["low", "Panels"],
                                             ["mid", "Cards"], ["high", "Hover"], ["highest", "Selected"]] },
                { title: I18n.tr("Text"), roles: [["text", "Text"], ["textDim", "Secondary text"],
                                         ["outline", "Outline"], ["outlineVariant", "Divider"]] },
                { title: I18n.tr("Accent"), roles: [["primary", "Accent"], ["primaryText", "Text on accent"],
                                           ["primaryBox", "Accent surface"], ["tertiary", "Second accent"],
                                           ["error", "Error"], ["errorText", "Text on error"]] },
                { title: I18n.tr("Colours"), roles: [["blue", "Blue"], ["sapphire", "Sapphire"], ["mauve", "Mauve"],
                                            ["pink", "Pink"], ["peach", "Peach"], ["yellow", "Yellow"],
                                            ["green", "Green"], ["teal", "Teal"], ["red", "Red"],
                                            ["maroon", "Maroon"], ["lavender", "Lavender"]] }
            ]

            SectionLabel {
                text: I18n.tr("Editing %1", Services.Theme.editingId.replace(/[-_]/g, " "))
            }

            Label {
                text: I18n.tr("Changes show and save as you make them. Click a swatch for sliders, or type a hex value.")
                role: "caption"; dim: true; wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            Repeater {
                model: editor.groups

                ColumnLayout {
                    id: group
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: Design.s(Design.space.xs)

                    Label {
                        text: group.modelData.title
                        role: "caption"
                        weight: Design.weight.semibold
                        dim: true
                        Layout.topMargin: Design.s(Design.space.xs)
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: Math.max(1, Math.floor(width / Design.s(Design.width.control)))
                        columnSpacing: Design.s(Design.space.sm)
                        rowSpacing: Design.s(Design.space.xs)

                        Repeater {
                            model: group.modelData.roles

                            Box {
                                id: roleRow
                                required property var modelData
                                readonly property string role: modelData[0]
                                readonly property string colour: Services.Theme.draft[role] || "#000000"
                                readonly property bool isSelected: editor.selected === role
                                // Typing breaks the text binding; keep it in step with the sliders.
                                onColourChanged: if (!hexField.focused) hexField.text = colour

                                Layout.fillWidth: true
                                Layout.preferredHeight: Design.s(Design.size.row)
                                radius: Design.s(Design.radius.ctl)
                                color: isSelected ? Design.stateSelectedSoft : Design.glassTile
                                border.color: isSelected ? Design.accentLine : "transparent"
                                border.width: Design.border

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: Design.s(Design.space.xs)
                                    anchors.rightMargin: Design.s(Design.space.xs)
                                    spacing: Design.s(Design.space.sm)

                                    Box {
                                        Layout.preferredWidth: Design.s(Design.size.sm)
                                        Layout.preferredHeight: Design.s(Design.size.sm)
                                        radius: Design.s(Design.radius.sm)
                                        color: roleRow.colour
                                        border.color: Design.glassBorderStrong
                                        border.width: Design.border
                                        Clickable {
                                            onClicked: editor.selected = roleRow.isSelected ? "" : roleRow.role
                                        }
                                    }

                                    Label {
                                        text: I18n.tr(roleRow.modelData[1])
                                        role: "caption"
                                        Layout.fillWidth: true
                                        elide: Text.ElideRight
                                    }

                                    Field {
                                        mono: true
                                        id: hexField
                                        Layout.preferredWidth: Design.s(Design.width.field)
                                        text: roleRow.colour
                                        function take(value) {
                                            const v = value.trim();
                                            if (!/^#?[0-9a-fA-F]{6}$/.test(v)) return;
                                            const hex = (v.startsWith("#") ? v : "#" + v).toLowerCase();
                                            if (hex !== String(roleRow.colour).toLowerCase())
                                                Services.Theme.setDraft(roleRow.role, hex);
                                        }
                                        onEdited: value => take(value)
                                        onCommitted: value => take(value)
                                    }
                                }
                            }
                        }
                    }

                    // Sliders for the selected colour, under its own group.
                    ColumnLayout {
                        id: picker
                        Layout.fillWidth: true
                        spacing: Design.s(Design.space.xs)
                        visible: group.modelData.roles.some(r => r[0] === editor.selected)

                        readonly property color current: Services.Theme.draft[editor.selected] || "#000000"

                        function setHsl(h, sat, l) {
                            const c = Qt.hsla(h, sat, l, 1.0);
                            const hex = (v) => ("0" + Math.round(v * 255).toString(16)).slice(-2);
                            Services.Theme.setDraft(editor.selected, "#" + hex(c.r) + hex(c.g) + hex(c.b));
                        }

                        Slider {
                            Layout.fillWidth: true
                            label: I18n.tr("Hue")
                            showPercent: false
                            minimum: 0; maximum: 359
                            value: Math.max(0, Math.round(picker.current.hslHue * 359))
                            tone: Qt.hsla(Math.max(0, picker.current.hslHue), 0.8, 0.6, 1)
                            onMoved: pct => picker.setHsl(pct / 359, picker.current.hslSaturation, picker.current.hslLightness)
                        }
                        Slider {
                            Layout.fillWidth: true
                            label: I18n.tr("Saturation")
                            value: Math.round(picker.current.hslSaturation * 100)
                            tone: picker.current
                            onMoved: pct => picker.setHsl(Math.max(0, picker.current.hslHue), pct / 100, picker.current.hslLightness)
                        }
                        Slider {
                            Layout.fillWidth: true
                            label: I18n.tr("Lightness")
                            value: Math.round(picker.current.hslLightness * 100)
                            tone: Design.text
                            onMoved: pct => picker.setHsl(Math.max(0, picker.current.hslHue), picker.current.hslSaturation, pct / 100)
                        }
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Design.s(Design.space.sm)
                Item { Layout.fillWidth: true }
                Button {
                    size: "sm"
                    variant: "secondary"
                    text: I18n.tr("Open JSON")
                    icon: "\u{f0219}"
                    onClicked: Quickshell.execDetached(["b1air-text", Services.Theme.themesDir + "/" + Services.Theme.editingId + ".json"])
                }
                Button {
                    size: "sm"
                    variant: "secondary"
                    text: I18n.tr("Revert")
                    icon: "\u{f0156}"
                    onClicked: Services.Theme.revertEdit()
                }
                Button {
                    size: "sm"
                    variant: "primary"
                    text: I18n.tr("Done")
                    icon: "\u{f012c}"
                    onClicked: { editor.selected = ""; Services.Theme.finishEdit(); }
                }
            }
        }

        // A heading and what it does, as a row: a caption over a paragraph
        // over a field read as three loose lines.
        SettingsRow {
            label: I18n.tr("Create your own")
            note: I18n.tr("A new theme starts as a copy of the palette on screen, so it renders correctly from the first save and you only change what you want to change.")
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.sm)

            Field {
                id: newThemeName
                Layout.fillWidth: true
                placeholder: I18n.tr("Name for the new theme")
                onAccepted: value => {
                    if (Services.Theme.createFrom(value) !== "")
                        newThemeName.text = "";
                }
            }

            Button {
                size: "sm"
                text: I18n.tr("Create")
                icon: "\u{f0415}"
                onClicked: {
                    if (Services.Theme.createFrom(newThemeName.text) !== "")
                        newThemeName.text = "";
                }
            }

            Button {
                size: "sm"
                variant: "secondary"
                text: I18n.tr("Edit")
                icon: "\u{f03eb}"
                enabled: Services.Theme.currentFile !== "" && Services.Theme.editingId === ""
                onClicked: Services.Theme.beginEdit(Settings.themeName)
            }
        }

        Label {
            text: Services.Theme.currentFile !== ""
                ? I18n.tr("Edit opens the current theme in the editor above.")
                : I18n.tr("Built-in themes can't be edited — create a copy first.")
            role: "caption"
            dim: true
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }

        // A heading and what it does, as a row: a caption over a paragraph
        // over a field read as three loose lines.
        SettingsRow {
            label: I18n.tr("Import & export")
            note: I18n.tr("Export writes the palette you are looking at into %1, where it shows up in the list above and can be copied to another machine.", Services.Theme.themesDir)
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Design.s(Design.space.sm)

            Field {
                mono: true
                id: importPath
                Layout.fillWidth: true
                placeholder: I18n.tr("Path to a theme .json to import")
                onAccepted: value => {
                    if (Services.Theme.importFrom(value))
                        importPath.text = "";
                }
            }

            Button {
                size: "sm"
                text: I18n.tr("Import")
                icon: "\u{f0552}"
                onClicked: {
                    if (Services.Theme.importFrom(importPath.text))
                        importPath.text = "";
                }
            }

            Button {
                size: "sm"
                variant: "secondary"
                text: I18n.tr("Export")
                icon: "\u{f0554}"
                onClicked: Services.Theme.exportTo("")
            }
        }

        Label {
            visible: Services.Theme.lastError !== "" || Services.Theme.lastExportPath !== ""
            // Services/Theme keeps its errors in English, as the rest of the
            // strings are kept; translated here, where they are shown.
            text: Services.Theme.lastError !== ""
                ? I18n.tr(Services.Theme.lastError)
                : I18n.tr("Exported to %1", Services.Theme.lastExportPath)
            role: "caption"
            color: Services.Theme.lastError !== "" ? Design.danger : Design.ok
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
        }
    }

}
