#include "git_backend.hpp"
#include <algorithm>
#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QCoreApplication>
#include <QCryptographicHash>
#include <QDateTime>
#include <QClipboard>
#include <QDesktopServices>
#include <QGuiApplication>
#include <QUrl>
#include <QSaveFile>
#include <QStandardPaths>
#include <iterator>
#include <memory>
#include <iostream>

GitBackend::GitBackend(QObject* parent) : QObject(parent), m_history(new HistoryModel(this)) {
    // Loads the list only. main() decides what to open — it used to be opened
    // here and then again there, and the second call won.
    loadRepos();

    // Every two seconds, and only while the window has focus: a window in the
    // background has nobody looking at it, and the app is otherwise at 0% CPU
    // when idle. Coming back to the window checks at once, so what was done
    // elsewhere in the meantime is on screen by the time anyone looks.
    m_pollTimer.setInterval(2000);
    connect(&m_pollTimer, &QTimer::timeout, this, &GitBackend::startPoll);
    connect(qApp, &QGuiApplication::applicationStateChanged, this, [this](Qt::ApplicationState s) {
        if (s == Qt::ApplicationActive) {
            startPoll();
            m_pollTimer.start();
        } else {
            m_pollTimer.stop();
        }
    });
    if (QGuiApplication::applicationState() == Qt::ApplicationActive) m_pollTimer.start();

    // Signing in happens in a terminal window, so the moment this window is
    // focused again is the moment the answer may have changed.
    connect(qApp, &QGuiApplication::applicationStateChanged, this, [this](Qt::ApplicationState s) {
        if (s == Qt::ApplicationActive) refreshAccounts();
    });

    m_fetchTimer.setInterval(5 * 60 * 1000);
    connect(&m_fetchTimer, &QTimer::timeout, this, &GitBackend::startBackgroundFetch);
    connect(qApp, &QGuiApplication::applicationStateChanged, this, [this](Qt::ApplicationState s) {
        if (s != Qt::ApplicationActive) {
            m_fetchTimer.stop();
            return;
        }
        m_fetchTimer.start();
        // Ten seconds, not ten minutes. Coming back to this window is most
        // often coming back from the browser, where a branch was just merged
        // and deleted — and with a ten-minute allowance, a fetch made shortly
        // before (opening the app makes one) meant nothing was asked, so the
        // deleted branch went on reading as published. A fetch is one round
        // trip; the ten seconds only keep a quick alt-tab from repeating it.
        const qint64 age = QDateTime::currentSecsSinceEpoch() - m_lastFetch;
        if (age > 10) startBackgroundFetch();
    });
    refreshAccounts();
}

// ── The known repositories ───────────────────────────────────────────────────
//
// The list is exactly what has been opened in this app, persisted beside the
// other apps' settings in ~/.config/b1air. There is deliberately no scan: this
// used to walk six hardcoded directory names one level deep, which both missed
// the repository actually in use — three levels down — and filled the list with
// whatever else it stumbled over. Which repositories matter is not something
// the disk can be asked.

namespace {

QString reposPath() {
    const QString dir = QStandardPaths::writableLocation(QStandardPaths::GenericConfigLocation)
                        + "/b1air";
    QDir().mkpath(dir);
    return dir + "/git_repos.json";
}

bool isRepoDir(const QString& path) {
    return !path.isEmpty() && QFileInfo::exists(path + "/.git");
}

/** Run git somewhere without reporting failure: the caller wants the answer. */
bool gitOk(const QString& workdir, const QStringList& args, QString* err = nullptr,
           QString* out = nullptr) {
    QProcess proc;
    proc.setWorkingDirectory(workdir);
    proc.start("git", args);
    proc.waitForFinished(30000);
    if (err) *err = QString::fromUtf8(proc.readAllStandardError()).trimmed();
    if (out) *out = QString::fromUtf8(proc.readAllStandardOutput());
    return proc.exitStatus() == QProcess::NormalExit && proc.exitCode() == 0;
}

/**
 * Turn unified diff text into the rows the diff view draws.
 *
 * Everything before the first hunk is git's preamble — `diff --git`, `index`,
 * the ---/+++ names, and for a commit also `new file mode`, `similarity index`,
 * `rename from` — and none of it is content. Only the first four were skipped,
 * so the rest was drawn as context lines numbered 1, 2, 3 of the file. The one
 * preamble line that is worth showing is git's note that a file is binary,
 * since there are no hunks to show instead.
 */
QVariantList parseDiff(const QString& out) {
    QVariantList rows;
    static const QRegularExpression hunkRe("@@ -([0-9]+).*\\+([0-9]+)");
    int oldL = 1;
    int newL = 1;
    bool inHunk = false;

    for (const auto& l : out.split("\n")) {
        QVariantMap row;
        if (l.startsWith("diff --git")) {
            inHunk = false;
            continue;
        }
        if (l.startsWith("@@")) {
            inHunk = true;
            row["type"] = "header";
            row["text"] = l;
            row["oldLine"] = "";
            row["newLine"] = "";
            auto match = hunkRe.match(l);
            if (match.hasMatch()) {
                oldL = match.captured(1).toInt();
                newL = match.captured(2).toInt();
            }
        } else if (!inHunk) {
            if (!l.startsWith("Binary files")) continue;
            row["type"] = "header";
            row["text"] = l;
            row["oldLine"] = "";
            row["newLine"] = "";
        } else if (l.startsWith("+")) {
            row["type"] = "add";
            row["text"] = l;
            row["oldLine"] = "";
            row["newLine"] = newL++;
        } else if (l.startsWith("-")) {
            row["type"] = "del";
            row["text"] = l;
            row["oldLine"] = oldL++;
            row["newLine"] = "";
        } else {
            row["type"] = "ctx";
            row["text"] = l;
            row["oldLine"] = oldL++;
            row["newLine"] = newL++;
        }
        rows.append(row);
    }
    return rows;
}

// Field and record separators for `git log --pretty`. The history used to be
// split on '|', so a subject containing one — "fix(a|b)" — was cut off there.
const QString kFieldSep = QStringLiteral("\x1f");
const QString kRecordSep = QStringLiteral("\x1e");

/**
 * "Name <email>" trailer values, separated by \x1d, as names. A trailer with
 * no name — an email alone — keeps the email, and the author's own name
 * repeated as a co-author is kept as written, since that is what git says.
 */
QStringList coAuthorNames(const QString& field) {
    QStringList names;
    for (const auto& v : field.split(QChar(0x1d), Qt::SkipEmptyParts)) {
        QString n = v.trimmed();
        const int lt = n.indexOf('<');
        if (lt > 0) n = n.left(lt).trimmed();
        if (!n.isEmpty() && !names.contains(n)) names << n;
    }
    return names;
}

/** The emails of the same trailers, by name, for the avatars. */
QVariantMap coAuthorEmails(const QString& field) {
    QVariantMap emails;
    for (const auto& v : field.split(QChar(0x1d), Qt::SkipEmptyParts)) {
        const QString t = v.trimmed();
        const int lt = t.indexOf('<'), gt = t.indexOf('>', lt);
        if (lt < 0 || gt < 0) continue;
        const QString name = lt > 0 ? t.left(lt).trimmed() : t.mid(lt + 1, gt - lt - 1);
        emails.insert(name, t.mid(lt + 1, gt - lt - 1).trimmed());
    }
    return emails;
}

// Commits read per page. One page is well under 50ms even on a large
// repository, and more than a window's worth of rows.
constexpr int kHistoryPage = 300;

} // namespace

// ── HistoryModel ─────────────────────────────────────────────────────────────

int HistoryModel::rowCount(const QModelIndex& parent) const {
    return parent.isValid() ? 0 : m_rows.size();
}

QVariant HistoryModel::data(const QModelIndex& index, int role) const {
    if (!index.isValid() || index.row() >= m_rows.size()) return {};
    const Commit& c = m_rows.at(index.row());
    switch (role) {
    case FullHashRole: return c.fullHash;
    case HashRole: return c.hash;
    case AuthorRole: return c.author;
    case TimeRole: return c.time;
    case MessageRole: return c.message;
    case CoAuthorsRole: return c.coAuthors;
    case EmailRole: return c.email;
    case SyncRole: return !m_hasRemote ? QString()
                        : m_unpushed.contains(c.fullHash) ? QStringLiteral("local")
                                                          : QStringLiteral("pushed");
    }
    return {};
}

QHash<int, QByteArray> HistoryModel::roleNames() const {
    return {{FullHashRole, "fullHash"}, {HashRole, "hash"}, {AuthorRole, "author"},
            {TimeRole, "time"}, {MessageRole, "message"}, {SyncRole, "sync"},
            {CoAuthorsRole, "coAuthors"}, {EmailRole, "email"}};
}

