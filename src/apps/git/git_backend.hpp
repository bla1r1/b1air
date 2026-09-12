#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>
#include <QProcess>
#include <QAbstractListModel>
#include <QHash>
#include <QSet>
#include <QTimer>
#include <functional>

/**
 * The commit log of HEAD, read a page at a time.
 *
 * History used to be a QVariantList of the newest 20 commits — nothing older
 * could be reached at all. A plain list cannot simply be made longer: QML
 * copies the whole of it on every read, and a ListView given a new array jumps
 * back to the top, so "load more on scroll" would throw the user back to the
 * start each time. A model appends rows in place, and ListView asks for the
 * next page itself through canFetchMore()/fetchMore() when it nears the end.
 */
class HistoryModel : public QAbstractListModel {
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY countChanged)

public:
    // TimeRole is the commit time in seconds. The window words it itself:
    // git's own %cr says "9 weeks ago" until the tenth week before it switches
    // to months, which reads wrong for anything past a month.
    // SyncRole is "pushed", "local" (on no remote yet) or "" when the
    // repository has no remote to push to, where the question does not apply.
    // CoAuthorsRole: the names from Co-authored-by trailers. The row showed
    // the author alone, so a commit written by two people credited one.
    enum Role { FullHashRole = Qt::UserRole + 1, HashRole, AuthorRole, TimeRole, MessageRole, SyncRole,
                CoAuthorsRole };

    explicit HistoryModel(QObject* parent = nullptr) : QAbstractListModel(parent) {}

    int rowCount(const QModelIndex& parent = QModelIndex()) const override;
    QVariant data(const QModelIndex& index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;
    bool canFetchMore(const QModelIndex& parent) const override;
    void fetchMore(const QModelIndex& parent) override;

    int count() const { return m_rows.size(); }
    Q_INVOKABLE QString hashAt(int row) const;

    /** Start again from the newest commit of the repository at path. */
    void reload(const QString& repoPath);

    /**
     * Which commits are on no remote. Updated in place — a push changes every
     * row's state and nothing else, so it must not reset the list's scroll.
     */
    void setUnpushed(const QSet<QString>& hashes, bool hasRemote);
    QString syncStateOf(const QString& fullHash) const;

signals:
    void countChanged();

private:
    struct Commit { QString fullHash, hash, author; qint64 time; QString message; QStringList coAuthors; };
    QList<Commit> readPage(int skip) const;

    QString m_repoPath;
    QList<Commit> m_rows;
    bool m_atEnd = true;
    QSet<QString> m_unpushed;
    bool m_hasRemote = false;
};

