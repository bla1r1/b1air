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
#include <QLocale>
#include <QMimeDatabase>
#include <QDirIterator>
#include <QPointer>
#include <QDateTime>
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
    m_files = new FileListModel(this);
    // Drives come and go (a USB stick, a phone); a light poll keeps the
    // sidebar honest without a udisks dependency.
    m_volumeTimer.setInterval(3000);
    connect(&m_volumeTimer, &QTimer::timeout, this, &FileManagerBackend::updateVolumes);
    m_volumeTimer.start();
    updateVolumes();
    QString home = QDir::homePath();
    setCurrentPath(home);
}

void FileManagerBackend::loadFiles() {
    FileListModel::Options o;
    o.showHidden = m_showHidden;
    o.dirsFirst = m_dirsFirst;
    o.sortField = m_sortField;
    o.ascending = m_sortAscending;
    o.filter = m_filterQuery;
    m_files->load(m_currentPath, o);
}

void FileManagerBackend::setDirsFirst(bool v) {
    if (m_dirsFirst == v) return;
    m_dirsFirst = v;
    emit sortChanged();
    refresh();
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
    loadFiles();
    updateTrashCount();
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
    // Not over something already there: QFile::rename refuses for a file,
    // but a folder renamed onto another folder's name is easy to lose.
    if (QFileInfo::exists(newPath) && newPath != oldPath) {
        emit errorOccurred("Something named " + newName + " is already here");
        return false;
    }
    if (QFile::rename(oldPath, newPath)) {
        pushUndo({"rename", {{oldPath, newPath}}, {}, "Rename"});
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
    transfer(sources, m_currentPath, cut);
}

void FileManagerBackend::transfer(const QStringList& sources, const QString& destDir, bool move) {
    if (m_busy || sources.isEmpty() || destDir.isEmpty()) return;
    for (const QString& s : sources) {
        const QString clean = QDir::cleanPath(s);
        if (destDir == clean || destDir.startsWith(clean + "/")) {
            emit pasteFinished(false, "Cannot put a folder inside itself");
            return;
        }
    }

    m_busy = true;
    emit busyChanged();
    QPointer<FileManagerBackend> self(this);
    // A worker thread: copying a large folder on the GUI thread froze the
    // window for as long as it took.
    std::thread([self, sources, destDir, move]() {
        QString error;
        QStringList landed;
        QList<QPair<QString, QString>> pairs;
        const QDir dest(destDir);
        for (const QString& src : sources) {
            const QFileInfo fi(src);
            if (!fi.exists() && !fi.isSymLink()) { error = fi.fileName() + " no longer exists"; break; }
            // Moving into the folder it already lives in is a no-op, not a copy.
            if (move && fi.absolutePath() == dest.absolutePath()) { landed << src; continue; }
            const QString target = freeName(dest, fi.fileName());
            if (move && QFile::rename(src, target)) { landed << target; pairs << qMakePair(src, target); continue; }
            if (!copyRecursive(src, target, &error)) break;
            if (move) {
                const bool removed = fi.isDir() && !fi.isSymLink() ? QDir(src).removeRecursively() : QFile::remove(src);
                if (!removed) { error = "Copied, but could not remove " + fi.fileName(); break; }
            }
            landed << target;
            pairs << qMakePair(src, target);
        }
        const bool ok = error.isEmpty();
        const int done = int(landed.size());
        const QString msg = ok ? QStringLiteral("%1 %2 item%3").arg(move ? "Moved" : "Copied").arg(done).arg(done == 1 ? "" : "s")
                               : error;
        QMetaObject::invokeMethod(qApp, [self, ok, msg, move, landed, destDir, pairs]() {
            if (!self) return;
            self->m_busy = false;
            emit self->busyChanged();
            if (!pairs.isEmpty()) {
                const int n = int(pairs.size());
                const QString what = n == 1 ? QFileInfo(pairs.first().first).fileName() : QStringLiteral("%1 items").arg(n);
                if (move) self->pushUndo({"move", pairs, {}, "Move " + what});
                else {
                    QStringList copies;
                    for (const auto& p : pairs) copies << p.second;
                    self->pushUndo({"copy", {}, copies, "Copy " + what});
                }
            }
            // A moved file is gone from where it was; the clipboard must not
            // offer to move it a second time.
            if (ok && move) {
                const QMimeData* d = QGuiApplication::clipboard()->mimeData();
                if (d && d->hasFormat(kGnomeCopied)) QGuiApplication::clipboard()->clear();
            }
            self->refresh();
            // What just arrived is selected, so it can be seen and acted on.
            if (destDir == self->m_currentPath) self->m_files->selectPaths(landed);
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


// ── Trash ───────────────────────────────────────────────────────────────────
//
// The freedesktop.org trash in the home directory: files/ holds the items,
// info/<name>.trashinfo where each came from. Trash on other drives is left
// to gio, which handles those when it trashes.

QString FileManagerBackend::trashPath() const {
    return QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + "/Trash/files";
}

void FileManagerBackend::updateTrashCount() {
    const int n = int(QDir(trashPath()).entryList(QDir::AllEntries | QDir::NoDotAndDotDot | QDir::Hidden | QDir::System).size());
    if (n != m_trashCount) {
        m_trashCount = n;
        emit trashChanged();
    }
}

bool FileManagerBackend::trashItems(const QStringList& paths) {
    if (paths.isEmpty()) return false;
    // One gio call for the lot; it is the same mechanism the single delete used.
    bool ok = QProcess::execute("gio", QStringList{"trash", "--"} + paths) == 0;
    if (!ok) ok = QProcess::execute("trash-put", paths) == 0;
    if (ok) pushUndo({"trash", {}, paths, paths.size() == 1
        ? "Move " + QFileInfo(paths.first()).fileName() + " to Trash"
        : QStringLiteral("Move %1 items to Trash").arg(paths.size())});
    if (!ok) emit errorOccurred(paths.size() == 1
        ? QStringLiteral("Could not move %1 to the trash").arg(QFileInfo(paths.first()).fileName())
        : QStringLiteral("Could not move %1 items to the trash").arg(paths.size()));
    refresh();
    return ok;
}

bool FileManagerBackend::deletePermanently(const QStringList& paths) {
    const QString info = QFileInfo(trashPath()).absolutePath() + "/info/";
    bool all = true;
    for (const QString& p : paths) {
        const QFileInfo fi(p);
        const bool ok = fi.isDir() && !fi.isSymLink() ? QDir(p).removeRecursively() : QFile::remove(p);
        if (ok && fi.absolutePath() == trashPath()) QFile::remove(info + fi.fileName() + ".trashinfo");
        all = all && ok;
    }
    if (!all) emit errorOccurred("Some items could not be deleted");
    refresh();
    return all;
}

bool FileManagerBackend::restoreFromTrash(const QStringList& paths) {
    const QString info = QFileInfo(trashPath()).absolutePath() + "/info/";
    int restored = 0;
    for (const QString& p : paths) {
        const QFileInfo fi(p);
        QFile f(info + fi.fileName() + ".trashinfo");
        QString original;
        if (f.open(QIODevice::ReadOnly)) {
            for (const QByteArray& line : f.readAll().split('\n'))
                if (line.startsWith("Path="))
                    original = QUrl::fromPercentEncoding(line.mid(5)).trimmed();
            f.close();
        }
        if (original.isEmpty()) continue;
        if (!original.startsWith('/')) original = QDir::homePath() + "/" + original;
        const QFileInfo target(original);
        QDir().mkpath(target.absolutePath());
        const QString dest = QFileInfo::exists(original) ? freeName(QDir(target.absolutePath()), target.fileName()) : original;
        if (QFile::rename(p, dest)) {
            QFile::remove(f.fileName());
            ++restored;
        }
    }
    if (restored < paths.size())
        emit errorOccurred(QStringLiteral("Restored %1 of %2").arg(restored).arg(paths.size()));
    else
        emit errorOccurred(restored == 1 ? QStringLiteral("Restored 1 item") : QStringLiteral("Restored %1 items").arg(restored));
    refresh();
    return restored == paths.size();
}

void FileManagerBackend::emptyTrash() {
    if (QProcess::execute("gio", {"trash", "--empty"}) != 0) {
        const QDir root(QFileInfo(trashPath()).absolutePath());
        for (const char* sub : {"files", "info"}) {
            QDir d(root.filePath(sub));
            for (const QFileInfo& fi : d.entryInfoList(QDir::AllEntries | QDir::NoDotAndDotDot | QDir::Hidden | QDir::System))
                fi.isDir() && !fi.isSymLink() ? (void)QDir(fi.absoluteFilePath()).removeRecursively()
                                              : (void)QFile::remove(fi.absoluteFilePath());
        }
    }
    refresh();
}

int FileManagerBackend::trashPurgeDays() {
    QFile f(prefsPath());
    if (!f.open(QIODevice::ReadOnly)) return 30;
    const QJsonObject o = QJsonDocument::fromJson(f.readAll()).object();
    return o.contains("trashPurgeDays") ? o.value("trashPurgeDays").toInt(30) : 30;
}

int FileManagerBackend::purgeTrash(int days) {
    if (days <= 0) return 0;
    const QString root = QStandardPaths::writableLocation(QStandardPaths::GenericDataLocation) + "/Trash";
    const QDateTime cutoff = QDateTime::currentDateTime().addDays(-days);
    int purged = 0;
    for (const QFileInfo& info : QDir(root + "/info").entryInfoList({"*.trashinfo"}, QDir::Files | QDir::Hidden)) {
        QFile f(info.absoluteFilePath());
        if (!f.open(QIODevice::ReadOnly)) continue;
        QDateTime deleted;
        for (const QByteArray& line : f.readAll().split('\n'))
            if (line.startsWith("DeletionDate="))
                deleted = QDateTime::fromString(QString::fromUtf8(line.mid(13)).trimmed(), Qt::ISODate);
        f.close();
        // No readable date: leave it — an unknown age is not an old one.
        if (!deleted.isValid() || deleted >= cutoff) continue;
        const QString name = info.completeBaseName();   // strips ".trashinfo"
        const QFileInfo item(root + "/files/" + name);
        const bool gone = !item.exists() && !item.isSymLink() ? true
            : item.isDir() && !item.isSymLink() ? QDir(item.absoluteFilePath()).removeRecursively()
            : QFile::remove(item.absoluteFilePath());
        if (gone && QFile::remove(info.absoluteFilePath())) ++purged;
    }
    return purged;
}

// ── Compress ────────────────────────────────────────────────────────────────

static bool addToArchive(struct archive* a, const QFileInfo& fi, const QString& entryName, QString* error) {
    struct archive_entry* e = archive_entry_new();
    archive_entry_set_pathname(e, entryName.toUtf8().constData());
    archive_entry_set_mtime(e, fi.lastModified().toSecsSinceEpoch(), 0);
    archive_entry_set_uid(e, fi.ownerId());
    archive_entry_set_gid(e, fi.groupId());
    archive_entry_set_perm(e, 0644 | (fi.isExecutable() ? 0111 : 0));
    bool ok = true;
    if (fi.isSymLink()) {
        archive_entry_set_filetype(e, AE_IFLNK);
        archive_entry_set_symlink(e, fi.symLinkTarget().toUtf8().constData());
        ok = archive_write_header(a, e) >= ARCHIVE_WARN;
    } else if (fi.isDir()) {
        archive_entry_set_filetype(e, AE_IFDIR);
        archive_entry_set_perm(e, 0755);
        ok = archive_write_header(a, e) >= ARCHIVE_WARN;
    } else {
        archive_entry_set_filetype(e, AE_IFREG);
        archive_entry_set_size(e, fi.size());
        QFile f(fi.absoluteFilePath());
        ok = f.open(QIODevice::ReadOnly) && archive_write_header(a, e) >= ARCHIVE_WARN;
        while (ok && !f.atEnd()) {
            const QByteArray chunk = f.read(1 << 16);
            ok = archive_write_data(a, chunk.constData(), size_t(chunk.size())) >= 0;
        }
    }
    if (!ok && error && error->isEmpty())
        *error = QString::fromUtf8(archive_error_string(a) ? archive_error_string(a) : "write failed") + " (" + fi.fileName() + ")";
    archive_entry_free(e);
    return ok;
}

void FileManagerBackend::compressItems(const QStringList& paths, const QString& name, const QString& format) {
    if (m_busy || paths.isEmpty() || name.isEmpty() || name.contains('/')) return;
    static const QStringList formats{"zip", "tar.gz", "tar.zst", "7z"};
    if (!formats.contains(format)) return;
    const QString target = freeName(QDir(m_currentPath), name + "." + format);
    m_busy = true;
    emit busyChanged();
    QPointer<FileManagerBackend> self(this);
    std::thread([self, paths, target, format]() {
        QString error;
        struct archive* a = archive_write_new();
        if (format == "zip") archive_write_set_format_zip(a);
        else if (format == "7z") archive_write_set_format_7zip(a);
        else {
            archive_write_set_format_pax_restricted(a);
            if (format == "tar.gz") archive_write_add_filter_gzip(a);
            else archive_write_add_filter_zstd(a);
        }
        bool ok = archive_write_open_filename(a, target.toLocal8Bit().constData()) == ARCHIVE_OK;
        if (!ok) error = QString::fromUtf8(archive_error_string(a));
        // Entries are named relative to the folder the items sit in, so the
        // archive unpacks to what was selected and not to the whole path.
        for (const QString& p : paths) {
            if (!ok) break;
            const QFileInfo top(p);
            const QDir base = top.absoluteDir();
            ok = addToArchive(a, top, top.fileName(), &error);
            if (ok && top.isDir() && !top.isSymLink()) {
                QDirIterator it(p, QDir::AllEntries | QDir::NoDotAndDotDot | QDir::Hidden | QDir::System,
                                QDirIterator::Subdirectories);
                while (ok && it.hasNext()) {
                    const QFileInfo fi(it.next());
                    ok = addToArchive(a, fi, base.relativeFilePath(fi.absoluteFilePath()), &error);
                }
            }
        }
        if (archive_write_close(a) != ARCHIVE_OK && ok) { ok = false; error = QString::fromUtf8(archive_error_string(a)); }
        archive_write_free(a);
        if (!ok) QFile::remove(target);
        const QString msg = ok ? "Created " + QFileInfo(target).fileName() : "Could not compress: " + error;
        QMetaObject::invokeMethod(qApp, [self, ok, msg, target]() {
            if (!self) return;
            self->m_busy = false;
            emit self->busyChanged();
            self->refresh();
            if (ok) self->m_files->selectPaths({target});
            emit self->pasteFinished(ok, msg);
        }, Qt::QueuedConnection);
    }).detach();
}

// ── Drives ──────────────────────────────────────────────────────────────────

void FileManagerBackend::updateVolumes() {
    QVariantList list;
    for (const QStorageInfo& s : QStorageInfo::mountedVolumes()) {
        if (!s.isValid() || !s.isReady()) continue;
        const QString root = s.rootPath();
        // What a person plugged in or mounted, not the system's own mounts.
        const bool user = root.startsWith("/media/") || root.startsWith("/run/media/") || root.startsWith("/mnt/");
        if (!user) continue;
        QVariantMap v;
        v["name"] = s.displayName().isEmpty() || s.displayName() == root ? QFileInfo(root).fileName() : s.displayName();
        v["path"] = root;
        v["device"] = QString::fromUtf8(s.device());
        v["free"] = FileListModel::formatSize(s.bytesAvailable()) + " free";
        v["percent"] = s.bytesTotal() > 0 ? 1.0 - double(s.bytesAvailable()) / double(s.bytesTotal()) : 0.0;
        list << v;
    }
    if (list != m_volumes) {
        m_volumes = list;
        emit volumesChanged();
    }
}

bool FileManagerBackend::unmount(const QString& path) {
    QString device;
    for (const QVariant& v : m_volumes)
        if (v.toMap().value("path").toString() == path) device = v.toMap().value("device").toString();
    // Leave the drive before letting go of it, or the unmount is refused as busy.
    if (m_currentPath == path || m_currentPath.startsWith(path + "/")) setCurrentPath(QDir::homePath());
    bool ok = QProcess::execute("gio", {"mount", "-u", path}) == 0;
    if (!ok && !device.isEmpty()) ok = QProcess::execute("udisksctl", {"unmount", "-b", device}) == 0;
    updateVolumes();
    emit errorOccurred(ok ? "It is safe to remove " + QFileInfo(path).fileName()
                          : "Could not unmount " + QFileInfo(path).fileName() + " — something may still be using it");
    return ok;
}

// ── Open With ───────────────────────────────────────────────────────────────

static QString desktopEntryName(const QString& id) {
    const QString file = QStandardPaths::locate(QStandardPaths::ApplicationsLocation, id);
    if (file.isEmpty()) return {};
    QFile f(file);
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text)) return {};
    bool inEntry = false;
    QString name;
    const QString lang = QLocale().name().section('_', 0, 0);
    for (const QByteArray& raw : f.readAll().split('\n')) {
        const QString line = QString::fromUtf8(raw).trimmed();
        if (line.startsWith('[')) { inEntry = line == "[Desktop Entry]"; continue; }
        if (!inEntry) continue;
        if (line.startsWith("NoDisplay=true") || line.startsWith("Hidden=true")) return {};
        if (line.startsWith("Name[" + lang + "]=")) name = line.section('=', 1);
        else if (line.startsWith("Name=") && name.isEmpty()) name = line.mid(5);
    }
    return name;
}

QVariantList FileManagerBackend::openWithApps(const QString& path) const {
    QVariantList out;
    const QString mime = QMimeDatabase().mimeTypeForFile(path).name();
    QProcess p;
    p.start("gio", {"mime", mime});
    if (!p.waitForFinished(2000)) return out;
    // "Default application for “text/plain”: b1air-text.desktop"
    // "Registered applications:" then one id per indented line.
    QString def;
    QStringList ids;
    for (const QString& line : QString::fromUtf8(p.readAllStandardOutput()).split('\n')) {
        const QString t = line.trimmed();
        if (t.startsWith("Default application")) def = t.section(':', -1).trimmed();
        else if (t.endsWith(".desktop") && !ids.contains(t)) ids << t;
    }
    if (!def.isEmpty() && !ids.contains(def)) ids.prepend(def);
    for (const QString& id : ids) {
        const QString name = desktopEntryName(id);
        if (name.isEmpty()) continue;
        out << QVariantMap{{"id", id}, {"name", name}, {"isDefault", id == def}};
    }
    return out;
}

void FileManagerBackend::openWith(const QString& desktopId, const QStringList& paths) {
    const QString file = QStandardPaths::locate(QStandardPaths::ApplicationsLocation, desktopId);
    if (file.isEmpty() || paths.isEmpty()) return;
    // gio launch reads the entry's Exec and field codes the same way a menu
    // does; gtk-launch is the fallback for an older glib.
    if (!QProcess::startDetached("gio", QStringList{"launch", file} + paths))
        QProcess::startDetached("gtk-launch", QStringList{desktopId} + paths);
}

// ── Properties ──────────────────────────────────────────────────────────────

QVariantMap FileManagerBackend::itemInfo(const QString& path) {
    QVariantMap m;
    const QFileInfo fi(path);
    if (!fi.exists() && !fi.isSymLink()) return m;
    const QMimeType mt = QMimeDatabase().mimeTypeForFile(fi);
    const QLocale loc;
    m["name"] = fi.fileName().isEmpty() ? path : fi.fileName();
    m["path"] = fi.absoluteFilePath();
    m["location"] = fi.absolutePath();
    m["isDir"] = fi.isDir();
    m["kind"] = fi.isDir() ? QStringLiteral("Folder") : mt.comment();
    m["mime"] = mt.name();
    m["category"] = FileListModel::categoryFor(mt.name(), fi.isDir(), fi.isExecutable());
    m["modified"] = loc.toString(fi.lastModified(), "d MMMM yyyy, HH:mm");
    m["created"] = fi.birthTime().isValid() ? loc.toString(fi.birthTime(), "d MMMM yyyy, HH:mm") : QString();
    m["owner"] = fi.owner() + (fi.group().isEmpty() ? QString() : " / " + fi.group());
    m["symlinkTarget"] = fi.isSymLink() ? fi.symLinkTarget() : QString();
    const auto P = fi.permissions();
    auto trip = [&](QFile::Permission r, QFile::Permission w, QFile::Permission x) {
        return QString(P & r ? "r" : "-") + (P & w ? "w" : "-") + (P & x ? "x" : "-");
    };
    m["permissions"] = trip(QFile::ReadOwner, QFile::WriteOwner, QFile::ExeOwner)
                     + trip(QFile::ReadGroup, QFile::WriteGroup, QFile::ExeGroup)
                     + trip(QFile::ReadOther, QFile::WriteOther, QFile::ExeOther);
    m["writable"] = fi.isWritable();
    if (fi.isDir()) {
        const int items = int(QDir(path).entryList(QDir::AllEntries | QDir::NoDotAndDotDot | QDir::Hidden | QDir::System).size());
        m["items"] = items;
        m["sizeText"] = QStringLiteral("Calculating…");
        // The total, walked on a worker thread: a home directory takes seconds.
        QPointer<FileManagerBackend> self(this);
        std::thread([self, path]() {
            qint64 bytes = 0;
            int files = 0;
            QDirIterator it(path, QDir::Files | QDir::Hidden | QDir::System | QDir::NoSymLinks,
                            QDirIterator::Subdirectories);
            while (it.hasNext()) {
                it.next();
                bytes += it.fileInfo().size();
                ++files;
            }
            const QString text = FileListModel::formatSize(bytes);
            QMetaObject::invokeMethod(qApp, [self, path, text, files]() {
                if (self) emit self->folderSizeReady(path, text, files);
            }, Qt::QueuedConnection);
        }).detach();
    } else {
        m["sizeText"] = FileListModel::formatSize(fi.size()) + QStringLiteral(" (%L1 bytes)").arg(fi.size());
    }
    return m;
}


// ── Undo ────────────────────────────────────────────────────────────────────

void FileManagerBackend::pushUndo(const UndoOp& op) {
    m_undo.append(op);
    while (m_undo.size() > 30) m_undo.removeFirst();
    emit undoChanged();
}

// Items trashed from these original paths, put back where they were: the
// most recent .trashinfo naming each path wins.
bool FileManagerBackend::restoreOriginals(const QStringList& originals) {
    const QString info = QFileInfo(trashPath()).absolutePath() + "/info/";
    QStringList found;
    for (const QString& orig : originals) {
        QString best;
        QString bestDate;
        for (const QFileInfo& fi : QDir(info).entryInfoList({"*.trashinfo"}, QDir::Files)) {
            QFile f(fi.absoluteFilePath());
            if (!f.open(QIODevice::ReadOnly)) continue;
            QString path, date;
            for (const QByteArray& line : f.readAll().split('\n')) {
                if (line.startsWith("Path=")) path = QUrl::fromPercentEncoding(line.mid(5)).trimmed();
                else if (line.startsWith("DeletionDate=")) date = QString::fromUtf8(line.mid(13)).trimmed();
            }
            if (path == orig && date >= bestDate) { best = fi.completeBaseName(); bestDate = date; }
        }
        if (!best.isEmpty()) found << trashPath() + "/" + best;
    }
    return !found.isEmpty() && restoreFromTrash(found);
}

void FileManagerBackend::undo() {
    if (m_undo.isEmpty() || m_busy) return;
    const UndoOp op = m_undo.takeLast();
    emit undoChanged();
    bool ok = true;
    QStringList back;
    if (op.kind == "move" || op.kind == "rename") {
        for (auto it = op.moves.crbegin(); it != op.moves.crend(); ++it) {
            const QString from = it->second, to = it->first;
            if (QFileInfo::exists(to)) { ok = false; continue; }   // never over something new
            QDir().mkpath(QFileInfo(to).absolutePath());
            if (QFile::rename(from, to)) { back << to; continue; }
            QString err;
            const QFileInfo fi(from);
            if (copyRecursive(from, to, &err)
                && (fi.isDir() && !fi.isSymLink() ? QDir(from).removeRecursively() : QFile::remove(from)))
                back << to;
            else ok = false;
        }
    } else if (op.kind == "copy") {
        // The copies go to the trash, not to nothing: undoing a copy should
        // not be the one way to lose data here.
        ok = QProcess::execute("gio", QStringList{"trash", "--"} + op.paths) == 0;
    } else if (op.kind == "trash") {
        ok = restoreOriginals(op.paths);
        back = op.paths;
    }
    refresh();
    if (!back.isEmpty()) m_files->selectPaths(back);
    emit errorOccurred(ok ? "Undone: " + op.label : "Could not fully undo: " + op.label);
}

} // namespace b1air
