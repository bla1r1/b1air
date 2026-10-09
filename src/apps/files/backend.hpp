#pragma once

#include <QObject>
#include <QString>
#include <QVariantList>
#include <QVariantMap>
#include <QStringList>
#include <QDateTime>
#include <QFileInfo>
#include <QDir>
#include <QStorageInfo>
#include <QProcess>
#include <QTimer>
#include "dir_model.hpp"

namespace b1air {

class FileManagerBackend : public QObject {
    Q_OBJECT

    Q_PROPERTY(QString currentPath READ currentPath WRITE setCurrentPath NOTIFY currentPathChanged)
    Q_PROPERTY(QString homePath READ homePath CONSTANT)
    Q_PROPERTY(bool canGoBack READ canGoBack NOTIFY historyChanged)
    Q_PROPERTY(bool canGoForward READ canGoForward NOTIFY historyChanged)
    Q_PROPERTY(bool showHidden READ showHidden WRITE setShowHidden NOTIFY showHiddenChanged)
    Q_PROPERTY(QString filterQuery READ filterQuery WRITE setFilterQuery NOTIFY filterQueryChanged)
    Q_PROPERTY(QString viewMode READ viewMode WRITE setViewMode NOTIFY viewModeChanged)
    Q_PROPERTY(QString sortField READ sortField WRITE setSortField NOTIFY sortChanged)
    Q_PROPERTY(bool sortAscending READ sortAscending WRITE setSortAscending NOTIFY sortChanged)
    Q_PROPERTY(QVariantList breadcrumbs READ breadcrumbs NOTIFY currentPathChanged)
    Q_PROPERTY(QVariantList places READ places CONSTANT)
    Q_PROPERTY(QString diskFreeSpace READ diskFreeSpace NOTIFY diskInfoChanged)
    Q_PROPERTY(QString diskTotalSpace READ diskTotalSpace NOTIFY diskInfoChanged)
    // Folder-chooser mode: `b1air-files --pick-folder <file> [start]`. Another
    // application needs a directory chosen, and this desktop has a file
    // manager — so it is used, rather than each app raising Qt's own dialog,
    // which looks and behaves like nothing else here.
    Q_PROPERTY(bool pickMode READ pickMode CONSTANT)
    // The listing of the current folder, with its selection.
    Q_PROPERTY(QObject* files READ files CONSTANT)
    Q_PROPERTY(bool dirsFirst READ dirsFirst WRITE setDirsFirst NOTIFY sortChanged)
    // Trash: where it is, whether we are in it, how much is in it.
    Q_PROPERTY(QString trashPath READ trashPath CONSTANT)
    Q_PROPERTY(bool inTrash READ inTrash NOTIFY currentPathChanged)
    Q_PROPERTY(int trashCount READ trashCount NOTIFY trashChanged)
    // Mounted drives other than the system one: [{name, path, free, total, percent, removable}]
    Q_PROPERTY(QVariantList volumes READ volumes NOTIFY volumesChanged)
    // Network shares mounted through gvfs (smb://, sftp://, …), as folders
    // under $XDG_RUNTIME_DIR/gvfs: [{name, server, path, uri}]
    Q_PROPERTY(QVariantList shares READ shares NOTIFY sharesChanged)
    // Servers connected to before, newest first: [{uri, user, domain}] —
    // never a password.
    Q_PROPERTY(QVariantList recentServers READ recentServers NOTIFY recentServersChanged)
    // A connection is being made.
    Q_PROPERTY(bool connecting READ connecting NOTIFY connectingChanged)
    // What Ctrl+Z would undo: "Move 3 items", "Rename", "Move to Trash" — or "".
    Q_PROPERTY(QString undoLabel READ undoLabel NOTIFY undoChanged)
    // A paste is copying in the background.
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)

public:
    explicit FileManagerBackend(QObject* parent = nullptr);
    virtual ~FileManagerBackend() = default;

    QString currentPath() const;
    // The real home directory. The QML side used to derive this from
    // currentPath, so opening the app on a folder made that folder "home":
    // every Favorites entry then pointed inside it and the breadcrumb
    // labelled it "~".
    QString homePath() const { return QDir::homePath(); }