class GitBackend : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString repoPath READ repoPath NOTIFY repoChanged)
    Q_PROPERTY(QString repoName READ repoName NOTIFY repoChanged)
    Q_PROPERTY(bool isRepo READ isRepo NOTIFY repoChanged)
    Q_PROPERTY(QString branchName READ branchName NOTIFY branchChanged)
    Q_PROPERTY(QVariantList branches READ branches NOTIFY branchChanged)
    // name → { upstream, gone, ahead, behind } for each local branch. "gone"
    // is a branch whose remote counterpart was deleted — on GitHub, say, after
    // a merged pull request. Nothing showed that: the branch looked exactly
    // like one still on the remote, and without a prune the remote-tracking
    // ref it was compared against never went away either.
    Q_PROPERTY(QVariantMap branchInfo READ branchInfo NOTIFY branchChanged)
    // Changes this app stashed when leaving the current branch, waiting to be
    // restored here: { ref, files } or empty.
    Q_PROPERTY(QVariantMap branchStash READ branchStash NOTIFY branchChanged)
    Q_PROPERTY(bool upstreamGone READ upstreamGone NOTIFY syncChanged)
    // { active, branch, conflicts } while a merge is in progress.
    Q_PROPERTY(QVariantMap mergeState READ mergeState NOTIFY statusChanged)
    // Every worktree of the repository: { path, branch, main, current }.
    Q_PROPERTY(QVariantList worktrees READ worktrees NOTIFY branchChanged)
    Q_PROPERTY(bool fetching READ fetching NOTIFY fetchingChanged)
    // The operation in progress: push, publish, pull, fetch, commit, checkout,
    // merge; empty when idle. progress is 0..100, or -1 when git gives none.
    Q_PROPERTY(QString busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(QString busyText READ busyText NOTIFY busyChanged)
    Q_PROPERTY(int progress READ progress NOTIFY busyChanged)
    Q_PROPERTY(QString statusSummary READ statusSummary NOTIFY statusChanged)
    Q_PROPERTY(QString selectedFile READ selectedFile NOTIFY selectedFileChanged)
    Q_PROPERTY(QVariantList changedFiles READ changedFiles NOTIFY statusChanged)
    Q_PROPERTY(HistoryModel* history READ history CONSTANT)
    Q_PROPERTY(QVariantList currentDiff READ currentDiff NOTIFY diffChanged)
    // The repositories this app knows about: the ones opened in it, and
    // nothing else. A property, not a function: the list used to be produced
    // by calling discoverRepos() inside a QML binding, which re-walked the
    // filesystem on every re-evaluation and — having no change signal — never
    // updated after one was added or removed.
    Q_PROPERTY(QVariantList repos READ repos NOTIFY reposChanged)
    // A commit picked in History, and what it changed. Kept apart from
    // selectedFile/currentDiff, which describe the working tree: History had
    // no state of its own, so a commit could not be opened at all — the list
    // was hover-only — and borrowing the Changes selection would have lost it
    // every time the tab was switched back.
    Q_PROPERTY(QString selectedCommit READ selectedCommit NOTIFY commitChanged)
    Q_PROPERTY(QVariantMap commitInfo READ commitInfo NOTIFY commitChanged)
    Q_PROPERTY(QVariantList commitFiles READ commitFiles NOTIFY commitChanged)
    Q_PROPERTY(QString commitFile READ commitFile NOTIFY commitDiffChanged)
    Q_PROPERTY(QVariantList commitDiff READ commitDiff NOTIFY commitDiffChanged)
    // Where the branch stands against its remote. Nothing said: push and pull
    // were two bare arrows, and whether there was anything to push was a
    // question for a terminal.
    Q_PROPERTY(bool hasRemote READ hasRemote NOTIFY syncChanged)
    Q_PROPERTY(QString upstream READ upstream NOTIFY syncChanged)
    Q_PROPERTY(int aheadCount READ aheadCount NOTIFY syncChanged)
    Q_PROPERTY(int behindCount READ behindCount NOTIFY syncChanged)
    // When this repository last fetched, in seconds, or 0 for never — the
    // mtime of .git/FETCH_HEAD, which every fetch and pull rewrites. The window
    // used to keep its own timestamp, which said "Never fetched" after every
    // restart and knew nothing of a fetch run in a terminal.
    Q_PROPERTY(qint64 lastFetchTime READ lastFetchTime NOTIFY syncChanged)
    Q_PROPERTY(QString remoteName READ remoteName NOTIFY syncChanged)
    Q_PROPERTY(QString selectedCommitSync READ selectedCommitSync NOTIFY syncChanged)
    // Signed-in hosting accounts, through the providers' own CLIs: gh for
    // GitHub, glab for GitLab. Each entry: provider, name, installed, login.
    Q_PROPERTY(QVariantList accounts READ accounts NOTIFY accountsChanged)

public:
    explicit GitBackend(QObject* parent = nullptr);

    QString repoPath() const { return m_repoPath; }
    QString repoName() const;
    bool isRepo() const { return m_isRepo; }
    QString branchName() const { return m_branchName; }
    QVariantList branches() const { return m_branches; }
    QVariantMap branchInfo() const { return m_branchInfo; }
    QVariantMap branchStash() const { return m_branchStash; }
    bool upstreamGone() const { return m_upstreamGone; }
    QVariantMap mergeState() const { return m_mergeState; }
    QVariantList worktrees() const { return m_worktrees; }

    /** Merge a branch into the current one. Conflicts leave the merge open. */
    Q_INVOKABLE void mergeBranch(const QString& branch);
    Q_INVOKABLE void commitMerge();
    Q_INVOKABLE void abortMerge();

    /** Check a branch out into a new worktree beside the main one. Returns its path. */
    Q_INVOKABLE QString createWorktree(const QString& branch);
    Q_INVOKABLE void removeWorktree(const QString& path);
    bool fetching() const { return m_bgFetch != nullptr; }
    QString busy() const { return m_busy; }
    QString busyText() const { return m_busyText; }
    int progress() const { return m_progress; }
    QString statusSummary() const { return m_statusSummary; }
    QString selectedFile() const { return m_selectedFile; }
    QVariantList changedFiles() const { return m_changedFiles; }
    HistoryModel* history() const { return m_history; }
    QVariantList currentDiff() const { return m_currentDiff; }
    QVariantList repos() const { return m_repos; }
    QString selectedCommit() const { return m_selectedCommit; }
    QVariantMap commitInfo() const { return m_commitInfo; }
    QVariantList commitFiles() const { return m_commitFiles; }
    QString commitFile() const { return m_commitFile; }
    QVariantList commitDiff() const { return m_commitDiff; }
    bool hasRemote() const { return m_hasRemote; }
    QString upstream() const { return m_upstream; }
    int aheadCount() const { return m_ahead; }
    int behindCount() const { return m_behind; }
    qint64 lastFetchTime() const { return m_lastFetch; }
    QString remoteName() const { return m_remoteName; }
    QString selectedCommitSync() const { return m_history->syncStateOf(m_selectedCommit); }
    QVariantList accounts() const { return m_accounts; }

    /** Re-read who is signed in. Asynchronous; accountsChanged when done. */
    Q_INVOKABLE void refreshAccounts();
    /**
     * Sign in in a terminal window. gh and glab both ask questions and print
     * a one-time code on the way; a terminal shows them as they are, where
     * scraping them into this window would break with the next CLI release.
     */
    Q_INVOKABLE void signIn(const QString& provider);
    Q_INVOKABLE void signOut(const QString& provider);

    /**
     * The repository to show at startup: the last one opened, if it still
     * exists, else the first known one, else home.
     */
    QString startupRepo() const;

    Q_INVOKABLE void openRepo(const QString& path);
    /** Open a commit from History: list its files and show the first. */
    Q_INVOKABLE void selectCommit(const QString& hash);
    /** Show one file of the selected commit. */
    Q_INVOKABLE void selectCommitFile(const QString& filePath);
    Q_INVOKABLE void refresh();
    Q_INVOKABLE void selectFile(const QString& filePath);
    Q_INVOKABLE void stageFile(const QString& filePath);
    Q_INVOKABLE void unstageFile(const QString& filePath);
    Q_INVOKABLE void stageAll();
    Q_INVOKABLE void unstageAll();
    Q_INVOKABLE void commit(const QString& message);
    Q_INVOKABLE void push();
    Q_INVOKABLE void pull();
    Q_INVOKABLE void fetch();
    /**
     * Check out a branch. With uncommitted changes the caller must say what
     * happens to them, as GitHub Desktop asks: "stash" leaves them on the
     * branch being left (stashed, and offered back on return), "bring" carries
     * them over. A plain checkout used to run regardless — git either carried
     * them silently or refused with an error, and the window never asked.
     */
    Q_INVOKABLE void switchBranch(const QString& branch, const QString& changes = QString());
    Q_INVOKABLE void restoreStash();
    Q_INVOKABLE void discardStash();
    Q_INVOKABLE bool createBranch(const QString& name);
    /**
     * Delete a branch. force is git's -D: it deletes one whose work is not
     * merged anywhere, and loses those commits. Without it git refuses and
     * says so, which is the answer the UI turns into a second question.
     */
    Q_INVOKABLE bool deleteBranch(const QString& name, bool force = false);

    /** Add a directory to the list and open it. Refuses one with no .git. */
    Q_INVOKABLE bool addRepo(const QString& path);
    /** Drop a repository from the list. Touches the list only, never the disk. */
    Q_INVOKABLE void forgetRepo(const QString& path);
    /**
     * Choose a folder with this desktop's own file manager.
     *
     * Qt's FolderDialog was what this used, and it is not the file manager the
     * rest of the desktop uses — a different window, different keys, different
     * idea of Favourites. b1air-files has a --pick-folder mode for this.
     */
    Q_INVOKABLE void pickRepoFolder();
    /**
     * Delete the working tree. To the trash, never with rm: a repository is
     * somebody's work, and the file manager beside it treats delete the same
     * way. The caller asks first — see the confirmation in GitWindow.qml.
     */
    Q_INVOKABLE bool trashRepo(const QString& path);
    // Paths are relative to the repository, or empty for the repository
    // itself. They are what the right-click menus call.
    Q_INVOKABLE void openTerminal(const QString& relPath = QString());
    Q_INVOKABLE void openFileManager(const QString& relPath = QString());
    Q_INVOKABLE void openFile(const QString& relPath);
    Q_INVOKABLE void copyText(const QString& text);
    Q_INVOKABLE QString absolutePath(const QString& relPath) const;

signals:
    void repoChanged();
    void branchChanged();
    void statusChanged();
    void selectedFileChanged();
    void diffChanged();
    void reposChanged();
    void commitChanged();
    void commitDiffChanged();
    void fetchingChanged();
    void busyChanged();
    /** A finished operation, for the window to show briefly. */
    void notice(const QString& message);
    void syncChanged();
    void accountsChanged();
    void commandFailed(const QString& message);

private:
    // trim=false for output whose leading whitespace is significant:
    // git status --porcelain encodes state in two columns, and a leading
    // space means "not staged". Trimming ate it on the first line, so the
    // top unstaged file read as staged and its button called unstage.
    QString runGit(const QStringList& args, bool trim = true);
    bool m_isRepo = false;
    void updateBranch();
    void updateStatus();
    void updateHistory();
    void updateSync();
    void updateDiff();

    bool m_hasRemote = false;
    QString m_upstream;
    int m_ahead = 0;
    int m_behind = 0;
    qint64 m_lastFetch = 0;
    // The remote push and fetch talk to: the upstream's, else "origin", else
    // the first one configured.
    QString m_remoteName;

    QVariantList m_accounts;
    int m_accountProbes = 0;

    QString m_repoPath;
    QString m_branchName = "main";
    QVariantList m_branches;
    QVariantMap m_branchInfo;
    QVariantMap m_branchStash;
    bool m_upstreamGone = false;
    QVariantMap m_mergeState;

    QString m_busy;
    QString m_busyText;
    QString m_busyLabel;
    int m_progress = -1;
    // Runs git without blocking the window. done gets success, stdout, stderr.
    void runTask(const QString& kind, const QString& text, const QStringList& args,
                 std::function<void(bool, const QString&, const QString&)> done);
    QVariantList m_worktrees;
    // Git's own paths for this checkout; in a worktree .git is a file.
    QHash<QString, QString> m_gitPaths;
    void resolveGitPaths();
    QString gitPath(const QString& name) const { return m_gitPaths.value(name); }

    // Fetching in the background, so the branch and sync state follow the
    // remote without anyone pressing Fetch. See startBackgroundFetch().
    QProcess* m_bgFetch = nullptr;
    QTimer m_fetchTimer;
    qint64 m_lastFetchFailedAt = 0;
    void startBackgroundFetch();
    QString m_statusSummary = "Clean";
    QString m_selectedFile;
    QVariantList m_changedFiles;
    QVariantList m_currentDiff;

    HistoryModel* m_history;
    // The HEAD the history was read at. refresh() runs after every stage and
    // every poll that sees a change; re-reading the log each time would reset
    // the list and its scroll position for edits that cannot have changed it.
    QString m_historyHead;

    // ── Noticing changes made outside the app ──
    // Nothing did: a file edited in an editor, or a commit made in a terminal,
    // stayed invisible until Fetch or a restart, both of which happen to call
    // refresh(). See startPoll() for what is compared.
    QTimer m_pollTimer;
    QProcess* m_pollProc = nullptr;
    QString m_pollStamp;
    void startPoll();
    QString stamp(const QString& statusOut) const;

    QString m_selectedCommit;
    QVariantMap m_commitInfo;
    QVariantList m_commitFiles;
    QString m_commitFile;
    QVariantList m_commitDiff;
    void clearCommit();
    void updateCommitDiff();

    QVariantList m_repos;
    // The repository open when the app last had one. Separate from the order
    // of m_repos so that opening a repository does not reshuffle the list.
    QString m_lastRepo;
    void loadRepos();
    void saveRepos() const;
    void rememberRepo(const QString& path);
};
