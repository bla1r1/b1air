#include "dir_model.hpp"
#include "tags.hpp"

#include <QCollator>
#include <QDir>
#include <QFileInfo>
#include <QLocale>
#include <QMimeDatabase>
#include <algorithm>
#include <utility>
#include <thread>
#include <QCoreApplication>
#include <QPointer>
#include <QCryptographicHash>
#include <QHash>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMutex>
#include <QRunnable>
#include <QSaveFile>
#include <QStandardPaths>
#include <QThreadPool>
#include <atomic>

namespace b1air {

FileListModel::FileListModel(QObject* parent) : QAbstractListModel(parent) {
    // A burst of changes (an extraction, a copy of a hundred files) is one
    // reload, not a hundred.
    m_reloadDebounce.setSingleShot(true);
    m_reloadDebounce.setInterval(250);
    connect(&m_reloadDebounce, &QTimer::timeout, this, [this] {
        reload();
        emit reloaded();
    });
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this,
            [this] { m_reloadDebounce.start(); });
}

int FileListModel::rowCount(const QModelIndex& parent) const {
    return parent.isValid() ? 0 : int(m_entries.size());
}

QHash<int, QByteArray> FileListModel::roleNames() const {
    return {
        {NameRole, "name"},       {PathRole, "path"},
        {IsDirRole, "isDir"},     {SizeRole, "size"},
        {SizeTextRole, "sizeText"}, {ModifiedRole, "modified"},
        {ModifiedTextRole, "modifiedText"}, {KindRole, "kind"},
        {CategoryRole, "category"}, {IsImageRole, "isImage"},
        {HiddenRole, "hidden"},   {SymlinkRole, "symlink"},
        {SelectedRole, "selected"}, {TagsRole, "tags"},
    };
}

QString FileListModel::formatSize(qint64 bytes) {
    if (bytes < 1024) return QStringLiteral("%1 B").arg(bytes);
    const double kb = bytes / 1024.0;
    if (kb < 1024) return QStringLiteral("%1 KB").arg(kb, 0, 'f', kb < 10 ? 1 : 0);
    const double mb = kb / 1024.0;
    if (mb < 1024) return QStringLiteral("%1 MB").arg(mb, 0, 'f', 1);
    return QStringLiteral("%1 GB").arg(mb / 1024.0, 0, 'f', 1);
}

static QString modifiedText(const QDateTime& dt) {
    const QDate today = QDate::currentDate();
    const QLocale loc;
    if (dt.date() == today) return "Today, " + loc.toString(dt.time(), "HH:mm");
    if (dt.date() == today.addDays(-1)) return "Yesterday, " + loc.toString(dt.time(), "HH:mm");
    if (dt.date().year() == today.year()) return loc.toString(dt, "d MMM, HH:mm");
    return loc.toString(dt.date(), "d MMM yyyy");
}

QString FileListModel::categoryFor(const QString& m, bool isDir, bool executable) {
    if (isDir) return "folder";
    if (m.startsWith("image/")) return "image";
    if (m.startsWith("video/")) return "video";
    if (m.startsWith("audio/")) return "audio";
    if (m == "application/pdf") return "pdf";
    static const QStringList archives = {
        "application/zip", "application/x-tar", "application/gzip", "application/x-7z-compressed",
        "application/x-xz", "application/zstd", "application/x-rar", "application/vnd.rar",
        "application/x-bzip2", "application/x-compressed-tar", "application/x-xz-compressed-tar",
        "application/x-bzip2-compressed-tar", "application/x-zstd-compressed-tar",
        "application/vnd.debian.binary-package", "application/x-rpm", "application/x-iso9660-image"};
    if (archives.contains(m)) return "archive";
    if (m.contains("opendocument") || m.contains("officedocument") || m == "application/msword"
        || m.contains("ms-excel") || m.contains("ms-powerpoint") || m == "application/rtf")
        return "document";
    if (m == "application/x-shellscript" || m == "text/x-python" || m == "text/x-python3"
        || m.startsWith("text/x-c") || m == "text/x-java" || m == "text/rust" || m == "text/x-go"
        || m == "application/javascript" || m == "text/javascript" || m == "application/x-typescript"
        || m == "text/x-qml" || m == "application/json" || m == "application/x-yaml"
        || m == "application/toml" || m == "text/x-makefile" || m == "text/x-cmake"
        || m == "text/html" || m == "text/css" || m == "application/xml" || m == "text/x-lua")
        return "code";
    if (m.startsWith("text/")) return "text";
    if (executable || m == "application/x-executable" || m == "application/x-sharedlib"
        || m == "application/x-pie-executable" || m == "application/x-appimage")
        return "executable";
    return "file";
}

