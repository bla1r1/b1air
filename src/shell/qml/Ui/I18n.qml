pragma Singleton

import QtQuick
import QtCore

// Translations, for the apps and the shell alike.
//
// Qt's own route (qsTr, .ts, .qm, a QTranslator installed by main()) cannot
// reach the shell: it runs inside the quickshell binary, which installs no
// translator of ours. So the strings are looked up here, from a JSON file per
// language next to this one — i18n/ru.json — read the way Design reads the
// theme: XMLHttpRequest, plain Qt, works in every process of the suite.
//
//   text: I18n.tr("Move to Trash")
//   text: I18n.tr("Rename %1 items", count)
//
// The English string is the key. A string with no translation, or a language
// with no file, shows the English — never an empty label.
//
// English is not a file: it is the strings in the code, the keys above.
//
// The language is the one picked in Settings → Language & Region (uiLanguage
// in settings.json), else the system's: LANGUAGE / LC_MESSAGES / LANG, which
// Qt reports as Qt.uiLanguage — when there is a translation for it. A system
// in German, which has none, gets English, the formats included: it used to
// get English words with German dates beside them. Formats (dates, numbers)
// follow formatsLocale when one is picked, else the interface language.
// `LANG=uk_UA.UTF-8 b1air-files` tries one out. A change applies to what
// starts afterwards: the shell restarts for it, an app when opened again.
QtObject {
    id: root

    // The system's language for messages: LANGUAGE, LC_MESSAGES, LANG, as
    // the system locale's uiLanguages reports them. Qt.uiLanguage is a
    // property nobody sets (empty), and Qt.locale().name follows LC_TIME and
    // the other formats, so a German LANG with English formats read as English.
    readonly property string systemLanguage:
        String(Qt.uiLanguage || (Qt.locale().uiLanguages || [])[0] || Qt.locale().name || "en")
            .split(/[_.@-]/)[0].toLowerCase()
    property string language: root.systemLanguage
    // The languages there is a file for, beside English.
    readonly property var translated: ["uk", "ru"]
    // Dates and numbers: Settings' formatsLocale, or the interface language's.
    property string formats: ""

    // Filled once at startup; bindings that call tr() re-run when it lands.
    property var dict: ({})

    function tr(text, ...args) {
        let s = root.dict[text];
        if (typeof s !== "string" || s === "") s = String(text);
        return root._fill(s, args);
    }

    // Counted strings: I18n.trn("%1 item", "%1 items", n). English picks by
    // n === 1; a translation can be one string or an array of plural forms —
    // for Russian three: [1 элемент, 2 элемента, 5 элементов]. %1 is n, and
    // any further arguments are %2, %3…
    function trn(singular, plural, n, ...args) {
        const forms = root.dict[plural];
        let s;
        if (Array.isArray(forms) && forms.length > 0) s = forms[Math.min(forms.length - 1, root._pluralIndex(n))];
        else if (typeof forms === "string" && forms !== "") s = forms;
        else s = n === 1 ? singular : plural;
        return root._fill(s, [n].concat(args));
    }

    // A date in the interface's language, whatever the system's is:
    // I18n.date(d, "dddd, MMMM d, yyyy"). The pattern is a key too, so a
    // language can put the day before the month.
    // The interface language's locale, for anything that names a day, a
    // month or AM/PM. Qt.locale() with no argument is the system's, so an
    // English desktop on a Ukrainian system wrote "дп" after the clock.
    readonly property var locale: Qt.locale(root.formats !== "" ? root.formats : root._regionOf(root.language))

    // The usual region of a language, for its dates and numbers. English is
    // the system's own English when it is one (en_GB keeps its dates), else
    // the United States'.
    function _regionOf(lang) {
        const sys = String(Qt.locale().name || "");
        if (sys.split("_")[0] === lang) return sys;
        return ({ en: "en_US", uk: "uk_UA", ru: "ru_RU" })[lang] || "en_US";
    }

    function date(d, pattern) {
        return root.locale.toString(d, root.tr(pattern));
    }

    // CLDR's rule for Russian, Ukrainian and Belarusian; anything else with
    // forms gets one/other.
    function _pluralIndex(n) {
        n = Math.abs(Math.floor(n));
        if (["ru", "uk", "be"].indexOf(root.language) >= 0) {
            if (n % 10 === 1 && n % 100 !== 11) return 0;
            if (n % 10 >= 2 && n % 10 <= 4 && (n % 100 < 12 || n % 100 > 14)) return 1;
            return 2;
        }
        return n === 1 ? 0 : 1;
    }

    function _fill(s, args) {
        for (let i = 0; i < args.length; ++i)
            s = s.split("%" + (i + 1)).join(String(args[i]));
        return s;
    }

    // uiLanguage from settings.json, "" when unset or "auto".
    function _chosen() {
        const xhr = new XMLHttpRequest();
        try {
            const dir = String(StandardPaths.writableLocation(StandardPaths.ConfigLocation));
            xhr.open("GET", dir + "/sway/settings.json", false);
            xhr.send();
            if ((xhr.status === 0 || xhr.status === 200) && xhr.responseText) {
                const j = JSON.parse(xhr.responseText);
                root.formats = String(j.formatsLocale || "");
                const v = String(j.uiLanguage || "");
                return v === "auto" ? "" : v;
            }
        } catch (e) {
            // No settings yet, or file reads are not allowed here: the system's.
        }
        return "";
    }

    function load() {
        const chosen = root._chosen();
        root.language = chosen || root.systemLanguage;
        if (root.translated.indexOf(root.language) < 0) root.language = "en";
        if (root.language === "en") return;
        const xhr = new XMLHttpRequest();
        try {
            xhr.open("GET", Qt.resolvedUrl("i18n/" + root.language + ".json"), false);
            xhr.send();
            if ((xhr.status === 0 || xhr.status === 200) && xhr.responseText)
                root.dict = JSON.parse(xhr.responseText);
        } catch (e) {
            // No file for this language: English stays.
        }
    }

    Component.onCompleted: load()
}