    bool pickMode() const { return !m_pickResultPath.isEmpty(); }
    void setPickResultPath(const QString& path) { m_pickResultPath = path; }
    /** Write the current directory where the caller is waiting for it, and go. */
    Q_INVOKABLE void confirmPick();
    Q_INVOKABLE void cancelPick();
    void setCurrentPath(const QString& path);

    bool canGoBack() const;
    bool canGoForward() const;

    bool showHidden() const;
    void setShowHidden(bool show);

    QString filterQuery() const;
    void setFilterQuery(const QString& query);

    QString viewMode() const;
    void setViewMode(const QString& mode);

    QString sortField() const;
    void setSortField(const QString& field);

    bool sortAscending() const;
    void setSortAscending(bool asc);

    QVariantList breadcrumbs() const;
    QVariantList places() const;
    QString diskFreeSpace() const;
    QString diskTotalSpace() const;
    // Free space of the disk `path` is on, for a row that names its own.
    Q_INVOKABLE QString freeSpaceOf(const QString& path) const;
    bool busy() const { return m_busy; }
    QObject* files() const { return m_files; }
    bool dirsFirst() const { return m_dirsFirst; }
    void setDirsFirst(bool v);
    QString trashPath() const;
    bool inTrash() const { return m_currentPath == trashPath(); }
    int trashCount() const { return m_trashCount; }
    QVariantList volumes() const { return m_volumes; }
    QVariantList shares() const { return m_shares; }
    QVariantList recentServers() const { return m_recentServers; }
    bool connecting() const { return m_connecting; }
    QString undoLabel() const { return m_undo.isEmpty() ? QString() : m_undo.last().label; }

public slots:
    void refresh();
    void historyBack();
    void historyForward();
    void goUp();
    void openItem(const QString& path);
    bool isArchive(const QString& path) const;
    bool extractArchive(const QString& path);
    void openTerminal(const QString& path = QString());
    void triggerQuickLook(const QString& path);
    void setWallpaper(const QString& path);
    bool createFolder(const QString& name);
    bool deleteItem(const QString& path);
    bool renameItem(const QString& oldPath, const QString& newName);
    // Batch rename: paths[i] gets names[i], all in one undo step. Returns
    // "" on success or why nothing was renamed — checked before any file
    // moves, so it is all or none.
    QString renameMany(const QStringList& paths, const QStringList& names);

    // Bookmarks were a plain QML array with a hard-coded first entry and no
    // store of any kind: the "+" in the sidebar appended to it, the row
    // appeared, and closing the window threw it away. Kept beside the rest of
    // this suite's per-app state in ~/.config/b1air.
    QVariantList loadBookmarks() const;

    // Colour tags (tags.hpp): on, or off when every one of them has it.
    void toggleTag(const QStringList& paths, const QString& tag);
    QStringList tagsOf(const QString& path) const;
    // {Red: 3, …} for the sidebar's Tags.
    QVariantMap tagCounts() const;
    // Listing a tag ("tag:Red"), not a folder: nothing is made or pasted here.
    Q_INVOKABLE bool inTagView() const { return m_currentPath.startsWith(QLatin1String("tag:")); }
    void saveBookmarks(const QVariantList& bookmarks) const;

    // View preferences (hidden files, sort, folders first, view mode), kept
    // beside the bookmarks so the window opens the way it was left.
    QVariantMap loadPrefs() const;
    void savePrefs(const QVariantMap& prefs) const;

    // For "Copy path": QML has no clipboard of its own.
    void copyText(const QString& text) const;

    // Copy, cut and paste of files, through the system clipboard in the
    // formats other file managers use (text/uri-list, plus GNOME's
    // x-special/gnome-copied-files for cut), so a copy here pastes in
    // Nautilus or Dolphin and the other way round.
    void copyFiles(const QStringList& paths, bool cut);
    bool clipboardHasFiles() const;
    // Into the current folder, on a worker thread; pasteFinished reports.
    void paste();
    // A new empty file in the current folder.
    bool createFile(const QString& name);

    // Undo the last move, rename, copy or trashing.
    void undo();
    bool pathExists(const QString& path) const { return QFileInfo::exists(path); }
    bool isDirectory(const QString& path) const { return QFileInfo(path).isDir(); }