bool HistoryModel::canFetchMore(const QModelIndex& parent) const {
    return !parent.isValid() && !m_atEnd;
}

void HistoryModel::fetchMore(const QModelIndex& parent) {
    if (!canFetchMore(parent)) return;
    const QList<Commit> page = readPage(m_rows.size());
    m_atEnd = page.size() < kHistoryPage;
    if (!page.isEmpty()) {
        beginInsertRows(QModelIndex(), m_rows.size(), m_rows.size() + page.size() - 1);
        m_rows.append(page);
        endInsertRows();
        emit countChanged();
    }
}

QString HistoryModel::hashAt(int row) const {
    return row >= 0 && row < m_rows.size() ? m_rows.at(row).fullHash : QString();
}

void HistoryModel::reload(const QString& repoPath) {
    beginResetModel();
    m_repoPath = repoPath;
    m_rows.clear();
    m_atEnd = repoPath.isEmpty();
    if (!m_atEnd) {
        m_rows = readPage(0);
        m_atEnd = m_rows.size() < kHistoryPage;
    }
    endResetModel();
    emit countChanged();
}

QList<HistoryModel::Commit> HistoryModel::readPage(int skip) const {
    QList<Commit> page;
    QString out;
    // Silently: a repository with no commits yet has no HEAD, and git log
    // failing there is the answer "nothing", not an error to show.
    if (!gitOk(m_repoPath, QStringList() << "log" << "--skip=" + QString::number(skip)
                                         << "-n" << QString::number(kHistoryPage)
                                         << "--pretty=format:%H%x1f%h%x1f%an%x1f%ct%x1f%s%x1f"
                                            "%(trailers:key=Co-authored-by,valueonly,separator=%x1d)%x1f%ae%x1e",
               nullptr, &out))
        return page;

    for (const auto& rec : out.split(kRecordSep, Qt::SkipEmptyParts)) {
        const QStringList parts = rec.trimmed().split(kFieldSep);
        if (parts.size() < 5) continue;
        page.append({parts[0], parts[1], parts[2], parts[3].toLongLong(), parts[4],
                     parts.size() > 5 ? coAuthorNames(parts[5]) : QStringList(),
                     parts.size() > 6 ? parts[6] : QString()});
    }
    return page;
}

void HistoryModel::setUnpushed(const QSet<QString>& hashes, bool hasRemote) {
    if (hashes == m_unpushed && hasRemote == m_hasRemote) return;
    m_unpushed = hashes;
    m_hasRemote = hasRemote;
    if (!m_rows.isEmpty())
        emit dataChanged(index(0), index(m_rows.size() - 1), {SyncRole});
}

QString HistoryModel::syncStateOf(const QString& fullHash) const {
    if (!m_hasRemote || fullHash.isEmpty()) return QString();
    return m_unpushed.contains(fullHash) ? QStringLiteral("local") : QStringLiteral("pushed");
}

QString GitBackend::startupRepo() const {
    // The directory this was started in, if it is a repository; otherwise the
    // last one that was open. It used to fall back to ~/DotsFiles — one
    // hardcoded path, which is nothing on most machines.
    //
    // It also used to fall back to the *first* known repository, which is the
    // one added longest ago, not the last one used — and main() then threw the
    // answer away by opening the working directory regardless. Started from
    // the launcher that is $HOME, so the app always came up with nothing open.
    const QString cwd = QDir::currentPath();
    if (isRepoDir(cwd)) return cwd;
    if (isRepoDir(m_lastRepo)) return m_lastRepo;
    return m_repos.isEmpty() ? QDir::homePath()
                             : m_repos.first().toMap().value("path").toString();
}

void GitBackend::loadRepos() {
    QFile f(reposPath());
    m_repos.clear();
    if (f.open(QIODevice::ReadOnly)) {
        const QJsonObject o = QJsonDocument::fromJson(f.readAll()).object();
        m_lastRepo = o.value("last").toString();
        for (const auto& v : o.value("known").toArray()) {
            const QString path = v.toObject().value("path").toString();
            // A repository that has been moved or deleted since is dropped
            // rather than listed as an entry that cannot be opened.
            if (!isRepoDir(path)) continue;
            QVariantMap item;
            item["path"] = path;
            item["name"] = QFileInfo(path).fileName();
            m_repos.append(item);
        }
    }
    emit reposChanged();
}

void GitBackend::saveRepos() const {
    QJsonArray known;
    for (const auto& r : m_repos) {
        QJsonObject o;
        o["path"] = r.toMap().value("path").toString();
        known.append(o);
    }
    QJsonObject root;
    root["known"] = known;
    if (!m_lastRepo.isEmpty()) root["last"] = m_lastRepo;

    QSaveFile f(reposPath());
    if (!f.open(QIODevice::WriteOnly)) return;
    f.write(QJsonDocument(root).toJson(QJsonDocument::Indented));
    f.commit();
}

void GitBackend::rememberRepo(const QString& path) {
    if (!isRepoDir(path)) return;
    for (const auto& r : m_repos)
        if (r.toMap().value("path").toString() == path) return;
    QVariantMap item;
    item["path"] = path;
    item["name"] = QFileInfo(path).fileName();
    m_repos.prepend(item);
    saveRepos();
    emit reposChanged();
}

bool GitBackend::addRepo(const QString& path) {
    QDir dir(path);
    while (!dir.isRoot() && !dir.exists(".git")) {
        if (!dir.cdUp()) break;
    }
    if (!dir.exists(".git")) {
        emit commandFailed(QStringLiteral("Not a git repository: ") + path);
        return false;
    }
    rememberRepo(dir.absolutePath());
    openRepo(dir.absolutePath());
    return true;
}

void GitBackend::forgetRepo(const QString& path) {
    for (int i = 0; i < m_repos.size(); ++i) {
        if (m_repos.at(i).toMap().value("path").toString() == path) {
            m_repos.removeAt(i);
            break;
        }
    }
    saveRepos();
    emit reposChanged();
}

void GitBackend::pickRepoFolder() {
    // A temporary file the chooser writes the chosen path into. A pipe would
    // be neater, but the file manager is a full application with its own
    // stdout — a file says exactly one thing and says it only on success.
    const QString out = QDir::tempPath() + QStringLiteral("/b1air-git-pick-%1")
                            .arg(QCoreApplication::applicationPid());
    QFile::remove(out);

    auto* proc = new QProcess(this);
    connect(proc, &QProcess::finished, this, [this, proc, out](int, QProcess::ExitStatus) {
        QFile f(out);
        if (f.open(QIODevice::ReadOnly)) {
            const QString path = QString::fromUtf8(f.readAll()).trimmed();
            f.close();
            if (!path.isEmpty()) addRepo(path);
        }
        QFile::remove(out);
        proc->deleteLater();
    });
    connect(proc, &QProcess::errorOccurred, this, [this, proc](QProcess::ProcessError) {
        emit commandFailed(QStringLiteral("Could not start the file manager"));
        proc->deleteLater();
    });
    proc->start("b1air-files", QStringList() << "--pick-folder" << out
                                             << (m_isRepo ? m_repoPath : QDir::homePath()));
}

bool GitBackend::trashRepo(const QString& path) {
    QFileInfo fi(path);
    if (!fi.isDir()) {
        emit commandFailed(QStringLiteral("No such directory: ") + path);
        return false;
    }
    // The same two commands, in the same order, as the file manager's own
    // delete: gio ships with glib, trash-put often is not installed, and
    // neither of them is `rm`.
    for (const QStringList& cmd : {QStringList{"gio", "trash", path},
                                   QStringList{"trash-put", path}}) {
        if (QProcess::execute(cmd.first(), cmd.mid(1)) == 0) {
            forgetRepo(path);
            if (m_repoPath == path) {
                // The open repository just went to the trash; land somewhere
                // that exists rather than showing a tree that is gone.
                openRepo(m_repos.isEmpty() ? QDir::homePath()
                                           : m_repos.first().toMap().value("path").toString());
            }
            return true;
        }
    }
    emit commandFailed(QStringLiteral("Could not move ") + fi.fileName() + QStringLiteral(" to the trash"));
    return false;
}

bool GitBackend::createBranch(const QString& name) {
    const QString n = name.trimmed();
    if (n.isEmpty() || !m_isRepo) return false;
    // git's own rules are stricter than this, and it reports them itself; what
    // is checked here is only what would make the command ambiguous.
    if (n.contains(' ') || n.startsWith('-')) {
        emit commandFailed(QStringLiteral("A branch name cannot contain spaces or start with '-'"));
        return false;
    }
    QString err;
    if (!gitOk(m_repoPath, QStringList() << "checkout" << "-b" << n, &err)) {
        emit commandFailed(err.isEmpty() ? QStringLiteral("Could not create ") + n : err);
        return false;
    }
    refresh();
    return true;
}

