#pragma once

// =============================================================================
// Finding and signalling processes by reading /proc, instead of running
// pgrep, pkill and pidof and parsing what they print.
//
// Each of those cost a process, and each had a way of being wrong that this
// project ran into:
//   - pgrep counts a zombie as running, so a crashed shell looked alive;
//   - `pgrep -f` matches any command line containing the word, its own and
//     the script's that called it included, so a test script that merely
//     mentioned "quickshell" kept the session from starting one;
//   - `pgrep -x` compares the kernel's 15-character name, so
//     `pgrep -x telegram-desktop` never found anything.
//
// Here a process is live unless it is a zombie or dead, the caller never
// finds itself, and a name matches either the kernel's name or the base name
// of argv[0]. Only this user's processes are looked at: the session has no
// business with anyone else's.
// =============================================================================

#include <cerrno>
#include <csignal>
#include <cstdio>
#include <cstring>
#include <dirent.h>
#include <fstream>
#include <functional>
#include <sstream>
#include <string>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>
#include <vector>

namespace b1air::proc {

struct Process {
    pid_t pid = 0;
    std::string comm;      // the kernel's name, at most 15 characters
    std::string exe_name;  // base name of argv[0]
    std::string cmdline;   // arguments joined by spaces
};

inline std::string read_small(const std::string& path) {
    std::ifstream f(path, std::ios::binary);
    std::ostringstream ss;
    ss << f.rdbuf();
    return ss.str();
}

// Every live process of this user, but not the caller.
inline void for_each(const std::function<bool(const Process&)>& visit) {
    DIR* dir = opendir("/proc");
    if (!dir) return;
    const pid_t self = getpid();
    const uid_t me = getuid();
    while (struct dirent* e = readdir(dir)) {
        char* end = nullptr;
        const long pid = std::strtol(e->d_name, &end, 10);
        if (!end || *end || pid <= 0 || pid == self) continue;
        const std::string base = std::string("/proc/") + e->d_name;

        struct stat st {};
        if (stat(base.c_str(), &st) != 0 || st.st_uid != me) continue;

        // stat: "pid (comm) S ..." — comm may itself contain ") ".
        const std::string stat_line = read_small(base + "/stat");
        const size_t open = stat_line.find('('), close = stat_line.rfind(')');
        if (open == std::string::npos || close == std::string::npos || close + 2 >= stat_line.size()) continue;
        const char state = stat_line[close + 2];
        if (state == 'Z' || state == 'X' || state == 'x') continue;

        Process p;
        p.pid = static_cast<pid_t>(pid);
        p.comm = stat_line.substr(open + 1, close - open - 1);
        std::string raw = read_small(base + "/cmdline");
        if (!raw.empty()) {
            const std::string argv0 = raw.c_str();
            p.exe_name = argv0.substr(argv0.rfind('/') + 1);
            for (char& c : raw) if (c == '\0') c = ' ';
            while (!raw.empty() && raw.back() == ' ') raw.pop_back();
            p.cmdline = raw;
        }
        if (!visit(p)) break;
    }
    closedir(dir);
}

inline bool name_matches(const Process& p, const std::string& name) {
    // The kernel keeps 15 characters of the name; a longer one matches on
    // that prefix, or on argv[0].
    return p.exe_name == name || p.comm == name
        || (name.size() > 15 && p.comm == name.substr(0, 15));
}

// pids of processes with this exact name.
inline std::vector<pid_t> find(const std::string& name) {
    std::vector<pid_t> out;
    for_each([&](const Process& p) {
        if (name_matches(p, name)) out.push_back(p.pid);
        return true;
    });
    return out;
}

inline bool running(const std::string& name) {
    bool found = false;
    for_each([&](const Process& p) {
        found = name_matches(p, name);
        return !found;
    });
    return found;
}

// Any process whose command line contains `needle` (what `pgrep -f` did,
// without finding itself).
inline bool running_with(const std::string& needle) {
    bool found = false;
    for_each([&](const Process& p) {
        found = p.cmdline.find(needle) != std::string::npos;
        return !found;
    });
    return found;
}

// Signals every process with this name; how many were signalled.
inline int kill_all(const std::string& name, int sig = SIGTERM) {
    int n = 0;
    for (const pid_t pid : find(name))
        if (::kill(pid, sig) == 0) ++n;
    return n;
}

} // namespace b1air::proc
