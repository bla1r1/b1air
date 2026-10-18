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
#include "syntax.hpp"

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
    // EmailRole: the author's email, for the avatar.
    // TagsRole: the tags on the commit, BranchesRole the branches (local and
    // remote) that point at it — git log's decorations, drawn as labels.
    enum Role { FullHashRole = Qt::UserRole + 1, HashRole, AuthorRole, TimeRole, MessageRole, SyncRole,
                CoAuthorsRole, EmailRole, TagsRole, BranchesRole };

    explicit HistoryModel(QObject* parent = nullptr) : QAbstractListModel(parent) {}

    int rowCount(const QModelIndex& parent = QModelIndex()) const override;
    QVariant data(const QModelIndex& index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;
    bool canFetchMore(const QModelIndex& parent) const override;
    void fetchMore(const QModelIndex& parent) override;

    int count() const { return m_rows.size(); }
    Q_INVOKABLE QString hashAt(int row) const;
    /** SyncRole of a row, for rows not on screen. */
    Q_INVOKABLE QString syncAt(int row) const { return row >= 0 && row < m_rows.size() ? syncStateOf(m_rows.at(row).fullHash) : QString(); }

    struct Commit { QString fullHash, hash, author; qint64 time; QString message; QStringList coAuthors; QString email;
                    QStringList tags, branches; };
    /**
     * A page of the log, newest first; safe off the GUI thread. range is a
     * revision range for git log ("HEAD..main"; empty is HEAD); filter keeps
     * the commits whose subject, author or hash has it in, any case.
     */
    static QList<Commit> readPage(const QString& repoPath, int skip, const QString& range = QString(),
                                  const QString& filter = QString());

    void setQuery(const QString& range, const QString& filter) { m_range = range; m_filter = filter; }
    QString range() const { return m_range; }
    QString filter() const { return m_filter; }

    /** Start again from the newest commit of the repository at path. */
    void reload(const QString& repoPath);
    /** The same, with the first page already read (GitBackend::refresh, on a worker). */
    void reset(const QString& repoPath, const QList<Commit>& firstPage);

    /**
     * Which commits are on no remote. Updated in place — a push changes every
     * row's state and nothing else, so it must not reset the list's scroll.
     */
    void setUnpushed(const QSet<QString>& hashes, bool hasRemote);
    QString syncStateOf(const QString& fullHash) const;

signals:
    void countChanged();

private:
    QList<Commit> readPage(int skip) const { return readPage(m_repoPath, skip, m_range, m_filter); }

    QString m_repoPath;
    QString m_range;
    QString m_filter;
    QList<Commit> m_rows;
    bool m_atEnd = true;
    QSet<QString> m_unpushed;
    bool m_hasRemote = false;
};

