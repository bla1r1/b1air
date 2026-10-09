#pragma once

#include <QAbstractListModel>
#include <QDateTime>
#include <QFileSystemWatcher>
#include <QSet>
#include <QTimer>
#include <vector>

namespace b1air {

/**
 * One directory's entries, sorted and filtered, with a selection.
 *
 * Replaces Qt's FolderListModel, which the window used before. That model
 * could not open a folder whose name holds "#" or "%" (it never reached the
 * Ready state, whatever form the URL took), knew nothing about selections, so
 * the window could hold one selected path and no more, and gave no file type
 * beyond the suffix. This one lists with QDir, types with QMimeDatabase, keeps
 * a set of selected paths that survives a refresh, and reloads by itself when
 * the directory changes on disk.
 */
class FileListModel : public QAbstractListModel {
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY countChanged)
    Q_PROPERTY(int selectionCount READ selectionCount NOTIFY selectionChanged)
    /** "3 items selected, 12.4 MB" — or empty. */
    Q_PROPERTY(QString selectionSummary READ selectionSummary NOTIFY selectionChanged)
    /** "4 folders, 12 files" for the whole listing. */
    Q_PROPERTY(QString summary READ summary NOTIFY countChanged)
    // The numbers behind summary and selectionSummary, for a UI that words
    // them itself (in another language, say).
    Q_PROPERTY(int folderCount READ folderCount NOTIFY countChanged)
    Q_PROPERTY(int fileCount READ fileCount NOTIFY countChanged)
    Q_PROPERTY(QString selectionSize READ selectionSize NOTIFY selectionChanged)
    Q_PROPERTY(bool selectionHasFolders READ selectionHasFolders NOTIFY selectionChanged)
    /** The keyboard cursor and the anchor for Shift-selection. */
    Q_PROPERTY(int currentIndex READ currentIndex WRITE setCurrentIndex NOTIFY currentIndexChanged)
    /** Set when the directory could not be read (permissions, gone). */
    Q_PROPERTY(QString error READ error NOTIFY countChanged)
    /** A folder on a network drive being read in the background. */
    Q_PROPERTY(bool loading READ loading NOTIFY loadingChanged)

public:
    enum Roles {
        NameRole = Qt::UserRole + 1,
        PathRole,
        IsDirRole,
        SizeRole,
        SizeTextRole,
        ModifiedRole,
        ModifiedTextRole,
        KindRole,
        CategoryRole,
        IsImageRole,
        HiddenRole,
        SymlinkRole,
        SelectedRole,
        TagsRole,
    };
    Q_ENUM(Roles)

    struct Entry {
        QString name;
        QString path;
        bool isDir = false;
        qint64 size = 0;
        QDateTime modified;
        QString kind;       // "PNG image", "Folder"
        QString category;   // folder|image|video|audio|code|text|archive|pdf|document|executable|file
        bool hidden = false;
        bool symlink = false;
        QStringList tags;   // colour tags (tags.hpp)
    };

    explicit FileListModel(QObject* parent = nullptr);

    int rowCount(const QModelIndex& parent = QModelIndex()) const override;
    QVariant data(const QModelIndex& index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;

    int count() const { return int(m_entries.size()); }
    int selectionCount() const { return int(m_selected.size()); }
    QString selectionSummary() const;
    int folderCount() const;
    int fileCount() const { return int(m_entries.size()) - folderCount(); }
    QString selectionSize() const;
    bool selectionHasFolders() const;
    QString summary() const;
    int currentIndex() const { return m_current; }
    void setCurrentIndex(int i);
    QString error() const { return m_error; }
    bool loading() const { return m_loading; }

    struct Options {
        bool showHidden = false;
        bool dirsFirst = true;
        QString sortField = "name";   // name | size | time | type
        bool ascending = true;
        QString filter;
        // Read on a worker thread (a network drive): the window shows the
        // folder at once and its contents when they come.
        bool background = false;
    };
    /**
     * List `dir` with these options. Keeps the selection for paths still
     * present. `relist` false, for the same folder, only filters and sorts
     * again what was read — a change of sort or search, not of the folder.
     */
    void load(const QString& dir, const Options& opts, bool relist = true);
    /** For a model made in QML (the column view's other columns): `dir`, names first, folders first. */
    Q_INVOKABLE void open(const QString& dir, bool showHidden = false);
    void reload();
    QString directory() const { return m_dir; }

    // Selection. mode: 0 replace, 1 toggle (Ctrl), 2 range from the anchor
    // (Shift), 3 range added to what is selected (Ctrl+Shift).
    Q_INVOKABLE void select(int row, int mode = 0);
    Q_INVOKABLE void selectAll();
    Q_INVOKABLE void clearSelection();
    Q_INVOKABLE void selectPaths(const QStringList& paths);
    Q_INVOKABLE QStringList selectedPaths() const;
    Q_INVOKABLE bool isSelected(int row) const;
    Q_INVOKABLE QVariantMap get(int row) const;
    Q_INVOKABLE int indexOfPath(const QString& path) const;
    /** First row whose name starts with `prefix` (type-to-find), from `from`. */
    Q_INVOKABLE int findPrefix(const QString& prefix, int from = 0) const;

    static QString formatSize(qint64 bytes);
    static QString categoryFor(const QString& mimeName, bool isDir, bool executable);

signals:
    void countChanged();
    void selectionChanged();
    void currentIndexChanged();
    /** The directory was re-read because it changed on disk. */
    void reloaded();
    void loadingChanged();

private:
    void sortEntries();
    void emitSelectionRows();
    // Everything in `dir`, hidden files too, unfiltered: what a worker reads.
    static std::vector<Entry> list(const QString& dir, QString* error);
    // list(), and what it found kept for the next time (network folders).
    static std::vector<Entry> readAndKeep(const QString& dir, QString* error);
    // The folders inside `dir`, read ahead in the background.
    static void readAheadOf(const QString& dir, const std::vector<Entry>& entries);
    // `m_raw` through the options into the rows shown.
    void refilter();
    void setLoading(bool on);

    std::vector<Entry> m_raw;     // the folder as read, before filter and sort
    QString m_rawDir;             // which folder m_raw is
    bool m_loading = false;
    int m_generation = 0;         // a read that comes back late is dropped
    QStringList m_pendingSelection;
    bool m_hasPendingSelection = false;

    std::vector<Entry> m_entries;
    QSet<QString> m_selected;
    int m_current = -1;
    int m_anchor = -1;
    QString m_dir;
    QString m_error;
    Options m_opts;
    QFileSystemWatcher m_watcher;
    QTimer m_reloadDebounce;
};

} // namespace b1air