bool GitBackend::deleteBranch(const QString& name, bool force) {
    const QString n = name.trimmed();
    if (n.isEmpty() || !m_isRepo) return false;
    if (n == m_branchName) {
        emit commandFailed(QStringLiteral("Cannot delete the branch you are on — switch first"));
        return false;
    }
    QString err;
    if (!gitOk(m_repoPath, QStringList() << "branch" << (force ? "-D" : "-d") << n, &err)) {
        // Deliberately not reported as a failure when it is the "not fully
        // merged" refusal: the window turns that into an explicit second
        // question rather than a message the user can do nothing with.
        if (!force && err.contains("not fully merged")) return false;
        emit commandFailed(err.isEmpty() ? QStringLiteral("Could not delete ") + n : err);
        return false;
    }
    refresh();
    return true;
}

QString GitBackend::runGit(const QStringList& args, bool trim) {
    if (m_repoPath.isEmpty()) return "";
    QProcess proc;
    proc.setWorkingDirectory(m_repoPath);
    proc.start("git", args);
    // push/pull over the network routinely take longer than 5s.
    proc.waitForFinished(30000);

    QString out = QString::fromUtf8(proc.readAllStandardOutput());
    out = trim ? out.trimmed() : QString(out).remove(QRegularExpression("\\s+$"));
    if (proc.exitStatus() != QProcess::NormalExit || proc.exitCode() != 0) {
        QString err = QString::fromUtf8(proc.readAllStandardError()).trimmed();
        if (err.isEmpty()) err = out;
        if (err.isEmpty()) err = "git " + args.join(' ') + " failed";
        emit commandFailed(err);
    }
    return out;
}

void GitBackend::openRepo(const QString& path) {
    QDir dir(path);
    while (!dir.isRoot() && !dir.exists(".git")) {
        if (!dir.cdUp()) break;
    }

    if (dir.exists(".git")) {
        m_repoPath = dir.absolutePath();
        m_isRepo = true;
    } else {
        m_repoPath = path;
        m_isRepo = false;
    }

    if (m_isRepo) {
        rememberRepo(m_repoPath);
        if (m_lastRepo != m_repoPath) {
            m_lastRepo = m_repoPath;
            saveRepos();
        }
    }

    resolveGitPaths();

    // A commit belongs to the repository it was picked in.
    clearCommit();
    emit repoChanged();
    refresh();

    // Opening a repository is when its remote state is most likely stale.
    if (m_isRepo && QDateTime::currentSecsSinceEpoch() - m_lastFetch > 60)
        QTimer::singleShot(0, this, &GitBackend::startBackgroundFetch);
}

void GitBackend::refresh() {
    updateBranch();
    // Before updateStatus: the change stamp taken there watches the upstream's
    // ref, and the upstream is what this reads.
    updateSync();
    updateStatus();
    updateHistory();
    updateDiff();
}

QString GitBackend::repoName() const {
    // The folder name is not a repository name. Reporting it regardless meant
    // the header read "Current Repository: DotsFiles" for a directory with no
    // .git in it, contradicting the pane beside it.
    if (!m_isRepo || m_repoPath.isEmpty()) return "No Repository";
    return QFileInfo(m_repoPath).fileName();
}

void GitBackend::updateBranch() {
    // Outside a repository `git branch --show-current` is empty for the same
    // reason a detached HEAD is, so the empty case only means "detached" when
    // there is a repository to be detached in.
    if (!m_isRepo) {
        m_branchName = QStringLiteral("—");
        emit branchChanged();
        return;
    }
    QString out = runGit(QStringList() << "branch" << "--show-current");
    m_branchName = out.isEmpty() ? "detached" : out;

    // for-each-ref rather than `git branch`: one call gives each branch's
    // upstream and how it stands against it, "[gone]" included.
    const QString refs = runGit(QStringList() << "for-each-ref" << "refs/heads"
                                              << "--format=%(refname:short)%1f%(upstream:short)%1f%(upstream:track)%1f%(worktreepath)");
    m_branches.clear();
    m_branchInfo.clear();
    static const QRegularExpression aheadRe("ahead (\\d+)"), behindRe("behind (\\d+)");
    for (const auto& line : refs.split('\n', Qt::SkipEmptyParts)) {
        const QStringList f = line.split(QChar(0x1f));
        const QString name = f.value(0).trimmed();
        if (name.isEmpty() || m_branches.contains(name)) continue;
        const QString track = f.value(2);
        QVariantMap info;
        info["upstream"] = f.value(1);
        info["gone"] = track.contains("gone");
        info["ahead"] = aheadRe.match(track).captured(1).toInt();
        info["behind"] = behindRe.match(track).captured(1).toInt();
        // Checked out in another worktree: git will not check it out here.
        const QString wt = f.value(3).trimmed();
        info["worktree"] = (!wt.isEmpty() && QDir::cleanPath(wt) != QDir::cleanPath(m_repoPath)) ? wt : QString();
        m_branches.append(name);
        m_branchInfo[name] = info;
    }

    m_worktrees.clear();
    const QString wtOut = runGit(QStringList() << "worktree" << "list" << "--porcelain");
    for (const auto& block : wtOut.split("\n\n", Qt::SkipEmptyParts)) {
        QVariantMap wt;
        for (const auto& line : block.split('\n', Qt::SkipEmptyParts)) {
            if (line.startsWith("worktree ")) wt["path"] = line.mid(9);
            else if (line.startsWith("branch refs/heads/")) wt["branch"] = line.mid(18);
            else if (line == QLatin1String("detached")) wt["branch"] = QStringLiteral("detached");
        }
        if (wt.value("path").toString().isEmpty()) continue;
        wt["main"] = m_worktrees.isEmpty();
        wt["current"] = QDir::cleanPath(wt["path"].toString()) == QDir::cleanPath(m_repoPath);
        m_worktrees.append(wt);
    }

    // A stash this app made when leaving the branch now checked out.
    m_branchStash.clear();
    const QString stashes = runGit(QStringList() << "stash" << "list" << "--format=%gd%x1f%s");
    const QString marker = QStringLiteral("b1air-git:") + m_branchName;
    for (const auto& line : stashes.split('\n', Qt::SkipEmptyParts)) {
        const QStringList f = line.split(QChar(0x1f));
        if (f.size() < 2 || !f[1].endsWith(marker)) continue;
        QString files;
        gitOk(m_repoPath, QStringList() << "stash" << "show" << "--include-untracked"
                                        << "--name-only" << f[0], nullptr, &files);
        m_branchStash["ref"] = f[0];
        m_branchStash["files"] = files.split('\n', Qt::SkipEmptyParts).size();
        break;
    }

    emit branchChanged();
}

