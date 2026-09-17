#include "backend.hpp"
#include <QClipboard>
#include <QGuiApplication>
#include <algorithm>
#include <QUrl>
#include <QDesktopServices>
#include <QJsonArray>
#include <QCoreApplication>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>
#include <QStandardPaths>
#include <QMimeData>
#include <QDirIterator>
#include <QPointer>
#include <thread>
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

void FileManagerBackend::refresh() {
    // Only the disk readout. This used to call loadDirectory(), which walked
    // the directory, formatted every size and date, decided an icon glyph and
    // colour for each entry and sorted the lot — into a list nothing read. The
    // views are driven by a FolderListModel bound to the same currentPath,
    // showHidden and filterQuery, so every navigation paid for the same
    // listing twice and used one of them.
    emit diskInfoChanged();
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
        openWithDefaultApp(path);
    }
}

// The application mimeapps.list names for this file. xdg-open alone was not
// enough: this desktop's XDG_CURRENT_DESKTOP is one it does not know, so it
// falls back to a generic mode that needs `file` to tell a .txt from a .jpg —
// and without it (a minimal install) Enter on any file did nothing at all.
// gio reads the same mimeapps.list with its own type detection; xdg-open is
// the fallback when gio is missing or fails.
void FileManagerBackend::openWithDefaultApp(const QString& path) {
    if (QStandardPaths::findExecutable("gio").isEmpty()) {
        QProcess::startDetached("xdg-open", {path});
        return;
    }
    auto* proc = new QProcess(this);
    connect(proc, &QProcess::finished, this, [this, proc, path](int code, QProcess::ExitStatus status) {
        proc->deleteLater();
        if (status == QProcess::NormalExit && code == 0) return;
        if (!QProcess::startDetached("xdg-open", {path}))
            emit errorOccurred("No application is set to open " + QFileInfo(path).fileName());
    });
    connect(proc, &QProcess::errorOccurred, this, [proc, path](QProcess::ProcessError e) {
        if (e != QProcess::FailedToStart) return;
        proc->deleteLater();
        QProcess::startDetached("xdg-open", {path});
    });
    proc->start("gio", {"open", path});
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

void FileManagerBackend::confirmPick() {
    if (m_pickResultPath.isEmpty()) return;
    QFile f(m_pickResultPath);
    if (f.open(QIODevice::WriteOnly)) {
        f.write(currentPath().toUtf8());
        f.close();
    }
    QCoreApplication::quit();
}

void FileManagerBackend::cancelPick() {
    // Leaving the file absent is how the caller learns nothing was chosen.
    QCoreApplication::quit();
}

bool FileManagerBackend::deleteItem(const QString& path) {
    QFileInfo fi(path);
    if (!fi.exists()) return false;

    // To the trash, and only to the trash. This tried trash-put — which is
    // not installed here — and then removed the file for good, so "delete"
    // on this machine was permanent with nothing said. gio ships with glib,
    // which everything on the desktop already needs.
    for (const QStringList& cmd : {QStringList{"gio", "trash", path}, QStringList{"trash-put", path}}) {
        if (QProcess::execute(cmd.first(), cmd.mid(1)) == 0) {
            refresh();
            return true;
        }
    }
    emit errorOccurred(QStringLiteral("Could not move %1 to the trash").arg(fi.fileName()));
    return false;
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

static QString prefsPath() {
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation)
                        + "/b1air";
    QDir().mkpath(dir);
    return dir + "/files_prefs.json";
}

QVariantMap FileManagerBackend::loadPrefs() const {
    QFile f(prefsPath());
    if (!f.open(QIODevice::ReadOnly))
        return {};
    const QJsonDocument doc = QJsonDocument::fromJson(f.readAll());
    return doc.isObject() ? doc.object().toVariantMap() : QVariantMap{};
}

void FileManagerBackend::savePrefs(const QVariantMap& prefs) const {
    QSaveFile f(prefsPath());
    if (!f.open(QIODevice::WriteOnly))
        return;
    f.write(QJsonDocument(QJsonObject::fromVariantMap(prefs)).toJson(QJsonDocument::Indented));
    f.commit();
}

void FileManagerBackend::copyText(const QString& text) const {
    QGuiApplication::clipboard()->setText(text);
}

static const char* kGnomeCopied = "x-special/gnome-copied-files";

void FileManagerBackend::copyFiles(const QStringList& paths, bool cut) {
    QList<QUrl> urls;
    QByteArray gnome = cut ? "cut" : "copy";
    for (const QString& p : paths) {
        if (p.isEmpty()) continue;
        const QUrl u = QUrl::fromLocalFile(p);
        urls << u;
        gnome += "\n" + u.toEncoded();
    }
    if (urls.isEmpty()) return;
    auto* data = new QMimeData;
    data->setUrls(urls);
    data->setData(kGnomeCopied, gnome);
    data->setText(paths.join('\n'));
    QGuiApplication::clipboard()->setMimeData(data);
}

bool FileManagerBackend::clipboardHasFiles() const {
    const QMimeData* d = QGuiApplication::clipboard()->mimeData();
    if (!d || !d->hasUrls()) return false;
    for (const QUrl& u : d->urls())
        if (u.isLocalFile()) return true;
    return false;
}

// "report.pdf" -> "report (copy).pdf", then "(copy 2)", ... until free.
static QString freeName(const QDir& dir, const QString& name) {
    if (!dir.exists(name)) return dir.absoluteFilePath(name);
    const QFileInfo fi(name);
    const QString suffix = fi.completeSuffix().isEmpty() || fi.fileName().startsWith('.')
                           ? QString() : "." + fi.completeSuffix();
    const QString base = suffix.isEmpty() ? name : name.left(name.size() - suffix.size());
    for (int i = 1;; ++i) {
        const QString candidate = base + (i == 1 ? " (copy)" : QStringLiteral(" (copy %1)").arg(i)) + suffix;
        if (!dir.exists(candidate)) return dir.absoluteFilePath(candidate);
    }
}

// Recursive copy that keeps permissions; symlinks are copied as links.
static bool copyRecursive(const QString& src, const QString& dst, QString* error) {
    const QFileInfo fi(src);
    if (fi.isSymLink()) {
        if (!QFile::link(fi.symLinkTarget(), dst)) { *error = "Could not copy link " + fi.fileName(); return false; }
        return true;
    }
    if (fi.isDir()) {
        if (!QDir().mkpath(dst)) { *error = "Could not create " + dst; return false; }
        QFile::setPermissions(dst, fi.permissions());
        const QDir d(src);
        for (const QFileInfo& e : d.entryInfoList(QDir::AllEntries | QDir::NoDotAndDotDot | QDir::Hidden | QDir::System))
            if (!copyRecursive(e.absoluteFilePath(), dst + "/" + e.fileName(), error)) return false;
        return true;
    }
    if (!QFile::copy(src, dst)) { *error = "Could not copy " + fi.fileName(); return false; }
    return true;
}

void FileManagerBackend::paste() {
    if (m_busy) return;
    const QMimeData* d = QGuiApplication::clipboard()->mimeData();
    if (!d || !d->hasUrls()) return;
    bool cut = false;
    if (d->hasFormat(kGnomeCopied))
        cut = d->data(kGnomeCopied).startsWith("cut");
    QStringList sources;
    for (const QUrl& u : d->urls())
        if (u.isLocalFile()) sources << u.toLocalFile();
    if (sources.isEmpty()) return;

    const QString destDir = m_currentPath;
    for (const QString& s : sources) {
        const QString clean = QDir::cleanPath(s);
        if (destDir == clean || destDir.startsWith(clean + "/")) {
            emit pasteFinished(false, "Cannot paste a folder into itself");
            return;
        }
    }

    m_busy = true;
    emit busyChanged();
    QPointer<FileManagerBackend> self(this);
    // A worker thread: copying a large folder on the GUI thread froze the
    // window for as long as it took.
    std::thread([self, sources, destDir, cut]() {
        QString error;
        int done = 0;
        const QDir dest(destDir);
        for (const QString& src : sources) {
            const QFileInfo fi(src);
            if (!fi.exists() && !fi.isSymLink()) { error = fi.fileName() + " no longer exists"; break; }
            // Cut into the folder it already lives in is a no-op, not a copy.
            if (cut && fi.absolutePath() == dest.absolutePath()) { ++done; continue; }
            const QString target = freeName(dest, fi.fileName());
            if (cut && QFile::rename(src, target)) { ++done; continue; }
            if (!copyRecursive(src, target, &error)) break;
            if (cut) {
                const bool removed = fi.isDir() && !fi.isSymLink() ? QDir(src).removeRecursively() : QFile::remove(src);
                if (!removed) { error = "Copied, but could not remove " + fi.fileName(); break; }
            }
            ++done;
        }
        const bool ok = error.isEmpty();
        const QString msg = ok ? QStringLiteral("%1 %2 item%3").arg(cut ? "Moved" : "Pasted").arg(done).arg(done == 1 ? "" : "s")
                               : error;
        QMetaObject::invokeMethod(qApp, [self, ok, msg, cut]() {
            if (!self) return;
            self->m_busy = false;
            emit self->busyChanged();
            // A moved file is gone from where it was; the clipboard must not
            // offer to move it a second time.
            if (ok && cut) QGuiApplication::clipboard()->clear();
            self->refresh();
            emit self->pasteFinished(ok, msg);
        }, Qt::QueuedConnection);
    }).detach();
}

bool FileManagerBackend::createFile(const QString& name) {
    if (name.isEmpty() || name.contains('/')) return false;
    const QString path = QDir(m_currentPath).absoluteFilePath(name);
    if (QFileInfo::exists(path)) return false;
    QFile f(path);
    if (!f.open(QIODevice::WriteOnly | QIODevice::NewOnly)) return false;
    f.close();
    refresh();
    return true;
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
