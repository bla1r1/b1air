.pragma library
// The few words on the login screen, in the languages the desktop speaks.
// sddm's own TextConstants are left alone: they are long, and English
// wherever sddm was built without its translations.

const words = {
    ru: {
        "Enter password": "Введите пароль",
        "Wrong password": "Неверный пароль",
        "Logging in…": "Вход…",
        "Log in": "Войти",
        "Caps Lock is on": "Включён Caps Lock",
        "Sleep": "Сон",
        "Restart": "Перезагрузить",
        "Shut down": "Выключить",
        "Users": "Пользователи",
    },
    uk: {
        "Enter password": "Введіть пароль",
        "Wrong password": "Неправильний пароль",
        "Logging in…": "Вхід…",
        "Log in": "Увійти",
        "Caps Lock is on": "Увімкнено Caps Lock",
        "Sleep": "Сон",
        "Restart": "Перезавантажити",
        "Shut down": "Вимкнути",
        "Users": "Користувачі",
    },
};

function tr(lang, text) {
    const w = words[lang];
    return w && w[text] ? w[text] : text;
}
