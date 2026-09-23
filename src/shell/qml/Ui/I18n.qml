pragma Singleton

import QtQuick

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
// The language is the system's: LANGUAGE / LC_MESSAGES / LANG, which Qt
// reports as Qt.uiLanguage. `LANG=ru_RU.UTF-8 b1air-files` tries one out.
QtObject {
    id: root

    readonly property string language:
        String(Qt.uiLanguage || Qt.locale().name || "en").split(/[_.@-]/)[0].toLowerCase()

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

    function load() {
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