QVariant FileListModel::data(const QModelIndex& index, int role) const {
    if (!index.isValid() || index.row() < 0 || index.row() >= int(m_entries.size()))
        return {};
    const Entry& e = m_entries[size_t(index.row())];
    switch (role) {
    case Qt::DisplayRole:
    case NameRole: return e.name;
    case PathRole: return e.path;
    case IsDirRole: return e.isDir;
    case SizeRole: return e.size;
    case SizeTextRole: return e.isDir ? QString() : formatSize(e.size);
    case ModifiedRole: return e.modified;
    case ModifiedTextRole: return modifiedText(e.modified);
    case KindRole: return e.kind;
    case CategoryRole: return e.category;
    case IsImageRole: return e.category == "image";
    case HiddenRole: return e.hidden;
    case SymlinkRole: return e.symlink;
    case SelectedRole: return m_selected.contains(e.path);
    case TagsRole: return e.tags;
    }
    return {};
}

void FileListModel::load(const QString& dir, const Options& opts, bool relist) {
    const bool sameDir = dir == m_dir;
    m_opts = opts;
    if (!sameDir) {
        if (!m_dir.isEmpty()) m_watcher.removePath(m_dir);
        m_dir = dir;
        if (!m_dir.isEmpty()) m_watcher.addPath(m_dir);
        m_selected.clear();
        m_current = -1;
        m_anchor = -1;
    }
    if (!relist && sameDir && m_rawDir == dir && !m_loading) {
        refilter();
        return;
    }
    reload();
}

void FileListModel::open(const QString& dir, bool showHidden) {
    Options o;
    o.showHidden = showHidden;
    load(dir, o);
}

std::vector<FileListModel::Entry> FileListModel::list(const QString& dir, QString* error) {
    // QMimeDatabase is safe to share between threads for lookups.
    static const QMimeDatabase mimeDb;
    std::vector<Entry> out;
    QDir d(dir);
    // "tag:Red": every file with that tag, wherever it is (tags.hpp).
    const bool tagView = dir.startsWith(QLatin1String("tag:"));
    if (!tagView && !d.exists()) {
        *error = "This folder no longer exists.";
        return out;
    }
    if (!tagView && !QFileInfo(dir).isReadable()) {
        *error = "You do not have permission to see what is in this folder.";
        return out;
    }
    QFileInfoList infos;
    if (tagView)
        for (const QString& p : tags::pathsWith(dir.mid(4))) infos << QFileInfo(p);
    else
        infos = d.entryInfoList(QDir::AllEntries | QDir::NoDotAndDotDot | QDir::System | QDir::Hidden, QDir::NoSort);
    out.reserve(size_t(infos.size()));
    // gvfs (shares, MTP phones) and the phone mounts sit under the runtime
    // directory; removable drives under /run/media, /media and /mnt.
    static const QString runtime = qEnvironmentVariable("XDG_RUNTIME_DIR", QStringLiteral("/run/user/"));
    const bool far = dir.startsWith(runtime) || dir.startsWith(u"/run/media/") || dir.startsWith(u"/media/")
                  || dir.startsWith(u"/mnt/");
    for (const QFileInfo& fi : infos) {
        Entry e;
        e.name = fi.fileName();
        e.path = fi.absoluteFilePath();
        e.isDir = fi.isDir();
        e.size = e.isDir ? 0 : fi.size();
        e.modified = fi.lastModified();
        e.hidden = fi.isHidden();
        e.symlink = fi.isSymLink();
        e.tags = tags::read(e.path);
        if (e.isDir) {
            e.kind = "Folder";
            e.category = "folder";
        } else {
            // By name first: reading the content of every file to type
            // it would make a folder of large videos slow to open. Not by
            // content either for a program (/usr/bin: 2000 files read, 0.6 s
            // of the 0.7 s it took to open) or for a file on a share or a
            // phone, where each read is a trip to the other end.
            QMimeType mt = mimeDb.mimeTypeForFile(fi, QMimeDatabase::MatchExtension);
            if (mt.isDefault() && fi.suffix().isEmpty() && fi.size() < (64 << 20) && !far && !fi.isExecutable())
                mt = mimeDb.mimeTypeForFile(fi, QMimeDatabase::MatchContent);
            else if (mt.isDefault() && fi.suffix().isEmpty() && fi.isExecutable())
                mt = mimeDb.mimeTypeForName(QStringLiteral("application/x-executable"));
            e.kind = mt.comment().isEmpty() ? mt.name() : mt.comment();
            if (!e.kind.isEmpty()) e.kind[0] = e.kind[0].toUpper();
            e.category = categoryFor(mt.name(), false, fi.isExecutable() && mt.inherits("application/octet-stream"));
        }
        out.push_back(std::move(e));
    }
    return out;
}

