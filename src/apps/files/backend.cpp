#include "backend.hpp"
#include <algorithm>
#include <QUrl>
#include <QDesktopServices>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>
#include <QStandardPaths>
#include <archive.h>
#include <archive_entry.h>

namespace b1air {

FileManagerBackend::FileManagerBackend(QObject* parent)
    : QObject(parent),
      m_historyIndex(-1),
      m_showHidden(false),
      m_filterQuery(""),
      m_viewMode("grid"),
      m_sortField("name"),
      m_sortAscending(true)
{
    QString home = QDir::homePath();
    setCurrentPath(home);
}

QString FileManagerBackend::currentPath() const {
    return m_currentPath;
}

void FileManagerBackend::setCurrentPath(const QString& path) {
    QDir dir(path);
    if (!dir.exists()) return;

    QString cleanPath = QDir::cleanPath(dir.canonicalPath());
    if (cleanPath.isEmpty()) cleanPath = path;

    if (m_currentPath != cleanPath) {
        m_currentPath = cleanPath;

        // Truncate forward history if navigating to a new path
        if (m_historyIndex >= 0 && m_historyIndex < m_history.size() - 1) {
            while (m_history.size() > m_historyIndex + 1) {
                m_history.removeLast();
            }
        }
        m_history.append(m_currentPath);
        m_historyIndex = m_history.size() - 1;

        emit currentPathChanged();
        emit historyChanged();
        refresh();
    }
}

bool FileManagerBackend::canGoBack() const {
    return m_historyIndex > 0;
}

bool FileManagerBackend::canGoForward() const {
    return m_historyIndex >= 0 && m_historyIndex < m_history.size() - 1;
}

void FileManagerBackend::historyBack() {
    if (canGoBack()) {
        m_historyIndex--;
        m_currentPath = m_history[m_historyIndex];
        emit currentPathChanged();
        emit historyChanged();
        refresh();
    }
}

void FileManagerBackend::historyForward() {
    if (canGoForward()) {
        m_historyIndex++;
        m_currentPath = m_history[m_historyIndex];
        emit currentPathChanged();
        emit historyChanged();
        refresh();
    }
}

void FileManagerBackend::goUp() {
    QDir dir(m_currentPath);
    if (dir.cdUp()) {
        setCurrentPath(dir.absolutePath());
    }
}

bool FileManagerBackend::showHidden() const {
    return m_showHidden;
}

void FileManagerBackend::setShowHidden(bool show) {
    if (m_showHidden != show) {
        m_showHidden = show;
        emit showHiddenChanged();
        refresh();
    }
}

QString FileManagerBackend::filterQuery() const {
    return m_filterQuery;
}

void FileManagerBackend::setFilterQuery(const QString& query) {
    if (m_filterQuery != query) {
        m_filterQuery = query;
        emit filterQueryChanged();
        refresh();
    }
}

QString FileManagerBackend::viewMode() const {
    return m_viewMode;
}

void FileManagerBackend::setViewMode(const QString& mode) {
    if (m_viewMode != mode) {
        m_viewMode = mode;
        emit viewModeChanged();
    }
}

QString FileManagerBackend::sortField() const {
    return m_sortField;
}

void FileManagerBackend::setSortField(const QString& field) {
    if (m_sortField != field) {
        m_sortField = field;
        emit sortChanged();
        refresh();
    }
}

bool FileManagerBackend::sortAscending() const {
    return m_sortAscending;
}

void FileManagerBackend::setSortAscending(bool asc) {
    if (m_sortAscending != asc) {
        m_sortAscending = asc;
        emit sortChanged();
        refresh();
    }
}

QVariantList FileManagerBackend::items() const {
    return m_items;
}

int FileManagerBackend::itemCount() const {
    return m_items.size();
}

QVariantList FileManagerBackend::breadcrumbs() const {
    QVariantList crumbs;
    QString home = QDir::homePath();

    if (m_currentPath.startsWith(home)) {
        QVariantMap homeCrumb;
        homeCrumb["name"] = "~";
        homeCrumb["path"] = home;
        crumbs.append(homeCrumb);

        QString rel = m_currentPath.mid(home.length());
        QStringList parts = rel.split('/', Qt::SkipEmptyParts);
        QString acc = home;
        for (const auto& part : parts) {
            acc += "/" + part;
            QVariantMap crumb;
            crumb["name"] = part;
            crumb["path"] = acc;
            crumbs.append(crumb);
        }
    } else {
        QVariantMap root;
        root["name"] = "/";
        root["path"] = "/";
        crumbs.append(root);

        QStringList parts = m_currentPath.split('/', Qt::SkipEmptyParts);
        QString acc = "";
        for (const auto& part : parts) {
            acc += "/" + part;
            QVariantMap crumb;
            crumb["name"] = part;
            crumb["path"] = acc;
            crumbs.append(crumb);
        }
    }
    return crumbs;
}

QVariantList FileManagerBackend::places() const {
    QVariantList list;
    QString home = QDir::homePath();

    auto addPlace = [&](const QString& name, const QString& path, const QString& glyph, const QString& color) {
        if (QDir(path).exists()) {
            QVariantMap p;
            p["name"] = name;
            p["path"] = path;
            p["glyph"] = glyph;
            p["color"] = color;
            list.append(p);
        }
    };

    addPlace("Home", home, "\u{f015}", "#7aa2f7");
    addPlace("Desktop", home + "/Desktop", "\u{f108}", "#7dcfff");
    addPlace("Documents", home + "/Documents", "\u{f02d}", "#bb9af7");
    addPlace("Downloads", home + "/Downloads", "\u{f019}", "#73daca");
    addPlace("Pictures", home + "/Pictures", "\u{f03e}", "#f7768e");
    addPlace("Music", home + "/Music", "\u{f001}", "#e0af68");
    addPlace("Videos", home + "/Videos", "\u{f008}", "#ff9e64");
    addPlace("File System", "/", "\u{f0a0}", "#c0caf5");

    return list;
}

QString FileManagerBackend::diskFreeSpace() const {
    QStorageInfo storage(m_currentPath);
    if (storage.isValid()) {
        return formatSize(storage.bytesAvailable()) + " free";
    }
    return "0 B free";
}

QString FileManagerBackend::diskTotalSpace() const {
    QStorageInfo storage(m_currentPath);
    if (storage.isValid()) {
        return formatSize(storage.bytesTotal());
    }
    return "0 B";
}

QString FileManagerBackend::formatSize(qint64 bytes) const {
    if (bytes < 1024) return QString("%1 B").arg(bytes);
    if (bytes < 1024 * 1024) return QString("%1 KB").arg(bytes / 1024.0, 0, 'f', 1);
    if (bytes < 1024 * 1024 * 1024) return QString("%1 MB").arg(bytes / (1024.0 * 1024.0), 0, 'f', 1);
    return QString("%1 GB").arg(bytes / (1024.0 * 1024.0 * 1024.0), 0, 'f', 1);
}

QString FileManagerBackend::getIconGlyph(const QFileInfo& fi) const {
    if (fi.isDir()) return "\u{f07b}"; // folder
    QString ext = fi.suffix().toLower();

    // Images
    if (ext == "png" || ext == "jpg" || ext == "jpeg" || ext == "webp" || ext == "gif" || ext == "svg" || ext == "bmp")
        return "\u{f03e}"; // image

    // Code & Scripts
    if (ext == "cpp" || ext == "hpp" || ext == "c" || ext == "h" || ext == "qml" || ext == "js" || ext == "ts" || ext == "py" || ext == "rs" || ext == "sh")
        return "\u{f121}"; // code

    // Documents & Text
    if (ext == "txt" || ext == "md" || ext == "json" || ext == "conf" || ext == "ini" || ext == "toml" || ext == "yaml" || ext == "yml")
        return "\u{f0f6}"; // file-text

    if (ext == "pdf") return "\u{f1c1}"; // pdf
    if (ext == "zip" || ext == "tar" || ext == "gz" || ext == "xz" || ext == "7z" || ext == "zst")
        return "\u{f1c6}"; // archive

    if (ext == "mp3" || ext == "flac" || ext == "wav" || ext == "ogg" || ext == "m4a")
        return "\u{f001}"; // audio

    if (ext == "mp4" || ext == "mkv" || ext == "webm" || ext == "mov" || ext == "avi")
        return "\u{f008}"; // video

    if (fi.isExecutable()) return "\u{f135}"; // rocket / binary

    return "\u{f016}"; // default file
}

QString FileManagerBackend::getIconColor(const QFileInfo& fi) const {
    if (fi.isDir()) return "#7aa2f7"; // blue
    QString ext = fi.suffix().toLower();

    if (ext == "png" || ext == "jpg" || ext == "jpeg" || ext == "webp" || ext == "gif" || ext == "svg")
        return "#f7768e"; // red/pink

    if (ext == "cpp" || ext == "hpp" || ext == "qml" || ext == "py" || ext == "rs" || ext == "sh" || ext == "js")
        return "#73daca"; // green

    if (ext == "txt" || ext == "md" || ext == "json" || ext == "conf" || ext == "ini" || ext == "toml")
        return "#c0caf5"; // text bright

    if (ext == "pdf") return "#ff9e64"; // orange
    if (ext == "zip" || ext == "tar" || ext == "gz" || ext == "7z")
        return "#e0af68"; // yellow

    if (ext == "mp3" || ext == "flac" || ext == "wav")
        return "#bb9af7"; // purple

    if (ext == "mp4" || ext == "mkv")
        return "#7dcfff"; // cyan

    if (fi.isExecutable()) return "#9ece6a";

    return "#a9b1d6";
}

void FileManagerBackend::refresh() {
    loadDirectory();
    emit diskInfoChanged();
}

void FileManagerBackend::loadDirectory() {
    QDir dir(m_currentPath);
    if (!dir.exists()) return;

    QDir::Filters filters = QDir::AllEntries | QDir::NoDotAndDotDot;
    if (m_showHidden) {
        filters |= QDir::Hidden;
    }

    QFileInfoList entryList = dir.entryInfoList(filters);
    QVariantList res;

    QString q = m_filterQuery.trimmed().toLower();

    for (const QFileInfo& fi : entryList) {
        QString name = fi.fileName();
        if (!q.isEmpty() && !name.toLower().contains(q)) {
            continue;
        }

        QString ext = fi.suffix().toLower();
        bool isImg = (ext == "png" || ext == "jpg" || ext == "jpeg" || ext == "webp" || ext == "gif" || ext == "bmp" || ext == "svg");
        bool isVid = (ext == "mp4" || ext == "mkv" || ext == "webm" || ext == "mov" || ext == "avi");

        QVariantMap item;
        item["name"] = name;
        item["path"] = fi.absoluteFilePath();
        item["url"] = QUrl::fromLocalFile(fi.absoluteFilePath()).toString();
        item["isDir"] = fi.isDir();
        item["isImage"] = isImg;
        item["isVideo"] = isVid;
        item["size"] = fi.isDir() ? 0 : fi.size();
        item["sizeFormatted"] = fi.isDir() ? "Folder" : formatSize(fi.size());
        item["mtime"] = fi.lastModified().toSecsSinceEpoch();
        item["mtimeFormatted"] = fi.lastModified().toString("MMM d, yyyy  hh:mm");
        item["glyph"] = getIconGlyph(fi);
        item["color"] = getIconColor(fi);

        res.append(item);
    }

    // Sort: Folders always first, then by field
    std::sort(res.begin(), res.end(), [this](const QVariant& a, const QVariant& b) {
        QVariantMap ma = a.toMap();
        QVariantMap mb = b.toMap();

        bool dirA = ma["isDir"].toBool();
        bool dirB = mb["isDir"].toBool();

        if (dirA != dirB) {
            return dirA; // Directory comes first
        }

        if (m_sortField == "size") {
            qint64 sa = ma["size"].toLongLong();
            qint64 sb = mb["size"].toLongLong();
            return m_sortAscending ? (sa < sb) : (sa > sb);
        } else if (m_sortField == "mtime") {
            qint64 ta = ma["mtime"].toLongLong();
            qint64 tb = mb["mtime"].toLongLong();
            return m_sortAscending ? (ta < tb) : (ta > tb);
        } else {
            QString na = ma["name"].toString().toLower();
            QString nb = mb["name"].toString().toLower();
            return m_sortAscending ? (na < nb) : (na > nb);
        }
    });

    m_items = res;
    emit itemsChanged();
}

void FileManagerBackend::openItem(const QString& path) {
    QFileInfo fi(path);
    if (fi.isDir()) {
        setCurrentPath(fi.absoluteFilePath());
    } else if (isArchive(path)) {
        // Mirrors Finder/Explorer: double-clicking an archive extracts it
        // next to itself instead of asking what app should open it.
        extractArchive(path);
    } else {
        QProcess::startDetached("xdg-open", QStringList() << path);
    }
}

bool FileManagerBackend::isArchive(const QString& path) const {
    const QString name = QFileInfo(path).fileName().toLower();
    static const QStringList suffixes = {
        ".tar.gz", ".tar.xz", ".tar.bz2", ".tar.zst", ".tgz", ".txz", ".tbz2",
        ".zip", ".tar", ".gz", ".xz", ".bz2", ".7z", ".zst", ".rar"
    };
    for (const QString& s : suffixes) {
        if (name.endsWith(s)) return true;
    }
    return false;
}

// Strips one of the recognized archive suffixes so "project.tar.gz" suggests
// "project" rather than "project.tar".
static QString stripArchiveSuffix(const QString& fileName) {
    static const QStringList suffixes = {
        ".tar.gz", ".tar.xz", ".tar.bz2", ".tar.zst", ".tgz", ".txz", ".tbz2",
        ".zip", ".tar", ".gz", ".xz", ".bz2", ".7z", ".zst", ".rar"
    };
    for (const QString& s : suffixes) {
        if (fileName.endsWith(s, Qt::CaseInsensitive)) {
            return fileName.left(fileName.size() - s.size());
        }
    }
    return fileName;
}

QString FileManagerBackend::uniqueExtractDir(const QFileInfo& archive) const {
    QString base = stripArchiveSuffix(archive.fileName());
    if (base.isEmpty()) base = "Archive";

    QDir parent = archive.absoluteDir();
    QString candidate = base;
    int n = 2;
    while (parent.exists(candidate)) {
        candidate = QString("%1 (%2)").arg(base).arg(n++);
    }
    return parent.absoluteFilePath(candidate);
}

// Extracts every entry via libarchive, refusing anything that would escape
// destDir (a "zip slip" path like "../../etc/passwd" inside the archive).
bool FileManagerBackend::extractWithLibarchive(const QString& archivePath, const QString& destDir, QString* error) {
    struct archive* a = archive_read_new();
    archive_read_support_filter_all(a);
    archive_read_support_format_all(a);

    struct archive* ext = archive_write_disk_new();
    archive_write_disk_set_options(ext, ARCHIVE_EXTRACT_TIME | ARCHIVE_EXTRACT_PERM |
                                            ARCHIVE_EXTRACT_ACL | ARCHIVE_EXTRACT_FFLAGS);

    bool ok = true;
    if (archive_read_open_filename(a, archivePath.toLocal8Bit().constData(), 10240) != ARCHIVE_OK) {
        if (error) *error = QString::fromUtf8(archive_error_string(a));
        ok = false;
    }

    const QString destCanonical = QDir(destDir).canonicalPath() + "/";

    while (ok) {
        struct archive_entry* entry;
        int r = archive_read_next_header(a, &entry);
        if (r == ARCHIVE_EOF) break;
        if (r != ARCHIVE_OK) {
            if (error) *error = QString::fromUtf8(archive_error_string(a));
            ok = false;
            break;
        }

        QString entryPath = QString::fromUtf8(archive_entry_pathname(entry));
        QString cleanFull = QDir::cleanPath(QDir(destDir).filePath(entryPath));
        if (cleanFull != QDir::cleanPath(destDir) && !(cleanFull + "/").startsWith(destCanonical)) {
            // Entry tries to write outside destDir (zip-slip) — skip it.
            continue;
        }
        archive_entry_set_pathname(entry, cleanFull.toLocal8Bit().constData());

        r = archive_write_header(ext, entry);
        if (r < ARCHIVE_OK && error) *error = QString::fromUtf8(archive_error_string(ext));
        if (r == ARCHIVE_FATAL) { ok = false; break; }

        if (archive_entry_size(entry) > 0) {
            const void* buf;
            size_t size;
            la_int64_t offset;
            while (true) {
                r = archive_read_data_block(a, &buf, &size, &offset);
                if (r == ARCHIVE_EOF) break;
                if (r != ARCHIVE_OK) { ok = false; break; }
                if (archive_write_data_block(ext, buf, size, offset) != ARCHIVE_OK) { ok = false; break; }
            }
        }
        archive_write_finish_entry(ext);
        if (!ok) break;
    }

    archive_read_close(a);
    archive_read_free(a);
    archive_write_close(ext);
    archive_write_free(ext);
    return ok;
}

bool FileManagerBackend::extractArchive(const QString& path) {
    QFileInfo fi(path);
    if (!fi.exists() || !fi.isFile()) return false;

    QString destDir = uniqueExtractDir(fi);
    QDir().mkpath(destDir);

    QString error;
    bool ok = extractWithLibarchive(path, destDir, &error);

    if (!ok) {
        // Fallback for whatever libarchive's build doesn't cover (e.g. some
        // rar variants) — bsdtar ships in the same libarchive package.
        QProcess proc;
        proc.start("bsdtar", QStringList() << "-xf" << path << "-C" << destDir);
        proc.waitForFinished(-1);
        ok = (proc.exitStatus() == QProcess::NormalExit && proc.exitCode() == 0);
    }

    if (ok) {
        refresh();
    } else {
        emit errorOccurred(tr("Couldn't extract \"%1\": %2").arg(fi.fileName(), error));
        QDir(destDir).removeRecursively();
    }
    return ok;
}

void FileManagerBackend::openTerminal(const QString& path) {
    QString target = path.isEmpty() ? m_currentPath : path;
    QFileInfo fi(target);
    if (!fi.isDir()) {
        target = fi.absolutePath();
    }
    // b1air-term accepts a directory argument and starts in it.
    QProcess::startDetached("b1air-term", QStringList() << target);
}

void FileManagerBackend::triggerQuickLook(const QString& path) {
    if (!path.isEmpty()) {
        QProcess::startDetached("b1air-daemon", QStringList() << "quicklook" << path);
    }
}

void FileManagerBackend::setWallpaper(const QString& path) {
    if (path.isEmpty()) return;
    // The daemon owns this: it applies via Sway IPC, falls back to swaybg, and
    // caches the image for SDDM. Spawning swaybg here would leave a second one
    // running on top of the first.
    QProcess::startDetached("b1air-daemon", QStringList() << "wallpaper" << "set" << path);
}

bool FileManagerBackend::createFolder(const QString& name) {
    if (name.isEmpty()) return false;
    QDir dir(m_currentPath);
    if (dir.mkdir(name)) {
        refresh();
        return true;
    }
    return false;
}

bool FileManagerBackend::deleteItem(const QString& path) {
    QFileInfo fi(path);
    if (!fi.exists()) return false;

    // Use trash-put if available, otherwise fallback to remove
    if (QProcess::execute("trash-put", QStringList() << path) == 0) {
        refresh();
        return true;
    }

    bool ok = false;
    if (fi.isDir()) {
        ok = QDir(path).removeRecursively();
    } else {
        ok = QFile::remove(path);
    }
    if (ok) refresh();
    return ok;
}

bool FileManagerBackend::renameItem(const QString& oldPath, const QString& newName) {
    if (newName.isEmpty()) return false;
    QFileInfo fi(oldPath);
    if (!fi.exists()) return false;

    QString newPath = fi.dir().absoluteFilePath(newName);
    if (QFile::rename(oldPath, newPath)) {
        refresh();
        return true;
    }
    return false;
}

static QString bookmarksPath() {
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation)
                        + "/b1air";
    QDir().mkpath(dir);
    return dir + "/files_bookmarks.json";
}

