#pragma once

// Where an app's QML comes from, decided once.
//
// All seven apps carried their own copy of this policy and no two agreed.
// b1air-git and b1air-notes looked in a source checkout and then in
// /usr/share/b1air-<app>/, never in ~/.config/b1air-shell — which is where
// install.sh actually puts the QML — so on a machine without a checkout they
// loaded a file nothing installs. The other five looked in four places, in an
// order that put the checkout first.
//
// A checkout first is right while developing and wrong everywhere else:
// anyone who cloned the repo once had ~/DotsFiles silently override every
// later update, with nothing on screen to say an old file was being drawn.
// (It happened here: a stale ~/DotsFiles kept serving b1air-monitor an old
// MonitorWindow.qml while the installed copy sat unused.) The checkout is
// consulted only when B1AIR_DEV_MODE=1 asks for it.

#include <QDir>
#include <QFile>
#include <QLibraryInfo>
#include <QQmlApplicationEngine>
#include <QString>
#include <QStringList>

namespace b1air {
namespace app {

inline bool dev_mode() {
    return qEnvironmentVariable("B1AIR_DEV_MODE") == QLatin1String("1");
}

/**
 * Directories holding Ui/, Services/ and the window files, most-preferred
 * first. `app_dir` is the app's own folder under src/apps, used only in dev
 * mode; pass an empty string for an app with no private QML.
 */
inline QStringList qml_dirs(const QString& app_dir) {
    const QString home = QDir::homePath();
    QStringList dirs;
    if (dev_mode()) {
        dirs << home + "/DotsFiles/src/shell/qml";
        if (!app_dir.isEmpty())
            dirs << home + "/DotsFiles/src/apps/" + app_dir;
    }
    dirs << home + "/.config/b1air-shell"
         << home + "/.config/quickshell"
         << "/usr/share/b1air-shell/qml"
         // Qt's own QML directory: /usr/lib/qt6/qml on Arch, but under
         // /usr/lib/<triplet> on Debian and /usr/lib64 on Fedora/openSUSE.
         << QLibraryInfo::path(QLibraryInfo::QmlImportsPath);
    return dirs;
}

/** The window file itself, or an empty string when nothing provides it. */
inline QString find_window_qml(const QString& file_name, const QString& app_dir) {
    for (const QString& dir : qml_dirs(app_dir)) {
        const QString candidate = dir + "/" + file_name;
        if (QFile::exists(candidate))
            return candidate;
    }
    return QString();
}

inline void add_import_paths(QQmlApplicationEngine& engine, const QString& app_dir) {
    // addImportPath() prepends, so the last one added is searched first:
    // walk the preference list backwards to end up with it in order.
    const QStringList dirs = qml_dirs(app_dir);
    for (auto it = dirs.crbegin(); it != dirs.crend(); ++it)
        engine.addImportPath(*it);
}

} // namespace app
} // namespace b1air