// ── What network folders held ───────────────────────────────────────────────
//
// A folder on a network drive takes as long to list as the server takes to
// answer: a router's Samba, 0.1 to 1 s a folder, however it is asked (through
// gvfs's FUSE or gio, measured alike). Waiting was the hang, and in the
// background it was a "Loading…" of the same length. So what each one held is
// kept — in memory, and in ~/.cache/b1air/listings across runs — and shown at
// once when it is opened again, while it is read anew behind; and the
// folders inside the one open are read ahead, one at a time, so going into
// any of them is already done.

namespace {

QMutex g_cacheLock;
QHash<QString, std::vector<FileListModel::Entry>> g_cache;
QHash<QString, qint64> g_cacheRead;   // when it was read from the server, this run
constexpr qint64 kFreshMs = 30000;    // newer than this is not read again on opening

QString cacheFile(const QString& dir) {
    const QByteArray key = QCryptographicHash::hash(dir.toUtf8(), QCryptographicHash::Sha1).toHex();
    return QStandardPaths::writableLocation(QStandardPaths::GenericCacheLocation)
        + "/b1air/listings/" + QString::fromLatin1(key) + ".json";
}

void saveCached(const QString& dir, const std::vector<FileListModel::Entry>& entries) {
    {
        QMutexLocker lock(&g_cacheLock);
        g_cache.insert(dir, entries);
        g_cacheRead.insert(dir, QDateTime::currentMSecsSinceEpoch());
    }
    QJsonArray list;
    for (const auto& e : entries) {
        list.append(QJsonObject{
            {"n", e.name}, {"d", e.isDir}, {"s", double(e.size)},
            {"m", double(e.modified.toMSecsSinceEpoch())}, {"h", e.hidden}, {"l", e.symlink},
            {"k", e.kind}, {"c", e.category}, {"t", QJsonArray::fromStringList(e.tags)}});
    }
    const QString file = cacheFile(dir);
    QDir().mkpath(QFileInfo(file).absolutePath());
    QSaveFile f(file);
    if (!f.open(QIODevice::WriteOnly)) return;
    f.write(QJsonDocument(QJsonObject{{"dir", dir}, {"entries", list}}).toJson(QJsonDocument::Compact));
    f.commit();
}

bool loadCached(const QString& dir, std::vector<FileListModel::Entry>* out) {
    {
        QMutexLocker lock(&g_cacheLock);
        auto it = g_cache.constFind(dir);
        if (it != g_cache.constEnd()) { *out = *it; return true; }
    }
    QFile f(cacheFile(dir));
    if (!f.open(QIODevice::ReadOnly)) return false;
    const QJsonObject root = QJsonDocument::fromJson(f.readAll()).object();
    if (root.value("dir").toString() != dir) return false;
    out->clear();
    for (const QJsonValue& v : root.value("entries").toArray()) {
        const QJsonObject o = v.toObject();
        FileListModel::Entry e;
        e.name = o.value("n").toString();
        e.path = dir + "/" + e.name;
        e.isDir = o.value("d").toBool();
        e.size = qint64(o.value("s").toDouble());
        e.modified = QDateTime::fromMSecsSinceEpoch(qint64(o.value("m").toDouble()));
        e.hidden = o.value("h").toBool();
        e.symlink = o.value("l").toBool();
        e.kind = o.value("k").toString();
        e.category = o.value("c").toString();
        for (const QJsonValue& t : o.value("t").toArray()) e.tags << t.toString();
        out->push_back(std::move(e));
    }
    QMutexLocker lock(&g_cacheLock);
    g_cache.insert(dir, *out);
    return true;
}

bool freshlyRead(const QString& dir) {
    QMutexLocker lock(&g_cacheLock);
    const qint64 at = g_cacheRead.value(dir, 0);
    return at > 0 && QDateTime::currentMSecsSinceEpoch() - at < kFreshMs;
}

bool sameListing(const std::vector<FileListModel::Entry>& a, const std::vector<FileListModel::Entry>& b) {
    if (a.size() != b.size()) return false;
    for (size_t i = 0; i < a.size(); ++i)
        if (a[i].name != b[i].name || a[i].size != b[i].size || a[i].modified != b[i].modified
                || a[i].isDir != b[i].isDir || a[i].tags != b[i].tags)
            return false;
    return true;
}

// Reading ahead: one folder at a time, so the server is never asked for
// more than the one the person may open next; what was queued for the last
// folder is dropped when another is opened.
QThreadPool& readAhead() {
    static QThreadPool* pool = [] {
        auto* p = new QThreadPool;
        p->setMaxThreadCount(1);
        return p;
    }();
    return *pool;
}
std::atomic<int> g_readAheadGen{0};

} // namespace