QVariantList FileManagerBackend::loadBookmarks() const {
    QFile f(bookmarksPath());
    if (!f.open(QIODevice::ReadOnly))
        return {};

    const QJsonDocument doc = QJsonDocument::fromJson(f.readAll());
    if (!doc.isArray())
        return {};

    QVariantList out;
    for (const QJsonValue& v : doc.array()) {
        const QJsonObject o = v.toObject();
        const QString path = o.value("path").toString();
        // A bookmark to a directory that is no longer there is a row that
        // silently does nothing when clicked, which is how the shipped
        // ~/DotsFiles entry behaved on every machine that kept its checkout
        // somewhere else.
        if (path.isEmpty() || !QFileInfo::exists(path))
            continue;
        QVariantMap m;
        m["name"] = o.value("name").toString(QFileInfo(path).fileName());
        m["path"] = path;
        m["icon"] = o.value("icon").toString(QStringLiteral("\uF01BF"));
        out.append(m);
    }
    return out;
}

void FileManagerBackend::saveBookmarks(const QVariantList& bookmarks) const {
    QJsonArray arr;
    for (const QVariant& v : bookmarks) {
        const QVariantMap m = v.toMap();
        QJsonObject o;
        o["name"] = m.value("name").toString();
        o["path"] = m.value("path").toString();
        o["icon"] = m.value("icon").toString();
        arr.append(o);
    }

    QSaveFile f(bookmarksPath());
    if (!f.open(QIODevice::WriteOnly))
        return;
    f.write(QJsonDocument(arr).toJson(QJsonDocument::Indented));
    f.commit();
}

} // namespace b1air