void GitBackend::updateStatus() {
    m_changedFiles.clear();

    // A folder that is not a repository produces no porcelain output, which is
    // indistinguishable from a repository with nothing to commit — so the
    // header reported "Working tree clean" for any directory at all, next to a
    // pane correctly saying "Open a repository".
    if (!m_isRepo) {
        m_statusSummary = QStringLiteral("No repository");
        m_selectedFile.clear();
        emit statusChanged();
        emit selectedFileChanged();
        return;
    }

    // -uall lists each untracked file. By default git folds a new directory
    // into one "dir/" row, and selecting that row tried to read the directory
    // as a file and showed nothing.
    QString out = runGit(QStringList() << "status" << "--porcelain=v1" << "-uall", false);

    QStringList lines = out.split("\n", Qt::SkipEmptyParts);
    for (const auto& l : lines) {
        if (l.size() < 3) continue;
        QString xy = l.left(2);
        QString filePath = l.mid(2).trimmed();
        // A staged rename reads "old -> new". Taken whole, that was the path
        // handed to git diff, which matched no file and showed nothing.
        const int arrow = filePath.indexOf(" -> ");
        QString oldPath;
        if (arrow >= 0) {
            oldPath = filePath.left(arrow);
            filePath = filePath.mid(arrow + 4);
        }

        QVariantMap item;
        item["path"] = filePath;
        item["oldPath"] = oldPath;
        item["name"] = QFileInfo(filePath).fileName();

        char x = xy[0].toLatin1();
        char y = xy[1].toLatin1();

        const bool conflicted = x == 'U' || y == 'U' || (x == 'A' && y == 'A') || (x == 'D' && y == 'D');
        // A conflicted file is not staged until it is marked resolved.
        item["isStaged"] = !conflicted && x != ' ' && x != '?';

        QString status = "modified";
        if (conflicted) status = "conflicted";
        else if (x == 'A' || y == 'A' || x == '?' || y == '?') status = "added";
        else if (x == 'D' || y == 'D') status = "deleted";
        else if (x == 'R' || y == 'R') status = "renamed";
        
        item["status"] = status;
        item["code"] = xy.trimmed();

        m_changedFiles.append(item);
    }

    int conflicts = 0;
    for (const auto& v : m_changedFiles)
        if (v.toMap().value("status") == QLatin1String("conflicted")) ++conflicts;
    m_mergeState.clear();
    if (QFileInfo::exists(gitPath("MERGE_HEAD"))) {
        QFile msg(gitPath("MERGE_MSG"));
        QString first;
        if (msg.open(QIODevice::ReadOnly)) first = QString::fromUtf8(msg.readLine()).trimmed();
        static const QRegularExpression nameRe("'([^']+)'");
        m_mergeState["active"] = true;
        m_mergeState["branch"] = nameRe.match(first).captured(1);
        m_mergeState["conflicts"] = conflicts;
    }

    if (m_changedFiles.isEmpty()) {
        m_statusSummary = "Working tree clean";
        m_selectedFile = "";
    } else {
        m_statusSummary = QString::number(m_changedFiles.size()) + " files changed";
        if (m_selectedFile.isEmpty() || !out.contains(m_selectedFile)) {
            m_selectedFile = m_changedFiles[0].toMap()["path"].toString();
        }
    }

    // What the poll compares against: the state this refresh just drew. Set
    // here, from the same output, so a refresh caused by a button is not
    // followed two seconds later by a second one for the same change.
    m_pollStamp = stamp(out);

    emit statusChanged();
    emit selectedFileChanged();
}

// ── Noticing outside changes ────────────────────────────────────────────────

QString GitBackend::stamp(const QString& statusOut) const {
    // git status alone misses two things. A file already listed as modified
    // stays one identical line however often it is edited again, so the diff
    // on screen went stale; the size and mtime of every listed file catch
    // that. And a commit, reset or checkout with a clean tree before and after
    // changes nothing status prints — but every one of them appends to HEAD's
    // reflog, and branch creation touches refs/heads or packed-refs.
    QCryptographicHash h(QCryptographicHash::Sha1);
    h.addData(statusOut.toUtf8());

    auto addFile = [&h](const QString& path) {
        const QFileInfo fi(path);
        if (!fi.exists()) return;
        h.addData(QByteArray::number(fi.size()));
        h.addData(QByteArray::number(fi.lastModified().toMSecsSinceEpoch()));
    };
    addFile(gitPath("logs/HEAD"));
    addFile(gitPath("HEAD"));
    addFile(gitPath("packed-refs"));
    addFile(gitPath("FETCH_HEAD"));
    addFile(gitPath("MERGE_HEAD"));
    addFile(gitPath("worktrees"));
    const QString refs = gitPath("refs");
    QDirIterator refsIt(refs, QDir::Dirs | QDir::NoDotAndDotDot, QDirIterator::Subdirectories);
    while (refsIt.hasNext()) addFile(refsIt.next());
    addFile(refs + "/heads");
    addFile(refs + "/stash");
    if (!m_upstream.isEmpty()) {
        addFile(refs + "/remotes/" + m_upstream);
        addFile(gitPath("logs") + "/refs/remotes/" + m_upstream);
    }
    for (const auto& line : statusOut.split('\n', Qt::SkipEmptyParts)) {
        if (line.size() < 4) continue;
        // For a rename porcelain prints "old -> new"; the new one is on disk.
        QString path = line.mid(3);
        const int arrow = path.indexOf(" -> ");
        if (arrow >= 0) path = path.mid(arrow + 4);
        addFile(m_repoPath + '/' + path);
    }
    return QString::fromLatin1(h.result().toHex());
}

void GitBackend::startPoll() {
    if (!m_isRepo || m_pollProc || !m_busy.isEmpty()) return;

    m_pollProc = new QProcess(this);
    m_pollProc->setWorkingDirectory(m_repoPath);
    const QString polledRepo = m_repoPath;
    connect(m_pollProc, &QProcess::finished, this, [this, polledRepo](int code, QProcess::ExitStatus st) {
        const QString out = QString::fromUtf8(m_pollProc->readAllStandardOutput())
                                .remove(QRegularExpression("\\s+$"));
        m_pollProc->deleteLater();
        m_pollProc = nullptr;
        // A repository switched while this ran: its answer is about the old one.
        if (polledRepo != m_repoPath || st != QProcess::NormalExit || code != 0) return;
        if (stamp(out) != m_pollStamp) refresh();
    });
    // --no-optional-locks: status otherwise takes index.lock to refresh the
    // index, and a poll holding it at the wrong moment makes a `git commit`
    // typed in a terminal fail with "Unable to create index.lock".
    m_pollProc->start("git", QStringList() << "--no-optional-locks" << "status"
                                           << "--porcelain=v1" << "-uall");
}

void GitBackend::updateHistory() {
    // Outside a repository there is nothing to list; an unborn HEAD (no
    // commits yet) reads as an empty head and an empty list.
    QString head;
    if (m_isRepo) {
        gitOk(m_repoPath, QStringList() << "rev-parse" << "--verify" << "-q" << "HEAD", nullptr, &head);
        head = head.trimmed();
    }
    const QString key = m_isRepo ? m_repoPath + '\n' + head : QString();
    if (key == m_historyHead && m_history->count() > 0) return;
    m_historyHead = key;
    m_history->reload(m_isRepo ? m_repoPath : QString());
}

// ── Against the remote ──────────────────────────────────────────────────────

void GitBackend::updateSync() {
    bool hasRemote = false;
    QString upstream;
    int ahead = 0;
    int behind = 0;
    QSet<QString> unpushed;

    if (m_isRepo) {
        QString out;
        gitOk(m_repoPath, QStringList() << "remote", nullptr, &out);
        hasRemote = !out.trimmed().isEmpty();
    }
    if (hasRemote) {
        QString out;
        if (gitOk(m_repoPath, QStringList() << "rev-parse" << "--abbrev-ref"
                                            << "--symbolic-full-name" << "@{upstream}", nullptr, &out))
            upstream = out.trimmed();

        // "Not pushed" means on no remote-tracking branch at all, not merely
        // missing from this branch's upstream: a branch cut from main and never
        // published would otherwise mark every commit back to the first one.
        // Silently — in a repository with no commits HEAD does not resolve.
        gitOk(m_repoPath, QStringList() << "rev-list" << "HEAD" << "--not" << "--remotes", nullptr, &out);
        for (const auto& h : out.split('\n', Qt::SkipEmptyParts)) unpushed.insert(h.trimmed());

        if (!upstream.isEmpty()
            && gitOk(m_repoPath, QStringList() << "rev-list" << "--left-right" << "--count"
                                               << "@{upstream}...HEAD", nullptr, &out)) {
            const QStringList n = out.trimmed().split('\t');
            if (n.size() == 2) {
                behind = n[0].toInt();
                ahead = n[1].toInt();
            }
        } else {
            // No upstream: nothing to pull from, and pushing publishes the
            // branch, which sends exactly the commits no remote has.
            ahead = unpushed.size();
        }
    }

    QString remoteName;
    if (hasRemote) {
        QString out;
        gitOk(m_repoPath, QStringList() << "remote", nullptr, &out);
        const QStringList remotes = out.split('\n', Qt::SkipEmptyParts);
        if (!upstream.isEmpty() && upstream.contains('/')) remoteName = upstream.section('/', 0, 0);
        else if (remotes.contains("origin")) remoteName = "origin";
        else if (!remotes.isEmpty()) remoteName = remotes.first().trimmed();
    }
    const QFileInfo fetchHead(gitPath("FETCH_HEAD"));
    m_lastFetch = m_isRepo && fetchHead.exists() ? fetchHead.lastModified().toSecsSinceEpoch() : 0;
    m_remoteName = remoteName;
    // Configured to track a branch the remote no longer has.
    m_upstreamGone = hasRemote && upstream.isEmpty()
                     && m_branchInfo.value(m_branchName).toMap().value("gone").toBool();

    // HEAD, the web address, the default branch and who commits.
    {
        QString out;
        QVariantMap lc;
        if (m_isRepo && gitOk(m_repoPath, {"log", "-1", "--format=%H%x1f%s%x1f%b%x1f%ct%x1f%P"}, nullptr, &out)) {
            const QStringList f = out.split(QChar(0x1f));
            if (f.size() >= 5) {
                const QStringList parents = f[4].split(' ', Qt::SkipEmptyParts);
                lc["hash"] = f[0];
                lc["subject"] = f[1];
                lc["body"] = f[2].trimmed();
                lc["time"] = f[3].toLongLong();
                // A merge or the first commit can't be undone softly; a pushed one shouldn't be.
                lc["canUndo"] = parents.size() == 1 && (!hasRemote || unpushed.contains(f[0]));
            }
        }
        m_lastCommit = lc;

        QString url;
        if (!remoteName.isEmpty() && gitOk(m_repoPath, {"remote", "get-url", remoteName}, nullptr, &out)) {
            url = out.trimmed();
            static const QRegularExpression scp("^[^@/]+@([^:]+):(.+)$");
            const auto m = scp.match(url);
            if (m.hasMatch()) url = "https://" + m.captured(1) + "/" + m.captured(2);
            url.replace(QRegularExpression("^ssh://[^@]+@"), "https://");
            url.replace(QRegularExpression("^git://"), "https://");
            if (url.endsWith(".git")) url.chop(4);
            if (!url.startsWith("http")) url.clear();
        }
        m_webUrl = url;

        m_defaultBranch.clear();
        if (!remoteName.isEmpty()
            && gitOk(m_repoPath, {"symbolic-ref", "--short", "refs/remotes/" + remoteName + "/HEAD"}, nullptr, &out))
            m_defaultBranch = out.trimmed().section('/', 1);
        if (m_defaultBranch.isEmpty())
            m_defaultBranch = m_branchInfo.contains("main") ? "main" : (m_branchInfo.contains("master") ? "master" : "");

        QVariantMap id;
        if (m_isRepo) {
            gitOk(m_repoPath, {"config", "user.name"}, nullptr, &out);
            id["name"] = out.trimmed();
            gitOk(m_repoPath, {"config", "user.email"}, nullptr, &out);
            id["email"] = out.trimmed();
        }
        m_identity = id;
    }

    m_history->setUnpushed(unpushed, hasRemote);
    m_hasRemote = hasRemote;
    m_upstream = upstream;
    m_ahead = ahead;
    m_behind = behind;
    emit syncChanged();
}

