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
// The language is the one picked in Settings → Keyboard → Interface language
// (uiLanguage in settings.json), else the system's: LANGUAGE / LC_MESSAGES /
// LANG, which Qt reports as Qt.uiLanguage. `LANG=uk_UA.UTF-8 b1air-files`
// tries one out. A change applies to what starts afterwards: the shell
// restarts for it, and an app when it is opened again.
QtObject {
    id: root

    readonly property string systemLanguage:
        String(Qt.uiLanguage || Qt.locale().name || "en").split(/[_.@-]/)[0].toLowerCase()
    property string language: root.systemLanguage

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
    function date(d, pattern) {
        return Qt.locale(root.language).toString(d, root.tr(pattern));
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
                const v = String(JSON.parse(xhr.responseText).uiLanguage || "");
                return v === "auto" ? "" : v;
            }
        } catch (e) {
            // No settings yet, or file reads are not allowed here: the system's.
        }
        return "";
    }

    function load() {
        root.language = root._chosen() || root.systemLanguage;
        if (root.language === "en" || root.language === "c" || root.language === "posix") return;
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
