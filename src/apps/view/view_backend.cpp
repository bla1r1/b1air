#include "view_backend.hpp"
#include <QCollator>
#include <QDateTime>
#include <QHash>
#include <QMimeDatabase>
#include <QSet>
#include <QProcess>
#include <algorithm>

ViewBackend::ViewBackend(QObject* parent) : QObject(parent) {}

void ViewBackend::openFile(const QString& filePath) {
    QFileInfo fi(filePath);
    if (!fi.exists() || !fi.isFile()) return;

    m_currentPath = fi.absoluteFilePath();
    // Another file of the folder already listed — a click in the strip, the
    // next song of the album — is a step along the list. It used to read the
    // folder again and hand QML a new list, which threw away and remade
    // every thumbnail in the strip on each click.
    const int at = m_imageList.indexOf(m_currentPath);
    if (at >= 0) m_currentIndex = at;
    else scanDirectory(fi.absolutePath(), m_currentPath);
    updateFileInfo();
}

namespace {

// Formats by MIME type, not by a list of extensions: whatever ffmpeg plays
// (the multimedia backend is ffmpeg) and whatever image plugin is installed
// (qt6-imageformats, kimageformats) opens, without this file naming them.
const QSet<QString> kVideoApps{
    "application/vnd.rn-realmedia", "application/vnd.ms-asf", "application/mxf",
    "application/x-matroska", "application/ogg", "application/x-shockwave-flash",
};
// audio/* that is not a sound: playlists and cue sheets name other files;
// MIDI and tracker formats ffmpeg is not built to play everywhere.
const QSet<QString> kNotAudio{
    "audio/x-mpegurl", "audio/mpegurl", "audio/x-scpls", "audio/x-ms-asx", "audio/x-iriver-pla",
    "audio/midi", "audio/x-midi", "audio/prs.sid",
};

QString kindForMime(const QMimeType& mt) {
    static QHash<QString, QString> known;
    const QString name = mt.name();
    const auto it = known.constFind(name);
    if (it != known.cend()) return *it;

    QString kind;
    if (name.startsWith(u"video/") || kVideoApps.contains(name)) {
        kind = QStringLiteral("video");
    } else if (name.startsWith(u"audio/")) {
        if (!kNotAudio.contains(name)) kind = QStringLiteral("audio");
    } else if (name.startsWith(u"image/")) {
        static const QList<QByteArray> readable = QImageReader::supportedMimeTypes();
        for (const QByteArray& r : readable)
            if (mt.inherits(QString::fromLatin1(r))) { kind = QStringLiteral("image"); break; }
    }
    known.insert(name, kind);
    return kind;
}

} // namespace

QString ViewBackend::kindOf(const QFileInfo& fi, bool sniff) {
    static const QMimeDatabase db;
    // The name alone for a folder full of files; the contents too for the one
    // opened, which may have no extension at all.
    QString kind = kindForMime(db.mimeTypeForFile(fi, QMimeDatabase::MatchExtension));
    if (kind.isEmpty() && sniff) kind = kindForMime(db.mimeTypeForFile(fi));
    return kind;
}

QString ViewBackend::nextOfKind() const {
    for (int i = m_currentIndex + 1; i < m_imageList.size(); ++i)
        if (m_kinds[i] == m_kind) return m_imageList[i];
    return {};
}

void ViewBackend::scanDirectory(const QString& dirPath, const QString& currentFile) {
    // Pictures, films and music: the window shows the first and plays the
    // other two, and the arrows go through all of them in the folder.
    QDir dir(dirPath);
    dir.setFilter(QDir::Files);
    QFileInfoList list = dir.entryInfoList();
    // In the order a person counts: "2 - Song" before "10 - Song", as the
    // tracks of an album are numbered.
    QCollator collator;
    collator.setNumericMode(true);
    collator.setCaseSensitivity(Qt::CaseInsensitive);
    std::sort(list.begin(), list.end(), [&](const QFileInfo& a, const QFileInfo& b) {
        return collator.compare(a.fileName(), b.fileName()) < 0;
    });

    m_imageList.clear();
    m_kinds.clear();
    m_filesInDir.clear();
    m_currentIndex = -1;

    for (const QFileInfo& fi : list) {
        const QString path = fi.absoluteFilePath();
        const bool current = path == currentFile;
        const QString kind = kindOf(fi, current);
        if (kind.isEmpty()) continue;
        if (current) m_currentIndex = m_imageList.size();
        m_imageList.append(path);
        m_kinds.append(kind);

        QVariantMap item;
        item["path"] = path;
        item["name"] = fi.fileName();
        item["kind"] = kind;
        m_filesInDir.append(item);
    }

    if (m_currentIndex == -1 && !m_imageList.isEmpty()) {
        m_currentIndex = 0;
        m_currentPath = m_imageList[0];
    }

    emit directoryChanged();
}

void ViewBackend::updateFileInfo() {
    if (m_currentPath.isEmpty()) return;

    QFileInfo fi(m_currentPath);
    m_fileName = fi.fileName();
    
    qint64 bytes = fi.size();
    if (bytes > 1024 * 1024) {
        m_fileSize = QString::number(bytes / (1024.0 * 1024.0), 'f', 2) + " MB";
    } else {
        m_fileSize = QString::number(bytes / 1024.0, 'f', 1) + " KB";
    }

    m_kind = m_currentIndex >= 0 ? m_kinds[m_currentIndex] : kindOf(fi, true);
    // A film's size is the player's to tell (QML reads it from the stream).
    QSize sz;
    m_animated = false;
    if (m_kind == u"image") {
        QImageReader reader(m_currentPath);
        sz = reader.size();
        if (reader.transformation() & QImageIOHandler::TransformationRotate90) sz.transpose();
        m_animated = reader.supportsAnimation() && reader.imageCount() > 1;
    }
    m_imageSize = sz;
    m_resolution = sz.isValid() ? QString("%1 × %2").arg(sz.width()).arg(sz.height()) : QString();

    emit currentPathChanged();
    emit fileChanged();
}

void ViewBackend::next() {
    if (hasNext()) {
        m_currentIndex++;
        m_currentPath = m_imageList[m_currentIndex];
        updateFileInfo();
    }
}

void ViewBackend::previous() {
    if (hasPrevious()) {
        m_currentIndex--;
        m_currentPath = m_imageList[m_currentIndex];
        updateFileInfo();
    }
}

void ViewBackend::setWallpaper() {
    if (m_currentPath.isEmpty()) return;
    // Was: a "wallpaper <path>" call the daemon does not accept (the verb is
    // "wallpaper set <path>"), plus a raw swaybg spawn that stacked a new
    // instance on every use without killing the previous one.
    QProcess::startDetached("b1air-daemon", QStringList() << "wallpaper" << "set" << m_currentPath);
}

QVariantMap ViewBackend::getMetadata() {
    QVariantMap meta;
    if (m_currentPath.isEmpty()) return meta;

    QFileInfo fi(m_currentPath);
    meta["fileName"] = fi.fileName();
    meta["path"] = fi.absoluteFilePath();
    meta["size"] = m_fileSize;
    meta["resolution"] = m_resolution;
    meta["created"] = fi.birthTime().toString("yyyy-MM-dd HH:mm:ss");
    meta["modified"] = fi.lastModified().toString("yyyy-MM-dd HH:mm:ss");

    QImageReader reader(m_currentPath);
    meta["format"] = QString::fromLatin1(reader.format()).toUpper();

    return meta;
}
