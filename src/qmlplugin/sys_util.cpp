#include "sys_util.hpp"

#include <QDBusConnection>
#include <QDBusMessage>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QSaveFile>
#include <QStandardPaths>

QString SysUtil::expand(const QString& path) {
    if (path == QLatin1String("~")) return QDir::homePath();
    if (path.startsWith(QLatin1String("~/"))) return QDir::homePath() + path.mid(1);
    return path;
}

QString SysUtil::readFile(const QString& path, int maxBytes) {
    QFile f(expand(path));
    if (!f.open(QIODevice::ReadOnly | QIODevice::Unbuffered)) return {};
    // /proc and /sys report size 0, so read until the end, in pieces: one
    // read of the whole cap is refused outright by /proc/sys, which sizes a
    // kernel buffer by the request (osrelease and hostname came back empty).
    const qint64 cap = maxBytes > 0 ? maxBytes : 4 * 1024 * 1024;
    QByteArray data;
    char chunk[65536];
    while (data.size() < cap) {
        const qint64 n = f.read(chunk, qMin<qint64>(sizeof chunk, cap - data.size()));
        if (n <= 0) break;
        data.append(chunk, n);
    }
    return QString::fromUtf8(data);
}

bool SysUtil::writeFile(const QString& path, const QString& text) {
    const QString p = expand(path);
    QDir().mkpath(QFileInfo(p).absolutePath());
    QSaveFile f(p);
    if (!f.open(QIODevice::WriteOnly)) return false;
    f.write(text.toUtf8());
    return f.commit();
}

bool SysUtil::removeFile(const QString& path) {
    const QString p = expand(path);
    return !QFileInfo::exists(p) || QFile::remove(p);
}

bool SysUtil::makeDir(const QString& path) {
    return QDir().mkpath(expand(path));
}

bool SysUtil::exists(const QString& path) {
    return QFileInfo::exists(expand(path));
}

QStringList SysUtil::listDir(const QString& path) {
    return QDir(expand(path)).entryList(QDir::AllEntries | QDir::NoDotAndDotDot | QDir::System);
}

void SysUtil::notify(const QString& app, const QString& title, const QString& body,
                     const QString& icon, const QString& urgency, int timeoutMs) {
    QDBusMessage m = QDBusMessage::createMethodCall(
        "org.freedesktop.Notifications", "/org/freedesktop/Notifications",
        "org.freedesktop.Notifications", "Notify");
    QVariantMap hints;
    if (!urgency.isEmpty())
        hints.insert("urgency", QVariant::fromValue<uchar>(
            urgency == QLatin1String("low") ? 0 : urgency == QLatin1String("critical") ? 2 : 1));
    m << app << 0u << icon << title << body << QStringList() << hints << timeoutMs;
    QDBusConnection::sessionBus().send(m);
}

bool SysUtil::commandExists(const QString& name) {
    if (name.isEmpty() || name.contains('/')) return QFileInfo(name).isExecutable();
    return !QStandardPaths::findExecutable(name).isEmpty();
}
