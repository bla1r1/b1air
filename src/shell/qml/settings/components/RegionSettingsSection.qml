import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../../Ui"
import "../../Services"

// =============================================================================
// Language & Region: three different things that were one, or none.
//
//   Interface language   b1air's own menus and apps (Ui/I18n.qml), from its
//                        translations; English where there is none.
//   System language      LANG for every other program — Firefox, GTK, Qt —
//                        in ~/.config/locale.conf, which b1air-session reads
//                        at login. It was whatever the installer left.
//   Formats              dates, times, numbers, money, units: LC_TIME and the
//                        rest in the same file, and formatsLocale for the
//                        shell. They followed LANG, so a German system had
//                        German dates beside an English interface.
//
// Only a generated locale can be used; "Add" generates one (as root).
// =============================================================================

ColumnLayout {
    id: section

    Layout.fillWidth: true
    spacing: Design.s(Design.space.lg)

    // ── What the system has ──────────────────────────────────────────────────
    property var installed: []          // ["de_DE", "en_US", …]
    Process {
        id: localeList
        running: true
        command: ["locale", "-a"]
        stdout: StdioCollector {
            onStreamFinished: {
                const seen = [];
                for (const line of String(this.text || "").split("\n")) {
                    const m = line.trim().match(/^([a-z]{2,3}_[A-Z]{2})\.(utf-?8|UTF-?8)$/);
                    if (m && seen.indexOf(m[1]) < 0) seen.push(m[1]);
                }
                section.installed = seen.sort();
            }
        }
    }
    // Offered to add when missing.
    readonly property var common: ["en_US", "en_GB", "de_DE", "fr_FR", "es_ES", "it_IT", "pl_PL",
        "pt_BR", "nl_NL", "cs_CZ", "uk_UA", "ru_RU", "tr_TR", "sv_SE", "ja_JP", "zh_CN"]
    readonly property var missing: section.common.filter(n => section.installed.indexOf(n) < 0)

    function nameOf(code) {
        const l = Qt.locale(code);
        const lang = l.nativeLanguageName || code;
        const land = l.nativeTerritoryName || "";
        return land ? lang + " (" + land + ")" : lang;
    }

    // ── ~/.config/locale.conf ────────────────────────────────────────────────
    property var conf: ({})
    FileView {
        id: confFile
        path: Quickshell.env("HOME") + "/.config/locale.conf"
        printErrors: false
        watchChanges: true
        onLoaded: section.conf = section.parse(text())
        onLoadFailed: section.conf = ({})
        onFileChanged: reload()
    }
    // The system-wide default, for "as the system".
    property var systemConf: ({})
    FileView {
        path: "/etc/locale.conf"
        printErrors: false
        onLoaded: section.systemConf = section.parse(text())
    }

    function parse(t) {
        const o = {};
        for (const line of String(t || "").split("\n")) {
            const m = line.match(/^\s*([A-Z_]+)=("?)(.*)\2\s*$/);
            if (m) o[m[1]] = m[3];
        }
        return o;
    }
    function write(changes) {
        const o = Object.assign({}, section.conf);
        for (const k in changes) {
            if (changes[k] === "") delete o[k];
            else o[k] = changes[k];
        }
        section.conf = o;
        confFile.setText(Object.keys(o).map(k => k + "=" + o[k]).join("\n") + "\n");
    }
    function codeOf(value) { return String(value || "").split(".")[0]; }

    readonly property var formatKeys: ["LC_TIME", "LC_NUMERIC", "LC_MONETARY", "LC_MEASUREMENT", "LC_PAPER"]
    readonly property string systemLang: section.codeOf(section.conf.LANG)
    readonly property string defaultLang: section.codeOf(section.systemConf.LANG) || section.codeOf(Quickshell.env("LANG"))

    // ── Adding a locale ──────────────────────────────────────────────────────
    property string adding: ""
    property string addError: ""
    Process {
        id: generate
        onExited: code => {
            section.addError = code === 0 ? "" : I18n.tr("Could not add %1", section.nameOf(section.adding));
            section.adding = "";
            localeList.running = false;
            localeList.running = true;
        }
    }
    function add(code) {
        section.adding = code;
        section.addError = "";
        generate.command = ["pkexec", "b1air-daemon", "locale", "generate", code];
        generate.running = true;
    }

    Timer {
        id: restartSoon
        // After settings.json is written: the shell reads the language and
        // the formats when it starts.
        interval: 600
        onTriggered: Quickshell.execDetached(["b1air-shell", "forceReload"])
    }

    function setUiLanguage(id) {
        if ((Settings.uiLanguage || "auto") === id) return;
        Settings.set("uiLanguage", id);
        restartSoon.restart();
    }
    function setSystemLanguage(id) {
        if (id === "__system") section.write({ LANG: "", LANGUAGE: "" });
        else section.write({ LANG: id + ".UTF-8", LANGUAGE: id.split("_")[0] });
    }
    function setFormats(id) {
        const code = id === "__interface" ? "" : id;
        Settings.set("formatsLocale", code);
        const w = {};
        for (const k of section.formatKeys) w[k] = code === "" ? "" : code + ".UTF-8";
        section.write(w);
        restartSoon.restart();
    }

    // One entry per installed locale, named in its own language.
    readonly property var installedChoices: section.installed.map(c => ({ id: c, label: section.nameOf(c), detail: c }))

    // ── Language ─────────────────────────────────────────────────────────────
    SettingsGroup {
        title: I18n.tr("Language")
        description: I18n.tr("What this desktop and other programs speak")

        SettingsRow {
            label: I18n.tr("Interface language")
            note: I18n.tr("The shell restarts to switch")

            SegmentedControl {
                size: "sm"
                model: [
                    { id: "auto", label: I18n.tr("Auto") },
                    { id: "en",   label: "EN" },
                    { id: "uk",   label: "UK" },
                    { id: "ru",   label: "RU" }
                ]
                current: Settings.uiLanguage || "auto"
                onPicked: function(id) { section.setUiLanguage(id); }
            }
        }

        Label {
            Layout.fillWidth: true
            Layout.leftMargin: Design.s(Design.space.rowPaddingX)
            Layout.rightMargin: Design.s(Design.space.rowPaddingX)
            Layout.bottomMargin: Design.s(Design.space.xs)
            readonly property string sys: I18n.systemLanguage
            visible: (Settings.uiLanguage || "auto") === "auto" && I18n.translated.indexOf(sys) < 0 && sys !== "en"
            text: I18n.tr("The system is in %1, which has no translation here: English is used, dates included.", Qt.locale(sys).nativeLanguageName || sys)
            role: "footnote"
            dim: true
            wrapMode: Text.WordWrap
        }

        SettingsRow {
            label: I18n.tr("System language")
            note: I18n.tr("What other programs speak. From the next login")

            Select {
                model: [{
                    id: "__system",
                    label: section.defaultLang
                        ? I18n.tr("As the system: %1", section.nameOf(section.defaultLang))
                        : I18n.tr("As the system")
                }].concat(section.installedChoices)
                current: section.systemLang === "" ? "__system" : section.systemLang
                onPicked: function(id) { section.setSystemLanguage(id); }
            }
        }

        SettingsRow {
            visible: section.missing.length > 0 || section.adding !== ""
            label: I18n.tr("Add a language")
            note: I18n.tr("Needs administrator password")

            Select {
                model: section.missing.map(c => ({ id: c, label: section.nameOf(c), detail: c }))
                current: ""
                placeholder: section.adding !== ""
                    ? I18n.tr("Adding %1…", section.nameOf(section.adding))
                    : I18n.tr("Choose a language…")
                enabled: section.adding === ""
                onPicked: function(id) { section.add(id); }
            }
        }

        Label {
            visible: section.addError !== "" && section.adding === ""
            Layout.fillWidth: true
            Layout.leftMargin: Design.s(Design.space.rowPaddingX)
            Layout.rightMargin: Design.s(Design.space.rowPaddingX)
            Layout.bottomMargin: Design.s(Design.space.xs)
            text: section.addError
            color: Design.danger
            role: "footnote"
            wrapMode: Text.WordWrap
        }
    }

    // ── Region ───────────────────────────────────────────────────────────────
    SettingsGroup {
        id: formatsGroup
        title: I18n.tr("Region")
        description: I18n.tr("Dates, times, numbers, money and units")

        SettingsRow {
            label: I18n.tr("Formats")
            note: I18n.tr("Independent of interface language")

            Select {
                model: [{ id: "__interface", label: I18n.tr("Like the interface language") }].concat(section.installedChoices)
                current: (Settings.formatsLocale || "") === "" ? "__interface" : Settings.formatsLocale
                onPicked: function(id) { section.setFormats(id); }
            }
        }

        // Live preview of formats
        Item {
            id: previewBox
            Layout.fillWidth: true
            implicitHeight: previewGrid.implicitHeight + Design.s(Design.space.md) * 2

            readonly property var preview: Qt.locale(Settings.formatsLocale || I18n.locale.name)
            readonly property var now: new Date()

            GridLayout {
                id: previewGrid
                anchors.fill: parent
                anchors.leftMargin: Design.s(Design.space.rowPaddingX)
                anchors.rightMargin: Design.s(Design.space.rowPaddingX)
                anchors.topMargin: Design.s(Design.space.sm)
                anchors.bottomMargin: Design.s(Design.space.sm)
                columns: 2
                columnSpacing: Design.s(Design.space.lg)
                rowSpacing: Design.s(Design.space.xs)

                Label { text: I18n.tr("Date"); role: "footnote"; dim: true }
                Label { text: previewBox.preview.toString(previewBox.now, previewBox.preview.dateFormat(Locale.LongFormat)); role: "footnote" }

                Label { text: I18n.tr("Short date and time"); role: "footnote"; dim: true }
                Label { text: previewBox.preview.toString(previewBox.now, previewBox.preview.dateTimeFormat(Locale.ShortFormat)); role: "footnote" }

                Label { text: I18n.tr("Number"); role: "footnote"; dim: true }
                Label { text: Number(1234567.89).toLocaleString(previewBox.preview, "f", 2); role: "footnote"; tabular: true }

                Label { text: I18n.tr("Money"); role: "footnote"; dim: true }
                Label { text: Number(1234.5).toLocaleCurrencyString(previewBox.preview); role: "footnote"; tabular: true }
            }
        }
    }
}