// What refresh() reads on the GUI thread and what a worker finds (git_backend.cpp).
struct GitRefresh;

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
    // { active, kind, branch, conflicts } while a merge, rebase, cherry-pick
    // or revert is in progress; kind is one of those four words. Each stops
    // on a conflict and waits to be continued or aborted.
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
    // HEAD: { hash, subject, body, time, canUndo }. canUndo while it is unpushed.
    Q_PROPERTY(QVariantMap lastCommit READ lastCommit NOTIFY syncChanged)
    // The remote as a web page (GitHub, GitLab, …), or empty.
    Q_PROPERTY(QString webUrl READ webUrl NOTIFY syncChanged)
    Q_PROPERTY(QString defaultBranch READ defaultBranch NOTIFY syncChanged)
    // git config user.name / user.email for this repository.
    Q_PROPERTY(QVariantMap identity READ identity NOTIFY syncChanged)
    Q_PROPERTY(QString selectedCommitSync READ selectedCommitSync NOTIFY syncChanged)
    // Signed-in hosting accounts, through the providers' own CLIs: gh for
    // GitHub, glab for GitLab. Each entry: provider, name, installed, login.
    Q_PROPERTY(QVariantList accounts READ accounts NOTIFY accountsChanged)
    // Every remote: { name, url }. For Repository settings.
    Q_PROPERTY(QVariantList remotes READ remotes NOTIFY syncChanged)
    // Diffs drawn with whitespace-only changes left out (git diff -w). Lines
    // cannot be staged one by one then: the rows are not the file's.
    Q_PROPERTY(bool ignoreWhitespace READ ignoreWhitespace WRITE setIgnoreWhitespace NOTIFY diffOptionsChanged)
    // The open pull requests of the repository on GitHub (gh pr list):
    // { number, title, branch, author, draft, updated }.
    Q_PROPERTY(QVariantList pullRequests READ pullRequests NOTIFY pullRequestsChanged)
    Q_PROPERTY(bool loadingPullRequests READ loadingPullRequests NOTIFY pullRequestsChanged)
    // The signed-in account's repositories on GitHub, for Clone:
    // { name, url, description, private, owner }.
    Q_PROPERTY(QVariantList remoteRepos READ remoteRepos NOTIFY remoteReposChanged)
    Q_PROPERTY(bool loadingRemoteRepos READ loadingRemoteRepos NOTIFY remoteReposChanged)
    // GitHub's .gitignore templates, by name, for New repository.
    Q_PROPERTY(QStringList gitignoreTemplates READ gitignoreTemplates NOTIFY gitignoreTemplatesChanged)
    // Where Clone and New repository put things unless told otherwise.
    Q_PROPERTY(QString defaultProjectsDir READ defaultProjectsDir CONSTANT)
    // History: what is searched for, and which branch the list is compared
    // with — "behind" lists its commits this branch lacks, "ahead" this
    // branch's that it lacks. Counts for both while a branch is picked.
    Q_PROPERTY(QString historyFilter READ historyFilter WRITE setHistoryFilter NOTIFY historyQueryChanged)
    Q_PROPERTY(QString compareBranch READ compareBranch NOTIFY historyQueryChanged)
    Q_PROPERTY(QString compareMode READ compareMode NOTIFY historyQueryChanged)
    Q_PROPERTY(int compareAhead READ compareAhead NOTIFY historyQueryChanged)
    Q_PROPERTY(int compareBehind READ compareBehind NOTIFY historyQueryChanged)
    // Branches only on a remote, to check out as GitHub Desktop's "Other
    // branches": "origin/feature", without the local ones that track them.
    Q_PROPERTY(QStringList remoteBranches READ remoteBranches NOTIFY branchChanged)
    // The whole file around the changes, not three lines of context.
    Q_PROPERTY(bool fullFile READ fullFile WRITE setFullFile NOTIFY diffOptionsChanged)
    // The pull request of the current branch on GitHub, if there is one:
    // { number, title, url, state, checks } — checks is "success",
    // "failure", "pending" or "" for none.
    Q_PROPERTY(QVariantMap currentPullRequest READ currentPullRequest NOTIFY currentPullRequestChanged)
    // Submodules: { path, commit, state } — state " " up to date, "+" at
    // another commit than recorded, "-" not checked out, "U" conflicted.
    Q_PROPERTY(QVariantList submodules READ submodules NOTIFY syncChanged)
    // Git LFS: { used, installed, ready } — the repository keeps files in
    // LFS, git-lfs is on this machine, and its filters are set up.
    Q_PROPERTY(QVariantMap lfs READ lfs NOTIFY syncChanged)
    // git config pull.rebase for this repository.
    Q_PROPERTY(bool pullRebase READ pullRebase NOTIFY syncChanged)

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
    /** Replay the current branch's own commits on top of another. */
    Q_INVOKABLE void rebaseBranch(const QString& onto);
    /** Merge the default branch in — its remote copy when there is one. */
    Q_INVOKABLE void updateFromDefault();
    /** Finish what mergeState describes, once its conflicts are staged. */
    Q_INVOKABLE void continueOperation();
    Q_INVOKABLE void abortOperation();
    // The old names, for the merge banner.
    Q_INVOKABLE void commitMerge() { continueOperation(); }
    Q_INVOKABLE void abortMerge() { abortOperation(); }
    /**
     * A conflicted file, settled with one side whole: "mine" is the branch
     * being worked on, "theirs" what is coming in. (In a rebase git's own
     * words are the other way round; this is what they mean to a person.)
     */
    Q_INVOKABLE void resolveWith(const QString& path, const QString& side);

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
    QVariantMap lastCommit() const { return m_lastCommit; }
    QString webUrl() const { return m_webUrl; }
    QString defaultBranch() const { return m_defaultBranch; }
    QVariantMap identity() const { return m_identity; }

    /** Take the last commit back; its changes stay staged, its message comes back. */
    Q_INVOKABLE void undoLastCommit();
    /** Throw away changes to files; a copy goes to the trash first. */
    Q_INVOKABLE void discardFiles(const QStringList& paths);
    Q_INVOKABLE void discardAll();
    /** Add a pattern to .gitignore. */
    Q_INVOKABLE void ignorePattern(const QString& pattern);
    Q_INVOKABLE void revertCommit(const QString& hash);
    /** Copy a commit onto a branch: the current one, or another (switched to first). */
    Q_INVOKABLE void cherryPick(const QString& hash, const QString& branch);
    /**
     * Move the branch back to a commit. What came after stays in the working
     * tree as uncommitted changes, as GitHub Desktop's "Reset to commit" does.
     */
    Q_INVOKABLE void resetToCommit(const QString& hash);
    /**
     * Fold a commit into the one before it, keeping both messages. Only for
     * commits that are on no remote: it rewrites them.
     */
    Q_INVOKABLE void squashIntoParent(const QString& hash);
    // Editing single commits, as an interactive rebase would, for commits on
    // no remote. Each rewrites from the commit up to HEAD.
    /** The commit's whole message, as written. */
    Q_INVOKABLE QString commitMessage(const QString& hash) const;
    Q_INVOKABLE void rewordCommit(const QString& hash, const QString& message);
    /**
     * Stop at the commit with its changes checked out: files changed and
     * staged then go into it when the rebase is continued.
     */
    Q_INVOKABLE void editCommit(const QString& hash);
    Q_INVOKABLE void dropCommit(const QString& hash);
    /** Swap with the next commit: direction +1 newer, -1 older. */
    Q_INVOKABLE void moveCommit(const QString& hash, int direction);
    /** Throw away single lines of the selected file's changes (rows of currentDiff). */
    Q_INVOKABLE void discardLines(const QVariantList& rows);
    /**
     * An image file as two pictures, before and after: { before, after } as
     * file:// URLs or "" where there is none. commit empty is the working tree.
     */
    Q_INVOKABLE QVariantMap imagePair(const QString& path, const QString& commit);
    Q_INVOKABLE void createBranchAt(const QString& name, const QString& hash);
    Q_INVOKABLE void createTag(const QString& name, const QString& hash);
    Q_INVOKABLE bool renameBranch(const QString& from, const QString& to);
    Q_INVOKABLE void openOnWeb();
    Q_INVOKABLE void openPullRequest();
    Q_INVOKABLE void refreshPullRequests();
    /** gh pr checkout: the pull request's branch, fetched and switched to. */
    Q_INVOKABLE void checkoutPullRequest(int number);
    Q_INVOKABLE void openPullRequestOnWeb(int number);

    /** Clone url into parentDir/<name>, then open it. */
    Q_INVOKABLE void cloneRepo(const QString& url, const QString& parentDir);
    Q_INVOKABLE void refreshRemoteRepos();
    /**
     * git init in parentDir/name, with a README and a .gitignore from
     * GitHub's templates if asked, and a first commit; then open it.
     */
    Q_INVOKABLE void createRepo(const QString& parentDir, const QString& name, const QString& description,
                                bool readme, const QString& gitignore);
    Q_INVOKABLE void refreshGitignoreTemplates();
    /** A repository with no remote, put on GitHub with gh repo create, and pushed. */
    Q_INVOKABLE void publishRepo(const QString& name, const QString& description, bool isPrivate);
    /** A folder chosen in Files; folderPicked(purpose, path) answers. */
    Q_INVOKABLE void pickFolder(const QString& purpose, const QString& start = QString());

    // Repository settings.
    Q_INVOKABLE bool setRemote(const QString& name, const QString& url);
    Q_INVOKABLE bool removeRemote(const QString& name);
    /** user.name and user.email, for this repository or (global) every one. */
    Q_INVOKABLE bool setIdentity(const QString& name, const QString& email, bool global);
    /** .gitignore in the editor, made first if there is none. */
    Q_INVOKABLE void editGitignore();
    /** The repository, or a file in it, in a code editor. */
    Q_INVOKABLE void openInEditor(const QString& relPath = QString());
    QString selectedCommitSync() const { return m_history->syncStateOf(m_selectedCommit); }
    QVariantList accounts() const { return m_accounts; }
    QVariantList remotes() const { return m_remotes; }
    bool ignoreWhitespace() const { return m_ignoreWhitespace; }
    void setIgnoreWhitespace(bool on);
    QVariantList pullRequests() const { return m_pullRequests; }
    bool loadingPullRequests() const { return m_loadingPrs; }
    QVariantList remoteRepos() const { return m_remoteRepos; }
    bool loadingRemoteRepos() const { return m_loadingRemoteRepos; }
    QStringList gitignoreTemplates() const { return m_gitignoreTemplates; }
    QString defaultProjectsDir() const;
    QString historyFilter() const { return m_history->filter(); }
    void setHistoryFilter(const QString& filter);
    QString compareBranch() const { return m_compareBranch; }
    QString compareMode() const { return m_compareMode; }
    int compareAhead() const { return m_compareAhead; }
    int compareBehind() const { return m_compareBehind; }
    QStringList remoteBranches() const { return m_remoteBranches; }
    QVariantList submodules() const { return m_submodules; }
    QVariantMap lfs() const { return m_lfs; }
    /** git submodule update --init --recursive. */
    Q_INVOKABLE void updateSubmodules();
    /** Set up Git LFS for this repository and fetch its files. */
    Q_INVOKABLE void setupLfs();
    bool fullFile() const { return m_fullFile; }
    void setFullFile(bool on);
    QVariantMap currentPullRequest() const { return m_currentPr; }
    bool pullRebase() const { return m_pullRebase; }
    Q_INVOKABLE void setPullRebase(bool on);
    Q_INVOKABLE void refreshCurrentPullRequest();
    /** Delete a tag here (not on the remote). */
    Q_INVOKABLE void deleteTag(const QString& name);
    Q_INVOKABLE void openCommitOnWeb(const QString& hash);
    /**
     * Put a commit just after another one, or (squash) fold it into that
     * one, as dragging one commit onto another does in GitHub Desktop.
     */
    Q_INVOKABLE void reorderCommit(const QString& hash, const QString& target, bool squash);
    /** Compare the history with a branch (empty: back to the plain log). */
    Q_INVOKABLE void setCompare(const QString& branch, const QString& mode);

    /**
     * The colours code is drawn in: keyword, string, comment, number, type,
     * as "#rrggbb". From the window, which knows the theme.
     */
    Q_INVOKABLE void setSyntaxPalette(const QVariantMap& colors);

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
    /** amend: replace the last commit with this one (its changes and these). */
    Q_INVOKABLE void commit(const QString& message, bool amend = false);
    /**
     * Stage or unstage single lines of the selected file: rows are indices
     * into currentDiff. The rest of the file stays as it was in the index.
     */
    Q_INVOKABLE void setLinesStaged(const QVariantList& rows, bool staged);
    /** Put every uncommitted change away for this branch (offered back on return). */
    Q_INVOKABLE void stashAll();
    Q_INVOKABLE void push();
    /** Push over what the remote has, unless it changed since the last fetch. */
    Q_INVOKABLE void forcePush();
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
    /** A commit went in; the window clears its message fields on this. */
    void committed();
    /** After an undo, for the commit fields. */
    void restoreMessage(const QString& summary, const QString& description);
    void syncChanged();
    void accountsChanged();
    void commandFailed(const QString& message);
    void diffOptionsChanged();
    void historyQueryChanged();
    void currentPullRequestChanged();
    void pullRequestsChanged();
    void remoteReposChanged();
    void gitignoreTemplatesChanged();
    void folderPicked(const QString& purpose, const QString& path);
    /** Clone or New repository finished; ok false keeps the dialog open. */
    void repoCreated(bool ok, const QString& path);

