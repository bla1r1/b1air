#include "proc_util.hpp"
#include "user_manager.hpp"
#include <pwd.h>
#include <grp.h>
#include <unistd.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <cstdlib>
#include <iostream>
#include <sstream>
#include <fstream>
#include <vector>
#include <sys/wait.h>
#include <fcntl.h>
#include <algorithm>

namespace b1air {


static bool run_argv(const std::vector<std::string>& args, bool quiet = false) {
    if (args.empty()) return false;
    std::vector<char*> argv;
    argv.reserve(args.size() + 1);
    for (const auto& arg : args) argv.push_back(const_cast<char*>(arg.c_str()));
    argv.push_back(nullptr);
    pid_t pid = fork();
    if (pid < 0) return false;
    if (pid == 0) {
        if (quiet) {
            int null = open("/dev/null", O_WRONLY);
            if (null >= 0) { dup2(null, STDOUT_FILENO); close(null); }
        }
        execvp(argv[0], argv.data());
        _exit(127);
    }
    int status = 0;
    return waitpid(pid, &status, 0) == pid && WIFEXITED(status) && WEXITSTATUS(status) == 0;
}

// AccountsService, which is how the login screen learns the picture and the
// name: sddm cannot read ~/.face.icon in a home only its owner opens, and
// /var/lib/AccountsService/icons is root's. Changing one's own account is
// allowed there without a password (org.freedesktop.accounts.change-own-
// user-data). FindUserByName first: the service loads an account only when
// asked about it.
static bool accounts_call(const UserProfile& p, const std::string& method, const std::string& value) {
    if (!run_argv({"busctl", "call", "org.freedesktop.Accounts", "/org/freedesktop/Accounts",
                   "org.freedesktop.Accounts", "FindUserByName", "s", p.username}, true))
        return false;
    return run_argv({"busctl", "call", "org.freedesktop.Accounts", "/org/freedesktop/Accounts/User" + p.uid,
                     "org.freedesktop.Accounts.User", method, "s", value}, true);
}

UserProfile UserManager::get_current_user_profile() {
    UserProfile p;

    uid_t uid = getuid();
    struct passwd* pw = getpwuid(uid);

    const char* user_env = std::getenv("USER");
    p.username = pw ? pw->pw_name : (user_env ? user_env : "user");
    p.uid = std::to_string(uid);
    p.home = pw ? pw->pw_dir : (std::getenv("HOME") ? std::getenv("HOME") : "/home/" + p.username);
    p.shell = pw ? pw->pw_shell : (std::getenv("SHELL") ? std::getenv("SHELL") : "/bin/bash");

    // Parse GECOS for display name
    if (pw && pw->pw_gecos && pw->pw_gecos[0] != '\0') {
        std::string gecos = pw->pw_gecos;
        size_t comma = gecos.find(',');
        p.name = (comma != std::string::npos) ? gecos.substr(0, comma) : gecos;
    }
    if (p.name.empty()) {
        p.name = p.username;
    }

    // Avatar path discovery
    std::string icon1 = p.home + "/.face.icon";
    std::string icon2 = p.home + "/.face";
    std::string icon3 = "/var/lib/AccountsService/icons/" + p.username;

    struct stat st;
    if (stat(icon1.c_str(), &st) == 0) {
        p.avatar = icon1;
    } else if (stat(icon2.c_str(), &st) == 0) {
        p.avatar = icon2;
    } else if (stat(icon3.c_str(), &st) == 0) {
        p.avatar = icon3;
    }

    // User groups
    int ngroups = 64;
#if defined(__APPLE__)
    std::vector<int> groups(ngroups);
    if (getgrouplist(p.username.c_str(), static_cast<int>(pw ? pw->pw_gid : 1000), groups.data(), &ngroups) >= 0) {
        std::ostringstream gs;
        for (int i = 0; i < ngroups; ++i) {
            struct group* gr = getgrgid(static_cast<gid_t>(groups[i]));
            if (gr) {
                if (i > 0) gs << ", ";
                gs << gr->gr_name;
            }
        }
        p.groups = gs.str();
    }
#else
    std::vector<gid_t> groups(ngroups);
    if (getgrouplist(p.username.c_str(), pw ? pw->pw_gid : 1000, groups.data(), &ngroups) >= 0) {
        std::ostringstream gs;
        for (int i = 0; i < ngroups; ++i) {
            struct group* gr = getgrgid(groups[i]);
            if (gr) {
                if (i > 0) gs << ", ";
                gs << gr->gr_name;
            }
        }
        p.groups = gs.str();
    }
#endif

    return p;
}

std::string UserManager::get_user_info_json() {
    UserProfile p = get_current_user_profile();

    std::ostringstream ss;
    ss << "{\n";
    ss << "  \"username\": \"" << util::escape_json(p.username) << "\",\n";
    ss << "  \"name\": \"" << util::escape_json(p.name) << "\",\n";
    ss << "  \"uid\": \"" << util::escape_json(p.uid) << "\",\n";
    ss << "  \"home\": \"" << util::escape_json(p.home) << "\",\n";
    ss << "  \"shell\": \"" << util::escape_json(p.shell) << "\",\n";
    ss << "  \"avatar\": \"" << util::escape_json(p.avatar) << "\",\n";
    ss << "  \"groups\": \"" << util::escape_json(p.groups) << "\"\n";
    ss << "}\n";

    return ss.str();
}

static bool copy_file(const std::string& src, const std::string& dst) {
    std::ifstream in(src, std::ios::binary);
    if (!in.is_open()) return false;
    std::ofstream out(dst, std::ios::binary | std::ios::trunc);
    if (!out.is_open()) return false;
    out << in.rdbuf();
    chmod(dst.c_str(), 0644);
    return true;
}

bool UserManager::set_avatar(const std::string& image_path) {
    UserProfile p = get_current_user_profile();
    if (image_path.empty()) return false;

    struct stat st;
    if (stat(image_path.c_str(), &st) != 0) return false;

    // The lock screen and the password dialog read ~/.face.icon; the login
    // screen reads AccountsService's copy. A copy of the copy, so the picture
    // stays when the file picked is moved or was a temporary one.
    const std::string face = p.home + "/.face.icon";
    bool ok1 = image_path == face || copy_file(image_path, face);
    bool ok2 = copy_file(image_path, p.home + "/.face");

    // At most 1 MB (AccountsService refuses bigger); the shell hands over a
    // 512-pixel PNG.
    if (!accounts_call(p, "SetIconFile", ok1 ? face : image_path))
        std::cerr << "[b1air-daemon] AccountsService did not take the picture; the login screen keeps the old one\n";

    return ok1 || ok2;
}

bool UserManager::set_name(const std::string& new_name) {
    if (new_name.empty()) return false;
    UserProfile p = get_current_user_profile();
    // chfn asks for the password on a terminal, and from Settings there is none.
    return accounts_call(p, "SetRealName", new_name) || run_argv({"chfn", "-f", new_name, p.username});
}

bool UserManager::set_shell(const std::string& new_shell) {
    if (new_shell.empty()) return false;
    struct stat st;
    if (stat(new_shell.c_str(), &st) != 0 || !(st.st_mode & S_IXUSR) || new_shell.find('\n') != std::string::npos) {
        return false;
    }
    UserProfile p = get_current_user_profile();
    std::ifstream shells("/etc/shells");
    std::string line;
    bool allowed = false;
    while (std::getline(shells, line)) if (line == new_shell) { allowed = true; break; }
    if (!allowed) return false;
    return run_argv({"chsh", "-s", new_shell, p.username});
}

bool UserManager::change_password() {
    // Use the bundled terminal for interactive password changes.
    if (access("/usr/local/bin/b1air-term", X_OK) == 0 || access("/usr/bin/b1air-term", X_OK) == 0)
        return run_argv({"b1air-term", "-e", "passwd"});
    return run_argv({"passwd"});
}

} // namespace b1air
