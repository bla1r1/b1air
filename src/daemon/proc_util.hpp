#pragma once

// Small helpers that had been copy-pasted between translation units.
//
// `escape_json` existed verbatim in focustime_db.cpp and user_manager.cpp, and
// `spawn_detached` in daemon_dbus.cpp had a near-identical twin in
// system_control.cpp called run_argv_detached — the same fork/setsid/dup2/execvp
// body differing only in one optional argument. Both were `static`, so nothing
// complained; they simply drifted apart in private.
//
// Header-only and inline on purpose: no build file needs to learn about a new
// source, which is one less place for the copies to come back.

#include <fcntl.h>
#include <cstring>
#include <sys/stat.h>
#include <cerrno>
#include <unistd.h>
#include <cstdlib>
#include <sys/wait.h>

#include <iomanip>
#include <sstream>
#include <string>
#include <vector>

extern char **environ;

namespace b1air {
namespace util {

/**
 * Escape a string for embedding in a JSON document.
 *
 * The copies this replaces handled the seven named escapes and passed
 * everything else through — including the C0 control characters below 0x20,
 * which JSON requires to be escaped. A window title carrying one of those
 * produced a document that would not parse, and window titles are exactly what
 * these functions serialise.
 */
inline std::string escape_json(const std::string& s) {
    std::ostringstream o;
    for (unsigned char c : s) {
        switch (c) {
        case '"':  o << "\\\""; break;
        case '\\': o << "\\\\"; break;
        case '\b': o << "\\b";  break;
        case '\f': o << "\\f";  break;
        case '\n': o << "\\n";  break;
        case '\r': o << "\\r";  break;
        case '\t': o << "\\t";  break;
        default:
            if (c < 0x20) {
                o << "\\u" << std::hex << std::setw(4) << std::setfill('0')
                  << static_cast<int>(c) << std::dec;
            } else {
                o << static_cast<char>(c);
            }
        }
    }
    return o.str();
}

/**
 * Run a command without a shell, fully detached from this process.
 *
 * No shell means no quoting rules to get wrong: arguments arrive at the child
 * exactly as given, whatever is in them.
 *
 * Returns whether the fork succeeded — the child is not waited on, so this says
 * nothing about whether the command itself worked.
 */
inline bool spawn_detached(const std::vector<std::string>& args,
                           const char* wayland_display = nullptr) {
    if (args.empty()) return false;

    // Everything the child needs is built here, before the fork.
    //
    // fork() in a process with threads gives the child one thread and every
    // lock exactly as it was at that instant — including the allocator's. If
    // another thread happened to be inside malloc, the child deadlocks the
    // first time it allocates, which it did: the argv vector was being built
    // *after* the fork. The child then never reached execvp and never exited,
    // and the parent sat in the waitpid below for ever.
    //
    // That is not theoretical. The shell's restart watchdog runs on its own
    // thread; its first respawn hung the whole watchdog, so a desktop that had
    // lost its shell stayed that way. Between fork and exec this now does
    // nothing but open/dup2/setsid/execvp, all of which are safe there.
    std::vector<char*> argv;
    argv.reserve(args.size() + 1);
    for (const auto& arg : args) argv.push_back(const_cast<char*>(arg.c_str()));
    argv.push_back(nullptr);

    // Same reason: an environment for the child, assembled before the fork
    // rather than by calling setenv() inside it.
    std::string wl_entry;
    std::vector<char*> envp;
    if (wayland_display) {
        wl_entry = std::string("WAYLAND_DISPLAY=") + wayland_display;
        for (char** e = environ; e && *e; ++e) {
            if (std::strncmp(*e, "WAYLAND_DISPLAY=", 16) != 0)
                envp.push_back(*e);
        }
        envp.push_back(const_cast<char*>(wl_entry.c_str()));
        envp.push_back(nullptr);
    }

    // Double fork. The first child forks again and exits at once; the
    // grandchild is orphaned and inherited by init, which reaps it. The parent
    // waits only for the short-lived middle process.
    //
    // The single fork this replaces left a zombie behind for every helper the
    // daemon ever launched — a screenshot overlay, a polkit dialog, an editor —
    // because a child that calls setsid() is still its parent's child, and
    // nothing here ever waited on it. The comment claimed init would adopt it;
    // init only adopts a child whose parent has *exited*, which for a session
    // daemon is never. Measured on a running session: eight zombies parented
    // to the daemon after an afternoon of launching helpers.
    //
    // SIGCHLD could not simply be ignored instead: this daemon also runs
    // commands with waitpid() and needs their exit status.
    pid_t pid = fork();
    if (pid < 0) return false;

    if (pid == 0) {
        pid_t inner = fork();
        if (inner < 0) _exit(127);
        if (inner > 0) _exit(0);

        (void)setsid();
        const int null_fd = open("/dev/null", O_RDWR | O_CLOEXEC);
        if (null_fd >= 0) {
            dup2(null_fd, STDIN_FILENO);
            dup2(null_fd, STDOUT_FILENO);
            dup2(null_fd, STDERR_FILENO);
            if (null_fd > STDERR_FILENO) close(null_fd);
        }

        if (!envp.empty())
            execvpe(argv[0], argv.data(), envp.data());
        else
            execvp(argv[0], argv.data());
        _exit(127);
    }

    // Reap the middle process, which has already exited. This is the only wait
    // in a detached spawn, and it returns immediately.
    int status = 0;
    while (waitpid(pid, &status, 0) < 0 && errno == EINTR) {}

    // Says the fork worked, nothing about the command: the grandchild is not
    // waited on, by design. Callers that need an exit status should not be
    // using a detached spawn.
    return true;
}

/**
 * Create a directory and every parent it needs.
 *
 * mkdir(2) makes one level. The screenshot path went through a single
 * mkdir("$HOME/Pictures/Screenshots"), which fails with ENOENT on any machine
 * where ~/Pictures does not exist yet — a fresh install, before anything has
 * created the XDG user directories — so the capture was written nowhere and
 * the only sign was a non-zero exit nobody sees. A configured folder nested
 * more than one level deep failed the same way.
 *
 * Returns whether the directory exists afterwards.
 */
/**
 * Whether `name` is an executable somewhere on $PATH — the check `command -v`
 * makes, without a shell.
 */
inline bool command_exists(const std::string& name) {
    const char* path = std::getenv("PATH");
    if (!path || name.empty() || name.find('/') != std::string::npos) return false;
    std::string dirs(path);
    size_t start = 0;
    while (start <= dirs.size()) {
        const size_t end = dirs.find(':', start);
        const std::string dir = dirs.substr(start, end == std::string::npos ? std::string::npos : end - start);
        if (!dir.empty() && ::access((dir + "/" + name).c_str(), X_OK) == 0) return true;
        if (end == std::string::npos) break;
        start = end + 1;
    }
    return false;
}

inline bool mkdir_p(const std::string& path, mode_t mode = 0755) {
    if (path.empty()) return false;

    std::string built;
    size_t i = 0;
    if (path[0] == '/') { built = "/"; i = 1; }

    while (i <= path.size()) {
        const size_t slash = path.find('/', i);
        const std::string part = path.substr(i, slash == std::string::npos ? std::string::npos : slash - i);
        if (!part.empty()) {
            if (built.size() > 1 || (built.size() == 1 && built[0] != '/')) built += "/";
            built += part;
            if (mkdir(built.c_str(), mode) != 0 && errno != EEXIST) return false;
        }
        if (slash == std::string::npos) break;
        i = slash + 1;
    }

    struct stat st{};
    return stat(path.c_str(), &st) == 0 && S_ISDIR(st.st_mode);
}

} // namespace util
} // namespace b1air