std::vector<FileListModel::Entry> FileListModel::readAndKeep(const QString& dir, QString* error) {
    std::vector<Entry> raw = list(dir, error);
    if (error->isEmpty()) saveCached(dir, raw);
    return raw;
}

void FileListModel::readAheadOf(const QString& dir, const std::vector<Entry>& entries) {
    const int gen = ++g_readAheadGen;
    readAhead().clear();
    int n = 0;
    for (const Entry& e : entries) {
        if (!e.isDir || e.symlink) continue;
        if (++n > 200) break;
        const QString sub = e.path;
        {
            QMutexLocker lock(&g_cacheLock);
            if (g_cache.contains(sub)) continue;   // read this run already
        }
        readAhead().start([sub, gen] {
            if (g_readAheadGen.load() != gen) return;
            QString error;
            readAndKeep(sub, &error);
        });
    }
    Q_UNUSED(dir);
}

void FileListModel::reload() {
    const int generation = ++m_generation;
    const QString dir = m_dir;
    if (!m_opts.background || dir.startsWith(QLatin1String("tag:"))) {
        QString error;
        m_raw = list(dir, &error);
        m_rawDir = dir;
        m_error = error;
        setLoading(false);
        refilter();
        return;
    }
    // Another folder: what it held last time, at once, if it was seen
    // before; else empty, "Loading…", rather than the last one's contents
    // under the new one's name. The same folder read again (it changed on
    // disk) keeps what it shows until the new list is in.
    if (m_rawDir != dir) {
        std::vector<Entry> cached;
        m_error.clear();
        if (loadCached(dir, &cached)) {
            m_raw = std::move(cached);
            m_rawDir = dir;
            setLoading(false);
            refilter();
            emit reloaded();
            readAheadOf(dir, m_entries);   // in the order shown
            // Read a moment ago (ahead, or just before): as good as new.
            if (freshlyRead(dir)) return;
        } else {
            m_raw.clear();
            m_rawDir.clear();
            refilter();
            setLoading(true);
        }
    } else if (m_raw.empty()) {
        setLoading(true);
    }
    QPointer<FileListModel> self(this);
    std::thread([self, dir, generation]() {
        QString error;
        std::vector<Entry> raw = readAndKeep(dir, &error);
        QMetaObject::invokeMethod(qApp, [self, dir, generation, raw = std::move(raw), error]() mutable {
            if (!self || generation != self->m_generation) return;
            const bool wasShown = self->m_rawDir == dir;
            // Unchanged since it was shown from memory: nothing to redo, and
            // the view keeps its place.
            if (wasShown && error == self->m_error && sameListing(raw, self->m_raw)) {
                self->setLoading(false);
                return;
            }
            self->m_raw = std::move(raw);
            self->m_rawDir = dir;
            self->m_error = error;
            self->setLoading(false);
            self->refilter();
            emit self->reloaded();
            if (!wasShown) readAheadOf(dir, self->m_entries);
        }, Qt::QueuedConnection);
    }).detach();
}

void FileListModel::setLoading(bool on) {
    if (m_loading == on) return;
    m_loading = on;
    emit loadingChanged();
}

