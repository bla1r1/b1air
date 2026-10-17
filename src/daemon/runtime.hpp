#pragma once

#include <sys/stat.h>
#include <unistd.h>
#include <pwd.h>
#include <cstdlib>
#include <string>

namespace b1air {

// $HOME, falling back to the passwd entry rather than to a guess: the old
// "/home/dev" default came from the development VM and silently pointed a
// real user's daemon at a path that does not exist on their machine.
inline std::string home_dir() {
    const char* home = std::getenv("HOME");
    if (home && *home) return home;
    if (const struct passwd* pw = getpwuid(getuid()); pw && pw->pw_dir) return pw->pw_dir;
    return {};
}

// Resolve a QML entry point by name ("Main.qml").
//
// `make install` deploys the QML to ~/.config/b1air-shell, while older setups
// kept it in ~/.config/quickshell. Checking only the latter meant a fresh
// install had no lock screen and four dead IPC entry points, all failing
// silently.
//
// install.sh installs the suite system-wide, and with it the QML to
// /usr/share/b1air-shell/qml — which this never looked in. A fresh install
// therefore had no shell ("Main.qml not found; the shell cannot start"), no
// Quickshell lock screen and no screenshot overlay; only machines that still
// carried a ~/.config copy from an older install worked. The per-user copies
// stay first so a `make install` without root still wins. Returns an empty
// string when no location has the file.
inline std::string qml_entry(const char* name) {
    const std::string home = home_dir();
    if (!home.empty()) {
        for (const char* dir : {"/.config/b1air-shell/", "/.config/quickshell/"}) {
            std::string path = home + dir + name;
            if (access(path.c_str(), R_OK) == 0) return path;
        }
    }
    std::string path = std::string("/usr/share/b1air-shell/qml/") + name;
    if (access(path.c_str(), R_OK) == 0) return path;
    return {};
}

// Made if missing, and put back to 0700 only when it is not: an
// unconditional chmod is an IN_ATTRIB on the directory every time, and the
// idle thread (idle.cpp) watches this one and calls runtime_path() on every
// wake — each chmod woke it for the next. It spun a core at 100% for the
// whole session, and everything watching $XDG_RUNTIME_DIR (the portals)
// woke with it.
inline void private_dir(const std::string& path) {
    struct stat st{};
    if (stat(path.c_str(), &st) != 0) {
        mkdir(path.c_str(), 0700);
    } else if ((st.st_mode & 07777) != 0700 && st.st_uid == getuid()) {
        chmod(path.c_str(), 0700);
    }
}

inline std::string runtime_dir() {
    const char* configured = std::getenv("XDG_RUNTIME_DIR");
    std::string base = configured && *configured ? configured : ("/tmp/b1air-" + std::to_string(static_cast<unsigned long>(getuid())));
    std::string dir = base + "/b1air";
    private_dir(base);
    private_dir(dir);
    return dir;
}

inline std::string runtime_path(const char* name) {
    return runtime_dir() + "/" + name;
}

} // namespace b1air
