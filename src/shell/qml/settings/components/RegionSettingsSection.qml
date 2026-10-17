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
    // Rows with a list each, as Windows and KDE lay it out. These were three
    // cards of pills, one per installed locale every time.
    Card {
        title: I18n.tr("Language")
        subtitle: I18n.tr("What this desktop and other programs speak")
        icon: "\u{f05ca}"

        FormRow {
            title: I18n.tr("Interface language")
            subtitle: I18n.tr("Menus, settings and apps of this desktop; the shell restarts to switch")
            Dropdown {
                model: [
                    { id: "auto", label: I18n.tr("Like the system") },
                    { id: "en",   label: "English",    detail: "en" },
                    { id: "uk",   label: "Українська", detail: "uk" },
                    { id: "ru",   label: "Русский",    detail: "ru" }
                ]
                current: Settings.uiLanguage || "auto"
                onPicked: id => section.setUiLanguage(id)
            }
        }
        Label {
            Layout.fillWidth: true
            readonly property string sys: I18n.systemLanguage
            visible: (Settings.uiLanguage || "auto") === "auto" && I18n.translated.indexOf(sys) < 0 && sys !== "en"
            text: I18n.tr("The system is in %1, which has no translation here: English is used, dates included.", Qt.locale(sys).nativeLanguageName || sys)
            role: "caption"; dim: true; wrapMode: Text.WordWrap
        }

        FormRow {
            title: I18n.tr("System language")
            subtitle: I18n.tr("What other programs speak: the browser, GTK and Qt apps. From the next login")
            Dropdown {
                model: [{
                    id: "__system",
                    label: section.defaultLang
                        ? I18n.tr("As the system: %1", section.nameOf(section.defaultLang))
                        : I18n.tr("As the system")
                }].concat(section.installedChoices)
                current: section.systemLang === "" ? "__system" : section.systemLang
                onPicked: id => section.setSystemLanguage(id)
            }
        }

        FormRow {
            title: I18n.tr("Add a language")
            subtitle: I18n.tr("A language has to be added to the system before it can be picked above. Needs the administrator password")
            visible: section.missing.length > 0 || section.adding !== ""
            Dropdown {
                model: section.missing.map(c => ({ id: c, label: section.nameOf(c), detail: c }))
                current: ""
                placeholder: section.adding !== ""
                    ? I18n.tr("Adding %1…", section.nameOf(section.adding))
                    : I18n.tr("Choose a language…")
                enabled: section.adding === ""
                onPicked: id => section.add(id)
            }
            Label {
                visible: section.addError !== "" && section.adding === ""
                Layout.fillWidth: true
                text: section.addError
                color: Design.danger
                role: "caption"; wrapMode: Text.WordWrap
            }
        }
    }

    // ── Region ───────────────────────────────────────────────────────────────
    Card {
        id: formatsCard
        title: I18n.tr("Region")
        subtitle: I18n.tr("Dates, times, numbers, money and units, here and in other programs")
        icon: "\u{f00f0}"

        FormRow {
            title: I18n.tr("Formats")
            subtitle: I18n.tr("Independent of the language: English menus with German dates is fine")
            Dropdown {
                model: [{ id: "__interface", label: I18n.tr("Like the interface language") }].concat(section.installedChoices)
                current: (Settings.formatsLocale || "") === "" ? "__interface" : Settings.formatsLocale
                onPicked: id => section.setFormats(id)
            }
        }

        // What it looks like, in the formats picked (before the restart too).
        readonly property var preview: Qt.locale(Settings.formatsLocale || I18n.locale.name)
        readonly property var now: new Date()
        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: Design.s(Design.space.lg)
            rowSpacing: Design.s(2)
            Label { text: I18n.tr("Date"); role: "caption"; dim: true }
            Label { text: formatsCard.preview.toString(formatsCard.now, formatsCard.preview.dateFormat(Locale.LongFormat)); role: "caption" }
            Label { text: I18n.tr("Short date and time"); role: "caption"; dim: true }
            Label { text: formatsCard.preview.toString(formatsCard.now, formatsCard.preview.dateTimeFormat(Locale.ShortFormat)); role: "caption" }
            Label { text: I18n.tr("Number"); role: "caption"; dim: true }
            Label { text: Number(1234567.89).toLocaleString(formatsCard.preview, "f", 2); role: "caption" }
            Label { text: I18n.tr("Money"); role: "caption"; dim: true }
            Label { text: Number(1234.5).toLocaleCurrencyString(formatsCard.preview); role: "caption" }
        }
    }
}