void FileListModel::refilter() {
    beginResetModel();
    m_entries.clear();
    const QString needle = m_opts.filter.trimmed();
    m_entries.reserve(m_raw.size());
    for (const Entry& e : m_raw) {
        if (e.hidden && !m_opts.showHidden) continue;
        if (!needle.isEmpty() && !e.name.contains(needle, Qt::CaseInsensitive)) continue;
        m_entries.push_back(e);
    }
    sortEntries();

    // The selection keeps whatever is still here.
    QSet<QString> still;
    for (const Entry& e : m_entries)
        if (m_selected.contains(e.path)) still.insert(e.path);
    const bool selChanged = still.size() != m_selected.size();
    m_selected = still;
    if (m_current >= int(m_entries.size())) m_current = int(m_entries.size()) - 1;
    endResetModel();
    emit countChanged();
    if (selChanged) emit selectionChanged();
    // A selection asked for while the folder was still being read.
    if (m_hasPendingSelection && !m_loading) {
        m_hasPendingSelection = false;
        selectPaths(std::exchange(m_pendingSelection, {}));
    }
}

// "file2" before "file10": digit runs compare as numbers, the rest through
// the collator. QCollator's numeric mode does this only where the locale
// backend supports it, and in the C/POSIX locale it silently does not.
static int naturalCompare(const QCollator& coll, const QString& a, const QString& b) {
    int i = 0, j = 0;
    while (i < a.size() && j < b.size()) {
        if (a[i].isDigit() && b[j].isDigit()) {
            // Skip leading zeros, then the longer run is the larger number;
            // equal lengths compare digit by digit.
            while (i + 1 < a.size() && a[i] == u'0' && a[i + 1].isDigit()) ++i;
            while (j + 1 < b.size() && b[j] == u'0' && b[j + 1].isDigit()) ++j;
            const int si = i, sj = j;
            while (i < a.size() && a[i].isDigit()) ++i;
            while (j < b.size() && b[j].isDigit()) ++j;
            if (i - si != j - sj) return (i - si) < (j - sj) ? -1 : 1;
            const int c = QStringView(a).mid(si, i - si).compare(QStringView(b).mid(sj, j - sj));
            if (c != 0) return c;
        } else {
            int si = i, sj = j;
            while (i < a.size() && !a[i].isDigit()) ++i;
            while (j < b.size() && !b[j].isDigit()) ++j;
            const int c = coll.compare(QStringView(a).mid(si, i - si), QStringView(b).mid(sj, j - sj));
            if (c != 0) return c;
        }
    }
    return (a.size() - i) - (b.size() - j);
}

void FileListModel::sortEntries() {
    QCollator coll;
    coll.setNumericMode(true);          // "file2" before "file10"
    coll.setCaseSensitivity(Qt::CaseInsensitive);
    const QString field = m_opts.sortField;
    const bool asc = m_opts.ascending;
    std::stable_sort(m_entries.begin(), m_entries.end(), [&](const Entry& a, const Entry& b) {
        if (m_opts.dirsFirst && a.isDir != b.isDir) return a.isDir;
        int c = 0;
        if (field == "size") c = a.size < b.size ? -1 : (a.size > b.size ? 1 : 0);
        else if (field == "time") c = a.modified < b.modified ? -1 : (a.modified > b.modified ? 1 : 0);
        else if (field == "type") c = coll.compare(a.kind, b.kind);
        if (c == 0) c = naturalCompare(coll, a.name, b.name);
        return asc ? c < 0 : c > 0;
    });
}

QString FileListModel::summary() const {
    int dirs = 0, files = 0;
    for (const Entry& e : m_entries) (e.isDir ? dirs : files)++;
    QStringList parts;
    if (dirs) parts << QStringLiteral("%1 folder%2").arg(dirs).arg(dirs == 1 ? "" : "s");
    if (files) parts << QStringLiteral("%1 file%2").arg(files).arg(files == 1 ? "" : "s");
    return parts.isEmpty() ? QStringLiteral("Empty") : parts.join(", ");
}

int FileListModel::folderCount() const {
    int dirs = 0;
    for (const Entry& e : m_entries) if (e.isDir) ++dirs;
    return dirs;
}

// Total size of the selected files ("" when none have a size); folders count
// for nothing until they are measured.
QString FileListModel::selectionSize() const {
    qint64 bytes = 0;
    for (const Entry& e : m_entries)
        if (!e.isDir && m_selected.contains(e.path)) bytes += e.size;
    return bytes > 0 ? formatSize(bytes) : QString();
}

