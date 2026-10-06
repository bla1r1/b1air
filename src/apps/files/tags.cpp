#include "tags.hpp"

#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>
#include <QStandardPaths>
#include <sys/xattr.h>

namespace b1air::tags {

namespace {

constexpr const char* kAttr = "user.xdg.tags";

QString indexPath() {
    return QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation) + "/b1air/tags.json";
}

QJsonObject loadIndex() {
    QFile f(indexPath());
    if (!f.open(QIODevice::ReadOnly)) return {};
    return QJsonDocument::fromJson(f.readAll()).object();
}

void saveIndex(const QJsonObject& index) {
    QDir().mkpath(QFileInfo(indexPath()).absolutePath());
    QSaveFile f(indexPath());
    if (!f.open(QIODevice::WriteOnly)) return;
    f.write(QJsonDocument(index).toJson(QJsonDocument::Compact));
    f.commit();
}

} // namespace

const QStringList& colours() {
    static const QStringList list{"Red", "Orange", "Yellow", "Green", "Blue", "Purple", "Gray"};
    return list;
}

QStringList read(const QString& path) {
    const QByteArray p = QFile::encodeName(path);
    char buf[1024];
    const ssize_t n = getxattr(p.constData(), kAttr, buf, sizeof(buf));
    if (n <= 0) return {};
    QStringList out;
    for (const QString& t : QString::fromUtf8(buf, int(n)).split(',', Qt::SkipEmptyParts))
        if (!t.trimmed().isEmpty()) out << t.trimmed();
    return out;
}

bool write(const QString& path, const QStringList& tags) {
    const QByteArray p = QFile::encodeName(path);
    if (tags.isEmpty()) {
        return removexattr(p.constData(), kAttr) == 0 || errno == ENODATA;
    }
    const QByteArray value = tags.join(',').toUtf8();
    return setxattr(p.constData(), kAttr, value.constData(), size_t(value.size()), 0) == 0;
}

bool toggle(const QStringList& paths, const QString& tag) {
    if (paths.isEmpty() || tag.isEmpty()) return false;
    bool all = true;
    for (const QString& p : paths)
        if (!read(p).contains(tag)) { all = false; break; }
    QJsonObject index = loadIndex();
    QJsonArray list = index.value(tag).toArray();
    bool ok = true;
    for (const QString& p : paths) {
        QStringList t = read(p);
        if (all) t.removeAll(tag);
        else if (!t.contains(tag)) t << tag;
        ok = write(p, t) && ok;
        // The index: add or drop this path under the tag.
        for (int i = list.size() - 1; i >= 0; --i)
            if (list.at(i).toString() == p) list.removeAt(i);
        if (!all) list.append(p);
    }
    index.insert(tag, list);
    saveIndex(index);
    return ok;
}

QStringList pathsWith(const QString& tag) {
    QJsonObject index = loadIndex();
    const QJsonArray list = index.value(tag).toArray();
    QStringList out;
    QJsonArray kept;
    for (const QJsonValue& v : list) {
        const QString p = v.toString();
        if (QFileInfo::exists(p) && read(p).contains(tag) && !out.contains(p)) {
            out << p;
            kept.append(p);
        }
    }
    if (kept.size() != list.size()) {
        index.insert(tag, kept);
        saveIndex(index);
    }
    return out;
}

QVariantMap counts() {
    QVariantMap out;
    for (const QString& c : colours()) out[c] = int(pathsWith(c).size());
    return out;
}

} // namespace b1air::tags
