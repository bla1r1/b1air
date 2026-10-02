import QtQuick
import QtQuick.Layouts
import Quickshell
import B1air.Daemon
import Quickshell.Io
import "../Ui"
import "../Services"

// =============================================================================
// macOS-Style Keyboard / Input Source Popup
// =============================================================================

PopupShell {
    id: window

    padding: Design.space.sm

    property int activeIndex: 0
    property string activeCode: "us"

    readonly property var langMap: ({
        "us": { name: "English (US)", badge: "ABC" },
        "en": { name: "English", badge: "ABC" },
        "ua": { name: "Ukrainian (Українська)", badge: "UA" },
        "uk": { name: "Ukrainian (Українська)", badge: "UA" },
        "de": { name: "German (Deutsch)", badge: "DE" },
        "pl": { name: "Polish (Polski)", badge: "PL" },
        "fr": { name: "French (Français)", badge: "FR" },
        "es": { name: "Spanish (Español)", badge: "ES" },
        "it": { name: "Italian (Italiano)", badge: "IT" },
        "pt": { name: "Portuguese (Português)", badge: "PT" },
        "cz": { name: "Czech (Čeština)", badge: "CZ" },
        "tr": { name: "Turkish (Türkçe)", badge: "TR" },
        "se": { name: "Swedish (Svenska)", badge: "SE" },
        "no": { name: "Norwegian (Norsk)", badge: "NO" },
        "fi": { name: "Finnish (Suomi)", badge: "FI" },
        "nl": { name: "Dutch (Nederlands)", badge: "NL" },
        "ja": { name: "Japanese (日本語)", badge: "JA" },
        "jp": { name: "Japanese (日本語)", badge: "JA" },
        "ko": { name: "Korean (한국어)", badge: "KO" },
        "kr": { name: "Korean (한국어)", badge: "KO" },
        "zh": { name: "Chinese (中文)", badge: "ZH" },
        "ka": { name: "Georgian (ქართული)", badge: "GE" },
        "ge": { name: "Georgian (ქართული)", badge: "GE" },
        "ro": { name: "Romanian (Română)", badge: "RO" },
        "hu": { name: "Hungarian (Magyar)", badge: "HU" },
        "el": { name: "Greek (Ελληνικά)", badge: "GR" },
        "gr": { name: "Greek (Ελληνικά)", badge: "GR" },
        "he": { name: "Hebrew (עברית)", badge: "IL" },
        "il": { name: "Hebrew (עברית)", badge: "IL" },
        "ar": { name: "Arabic (العربية)", badge: "AR" },
        "ru": { name: "Russian (Русский)", badge: "RU" }
    })

    function getLangInfo(code) {
        const c = (code || "").trim().toLowerCase();
        if (langMap[c]) return langMap[c];
        return { name: c.toUpperCase(), badge: c.toUpperCase() };
    }

    readonly property var configuredLanguages: {
        const str = Settings.language || "us";
        return str.split(",").map(x => x.trim()).filter(x => x.length > 0);
    }

    // Which layout is active, asked of sway when the popup opens.
    Component.onCompleted: Sway.query("inputs", inputs => {
        if (!Array.isArray(inputs))
            return;   // sway not answering yet
        for (const dev of inputs) {
            if (dev.type !== "keyboard")
                continue;
            const idx = Number(dev.xkb_active_layout_index || 0);
            window.activeIndex = idx;
            if (window.configuredLanguages.length > idx)
                window.activeCode = window.configuredLanguages[idx];
            return;
        }
    })

    function switchLayout(idx) {
        window.activeIndex = idx;
        Sway.command("input type:keyboard xkb_switch_layout " + Number(idx));
        window.close();
    }

    function openKeyboardSettings() {
        window.close();
        if (typeof masterWindow !== "undefined") {
            masterWindow.handleIpcCommand("open:settings:keyboard", true);
        } else {
            Quickshell.execDetached(["b1air-shell", "open", "settings", "keyboard"]);
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Design.s(Design.space.xs)

        // Header Title
        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Design.s(Design.space.xs)
            Layout.rightMargin: Design.s(Design.space.xs)
            Layout.topMargin: Design.s(2)
            spacing: Design.s(Design.space.xs)

            Icon {
                text: "\u{f030c}"
                role: "caption"
                color: Design.textDim
            }

            Label {
                text: I18n.tr("Input Sources")
                role: "caption"
                weight: Design.weight.bold
                color: Design.textDim
                Layout.fillWidth: true
            }
        }

        // Divider
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Design.veilStrong
        }

        // Layouts List
        ColumnLayout {
            Layout.fillWidth: true
            spacing: Design.s(2)

            Repeater {
                model: window.configuredLanguages

                delegate: Rectangle {
                    id: row
                    required property string modelData
                    required property int index

                    Layout.fillWidth: true
                    Layout.preferredHeight: Design.s(34)
                    radius: Design.s(Design.radius.ctl)

                    readonly property bool isActive: window.activeIndex === row.index
                    readonly property var info: window.getLangInfo(row.modelData)

                    color: rowMa.containsMouse ? Design.raised : (row.isActive ? Design.tint(Design.accent, 0.12) : "transparent")

                    Behavior on color { ColorAnimation { duration: Design.duration.fast } }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Design.s(Design.space.sm)
                        anchors.rightMargin: Design.s(Design.space.sm)
                        spacing: Design.s(Design.space.sm)

                        // macOS-style Layout Badge
                        Rectangle {
                            width: Design.s(32); height: Design.s(20); radius: Design.s(4)
                            color: row.isActive ? Design.accent : Design.sunken
                            border.color: row.isActive ? Design.accent : Design.raised
                            border.width: 1

                            Label {
                                anchors.centerIn: parent
                                text: row.info.badge
                                role: "caption"
                                weight: Design.weight.bold
                                isMono: true
                                color: row.isActive ? Design.surface : Design.text
                            }
                        }

                        // Language Name
                        Label {
                            text: row.info.name
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            weight: row.isActive ? Design.weight.bold : Design.weight.medium
                            color: row.isActive ? Design.text : Design.textDim
                        }

                        // Checkmark on active layout
                        Icon {
                            visible: row.isActive
                            text: "\u{f00c}"
                            role: "caption"
                            color: Design.accent
                        }
                    }

                    Clickable {
                        id: rowMa
                        hoverEnabled: true
                        onClicked: window.switchLayout(row.index)
                    }
                }
            }
        }

        // Bottom Divider
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 1
            color: Design.veilStrong
        }

        // "Keyboard Settings..." Action Row
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: Design.s(32)
            radius: Design.s(Design.radius.ctl)
            color: settMa.containsMouse ? Design.raised : "transparent"

            Behavior on color { ColorAnimation { duration: Design.duration.fast } }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Design.s(Design.space.sm)
                anchors.rightMargin: Design.s(Design.space.sm)
                spacing: Design.s(Design.space.sm)

                Icon {
                    text: "\u{f0493}"
                    role: "caption"
                    color: Design.textDim
                }

                Label {
                    text: I18n.tr("Keyboard Settings...")
                    role: "caption"
                    weight: Design.weight.medium
                    Layout.fillWidth: true
                }
            }

            Clickable {
                id: settMa
                hoverEnabled: true
                onClicked: window.openKeyboardSettings()
            }
        }
    }
}