// ── Hosting accounts ────────────────────────────────────────────────────────

namespace {

struct Provider {
    const char* id;
    const char* name;
    const char* cli;
    const char* host;
};

const Provider kProviders[] = {
    {"github", "GitHub", "gh", "github.com"},
    {"gitlab", "GitLab", "glab", "gitlab.com"},
};

const Provider* findProvider(const QString& id) {
    for (const auto& p : kProviders)
        if (id == QLatin1String(p.id)) return &p;
    return nullptr;
}

/** The login a CLI reports as signed in, or empty. */
QString parseLogin(const Provider& p, const QString& out) {
    if (QLatin1String(p.id) == QLatin1String("github")) {
        // gh has a JSON form; its text form has been reworded between
        // releases ("as X", then "account X").
        const QJsonArray entries = QJsonDocument::fromJson(out.toUtf8())
                                       .object().value("hosts").toObject()
                                       .value(p.host).toArray();
        for (const auto& v : entries) {
            const QJsonObject e = v.toObject();
            if (e.value("active").toBool() && e.value("state").toString() == "success")
                return e.value("login").toString();
        }
        return QString();
    }
    // glab has no JSON form for this; "Logged in to gitlab.com as NAME".
    static const QRegularExpression re("Logged in to (\\S+) as (\\S+)");
    auto it = re.globalMatch(out);
    while (it.hasNext()) {
        const auto m = it.next();
        if (m.captured(1) == QLatin1String(p.host)) return m.captured(2);
    }
    return QString();
}

} // namespace

void GitBackend::refreshAccounts() {
    if (m_accountProbes > 0) return;

    QVariantList list;
    for (const auto& p : kProviders) {
        QVariantMap a;
        a["provider"] = QString::fromLatin1(p.id);
        a["name"] = QString::fromLatin1(p.name);
        a["cli"] = QString::fromLatin1(p.cli);
        a["installed"] = !QStandardPaths::findExecutable(p.cli).isEmpty();
        // Keep the last answer while the new one is read, so the button does
        // not flash "Sign in" on every focus.
        for (const auto& old : m_accounts)
            if (old.toMap().value("provider") == a["provider"])
                a["login"] = old.toMap().value("login");
        list.append(a);
    }
    m_accounts = list;
    emit accountsChanged();

    for (int i = 0; i < int(std::size(kProviders)); ++i) {
        const Provider& p = kProviders[i];
        if (!m_accounts.at(i).toMap().value("installed").toBool()) continue;

        auto* proc = new QProcess(this);
        ++m_accountProbes;
        connect(proc, &QProcess::finished, this, [this, proc, i](int, QProcess::ExitStatus) {
            // Both streams: gh writes to stdout with --json, glab writes its
            // status to stderr. Exit codes are no help — both exit 1 when
            // signed out, and gh does for an expired token on another host.
            const QString out = QString::fromUtf8(proc->readAllStandardOutput())
                                + QString::fromUtf8(proc->readAllStandardError());
            QVariantMap a = m_accounts.at(i).toMap();
            a["login"] = parseLogin(kProviders[i], out);
            m_accounts[i] = a;
            proc->deleteLater();
            --m_accountProbes;
            emit accountsChanged();
        });
        connect(proc, &QProcess::errorOccurred, this, [this, proc](QProcess::ProcessError e) {
            if (e != QProcess::FailedToStart) return;
            proc->deleteLater();
            --m_accountProbes;
        });
        QStringList args{"auth", "status", "--hostname", QString::fromLatin1(p.host)};
        if (QLatin1String(p.id) == QLatin1String("github")) args << "--json" << "hosts";
        proc->start(p.cli, args);
    }
}

void GitBackend::signIn(const QString& provider) {
    const Provider* p = findProvider(provider);
    if (!p) return;
    const QString login = QLatin1String(p->id) == QLatin1String("github")
        ? QStringLiteral("gh auth login --hostname github.com --git-protocol https --web")
        : QStringLiteral("glab auth login --hostname gitlab.com");
    // b1air-term closes the tab when the command exits, which would take any
    // error with it; the pause keeps the outcome readable. sh -c because the
    // terminal hands the line to the login shell, which may not be POSIX.
    const QString line = QStringLiteral("sh -c '%1; echo; printf \"Press Enter to close \"; read _'")
                             .arg(login);
    if (!QProcess::startDetached("b1air-term", QStringList() << "-e" << line))
        emit commandFailed(QStringLiteral("Could not start the terminal"));
}

void GitBackend::signOut(const QString& provider) {
    const Provider* p = findProvider(provider);
    if (!p) return;
    QString login;
    for (const auto& v : m_accounts)
        if (v.toMap().value("provider") == provider) login = v.toMap().value("login").toString();

    QStringList args{"auth", "logout", "--hostname", QString::fromLatin1(p->host)};
    // With more than one account on a host gh asks which one — and there is no
    // terminal here to answer. Naming it makes the question unnecessary.
    if (QLatin1String(p->id) == QLatin1String("github") && !login.isEmpty()) args << "--user" << login;

    auto* proc = new QProcess(this);
    connect(proc, &QProcess::finished, this, [this, proc](int code, QProcess::ExitStatus st) {
        if (st != QProcess::NormalExit || code != 0) {
            const QString err = QString::fromUtf8(proc->readAllStandardError()).trimmed();
            emit commandFailed(err.isEmpty() ? QStringLiteral("Sign-out failed") : err);
        }
        proc->deleteLater();
        refreshAccounts();
    });
    proc->start(p->cli, args);
    proc->closeWriteChannel();
}

// ── A commit from History ───────────────────────────────────────────────────

void GitBackend::clearCommit() {
    m_selectedCommit.clear();
    emit syncChanged();
    m_commitInfo.clear();
    m_commitFiles.clear();
    m_commitFile.clear();
    m_commitDiff.clear();
    emit commitChanged();
    emit commitDiffChanged();
}

