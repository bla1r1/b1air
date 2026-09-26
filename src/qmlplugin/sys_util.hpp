#pragma once

// =============================================================================
// Sys — the few things the shell asked bash for, done in-process.
//
// About twenty places ran `bash -c` (or `sh -c`) to write a line to a file,
// read one, remove one, list a directory or ask whether a program is
// installed — a process each, a script string each, and a quoting mistake
// away from running something it should not. These are those operations, as
// plain calls on files and directories. "~/" at the start of a path is the
// home directory, as it was in the scripts.
//
//   Sys.writeFile("~/.cache/qs_screenshot_mode", "true")
//   const text = Sys.readFile("/proc/uptime")
//   if (Sys.commandExists("powerprofilesctl")) ...
// =============================================================================

#include <QObject>
#include <QString>
#include <QStringList>

class SysUtil : public QObject {
    Q_OBJECT
public:
    using QObject::QObject;

    /** The file's text; "" when it cannot be read. Capped at `maxBytes`. */
    Q_INVOKABLE static QString readFile(const QString& path, int maxBytes = 4 * 1024 * 1024);
    /** Written whole (temporary file, then renamed), parent made if needed. */
    Q_INVOKABLE static bool writeFile(const QString& path, const QString& text);
    Q_INVOKABLE static bool removeFile(const QString& path);
    Q_INVOKABLE static bool makeDir(const QString& path);
    Q_INVOKABLE static bool exists(const QString& path);
    /** Names in a directory, without "." and "..". */
    Q_INVOKABLE static QStringList listDir(const QString& path);
    /** Whether `name` is an executable somewhere on PATH. */
    Q_INVOKABLE static bool commandExists(const QString& name);

    /**
     * A desktop notification, sent over D-Bus as notify-send would. Not
     * waited on: in the shell, the notification server is this process.
     * urgency: "low", "normal", "critical"; timeoutMs -1 lets the server pick.
     */
    Q_INVOKABLE static void notify(const QString& app, const QString& title,
                                   const QString& body = QString(), const QString& icon = QString(),
                                   const QString& urgency = QString(), int timeoutMs = -1);

    static QString expand(const QString& path);
};