    // Several at once: what the selection works on.
    bool trashItems(const QStringList& paths);
    bool deletePermanently(const QStringList& paths);
    bool restoreFromTrash(const QStringList& paths);
    void emptyTrash();
    // Deletes trashed items older than `days` (by their DeletionDate) and
    // returns how many went. Static: `b1air-files --purge-trash` runs it at
    // login without opening a window.
    static int purgeTrash(int days);
    // The age limit from the prefs file; 0 means keep everything.
    static int trashPurgeDays();
    // Packs `paths` into <currentPath>/<name>.<format> on the worker thread
    // (zip, tar.gz, tar.zst or 7z). Reports through pasteFinished.
    void compressItems(const QStringList& paths, const QString& name, const QString& format);
    // Copy or move `sources` into `destDir` on the worker thread — drag and
    // drop, and "Move to…"/"Copy to…". Reports through pasteFinished.
    void transfer(const QStringList& sources, const QString& destDir, bool move);
    // Mounted drives.
    bool unmount(const QString& path);
    // Connect to a share — "smb://nas/media", "\\nas\media", "nas/media" —
    // through gvfs (gio mount), and go there; serverConnected reports. An
    // empty user is a guest. The password goes to gio on its stdin, never
    // on a command line.
    void connectServer(const QString& address, const QString& user,
                       const QString& domain, const QString& password);
    void forgetServer(const QString& uri);
    // "smb://nas/media" for what was typed, or "" when it is no address.
    Q_INVOKABLE QString serverUri(const QString& address) const;
    // Where gvfs shows its mounts as folders: $XDG_RUNTIME_DIR/gvfs.
    static QString gvfsRoot();
    // Applications that open this file: [{id, name, isDefault}]
    QVariantList openWithApps(const QString& path) const;
    void openWith(const QString& desktopId, const QStringList& paths);
    // Name, kind, size, dates, permissions, owner. A folder's total size
    // arrives later through folderSizeReady.
    QVariantMap itemInfo(const QString& path);

signals:
    void currentPathChanged();
    void historyChanged();
    void showHiddenChanged();
    void filterQueryChanged();
    void viewModeChanged();
    void sortChanged();
    void diskInfoChanged();
    void errorOccurred(const QString& message);
    void busyChanged();
    void pasteFinished(bool ok, const QString& message);
    void trashChanged();
    void undoChanged();
    void volumesChanged();
    void sharesChanged();
    void recentServersChanged();
    void connectingChanged();
    void serverConnected(bool ok, const QString& path, const QString& message);
    // An address that named a server and no share: what it shares, to pick.
    void sharesListed(const QString& uri, const QStringList& names);
    void folderSizeReady(const QString& path, const QString& sizeText, int fileCount);

private:
    QString m_pickResultPath;   // non-empty only in --pick-folder mode
    bool m_busy = false;
    bool m_dirsFirst = true;
    struct UndoOp {
        QString kind;                          // move | rename | copy | trash
        QList<QPair<QString, QString>> moves;  // done as first -> second
        QStringList paths;                     // copies made, or originals trashed
        QString label;
    };
    QList<UndoOp> m_undo;
    void pushUndo(const UndoOp& op);
    bool restoreOriginals(const QStringList& originals);
    int m_trashCount = 0;
    QVariantList m_volumes;
    QVariantList m_shares;
    QVariantList m_recentServers;
    bool m_connecting = false;
    void updateShares();
    void rememberServer(const QString& uri, const QString& user, const QString& domain);
    void openShare(const QString& target, const QString& uri, const QString& user, const QString& domain,
                   const QString& failure = {});
    void listShares(const QString& target, const QString& uri, const QString& failure = {});
    QTimer m_volumeTimer;
    FileListModel* m_files = nullptr;
    void loadFiles(bool relist = true);
    void updateTrashCount();
    void updateDiskInfo();
    QString m_freeText, m_totalText;
    int m_diskGen = 0;
    void updateVolumes();
    QString formatSize(qint64 bytes) const;
    void openWithDefaultApp(const QString& path);
    QString uniqueExtractDir(const QFileInfo& archive) const;
    bool extractWithLibarchive(const QString& archivePath, const QString& destDir, QString* error);

    QString m_currentPath;
    QStringList m_history;
    int m_historyIndex;
    bool m_showHidden;
    QString m_filterQuery;
    QString m_viewMode;
    QString m_sortField;
    bool m_sortAscending;
};

} // namespace b1air