void GitBackend::selectCommit(const QString& hash) {
    if (!m_isRepo || hash.isEmpty()) return;
    if (hash == m_selectedCommit) return;

    m_selectedCommit = hash;
    emit syncChanged();
    m_commitInfo.clear();
    m_commitFiles.clear();

    const QString info = runGit(QStringList() << "show" << "-s" << "--date=format:%d %b %Y, %H:%M"
                                              << "--format=%h%x1f%an%x1f%ae%x1f%ad%x1f%s%x1f%b%x1f"
                                                 "%(trailers:key=Co-authored-by,valueonly,separator=%x1d)"
                                              << hash);
    const QStringList f = info.split(kFieldSep);
    if (f.size() >= 7) {
        m_commitInfo["hash"] = f[0];
        m_commitInfo["author"] = f[1];
        m_commitInfo["email"] = f[2];
        m_commitInfo["date"] = f[3];
        m_commitInfo["subject"] = f[4];
        // The co-author trailers are shown as people in the header, so they
        // are taken out of the body rather than printed a second time.
        static const QRegularExpression coLine("^co-authored-by:.*$\\n?",
            QRegularExpression::CaseInsensitiveOption | QRegularExpression::MultilineOption);
        m_commitInfo["body"] = QString(f[5]).remove(coLine).trimmed();
        m_commitInfo["coAuthors"] = coAuthorNames(f[6]);
        m_commitInfo["coAuthorEmails"] = coAuthorEmails(f[6]);
    }

    // --diff-merges=first-parent: a merge shows what it brought into the
    // branch. git show's default for a merge is the combined diff, which is
    // empty for any merge without conflicts — the commit would list no files.
    // -M so a rename is one row rather than a deletion and an addition.
    const QString names = runGit(QStringList() << "show" << "--format=" << "--name-status" << "-M"
                                               << "--diff-merges=first-parent" << hash);
    for (const auto& line : names.split("\n", Qt::SkipEmptyParts)) {
        const QStringList cols = line.split("\t");
        if (cols.size() < 2) continue;
        const QChar code = cols[0].isEmpty() ? QChar('M') : cols[0].at(0);
        QVariantMap item;
        // For a rename or copy git prints the old path, then the new one.
        const bool moved = (code == 'R' || code == 'C') && cols.size() >= 3;
        item["path"] = moved ? cols[2] : cols[1];
        item["oldPath"] = moved ? cols[1] : QString();
        item["name"] = QFileInfo(item["path"].toString()).fileName();
        item["status"] = code == 'A' ? "added"
                       : code == 'D' ? "deleted"
                       : moved       ? "renamed"
                                     : "modified";
        m_commitFiles.append(item);
    }
    emit commitChanged();

    selectCommitFile(m_commitFiles.isEmpty() ? QString()
                                             : m_commitFiles.first().toMap().value("path").toString());
}

void GitBackend::selectCommitFile(const QString& filePath) {
    m_commitFile = filePath;
    updateCommitDiff();
}

void GitBackend::updateCommitDiff() {
    m_commitDiff.clear();
    if (m_selectedCommit.isEmpty() || m_commitFile.isEmpty()) {
        emit commitDiffChanged();
        return;
    }

    QStringList args = QStringList() << "show" << "--format=" << "--no-color" << "-M"
                                     << "--diff-merges=first-parent" << m_selectedCommit << "--";
    // A rename is only detected when both of its paths are in the pathspec;
    // with the new one alone git reports the whole file as added.
    for (const auto& v : m_commitFiles) {
        const QVariantMap f = v.toMap();
        if (f.value("path").toString() != m_commitFile) continue;
        if (!f.value("oldPath").toString().isEmpty()) args << f.value("oldPath").toString();
        break;
    }
    args << m_commitFile;

    m_commitDiff = parseDiff(runGit(args, false));
    emit commitDiffChanged();
}

void GitBackend::selectFile(const QString& filePath) {
    m_selectedFile = filePath;
    emit selectedFileChanged();
    updateDiff();
}

void GitBackend::updateDiff() {
    m_currentDiff.clear();
    if (m_selectedFile.isEmpty()) {
        emit diffChanged();
        return;
    }

    QString out = runGit(QStringList() << "diff" << "HEAD" << "--" << m_selectedFile);
    if (out.isEmpty()) {
        out = runGit(QStringList() << "diff" << "--" << m_selectedFile);
    }
    if (out.isEmpty()) {
        // Untracked file: show file content as added lines
        QFile file(m_repoPath + "/" + m_selectedFile);
        if (file.open(QIODevice::ReadOnly | QIODevice::Text)) {
            QString content = QString::fromUtf8(file.readAll());
            QStringList fileLines = content.split("\n");
            for (int i = 0; i < fileLines.size(); ++i) {
                QVariantMap row;
                row["type"] = "add";
                row["newLine"] = i + 1;
                row["oldLine"] = "";
                row["text"] = "+" + fileLines[i];
                m_currentDiff.append(row);
            }
            emit diffChanged();
            return;
        }
    }

    m_currentDiff = parseDiff(out);
    emit diffChanged();
}

void GitBackend::stageFile(const QString& filePath) {
    runGit(QStringList() << "add" << filePath);
    refresh();
}

void GitBackend::unstageFile(const QString& filePath) {
    runGit(QStringList() << "restore" << "--staged" << filePath);
    refresh();
}

void GitBackend::stageAll() {
    runGit(QStringList() << "add" << "-A");
    refresh();
}

void GitBackend::unstageAll() {
    runGit(QStringList() << "restore" << "--staged" << ".");
    refresh();
}

void GitBackend::runTask(const QString& kind, const QString& text, const QStringList& args,
                         std::function<void(bool, const QString&, const QString&)> done) {
    if (!m_isRepo) return;
    if (!m_busy.isEmpty()) {
        emit commandFailed(QStringLiteral("Wait for the current operation to finish"));
        return;
    }
    m_busy = kind;
    m_busyText = text;
    m_busyLabel = text;
    m_progress = -1;
    emit busyChanged();

    auto* proc = new QProcess(this);
    proc->setWorkingDirectory(m_repoPath);
    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    // No terminal to answer a prompt in; fail instead of hanging.
    env.insert("GIT_TERMINAL_PROMPT", "0");
    env.insert("GIT_SSH_COMMAND", "ssh -o BatchMode=yes");
    env.insert("LC_ALL", "C.UTF-8");
    proc->setProcessEnvironment(env);

    auto err = std::make_shared<QString>();
    connect(proc, &QProcess::readyReadStandardError, this, [this, proc, err]() {
        const QString chunk = QString::fromUtf8(proc->readAllStandardError());
        err->append(chunk);
        // git --progress rewrites one line with \r: "Writing objects:  45% (9/20)".
        static const QRegularExpression re("([A-Za-z][A-Za-z ]+):\\s+(\\d+)%");
        auto it = re.globalMatch(chunk);
        QString phase;
        int pct = -1;
        while (it.hasNext()) {
            const auto m = it.next();
            phase = m.captured(1).trimmed();
            pct = m.captured(2).toInt();
        }
        if (pct >= 100) {
            // Transfer done; what's left is waiting on the other side.
            m_progress = -1;
            m_busyText = m_busyLabel;
            emit busyChanged();
        } else if (pct >= 0) {
            m_progress = pct;
            m_busyText = phase + " " + QString::number(pct) + "%";
            emit busyChanged();
        }
    });
    connect(proc, &QProcess::finished, this, [this, proc, err, done](int code, QProcess::ExitStatus st) {
        const QString out = QString::fromUtf8(proc->readAllStandardOutput());
        err->append(QString::fromUtf8(proc->readAllStandardError()));
        proc->deleteLater();
        m_busy.clear();
        m_busyText.clear();
        m_progress = -1;
        emit busyChanged();
        const bool ok = st == QProcess::NormalExit && code == 0;
        if (done) done(ok, out, *err);
        refresh();
    });
    connect(proc, &QProcess::errorOccurred, this, [this, proc](QProcess::ProcessError e) {
        if (e != QProcess::FailedToStart) return;
        proc->deleteLater();
        m_busy.clear();
        emit busyChanged();
        emit commandFailed(QStringLiteral("Could not run git"));
    });
    proc->start("git", args);
}

namespace {
// The useful part of git's stderr: progress lines and hints dropped.
QString gitError(const QString& err, const QString& out, const QString& fallback) {
    QStringList keep;
    for (QString line : QString(err).replace('\r', '\n').split('\n', Qt::SkipEmptyParts)) {
        line = line.trimmed();
        if (line.startsWith("hint:") || line.contains('%') || line.startsWith("remote: Counting")
            || line.startsWith("To ") || line.startsWith("From ")) continue;
        for (const char* prefix : {"fatal: ", "error: "})
            if (line.startsWith(QLatin1String(prefix))) line = line.mid(int(strlen(prefix)));
        if (!line.isEmpty()) line[0] = line[0].toUpper();
        keep << line;
    }
    if (keep.isEmpty() && !out.trimmed().isEmpty()) keep << out.trimmed().split('\n').first();
    return keep.isEmpty() ? fallback : keep.mid(0, 3).join('\n');
}
} // namespace

