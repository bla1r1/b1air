#include "backend.hpp"

#include <QDir>
#include <QFile>
#include <QProcess>
#include <QTextStream>
#include <sys/statvfs.h>
#include <csignal>
#include <thread>
#include <algorithm>
#include <fstream>
#include <QDateTime>
#include <QFileInfo>
#include <cerrno>
#include <cstring>
#include <pwd.h>
#include <unistd.h>
#include <dirent.h>
#include <fcntl.h>
#include <sys/stat.h>
#include <cstdio>
#include <cstdlib>

namespace b1air {

// ═════════════════════════════════════════════════════════════════════════════
// ProcessModel Implementation (Direct C++ Model — Zero JSON)
// ═════════════════════════════════════════════════════════════════════════════

ProcessModel::ProcessModel(QObject* parent)
    : QAbstractListModel(parent) {}

int ProcessModel::rowCount(const QModelIndex& parent) const {
    if (parent.isValid()) return 0;
    return static_cast<int>(m_filtered.size());
}

QVariant ProcessModel::data(const QModelIndex& index, int role) const {
    if (!index.isValid() || index.row() < 0 || index.row() >= static_cast<int>(m_filtered.size()))
        return QVariant();

    const auto& p = m_filtered[index.row()];
    switch (role) {
        case PidRole:  return p.pid;
        case CpuRole:  return p.cpu;
        case MemRole:  return p.mem;
        case UserRole: return p.user;
        case NameRole: return p.name;
        default: return QVariant();
    }
}

QHash<int, QByteArray> ProcessModel::roleNames() const {
    return {
        { PidRole,  "pid" },
        { CpuRole,  "cpu" },
        { MemRole,  "mem" },
        { UserRole, "user" },
        { NameRole, "name" }
    };
}

void ProcessModel::updateProcesses(std::vector<ProcessInfo> procs) {
    m_all = std::move(procs);
    applyFilterAndSort();
}

void ProcessModel::setFilter(const QString& filter) {
    m_filter = filter.trimmed().toLower();
    applyFilterAndSort();
}

void ProcessModel::setSort(const QString& field) {
    m_sortField = field;
    applyFilterAndSort();
}

void ProcessModel::applyFilterAndSort() {
    std::vector<ProcessInfo> next;
    next.reserve(m_all.size());
    for (const auto& p : m_all) {
        if (m_filter.isEmpty() ||
            p.name.toLower().contains(m_filter) ||
            p.user.toLower().contains(m_filter) ||
            QString::number(p.pid).contains(m_filter)) {
            next.push_back(p);
        }
    }

    // stable_sort, ties by pid: equal values kept swapping places between
    // samples, and the rows shuffled under the pointer.
    auto byPid = [](const ProcessInfo& a, const ProcessInfo& b) { return a.pid < b.pid; };
    if (m_sortField == "cpu") {
        std::stable_sort(next.begin(), next.end(), [&](const ProcessInfo& a, const ProcessInfo& b) {
            return a.cpu != b.cpu ? a.cpu > b.cpu : byPid(a, b);
        });
    } else if (m_sortField == "mem") {
        std::stable_sort(next.begin(), next.end(), [&](const ProcessInfo& a, const ProcessInfo& b) {
            return a.mem != b.mem ? a.mem > b.mem : byPid(a, b);
        });
    } else if (m_sortField == "pid") {
        std::stable_sort(next.begin(), next.end(), byPid);
    } else if (m_sortField == "name") {
        std::stable_sort(next.begin(), next.end(), [&](const ProcessInfo& a, const ProcessInfo& b) {
            const int c = a.name.compare(b.name, Qt::CaseInsensitive);
            return c != 0 ? c < 0 : byPid(a, b);
        });
    }

    // In place, not a model reset. A reset every refresh threw the list back
    // to the top 40 times a minute and rebuilt every row.
    const std::vector<ProcessInfo> prev = m_filtered;
    const int oldCount = static_cast<int>(m_filtered.size());
    const int newCount = static_cast<int>(next.size());
    if (newCount > oldCount) {
        beginInsertRows(QModelIndex(), oldCount, newCount - 1);
        m_filtered = std::move(next);
        endInsertRows();
    } else if (newCount < oldCount) {
        beginRemoveRows(QModelIndex(), newCount, oldCount - 1);
        m_filtered = std::move(next);
        endRemoveRows();
    } else {
        m_filtered = std::move(next);
    }
    // Only the rows that read differently: every row was told it changed on
    // every sample, and each one on screen redid all its bindings — on an
    // idle machine, for the same numbers.
    const auto same = [](const ProcessInfo& a, const ProcessInfo& b) {
        return a.pid == b.pid && a.cpu == b.cpu && a.mem == b.mem && a.name == b.name && a.user == b.user;
    };
    const int common = std::min(oldCount, newCount);
    int from = -1;
    for (int i = 0; i <= common; ++i) {
        const bool changed = i < common && !same(prev[size_t(i)], m_filtered[size_t(i)]);
        if (changed && from < 0) from = i;
        if (!changed && from >= 0) {
            emit dataChanged(index(from), index(i - 1));
            from = -1;
        }
    }
}

// ═════════════════════════════════════════════════════════════════════════════
// MonitorBackend Implementation
// ═════════════════════════════════════════════════════════════════════════════

MonitorBackend::MonitorBackend(QObject* parent)
    : QObject(parent)
    , m_procModel(new ProcessModel(this))
    , m_timer(new QTimer(this))
{
    m_cores = static_cast<int>(std::thread::hardware_concurrency());
    if (m_cores <= 0) m_cores = 1;

    // CPU Model from /proc/cpuinfo
    QFile cpuinfo("/proc/cpuinfo");
    if (cpuinfo.open(QIODevice::ReadOnly | QIODevice::Text)) {
        QTextStream in(&cpuinfo);
        while (!in.atEnd()) {
            QString line = in.readLine();
            if (line.startsWith("model name") || line.startsWith("Hardware") || line.startsWith("Processor")) {
                int col = line.indexOf(':');
                if (col != -1 && col + 2 < line.size()) {
                    m_cpuModel = line.mid(col + 2).trimmed();
                    break;
                }
            }
        }
    }

    // No seeded history.
    //
    // This used to push forty zeros in before the first sample, and the chart
    // draws forty slots across its width — so a freshly opened window showed a
    // flat line pinned to zero for the first minute and then a vertical cliff
    // where the real readings began. It looked like a fault, and the ceiling
    // logic scaled the axis against data that was not measured.
    //
    // The chart already right-aligns whatever it is given, so an empty buffer
    // simply draws a short trace at the right edge that grows leftwards as the
    // minute fills. That is also the honest picture: nothing is shown for time
    // the program was not running.

    connect(m_timer, &QTimer::timeout, this, &MonitorBackend::poll);
    m_timer->start(1500);

    poll();
}

void MonitorBackend::refresh() {
    poll();
}

bool MonitorBackend::killProcess(int pid, bool force) {
    if (pid <= 1) return false;
    if (::kill(pid, force ? SIGKILL : SIGTERM) != 0) {
        // It failed in silence before: a root process simply stayed.
        const int e = errno;
        emit killFailed(e == EPERM ? QStringLiteral("Not allowed: process %1 belongs to another user").arg(pid)
                      : e == ESRCH ? QStringLiteral("Process %1 has already exited").arg(pid)
                      : QStringLiteral("Could not end process %1: %2").arg(pid).arg(QString::fromLocal8Bit(strerror(e))));
        return false;
    }
    poll();
    return true;
}

void MonitorBackend::setProcessFilter(const QString& query) {
    if (m_procModel) m_procModel->setFilter(query);
}

void MonitorBackend::setProcessSort(const QString& sortBy) {
    if (m_procModel) m_procModel->setSort(sortBy);
}

void MonitorBackend::poll() {
    updateCpu();
    updateMemory();
    updateDisk();
    updateLoadAndUptime();
    updateProcesses();

    // History shift
    m_cpuHistory.append(m_cpuPercent);
    if (m_cpuHistory.size() > 40) m_cpuHistory.removeFirst();

    m_ramHistory.append(m_ramPercent);
    if (m_ramHistory.size() > 40) m_ramHistory.removeFirst();

    emit historyChanged();
}

void MonitorBackend::updateCpu() {
    QFile statFile("/proc/stat");
    if (statFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
        QTextStream in(&statFile);
        QString line = in.readLine();
        QStringList tokens = line.split(QChar(' '), Qt::SkipEmptyParts);
        if (tokens.size() >= 5) {
            unsigned long long u = tokens[1].toULongLong();
            unsigned long long n = tokens[2].toULongLong();
            unsigned long long s = tokens[3].toULongLong();
            unsigned long long i = tokens[4].toULongLong();
            unsigned long long io = (tokens.size() > 5) ? tokens[5].toULongLong() : 0;
            unsigned long long irq = (tokens.size() > 6) ? tokens[6].toULongLong() : 0;
            unsigned long long sirq = (tokens.size() > 7) ? tokens[7].toULongLong() : 0;
            unsigned long long st = (tokens.size() > 8) ? tokens[8].toULongLong() : 0;

            unsigned long long idle = i + io;
            unsigned long long non_idle = u + n + s + irq + sirq + st;
            unsigned long long total = idle + non_idle;

            if (m_prevTotal > 0 && total > m_prevTotal) {
                unsigned long long d_total = total - m_prevTotal;
                unsigned long long d_idle = idle - m_prevIdle;
                qreal pct = static_cast<qreal>(d_total - d_idle) * 100.0 / static_cast<qreal>(d_total);
                if (pct < 0.0) pct = 0.0;
                if (pct > 100.0) pct = 100.0;
                m_cpuPercent = pct;
                emit cpuChanged();
            }

            m_prevIdle = idle;
            m_prevTotal = total;
        }
    }
}

void MonitorBackend::updateMemory() {
    std::ifstream f("/proc/meminfo");
    if (!f.is_open()) return;

    std::string key;
    long long val = 0;
    std::string unit;
    long long totalKb = 0, availKb = 0, swapTotalKb = 0, swapFreeKb = 0;

    while (f >> key >> val >> unit) {
        if (key == "MemTotal:") totalKb = val;
        else if (key == "MemAvailable:") availKb = val;
        else if (key == "SwapTotal:") swapTotalKb = val;
        else if (key == "SwapFree:") swapFreeKb = val;
    }

    long long usedKb = totalKb - availKb;
    if (usedKb < 0) usedKb = 0;

    m_ramUsedMb = usedKb / 1024.0;
    m_ramTotalMb = totalKb / 1024.0;
    m_ramPercent = (totalKb > 0) ? (static_cast<qreal>(usedKb) * 100.0 / totalKb) : 0.0;

    long long swapUsedKb = swapTotalKb - swapFreeKb;
    if (swapUsedKb < 0) swapUsedKb = 0;
    m_swapUsedMb = swapUsedKb / 1024.0;
    m_swapTotalMb = swapTotalKb / 1024.0;

    emit ramChanged();
    emit swapChanged();
}

void MonitorBackend::updateDisk() {
    struct statvfs fs;
    if (statvfs("/", &fs) == 0) {
        double total = static_cast<double>(fs.f_blocks) * fs.f_frsize;
        double free = static_cast<double>(fs.f_bavail) * fs.f_frsize;
        m_diskTotalGb = total / (1024.0 * 1024.0 * 1024.0);
        m_diskFreeGb = free / (1024.0 * 1024.0 * 1024.0);
        m_diskPercent = (total > 0) ? (((total - free) * 100.0) / total) : 0.0;
        emit diskChanged();
    }
}

void MonitorBackend::updateLoadAndUptime() {
    QFile loadFile("/proc/loadavg");
    if (loadFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
        QTextStream in(&loadFile);
        QString line = in.readLine();
        QStringList parts = line.split(QChar(' '), Qt::SkipEmptyParts);
        if (parts.size() >= 3) {
            m_loadAvg = parts[0] + " " + parts[1] + " " + parts[2];
            emit loadAvgChanged();
        }
    }

    QFile upFile("/proc/uptime");
    if (upFile.open(QIODevice::ReadOnly | QIODevice::Text)) {
        QTextStream in(&upFile);
        double sec = 0;
        in >> sec;
        int hrs = static_cast<int>(sec) / 3600;
        int mins = (static_cast<int>(sec) % 3600) / 60;
        m_uptime = QString::number(hrs) + "h " + QString::number(mins) + "m";
        emit uptimeChanged();
    }
}

// Every process, read from /proc. This ran `ps --sort=-pcpu` and kept the
// first 40 lines: the filter searched those 40 and nothing else, "Sort by RAM"
// re-sorted the 40 busiest by CPU, and the footer counted 40 tasks on any
// machine. ps's %CPU is also the average over the process's whole life, not
// what it is doing now; this is the share of the last interval, as top shows.
namespace {

// A small file under /proc, whole, by a path relative to the open /proc.
// QFile cost more than the reading: an object, a path built, an open through
// its engine, for each of three files of each of hundreds of processes.
ssize_t readProc(int procFd, const char* path, char* buf, size_t size) {
    const int fd = openat(procFd, path, O_RDONLY | O_CLOEXEC);
    if (fd < 0) return -1;
    const ssize_t n = read(fd, buf, size - 1);
    close(fd);
    buf[n > 0 ? n : 0] = 0;
    return n;
}

} // namespace

void MonitorBackend::updateProcesses() {
    static const long ticksPerSec = sysconf(_SC_CLK_TCK);
    static const long pageKb = sysconf(_SC_PAGESIZE) / 1024;
    const qint64 nowMs = QDateTime::currentMSecsSinceEpoch();
    const double elapsedTicks = m_prevProcSampleMs > 0
        ? (nowMs - m_prevProcSampleMs) / 1000.0 * ticksPerSec : 0.0;
    const double memTotalKb = m_ramTotalMb > 0 ? m_ramTotalMb * 1024.0 : 0.0;

    std::vector<ProcessInfo> list;
    list.reserve(m_prevProcTicks.size() + 16);
    QHash<int, unsigned long long> ticksNow;
    ticksNow.reserve(m_prevProcTicks.size() + 16);
    QHash<int, LongName> longNames;
    DIR* proc = opendir("/proc");
    if (!proc) return;
    const int procFd = dirfd(proc);
    char buf[4096];
    char path[64];
    while (const struct dirent* e = readdir(proc)) {
        if (e->d_type != DT_DIR && e->d_type != DT_UNKNOWN) continue;
        char* end = nullptr;
        const long pid = std::strtol(e->d_name, &end, 10);
        if (!end || *end || pid <= 0) continue;

        std::snprintf(path, sizeof(path), "%ld/stat", pid);
        if (readProc(procFd, path, buf, sizeof(buf)) <= 0) continue;
        // comm is in parentheses and may itself hold spaces or ')'.
        const char* open = std::strchr(buf, '(');
        const char* close = std::strrchr(buf, ')');
        if (!open || !close || close < open || close[1] == 0) continue;
        // The fields after comm, from the state (field 3) on: utime and
        // stime are 14 and 15, rss 24.
        unsigned long long utime = 0, stime = 0;
        long long rssPages = 0;
        const char* f = close + 2;
        int field = 3;
        while (*f && field <= 24) {
            if (field == 14) utime = std::strtoull(f, nullptr, 10);
            else if (field == 15) stime = std::strtoull(f, nullptr, 10);
            else if (field == 24) rssPages = std::strtoll(f, nullptr, 10);
            f = std::strchr(f, ' ');
            if (!f) break;
            ++f;
            ++field;
        }
        if (field < 24) continue;
        const unsigned long long ticks = utime + stime;
        ticksNow.insert(int(pid), ticks);
        QString name = QString::fromUtf8(open + 1, close - open - 1);

        // comm stops at 15 characters ("environment-man"); the executable's
        // own name is in cmdline — read once for each process, not on every
        // sample.
        if (name.size() >= 15) {
            const auto known = m_longNames.constFind(int(pid));
            if (known != m_longNames.cend() && known->comm == name) {
                longNames.insert(int(pid), *known);
                name = known->name;
            } else {
                const QString comm = name;
                std::snprintf(path, sizeof(path), "%ld/cmdline", pid);
                if (readProc(procFd, path, buf, sizeof(buf)) > 0) {
                    const QString exe = QFileInfo(QString::fromUtf8(buf)).fileName();   // argv[0]
                    if (exe.startsWith(name)) name = exe;
                }
                longNames.insert(int(pid), {comm, name});
            }
        }

        ProcessInfo p;
        p.pid = int(pid);
        p.name = std::move(name);
        const auto prev = m_prevProcTicks.constFind(int(pid));
        p.cpu = (elapsedTicks > 0 && prev != m_prevProcTicks.cend() && ticks >= *prev)
                ? float((ticks - *prev) / elapsedTicks * 100.0) : 0.0f;
        p.mem = memTotalKb > 0 ? float(rssPages * pageKb / memTotalKb * 100.0) : 0.0f;

        struct stat st {};
        const uint uid = fstatat(procFd, e->d_name, &st, 0) == 0 ? st.st_uid : 0;
        auto u = m_userNames.constFind(uid);
        if (u == m_userNames.cend()) {
            const struct passwd* pw = getpwuid(uid);
            u = m_userNames.insert(uid, pw ? QString::fromUtf8(pw->pw_name) : QString::number(uid));
        }
        p.user = *u;
        list.push_back(std::move(p));
    }
    closedir(proc);
    m_prevProcTicks = std::move(ticksNow);
    m_longNames = std::move(longNames);
    m_prevProcSampleMs = nowMs;

    if (m_taskCount != int(list.size())) {
        m_taskCount = int(list.size());
        emit tasksChanged();
    }
    if (m_procModel) {
        m_procModel->updateProcesses(std::move(list));
    }
}

} // namespace b1air