private:
    // trim=false for output whose leading whitespace is significant:
    // git status --porcelain encodes state in two columns, and a leading
    // space means "not staged". Trimming ate it on the first line, so the
    // top unstaged file read as staged and its button called unstage.
    QString runGit(const QStringList& args, bool trim = true);
    bool m_isRepo = false;
    // refresh() runs git on a worker; one at a time, and one more if asked
    // for while it ran.
    bool m_refreshing = false;
    bool m_refreshAgain = false;
    void applyRefresh(const GitRefresh& r);
    void updateDiff();

    bool m_hasRemote = false;
    QString m_upstream;
    int m_ahead = 0;
    int m_behind = 0;
    qint64 m_lastFetch = 0;
    // The remote push and fetch talk to: the upstream's, else "origin", else
    // the first one configured.
    QString m_remoteName;
    QVariantMap m_lastCommit;
    QString m_webUrl;
    QString m_defaultBranch;
    QVariantMap m_identity;

    QVariantList m_accounts;
    int m_accountProbes = 0;
    QVariantList m_remotes;
    bool m_ignoreWhitespace = false;
    syntax::Palette m_syntax;
    QVariantList m_pullRequests;
    bool m_loadingPrs = false;
    QString m_prsRepo;
    QVariantList m_remoteRepos;
    bool m_loadingRemoteRepos = false;
    QStringList m_gitignoreTemplates;
    QStringList m_remoteBranches;
    QVariantList m_submodules;
    QVariantMap m_lfs;
    bool m_fullFile = false;
    bool m_pullRebase = false;
    QVariantMap m_currentPr;
    QString m_currentPrKey;
    bool m_loadingCurrentPr = false;
    QString m_compareBranch;
    QString m_compareMode = "behind";
    int m_compareAhead = 0;
    int m_compareBehind = 0;
    void applyHistoryQuery();
    // Rewrites the commits after `base` (empty: from the root) to the todo
    // lines given, through rebase -i with this list in place of its own.
    void rewriteHistory(const QString& base, const QStringList& todo, const QString& busyText,
                        const QString& doneText);
    // The commits from just before `hash` to HEAD, oldest first, or empty
    // with an error said when they cannot be rewritten (pushed, merges, changes).
    QStringList rewritable(const QString& hash, QString* base, int extraBack = 0);
    // Runs a command that is not git in the repository (gh), output to done.
    void runTool(const QString& program, const QStringList& args, const QString& workdir,
                 std::function<void(bool, const QString&, const QString&)> done);
    // A task that needs no repository open: clone. Same busy state as runTask.
    void runTaskIn(const QString& workdir, const QString& kind, const QString& text, const QStringList& args,
                   std::function<void(bool, const QString&, const QString&)> done);

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