void GitBackend::commit(const QString& message) {
    if (message.trimmed().isEmpty()) return;
    const QString branch = m_branchName;
    // Nothing ticked means everything, as in GitHub Desktop, whose layout
    // this copies. It used to run a bare `git commit`, which with nothing
    // staged fails with git's "On branch master … nothing added to commit".
    const bool anyStaged = std::any_of(m_changedFiles.cbegin(), m_changedFiles.cend(),
        [](const QVariant& v) { return v.toMap().value("isStaged").toBool(); });
    if (!anyStaged) runGit({"add", "-A"});
    runTask("commit", "Committing…", {"commit", "-m", message},
            [this, branch](bool ok, const QString& out, const QString& err) {
        if (ok) {
            emit committed();
            emit notice("Committed to " + branch);
        } else {
            emit commandFailed(gitError(err, out, "Commit failed"));
        }
    });
}

void GitBackend::push() {
    const QString remote = m_remoteName.isEmpty() ? QStringLiteral("origin") : m_remoteName;
    const bool publish = m_upstream.isEmpty() && !m_remoteName.isEmpty();
    // A new branch has no upstream, and plain `git push` refuses it.
    const QStringList args = publish
        ? QStringList{"push", "--progress", "--set-upstream", m_remoteName, "HEAD"}
        : QStringList{"push", "--progress"};
    const QString branch = m_branchName;
    runTask(publish ? "publish" : "push",
            publish ? "Publishing " + branch + "…" : "Pushing to " + remote + "…", args,
            [this, publish, branch, remote](bool ok, const QString& out, const QString& err) {
        if (ok) emit notice(publish ? "Published " + branch : "Pushed to " + remote);
        else emit commandFailed(gitError(err, out, "Push failed"));
    });
}

void GitBackend::pull() {
    const QString remote = m_remoteName.isEmpty() ? QStringLiteral("origin") : m_remoteName;
    runTask("pull", "Pulling from " + remote + "…", {"pull", "--progress", "--prune"},
            [this, remote](bool ok, const QString& out, const QString& err) {
        if (!ok) emit commandFailed(gitError(err, out, "Pull failed"));
        else emit notice(out.contains("Already up to date") ? "Already up to date" : "Pulled from " + remote);
    });
}

void GitBackend::fetch() {
    const QString remote = m_remoteName.isEmpty() ? QStringLiteral("origin") : m_remoteName;
    runTask("fetch", "Fetching " + remote + "…", {"fetch", "--progress", "--prune"},
            [this, remote](bool ok, const QString& out, const QString& err) {
        if (ok) emit notice("Fetched " + remote);
        else emit commandFailed(gitError(err, out, "Fetch failed"));
    });
}

void GitBackend::switchBranch(const QString& branch, const QString& changes) {
    if (branch.isEmpty() || !m_isRepo) return;

    clearCommit();
    if (changes == QLatin1String("stash")) {
        // Named after the branch being left; that is how it is found again.
        QString err;
        if (!gitOk(m_repoPath, QStringList() << "stash" << "push" << "--include-untracked"
                                             << "-m" << QStringLiteral("b1air-git:") + m_branchName, &err)) {
            emit commandFailed(err.isEmpty() ? QStringLiteral("Could not stash the changes") : err);
            return;
        }
    }
    const bool stashed = changes == QLatin1String("stash");
    runTask("checkout", "Switching to " + branch + "…", {"checkout", "--progress", branch},
            [this, branch, stashed](bool ok, const QString& out, const QString& err) {
        if (ok) {
            emit notice("Switched to " + branch);
            return;
        }
        // Don't leave the work stashed for a switch that didn't happen.
        if (stashed) gitOk(m_repoPath, QStringList() << "stash" << "pop");
        emit commandFailed(gitError(err, out, "Could not switch to " + branch));
    });
}

void GitBackend::undoLastCommit() {
    if (!m_lastCommit.value("canUndo").toBool()) return;
    const QString subject = m_lastCommit.value("subject").toString();
    const QString body = m_lastCommit.value("body").toString();
    runTask("undo", "Undoing commit…", {"reset", "--soft", "HEAD~1"},
            [this, subject, body](bool ok, const QString& out, const QString& err) {
        if (!ok) {
            emit commandFailed(gitError(err, out, "Could not undo the commit"));
            return;
        }
        emit restoreMessage(subject, body);
        emit notice("Commit undone");
    });
}

void GitBackend::discardFiles(const QStringList& paths) {
    if (!m_isRepo || paths.isEmpty() || !m_busy.isEmpty()) return;

    // Everything about to be thrown away is copied out and sent to the trash.
    // Under the home directory: gio refuses to trash anything on /tmp.
    const QString backup = QStandardPaths::writableLocation(QStandardPaths::GenericCacheLocation)
                         + "/b1air-git/discarded-" + QFileInfo(m_repoPath).fileName() + "-"
                         + QDateTime::currentDateTime().toString("yyyyMMdd-hhmmss");
    QStringList restore;
    for (const auto& v : m_changedFiles) {
        const QVariantMap f = v.toMap();
        const QString path = f.value("path").toString();
        if (!paths.contains(path)) continue;
        const QString abs = m_repoPath + "/" + path;
        if (QFileInfo(abs).isFile()) {
            QDir().mkpath(QFileInfo(backup + "/" + path).absolutePath());
            QFile::copy(abs, backup + "/" + path);
        }
        const QString code = f.value("code").toString();
        const QString status = f.value("status").toString();
        if (code == "??") {
            QFile::remove(abs);
        } else if (status == "added") {
            gitOk(m_repoPath, {"rm", "--cached", "-q", "-f", "--", path});
            QFile::remove(abs);
        } else if (status == "renamed") {
            const QString old = f.value("oldPath").toString();
            gitOk(m_repoPath, {"reset", "-q", "--", path, old});
            QFile::remove(abs);
            if (!old.isEmpty()) restore << old;
        } else {
            restore << path;
        }
    }
    if (!restore.isEmpty()) {
        QStringList args{"restore", "--source=HEAD", "--staged", "--worktree", "--"};
        args << restore;
        QString err;
        if (!gitOk(m_repoPath, args, &err)) emit commandFailed(gitError(err, QString(), "Could not discard"));
    }
    if (QFileInfo::exists(backup) && QProcess::execute("gio", {"trash", backup}) != 0)
        QProcess::execute("trash-put", {backup});
    emit notice(paths.size() == 1 ? "Discarded changes to " + QFileInfo(paths.first()).fileName()
                                  : "Discarded " + QString::number(paths.size()) + " files");
    refresh();
}

void GitBackend::discardAll() {
    QStringList paths;
    for (const auto& v : m_changedFiles) paths << v.toMap().value("path").toString();
    discardFiles(paths);
}

void GitBackend::ignorePattern(const QString& pattern) {
    if (!m_isRepo || pattern.trimmed().isEmpty()) return;
    QFile f(m_repoPath + "/.gitignore");
    QString text;
    if (f.open(QIODevice::ReadOnly)) {
        text = QString::fromUtf8(f.readAll());
        f.close();
    }
    if (text.split('\n').contains(pattern.trimmed())) return;
    if (!text.isEmpty() && !text.endsWith('\n')) text += '\n';
    text += pattern.trimmed() + '\n';
    QSaveFile out(m_repoPath + "/.gitignore");
    if (out.open(QIODevice::WriteOnly)) {
        out.write(text.toUtf8());
        out.commit();
    }
    emit notice("Added " + pattern.trimmed() + " to .gitignore");
    refresh();
}

void GitBackend::revertCommit(const QString& hash) {
    runTask("revert", "Reverting…", {"revert", "--no-edit", hash},
            [this](bool ok, const QString& out, const QString& err) {
        if (ok) emit notice("Reverted");
        else emit commandFailed(gitError(err, out, "Could not revert that commit"));
    });
}

void GitBackend::createBranchAt(const QString& name, const QString& hash) {
    const QString n = name.trimmed();
    if (n.isEmpty()) return;
    runTask("checkout", "Creating " + n + "…", {"checkout", "-b", n, hash},
            [this, n](bool ok, const QString& out, const QString& err) {
        if (ok) emit notice("Switched to new branch " + n);
        else emit commandFailed(gitError(err, out, "Could not create " + n));
    });
}

void GitBackend::createTag(const QString& name, const QString& hash) {
    const QString n = name.trimmed();
    if (n.isEmpty() || !m_isRepo) return;
    QString err;
    if (gitOk(m_repoPath, {"tag", n, hash}, &err)) emit notice("Tagged " + n);
    else emit commandFailed(gitError(err, QString(), "Could not create the tag"));
    refresh();
}

