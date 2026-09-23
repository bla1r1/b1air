#include "dir_model.hpp"

#include <QCollator>
#include <QDir>
#include <QFileInfo>
#include <QLocale>
#include <QMimeDatabase>
#include <algorithm>

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
        {SelectedRole, "selected"},
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
    }
    return {};
}

void FileListModel::load(const QString& dir, const Options& opts) {
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
    reload();
}

void FileListModel::reload() {
    static QMimeDatabase mimeDb;
    beginResetModel();
    m_entries.clear();
    m_error.clear();

    QDir d(m_dir);
    if (!d.exists()) {
        m_error = "This folder no longer exists.";
    } else if (!QFileInfo(m_dir).isReadable()) {
        m_error = "You do not have permission to see what is in this folder.";
    } else {
        QDir::Filters f = QDir::AllEntries | QDir::NoDotAndDotDot | QDir::System;
        if (m_opts.showHidden) f |= QDir::Hidden;
        const QString needle = m_opts.filter.trimmed();
        const QFileInfoList infos = d.entryInfoList(f, QDir::NoSort);
        m_entries.reserve(size_t(infos.size()));
        for (const QFileInfo& fi : infos) {
            if (!needle.isEmpty() && !fi.fileName().contains(needle, Qt::CaseInsensitive)) continue;
            Entry e;
            e.name = fi.fileName();
            e.path = fi.absoluteFilePath();
            e.isDir = fi.isDir();
            e.size = e.isDir ? 0 : fi.size();
            e.modified = fi.lastModified();
            e.hidden = fi.isHidden();
            e.symlink = fi.isSymLink();
            if (e.isDir) {
                e.kind = "Folder";
                e.category = "folder";
            } else {
                // By name first: reading the content of every file to type
                // it would make a folder of large videos slow to open.
                QMimeType mt = mimeDb.mimeTypeForFile(fi, QMimeDatabase::MatchExtension);
                if (mt.isDefault() && fi.suffix().isEmpty() && fi.size() < (64 << 20))
                    mt = mimeDb.mimeTypeForFile(fi, QMimeDatabase::MatchContent);
                e.kind = mt.comment().isEmpty() ? mt.name() : mt.comment();
                if (!e.kind.isEmpty()) e.kind[0] = e.kind[0].toUpper();
                e.category = categoryFor(mt.name(), false, fi.isExecutable() && mt.inherits("application/octet-stream"));
            }
            m_entries.push_back(std::move(e));
        }
        sortEntries();
    }

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
            const int c = coll.compare(a.mid(si, i - si), b.mid(sj, j - sj));
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
