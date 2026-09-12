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

    // Bookmarks were a plain QML array with a hard-coded first entry and no
    // store of any kind: the "+" in the sidebar appended to it, the row
    // appeared, and closing the window threw it away. Kept beside the rest of
    // this suite's per-app state in ~/.config/b1air.
    QVariantList loadBookmarks() const;
    void saveBookmarks(const QVariantList& bookmarks) const;

    // View preferences (hidden files, sort, folders first, view mode), kept
    // beside the bookmarks so the window opens the way it was left.
    QVariantMap loadPrefs() const;
    void savePrefs(const QVariantMap& prefs) const;

    // For "Copy path": QML has no clipboard of its own.
    void copyText(const QString& text) const;

signals:
    void currentPathChanged();
    void historyChanged();
    void showHiddenChanged();
    void filterQueryChanged();
    void viewModeChanged();
    void sortChanged();
    void diskInfoChanged();
    void errorOccurred(const QString& message);

private:
    QString m_pickResultPath;   // non-empty only in --pick-folder mode
    QString formatSize(qint64 bytes) const;
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