bool GitBackend::renameBranch(const QString& from, const QString& to) {
    const QString n = to.trimmed();
    if (n.isEmpty() || from.isEmpty() || n == from) return false;
    QString err;
    if (!gitOk(m_repoPath, {"branch", "-m", from, n}, &err)) {
        emit commandFailed(gitError(err, QString(), "Could not rename the branch"));
        return false;
    }
    emit notice("Renamed " + from + " to " + n);
    refresh();
    return true;
}

void GitBackend::openOnWeb() {
    if (!m_webUrl.isEmpty()) QDesktopServices::openUrl(QUrl(m_webUrl + (m_webUrl.contains("gitlab") ? "/-/tree/" : "/tree/") + m_branchName));
}

void GitBackend::openPullRequest() {
    if (m_webUrl.isEmpty()) return;
    const QString url = m_webUrl.contains("gitlab")
        ? m_webUrl + "/-/merge_requests/new?merge_request%5Bsource_branch%5D=" + m_branchName
        : m_webUrl + "/compare/" + m_branchName + "?expand=1";
    QDesktopServices::openUrl(QUrl(url));
}

void GitBackend::resolveGitPaths() {
    m_gitPaths.clear();
    if (!m_isRepo) return;
    static const QStringList names = {"HEAD", "logs/HEAD", "logs", "FETCH_HEAD", "MERGE_HEAD",
                                      "MERGE_MSG", "packed-refs", "refs", "worktrees"};
    QStringList args{"rev-parse"};
    for (const auto& n : names) args << "--git-path" << n;
    QString out;
    if (!gitOk(m_repoPath, args, nullptr, &out)) return;
    const QStringList lines = out.split('\n', Qt::SkipEmptyParts);
    for (int i = 0; i < names.size() && i < lines.size(); ++i)
        m_gitPaths[names[i]] = QDir(m_repoPath).absoluteFilePath(lines[i].trimmed());
}

void GitBackend::mergeBranch(const QString& branch) {
    if (!m_isRepo || branch.isEmpty() || branch == m_branchName) return;
    clearCommit();
    const QString into = m_branchName;
    runTask("merge", "Merging " + branch + "…", {"merge", "--no-edit", branch},
            [this, branch, into](bool ok, const QString& out, const QString& err) {
        if (ok) emit notice("Merged " + branch + " into " + into);
        // Conflicts leave the merge open; the banner takes it from there.
        else if (QFileInfo::exists(gitPath("MERGE_HEAD"))) emit notice("Merge has conflicts to resolve");
        else emit commandFailed(gitError(err, out, "Merge failed"));
    });
}

void GitBackend::commitMerge() {
    if (m_mergeState.value("conflicts").toInt() > 0) {
        emit commandFailed(QStringLiteral("Resolve the conflicts and stage those files first"));
        return;
    }
    runTask("commit", "Committing merge…", {"commit", "--no-edit"},
            [this](bool ok, const QString& out, const QString& err) {
        if (ok) emit notice("Merge committed");
        else emit commandFailed(gitError(err, out, "Commit failed"));
    });
}

void GitBackend::abortMerge() {
    runGit(QStringList() << "merge" << "--abort");
    refresh();
}

QString GitBackend::createWorktree(const QString& branch) {
    if (!m_isRepo || branch.isEmpty() || m_worktrees.isEmpty()) return QString();
    const QFileInfo mainWt(m_worktrees.first().toMap().value("path").toString());
    QString safe = branch;
    safe.replace('/', '-');
    const QString base = mainWt.absolutePath() + "/" + mainWt.fileName() + "-" + safe;
    QString path = base;
    for (int n = 2; QFileInfo::exists(path); ++n) path = base + "-" + QString::number(n);

    QString err;
    if (!gitOk(m_repoPath, QStringList() << "worktree" << "add" << path << branch, &err)) {
        emit commandFailed(err.isEmpty() ? QStringLiteral("Could not create the worktree") : err);
        return QString();
    }
    refresh();
    return path;
}

void GitBackend::removeWorktree(const QString& path) {
    if (!m_isRepo || path.isEmpty()) return;
    QString err;
    // git refuses a worktree with uncommitted changes, and says so.
    if (!gitOk(m_repoPath, QStringList() << "worktree" << "remove" << path, &err)) {
        emit commandFailed(err.isEmpty() ? QStringLiteral("Could not remove the worktree") : err);
        return;
    }
    forgetRepo(path);
    refresh();
}

void GitBackend::restoreStash() {
    const QString ref = m_branchStash.value("ref").toString();
    if (ref.isEmpty()) return;
    runGit(QStringList() << "stash" << "pop" << ref);
    refresh();
}

void GitBackend::discardStash() {
    const QString ref = m_branchStash.value("ref").toString();
    if (ref.isEmpty()) return;
    runGit(QStringList() << "stash" << "drop" << ref);
    refresh();
}

QString GitBackend::absolutePath(const QString& relPath) const {
    return relPath.isEmpty() ? m_repoPath : QDir(m_repoPath).filePath(relPath);
}

void GitBackend::openTerminal(const QString& relPath) {
    if (m_repoPath.isEmpty()) return;
    QFileInfo fi(absolutePath(relPath));
    const QString dir = fi.isDir() ? fi.absoluteFilePath() : fi.absolutePath();
    QProcess::startDetached("b1air-term", QStringList() << dir, dir);
}

void GitBackend::openFileManager(const QString& relPath) {
    if (m_repoPath.isEmpty()) return;
    QFileInfo fi(absolutePath(relPath));
    QProcess::startDetached("b1air-files", QStringList() << (fi.isDir() ? fi.absoluteFilePath() : fi.absolutePath()));
}

void GitBackend::openFile(const QString& relPath) {
    const QString path = absolutePath(relPath);
    if (!QFileInfo::exists(path)) {
        emit commandFailed(QStringLiteral("Not on disk: ") + relPath);
        return;
    }
    QDesktopServices::openUrl(QUrl::fromLocalFile(path));
}

void GitBackend::copyText(const QString& text) {
    QGuiApplication::clipboard()->setText(text);
}

// ── Fetching in the background ───────────────────────────────────────────────
//
// GitHub Desktop fetches on its own; this app never did, so nothing about the
// remote — new commits, a deleted branch — reached the window until Fetch was
// pressed. Every five minutes while the window has focus, and on focus when the
// last fetch is more than a minute old.

void GitBackend::startBackgroundFetch() {
    if (!m_isRepo || !m_hasRemote || m_bgFetch || !m_busy.isEmpty()) return;
    // A fetch that failed — offline, a remote that wants a password — wrote
    // no FETCH_HEAD, so its age never drops; without a pause every focus of
    // the window would try again. Only after a failure: a successful fetch
    // updates FETCH_HEAD, and throttling those too blocked the fetch on coming
    // back from the browser whenever the app had fetched less than a minute
    // earlier — which is the case this exists for.
    const qint64 now = QDateTime::currentSecsSinceEpoch();
    if (m_lastFetchFailedAt && now - m_lastFetchFailedAt < 60) return;

    m_bgFetch = new QProcess(this);
    m_bgFetch->setWorkingDirectory(m_repoPath);
    // Never ask for anything: there is no terminal to answer in, and a
    // credential prompt would hang the fetch until the timeout. A remote
    // that needs one is fetched by the button, which reports the failure.
    QProcessEnvironment env = QProcessEnvironment::systemEnvironment();
    env.insert("GIT_TERMINAL_PROMPT", "0");
    env.insert("GIT_SSH_COMMAND", "ssh -o BatchMode=yes");
    m_bgFetch->setProcessEnvironment(env);
    const QString repo = m_repoPath;
    connect(m_bgFetch, &QProcess::finished, this, [this, repo](int code, QProcess::ExitStatus st) {
        m_lastFetchFailedAt = (st == QProcess::NormalExit && code == 0)
                                  ? 0 : QDateTime::currentSecsSinceEpoch();
        m_bgFetch->deleteLater();
        m_bgFetch = nullptr;
        emit fetchingChanged();
        // Offline, or a remote that wants credentials: silently nothing.
        if (repo == m_repoPath) refresh();
    });
    connect(m_bgFetch, &QProcess::errorOccurred, this, [this](QProcess::ProcessError e) {
        if (e != QProcess::FailedToStart) return;
        m_bgFetch->deleteLater();
        m_bgFetch = nullptr;
        emit fetchingChanged();
    });
    m_bgFetch->start("git", QStringList() << "fetch" << "--prune" << "--quiet");
    emit fetchingChanged();
}