bool FileListModel::selectionHasFolders() const {
    for (const Entry& e : m_entries)
        if (e.isDir && m_selected.contains(e.path)) return true;
    return false;
}

QString FileListModel::selectionSummary() const {
    if (m_selected.isEmpty()) return {};
    qint64 bytes = 0;
    int dirs = 0;
    for (const Entry& e : m_entries) {
        if (!m_selected.contains(e.path)) continue;
        if (e.isDir) ++dirs; else bytes += e.size;
    }
    const int n = int(m_selected.size());
    QString s = n == 1 ? QStringLiteral("1 item selected") : QStringLiteral("%1 items selected").arg(n);
    if (bytes > 0) s += ", " + formatSize(bytes) + (dirs ? " in files" : "");
    return s;
}

void FileListModel::setCurrentIndex(int i) {
    i = std::clamp(i, -1, int(m_entries.size()) - 1);
    if (i == m_current) return;
    m_current = i;
    emit currentIndexChanged();
}

void FileListModel::emitSelectionRows() {
    if (!m_entries.empty())
        emit dataChanged(index(0), index(int(m_entries.size()) - 1), {SelectedRole});
    emit selectionChanged();
}

void FileListModel::select(int row, int mode) {
    if (row < 0 || row >= int(m_entries.size())) return;
    const QString& p = m_entries[size_t(row)].path;
    if (mode == 1) {
        if (m_selected.contains(p)) m_selected.remove(p); else m_selected.insert(p);
        m_anchor = row;
    } else if (mode == 2 || mode == 3) {
        if (mode == 2) m_selected.clear();
        const int from = m_anchor < 0 ? row : m_anchor;
        for (int i = std::min(from, row); i <= std::max(from, row); ++i)
            m_selected.insert(m_entries[size_t(i)].path);
    } else {
        m_selected.clear();
        m_selected.insert(p);
        m_anchor = row;
    }
    setCurrentIndex(row);
    emitSelectionRows();
}

void FileListModel::selectAll() {
    for (const Entry& e : m_entries) m_selected.insert(e.path);
    emitSelectionRows();
}

void FileListModel::clearSelection() {
    if (m_selected.isEmpty()) return;
    m_selected.clear();
    emitSelectionRows();
}

void FileListModel::selectPaths(const QStringList& paths) {
    // Not read yet (a network drive): kept for when it is.
    if (m_loading) {
        m_pendingSelection = paths;
        m_hasPendingSelection = true;
        return;
    }
    m_selected.clear();
    int first = -1;
    for (int i = 0; i < int(m_entries.size()); ++i) {
        if (paths.contains(m_entries[size_t(i)].path)) {
            m_selected.insert(m_entries[size_t(i)].path);
            if (first < 0) first = i;
        }
    }
    if (first >= 0) { m_anchor = first; setCurrentIndex(first); }
    emitSelectionRows();
}

QStringList FileListModel::selectedPaths() const {
    QStringList out;
    // In display order, which is the order a person expects them pasted in.
    for (const Entry& e : m_entries)
        if (m_selected.contains(e.path)) out << e.path;
    return out;
}

bool FileListModel::isSelected(int row) const {
    return row >= 0 && row < int(m_entries.size()) && m_selected.contains(m_entries[size_t(row)].path);
}

QVariantMap FileListModel::get(int row) const {
    QVariantMap m;
    if (row < 0 || row >= int(m_entries.size())) return m;
    const QHash<int, QByteArray> roles = roleNames();
    for (auto it = roles.cbegin(); it != roles.cend(); ++it)
        m[QString::fromUtf8(it.value())] = data(index(row), it.key());
    return m;
}

int FileListModel::indexOfPath(const QString& path) const {
    for (int i = 0; i < int(m_entries.size()); ++i)
        if (m_entries[size_t(i)].path == path) return i;
    return -1;
}

int FileListModel::findPrefix(const QString& prefix, int from) const {
    if (prefix.isEmpty() || m_entries.empty()) return -1;
    const int n = int(m_entries.size());
    for (int k = 0; k < n; ++k) {
        const int i = (std::max(0, from) + k) % n;
        if (m_entries[size_t(i)].name.startsWith(prefix, Qt::CaseInsensitive)) return i;
    }
    return -1;
}

} // namespace b1air
