#include "proc_util.hpp"
#include "system_control.hpp"
#include "sway_ipc.hpp"
#include "settings_manager.hpp"
#include <cmath>
#include <nlohmann/json.hpp>
#include "secret_store.hpp"

#include <iostream>
#include <openssl/crypto.h>
#include <fstream>
#include <pwd.h>
#include <cstdlib>
#include <unistd.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <chrono>
#include <iomanip>
#include <sstream>
#include <algorithm>
#include <functional>
#include <array>
#include <memory>
#include <random>
#include <vector>
#include <unordered_set>
#include <unordered_map>
#include <thread>
#include <cstring>
#include <cctype>
#include <cstdio>
#include <cstdarg>
#include <dirent.h>
#include <filesystem>
#include <csignal>
#include <climits>
#include <sys/statvfs.h>
#include <sys/wait.h>
#include <systemd/sd-bus.h>
#include <arpa/inet.h>
#include <netdb.h>
#include "runtime.hpp"

namespace b1air {

static bool is_game_mode_active() {
    return (access(runtime_path("game-mode.state").c_str(), F_OK) == 0);
}

// ── Helper to execute command and capture single line stdout ────────────────
static std::string exec_cmd(const std::string& cmd) {
    std::array<char, 256> buffer;
    std::string result;
    FILE* pipe = popen(cmd.c_str(), "r");
    if (!pipe) return "";
    while (fgets(buffer.data(), buffer.size(), pipe) != nullptr) {
        result += buffer.data();
    }
    pclose(pipe);
    // Trim trailing newline
    while (!result.empty() && (result.back() == '\n' || result.back() == '\r')) {
        result.pop_back();
    }
    return result;
}

static std::string exec_cmd_full(const std::string& cmd) {
    std::array<char, 4096> buffer;
    std::string result;
    FILE* pipe = popen(cmd.c_str(), "r");
    if (!pipe) return "";
    while (fgets(buffer.data(), buffer.size(), pipe) != nullptr) {
        result += buffer.data();
    }
    pclose(pipe);
    return result;
}

static std::string json_escape(const std::string& s) {
    std::string out;
    out.reserve(s.size());
    for (char c : s) {
        if (c == '"') out += "\\\"";
        else if (c == '\\') out += "\\\\";
        else if (c == '\b') out += "\\b";
        else if (c == '\f') out += "\\f";
        else if (c == '\n') out += "\\n";
        else if (c == '\r') out += "\\r";
        else if (c == '\t') out += "\\t";
        else out += c;
    }
    return out;
}

// Quote data before passing it to one of the legacy shell-only helpers.
// New code should prefer execve/QProcess and avoid a shell entirely.
static std::string shell_quote(const std::string& s) {
    std::string out = "'";
    for (char c : s) {
        if (c == '\'') out += "'\\''";
        else out += c;
    }
    out += "'";
    return out;
}

static bool valid_geometry(const std::string& value) {
    if (value.empty() || value.size() > 128) return false;
    for (unsigned char c : value) {
        if (!(std::isdigit(c) || c == ',' || c == ' ' || c == 'x' || c == 'X' || c == '-' || c == '.')) return false;
    }
    return true;
}

// Sway receives commands as a small command language over IPC.  File paths
// must therefore not be interpolated into that language without rejecting its
// separators and quoting characters.  The same path is still passed as an
// argv element to external tools, but Sway needs this additional check.
static bool safe_sway_path(const std::string& value) {
    if (value.empty() || value.size() > PATH_MAX) return false;
    for (unsigned char c : value) {
        if (std::iscntrl(c) || c == '\'' || c == '"' || c == '\\' ||
            c == ';' || c == '{' || c == '}' || c == '[' || c == ']' ||
            c == '$' || c == '#') return false;
    }
    return true;
}

static bool safe_wallpaper_file(const std::string& value, std::string& resolved) {
    if (value.empty() || value.size() > PATH_MAX) return false;
    char path[PATH_MAX];
    if (!realpath(value.c_str(), path)) return false;
    struct stat st{};
    if (stat(path, &st) != 0 || !S_ISREG(st.st_mode) || st.st_size <= 0 || st.st_size > 50 * 1024 * 1024) return false;
    const std::string lower = [&] {
        std::string ext = std::filesystem::path(path).extension().string();
        std::transform(ext.begin(), ext.end(), ext.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
        return ext;
    }();
    if (lower != ".jpg" && lower != ".jpeg" && lower != ".png" && lower != ".webp") return false;
    resolved = path;
    return true;
}

static bool safe_art_url(const std::string& url) {
    if (url.size() > 2048) return false;
    const bool http = url.rfind("http://", 0) == 0;
    const bool https = url.rfind("https://", 0) == 0;
    if (!http && !https) return url.rfind("file://", 0) == 0;

    const size_t authority_start = url.find("://") + 3;
    const size_t authority_end = url.find_first_of("/?#", authority_start);
    const std::string authority = url.substr(
        authority_start, authority_end == std::string::npos ? std::string::npos : authority_end - authority_start);
    if (authority.empty() || authority.find('@') != std::string::npos) return false;

    std::string host;
    std::string service = http ? "80" : "443";
    if (authority.front() == '[') {
        const size_t close = authority.find(']');
        if (close == std::string::npos) return false;
        host = authority.substr(1, close - 1);
        if (close + 1 < authority.size()) {
            if (authority[close + 1] != ':') return false;
            service = authority.substr(close + 2);
        }
    } else {
        const size_t colon = authority.rfind(':');
        if (colon != std::string::npos) {
            host = authority.substr(0, colon);
            service = authority.substr(colon + 1);
        } else {
            host = authority;
        }
    }
    if (host.empty() || (service != "80" && service != "443")) return false;

    addrinfo hints{};
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_family = AF_UNSPEC;
    addrinfo* results = nullptr;
    if (getaddrinfo(host.c_str(), service.c_str(), &hints, &results) != 0 || !results) return false;

    bool has_address = false;
    bool public_only = true;
    for (addrinfo* it = results; it; it = it->ai_next) {
        if (!it->ai_addr) continue;
        has_address = true;
        if (it->ai_family == AF_INET) {
            const auto* sa = reinterpret_cast<const sockaddr_in*>(it->ai_addr);
            const uint32_t ip = ntohl(sa->sin_addr.s_addr);
            const bool private_v4 = (ip >> 24) == 0 || (ip >> 24) == 10 ||
                                    (ip >> 24) == 127 || (ip >> 16) == 0xA9FE ||
                                    (ip >> 20) == 0xAC1 || (ip >> 16) == 0xC0A8 ||
                                    (ip >> 28) >= 14;
            public_only = public_only && !private_v4;
        } else if (it->ai_family == AF_INET6) {
            const auto* sa = reinterpret_cast<const sockaddr_in6*>(it->ai_addr);
            const unsigned char* b = sa->sin6_addr.s6_addr;
            const bool loopback = IN6_IS_ADDR_LOOPBACK(&sa->sin6_addr);
            const bool local = IN6_IS_ADDR_LINKLOCAL(&sa->sin6_addr) ||
                               (b[0] >= 0xfc && b[0] <= 0xfd) ||
                               IN6_IS_ADDR_UNSPECIFIED(&sa->sin6_addr) ||
                               IN6_IS_ADDR_MULTICAST(&sa->sin6_addr);
            public_only = public_only && !loopback && !local;
        } else {
            public_only = false;
        }
    }
    freeaddrinfo(results);
    return has_address && public_only;
}

static std::string read_file_string(const std::string& path);

static pid_t runtime_pid(const std::string& path) {
    std::string text = read_file_string(path);
    while (!text.empty() && (text.back() == '\n' || text.back() == '\r')) text.pop_back();
    if (text.empty() || text.size() > 10) return -1;
    for (char c : text) if (c < '0' || c > '9') return -1;
    errno = 0;
    const long value = std::strtol(text.c_str(), nullptr, 10);
    return errno == 0 && value > 0 && value <= INT_MAX ? static_cast<pid_t>(value) : -1;
}

static bool run_argv_with_input(const std::vector<std::string>& args, const std::string& input, bool append_newline) {
    if (args.empty()) return false;
    int pipefd[2];
    if (pipe(pipefd) != 0) return false;
    std::vector<char*> argv;
    for (const auto& arg : args) argv.push_back(const_cast<char*>(arg.c_str()));
    argv.push_back(nullptr);
    pid_t pid = fork();
    if (pid == 0) {
        close(pipefd[1]);
        dup2(pipefd[0], STDIN_FILENO);
        close(pipefd[0]);
        execvp(argv[0], argv.data());
        _exit(127);
    }
    close(pipefd[0]);
    if (pid < 0) { close(pipefd[1]); return false; }
    std::string payload = append_newline ? input + "\n" : input;
    const char* data = payload.data();
    size_t remaining = payload.size();
    while (remaining > 0) {
        ssize_t written = write(pipefd[1], data, remaining);
        if (written <= 0) break;
        data += written;
        remaining -= static_cast<size_t>(written);
    }
    close(pipefd[1]);
    int status = 0;
    return waitpid(pid, &status, 0) == pid && WIFEXITED(status) && WEXITSTATUS(status) == 0;
}

static bool run_argv_with_stdin(const std::vector<std::string>& args, const std::string& input) {
    return run_argv_with_input(args, input, true);
}

static bool run_argv_with_raw_stdin(const std::vector<std::string>& args, const std::string& input) {
    return run_argv_with_input(args, input, false);
}

static bool run_argv_status(const std::vector<std::string>& args) {
    if (args.empty()) return false;
    std::vector<char*> argv;
    for (const auto& arg : args) argv.push_back(const_cast<char*>(arg.c_str()));
    argv.push_back(nullptr);
    pid_t pid = fork();
    if (pid == 0) {
        const int null_fd = open("/dev/null", O_RDWR | O_CLOEXEC);
        if (null_fd >= 0) {
            dup2(null_fd, STDOUT_FILENO); dup2(null_fd, STDERR_FILENO);
            if (null_fd > STDERR_FILENO) close(null_fd);
        }
        execvp(argv[0], argv.data());
        _exit(127);
    }
    if (pid < 0) return false;
    int status = 0;
    return waitpid(pid, &status, 0) == pid && WIFEXITED(status) && WEXITSTATUS(status) == 0;
}

static bool run_argv_status_env(const std::vector<std::string>& args,
                                const std::vector<std::pair<std::string, std::string>>& env) {
    if (args.empty()) return false;
    std::vector<char*> argv;
    for (const auto& arg : args) argv.push_back(const_cast<char*>(arg.c_str()));
    argv.push_back(nullptr);
    pid_t pid = fork();
    if (pid == 0) {
        const int null_fd = open("/dev/null", O_RDWR | O_CLOEXEC);
        if (null_fd >= 0) {
            dup2(null_fd, STDOUT_FILENO); dup2(null_fd, STDERR_FILENO);
            if (null_fd > STDERR_FILENO) close(null_fd);
        }
        for (const auto& [key, value] : env) (void)setenv(key.c_str(), value.c_str(), 1);
        execvp(argv[0], argv.data());
        _exit(127);
    }
    if (pid < 0) return false;
    int status = 0;
    return waitpid(pid, &status, 0) == pid && WIFEXITED(status) && WEXITSTATUS(status) == 0;
}


static pid_t spawn_argv_detached(const std::vector<std::string>& args) {
    if (args.empty()) return -1;
    pid_t pid = fork();
    if (pid < 0) return -1;
    if (pid == 0) {
        (void)setsid();
        const int null_fd = open("/dev/null", O_RDWR | O_CLOEXEC);
        if (null_fd >= 0) {
            dup2(null_fd, STDIN_FILENO); dup2(null_fd, STDOUT_FILENO); dup2(null_fd, STDERR_FILENO);
            if (null_fd > STDERR_FILENO) close(null_fd);
        }
        std::vector<char*> argv;
        for (const auto& arg : args) argv.push_back(const_cast<char*>(arg.c_str()));
        argv.push_back(nullptr);
        execvp(argv[0], argv.data());
        _exit(127);
    }
    return pid;
}

static void notify_user(const std::string& app, const std::string& title,
                        const std::string& body = {}, const std::string& icon = {},
                        const std::string& hint = {}, const std::string& urgency = {}) {
    std::vector<std::string> args = {"notify-send"};
    if (!app.empty()) { args.push_back("-a"); args.push_back(app); }
    if (!icon.empty()) { args.push_back("-i"); args.push_back(icon); }
    if (!urgency.empty()) { args.push_back("-u"); args.push_back(urgency); }
    if (!hint.empty()) { args.push_back("-h"); args.push_back(hint); }
    args.push_back(title);
    if (!body.empty()) args.push_back(body);
    (void)run_argv_status(args);
}

static std::string run_argv_capture(const std::vector<std::string>& args, const std::string& input = "") {
    if (args.empty()) return "";
    int out_pipe[2];
    if (pipe(out_pipe) != 0) return "";
    int in_pipe[2] = {-1, -1};
    if (!input.empty() && pipe(in_pipe) != 0) { close(out_pipe[0]); close(out_pipe[1]); return ""; }
    std::vector<char*> argv;
    for (const auto& arg : args) argv.push_back(const_cast<char*>(arg.c_str()));
    argv.push_back(nullptr);
    pid_t pid = fork();
    if (pid == 0) {
        dup2(out_pipe[1], STDOUT_FILENO);
        dup2(out_pipe[1], STDERR_FILENO);
        close(out_pipe[0]); close(out_pipe[1]);
        if (!input.empty()) { close(in_pipe[1]); dup2(in_pipe[0], STDIN_FILENO); close(in_pipe[0]); }
        execvp(argv[0], argv.data());
        _exit(127);
    }
    close(out_pipe[1]);
    if (pid < 0) { close(out_pipe[0]); if (in_pipe[0] >= 0) { close(in_pipe[0]); close(in_pipe[1]); } return ""; }
    if (!input.empty()) {
        close(in_pipe[0]);
        std::string payload = input + "\n";
        (void)write(in_pipe[1], payload.data(), payload.size());
        close(in_pipe[1]);
    }
    std::string output;
    std::array<char, 4096> buffer;
    ssize_t count;
    while ((count = read(out_pipe[0], buffer.data(), buffer.size())) > 0) output.append(buffer.data(), count);
    close(out_pipe[0]);
    int status = 0;
    waitpid(pid, &status, 0);
    return output;
}

static bool logind_call(const char* method, const char* signature = "", ...) {
    sd_bus* bus = nullptr;
    sd_bus_error error = SD_BUS_ERROR_NULL;
    sd_bus_message* reply = nullptr;
    if (sd_bus_open_system(&bus) < 0) return false;

    va_list ap;
    va_start(ap, signature);
    int r = sd_bus_call_methodv(bus, "org.freedesktop.login1", "/org/freedesktop/login1",
                                "org.freedesktop.login1.Manager", method, &error, &reply,
                                signature, ap);
    va_end(ap);
    sd_bus_error_free(&error);
    sd_bus_message_unref(reply);
    sd_bus_unref(bus);
    return r >= 0;
}

static bool logind_session_call(const char* method) {
    const char* session = std::getenv("XDG_SESSION_ID");
    if (!session || *session == '\0') return false;
    return logind_call(method, "s", session);
}

static std::string read_file_string(const std::string& path) {
    const int fd = open(path.c_str(), O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
    if (fd < 0) return "";
    struct stat st{};
    if (fstat(fd, &st) != 0 || !S_ISREG(st.st_mode) || st.st_size > 16 * 1024 * 1024) {
        close(fd);
        return "";
    }
    std::string result(static_cast<size_t>(st.st_size), '\0');
    size_t offset = 0;
    while (offset < result.size()) {
        const ssize_t n = read(fd, result.data() + offset, result.size() - offset);
        if (n <= 0) { close(fd); return ""; }
        offset += static_cast<size_t>(n);
    }
    close(fd);
    return result;
}

static bool write_private_file(const std::string& path, const std::string& contents) {
    const int fd = open(path.c_str(), O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC | O_NOFOLLOW, 0600);
    if (fd < 0) return false;
    if (fchmod(fd, 0600) != 0) { close(fd); return false; }
    size_t offset = 0;
    while (offset < contents.size()) {
        const ssize_t n = write(fd, contents.data() + offset, contents.size() - offset);
        if (n <= 0) { close(fd); return false; }
        offset += static_cast<size_t>(n);
    }
    const bool ok = fsync(fd) == 0;
    close(fd);
    return ok;
}

static bool write_fd_all(int fd, const std::string& contents) {
    size_t offset = 0;
    while (offset < contents.size()) {
        const ssize_t n = write(fd, contents.data() + offset, contents.size() - offset);
        if (n <= 0) return false;
        offset += static_cast<size_t>(n);
    }
    return true;
}

// ── Game Mode ────────────────────────────────────────────────────────────────
bool SystemControl::enable_game_mode() {
    SwayIPC ipc;
    if (ipc.connect()) {
        // "Adaptive Sync (VRR)" on the Game Mode page wrote
        // `gameModeAdaptiveSync` and nothing read it: VRR was switched on for
        // every game-mode session whatever the toggle said, which on a monitor
        // that reports support and flickers with it is exactly the setting
        // someone would go looking for.
        std::string cmd = "blur disable; shadows disable; corner_radius 0; default_border pixel 0";
        if (SettingsManager::get_json_bool("gameModeAdaptiveSync", false))
            cmd += "; output * adaptive_sync on";
        ipc.send_command(0, cmd);
    }

    (void)run_argv_status({"powerprofilesctl", "set", "performance"});
    (void)run_argv_status({"pw-metadata", "-n", "settings", "0", "clock.force-quantum", "256"});
    SettingsManager::set_json_value("notificationsDnd", "true");

    if (!write_private_file(runtime_path("game-mode.state"), "1\n")) return false;

    notify_user("Game Mode", "Game Mode Enabled", "Compositor effects disabled • Performance active", "input-gaming");
    return true;
}

bool SystemControl::disable_game_mode() {
    SwayIPC ipc;
    if (ipc.connect()) {
        // Restore what the user actually has, not the shipped defaults.
        //
        // This put back blur, shadows, a 10px corner radius and a 2px border
        // as literals, so a desktop with square corners and no blur got them
        // both back the first time game mode was switched off, and a border
        // width chosen in Settings was replaced by 2. Leaving game mode is not
        // an invitation to restyle the desktop.
        const DesktopSettings s = SettingsManager::load();
        std::string cmd =
            std::string("blur ") + (SettingsManager::get_json_bool("blurEnabled", true) ? "enable" : "disable")
            + "; shadows " + (SettingsManager::get_json_bool("shadowsEnabled", true) ? "enable" : "disable")
            + "; corner_radius " + std::to_string(SettingsManager::get_json_int("cornerRadius", 10))
            + "; default_border pixel " + std::to_string(s.borderWidth);
        if (SettingsManager::get_json_bool("gameModeAdaptiveSync", false))
            cmd += "; output * adaptive_sync off";
        ipc.send_command(0, cmd);
    }

    (void)run_argv_status({"powerprofilesctl", "set", "balanced"});
    (void)run_argv_status({"pw-metadata", "-n", "settings", "0", "clock.force-quantum", "0"});
    SettingsManager::set_json_value("notificationsDnd", "false");

    unlink(runtime_path("game-mode.state").c_str());

    notify_user("Game Mode", "Game Mode Disabled", "Standard desktop profile restored", "input-gaming");
    return true;
}

bool SystemControl::toggle_game_mode() {
    if (is_game_mode_active()) {
        return disable_game_mode();
    } else {
        return enable_game_mode();
    }
}

std::string SystemControl::get_game_mode_status_json() {
    return is_game_mode_active() ? "{\"enabled\":true}" : "{\"enabled\":false}";
}

// ── Session Control ──────────────────────────────────────────────────────────
bool SystemControl::run_quickshell_lock() {
    const std::string qs_lock = b1air::qml_entry("Lock.qml");
    if (qs_lock.empty()) {
        return false;
    }
    // "Dim screen on lock" on the Power page. The setting existed, the toggle
    // wrote it, and nothing read it: the backlight went down on every lock
    // whatever it said.
    const bool dim = SettingsManager::get_json_bool("dimOnLock", true);
    if (dim) ddc_dim();
    const int ret = run_argv_status({"quickshell", "-p", qs_lock}) ? 0 : 1;
    if (dim) ddc_undim();
    return (ret == 0);
}

bool SystemControl::lock_session_async() {
    // Called from more than one place that can legitimately overlap — a lid
    // bindswitch and swayidle's own `lock`/before-sleep hooks can all fire
    // within the same second of a lid close. Without this, each one spawns
    // its own Lock.qml, stacking duplicate lock screens on top of each other.
    if (!run_argv_capture({"pgrep", "-f", "quickshell -p .*Lock.qml"}).empty()) return true;

    (void)logind_session_call("LockSession");
    const std::string qs_lock = b1air::qml_entry("Lock.qml");
    if (qs_lock.empty()) return run_swaylock();

    // Double-fork so the daemon never has to wait on this: the immediate
    // child exits right away (reaped below) and the grandchild — the actual
    // quickshell process — is reparented to init, instead of sitting around
    // as a zombie under the daemon until something happens to reap it.
    pid_t pid = fork();
    if (pid == 0) {
        setsid();
        if (fork() == 0) {
            const int null_fd = open("/dev/null", O_RDWR | O_CLOEXEC);
            if (null_fd >= 0) {
                dup2(null_fd, STDIN_FILENO); dup2(null_fd, STDOUT_FILENO); dup2(null_fd, STDERR_FILENO);
                if (null_fd > STDERR_FILENO) close(null_fd);
            }
            execlp("quickshell", "quickshell", "-p", qs_lock.c_str(), static_cast<char*>(nullptr));
            _exit(127);
        }
        _exit(0);
    }
    if (pid > 0) waitpid(pid, nullptr, 0);
    return pid > 0;
}

bool SystemControl::run_swaylock() {
    if (!run_argv_capture({"pidof", "swaylock"}).empty()) return true;

    std::string help_text = exec_cmd_full("swaylock --help 2>&1");
    auto supports = [&](const std::string& flag) {
        return help_text.find(flag) != std::string::npos;
    };

    const char* home = std::getenv("HOME");
    std::string home_str = home ? home : "";
    std::string user_wp = home_str + "/.config/sway/wallpaper.jpg";
    std::string cache_wp = home_str + "/.cache/current_wallpaper.jpg";

    std::vector<std::string> args = {"swaylock", "--ignore-empty-password", "--color", "1a1b26", "--font", "JetBrainsMono Nerd Font"};

    if (access("/var/cache/wallpaper/current.jpg", R_OK) == 0) {
        args.insert(args.end(), {"--image", "/var/cache/wallpaper/current.jpg", "--scaling", "fill"});
    } else if (access(cache_wp.c_str(), R_OK) == 0) {
        args.insert(args.end(), {"--image", cache_wp, "--scaling", "fill"});
    } else if (access(user_wp.c_str(), R_OK) == 0) {
        args.insert(args.end(), {"--image", user_wp, "--scaling", "fill"});
    }

    auto add_flag = [&](const char* flag) { if (supports(flag)) args.emplace_back(flag); };
    auto add_pair = [&](const char* flag, const char* value) { if (supports(flag)) args.insert(args.end(), {flag, value}); };
    add_flag("--indicator-idle-visible"); add_pair("--indicator-radius", "85"); add_pair("--indicator-thickness", "6");
    add_pair("--ring-color", "7aa2f7"); add_pair("--inside-color", "16161ecc"); add_pair("--line-color", "00000000");
    add_pair("--separator-color", "00000000"); add_pair("--key-hl-color", "7aa2f7"); add_pair("--bs-hl-color", "f7768e");
    add_pair("--text-color", "c0caf5"); add_pair("--text-clear-color", "e0af68"); add_pair("--ring-ver-color", "9ece6a");
    add_pair("--inside-ver-color", "16161ecc"); add_pair("--text-ver-color", "9ece6a"); add_pair("--ring-wrong-color", "f7768e");
    add_pair("--inside-wrong-color", "16161ecc"); add_pair("--text-wrong-color", "f7768e"); add_flag("--show-keyboard-layout");
    add_pair("--layout-bg-color", "16161ecc"); add_pair("--layout-border-color", "7aa2f7"); add_pair("--layout-text-color", "c0caf5");
    add_flag("--screenshots");
    if (supports("--clock")) {
        args.emplace_back("--clock");
        add_pair("--timestr", "%H:%M"); add_pair("--datestr", "%A, %B %d, %Y");
    }
    add_pair("--effect-blur", "10x4"); add_pair("--effect-dim", "0.20"); add_pair("--effect-vignette", "0.25:0.25");
    add_pair("--grace", "1"); add_pair("--fade-in", "0.2");

    const bool dim = SettingsManager::get_json_bool("dimOnLock", true);
    if (dim) ddc_dim();
    const int ret = run_argv_status(args) ? 0 : 1;
    if (dim) ddc_undim();
    return (ret == 0);
}

bool SystemControl::lock_session(const std::string& mode) {
    // Tell logind first so inhibitors, lock state and suspend coordination use
    // the same session lifecycle as KDE/GNOME.
    (void)logind_session_call("LockSession");
    if (mode == "swaylock") {
        return run_swaylock();
    }
    if (mode == "quickshell") {
        if (run_quickshell_lock()) return true;
        return run_swaylock();
    }
    if (run_quickshell_lock()) return true;
    return run_swaylock();
}

bool SystemControl::logout_session() {
    if (logind_session_call("TerminateSession")) return true;
    SwayIPC ipc;
    return ipc.connect() && ipc.send_command(0, "exit").find("success") != std::string::npos;
}

bool SystemControl::suspend_system() {
    // lock_session() blocks until the screen is unlocked again — an idle
    // timeout calling this would never reach Suspend until someone typed
    // their password first, defeating the entire point of auto-suspend.
    lock_session_async();
    return logind_call("Suspend", "b", true);
}

bool SystemControl::reboot_system() {
    return logind_call("Reboot", "b", true);
}

bool SystemControl::shutdown_system() {
    return logind_call("PowerOff", "b", true);
}

// ── Power Profiles ───────────────────────────────────────────────────────────
std::string SystemControl::power_profile_get() {
    std::string out = exec_cmd("powerprofilesctl get 2>/dev/null");
    if (!out.empty()) return out;
    std::string gov = exec_cmd("cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null");
    if (gov == "performance") return "performance";
    if (gov == "powersave") return "power-saver";
    return "balanced";
}

bool SystemControl::power_profile_set(const std::string& profile) {
    if (profile != "performance" && profile != "power-saver" && profile != "balanced") return false;
    if (run_argv_status({"powerprofilesctl", "set", profile})) {
        return true;
    }
    std::string gov = (profile == "performance" ? "performance" : (profile == "power-saver" ? "powersave" : "schedutil"));
    bool changed = false;
    std::error_code ec;
    for (const auto& cpu : std::filesystem::directory_iterator("/sys/devices/system/cpu", ec)) {
        const std::string name = cpu.path().filename().string();
        if (name.rfind("cpu", 0) != 0 || name.size() <= 3 ||
            !std::all_of(name.begin() + 3, name.end(), [](char c) { return std::isdigit(static_cast<unsigned char>(c)); })) continue;
        const std::string governor = (cpu.path() / "cpufreq/scaling_governor").string();
        if (access(governor.c_str(), W_OK) == 0) changed = run_argv_with_stdin({"tee", governor}, gov) || changed;
        else if (run_argv_with_stdin({"sudo", "tee", governor}, gov)) changed = true;
    }
    return changed;
}

// ── Battery charge control ───────────────────────────────────────────────────
//
// What KDE's power applet calls a charge limit: the percentage the pack stops
// charging at, so a laptop that lives on mains does not sit at 100% and age.
// Plus charge_behaviour, which is the same idea from the other end — hold the
// charge where it is, or run the machine down off the battery on purpose.
//
// Both are sysfs files under each power supply, root-owned 0644 by default;
// etc/udev/rules.d/99-b1air-power.rules hands the `power` group write access
// so the settings page does not raise an authentication dialog per keystroke.

namespace {

/** Every battery node, in listing order: BAT0, BAT1, battery, … */
std::vector<std::filesystem::path> battery_nodes() {
    std::vector<std::filesystem::path> out;
    std::error_code ec;
    for (const auto& e : std::filesystem::directory_iterator("/sys/class/power_supply", ec)) {
        const std::string n = e.path().filename().string();
        if (n.rfind("BAT", 0) == 0 || n.rfind("battery", 0) == 0) out.push_back(e.path());
    }
    std::sort(out.begin(), out.end());
    return out;
}

std::string read_trimmed(const std::filesystem::path& p) {
    std::ifstream in(p);
    if (!in) return "";
    std::string s;
    std::getline(in, s);
    while (!s.empty() && (s.back() == '\n' || s.back() == ' ')) s.pop_back();
    return s;
}

/**
 * Write one sysfs attribute, escalating only if we have to.
 *
 * With the udev rule in place the direct write succeeds and nothing is
 * prompted. Without it — a machine installed before the rule, or one where
 * udev has not re-triggered — pkexec asks once rather than the setting simply
 * not working, which is how this would otherwise fail: silently, with the
 * slider snapping back on the next poll.
 */
bool write_sysfs(const std::filesystem::path& p, const std::string& value) {
    if (access(p.c_str(), W_OK) == 0) {
        std::ofstream out(p);
        if (out) { out << value; if (out.good()) return true; }
    }
    return run_argv_with_stdin({"pkexec", "tee", p.string()}, value);
}

} // namespace

/**
 * Every pack, its limit and its behaviour, as JSON for the settings page.
 *
 * `charge_behaviour` reads as a menu with the active entry in brackets —
 * "[auto] inhibit-charge force-discharge" — so the current value has to be
 * picked out of it rather than used as it stands.
 */
std::string SystemControl::battery_status_json() {
    nlohmann::json out = nlohmann::json::object();
    nlohmann::json packs = nlohmann::json::array();
    bool any_limit = false, any_behaviour = false;
    for (const auto& node : battery_nodes()) {
        nlohmann::json p = nlohmann::json::object();
        p["name"] = node.filename().string();

        const std::string end = read_trimmed(node / "charge_control_end_threshold");
        if (!end.empty()) {
            try { p["limit"] = std::stoi(end); any_limit = true; } catch (...) {}
            p["limitWritable"] = access((node / "charge_control_end_threshold").c_str(), W_OK) == 0;
        }
        const std::string start = read_trimmed(node / "charge_control_start_threshold");
        if (!start.empty()) { try { p["limitStart"] = std::stoi(start); } catch (...) {} }

        const std::string beh = read_trimmed(node / "charge_behaviour");
        if (!beh.empty()) {
            any_behaviour = true;
            nlohmann::json options = nlohmann::json::array();
            std::string active;
            std::stringstream ss(beh);
            std::string word;
            while (ss >> word) {
                if (word.size() > 2 && word.front() == '[' && word.back() == ']') {
                    active = word.substr(1, word.size() - 2);
                    options.push_back(active);
                } else {
                    options.push_back(word);
                }
            }
            p["behaviour"] = active;
            p["behaviourOptions"] = options;
            p["behaviourWritable"] = access((node / "charge_behaviour").c_str(), W_OK) == 0;
        }
        p["capacity"] = read_trimmed(node / "capacity");
        p["status"] = read_trimmed(node / "status");
        packs.push_back(p);
    }
    out["batteries"] = packs;
    out["hasLimit"] = any_limit;
    out["hasBehaviour"] = any_behaviour;
    return out.dump();
}

/** Set the charge limit on every pack. 100 is "no limit", not "off". */
bool SystemControl::battery_limit_set(int percent) {
    if (percent < 20 || percent > 100) return false;   // below 20 the pack may never charge
    bool any = false;
    for (const auto& node : battery_nodes()) {
        const auto endp = node / "charge_control_end_threshold";
        if (!std::filesystem::exists(endp)) continue;
        // The start threshold has to move first when it would otherwise sit
        // above the new end: the kernel rejects start >= end, and the write
        // would fail with nothing to say why.
        const auto startp = node / "charge_control_start_threshold";
        if (std::filesystem::exists(startp)) {
            const std::string cur = read_trimmed(startp);
            int start = 0;
            try { start = std::stoi(cur); } catch (...) {}
            if (start >= percent) (void)write_sysfs(startp, std::to_string(std::max(0, percent - 5)));
        }
        any = write_sysfs(endp, std::to_string(percent)) || any;
    }
    return any;
}

/** auto, inhibit-charge or force-discharge, on every pack that offers it. */
bool SystemControl::battery_behaviour_set(const std::string& behaviour) {
    if (behaviour != "auto" && behaviour != "inhibit-charge" && behaviour != "force-discharge")
        return false;
    bool any = false;
    for (const auto& node : battery_nodes()) {
        const auto p = node / "charge_behaviour";
        if (!std::filesystem::exists(p)) continue;
        any = write_sysfs(p, behaviour) || any;
    }
    return any;
}

// ── Caffeine / Idle Inhibitor (Stay Awake Mode) ──────────────────────────────
bool SystemControl::caffeine_is_active() {
    return (access(runtime_path("caffeine.state").c_str(), F_OK) == 0);
}

bool SystemControl::caffeine_set(bool active) {
    if (active) {
        int fd = open(runtime_path("caffeine.state").c_str(), O_CREAT | O_WRONLY | O_TRUNC, 0600);
        if (fd >= 0) close(fd);
        // The inhibitor is the feature. Announcing it without checking left a
        // machine promising to stay awake and going to sleep anyway.
        if (!run_argv_status({"swaymsg", "inhibit_idle", "focus"})) {
            unlink(runtime_path("caffeine.state").c_str());
            notify_user("b1air DE", "Could not keep the screen awake",
                        "The compositor refused the idle inhibitor.", "dialog-error");
            return false;
        }
        notify_user("b1air DE", "Caffeine Mode Active", "Screen sleep and idle lock disabled", "caffeine");
    } else {
        unlink(runtime_path("caffeine.state").c_str());
        (void)run_argv_status({"swaymsg", "inhibit_idle", "none"});
        notify_user("b1air DE", "Caffeine Mode Disabled", "Normal screen sleep restored", "caffeine");
    }
    return true;
}

bool SystemControl::caffeine_toggle() {
    bool current = caffeine_is_active();
    return caffeine_set(!current);
}

// ── Dynamic Applications Scanner (.desktop parser) ───────────────────────────
struct DesktopAppEntry {
    std::string name;
    std::string exec;
    std::string desktop_file;
    std::string icon;
    std::string comment;
    std::string categories;
    std::string mime_type;
    bool no_display = false;
    bool terminal = false;
    bool hidden = false;
    std::string try_exec;
    std::string only_show_in;
    std::string not_show_in;
};

// Desktop-entry visibility rules from the XDG spec that the scan used to skip.
//
// Only NoDisplay was honoured, so the launcher listed entries no desktop should
// show: Plasma's own tools (Discover, the Fcitx migration wizards) that name a
// desktop in OnlyShowIn, service browsers like the three Avahi ones, and
// entries whose program is not even installed. Filtering them here fixes it for
// every consumer at once rather than in each launcher.

/** Is `needle` one of the semicolon-separated names in `list`? */
static bool desktop_list_contains(const std::string& list, const std::string& needle) {
    size_t start = 0;
    while (start <= list.size()) {
        size_t end = list.find(';', start);
        if (end == std::string::npos) end = list.size();
        if (list.compare(start, end - start, needle) == 0) return true;
        if (end == list.size()) break;
        start = end + 1;
    }
    return false;
}

/**
 * OnlyShowIn / NotShowIn against this desktop's name.
 *
 * XDG_CURRENT_DESKTOP is a colon-separated preference list — the session sets
 * it to "b1air:sway" — and an entry is shown if any of those names matches.
 */
static bool desktop_entry_runs_here(const std::string& only_show_in,
                                    const std::string& not_show_in) {
    std::vector<std::string> names;
    const char* current = getenv("XDG_CURRENT_DESKTOP");
    std::string cur = current ? current : "";
    size_t start = 0;
    while (start <= cur.size() && !cur.empty()) {
        size_t end = cur.find(':', start);
        if (end == std::string::npos) end = cur.size();
        if (end > start) names.push_back(cur.substr(start, end - start));
        if (end == cur.size()) break;
        start = end + 1;
    }

    if (!not_show_in.empty()) {
        for (const auto& n : names)
            if (desktop_list_contains(not_show_in, n)) return false;
    }
    if (!only_show_in.empty()) {
        for (const auto& n : names)
            if (desktop_list_contains(only_show_in, n)) return true;
        return false;
    }
    return true;
}

/** TryExec names the program that must exist for the entry to be shown. */
static bool try_exec_present(const std::string& try_exec) {
    if (try_exec.empty()) return true;
    if (try_exec.front() == '/') return access(try_exec.c_str(), X_OK) == 0;

    const char* path = getenv("PATH");
    std::string p = path ? path : "/usr/local/bin:/usr/bin:/bin";
    size_t start = 0;
    while (start <= p.size()) {
        size_t end = p.find(':', start);
        if (end == std::string::npos) end = p.size();
        if (end > start) {
            std::string cand = p.substr(start, end - start) + "/" + try_exec;
            if (access(cand.c_str(), X_OK) == 0) return true;
        }
        if (end == p.size()) break;
        start = end + 1;
    }
    return false;
}

/**
 * The icon theme the desktop is actually configured to use.
 *
 * gtk-3.0/settings.ini and qt6ct.conf both name it, and this project ships
 * both saying Papirus-Dark. Read once: the answer does not change while the
 * session runs, and every desktop entry asks for it.
 */
static const std::string& configured_icon_theme() {
    static const std::string theme = [] () -> std::string {
        const char* home = std::getenv("HOME");
        if (!home) return "hicolor";
        const std::string h = home;
        const std::pair<std::string, std::string> sources[] = {
            { h + "/.config/gtk-3.0/settings.ini", "gtk-icon-theme-name" },
            { h + "/.config/gtk-4.0/settings.ini", "gtk-icon-theme-name" },
            { h + "/.config/qt6ct/qt6ct.conf",     "icon_theme" },
        };
        for (const auto& [path, key] : sources) {
            std::ifstream f(path);
            std::string line;
            while (std::getline(f, line)) {
                const size_t eq = line.find('=');
                if (eq == std::string::npos) continue;
                std::string k = line.substr(0, eq);
                k.erase(std::remove_if(k.begin(), k.end(), ::isspace), k.end());
                if (k != key) continue;
                std::string v = line.substr(eq + 1);
                while (!v.empty() && (v.front() == ' ' || v.front() == '"')) v.erase(v.begin());
                while (!v.empty() && (v.back() == ' ' || v.back() == '"' || v.back() == '\r')) v.pop_back();
                if (!v.empty()) return v;
            }
        }
        return "hicolor";
    }();
    return theme;
}

/**
 * An icon name from a desktop entry to a file on disk.
 *
 * This used to search five hard-coded directories — hicolor, one AdwaitaLegacy
 * folder and pixmaps — and never the icon theme the desktop is set to. This
 * project installs papirus-icon-theme and writes Papirus-Dark into both the
 * GTK and the Qt settings it ships, and Papirus was not among the paths, so
 * most entries resolved to nothing: b1air-notes, b1air-git and b1air-view all
 * came back with no icon and drew the "not found" placeholder in the window
 * switcher.
 *
 * Icon themes lay their files out as <theme>/<size>/<context>/<name>.<ext> or
 * <theme>/<context>/<size>/<name>.<ext> depending on the theme, so both are
 * tried, along with the theme's Inherits chain.
 */
static std::string resolve_desktop_icon(const std::string& icon) {
    if (icon.empty()) return {};
    if (icon.front() == '/') return icon;

    const char* home = std::getenv("HOME");
    const std::string h = home ? home : "";

    std::vector<std::string> theme_roots;
    for (const std::string& base : { h.empty() ? std::string() : h + "/.local/share/icons",
                                     std::string("/usr/share/icons") }) {
        if (base.empty()) continue;
        for (const std::string& theme : { configured_icon_theme(), std::string("hicolor") })
            theme_roots.push_back(base + "/" + theme);
    }

    const char* contexts[] = { "apps", "mimetypes", "categories", "devices", "places", "legacy" };
    const char* exts[] = { ".svg", ".png", ".xpm" };

    for (const auto& root : theme_roots) {
        std::error_code ec;
        if (!std::filesystem::is_directory(root, ec)) continue;

        // <theme>/<context>/<size>/name and <theme>/<size>/<context>/name both
        // occur in the wild; walking the theme's own top level covers each.
        for (const auto& entry : std::filesystem::directory_iterator(root, ec)) {
            if (!entry.is_directory()) continue;
            for (const char* ctx : contexts) {
                for (const char* ext : exts) {
                    const std::string a = entry.path().string() + "/" + ctx + "/" + icon + ext;
                    if (access(a.c_str(), R_OK) == 0) return a;
                }
            }
            // <theme>/apps/<size>/name
            for (const auto& sub : std::filesystem::directory_iterator(entry.path(), ec)) {
                if (!sub.is_directory()) continue;
                for (const char* ext : exts) {
                    const std::string b = sub.path().string() + "/" + icon + ext;
                    if (access(b.c_str(), R_OK) == 0) return b;
                }
            }
        }
    }

    // Themes exhausted: the places an icon can still be.
    std::vector<std::string> flat = {
        "/usr/share/icons/AdwaitaLegacy/48x48/legacy/",
        "/usr/share/pixmaps/"
    };
    if (!h.empty()) flat.push_back(h + "/.local/share/icons/");
    for (const auto& root : flat)
        for (const char* ext : exts) {
            const std::string candidate = root + icon + ext;
            if (access(candidate.c_str(), R_OK) == 0) return candidate;
        }
    return {};
}

static std::string s_apps_cache_category;
static std::string s_apps_cache_json;
static std::chrono::steady_clock::time_point s_apps_cache_time;

std::string SystemControl::apps_list_json(const std::string& category) {
    auto now = std::chrono::steady_clock::now();
    if (!s_apps_cache_json.empty() && category == s_apps_cache_category &&
        std::chrono::duration_cast<std::chrono::seconds>(now - s_apps_cache_time).count() < 30) {
        return s_apps_cache_json;
    }

    std::vector<std::string> search_dirs = {
        "/usr/share/applications",
        "/var/lib/flatpak/exports/share/applications"
    };
    const char* home = std::getenv("HOME");
    if (home) {
        search_dirs.push_back(std::string(home) + "/.local/share/applications");
    }

    std::unordered_map<std::string, DesktopAppEntry> apps;

    for (const auto& dir_path : search_dirs) {
        DIR* d = opendir(dir_path.c_str());
        if (!d) continue;
        struct dirent* ent;
        while ((ent = readdir(d)) != nullptr) {
            std::string fname = ent->d_name;
            if (fname.size() > 8 && fname.substr(fname.size() - 8) == ".desktop") {
                if (apps.count(fname)) continue;

                std::ifstream f(dir_path + "/" + fname);
                if (!f) continue;
                std::string line;
                DesktopAppEntry entry;
                entry.desktop_file = fname;
                bool in_desktop_entry = false;

                while (std::getline(f, line)) {
                    if (line == "[Desktop Entry]") {
                        in_desktop_entry = true;
                        continue;
                    } else if (!line.empty() && line[0] == '[' && in_desktop_entry) {
                        break;
                    }
                    if (!in_desktop_entry) continue;

                    size_t eq = line.find('=');
                    if (eq != std::string::npos) {
                        std::string key = line.substr(0, eq);
                        std::string val = line.substr(eq + 1);

                        if (key == "Name" && entry.name.empty()) entry.name = val;
                        else if (key == "Exec" && entry.exec.empty()) {
                            size_t p;
                            while ((p = val.find("%")) != std::string::npos && p + 1 < val.size()) {
                                val.erase(p, 2);
                            }
                            while (!val.empty() && val.back() == ' ') val.pop_back();
                            entry.exec = val;
                        }
                        else if (key == "Icon" && entry.icon.empty()) entry.icon = val;
                        else if (key == "Comment" && entry.comment.empty()) entry.comment = val;
                        else if (key == "Categories") entry.categories = val;
                        else if (key == "MimeType") entry.mime_type = val;
                        else if (key == "NoDisplay") entry.no_display = (val == "true" || val == "1");
                        else if (key == "Terminal") entry.terminal = (val == "true" || val == "1");
                        else if (key == "Hidden") entry.hidden = (val == "true" || val == "1");
                        else if (key == "TryExec" && entry.try_exec.empty()) entry.try_exec = val;
                        else if (key == "OnlyShowIn") entry.only_show_in = val;
                        else if (key == "NotShowIn") entry.not_show_in = val;
                    }
                }

                if (!entry.name.empty() && !entry.exec.empty()
                        && !entry.no_display && !entry.hidden
                        && desktop_entry_runs_here(entry.only_show_in, entry.not_show_in)
                        && try_exec_present(entry.try_exec)) {
                    apps[fname] = entry;
                }
            }
        }
        closedir(d);
    }

    std::vector<DesktopAppEntry> matched;
    std::string cat_low = category;
    std::transform(cat_low.begin(), cat_low.end(), cat_low.begin(), ::tolower);

    for (const auto& [_, app] : apps) {
        std::string n_low = app.name;
        std::string e_low = app.exec;
        std::string c_low = app.categories;
        std::string m_low = app.mime_type;
        std::transform(n_low.begin(), n_low.end(), n_low.begin(), ::tolower);
        std::transform(e_low.begin(), e_low.end(), e_low.begin(), ::tolower);
        std::transform(c_low.begin(), c_low.end(), c_low.begin(), ::tolower);
        std::transform(m_low.begin(), m_low.end(), m_low.begin(), ::tolower);

        bool match = false;
        if (cat_low == "all") {
            match = true;
        } else if (cat_low == "browser" || cat_low == "web-browser") {
            match = (c_low.find("webbrowser") != std::string::npos || m_low.find("text/html") != std::string::npos ||
                     e_low.find("firefox") != std::string::npos || e_low.find("chrome") != std::string::npos ||
                     e_low.find("chromium") != std::string::npos || e_low.find("brave") != std::string::npos ||
                     e_low.find("zen") != std::string::npos || e_low.find("vivaldi") != std::string::npos ||
                     e_low.find("opera") != std::string::npos || e_low.find("librewolf") != std::string::npos ||
                     e_low.find("floorp") != std::string::npos || e_low.find("qutebrowser") != std::string::npos);
        } else if (cat_low == "terminal") {
            match = (c_low.find("terminalemulator") != std::string::npos ||
                     e_low.find("b1air-term") != std::string::npos || e_low.find("foot") != std::string::npos ||
                     e_low.find("alacritty") != std::string::npos || e_low.find("ghostty") != std::string::npos ||
                     e_low.find("wezterm") != std::string::npos || e_low.find("konsole") != std::string::npos ||
                     e_low.find("xterm") != std::string::npos || e_low.find("blackbox") != std::string::npos);
        } else if (cat_low == "filemanager" || cat_low == "file-manager") {
            match = (c_low.find("filemanager") != std::string::npos || m_low.find("inode/directory") != std::string::npos ||
                     e_low.find("thunar") != std::string::npos || e_low.find("nautilus") != std::string::npos ||
                     e_low.find("dolphin") != std::string::npos || e_low.find("nemo") != std::string::npos ||
                     e_low.find("pcmanfm") != std::string::npos || e_low.find("yazi") != std::string::npos ||
                     e_low.find("ranger") != std::string::npos);
        } else if (cat_low == "editor" || cat_low == "text-editor") {
            match = (c_low.find("texteditor") != std::string::npos || c_low.find("ide") != std::string::npos ||
                     e_low.find("code") != std::string::npos || e_low.find("cursor") != std::string::npos ||
                     e_low.find("nvim") != std::string::npos || e_low.find("zed") != std::string::npos ||
                     e_low.find("sublime") != std::string::npos || e_low.find("kate") != std::string::npos ||
                     e_low.find("gedit") != std::string::npos || e_low.find("micro") != std::string::npos ||
                     e_low.find("helix") != std::string::npos);
        } else if (cat_low == "player" || cat_low == "media-player" || cat_low == "media") {
            match = (c_low.find("audiovideo") != std::string::npos || c_low.find("player") != std::string::npos ||
                     e_low.find("mpv") != std::string::npos || e_low.find("vlc") != std::string::npos ||
                     e_low.find("spotify") != std::string::npos || e_low.find("celluloid") != std::string::npos);
        } else if (cat_low == "image" || cat_low == "image-viewer") {
            match = (c_low.find("viewer") != std::string::npos || c_low.find("rastergraphics") != std::string::npos ||
                     e_low.find("imv") != std::string::npos || e_low.find("loupe") != std::string::npos ||
                     e_low.find("eog") != std::string::npos || e_low.find("gwenview") != std::string::npos ||
                     e_low.find("ristretto") != std::string::npos);
        }

        if (match) {
            matched.push_back(app);
        }
    }

    std::sort(matched.begin(), matched.end(), [](const DesktopAppEntry& a, const DesktopAppEntry& b) {
        return a.name < b.name;
    });

    std::string res = "[";
    for (size_t i = 0; i < matched.size(); ++i) {
        const auto& a = matched[i];
        std::string item = "{\"name\":\"" + json_escape(a.name) + "\","
                           "\"exec\":\"" + json_escape(a.exec) + "\","
                           "\"desktopFile\":\"" + json_escape(a.desktop_file) + "\","
                           "\"icon\":\"" + json_escape(a.icon) + "\","
                           "\"iconPath\":\"" + json_escape(resolve_desktop_icon(a.icon)) + "\","
                           "\"comment\":\"" + json_escape(a.comment) + "\","
                           // Terminal=true was parsed and then dropped on the floor.
                           // Launchers executed such an entry directly, so htop and
                           // btop++ started without a terminal and died immediately —
                           // clicking them did nothing at all. Reported so a launcher
                           // can open them the way they need.
                           "\"terminal\":" + std::string(a.terminal ? "true" : "false") + ","
                           "\"category\":\"" + json_escape(a.categories) + "\"}";
        res += item;
        if (i + 1 < matched.size()) res += ",";
    }
    res += "]";
    s_apps_cache_category = category;
    s_apps_cache_json = res;
    s_apps_cache_time = now;
    return res;
}

// ── Color Dropper / Pixel Picker ─────────────────────────────────────────────
std::string SystemControl::pick_color() {
    std::string pos = exec_cmd("slurp -p 2>/dev/null");
    if (pos.empty()) return "";
    while (!pos.empty() && (pos.back() == '\n' || pos.back() == '\r' || pos.back() == ' ')) pos.pop_back();
    if (!valid_geometry(pos)) return "";

    std::string hex = exec_cmd("grim -g \"" + pos + " 1x1\" -t ppm - 2>/dev/null | convert - -format '%[pixel:p{0,0}]' info: 2>/dev/null");
    
    if (hex.empty() || hex[0] != '#') {
        hex = exec_cmd("grim -g \"" + pos + " 1x1\" -t ppm - 2>/dev/null | tail -c 3 | xxd -p | sed 's/^/#/' 2>/dev/null");
    }

    if (!hex.empty()) {
        while (!hex.empty() && (hex.back() == '\n' || hex.back() == '\r' || hex.back() == ' ')) hex.pop_back();
        if (hex.size() != 7 || hex[0] != '#' ||
            !std::all_of(hex.begin() + 1, hex.end(), [](unsigned char c) { return std::isxdigit(c); })) return "";
        (void)run_argv_with_stdin({"wl-copy"}, hex);
        (void)run_argv_status({"notify-send", "-a", "b1air DE", "-i", "color-picker",
                                "Color Picked", hex + " copied to clipboard"});
        return hex;
    }
    return "";
}

// ── Window Minimization & Window Switcher ────────────────────────────────────
bool SystemControl::window_minimize() {
    SwayIPC ipc;
    if (!ipc.connect()) return false;
    std::string resp = ipc.send_command(0, "mark --add _b1air_minimized; move scratchpad");
    return (resp.find("\"success\":true") != std::string::npos || resp.find("\"success\": true") != std::string::npos);
}

bool SystemControl::window_restore(int64_t con_id) {
    SwayIPC ipc;
    if (!ipc.connect()) return false;
    std::string cmd;
    if (con_id > 0) {
        cmd = "[con_id=" + std::to_string(con_id) + "] scratchpad show; [con_id=" + std::to_string(con_id) + "] focus; [con_id=" + std::to_string(con_id) + "] mark --toggle _b1air_minimized";
    } else {
        cmd = "[con_mark=\"_b1air_minimized\"] scratchpad show; [con_mark=\"_b1air_minimized\"] focus; [con_mark=\"_b1air_minimized\"] mark --toggle _b1air_minimized";
    }
    std::string resp = ipc.send_command(0, cmd);
    return (resp.find("\"success\":true") != std::string::npos || resp.find("\"success\": true") != std::string::npos);
}

bool SystemControl::window_toggle_minimize() {
    return window_minimize();
}

int SystemControl::window_count_minimized() {
    SwayIPC ipc;
    if (!ipc.connect()) return 0;
    std::string tree = ipc.send_command(4, "");
    int count = 0;
    size_t pos = 0;
    while ((pos = tree.find("\"_b1air_minimized\"", pos)) != std::string::npos) {
        count++;
        pos += 18;
    }
    return count;
}

namespace {

/**
 * Depth-first walk over a sway tree.
 *
 * The two functions below used to pick the tree apart with substring searches
 * — find("{\"id\":"), find("\"app_id\":\""), find("\"focused\":true") — and
 * sway pretty-prints its IPC replies. The text is `{\n    "id": 3` and
 * `"focused": true`, with spaces, so none of those patterns matched anything
 * on any machine and both lists came back empty every time. Measured against a
 * live tree:
 *
 *   swaymsg -r -t get_tree | grep -c '"app_id":"'    -> 0
 *   swaymsg -r -t get_tree | grep -c '"focused":true' -> 0
 *
 * Walking the parsed tree costs one parse of a document the daemon already has
 * in hand, and whitespace cannot break it again.
 */
void walk_tree(const nlohmann::json& node,
               const std::function<void(const nlohmann::json&)>& visit) {
    visit(node);
    for (const char* key : {"nodes", "floating_nodes"}) {
        if (!node.contains(key) || !node[key].is_array()) continue;
        for (const auto& child : node[key]) walk_tree(child, visit);
    }
}

/**
 * A string field, treating JSON null as absent.
 *
 * nlohmann's value() throws type_error when the key is present but holds the
 * wrong type, and sway sends "name": null for a container that has no title —
 * which threw out of the whole listing rather than skipping one node.
 */
std::string json_str(const nlohmann::json& n, const char* key, const std::string& def) {
    if (!n.contains(key) || !n[key].is_string()) return def;
    return n[key].get<std::string>();
}

/**
 * Width and height of the focused output, falling back to the first one.
 *
 * PiP and the zone snapper each took the first "rect": in the outputs reply and
 * read the numbers after it, which happens to work on a single monitor and
 * places the window on the wrong screen on any other. Both wanted the display
 * the user is actually looking at.
 */
void focused_output_size(const std::string& outputs_json, int& w, int& h) {
    w = 1920;
    h = 1080;
    try {
        const auto outputs = nlohmann::json::parse(outputs_json);
        const nlohmann::json* chosen = nullptr;
        for (const auto& o : outputs) {
            if (!o.contains("rect")) continue;
            if (!chosen) chosen = &o;
            if (o.value("focused", false)) { chosen = &o; break; }
        }
        if (chosen) {
            const auto& r = (*chosen)["rect"];
            w = r.value("width", w);
            h = r.value("height", h);
        }
    } catch (const std::exception&) {
        // Keep the 1920x1080 assumption rather than placing nothing.
    }
}

/** A window someone can see, as opposed to a workspace or a split container. */
bool is_window(const nlohmann::json& n) {
    const std::string type = json_str(n, "type", "");
    if (type != "con" && type != "floating_con") return false;
    // Present *and not null*. sway sends "app_id": null and "window": null on
    // split containers too, so testing for the key alone counted every split
    // as a window: "float the whole workspace" floated a split with two
    // windows in it as one block, and left those two tiled inside it.
    const auto has = [&](const char* k, bool (nlohmann::json::*ok)() const noexcept) {
        auto it = n.find(k);
        return it != n.end() && ((*it).*ok)();
    };
    return has("app_id", &nlohmann::json::is_string)
        || has("window_properties", &nlohmann::json::is_object)
        || has("window", &nlohmann::json::is_number);
}

/** app_id, falling back to the X11 class for an XWayland window. */
std::string node_app_id(const nlohmann::json& n) {
    if (n.contains("app_id") && n["app_id"].is_string()) return n["app_id"].get<std::string>();
    if (n.contains("window_properties") && n["window_properties"].is_object()) {
        const auto& wp = n["window_properties"];
        if (wp.contains("class") && wp["class"].is_string()) return wp["class"].get<std::string>();
    }
    return "application";
}

} // namespace

std::string SystemControl::window_list_minimized_json() {
    SwayIPC ipc;
    if (!ipc.connect()) return "[]";

    nlohmann::json tree;
    try { tree = nlohmann::json::parse(ipc.send_command(4, "")); }
    catch (const std::exception&) { return "[]"; }

    std::vector<std::string> items;
    walk_tree(tree, [&](const nlohmann::json& n) {
        if (!is_window(n)) return;
        if (!n.contains("marks") || !n["marks"].is_array()) return;

        bool minimized = false;
        for (const auto& mark : n["marks"])
            if (mark.is_string() && mark.get<std::string>().find("_b1air_minimized") != std::string::npos)
                minimized = true;
        if (!minimized) return;

        const int64_t id = n.value("id", static_cast<int64_t>(0));
        if (id <= 0) return;
        items.push_back("{\"id\":" + std::to_string(id)
                        + ",\"name\":\"" + json_escape(json_str(n, "name", "Window"))
                        + "\",\"app_id\":\"" + json_escape(node_app_id(n)) + "\"}");
    });

    std::string res = "[";
    for (size_t i = 0; i < items.size(); ++i) {
        res += items[i];
        if (i + 1 < items.size()) res += ",";
    }
    res += "]";
    return res;
}

std::string SystemControl::window_list_open_json() {
    SwayIPC ipc;
    if (!ipc.connect()) return "[]";

    nlohmann::json tree;
    try { tree = nlohmann::json::parse(ipc.send_command(4, "")); }
    catch (const std::exception&) { return "[]"; }

    std::vector<std::string> items;
    walk_tree(tree, [&](const nlohmann::json& n) {
        if (!is_window(n)) return;

        const int64_t id = n.value("id", static_cast<int64_t>(0));
        const std::string name = json_str(n, "name", "");
        const std::string app_id = node_app_id(n);
        if (id <= 0 || name.empty() || name == "null") return;
        // The shell's own surfaces are not windows anyone wants to switch to.
        if (app_id == "quickshell" || app_id == "waybar") return;

        items.push_back("{\"id\":" + std::to_string(id)
                        + ",\"name\":\"" + json_escape(name)
                        + "\",\"app_id\":\"" + json_escape(app_id)
                        + "\",\"focused\":" + (n.value("focused", false) ? "true" : "false") + "}");
    });

    std::string res = "[";
    for (size_t i = 0; i < items.size(); ++i) {
        res += items[i];
        if (i + 1 < items.size()) res += ",";
    }
    res += "]";
    return res;
}

// ── Other applications' colours ──────────────────────────────────────────────
//
// The shell and our own apps follow the theme picker; nothing else did. The
// session set `gtk-theme Tokyonight-Dark`, a theme that is not installed, and
// the shipped settings.ini names adw-gtk3-dark, also not installed — so GTK
// apps drew stock Adwaita, dark only because of prefer-dark. Qt apps used
// Kvantum's Tokyo-Night, fixed. Changing the theme changed none of them.
//
// This makes them follow: GTK through Adwaita (built into GTK, always there)
// plus @define-color overrides in gtk.css; Qt through a Kvantum theme
// generated from the palette. `appColorScheme` can pin them dark or light
// instead; when that disagrees with the palette, they get the stock dark or
// light look with only the accent carried over, since a dark palette cannot
// be used as a light one.
namespace {

double channel(int v) {
    const double c = v / 255.0;
    return c <= 0.03928 ? c / 12.92 : std::pow((c + 0.055) / 1.055, 2.4);
}

double luminance(const std::string& hex) {
    if (hex.size() < 7 || hex[0] != '#') return 0.0;
    try {
        const int r = std::stoi(hex.substr(1, 2), nullptr, 16);
        const int g = std::stoi(hex.substr(3, 2), nullptr, 16);
        const int b = std::stoi(hex.substr(5, 2), nullptr, 16);
        return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b);
    } catch (...) { return 0.0; }
}

// Replace (or add) `key=value` lines under [Settings] in a GTK settings.ini.
void set_ini_keys(const std::string& path, const std::vector<std::pair<std::string, std::string>>& kv) {
    std::ifstream in(path);
    std::vector<std::string> lines;
    std::string line;
    while (std::getline(in, line)) lines.push_back(line);
    if (lines.empty()) lines.push_back("[Settings]");
    for (const auto& [k, v] : kv) {
        bool done = false;
        for (auto& l : lines)
            if (l.rfind(k + "=", 0) == 0) { l = k + "=" + v; done = true; }
        if (!done) lines.push_back(k + "=" + v);
    }
    std::filesystem::create_directories(std::filesystem::path(path).parent_path());
    std::ofstream out(path);
    for (const auto& l : lines) out << l << "\n";
}

/**
 * Write a file that may not be writable, without creating its directory.
 *
 * write_file() below calls create_directories() and std::rename, both of which
 * throw or leave a stray .tmp behind when the target is a root-owned directory
 * we only have group access to. /var/cache/wallpaper is exactly that: mode
 * 2775 root:wallpaper, with this user and sddm both in the group. A machine
 * where the group was never set up must lose the palette silently, not fail
 * the whole appearance apply.
 */
bool write_file_best_effort(const std::string& path, const std::string& text) {
    std::ofstream out(path, std::ios::trunc);
    if (!out) return false;
    out << text;
    return out.good();
}

void write_file(const std::string& path, const std::string& text) {
    std::filesystem::create_directories(std::filesystem::path(path).parent_path());
    const std::string tmp = path + ".tmp";
    { std::ofstream out(tmp); out << text; }
    std::rename(tmp.c_str(), path.c_str());
}

} // namespace

bool SystemControl::appearance_apply() {
    const char* home_env = std::getenv("HOME");
    const std::string home = home_env ? home_env : "";

    // The live palette, as Services/Theme publishes it.
    nlohmann::json pal = nlohmann::json::object();
    {
        std::ifstream in(home + "/.config/b1air/theme.json");
        if (in) { try { in >> pal; } catch (...) { pal = nlohmann::json::object(); } }
    }
    auto c = [&](const char* key, const char* fallback) {
        return json_str(pal, key, fallback);
    };
    const std::string ground = c("ground", "#1a1b26");
    const std::string accent = c("primary", c("blue", "#7aa2f7").c_str());
    const std::string accentText = c("primaryText", "#16161e");

    const bool paletteDark = luminance(ground) < 0.4;
    std::string scheme = SettingsManager::get_json_string("appColorScheme");
    if (scheme != "dark" && scheme != "light") scheme = "auto";
    const bool dark = scheme == "dark" || (scheme == "auto" && paletteDark);
    const bool usePalette = dark == paletteDark;

    // GTK: the stock theme, dark or light, and the portal's colour scheme —
    // which is what browsers, Electron and libadwaita apps read.
    (void)run_argv_status({"gsettings", "set", "org.gnome.desktop.interface", "color-scheme",
                           dark ? "prefer-dark" : "prefer-light"});
    (void)run_argv_status({"gsettings", "set", "org.gnome.desktop.interface", "gtk-theme",
                           dark ? "Adwaita-dark" : "Adwaita"});
    (void)run_argv_status({"gsettings", "set", "org.gnome.desktop.interface", "icon-theme",
                           dark ? "Papirus-Dark" : "Papirus"});
    // The desktop's own cursor (src/cursors). gsettings is what GTK 4 and
    // libadwaita apps read; sway takes it from input.conf.
    (void)run_argv_status({"gsettings", "set", "org.gnome.desktop.interface", "cursor-theme", "b1air-cursors"});
    for (const char* dir : {"/.config/gtk-3.0/settings.ini", "/.config/gtk-4.0/settings.ini"}) {
        set_ini_keys(home + dir, {{"gtk-theme-name", dark ? "Adwaita-dark" : "Adwaita"},
                                  {"gtk-icon-theme-name", dark ? "Papirus-Dark" : "Papirus"},
                                  {"gtk-application-prefer-dark-theme", dark ? "1" : "0"},
                                  {"gtk-cursor-theme-name", "b1air-cursors"}});
    }

    std::string css =
        "/* Generated by b1air (b1air-daemon appearance apply) from the active\n"
        " * theme; rewritten whenever the theme or Settings -> Appearance ->\n"
        " * Other applications changes, so edits here do not survive. */\n\n";
    auto def = [&](const std::string& name, const std::string& value) {
        css += "@define-color " + name + " " + value + ";\n";
    };
    def("accent_color", accent);
    def("accent_bg_color", accent);
    def("accent_fg_color", accentText);
    def("theme_selected_bg_color", accent);
    def("theme_selected_fg_color", accentText);
    if (usePalette) {
        const std::string low = c("low", ground.c_str()), lowest = c("lowest", ground.c_str());
        const std::string mid = c("mid", low.c_str()), high = c("high", mid.c_str());
        const std::string text = c("text", "#c0caf5"), dim = c("textDim", text.c_str());
        const std::string outline = c("outlineVariant", high.c_str());
        def("window_bg_color", ground);   def("window_fg_color", text);
        def("view_bg_color", lowest);     def("view_fg_color", text);
        def("headerbar_bg_color", low);   def("headerbar_fg_color", text);
        def("headerbar_backdrop_color", ground);
        def("sidebar_bg_color", low);     def("sidebar_fg_color", text);
        def("card_bg_color", mid);        def("card_fg_color", text);
        def("popover_bg_color", low);     def("popover_fg_color", text);
        def("dialog_bg_color", ground);   def("dialog_fg_color", text);
        def("destructive_bg_color", c("red", "#f7768e"));
        def("theme_bg_color", ground);    def("theme_fg_color", text);
        def("theme_base_color", lowest);  def("theme_text_color", text);
        def("theme_unfocused_bg_color", ground); def("theme_unfocused_fg_color", dim);
        def("insensitive_fg_color", dim); def("borders", outline);
    }
    write_file(home + "/.config/gtk-3.0/gtk.css", css);
    write_file(home + "/.config/gtk-4.0/gtk.css", css);

    // Window borders from the palette: written for the next start, and sent to
    // the running sway so they change now. look-and-feel.conf had them fixed.
    {
        const std::string text = c("text", "#c0caf5");
        const std::string dim = c("textDim", "#a9b1d6");
        const std::string low = c("lowest", "#16161e");
        const std::string alt = c("tertiary", "#bb9af7");
        const std::string err = c("error", "#f7768e");
        const std::vector<std::vector<std::string>> rules = {
            {"client.focused", accent, ground, text, alt, accent},
            {"client.focused_inactive", low, low, dim, low, low},
            {"client.unfocused", low, low, dim, low, low},
            {"client.urgent", err, ground, text, err, err},
        };
        std::string conf = "# Generated by b1air-daemon (appearance apply) from the theme.\n";
        for (const auto& r : rules) {
            std::string line;
            for (const auto& part : r) line += (line.empty() ? "" : " ") + part;
            conf += line + "\n";
            std::vector<std::string> argv{"swaymsg"};
            argv.insert(argv.end(), r.begin(), r.end());
            (void)run_argv_status(argv);
        }
        write_file(home + "/.config/sway/conf.d/custom_theme_colors.conf", conf);
    }

    // Qt, through Kvantum (qt6ct is set to style=kvantum).
    std::string kvTheme = dark ? "KvGnomeDark" : "KvGnome";
    if (usePalette) {
        kvTheme = "b1air";
        const std::string low = c("low", ground.c_str()), lowest = c("lowest", ground.c_str());
        const std::string mid = c("mid", low.c_str()), high = c("high", mid.c_str());
        const std::string highest = c("highest", high.c_str()), text = c("text", "#c0caf5");
        const std::string outline = c("outline", c("textDim", text.c_str()).c_str());
        // The shipped Tokyo-Night.kvconfig is the template: its widget
        // settings stay, and only [GeneralColors] is written from the palette.
        std::string base;
        {
            std::ifstream in(home + "/.config/Kvantum/Tokyo-Night/Tokyo-Night.kvconfig");
            std::stringstream ss; ss << in.rdbuf(); base = ss.str();
        }
        const std::string colors =
            "[GeneralColors]\n"
            "window.color=" + low + "\nbase.color=" + lowest + "\nalt.base.color=" + ground + "\n"
            "button.color=" + mid + "\nlight.color=" + highest + "\nmid.light.color=" + high + "\n"
            "dark.color=" + lowest + "\nmid.color=" + high + "\n"
            "highlight.color=" + accent + "\ninactive.highlight.color=" + accent + "\n"
            "text.color=" + text + "\nwindow.text.color=" + text + "\nbutton.text.color=" + text + "\n"
            "disabled.text.color=" + outline + "\ntooltip.text.color=" + text + "\n"
            "highlight.text.color=" + accentText + "\n"
            "link.color=" + c("sapphire", accent.c_str()) + "\nlink.visited.color=" + c("mauve", accent.c_str()) + "\n\n";
        std::string out;
        const size_t gc = base.find("[GeneralColors]");
        if (gc == std::string::npos) {
            out = "[%General]\nauthor=b1air\n\n" + colors + base;
        } else {
            const size_t next = base.find("\n[", gc + 1);
            out = base.substr(0, gc) + colors + (next == std::string::npos ? "" : base.substr(next + 1));
        }
        write_file(home + "/.config/Kvantum/b1air/b1air.kvconfig", out);
    }
    set_ini_keys(home + "/.config/Kvantum/kvantum.kvconfig", {{"theme", kvTheme}});
    // set_ini_keys puts a missing key under whatever section is last; the
    // file has a single [General] section, so that is the right one.

    // The login screen, which runs as another user entirely.
    //
    // The SDDM theme's colours were the same Tokyo Night hex values as the
    // shell's, written out by hand in its default.conf — identical by
    // coincidence and only until the theme was changed once, after which the
    // desktop was one colour and the screen you log in through was another.
    //
    // sddm cannot read ~/.config/b1air/theme.json: it runs as the sddm user
    // and $HOME is not readable to it. /var/cache/wallpaper already exists for
    // exactly this problem — it is how the login background is shared — and
    // sddm is a member of its group, so the palette goes beside the wallpaper.
    //
    // As QML rather than JSON, because the greeter can load a QML file with
    // Qt.createComponent() and cannot read one with XMLHttpRequest unless
    // QML_XHR_ALLOW_FILE_READ is set in sddm's own service environment. A
    // generated file avoids needing that at all.
    {
        std::string qml =
            "// Generated by b1air-daemon (appearance apply). Edits are lost.\n"
            "// The active desktop palette, for the SDDM theme: see\n"
            "// usr/share/sddm/themes/b1air/components/Palette.qml.\n"
            "import QtQuick\n\nQtObject {\n";
        for (const char* key : {"ground", "lowest", "low", "mid", "high", "highest",
                                "text", "textDim", "outline", "outlineVariant",
                                "primary", "primaryText", "primaryBox", "tertiary",
                                "error", "errorText", "yellow", "green", "sapphire"}) {
            if (!pal.contains(key) || !pal[key].is_string()) continue;
            qml += std::string("    readonly property color ") + key + ": \""
                 + pal[key].get<std::string>() + "\"\n";
        }
        // The scheme the rest of this function resolved, so the greeter shows
        // the same light or dark face the session does.
        qml += std::string("    readonly property bool dark: ") + (dark ? "true" : "false") + "\n}\n";
        (void)write_file_best_effort("/var/cache/wallpaper/Palette.qml", qml);
    }
    return true;
}

// ── Hyprland's window controls, in sway ──────────────────────────────────────
//
// Three things Hyprland had on the keyboard that sway has no single command
// for, asked for back after the move from Hyprland.

namespace {

/** The focused window, and the workspace it is on, from one tree read. */
struct FocusedCtx {
    const nlohmann::json* win = nullptr;
    const nlohmann::json* workspace = nullptr;
};

void find_focused(const nlohmann::json& n, const nlohmann::json* ws, FocusedCtx& out) {
    if (out.win) return;
    if (json_str(n, "type", "") == "workspace") ws = &n;
    if (n.contains("focused") && n["focused"].is_boolean() && n["focused"].get<bool>()) {
        out.win = &n;
        out.workspace = ws;
        return;
    }
    for (const char* key : {"nodes", "floating_nodes"}) {
        if (!n.contains(key) || !n[key].is_array()) continue;
        for (const auto& c : n[key]) find_focused(c, ws, out);
    }
}

int rect_num(const nlohmann::json& n, const char* key) {
    if (!n.contains("rect") || !n["rect"].is_object()) return 0;
    const auto& r = n["rect"];
    return (r.contains(key) && r[key].is_number()) ? r[key].get<int>() : 0;
}

bool has_mark_prefix(const nlohmann::json& n, const std::string& prefix, std::string* found = nullptr) {
    if (!n.contains("marks") || !n["marks"].is_array()) return false;
    for (const auto& m : n["marks"]) {
        if (m.is_string() && m.get<std::string>().rfind(prefix, 0) == 0) {
            if (found) *found = m.get<std::string>();
            return true;
        }
    }
    return false;
}

bool is_floating_node(const nlohmann::json& n) {
    const std::string f = json_str(n, "floating", "");
    return f == "user_on" || f == "auto_on" || json_str(n, "type", "") == "floating_con";
}

} // namespace

/**
 * Maximize, as Hyprland's `fullscreen, 1`: the window fills the workspace but
 * the bar and the outer gaps stay. sway only has real fullscreen, so the
 * window is floated over the workspace's usable area — which sway reports with
 * the bar's exclusive zone and the gaps already taken off — and remembered by a
 * mark: a tiled window goes back into the tiling, a floating one to where it was.
 */
bool SystemControl::window_maximize_toggle() {
    SwayIPC ipc;
    if (!ipc.connect()) return false;
    nlohmann::json tree;
    try { tree = nlohmann::json::parse(ipc.send_command(4, "")); } catch (...) { return false; }
    FocusedCtx ctx;
    find_focused(tree, nullptr, ctx);
    if (!ctx.win || !ctx.workspace || !is_window(*ctx.win)) return false;
    const auto& w = *ctx.win;
    const std::string id = std::to_string(w.value("id", static_cast<int64_t>(0)));
    const std::string sel = "[con_id=" + id + "] ";

    std::string mark;
    if (has_mark_prefix(w, "_b1air_max_tiled", &mark)) {
        ipc.send_command(0, sel + "floating disable; " + sel + "unmark " + mark);
        return true;
    }
    if (has_mark_prefix(w, "_b1air_max_float_", &mark)) {
        // _b1air_max_float_X_Y_W_H
        int x = 0, y = 0, ww = 0, hh = 0;
        if (std::sscanf(mark.c_str(), "_b1air_max_float_%d_%d_%d_%d", &x, &y, &ww, &hh) == 4 && ww > 0 && hh > 0) {
            ipc.send_command(0, sel + "resize set " + std::to_string(ww) + " px " + std::to_string(hh) + " px; "
                              + sel + "move absolute position " + std::to_string(x) + " px " + std::to_string(y) + " px");
        }
        ipc.send_command(0, sel + "unmark " + mark);
        return true;
    }

    const auto& ws = *ctx.workspace;
    const int wx = rect_num(ws, "x"), wy = rect_num(ws, "y");
    const int ww = rect_num(ws, "width"), wh = rect_num(ws, "height");
    if (ww <= 0 || wh <= 0) return false;

    std::string remember;
    if (is_floating_node(w)) {
        remember = "_b1air_max_float_" + std::to_string(rect_num(w, "x")) + "_" + std::to_string(rect_num(w, "y"))
                 + "_" + std::to_string(rect_num(w, "width")) + "_" + std::to_string(rect_num(w, "height"));
    } else {
        remember = "_b1air_max_tiled";
    }
    ipc.send_command(0, sel + "mark --add " + remember + "; " + sel + "floating enable; "
                      + sel + "resize set " + std::to_string(ww) + " px " + std::to_string(wh) + " px; "
                      + sel + "move absolute position " + std::to_string(wx) + " px " + std::to_string(wy) + " px");
    return true;
}

/**
 * Every window on the workspace floating, or every one tiled again — Hyprland's
 * `workspaceopt allfloat`. If anything on the workspace is still tiled, the
 * press floats it all; if nothing is, it tiles it all, so the key is a toggle
 * whatever mixture it starts from.
 */
bool SystemControl::window_float_all_toggle() {
    SwayIPC ipc;
    if (!ipc.connect()) return false;
    nlohmann::json tree;
    try { tree = nlohmann::json::parse(ipc.send_command(4, "")); } catch (...) { return false; }
    FocusedCtx ctx;
    find_focused(tree, nullptr, ctx);
    if (!ctx.workspace) return false;

    std::vector<std::pair<int64_t, bool>> wins;   // id, floating
    walk_tree(*ctx.workspace, [&](const nlohmann::json& n) {
        if (is_window(n))
            wins.emplace_back(n.value("id", static_cast<int64_t>(0)), is_floating_node(n));
    });
    if (wins.empty()) return true;
    const bool any_tiled = std::any_of(wins.begin(), wins.end(), [](const auto& p) { return !p.second; });

    std::string cmd;
    for (const auto& [id, floating] : wins) {
        if (id <= 0 || floating == any_tiled) continue;
        cmd += "[con_id=" + std::to_string(id) + "] floating " + (any_tiled ? "enable" : "disable") + "; ";
    }
    if (!cmd.empty()) ipc.send_command(0, cmd);
    return true;
}

/**
 * Opaque, and back — Hyprland's `setprop active opaque toggle`.
 *
 * sway does not report a window's opacity, so "back" is the value windowrules
 * gives this app (the terminal's 0.92), or 1.0 when no rule names it. The
 * mark is how the second press knows it is the second press.
 */
bool SystemControl::window_opacity_toggle() {
    SwayIPC ipc;
    if (!ipc.connect()) return false;
    nlohmann::json tree;
    try { tree = nlohmann::json::parse(ipc.send_command(4, "")); } catch (...) { return false; }
    FocusedCtx ctx;
    find_focused(tree, nullptr, ctx);
    if (!ctx.win || !is_window(*ctx.win)) return false;
    const auto& w = *ctx.win;
    const std::string sel = "[con_id=" + std::to_string(w.value("id", static_cast<int64_t>(0))) + "] ";

    std::string mark;
    if (has_mark_prefix(w, "_b1air_opaque", &mark)) {
        double rule = 1.0;
        const std::string app = node_app_id(w);
        const char* home = std::getenv("HOME");
        std::ifstream rules(std::string(home ? home : "") + "/.config/sway/conf.d/windowrules.conf");
        std::string line;
        const std::string needle = "for_window [app_id=\"" + app + "\"] opacity ";
        while (!app.empty() && std::getline(rules, line)) {
            if (line.rfind(needle, 0) == 0) {
                try { rule = std::stod(line.substr(needle.size())); } catch (...) {}
            }
        }
        char buf[16];
        std::snprintf(buf, sizeof(buf), "%.2f", std::clamp(rule, 0.1, 1.0));
        ipc.send_command(0, sel + "opacity set " + buf + "; " + sel + "unmark " + mark);
    } else {
        ipc.send_command(0, sel + "opacity set 1; " + sel + "mark --add _b1air_opaque");
    }
    return true;
}


// ── Multi-Monitor Layout Manager ─────────────────────────────────────────────
static std::string get_monitors_state_file() {
    return runtime_path("monitors-layout.json");
}

bool SystemControl::monitors_save(const std::string& layout_json) {
    std::string path = get_monitors_state_file();
    return write_private_file(path, layout_json + "\n");
}

bool SystemControl::monitors_apply(const std::string& layout_json) {
    if (layout_json.empty() || layout_json == "[]") return false;

    SwayIPC ipc;
    if (!ipc.connect()) return false;

    size_t cur = 0;
    while ((cur = layout_json.find('{', cur)) != std::string::npos) {
        size_t end = layout_json.find('}', cur);
        if (end == std::string::npos) break;
        std::string chunk = layout_json.substr(cur, end - cur + 1);

        auto get_str = [&](const std::string& key) -> std::string {
            size_t p = chunk.find("\"" + key + "\"");
            if (p == std::string::npos) return "";
            size_t c = chunk.find(':', p + key.size() + 2);
            if (c == std::string::npos) return "";
            size_t q1 = chunk.find('"', c + 1);
            if (q1 == std::string::npos) return "";
            size_t q2 = chunk.find('"', q1 + 1);
            if (q2 == std::string::npos) return "";
            return chunk.substr(q1 + 1, q2 - q1 - 1);
        };

        auto get_num = [&](const std::string& key, double def) -> double {
            size_t p = chunk.find("\"" + key + "\"");
            if (p == std::string::npos) return def;
            size_t c = chunk.find(':', p + key.size() + 2);
            if (c == std::string::npos) return def;
            size_t s = chunk.find_first_of("0123456789-.", c + 1);
            if (s == std::string::npos) return def;
            size_t e = chunk.find_first_not_of("0123456789-.", s);
            std::string sub = (e == std::string::npos) ? chunk.substr(s) : chunk.substr(s, e - s);
            try { return std::stod(sub); } catch (...) { return def; }
        };

        std::string name = get_str("name");
        int resW = static_cast<int>(get_num("resW", 1920));
        int resH = static_cast<int>(get_num("resH", 1080));
        double rate = get_num("rate", 60);
        double scale = get_num("sysScale", 1.0);
        int x = static_cast<int>(get_num("x", 0));
        int y = static_cast<int>(get_num("y", 0));
        std::string transform = get_str("transform");

        // Whether the output is on at all. The layout has carried "active"
        // since it was written — the QML that builds it even documents the
        // daemon as normalising the field — and nothing here read it, so an
        // output turned off in Settings came back on at the next restore.
        // Turning it off is also the whole command: mode and position mean
        // nothing for a disabled output, and sway rejects them for one.
        const bool active = chunk.find("\"active\":false") == std::string::npos
                         && chunk.find("\"active\": false") == std::string::npos;

        if (!name.empty() && !active) {
            ipc.send_command(0, "output \"" + name + "\" disable");
        } else if (!name.empty() && resW > 0 && resH > 0) {
            ipc.send_command(0, "output \"" + name + "\" enable");
            std::string mode_str = std::to_string(resW) + "x" + std::to_string(resH);
            if (rate > 0) {
                std::stringstream rss;
                rss << rate;
                mode_str += "@" + rss.str() + "Hz";
            }
            std::stringstream scss;
            scss << std::fixed << std::setprecision(2) << scale;

            std::string cmd = "output \"" + name + "\" mode \"" + mode_str + "\" position " + std::to_string(x) + " " + std::to_string(y) + " scale " + scss.str();
            ipc.send_command(0, cmd);

            if (!transform.empty() && transform != "normal") {
                ipc.send_command(0, "output \"" + name + "\" transform " + transform);
            }
        }

        cur = end + 1;
    }

    monitors_save(layout_json);
    return true;
}

bool SystemControl::monitors_restore() {
    SwayIPC ipc;
    if (!ipc.connect()) return false;

    std::string outputs_json = ipc.get_outputs();
    if (outputs_json.empty() || outputs_json == "[]") return false;

    std::string state_path = get_monitors_state_file();
    std::string saved_json = read_file_string(state_path);

    if (!saved_json.empty() && saved_json != "[]") {
        // Does the saved layout mention any output that is actually connected?
        //
        // This used to scan the reply for the literal bytes "name":" — with no
        // space. Sway pretty-prints its IPC replies, so what arrives is
        // "name": "HEADLESS-1", the search matched nothing, and the saved
        // layout was never applied: monitor restore had never once worked.
        // Parsed rather than searched, so spacing cannot decide it again.
        bool has_match = false;
        try {
            const auto outputs = nlohmann::json::parse(outputs_json);
            const auto saved = nlohmann::json::parse(saved_json);
            for (const auto& o : outputs) {
                if (!o.contains("name") || !o["name"].is_string()) continue;
                const std::string name = o["name"].get<std::string>();
                for (const auto& sv : saved) {
                    if (sv.contains("name") && sv["name"].is_string()
                        && sv["name"].get<std::string>() == name) {
                        has_match = true;
                        break;
                    }
                }
                if (has_match) break;
            }
        } catch (const std::exception&) {
            has_match = false;
        }

        if (has_match) {
            return monitors_apply(saved_json);
        }
    }

    // First run, or a set of displays never seen before: lay them out left to
    // right in the order sway reports and give each the next workspace.
    //
    // This used to cut the reply at the first '}' and search the piece for
    // "name":" — which sway never writes, since it pretty-prints — so the
    // fallback never arranged anything either. Both halves of monitor restore
    // were dead for the same reason.
    int x = 0;
    int ws = 1;
    try {
        for (const auto& out : nlohmann::json::parse(outputs_json)) {
            const std::string name = json_str(out, "name", "");
            if (name.empty()) continue;

            double scale = out.value("scale", 1.0);
            if (scale <= 0) scale = 1.0;

            int width = 1920;
            if (out.contains("current_mode") && out["current_mode"].is_object())
                width = out["current_mode"].value("width", 1920);
            else if (out.contains("rect") && out["rect"].is_object())
                width = out["rect"].value("width", 1920);

            std::stringstream scss;
            scss << std::fixed << std::setprecision(2) << scale;
            ipc.send_command(0, "output \"" + name + "\" position " + std::to_string(x) + " 0 scale " + scss.str());
            ipc.send_command(0, "workspace number " + std::to_string(ws) + " output \"" + name + "\"");

            x += static_cast<int>(width / scale);
            ws++;
        }
    } catch (const std::exception&) {
        return false;
    }

    return true;
}

// ── Screenshots ──────────────────────────────────────────────────────────────
// ── Fullscreen Toggle ────────────────────────────────────────────────────────
bool SystemControl::toggle_fullscreen() {
    SwayIPC ipc;
    if (!ipc.connect()) return false;
    return ipc.toggle_fullscreen();
}

// ── Camera privacy ───────────────────────────────────────────────────────────

bool SystemControl::camera_in_use() {
    DIR *proc = opendir("/proc");
    if (!proc) return false;

    bool found = false;
    struct dirent *pe;
    while (!found && (pe = readdir(proc)) != nullptr) {
        if (pe->d_name[0] < '0' || pe->d_name[0] > '9')
            continue;

        const std::string fd_dir = std::string("/proc/") + pe->d_name + "/fd";
        DIR *fds = opendir(fd_dir.c_str());
        if (!fds)
            continue;                       // another user's process, or it exited

        struct dirent *fe;
        while ((fe = readdir(fds)) != nullptr) {
            if (fe->d_name[0] == '.')
                continue;
            char target[256];
            const std::string link = fd_dir + "/" + fe->d_name;
            const ssize_t n = readlink(link.c_str(), target, sizeof(target) - 1);
            if (n <= 0)
                continue;
            target[n] = '\0';
            if (std::strncmp(target, "/dev/video", 10) == 0) {
                found = true;
                break;
            }
        }
        closedir(fds);
    }

    closedir(proc);
    return found;
}

// ── Layout Shorthand ─────────────────────────────────────────────────────────
std::string SystemControl::get_layout_shorthand() {
    SwayIPC ipc;
    if (!ipc.connect()) return "US";

    std::string inputs = ipc.get_inputs();
    if (inputs.empty()) return "US";

    size_t pos = inputs.find("\"xkb_active_layout_name\":");
    if (pos == std::string::npos) return "US";

    size_t start = inputs.find('"', pos + 25);
    if (start == std::string::npos) return "US";
    size_t end = inputs.find('"', start + 1);
    if (end == std::string::npos) return "US";

    std::string layout = inputs.substr(start + 1, end - start - 1);
    std::string lower = layout;
    std::transform(lower.begin(), lower.end(), lower.begin(), ::tolower);

    if (lower.find("ukrainian") != std::string::npos || lower.find("українська") != std::string::npos || lower == "ua" || lower == "uk") return "UA";
    if (lower.find("german") != std::string::npos || lower.find("deutsch") != std::string::npos || lower == "de") return "DE";
    if (lower.find("french") != std::string::npos || lower.find("français") != std::string::npos || lower == "fr") return "FR";
    if (lower.find("spanish") != std::string::npos || lower.find("español") != std::string::npos || lower == "es") return "ES";
    if (lower.find("polish") != std::string::npos || lower.find("polski") != std::string::npos || lower == "pl") return "PL";
    if (lower.find("italian") != std::string::npos || lower.find("italiano") != std::string::npos || lower == "it") return "IT";
    if (lower.find("russian") != std::string::npos || lower.find("русский") != std::string::npos || lower == "ru") return "RU";
    if (lower.find("english") != std::string::npos || lower == "us" || lower == "en") return "US";

    if (layout.size() >= 2 && layout.size() <= 3) {
        std::string upper = layout;
        std::transform(upper.begin(), upper.end(), upper.begin(), ::toupper);
        return upper;
    }

    return "US";
}

// ── Wi-Fi & Network Status ───────────────────────────────────────────────────
std::string SystemControl::get_wifi_status_json() {
    std::string radio = exec_cmd("nmcli -t -f WIFI general 2>/dev/null | head -n1");
    if (radio == "enabled") {
        std::string line = exec_cmd("nmcli -t -f IN-USE,SIGNAL device wifi list 2>/dev/null | grep '^\\*' | head -n1");
        if (!line.empty()) {
            size_t colon = line.find(':');
            std::string sig_str = (colon != std::string::npos) ? line.substr(colon + 1) : "0";
            int signal = 0;
            try { signal = std::stoi(sig_str); } catch (...) { signal = 0; }

            std::string icon = "󰤯";
            if (signal >= 80) icon = "󰤨";
            else if (signal >= 60) icon = "󰤥";
            else if (signal >= 40) icon = "󰤢";
            else if (signal >= 20) icon = "󰤟";

            return "{\"text\":\"" + icon + "  " + std::to_string(signal) + "%\",\"class\":\"connected\"}";
        }
    }

    // Check for active wired Ethernet (common in Virtual Machines)
    std::string wired = exec_cmd("nmcli -t -f TYPE,STATE device 2>/dev/null | grep -E '^ethernet:connected'");
    if (!wired.empty()) {
        return "{\"text\":\"󰈀 Wired\",\"class\":\"connected\"}";
    }

    if (radio != "enabled") {
        return "{\"text\":\"󰤮\",\"class\":\"off\"}";
    }

    return "{\"text\":\"󰤯\",\"class\":\"disconnected\"}";
}

// ── Interactive Wi-Fi Management ─────────────────────────────────────────────
std::string SystemControl::wifi_list_json() {
    std::string out = exec_cmd("nmcli -t -f SSID,BSSID,SIGNAL,SECURITY,IN-USE device wifi list 2>/dev/null");
    std::istringstream stream(out);
    std::string line;
    std::vector<std::string> json_items;
    std::unordered_set<std::string> seen_ssids;

    while (std::getline(stream, line)) {
        if (line.empty()) continue;
        std::vector<std::string> parts;
        std::string cur;
        for (size_t i = 0; i < line.size(); ++i) {
            if (line[i] == '\\' && i + 1 < line.size() && line[i + 1] == ':') {
                cur += ':';
                ++i;
            } else if (line[i] == ':') {
                parts.push_back(cur);
                cur.clear();
            } else {
                cur += line[i];
            }
        }
        parts.push_back(cur);

        if (parts.size() >= 5) {
            std::string ssid = parts[0];
            std::string bssid = parts[1];
            int signal = 0;
            try { signal = std::stoi(parts[2]); } catch (...) {}
            std::string security = parts[3];
            bool in_use = (parts[4] == "*");

            if (ssid.empty()) continue;
            if (seen_ssids.count(ssid)) continue;
            seen_ssids.insert(ssid);

            std::string item = "{\"ssid\":\"" + json_escape(ssid) + "\","
                               "\"bssid\":\"" + json_escape(bssid) + "\","
                               "\"signal\":" + std::to_string(signal) + ","
                               "\"security\":\"" + json_escape(security) + "\","
                               "\"secured\":" + std::string((security.empty() || security == "--") ? "false" : "true") + ","
                               "\"active\":" + std::string(in_use ? "true" : "false") + "}";
            json_items.push_back(item);
        }
    }

    std::string res = "[";
    for (size_t i = 0; i < json_items.size(); ++i) {
        res += json_items[i];
        if (i + 1 < json_items.size()) res += ",";
    }
    res += "]";
    return res;
}

std::string SystemControl::wifi_connect(const std::string& ssid, const std::string& password) {
    const std::vector<std::string> args = {"nmcli", "device", "wifi", "connect", ssid};
    // nmcli prompts for the secret when no password argument is supplied;
    // feed it through stdin so it never appears in /proc or process listings.
    std::string out = password.empty() ? run_argv_capture(args) : run_argv_capture(args, password);
    bool ok = (out.find("successfully") != std::string::npos || out.find("Connection successfully activated") != std::string::npos);
    return "{\"success\":" + std::string(ok ? "true" : "false") + ",\"message\":\"" + json_escape(out) + "\"}";
}

// ── Interactive Bluetooth Management ─────────────────────────────────────────
std::string SystemControl::bt_list_json() {
    std::string paired_out = exec_cmd("bluetoothctl paired-devices 2>/dev/null");
    std::string all_out = exec_cmd("bluetoothctl devices 2>/dev/null");
    std::string info_out = exec_cmd("bluetoothctl info 2>/dev/null");

    std::unordered_map<std::string, std::pair<std::string, bool>> devs;

    auto parse_lines = [&](const std::string& text, bool is_paired) {
        std::istringstream st(text);
        std::string l;
        while (std::getline(st, l)) {
            if (l.rfind("Device ", 0) == 0 && l.size() > 25) {
                std::string mac = l.substr(7, 17);
                std::string name = l.size() > 25 ? l.substr(25) : mac;
                if (!devs.count(mac) || is_paired) {
                    devs[mac] = {name, is_paired};
                }
            }
        }
    };

    parse_lines(paired_out, true);
    parse_lines(all_out, false);

    std::vector<std::string> json_items;
    for (const auto& [mac, info] : devs) {
        bool connected = (info_out.find(mac) != std::string::npos && info_out.find("Connected: yes") != std::string::npos);
        std::string item = "{\"mac\":\"" + json_escape(mac) + "\","
                           "\"name\":\"" + json_escape(info.first) + "\","
                           "\"paired\":" + std::string(info.second ? "true" : "false") + ","
                           "\"connected\":" + std::string(connected ? "true" : "false") + "}";
        json_items.push_back(item);
    }

    std::string res = "[";
    for (size_t i = 0; i < json_items.size(); ++i) {
        res += json_items[i];
        if (i + 1 < json_items.size()) res += ",";
    }
    res += "]";
    return res;
}

bool SystemControl::bt_connect(const std::string& mac) {
    if (mac.size() != 17) return false;
    for (size_t i = 0; i < mac.size(); ++i) {
        if (i % 3 == 2) { if (mac[i] != ':') return false; }
        else if (!std::isxdigit(static_cast<unsigned char>(mac[i]))) return false;
    }
    return run_argv_with_stdin({"bluetoothctl", "connect", mac}, "");
}

bool SystemControl::bt_disconnect(const std::string& mac) {
    if (mac.size() != 17) return false;
    return run_argv_with_stdin({"bluetoothctl", "disconnect", mac}, "");
}

bool SystemControl::bt_pair(const std::string& mac) {
    if (mac.size() != 17) return false;
    return run_argv_with_stdin({"bluetoothctl", "pair", mac}, "");
}

// ── Media Player Status ──────────────────────────────────────────────────────
std::string SystemControl::get_media_status_json() {
    std::string output = exec_cmd("playerctl metadata --format '{{status}}\x1f{{artist}}\x1f{{title}}\x1f{{playerName}}' 2>/dev/null");
    if (output.empty()) {
        return "{\"text\":\"\",\"class\":\"hidden\",\"tooltip\":\"No active player\"}";
    }

    std::stringstream ss(output);
    std::string status, artist, title, player;
    std::getline(ss, status, '\x1f');
    std::getline(ss, artist, '\x1f');
    std::getline(ss, title, '\x1f');
    std::getline(ss, player, '\x1f');

    if (status != "Playing" && status != "Paused") {
        return "{\"text\":\"\",\"class\":\"hidden\",\"tooltip\":\"No active player\"}";
    }

    std::string label = title.empty() ? "Media" : title;
    if (!artist.empty()) label = artist + " - " + label;

    // Escape JSON string
    std::string safe_label;
    for (char c : label) {
        if (c == '"' || c == '\\') safe_label += '\\';
        else safe_label += c;
    }

    std::string cls = (status == "Playing") ? "playing" : "paused";
    return "{\"text\":\"" + safe_label + "\",\"class\":\"" + cls + "\",\"tooltip\":\"" + safe_label + "\"}";
}

// ── Volume & Microphone ──────────────────────────────────────────────────────
int SystemControl::get_volume() {
    std::string raw = run_argv_capture({"wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"});
    size_t start = raw.find("0.");
    if (start != std::string::npos) {
        try { return static_cast<int>(std::stod(raw.substr(start)) * 100.0); } catch (...) {}
    }
    raw = run_argv_capture({"pamixer", "--get-volume"});
    try { return std::stoi(raw); } catch (...) { return 0; }
}

/**
 * A freedesktop sound-theme event, if the user asked for it.
 *
 * Settings → Sound offers "Volume Step Feedback Click" and "Screenshot Shutter
 * Sound"; both were switches storing values nothing read. The QML side has a
 * SoundEffects service, but the events they describe happen here — the volume
 * keys and the capture both run in the daemon — so the sounds belong here too.
 * libcanberra and sound-theme-freedesktop are already in the package list.
 */
static void play_feedback_sound(const char* setting_key, const char* sound_name) {
    if (!SettingsManager::get_json_bool(setting_key, true)) return;
    (void)util::spawn_detached({"canberra-gtk-play", "-i", sound_name});
}

bool SystemControl::volume_up(int step) {
    // The OSD bar already covers this (see the mute/brightness fixes above).
    const bool ok = run_argv_status({"wpctl", "set-volume", "-l", "1.5", "@DEFAULT_AUDIO_SINK@", std::to_string(step) + "%+"})
        || run_argv_status({"pamixer", "-i", std::to_string(step)});
    if (ok) play_feedback_sound("soundVolumeFeedback", "audio-volume-change");
    return ok;
}

bool SystemControl::volume_down(int step) {
    const bool ok = run_argv_status({"wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", std::to_string(step) + "%-"})
        || run_argv_status({"pamixer", "-d", std::to_string(step)});
    if (ok) play_feedback_sound("soundVolumeFeedback", "audio-volume-change");
    return ok;
}

bool SystemControl::volume_toggle_mute() {
    if (!run_argv_status({"wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"})) {
        (void)run_argv_status({"pamixer", "-t"});
    }
    // The shell's own OSD watches PipeWire's mute/volume state directly and
    // shows the on-screen bar for this; a desktop notification on top of that
    // was a redundant toast for every single press.
    return true;
}

std::string SystemControl::get_mic_status() {
    std::string raw = run_argv_capture({"wpctl", "get-volume", "@DEFAULT_AUDIO_SOURCE@"});
    std::string mute = raw.find("MUTED") != std::string::npos ? "muted" : "unmuted";
    if (mute != "muted") {
        std::string pm = run_argv_capture({"pamixer", "--default-source", "--get-mute"});
        if (pm == "true") mute = "muted";
    }
    return mute;
}

bool SystemControl::mic_toggle() {
    if (!run_argv_status({"wpctl", "set-mute", "@DEFAULT_AUDIO_SOURCE@", "toggle"})) {
        (void)run_argv_status({"pamixer", "--default-source", "-t"});
    }
    // The shell's own OSD watches PipeWire's source mute state directly and
    // shows the on-screen bar for this; a desktop notification on top of
    // that was a redundant toast for every single press.
    return true;
}

// ── Screen Brightness ────────────────────────────────────────────────────────
bool SystemControl::brightness_available() {
    DIR* dir = opendir("/sys/class/backlight");
    if (!dir) return false;
    struct dirent* entry;
    bool found = false;
    while ((entry = readdir(dir)) != nullptr) {
        if (entry->d_name[0] != '.') {
            found = true;
            break;
        }
    }
    closedir(dir);
    return found;
}

int SystemControl::brightness_get() {
    std::string raw = run_argv_capture({"brightnessctl", "-c", "backlight", "-m"});
    size_t percent = raw.find('%');
    size_t begin = percent;
    while (begin > 0 && std::isdigit(static_cast<unsigned char>(raw[begin - 1]))) --begin;
    std::string val = percent != std::string::npos ? raw.substr(begin, percent - begin) : "";
    try { return std::stoi(val); } catch (...) { return 100; }
}

bool SystemControl::brightness_up(int step) {
    // The shell's own OSD watches the backlight sysfs file directly and
    // shows the on-screen bar for this; a desktop notification on top of
    // that was a redundant toast for every single press.
    return run_argv_status({"brightnessctl", "-c", "backlight", "-e4", "-n2", "set", std::to_string(step) + "%+"});
}

bool SystemControl::brightness_down(int step) {
    return run_argv_status({"brightnessctl", "-c", "backlight", "-e4", "-n2", "set", std::to_string(step) + "%-"});
}

bool SystemControl::brightness_set(int pct) {
    return run_argv_status({"brightnessctl", "-c", "backlight", "-e4", "-n2", "set", std::to_string(pct) + "%"});
}

// ── DDC/CI External Monitor Controls ─────────────────────────────────────────
struct DdcDisplay {
    std::string id;
    std::string name;
};

static std::string get_sway_cache_dir() {
    std::string dir = runtime_dir() + "/sway";
    mkdir(dir.c_str(), 0700);
    mkdir((dir + "/monitor-brightness-values").c_str(), 0755);
    return dir;
}

static std::vector<DdcDisplay> detect_ddc_displays(bool force = false) {
    std::string cache_dir = get_sway_cache_dir();
    std::string disp_cache = cache_dir + "/monitor-brightness-displays";
    std::vector<DdcDisplay> displays;

    bool cache_fresh = false;
    struct stat st;
    if (!force && stat(disp_cache.c_str(), &st) == 0) {
        auto now = std::chrono::system_clock::now();
        auto now_sec = std::chrono::duration_cast<std::chrono::seconds>(now.time_since_epoch()).count();
        int ttl = (st.st_size > 0) ? 45 : 10;
        if (now_sec - st.st_mtime < ttl) {
            cache_fresh = true;
        }
    }

    if (cache_fresh) {
        std::ifstream in(disp_cache);
        std::string line;
        while (std::getline(in, line)) {
            size_t tab = line.find('\t');
            if (tab != std::string::npos) {
                DdcDisplay d;
                d.id = line.substr(0, tab);
                d.name = line.substr(tab + 1);
                displays.push_back(d);
            }
        }
        if (!displays.empty() || st.st_size == 0) {
            return displays;
        }
    }

    std::string raw = exec_cmd_full("timeout 2s ddcutil detect --brief 2>/dev/null");
    std::istringstream stream(raw);
    std::string line, cur_display, cur_bus, cur_model;

    auto emit = [&]() {
        if (!cur_display.empty()) {
            DdcDisplay d;
            d.id = !cur_bus.empty() ? ("bus:" + cur_bus) : ("display:" + cur_display);
            d.name = !cur_model.empty() ? cur_model : ("Display " + cur_display);
            displays.push_back(d);
        }
        cur_display = "";
        cur_bus = "";
        cur_model = "";
    };

    while (std::getline(stream, line)) {
        while (!line.empty() && (line.back() == '\r' || line.back() == '\n' || line.back() == ' ')) line.pop_back();
        if (line.rfind("Display ", 0) == 0) {
            emit();
            cur_display = line.substr(8);
        } else if (line.find("I2C bus:") != std::string::npos) {
            size_t p = line.find("/dev/i2c-");
            if (p != std::string::npos) {
                size_t start = p + 9;
                size_t end = line.find_first_not_of("0123456789", start);
                cur_bus = (end == std::string::npos) ? line.substr(start) : line.substr(start, end - start);
            }
        } else if (line.find("Monitor:") != std::string::npos) {
            size_t p = line.find("Monitor:");
            size_t start = line.find_first_not_of(" \t", p + 8);
            if (start != std::string::npos) {
                cur_model = line.substr(start);
                // ddcutil writes "MFG:Model name:serial"; the model is the
                // part a person recognises on a slider label.
                size_t c1 = cur_model.find(':');
                size_t c2 = c1 == std::string::npos ? c1 : cur_model.find(':', c1 + 1);
                if (c2 != std::string::npos && c2 > c1 + 1)
                    cur_model = cur_model.substr(c1 + 1, c2 - c1 - 1);
            }
        } else if (line.empty()) {
            emit();
        }
    }
    emit();

    std::ofstream out(disp_cache);
    for (const auto& d : displays) {
        out << d.id << "\t" << d.name << "\n";
    }
    out.close();

    return displays;
}

static int get_ddc_brightness_single(const std::string& id) {
    std::string cache_dir = get_sway_cache_dir();
    std::string safe_id = id;
    std::replace(safe_id.begin(), safe_id.end(), ':', '_');
    std::replace(safe_id.begin(), safe_id.end(), '/', '_');
    std::string val_cache = cache_dir + "/monitor-brightness-values/" + safe_id;

    std::vector<std::string> ddc_args = {"timeout", "2s", "ddcutil", "getvcp", "10"};
    if (id.rfind("bus:", 0) == 0) ddc_args.insert(ddc_args.end(), {"--bus", id.substr(4)});
    else if (id.rfind("display:", 0) == 0) ddc_args.insert(ddc_args.end(), {"--display", id.substr(8)});
    else ddc_args.insert(ddc_args.end(), {"--display", id});
    ddc_args.push_back("--noverify");

    std::string out = run_argv_capture(ddc_args);
    size_t value_pos = out.find("current value =");
    if (value_pos != std::string::npos) {
        value_pos = out.find_first_of("0123456789", value_pos);
        out = value_pos == std::string::npos ? "" : out.substr(value_pos);
    }
    if (!out.empty()) {
        try {
            int v = std::stoi(out);
            (void)write_private_file(val_cache, std::to_string(v) + "\n");
            return v;
        } catch (...) {}
    }

    std::ifstream in(val_cache);
    if (in) {
        int v = 50;
        in >> v;
        return v;
    }
    return 50;
}

std::string SystemControl::ddc_list_json(bool force_detect) {
    auto displays = detect_ddc_displays(force_detect);
    std::string json = "[";
    for (size_t i = 0; i < displays.size(); ++i) {
        int b = get_ddc_brightness_single(displays[i].id);
        json += "{\"id\":\"" + json_escape(displays[i].id) + "\",\"name\":\"" + json_escape(displays[i].name) + "\",\"type\":\"ddc\",\"brightness\":" + std::to_string(b) + "}";
        if (i + 1 < displays.size()) json += ",";
    }
    json += "]";
    return json;
}

bool SystemControl::ddc_set(const std::string& id, int percent) {
    percent = std::clamp(percent, 1, 100);
    std::string cache_dir = get_sway_cache_dir();
    std::string safe_id = id;
    std::replace(safe_id.begin(), safe_id.end(), ':', '_');
    std::replace(safe_id.begin(), safe_id.end(), '/', '_');
    std::string val_cache = cache_dir + "/monitor-brightness-values/" + safe_id;

    (void)write_private_file(val_cache, std::to_string(percent) + "\n");

    std::vector<std::string> args = {"timeout", "2s", "ddcutil", "setvcp", "10", std::to_string(percent)};
    if (id.rfind("bus:", 0) == 0) args.insert(args.end(), {"--bus", id.substr(4)});
    else if (id.rfind("display:", 0) == 0) args.insert(args.end(), {"--display", id.substr(8)});
    else args.insert(args.end(), {"--display", id});
    args.push_back("--noverify");
    (void)util::spawn_detached(args);
    return true;
}

bool SystemControl::ddc_adjust_all(int step) {
    auto displays = detect_ddc_displays(false);
    for (const auto& d : displays) {
        int cur = get_ddc_brightness_single(d.id);
        int next = std::clamp(cur + step, 1, 100);
        ddc_set(d.id, next);
    }
    return true;
}

std::string SystemControl::ddc_status_json() {
    auto displays = detect_ddc_displays(false);
    if (displays.empty()) {
        return "{\"text\":\"\",\"tooltip\":\"No DDC brightness controls found\",\"class\":\"empty\"}";
    }

    int sum = 0;
    std::string tooltip;
    for (size_t i = 0; i < displays.size(); ++i) {
        int b = get_ddc_brightness_single(displays[i].id);
        sum += b;
        tooltip += displays[i].name + "  " + std::to_string(b) + "%";
        if (i + 1 < displays.size()) tooltip += "\\n";
    }
    int avg = sum / static_cast<int>(displays.size());
    return "{\"text\":\"󰃠  " + std::to_string(avg) + "%\",\"tooltip\":\"" + tooltip + "\",\"class\":\"active\"}";
}

bool SystemControl::ddc_refresh() {
    detect_ddc_displays(true);
    return true;
}

bool SystemControl::ddc_dim() {
    std::string cur = std::to_string(brightness_get());
    std::ofstream out(runtime_path("brightness.saved"));
    out << cur << "\n";
    out.close();

    (void)run_argv_status({"brightnessctl", "-c", "backlight", "set", "10%"});
    (void)run_argv_status({"ddcutil", "setvcp", "10", "10", "--noverify"});
    return true;
}

bool SystemControl::ddc_undim() {
    std::string saved = "100";
    std::ifstream in(runtime_path("brightness.saved"));
    if (in) {
        in >> saved;
        in.close();
    }
    bool valid_saved = !saved.empty() && std::all_of(saved.begin(), saved.end(), [](char c) { return std::isdigit(static_cast<unsigned char>(c)); });
    if (valid_saved) (void)run_argv_status({"brightnessctl", "-c", "backlight", "set", saved + "%"});
    (void)run_argv_status({"ddcutil", "setvcp", "10", "100", "--noverify"});
    unlink(runtime_path("brightness.saved").c_str());
    return true;
}

// ── Weather Forecast & Live Status ───────────────────────────────────────────
// This is the fallback for every weather-fetch failure — no OpenWeatherMap
// key AND wttr.in also unreachable, a configured key whose fetch failed
// (usually the network, not the key), or a response jq couldn't parse — not
// only the literal "no key configured" case. It used to say "No API Key" in
// all of them, so a plain transient network blip at startup looked like a
// permanent configuration problem.
static std::string get_dummy_weather_json() {
    auto now = std::chrono::system_clock::now();
    std::string json = "{\"forecast\":[";
    for (int i = 0; i < 5; ++i) {
        auto day_point = now + std::chrono::hours(24 * i);
        auto t = std::chrono::system_clock::to_time_t(day_point);
        struct tm* tm = std::localtime(&t);
        char day_short[16], day_full[32], date_str[32];
        std::strftime(day_short, sizeof(day_short), "%a", tm);
        std::strftime(day_full, sizeof(day_full), "%A", tm);
        std::strftime(date_str, sizeof(date_str), "%d %b", tm);

        json += "{\"id\":\"" + std::to_string(i) + "\",\"day\":\"" + day_short + "\",\"day_full\":\"" + day_full + "\",\"date\":\"" + date_str + "\",\"max\":\"0.0\",\"min\":\"0.0\",\"feels_like\":\"0.0\",\"wind\":\"0\",\"humidity\":\"0\",\"pop\":\"0\",\"icon\":\"\",\"hex\":\"#cdd6f4\",\"desc\":\"Weather unavailable\",\"hourly\":[{\"time\":\"00:00\",\"temp\":\"0.0\",\"icon\":\"\",\"hex\":\"#cdd6f4\"}]}";
        if (i + 1 < 5) json += ",";
    }
    json += "]}";
    return json;
}

static std::string weather_icon_from_desc(const std::string& d_in) {
    std::string d = d_in;
    std::transform(d.begin(), d.end(), d.begin(), ::tolower);
    if (d.find("sun") != std::string::npos || d.find("clear") != std::string::npos) return "\uf185";
    if (d.find("rain") != std::string::npos || d.find("drizzle") != std::string::npos || d.find("shower") != std::string::npos) return "\uf043";
    if (d.find("snow") != std::string::npos || d.find("ice") != std::string::npos) return "\uf2dc";
    if (d.find("thunder") != std::string::npos || d.find("storm") != std::string::npos) return "\uf0e7";
    return "\uf0c2";
}

static std::string weather_hex_from_desc(const std::string& d_in) {
    std::string d = d_in;
    std::transform(d.begin(), d.end(), d.begin(), ::tolower);
    if (d.find("sun") != std::string::npos || d.find("clear") != std::string::npos) return "#f9e2af";
    if (d.find("rain") != std::string::npos || d.find("drizzle") != std::string::npos) return "#74c7ec";
    if (d.find("snow") != std::string::npos || d.find("ice") != std::string::npos) return "#cdd6f4";
    if (d.find("thunder") != std::string::npos || d.find("storm") != std::string::npos) return "#f9e2af";
    return "#bac2de";
}

std::string SystemControl::weather_get_json(bool force) {
    const char* home = std::getenv("HOME");
    const std::string home_str = home ? home : "/tmp";
    std::string cache_dir = home_str + "/.cache/quickshell/weather";
    mkdir(cache_dir.c_str(), 0755);

    std::string env_file = home_str + "/.config/b1air-shell/calendar/.env";
    if (access(env_file.c_str(), R_OK) != 0) env_file = home_str + "/.config/quickshell/calendar/.env";
    std::string api_key;
    SecretStore secrets;
    (void)secrets.get("weather-api-key", api_key);
    // The Settings writer sends the key followed by a newline, and the store
    // keeps what it is given, so the key went into the URL as "abc…\n".
    while (!api_key.empty() && std::isspace(static_cast<unsigned char>(api_key.back()))) api_key.pop_back();
    while (!api_key.empty() && std::isspace(static_cast<unsigned char>(api_key.front()))) api_key.erase(api_key.begin());
    std::string city_id = std::getenv("OPENWEATHER_CITY_ID") ? std::getenv("OPENWEATHER_CITY_ID") : "";
    std::string unit = std::getenv("OPENWEATHER_UNIT") ? std::getenv("OPENWEATHER_UNIT") : "metric";

    std::ifstream env_in(env_file);
    if (env_in) {
        std::string line;
        while (std::getline(env_in, line)) {
            if (line.empty() || line[0] == '#') continue;
            size_t eq = line.find('=');
            if (eq != std::string::npos) {
                std::string k = line.substr(0, eq);
                std::string v = line.substr(eq + 1);
                k.erase(std::remove_if(k.begin(), k.end(), ::isspace), k.end());
                while (!v.empty() && (v.back() == '\r' || v.back() == '\n' || v.back() == '"' || v.back() == '\'')) v.pop_back();
                while (!v.empty() && (v.front() == '"' || v.front() == '\'')) v.erase(v.begin());
                // Legacy .env is intentionally ignored for credentials. Users
                // must migrate the key through b1air-secret-service.
                if (k == "OPENWEATHER_CITY_ID") city_id = v;
                else if (k == "OPENWEATHER_UNIT") unit = v;
            }
        }
    }

    // The Weather settings page writes weatherCityId and weatherUnit, and this
    // only ever looked at the environment and a legacy .env file. So a city
    // entered there was never used — with no city the OpenWeather branch below
    // is skipped, and a saved key did nothing either — and Fahrenheit changed
    // no number anywhere. The page wins over the older sources.
    const std::string settings_city = SettingsManager::get_json_string("weatherCityId");
    if (!settings_city.empty()) city_id = settings_city;
    const std::string settings_unit = SettingsManager::get_json_string("weatherUnit");
    if (!settings_unit.empty()) unit = settings_unit;
    if (unit != "imperial") unit = "metric";
    // Goes into a URL and a file name.
    city_id.erase(std::remove_if(city_id.begin(), city_id.end(),
                                 [](unsigned char c) { return !std::isdigit(c); }), city_id.end());
    const bool imperial = unit == "imperial";
    const bool use_openweather = !(api_key.empty() || api_key == "Skipped" || api_key == "OPENWEATHER_KEY" || city_id.empty());

    // One cache per source and unit. A single weather.json meant that changing
    // the unit or the city kept serving the old numbers for up to 15 minutes,
    // which is exactly when someone is looking to see whether it worked.
    std::string json_file = cache_dir + "/weather-" + unit + "-" + (use_openweather ? city_id : std::string("wttr")) + ".json";

    struct stat st;
    if (!force && stat(json_file.c_str(), &st) == 0) {
        auto now = std::chrono::system_clock::now();
        auto now_sec = std::chrono::duration_cast<std::chrono::seconds>(now.time_since_epoch()).count();
        if (now_sec - st.st_mtime < 900 && st.st_size > 50) {
            std::string cached = read_file_string(json_file);
            if (!cached.empty()) return cached;
        }
    }

    if (!use_openweather) {
        std::string raw = run_argv_capture({"curl", "-fsS", "--max-time", "5", "https://wttr.in/?format=j1"});
        if (!raw.empty()) {
            try {
                auto data = nlohmann::json::parse(raw);
                if (data.contains("weather") && data["weather"].is_array()) {
                    nlohmann::json forecast_arr = nlohmann::json::array();
                    auto curr = (data.contains("current_condition") && data["current_condition"].is_array() && !data["current_condition"].empty())
                                ? data["current_condition"][0] : nlohmann::json::object();
                    std::string feels = curr.value(imperial ? "FeelsLikeF" : "FeelsLikeC", "20");

                    int idx = 0;
                    for (const auto& day : data["weather"]) {
                        if (idx >= 5) break;
                        std::string date_str = day.value("date", "");
                        struct tm tm_date = {};
                        strptime(date_str.c_str(), "%Y-%m-%d", &tm_date);
                        char day_short[16], day_full[32], date_formatted[32];
                        std::strftime(day_short, sizeof(day_short), "%a", &tm_date);
                        std::strftime(day_full, sizeof(day_full), "%A", &tm_date);
                        std::strftime(date_formatted, sizeof(date_formatted), "%d %b", &tm_date);

                        nlohmann::json hourly_arr = nlohmann::json::array();
                        std::string day_desc = "Clear";
                        std::string wind = "0", humid = "0", pop = "0";

                        if (day.contains("hourly") && day["hourly"].is_array()) {
                            size_t mid_idx = day["hourly"].size() / 2;
                            if (mid_idx < day["hourly"].size()) {
                                const auto& mid = day["hourly"][mid_idx];
                                if (mid.contains("weatherDesc") && mid["weatherDesc"].is_array() && !mid["weatherDesc"].empty()) {
                                    day_desc = mid["weatherDesc"][0].value("value", "Clear");
                                }
                                wind = mid.value(imperial ? "windspeedMiles" : "windspeedKmph", "0");
                                humid = mid.value("humidity", "0");
                                pop = mid.value("chanceofrain", "0");
                            }

                            for (const auto& h : day["hourly"]) {
                                std::string t_raw = h.value("time", "0");
                                std::string t_str = "00:00";
                                if (t_raw.length() == 3) t_str = "0" + t_raw.substr(0, 1) + ":00";
                                else if (t_raw.length() == 4) t_str = t_raw.substr(0, 2) + ":00";

                                std::string hdesc = "Clear";
                                if (h.contains("weatherDesc") && h["weatherDesc"].is_array() && !h["weatherDesc"].empty()) {
                                    hdesc = h["weatherDesc"][0].value("value", "Clear");
                                }

                                hourly_arr.push_back({
                                    {"time", t_str},
                                    {"temp", h.value(imperial ? "tempF" : "tempC", "0")},
                                    {"icon", weather_icon_from_desc(hdesc)},
                                    {"hex", weather_hex_from_desc(hdesc)}
                                });
                            }
                        }

                        forecast_arr.push_back({
                            {"id", std::to_string(idx)},
                            {"day", day_short},
                            {"day_full", day_full},
                            {"date", date_formatted},
                            {"max", day.value(imperial ? "maxtempF" : "maxtempC", "0")},
                            {"min", day.value(imperial ? "mintempF" : "mintempC", "0")},
                            {"feels_like", feels},
                            {"wind", wind},
                            {"humidity", humid},
                            {"pop", pop},
                            {"icon", weather_icon_from_desc(day_desc)},
                            {"hex", weather_hex_from_desc(day_desc)},
                            {"desc", day_desc},
                            {"hourly", hourly_arr}
                        });
                        idx++;
                    }

                    nlohmann::json result = {{"unit", imperial ? "F" : "C"}, {"forecast", forecast_arr}};
                    std::string res_str = result.dump();
                    std::ofstream out(json_file);
                    out << res_str << "\n";
                    out.close();
                    return res_str;
                }
            } catch (...) {}
        }
        // Not cached: this is a fetch failure (wttr.in unreachable, bad
        // response), not a real result — writing it to the cache used to
        // make a transient network blip at startup (curl failing because
        // Wi-Fi wasn't up yet) stick for a full 15 minutes, since the next
        // call would just read the cached failure back and never retry.
        return get_dummy_weather_json();
    }

    std::string url = "https://api.openweathermap.org/data/2.5/forecast?APPID=" + api_key + "&id=" + city_id + "&units=" + unit;
    std::string raw = run_argv_capture({"curl", "-fsS", "--max-time", "8", url});

    if (raw.empty() || raw.find("\"cod\":\"200\"") == std::string::npos) {
        std::string cached = read_file_string(json_file);
        if (!cached.empty()) return cached;
        return get_dummy_weather_json();
    }

    // OpenWeather reports wind in m/s for metric and mph for imperial; the
    // calendar labels it km/h, so metric is converted here. It used to go
    // through as m/s under a km/h label, a quarter of the real figure.
    const std::string transform_program =
        "def weather_icon($code): if ($code == \"50d\" or $code == \"50n\") then \"\" elif $code == \"01d\" then \"\" elif $code == \"01n\" then \"\" elif ($code | test(\"^(02|03|04)[dn]$\")) then \"\" elif ($code | test(\"^(09|10)[dn]$\")) then \"\" elif ($code == \"11d\" or $code == \"11n\") then \"\" elif ($code == \"13d\" or $code == \"13n\") then \"\" else \"\" end; "
        "def weather_hex($code): if ($code == \"50d\" or $code == \"50n\") then \"#84afdb\" elif $code == \"01d\" then \"#f9e2af\" elif $code == \"01n\" then \"#cba6f7\" elif ($code | test(\"^(02|03|04)[dn]$\")) then \"#bac2de\" elif ($code | test(\"^(09|10)[dn]$\")) then \"#74c7ec\" elif $code == \"11d\" then \"#f9e2af\" elif ($code == \"13d\" or $code == \"13n\") then \"#cdd6f4\" else \"#cdd6f4\" end; "
        "def one_decimal: ((. * 10 | round) / 10 | tostring); "
        "def titlecase: split(\" \") | map(if length > 0 then (.[0:1] | ascii_upcase) + .[1:] else . end) | join(\" \"); "
        "def day_forecast($idx; $items): ($items[(($items | length) / 2 | floor)].weather[0].icon // \"04d\") as $code | { id: ($idx | tostring), day: ($items[0].dt | strftime(\"%a\")), day_full: ($items[0].dt | strftime(\"%A\")), date: ($items[0].dt | strftime(\"%d %b\")), max: ([$items[].main.temp_max] | max | one_decimal), min: ([$items[].main.temp_min] | min | one_decimal), feels_like: ([$items[].main.feels_like] | max | one_decimal), wind: ([$items[].wind.speed] | max | (if $unit == \"C\" then . * 3.6 else . end) | round | tostring), humidity: (([$items[].main.humidity] | add / length) | round | tostring), pop: (([$items[].pop] | max // 0) * 100 | floor | tostring), icon: weather_icon($code), hex: weather_hex($code), desc: (($items[(($items | length) / 2 | floor)].weather[0].description // \"Unknown\") | titlecase), hourly: [ $items[] | (.weather[0].icon // \"04d\") as $hour_code | { time: (.dt | strftime(\"%H:%M\")), temp: (.main.temp | one_decimal), icon: weather_icon($hour_code), hex: weather_hex($hour_code) } ] }; "
        ".list as $items | ($items | map(.dt_txt[0:10]) | unique | .[:5]) as $dates | { unit: $unit, forecast: [ range(0; ($dates | length)) as $idx | $dates[$idx] as $date | day_forecast($idx; [$items[] | select(.dt_txt | startswith($date))]) ] }";

    // Feed network data through stdin.  Never embed an HTTP response in a
    // shell here-document: an attacker-controlled line such as EOF could
    // terminate it and turn the remainder into shell syntax.
    std::string formatted = run_argv_capture({"jq", "-c", "--arg", "unit", imperial ? "F" : "C", transform_program}, raw);
    if (formatted.find("\"forecast\":") != std::string::npos) {
        std::ofstream out(json_file);
        out << formatted << "\n";
        out.close();
        return formatted;
    }

    return get_dummy_weather_json();
}

std::string SystemControl::weather_get_current_info(const std::string& field) {
    std::string json = weather_get_json(false);

    auto now = std::chrono::system_clock::now();
    auto in_time_t = std::chrono::system_clock::to_time_t(now);
    struct tm* tm = std::localtime(&in_time_t);
    char buf[16];
    std::strftime(buf, sizeof(buf), "%H:%M", tm);
    std::string curr_time = buf;

    // The unit comes from the forecast itself, which carries it since the
    // Fahrenheit setting started doing something.
    std::string program = "(.unit // \"C\") as $u | ((.forecast[0].hourly | map(select(.time <= $ct)) | last) // .forecast[0].hourly[0]) | ";
    if (field == "icon" || field == "--current-icon") program += ".icon";
    else if (field == "temp" || field == "--current-temp") program += "(.temp + \"°\" + $u)";
    else if (field == "hex" || field == "--current-hex") program += ".hex";
    else program += "(.icon + \"\\n\" + .temp + \"°\" + $u)";
    return run_argv_capture({"jq", "-r", "--arg", "ct", curr_time, program}, json);
}

// ── Keyboard Backlight ───────────────────────────────────────────────────────
static std::string detect_kbd_device() {
    const std::string raw = run_argv_capture({"brightnessctl", "-l"});
    const size_t marker = raw.find("kbd_backlight");
    if (marker == std::string::npos) return "";
    const size_t begin = raw.rfind('\'', marker);
    const size_t end = raw.find('\'', marker);
    if (begin == std::string::npos || end == std::string::npos || end <= begin + 1) return "";
    return raw.substr(begin + 1, end - begin - 1);
}

bool SystemControl::kbd_backlight_available() {
    std::string dev = detect_kbd_device();
    return !dev.empty();
}

int SystemControl::kbd_backlight_get() {
    std::string dev = detect_kbd_device();
    if (dev.empty()) return 0;
    std::string raw = run_argv_capture({"brightnessctl", "-d", dev, "-m"});
    size_t percent = raw.find('%');
    size_t begin = percent;
    while (begin > 0 && std::isdigit(static_cast<unsigned char>(raw[begin - 1]))) --begin;
    std::string val = percent != std::string::npos ? raw.substr(begin, percent - begin) : "";
    try { return std::stoi(val); } catch (...) { return 0; }
}

bool SystemControl::kbd_backlight_inc(int step) {
    std::string dev = detect_kbd_device();
    if (dev.empty()) return false;
    (void)run_argv_status({"brightnessctl", "-d", dev, "set", std::to_string(step) + "%+"});
    int val = kbd_backlight_get();
    notify_user("b1air DE", "Keyboard Backlight: " + std::to_string(val) + "%", {}, "input-keyboard",
                "string:x-canonical-private-synchronous:sys-notify-kbd", "low");
    return true;
}

bool SystemControl::kbd_backlight_dec(int step) {
    std::string dev = detect_kbd_device();
    if (dev.empty()) return false;
    (void)run_argv_status({"brightnessctl", "-d", dev, "set", std::to_string(step) + "%-"});
    int val = kbd_backlight_get();
    notify_user("b1air DE", "Keyboard Backlight: " + std::to_string(val) + "%", {}, "input-keyboard",
                "string:x-canonical-private-synchronous:sys-notify-kbd", "low");
    return true;
}

bool SystemControl::kbd_backlight_set(int val) {
    std::string dev = detect_kbd_device();
    if (dev.empty()) return false;
    (void)run_argv_status({"brightnessctl", "-d", dev, "set", std::to_string(val) + "%"});
    return true;
}

bool SystemControl::kbd_backlight_off() {
    std::string dev = detect_kbd_device();
    if (dev.empty()) return false;
    (void)run_argv_status({"brightnessctl", "-d", dev, "set", "0"});
    notify_user("b1air DE", "Keyboard Backlight: OFF", {}, "input-keyboard",
                "string:x-canonical-private-synchronous:sys-notify-kbd", "low");
    return true;
}

// ── Wallpaper ────────────────────────────────────────────────────────────────
bool SystemControl::wallpaper_set(const std::string& filepath, const std::string& /*mode*/) {
    std::string resolved_path;
    if (!safe_wallpaper_file(filepath, resolved_path) || access(resolved_path.c_str(), R_OK) != 0 || !safe_sway_path(resolved_path)) return false;

    const char* home = std::getenv("HOME");
    std::string cache_file = std::string(home ? home : "/tmp") + "/.cache/current_wallpaper.jpg";

    // Copy to user cache
    (void)run_argv_status({"cp", "-f", resolved_path, cache_file});
    // Copy to SDDM cache if writable
    (void)run_argv_status({"cp", "-f", resolved_path, "/var/cache/wallpaper/current.jpg"});

    // Apply to Sway
    SwayIPC ipc;
    if (ipc.connect()) {
        ipc.send_command(0, "output * bg '" + resolved_path + "' fill");
    } else {
        (void)run_argv_status({"pkill", "-x", "swaybg"});
        (void)util::spawn_detached({"swaybg", "-m", "fill", "-i", resolved_path});
    }

    return true;
}

bool SystemControl::wallpaper_random(const std::string& dir_arg) {
    const char* home = std::getenv("HOME");
    std::string target_dir = dir_arg.empty() ? (std::string(home ? home : "") + "/.wallpapers") : dir_arg;

    DIR* dir = opendir(target_dir.c_str());
    if (!dir) return false;

    std::vector<std::string> images;
    struct dirent* entry;
    while ((entry = readdir(dir)) != nullptr) {
        if (entry->d_name[0] == '.') continue;
        std::string name = entry->d_name;
        std::string lower = name;
        std::transform(lower.begin(), lower.end(), lower.begin(), ::tolower);
        if (lower.ends_with(".jpg") || lower.ends_with(".jpeg") || lower.ends_with(".png") || lower.ends_with(".webp")) {
            images.push_back(target_dir + "/" + name);
        }
    }
    closedir(dir);

    if (images.empty()) return false;

    std::random_device rd;
    std::mt19937 g(rd());
    std::uniform_int_distribution<size_t> dist(0, images.size() - 1);
    return wallpaper_set(images[dist(g)]);
}

bool SystemControl::wallpaper_restore() {
    const char* home = std::getenv("HOME");
    std::string cache_file = std::string(home ? home : "/tmp") + "/.cache/current_wallpaper.jpg";
    if (access(cache_file.c_str(), R_OK) == 0) {
        return wallpaper_set(cache_file, "restore");
    }
    return wallpaper_random();
}

// ── Night Light ──────────────────────────────────────────────────────────────
bool SystemControl::night_light_on(int temp, bool announce) {
    // spawn_detached tells you the fork worked, not that the program ran:
    // with wlsunset missing the exec fails inside the child and this still
    // announced "Night Light Enabled" over a screen that never changed
    // colour. Check the binary is there, then check it stayed up.
    if (!try_exec_present("wlsunset")) {
        notify_user("Night Light", "wlsunset is not installed",
                    "Install wlsunset to use night light.", "dialog-error");
        return false;
    }

    // wlsunset has no "fixed temperature" mode; it moves between -t at night
    // and -T by day. This passed -t alone, so -T stayed at its 6500 K default,
    // and with no location given wlsunset decides it is permanently day and
    // sits at 6500 K — which is no filter at all. The shell's own attempt
    // passed -t and -T equal, which wlsunset refuses outright ("high temp
    // must be higher than low") and exits. So night light had never tinted
    // the screen from any of the three places that offer it. A one-kelvin
    // gap makes both ends the chosen value.
    temp = std::clamp(temp, 1000, 6500);
    (void)run_argv_status({"pkill", "-x", "wlsunset"});
    if (!util::spawn_detached({"wlsunset", "-t", std::to_string(temp), "-T", std::to_string(temp + 1)})) {
        notify_user("Night Light", "Could not start wlsunset", {}, "dialog-error");
        return false;
    }

    std::this_thread::sleep_for(std::chrono::milliseconds(200));
    if (!run_argv_status({"pgrep", "-x", "wlsunset"})) {
        notify_user("Night Light", "wlsunset exited immediately",
                    "The compositor may not support gamma control.", "dialog-error");
        return false;
    }

    // Quiet for the Settings slider, which restarts this on every step, and
    // for the login restore: a toast per notch, or one at every login, is
    // noise about something the user is looking at.
    if (announce)
        notify_user("Night Light", "Night Light Enabled", "Warm color temperature active", "weather-clear-night");
    return true;
}

bool SystemControl::night_light_off(bool announce) {
    (void)run_argv_status({"pkill", "-x", "wlsunset"});
    if (announce)
        notify_user("Night Light", "Night Light Disabled", "Standard display colors restored", "weather-clear");
    return true;
}

bool SystemControl::night_light_toggle() {
    std::string check = exec_cmd("pgrep wlsunset");
    if (!check.empty()) {
        return night_light_off();
    } else {
        return night_light_on(SettingsManager::get_json_int("nightLightTemp", 4000));
    }
}

bool SystemControl::night_light_auto() {
    auto now = std::chrono::system_clock::now();
    auto in_time_t = std::chrono::system_clock::to_time_t(now);
    struct tm* tm = std::localtime(&in_time_t);
    int hour = tm->tm_hour;

    if (hour >= 20 || hour < 7) {
        return night_light_on(4000);
    } else {
        return night_light_off();
    }
}

// ── System Updates ───────────────────────────────────────────────────────────
//
// One line of output per pending update from the distribution's repositories,
// whichever package manager this is. All of them read cached metadata and need
// no root: checkupdates syncs into its own temporary database, `apt-get -s`
// only simulates, and dnf and zypper refresh into the user's cache.
static const char* const kPendingUpdatesCmd =
    "if command -v checkupdates >/dev/null 2>&1; then checkupdates; "
    "elif command -v apt-get >/dev/null 2>&1; then apt-get -s -o Debug::NoLocking=1 upgrade | grep '^Inst '; "
    "elif command -v dnf >/dev/null 2>&1; then dnf -q check-update | grep -E '^[^[:space:]]+[.][^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+[^[:space:]]+$'; "
    "elif command -v zypper >/dev/null 2>&1; then zypper -q list-updates | grep '^v '; "
    "fi";

std::string SystemControl::get_updates_json(bool /*force*/) {
    int system_updates = 0;
    int aur_updates = 0;

    std::string sys_str = exec_cmd(std::string("{ ") + kPendingUpdatesCmd + "; } 2>/dev/null | wc -l");
    try { system_updates = std::stoi(sys_str); } catch (...) { system_updates = 0; }

    // The AUR exists only on Arch; elsewhere neither helper is installed and
    // this counts nothing.
    std::string aur_str = exec_cmd("{ if command -v yay >/dev/null 2>&1; then yay -Qua; "
                                   "elif command -v paru >/dev/null 2>&1; then paru -Qua; fi; } 2>/dev/null | wc -l");
    try { aur_updates = std::stoi(aur_str); } catch (...) { aur_updates = 0; }

    // Which package manager answered, for the windows that name it.
    const std::string manager = exec_cmd(
        "for m in pacman apt-get dnf zypper; do command -v $m >/dev/null 2>&1 && { echo ${m%-get}; break; }; done");

    int total = system_updates + aur_updates;
    if (total == 0) {
        return "{\"text\":\"\",\"alt\":\"0\",\"tooltip\":\"Packages are up to date\",\"class\":\"green\",\"manager\":\"" + json_escape(manager) + "\",\"system\":0,\"aur\":0}";
    }

    std::string cls = (total > 50) ? "red" : ((total > 0) ? "yellow" : "green");
    std::string tooltip = std::to_string(system_updates) + " System";
    if (aur_updates > 0) tooltip += " | " + std::to_string(aur_updates) + " AUR";
    return "{\"text\":\" " + std::to_string(total) + "\",\"alt\":\"" + std::to_string(total) + "\",\"tooltip\":\"" + tooltip + "\",\"class\":\"" + cls + "\",\"manager\":\"" + json_escape(manager) + "\",\"system\":" + std::to_string(system_updates) + ",\"aur\":" + std::to_string(aur_updates) + "}";
}

// ── Default applications ─────────────────────────────────────────────────────
//
// Settings -> Default Apps records its choice with xdg-mime, and Mod+T, Mod+E
// and Mod+F ran b1air-term, b1air-files and firefox by name. Picking another
// terminal there changed what a link or a folder opened in and left the key
// that everyone actually uses on the old one. The keys come through here now,
// so the page and the keyboard agree.
bool SystemControl::open_default(const std::string& kind) {
    std::string mime, fallback;
    if (kind == "terminal")     { mime = "x-scheme-handler/terminal"; fallback = "b1air-term"; }
    else if (kind == "files")   { mime = "inode/directory";           fallback = "b1air-files"; }
    else if (kind == "browser") { mime = "x-scheme-handler/https";    fallback = "firefox"; }
    else return false;

    std::string desktop = run_argv_capture({"xdg-mime", "query", "default", mime});
    while (!desktop.empty() && std::isspace(static_cast<unsigned char>(desktop.back()))) desktop.pop_back();
    // gtk-launch hands the entry to GIO and returns once it has started, so
    // its status says whether the entry was found and could run.
    if (!desktop.empty() && run_argv_status({"gtk-launch", desktop}))
        return true;
    return util::spawn_detached({fallback});
}

bool SystemControl::launch_system_upgrade() {
    // Used to hardcode "yay -Syu", which fails outright on a --no-aur install
    // with no AUR helper. dotfiles_sys() already has the package-manager
    // fallback chain for exactly this upgrade; reuse it instead of a second,
    // narrower copy that only some install profiles could actually run.
    return dotfiles_sys();
}

// ── Terminal Themes ──────────────────────────────────────────────────────────
std::vector<std::string> SystemControl::term_theme_list() {
    std::vector<std::string> res;
    const char* home = std::getenv("HOME");
    std::string themes_dir = std::string(home ? home : "") + "/.config/b1air-term/themes";

    DIR* dir = opendir(themes_dir.c_str());
    if (!dir) return res;

    struct dirent* entry;
    while ((entry = readdir(dir)) != nullptr) {
        std::string name = entry->d_name;
        if (name.ends_with(".conf")) {
            res.push_back(name.substr(0, name.size() - 5));
        }
    }
    closedir(dir);
    return res;
}

bool SystemControl::term_theme_set(const std::string& theme) {
    const char* home = std::getenv("HOME");
    std::string conf_file = std::string(home ? home : "") + "/.config/b1air-term/term.conf";
    if (theme.empty() || theme.size() > 128 || theme.find_first_not_of("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-.") != std::string::npos || theme.find("..") != std::string::npos) return false;
    std::string theme_file = std::string(home ? home : "") + "/.config/b1air-term/themes/" + theme + ".conf";

    if (access(theme_file.c_str(), R_OK) != 0) {
        std::cerr << "Theme file not found: " << theme_file << "\n";
        return false;
    }

    std::string config = read_file_string(conf_file);
    if (config.empty()) return false;
    std::istringstream lines(config);
    std::ostringstream updated;
    std::string line;
    bool replaced = false;
    while (std::getline(lines, line)) {
        if (line.rfind("include themes/", 0) == 0) {
            updated << "include themes/" << theme << ".conf\n";
            replaced = true;
        } else {
            updated << line << '\n';
        }
    }
    if (!replaced || !write_private_file(conf_file, updated.str())) return false;
    std::cout << "✓ b1air-term theme updated to '" << theme << "'\n";
    return true;
}

// ── Gamepad Idle Inhibitor ───────────────────────────────────────────────────
int SystemControl::run_gamepad_inhibit() {
    std::cout << "[b1air-gamepad] Monitoring joystick activity (/dev/input/js*)...\n";
    while (true) {
        DIR* dir = opendir("/dev/input");
        if (dir) {
            struct dirent* entry;
            while ((entry = readdir(dir)) != nullptr) {
                if (std::strncmp(entry->d_name, "js", 2) == 0) {
                    std::string js_path = std::string("/dev/input/") + entry->d_name;
                    int fd = open(js_path.c_str(), O_RDONLY | O_NONBLOCK);
                    if (fd >= 0) {
                        char buf[64];
                        ssize_t n = read(fd, buf, sizeof(buf));
                        close(fd);
                        if (n > 0) {
                            (void)util::spawn_detached({"systemd-inhibit", "--what=idle", "--who=b1air-gamepad",
                                                     "--why=Gamepad Active", "sleep", "120"});
                        }
                    }
                }
            }
            closedir(dir);
        }
        std::this_thread::sleep_for(std::chrono::seconds(2));
    }
    return 0;
}

// ── Desktop Reload ───────────────────────────────────────────────────────────
bool SystemControl::reload_desktop() {
    SwayIPC ipc;
    if (ipc.connect()) {
        ipc.send_command(0, "reload");
    } else {
        (void)run_argv_status({"swaymsg", "reload"});
    }

    const std::string main_qml = b1air::qml_entry("Main.qml");
    if (!main_qml.empty()) {
        (void)run_argv_status({"qs", "-p", main_qml, "ipc", "call", "main", "forceReload"});
    }
    return true;
}

// ── Equalizer Controls ───────────────────────────────────────────────────────
static std::string eq_state_file() { return runtime_path("eq_state.json"); }

static void ensure_default_eq_state() {
    const std::string path = eq_state_file();
    if (access(path.c_str(), F_OK) != 0) {
        std::ofstream out(path);
        out << "{\"b1\": 0, \"b2\": 0, \"b3\": 0, \"b4\": 0, \"b5\": 0, \"b6\": 0, \"b7\": 0, \"b8\": 0, \"b9\": 0, \"b10\": 0, \"preset\": \"Flat\", \"pending\": false}\n";
        out.close();
    }
}

std::string SystemControl::eq_get_state_json() {
    ensure_default_eq_state();
    std::string s = read_file_string(eq_state_file());
    return s.empty() ? "{\"b1\":0,\"b2\":0,\"b3\":0,\"b4\":0,\"b5\":0,\"b6\":0,\"b7\":0,\"b8\":0,\"b9\":0,\"b10\":0,\"preset\":\"Flat\",\"pending\":false}" : s;
}

bool SystemControl::eq_apply() {
    ensure_default_eq_state();
    std::string cur_state = eq_get_state_json();

    // Extract b1..b10
    std::vector<double> gains(10, 0.0);
    for (int i = 1; i <= 10; ++i) {
        std::string key = "\"b" + std::to_string(i) + "\"";
        size_t p = cur_state.find(key);
        if (p != std::string::npos) {
            size_t colon = cur_state.find(':', p + key.size());
            if (colon != std::string::npos) {
                size_t s = cur_state.find_first_of("0123456789-.", colon + 1);
                if (s != std::string::npos) {
                    size_t e = cur_state.find_first_not_of("0123456789-.", s);
                    std::string val = (e == std::string::npos) ? cur_state.substr(s) : cur_state.substr(s, e - s);
                    try { gains[i - 1] = std::stod(val); } catch (...) {}
                }
            }
        }
    }

    // Set pending = false in EQ_STATE_FILE
    size_t pending_pos = cur_state.find("\"pending\":");
    if (pending_pos != std::string::npos) {
        size_t true_pos = cur_state.find("true", pending_pos);
        if (true_pos != std::string::npos && true_pos - pending_pos < 20) {
            cur_state.replace(true_pos, 4, "false");
            (void)write_private_file(eq_state_file(), cur_state + "\n");
        }
    }

    const char* home = std::getenv("HOME");
    std::string home_str = home ? home : "/tmp";
    mkdir((home_str + "/.config").c_str(), 0755);
    mkdir((home_str + "/.config/easyeffects").c_str(), 0755);
    std::string preset_dir = home_str + "/.config/easyeffects/output";
    mkdir(preset_dir.c_str(), 0755);
    std::string preset_file = preset_dir + "/live_eq.json";

    // 32 bands generation
    const int freqs[32] = {32, 40, 50, 63, 80, 100, 125, 160, 200, 250, 315, 400, 500, 630, 800, 1000, 1250, 1600, 2000, 2500, 3150, 4000, 5000, 6300, 8000, 10000, 12500, 16000, 20000, 22000, 24000, 24000};
    const int slider_map[10] = {0, 3, 6, 9, 12, 15, 18, 21, 24, 27};

    std::stringstream bands_json;
    for (int i = 0; i < 32; ++i) {
        double gain = 0.0;
        for (int s = 0; s < 10; ++s) {
            if (i == slider_map[s]) {
                gain = gains[s];
                break;
            }
        }
        bands_json << "        \"band" << i << "\": {\"frequency\": " << freqs[i] << ".0, \"gain\": " << std::fixed << std::setprecision(1) << gain
                   << ", \"mode\": \"Bell\", \"mute\": false, \"q\": 1.0, \"solo\": false, \"width\": 1.0, \"slope\": \"x1\"}"
                   << (i + 1 < 32 ? ",\n" : "\n");
    }

    std::string bands_str = bands_json.str();
    std::string preset_content = "{\n  \"output\": {\n    \"blocklist\": [],\n    \"plugins_order\": [\"equalizer\"],\n    \"equalizer\": {\n      \"bypass\": false,\n      \"input-gain\": 0.0,\n      \"output-gain\": 0.0,\n      \"left\": {\n" + bands_str + "      },\n      \"right\": {\n" + bands_str + "      },\n      \"mode\": \"IIR\",\n      \"num-bands\": 32,\n      \"split-channels\": false\n    }\n  }\n}\n";

    std::ofstream out(preset_file);
    if (out) {
        out << preset_content;
        out.close();
        (void)util::spawn_detached({"easyeffects", "-l", "live_eq"});
        return true;
    }
    return false;
}

bool SystemControl::eq_set_band(int band_idx, int val) {
    if (band_idx < 1 || band_idx > 10) return false;
    ensure_default_eq_state();
    std::string cur = eq_get_state_json();

    // Parse and update b1..b10
    std::vector<int> b(10, 0);
    for (int i = 1; i <= 10; ++i) {
        std::string key = "\"b" + std::to_string(i) + "\"";
        size_t p = cur.find(key);
        if (p != std::string::npos) {
            size_t colon = cur.find(':', p + key.size());
            if (colon != std::string::npos) {
                size_t s = cur.find_first_of("0123456789-", colon + 1);
                if (s != std::string::npos) {
                    try { b[i - 1] = std::stoi(cur.substr(s)); } catch (...) {}
                }
            }
        }
    }
    b[band_idx - 1] = val;

    std::stringstream out;
    out << "{\"b1\": " << b[0] << ", \"b2\": " << b[1] << ", \"b3\": " << b[2] << ", \"b4\": " << b[3] << ", \"b5\": " << b[4]
        << ", \"b6\": " << b[5] << ", \"b7\": " << b[6] << ", \"b8\": " << b[7] << ", \"b9\": " << b[8] << ", \"b10\": " << b[9]
        << ", \"preset\": \"Custom\", \"pending\": true}\n";

    return write_private_file(eq_state_file(), out.str());
}

bool SystemControl::eq_set_preset(const std::string& preset) {
    std::vector<int> b = {0,0,0,0,0,0,0,0,0,0};
    if (preset == "Flat") b = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0};
    else if (preset == "Bass") b = {5, 7, 5, 2, 1, 0, 0, 0, 1, 2};
    else if (preset == "Treble") b = {-2, -1, 0, 1, 2, 3, 4, 5, 6, 6};
    else if (preset == "Vocal") b = {-2, -1, 1, 3, 5, 5, 4, 2, 1, 0};
    else if (preset == "Pop") b = {2, 4, 2, 0, 1, 2, 4, 2, 1, 2};
    else if (preset == "Rock") b = {5, 4, 2, -1, -2, -1, 2, 4, 5, 6};
    else if (preset == "Jazz") b = {3, 3, 1, 1, 1, 1, 2, 1, 2, 3};
    else if (preset == "Classic") b = {0, 1, 2, 2, 2, 2, 1, 2, 3, 4};
    else b = {0, 0, 0, 0, 0, 0, 0, 0, 0, 0};

    std::stringstream out;
    out << "{\"b1\": " << b[0] << ", \"b2\": " << b[1] << ", \"b3\": " << b[2] << ", \"b4\": " << b[3] << ", \"b5\": " << b[4]
        << ", \"b6\": " << b[5] << ", \"b7\": " << b[6] << ", \"b8\": " << b[7] << ", \"b9\": " << b[8] << ", \"b10\": " << b[9]
        << ", \"preset\": \"" << preset << "\", \"pending\": false}\n";

    (void)write_private_file(eq_state_file(), out.str());
    return eq_apply();
}

bool SystemControl::eq_set_all(const std::vector<int>& bands) {
    if (bands.size() < 10) return false;
    std::stringstream out;
    out << "{\"b1\": " << bands[0] << ", \"b2\": " << bands[1] << ", \"b3\": " << bands[2] << ", \"b4\": " << bands[3] << ", \"b5\": " << bands[4]
        << ", \"b6\": " << bands[5] << ", \"b7\": " << bands[6] << ", \"b8\": " << bands[7] << ", \"b9\": " << bands[8] << ", \"b10\": " << bands[9]
        << ", \"preset\": \"Custom\", \"pending\": false}\n";

    (void)write_private_file(eq_state_file(), out.str());
    return eq_apply();
}

// ── Media Info & Cover Art Processing ────────────────────────────────────────
std::string SystemControl::media_get_info_json() {
    const char* home = std::getenv("HOME");
    std::string home_str = home ? home : "/tmp";
    std::string tmp_dir = home_str + "/.cache/sway/music";
    mkdir(tmp_dir.c_str(), 0755);

    std::string metadata = exec_cmd("playerctl metadata --format '{{status}}\x1f{{mpris:artUrl}}\x1f{{xesam:title}}\x1f{{xesam:artist}}\x1f{{mpris:length}}\x1f{{position}}\x1f{{playerName}}' 2>/dev/null");

    std::string placeholder = tmp_dir + "/placeholder_blank.png";
    if (access(placeholder.c_str(), R_OK) != 0) {
        (void)run_argv_status({"convert", "-size", "500x500", "xc:#313244", placeholder});
    }

    std::string default_grad = "linear-gradient(45deg, #cba6f7, #89b4fa, #f38ba8, #cba6f7)";
    std::string default_text = "#cdd6f4";

    if (metadata.empty()) {
        return "{\"title\":\"Not Playing\",\"artist\":\"\",\"status\":\"Stopped\",\"length\":1,\"position\":0,\"lengthStr\":\"00:01\",\"positionStr\":\"00:00\",\"timeStr\":\"00:00 / 00:01\",\"percent\":0,\"source\":\"Offline\",\"playerName\":\"\",\"blur\":\"" + placeholder + "\",\"grad\":\"" + default_grad + "\",\"textColor\":\"" + default_text + "\",\"deviceIcon\":\"󰓃\",\"deviceName\":\"Speaker\",\"artUrl\":\"" + placeholder + "\"}";
    }

    std::stringstream ss(metadata);
    std::string status, raw_url, title, artist, len_str, pos_str, player_name;
    std::getline(ss, status, '\x1f');
    std::getline(ss, raw_url, '\x1f');
    std::getline(ss, title, '\x1f');
    std::getline(ss, artist, '\x1f');
    std::getline(ss, len_str, '\x1f');
    std::getline(ss, pos_str, '\x1f');
    std::getline(ss, player_name, '\x1f');

    if (status != "Playing" && status != "Paused") status = "Stopped";
    if (title.empty()) title = "Media";

    int64_t len_micro = 1000000;
    int64_t pos_micro = 0;
    try { if (!len_str.empty()) len_micro = std::stoll(len_str); } catch (...) {}
    try { if (!pos_str.empty()) pos_micro = std::stoll(pos_str); } catch (...) {}
    int len_sec = static_cast<int>(len_micro / 1000000);
    if (len_sec <= 0) len_sec = 1;
    int pos_sec = static_cast<int>(pos_micro / 1000000);
    if (pos_sec < 0) pos_sec = 0;
    if (pos_sec > len_sec) pos_sec = len_sec;
    int percent = (pos_sec * 100) / len_sec;

    char l_buf[16], p_buf[16];
    std::snprintf(l_buf, sizeof(l_buf), "%02d:%02d", len_sec / 60, len_sec % 60);
    std::snprintf(p_buf, sizeof(p_buf), "%02d:%02d", pos_sec / 60, pos_sec % 60);
    std::string length_str = l_buf;
    std::string position_str = p_buf;
    std::string time_str = position_str + " / " + length_str;

    // Detect device name
    std::string sink = exec_cmd("pactl get-default-sink 2>/dev/null");
    std::string dev_icon = "󰓃";
    std::string dev_name = "Speaker";
    if (sink.find("bluez") != std::string::npos) {
        dev_icon = "󰂯";
        dev_name = "Bluetooth";
    } else if (sink.find("usb") != std::string::npos) {
        dev_name = "USB Audio";
    } else if (sink.find("pci") != std::string::npos) {
        dev_name = "System";
    }

    // Cover art hashing and async processing
    std::hash<std::string> hasher;
    std::string track_key = title + "-" + artist;
    std::string hash_str = std::to_string(hasher(track_key));
    std::string final_art = tmp_dir + "/" + hash_str + "_art.jpg";
    std::string blur_path = tmp_dir + "/" + hash_str + "_blur.png";
    std::string color_path = tmp_dir + "/" + hash_str + "_grad.txt";
    std::string text_path = tmp_dir + "/" + hash_str + "_text.txt";

    std::string display_art = placeholder;
    std::string display_blur = placeholder;
    std::string display_grad = default_grad;
    std::string display_text = default_text;

    if (access(final_art.c_str(), R_OK) == 0) {
        display_art = final_art;
        if (access(blur_path.c_str(), R_OK) == 0) display_blur = blur_path;
        std::string g = read_file_string(color_path);
        if (!g.empty()) {
            while (!g.empty() && (g.back() == '\n' || g.back() == '\r')) g.pop_back();
            display_grad = g;
        }
        std::string txt = read_file_string(text_path);
        if (!txt.empty()) {
            while (!txt.empty() && (txt.back() == '\n' || txt.back() == '\r')) txt.pop_back();
            display_text = txt;
        }
    } else if (!raw_url.empty()) {
        // Spawn async processor
        std::thread([=]() {
            if (safe_art_url(raw_url) && (raw_url.rfind("http://", 0) == 0 || raw_url.rfind("https://", 0) == 0)) {
                if (!run_argv_status({"curl", "-fsS", "--proto", "=http,https", "--proto-redir", "=http,https",
                                      "--connect-timeout", "3", "--max-time", "10", "--max-filesize", "5242880",
                                      "-o", final_art, raw_url}))
                    (void)run_argv_status({"cp", placeholder, final_art});
            } else if (safe_art_url(raw_url) && raw_url.rfind("file://", 0) == 0) {
                std::string clean = raw_url.substr(7);
                char local_path[PATH_MAX];
                struct stat local_stat{};
                if (!realpath(clean.c_str(), local_path) || stat(local_path, &local_stat) != 0 ||
                    !S_ISREG(local_stat.st_mode) || local_stat.st_size <= 0 || local_stat.st_size > 5 * 1024 * 1024 ||
                    !run_argv_status({"cp", local_path, final_art}))
                    (void)run_argv_status({"cp", placeholder, final_art});
            } else {
                (void)run_argv_status({"cp", placeholder, final_art});
            }
            if (!run_argv_status({"convert", final_art, "-blur", "0x20", "-brightness-contrast", "-30x-10", blur_path}))
                (void)run_argv_status({"cp", final_art, blur_path});
            std::string colors = exec_cmd("convert " + shell_quote(final_art) + " -resize 50x50 -alpha off +dither -quantize RGB -colors 3 -depth 8 -format '%c' histogram:info: 2>/dev/null | grep -E -o '#[0-9A-Fa-f]{6}' | head -n 3 | tr '\\n' ' '");
            std::stringstream css(colors);
            std::string c1, c2, c3;
            css >> c1 >> c2 >> c3;
            if (c1.empty()) c1 = "#cba6f7";
            if (c2.empty()) c2 = c1;
            if (c3.empty()) c3 = c1;
            std::ofstream gout(color_path);
            gout << "linear-gradient(45deg, " << c1 << ", " << c2 << ", " << c3 << ", " << c1 << ")\n";
            gout.close();
            std::ofstream tout(text_path);
            tout << "#cdd6f4\n";
            tout.close();
        }).detach();
    }

    return "{\"title\":\"" + json_escape(title) + "\",\"artist\":\"" + json_escape(artist) + "\",\"status\":\"" + status + "\",\"length\":" + std::to_string(len_sec) + ",\"position\":" + std::to_string(pos_sec) + ",\"lengthStr\":\"" + length_str + "\",\"positionStr\":\"" + position_str + "\",\"timeStr\":\"" + time_str + "\",\"percent\":" + std::to_string(percent) + ",\"source\":\"" + json_escape(player_name) + "\",\"playerName\":\"" + json_escape(player_name) + "\",\"blur\":\"" + json_escape(display_blur) + "\",\"grad\":\"" + json_escape(display_grad) + "\",\"textColor\":\"" + json_escape(display_text) + "\",\"deviceIcon\":\"" + dev_icon + "\",\"deviceName\":\"" + json_escape(dev_name) + "\",\"artUrl\":\"" + json_escape(display_art) + "\"}";
}

// ── Diary & Obsidian Notes ───────────────────────────────────────────────────
bool SystemControl::diary_open() {
    const char* home = std::getenv("HOME");
    std::string vault_dir = std::string(home ? home : "/tmp") + "/Life/Obsidian";

    auto now = std::chrono::system_clock::now();
    auto in_time_t = std::chrono::system_clock::to_time_t(now);
    struct tm* tm = std::localtime(&in_time_t);
    char year[16], day[16], month[16];
    std::strftime(year, sizeof(year), "%Y", tm);
    std::strftime(day, sizeof(day), "%d", tm);
    std::strftime(month, sizeof(month), "%m", tm);

    std::string filename = std::string(day) + "." + month;
    std::string diary_year_dir = vault_dir + "/Diary/" + year;
    mkdir(vault_dir.c_str(), 0755);
    mkdir((vault_dir + "/Diary").c_str(), 0755);
    mkdir(diary_year_dir.c_str(), 0755);

    std::string note_file = diary_year_dir + "/" + filename + ".md";
    if (access(note_file.c_str(), F_OK) != 0) {
        std::ofstream out(note_file);
        out << "#diary\n\n";
        out.close();
    }

    std::string contents_file = vault_dir + "/Diary/Contents.md";
    std::string contents = read_file_string(contents_file);
    std::string link_entry = "[[" + filename + "]]";

    if (contents.empty()) {
        std::ofstream out(contents_file);
        out << "## " << year << "\n- " << link_entry << "\n";
        out.close();
    } else if (contents.find(link_entry) == std::string::npos) {
        std::string year_header = "## " + std::string(year);
        size_t ypos = contents.find(year_header);
        if (ypos != std::string::npos) {
            size_t next_line = contents.find('\n', ypos);
            if (next_line != std::string::npos) {
                contents.insert(next_line + 1, "- " + link_entry + "\n");
            } else {
                contents += "\n- " + link_entry + "\n";
            }
        } else {
            contents += "\n## " + std::string(year) + "\n- " + link_entry + "\n";
        }
        std::ofstream out(contents_file);
        out << contents;
        out.close();
    }

    std::string uri = "obsidian://open?vault=Obsidian&file=Diary/" + std::string(year) + "/" + filename;
    return util::spawn_detached({"xdg-open", uri});
}

// ── Calendar Schedule ────────────────────────────────────────────────────────
std::string SystemControl::schedule_get_json() {
    const char* home = std::getenv("HOME");
    std::string cache_dir = std::string(home ? home : "/tmp") + "/.cache/quickshell/schedule";
    mkdir(cache_dir.c_str(), 0755);
    std::string cache_file = cache_dir + "/schedule.json";

    if (access(cache_file.c_str(), R_OK) == 0) {
        std::string content = read_file_string(cache_file);
        if (!content.empty()) return content;
    }

    std::string fallback = "{ \"header\": \"No Classes Scheduled\", \"lessons\": [], \"link\": \"\" }";
    std::ofstream out(cache_file);
    if (out) {
        out << fallback << "\n";
        out.close();
    }
    return fallback;
}

// ── Dotfiles Git Sync & Diff ─────────────────────────────────────────────────
static std::string find_dotfiles_repo() {
    const char* home = std::getenv("HOME");
    std::string home_str = home ? home : "";

    // install.sh records the real clone path here, so a repo cloned anywhere
    // at all is found — not just one that happens to sit in one of a handful
    // of guessed locations (one of which was a specific developer's own
    // ~/Documents/GitHub path).
    std::string state_file = home_str + "/.local/state/b1air/dotfiles-repo";
    std::ifstream in(state_file);
    if (in) {
        std::string recorded;
        std::getline(in, recorded);
        if (!recorded.empty() && access((recorded + "/.git").c_str(), F_OK) == 0) {
            return recorded;
        }
    }

    // Fallback for a repo that predates install.sh recording its path.
    std::vector<std::string> candidates = {
        home_str + "/Documents/GitHub/DotsFiles",
        home_str + "/GitHub/DotsFiles",
        home_str + "/DotsFiles",
        home_str + "/.local/src/dotfiles"
    };
    for (const auto& c : candidates) {
        if (access((c + "/.git").c_str(), F_OK) == 0) {
            return c;
        }
    }
    return "";
}

std::string SystemControl::dotfiles_status_json() {
    std::string repo = find_dotfiles_repo();
    if (repo.empty()) {
        return "{\"ok\":false,\"error\":\"repo_not_found\"}";
    }

    // Was run_argv_detached — fire-and-forget, so the reads just below could
    // (and often would) run before the fetch actually landed, showing a
    // stale remote_hash right after opening the updater. Block on it.
    //
    // Never prompt: the daemon has no terminal, and a remote that wants a
    // password or an unknown SSH host key would hang the check — and the
    // updater window waiting on it — until the fetch gave up. A failed fetch
    // is reported (fetch_ok) so the window can say the answer may be stale
    // instead of claiming "up to date".
    const std::string fetch_out = exec_cmd(
        "GIT_TERMINAL_PROMPT=0 GIT_SSH_COMMAND='ssh -o BatchMode=yes' git -C " + shell_quote(repo) +
        " fetch --quiet origin 2>&1; echo \"rc=$?\"");
    const bool fetch_ok = fetch_out.size() >= 4 && fetch_out.compare(fetch_out.size() - 4, 4, "rc=0") == 0;

    std::string branch = exec_cmd("git -C " + shell_quote(repo) + " rev-parse --abbrev-ref HEAD 2>/dev/null");
    if (branch.empty()) branch = "main";
    std::string local_hash = exec_cmd("git -C " + shell_quote(repo) + " rev-parse --short HEAD 2>/dev/null");
    std::string remote_ref = exec_cmd("git -C " + shell_quote(repo) + " rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null");
    if (remote_ref.empty()) remote_ref = "origin/main";
    std::string remote_hash = exec_cmd("git -C " + shell_quote(repo) + " rev-parse --short " + shell_quote(remote_ref) + " 2>/dev/null");

    // The changelog line used to come from a hardcoded
    // api.github.com/repos/bla1r1/DotsFiles call — dead weight (a second
    // network round-trip for something `git fetch` above already retrieved)
    // and it would silently go stale the moment the repo moved or was
    // renamed. `git log` already has the answer locally, for whatever
    // remote `origin` actually points at right now.
    std::string remote_message = exec_cmd("git -C " + shell_quote(repo) + " log -1 --pretty=%s " +
                                          shell_quote(remote_ref) + " 2>/dev/null");

    // `local_hash != remote_hash` cannot tell "there is something to pull" from
    // "there is something to push", and the two are opposite answers. A
    // checkout with local commits not yet pushed — the normal state of this
    // repository between a commit and a push — reported an update as available
    // and drew the arrow backwards, from the newer local commit to the older
    // remote one, offering to "update" to a revision that predates what is
    // installed. Measured at twelve commits ahead and none behind: it said
    // update_available true.
    //
    // --left-right --count over a symmetric difference answers both at once:
    // the left number is what the remote has and this checkout does not, the
    // right number is the reverse. Only the left one is an update.
    long behind = 0, ahead = 0;
    {
        const std::string counts = exec_cmd("git -C " + shell_quote(repo) +
                                            " rev-list --left-right --count " +
                                            shell_quote(remote_ref + "...HEAD") + " 2>/dev/null");
        std::istringstream in(counts);
        in >> behind >> ahead;
    }

    bool update_available = (!remote_hash.empty() && behind > 0);

    // What an update would bring: one line per incoming commit, newest first.
    // Only the newest subject used to be shown, so ten incoming changes and
    // one looked the same.
    std::string incoming = "[";
    if (behind > 0) {
        const std::string log = exec_cmd("git -C " + shell_quote(repo) +
                                         " log --no-merges -n 30 --pretty=format:%h%x1f%s " +
                                         shell_quote("HEAD.." + remote_ref) + " 2>/dev/null");
        std::istringstream lines(log);
        std::string line;
        bool first = true;
        while (std::getline(lines, line)) {
            const size_t sep = line.find('\x1f');
            if (sep == std::string::npos) continue;
            incoming += std::string(first ? "" : ",") + "{\"hash\":\"" + json_escape(line.substr(0, sep)) +
                        "\",\"subject\":\"" + json_escape(line.substr(sep + 1)) + "\"}";
            first = false;
        }
    }
    incoming += "]";

    // Uncommitted edits to tracked files make `git pull --ff-only` refuse, so
    // the window warns before the update rather than the update failing.
    const bool dirty = !exec_cmd("git -C " + shell_quote(repo) + " status --porcelain -uno 2>/dev/null").empty();

    return "{\"ok\":true,\"fetch_ok\":" + std::string(fetch_ok ? "true" : "false") +
           ",\"dirty\":" + (dirty ? "true" : "false") + ",\"incoming\":" + incoming + ","
           "\"repo_dir\":\"" + json_escape(repo) + "\",\"branch\":\"" + json_escape(branch) + "\",\"local_hash\":\"" + local_hash + "\",\"remote_hash\":\"" + remote_hash + "\",\"remote_ref\":\"" + json_escape(remote_ref) + "\",\"remote_message\":\"" + json_escape(remote_message) + "\",\"behind\":" + std::to_string(behind) + ",\"ahead\":" + std::to_string(ahead) + ",\"update_available\":" + (update_available ? "true" : "false") + "}";
}

bool SystemControl::dotfiles_sync() {
    std::string repo = find_dotfiles_repo();
    if (repo.empty()) return false;
    // --pull: update-dotfiles.sh leaves git alone unless asked, and this never
    // asked — so "Update" rebuilt and redeployed the commit already checked
    // out, and the updater still said N changes behind afterwards.
    std::string script = "bash " + shell_quote(repo + "/update-dotfiles.sh") + " --pull --repo-dir " + shell_quote(repo) + "; printf '\\nPress Enter to close...\\n'; read -r _";
    // bash, not fish: `read -r` is not a fish builtin option, so the window
    // closed on an error instead of waiting for Enter.
    return util::spawn_detached({"b1air-term", "-e", "bash", "-lc", script});
}

bool SystemControl::dotfiles_sys() {
    // Was handed to `fish -lc`, which has no `if ...; then ...; fi`: the
    // upgrade window printed a syntax error and never ran anything.
    const std::string script = "if command -v yay >/dev/null 2>&1; then yay -Syu; "
                              "elif command -v paru >/dev/null 2>&1; then paru -Syu; "
                              "elif command -v pacman >/dev/null 2>&1; then sudo pacman -Syu; "
                              "elif command -v apt-get >/dev/null 2>&1; then sudo apt-get update && sudo apt-get upgrade; "
                              "elif command -v dnf >/dev/null 2>&1; then sudo dnf upgrade --refresh; "
                              "elif command -v zypper >/dev/null 2>&1; then sudo zypper refresh && sudo zypper dup; "
                              "else echo 'No supported package manager found.'; fi; "
                              "printf '\\nPress Enter to close...\\n'; read -r _";
    return util::spawn_detached({"b1air-term", "-e", "bash", "-lc", script});
}

// ── Screen Capture, Recording & QR Scanner ───────────────────────────────────

// ScreenshotOverlay.qml is a full interactive selection/edit/record UI — its
// own capture button already shells out to `b1air-daemon capture --geometry
// ...`, the same function below. Nothing pointed a keybind at the overlay
// itself, though, so the whole file sat unreachable; Print instead called
// capture() directly with a blind, non-interactive slurp selection.
bool SystemControl::run_screenshot_overlay(bool edit_mode) {
    const std::string qml = b1air::qml_entry("ScreenshotOverlay.qml");
    if (qml.empty()) return false;
    std::vector<std::string> argv = {"quickshell", "-p", qml};
    if (edit_mode) argv = {"env", "QS_SCREENSHOT_EDIT=true", "quickshell", "-p", qml};
    return util::spawn_detached(argv);
}

bool SystemControl::capture(const std::string& mode, const std::string& geom, bool edit, int delay_override) {
    if (!geom.empty() && !valid_geometry(geom)) return false;

    // Settings → Screenshots offers a folder, a format, a delay and switches
    // for saving and copying. None of them reached here: this function wrote
    // Screenshot_<time>.png into ~/Pictures/Screenshots, always, and always
    // copied to the clipboard. Five controls storing values nothing read.
    const char* home = std::getenv("HOME");
    const std::string home_dir = std::string(home ? home : "/tmp");

    std::string target_dir = SettingsManager::get_json_string("screenshotDir");
    if (target_dir.empty()) target_dir = home_dir + "/Pictures/Screenshots";
    if (target_dir.rfind("~/", 0) == 0) target_dir = home_dir + target_dir.substr(1);

    std::string format = SettingsManager::get_json_string("screenshotFormat");
    std::transform(format.begin(), format.end(), format.begin(),
                   [](unsigned char c) { return std::tolower(c); });
    if (format != "jpg" && format != "jpeg" && format != "webp") format = "png";

    // A delay on the command line wins over the setting: that is how the
    // delayed-shot keys (Mod+Ctrl+Print, 5 s; Mod+Ctrl+Shift+Print, 10 s) ask
    // for theirs without changing what plain Print does.
    const int delay = std::max(0, std::min(60, delay_override >= 0 ? delay_override
                                               : SettingsManager::get_json_int("screenshotDelay", 0)));
    const bool to_file = SettingsManager::get_json_bool("screenshotSaveToFile", true);
    const bool to_clipboard = SettingsManager::get_json_bool("screenshotCopyToClipboard", true);

    if (!util::mkdir_p(target_dir)) {
        notify_user("Screenshot", "Cannot write there", target_dir, "");
        return false;
    }

    auto now = std::chrono::system_clock::now();
    auto in_time_t = std::chrono::system_clock::to_time_t(now);
    std::stringstream ss;
    ss << std::put_time(std::localtime(&in_time_t), "%Y-%m-%d_%H-%M-%S");
    std::string timestamp = ss.str();

    // Turning both switches off would throw the capture away, so the file is
    // still written; a screenshot that goes nowhere is not a setting anyone
    // means to choose. Editing needs a real file on disk in any case.
    const bool keep_file = to_file || !to_clipboard || edit;
    const std::string ext = (format == "jpg") ? "jpeg" : format;
    std::string filepath = keep_file
        ? target_dir + "/Screenshot_" + timestamp + "." + ext
        : runtime_dir() + "/screenshot-" + timestamp + "." + ext;

    std::string selected = geom;
    if (selected.empty() && mode == "area") selected = run_argv_capture({"slurp"});
    if (!selected.empty() && !valid_geometry(selected)) return false;
    if (selected.empty() && mode == "window") {
        // This used to look for the bytes "focused":true and then walk
        // backwards to the nearest "rect": . Sway pretty-prints its IPC
        // replies, so the text is "focused": true — with a space — and the
        // search matched nothing on any machine: Super+Shift+Print, which the
        // README and the shortcut sheet both document, has never taken a
        // screenshot. Walking the parsed tree also picks the focused node's
        // own rect rather than whichever one happened to sit above it.
        SwayIPC ipc;
        if (!ipc.connect()) return false;
        const std::string tree = ipc.get_tree();

        std::function<const nlohmann::json*(const nlohmann::json&)> find_focused =
            [&](const nlohmann::json& node) -> const nlohmann::json* {
                if (node.value("focused", false) && node.contains("rect"))
                    return &node;
                for (const char* key : {"nodes", "floating_nodes"}) {
                    if (!node.contains(key) || !node[key].is_array()) continue;
                    for (const auto& child : node[key])
                        if (const auto* hit = find_focused(child)) return hit;
                }
                return nullptr;
            };

        try {
            const auto parsed = nlohmann::json::parse(tree);
            const auto* node = find_focused(parsed);
            if (!node) return false;
            const auto& r = (*node)["rect"];
            selected = std::to_string(r.value("x", 0)) + "," + std::to_string(r.value("y", 0))
                     + " " + std::to_string(r.value("width", 0)) + "x"
                     + std::to_string(r.value("height", 0));
        } catch (const std::exception&) { return false; }
    }
    // After the selection, not before it: the delay exists so a menu can be
    // opened and left open while the shot is taken.
    if (delay > 0) sleep(static_cast<unsigned int>(delay));

    std::vector<std::string> grim_args = {"grim"};
    // grim writes png and jpeg itself; webp is converted afterwards.
    grim_args.push_back("-t");
    grim_args.push_back(format == "webp" ? "png" : ext);
    if (!selected.empty()) { grim_args.push_back("-g"); grim_args.push_back(selected); }
    grim_args.push_back(filepath);
    if (!run_argv_status(grim_args)) return false;

    if (format == "webp") {
        // imagemagick is already a declared dependency. If the conversion
        // fails the PNG stays where it is rather than the capture being lost.
        (void)run_argv_status({"magick", filepath, filepath});
    }

    const std::string mime = (format == "png") ? "image/png"
                           : (format == "webp") ? "image/webp" : "image/jpeg";

    if (edit) {
        if (!run_argv_status_env({"satty", "--filename", filepath, "--output-filename", filepath,
                                  "--init-tool", "brush", "--copy-command", "wl-copy"},
                                 {{"GSK_RENDERER", "gl"}})) return false;
    } else if (to_clipboard) {
        const std::string image = read_file_string(filepath);
        if (image.empty() || !run_argv_with_raw_stdin({"wl-copy", "-t", mime}, image)) return false;
    }

    if (!keep_file) {
        unlink(filepath.c_str());
        play_feedback_sound("soundScreenshotFeedback", "camera-shutter");
        notify_user("Screenshot", "Copied to clipboard", "", "");
        return true;
    }

    play_feedback_sound("soundScreenshotFeedback", "camera-shutter");
    notify_user("Screenshot", "Screenshot Saved", filepath, filepath);
    return true;
}

bool SystemControl::record_stop() {
    std::string cache_dir = runtime_dir();
    std::string pid_file = cache_dir + "/rec_pid";

    if (access(pid_file.c_str(), R_OK) == 0) {
        std::string pid_str = read_file_string(pid_file);
        while (!pid_str.empty() && (pid_str.back() == '\n' || pid_str.back() == '\r')) pid_str.pop_back();

        auto decimal_id = [](const std::string& s) {
            if (s.empty() || s.size() > 10) return false;
            for (char c : s) if (c < '0' || c > '9') return false;
            return true;
        };
        if (decimal_id(pid_str) && pid_str != "0") {
            errno = 0;
            const long parsed_pid = std::strtol(pid_str.c_str(), nullptr, 10);
            const pid_t pid = static_cast<pid_t>(parsed_pid);
            if (errno != 0 || parsed_pid <= 0 || parsed_pid > INT_MAX) return false;
            (void)::kill(pid, SIGINT);
            std::this_thread::sleep_for(std::chrono::milliseconds(500));
            (void)::kill(pid, SIGKILL);
        }

        std::string pw_modules = cache_dir + "/pw_modules";
        std::ifstream in(pw_modules);
        if (in) {
            std::string mod_id;
            while (std::getline(in, mod_id)) {
                if (decimal_id(mod_id)) {
                    (void)run_argv_capture({"pactl", "unload-module", mod_id});
                }
            }
            in.close();
            unlink(pw_modules.c_str());
        }

        unlink(pid_file.c_str());
        std::string final_file = read_file_string(cache_dir + "/final_file");
        unlink((cache_dir + "/final_file").c_str());
        unlink((cache_dir + "/processing.lock").c_str());

        if (!final_file.empty()) {
            (void)run_argv_capture({"notify-send", "-a", "Screen Recorder", "-i", final_file,
                                     "⏺ Recording Saved", final_file});
        }
        return true;
    }
    return false;
}

bool SystemControl::record_toggle(const std::string& geom, double desk_vol, double mic_vol, bool desk_mute, bool mic_mute, const std::string& mic_dev) {
    const char* home = std::getenv("HOME");
    std::string cache_dir = runtime_dir();
    std::string pid_file = cache_dir + "/rec_pid";

    if (access(pid_file.c_str(), R_OK) == 0) {
        return record_stop();
    }

    std::string record_dir = std::string(home ? home : "/tmp") + "/Videos/Recordings";
    mkdir(record_dir.c_str(), 0755);

    auto now = std::chrono::system_clock::now();
    auto in_time_t = std::chrono::system_clock::to_time_t(now);
    std::stringstream ss;
    ss << std::put_time(std::localtime(&in_time_t), "%Y-%m-%d-%H%M%S");
    std::string vid_file = record_dir + "/Recording_" + ss.str() + ".mp4";

    std::string audio_mix;
    const std::string modules_path = cache_dir + "/pw_modules";
    const int modules_fd = open(modules_path.c_str(), O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC | O_NOFOLLOW, 0600);
    if (modules_fd < 0) return false;

    if (!desk_mute) {
        std::string desk_sink = exec_cmd("pactl get-default-sink 2>/dev/null");
        if (!desk_sink.empty()) {
            std::string sink_id = exec_cmd("pactl load-module module-null-sink sink_name=qs_virt_desk 2>/dev/null");
            std::string loop_id = run_argv_capture({"pactl", "load-module", "module-loopback",
                                                     "source=" + desk_sink + ".monitor", "sink=qs_virt_desk"});
            int vol_int = static_cast<int>(desk_vol * 65536);
            (void)run_argv_status({"pactl", "set-sink-volume", "qs_virt_desk", std::to_string(vol_int)});
            (void)write_fd_all(modules_fd, sink_id + "\n" + loop_id + "\n");
            audio_mix += "qs_virt_desk.monitor|";
        }
    }

    if (!mic_mute) {
        std::string source = (!mic_dev.empty() && mic_dev != "null") ? mic_dev : exec_cmd("pactl get-default-source 2>/dev/null");
        if (!source.empty()) {
            std::string sink_id = exec_cmd("pactl load-module module-null-sink sink_name=qs_virt_mic 2>/dev/null");
            std::string loop_id = run_argv_capture({"pactl", "load-module", "module-loopback",
                                                     "source=" + source, "sink=qs_virt_mic"});
            int vol_int = static_cast<int>(mic_vol * 65536);
            (void)run_argv_status({"pactl", "set-sink-volume", "qs_virt_mic", std::to_string(vol_int)});
            (void)write_fd_all(modules_fd, sink_id + "\n" + loop_id + "\n");
            audio_mix += "qs_virt_mic.monitor|";
        }
    }
    fchmod(modules_fd, 0600);
    close(modules_fd);

    if (!audio_mix.empty() && audio_mix.back() == '|') audio_mix.pop_back();

    std::vector<std::string> gsr_args = {"gpu-screen-recorder", "-w", "portal", "-c", "mp4", "-f", "60"};
    if (!audio_mix.empty()) { gsr_args.push_back("-a"); gsr_args.push_back(audio_mix); }
    if (!geom.empty()) { gsr_args.push_back("-g"); gsr_args.push_back(geom); }
    gsr_args.push_back("-o"); gsr_args.push_back(vid_file);
    const pid_t recorder_pid = spawn_argv_detached(gsr_args);
    if (recorder_pid <= 0 || !write_private_file(pid_file, std::to_string(recorder_pid) + "\n") ||
        !write_private_file(cache_dir + "/final_file", vid_file + "\n")) return false;

    notify_user("Screen Recorder", "⏺ Recording Started", "Recording in progress...");
    return true;
}

std::string SystemControl::scan_qr(const std::string& geom) {
    if (!geom.empty() && !valid_geometry(geom)) return "";
    std::string tmp_img = runtime_path(("qr-scan-" + std::to_string(getpid()) + ".png").c_str());
    std::vector<std::string> grim_args = {"grim"};
    if (!geom.empty()) { grim_args.push_back("-g"); grim_args.push_back(geom); }
    grim_args.push_back(tmp_img);
    if (!run_argv_status(grim_args)) return "";

    std::string xml = run_argv_capture({"zbarimg", "--xml", "-q", tmp_img});
    unlink(tmp_img.c_str());

    std::string res_file = runtime_path("qr_result");
    if (xml.empty()) {
        (void)write_private_file(res_file, "0,0,0,0|||NOT_FOUND\n");
        return "0,0,0,0|||NOT_FOUND";
    }

    // Parse XML: extract <symbol> <data> and <polygon points="...">
    size_t sym_pos = xml.find("<symbol");
    if (sym_pos == std::string::npos) {
        (void)write_private_file(res_file, "0,0,0,0|||NOT_FOUND\n");
        return "0,0,0,0|||NOT_FOUND";
    }

    std::string data_text;
    size_t data_pos = xml.find("<data", sym_pos);
    if (data_pos != std::string::npos) {
        size_t tag_end = xml.find('>', data_pos);
        size_t close_tag = xml.find("</data>", tag_end);
        if (tag_end != std::string::npos && close_tag != std::string::npos) {
            data_text = xml.substr(tag_end + 1, close_tag - (tag_end + 1));
        }
    }

    int min_x = 99999, min_y = 99999, max_x = 0, max_y = 0;
    size_t poly_pos = xml.find("points=\"", sym_pos);
    if (poly_pos != std::string::npos) {
        size_t q_end = xml.find('"', poly_pos + 8);
        if (q_end != std::string::npos) {
            std::string pts_str = xml.substr(poly_pos + 8, q_end - (poly_pos + 8));
            std::stringstream pss(pts_str);
            std::string pair;
            while (pss >> pair) {
                size_t comma = pair.find(',');
                if (comma != std::string::npos) {
                    try {
                        int x = std::stoi(pair.substr(0, comma));
                        int y = std::stoi(pair.substr(comma + 1));
                        min_x = std::min(min_x, x);
                        min_y = std::min(min_y, y);
                        max_x = std::max(max_x, x);
                        max_y = std::max(max_y, y);
                    } catch (...) {}
                }
            }
        }
    }

    if (min_x == 99999) { min_x = 0; min_y = 0; max_x = 0; max_y = 0; }
    int w = max_x - min_x;
    int h = max_y - min_y;

    // Clean data text
    std::string clean_data;
    for (char c : data_text) {
        if (c == '\n') clean_data += "\\n";
        else if (c != '\r') clean_data += c;
    }

    std::string result = std::to_string(min_x) + "," + std::to_string(min_y) + "," + std::to_string(w) + "," + std::to_string(h) + "|||" + clean_data;
    (void)write_private_file(res_file, result + "\n");
    return result;
}

// ── Native Polkit Agent & Authentication Dialog ──────────────────────────────
std::string SystemControl::polkit_prompt_dialog(const std::string& action_id, const std::string& message,
                                                const std::string& user, const std::string& cookie) {
    // Authentication UI must not be loaded from a user-writable QML tree:
    // replacing it would turn the Polkit agent into a password stealer.
    const std::string qml_candidates[] = {
        "/usr/local/share/b1air-shell/qml/polkit/PolkitDialog.qml",
        "/usr/share/b1air-shell/qml/polkit/PolkitDialog.qml"
    };
    std::string qml_path;
    for (const auto& candidate : qml_candidates) {
        struct stat st{};
        if (stat(candidate.c_str(), &st) == 0 && S_ISREG(st.st_mode) &&
            st.st_uid == 0 && (st.st_mode & 022) == 0) {
            qml_path = candidate;
            break;
        }
    }
    if (qml_path.empty()) return "";
    
    std::string resp_template = runtime_path("polkit-response-XXXXXX");
    std::vector<char> resp_buf(resp_template.begin(), resp_template.end());
    resp_buf.push_back('\0');
    int response_fd = mkstemp(resp_buf.data());
    if (response_fd < 0) return "";
    std::string resp_file(resp_buf.data());
    fchmod(response_fd, 0600);
    close(response_fd);
    unlink(resp_file.c_str());

    std::string target_user = user.empty() ? (std::getenv("USER") ? std::getenv("USER") : "root") : user;

    if (!run_argv_status_env({"quickshell", "-p", qml_path}, {
            {"POLKIT_ACTION", action_id}, {"POLKIT_MESSAGE", message},
            {"POLKIT_USER", target_user}, {"POLKIT_COOKIE", cookie},
            {"POLKIT_RESP_FILE", resp_file}})) {
        unlink(resp_file.c_str());
        return "";
    }

    // Wait for response file (up to 30s)
    std::string password = "";
    for (int i = 0; i < 300; ++i) {
        if (access(resp_file.c_str(), F_OK) == 0) {
            std::ifstream in(resp_file);
            if (in) {
                std::stringstream buffer;
                buffer << in.rdbuf();
                password = buffer.str();
            }
            unlink(resp_file.c_str());
            break;
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
    }

    if (password == "CANCELLED\n" || password == "CANCELLED") return "";
    while (!password.empty() && (password.back() == '\n' || password.back() == '\r')) {
        password.pop_back();
    }
    return password;
}

int SystemControl::polkit_agent_run() {
    std::cerr << "Use b1air-polkit-agent for the registered graphical Polkit listener\n";
    return 1;
}

bool SystemControl::polkit_write_response(const std::string& path, const std::string& response) {
    const std::string prefix = runtime_dir() + "/";
    if (path.rfind(prefix, 0) != 0 || path.find("..") != std::string::npos) return false;
    const int fd = open(path.c_str(), O_WRONLY | O_CREAT | O_TRUNC | O_NOFOLLOW | O_CLOEXEC, 0600);
    if (fd < 0) return false;
    size_t written = 0;
    while (written < response.size()) {
        const ssize_t count = write(fd, response.data() + written, response.size() - written);
        if (count <= 0) { close(fd); return false; }
        written += static_cast<size_t>(count);
    }
    fchmod(fd, 0600);
    close(fd);
    return true;
}

// ── Remote Desktop (WayVNC) & Screencast Management ───────────────────────────
bool SystemControl::remote_desktop_start(int port, const std::string& password) {
    if (port < 1024 || port > 65535 || password.size() > 256) return false;
    for (unsigned char c : password) {
        if (c < 0x21 || c == 0x7f || c == '\n' || c == '\r') return false;
    }

    SecretStore secrets;
    if (!password.empty() && !secrets.set("vnc-password", password)) return false;
    std::string vnc_password;
    if (!secrets.get("vnc-password", vnc_password) || vnc_password.empty()) {
        std::cerr << "WayVNC password is not configured; refusing unauthenticated start\n";
        return false;
    }

    remote_desktop_stop();
    const char* bind = std::getenv("B1AIR_DEV_MODE");
    const char* unsafe_bind = std::getenv("B1AIR_DEV_VNC_UNSAFE");
    const bool unsafe_dev_bind = bind && std::string(bind) == "1" && unsafe_bind && std::string(unsafe_bind) == "1";
    std::string bind_address = unsafe_dev_bind ? "0.0.0.0" : "127.0.0.1";
    if (unsafe_dev_bind) std::cerr << "WARNING: WayVNC is intentionally exposed on all interfaces in unsafe dev mode\n";

    const std::string tls_key = runtime_path("wayvnc-tls.key");
    const std::string tls_cert = runtime_path("wayvnc-tls.crt");
    if (access(tls_key.c_str(), R_OK) != 0 || access(tls_cert.c_str(), R_OK) != 0) {
        (void)run_argv_capture({"openssl", "req", "-x509", "-newkey", "ed25519", "-nodes",
                                 "-keyout", tls_key, "-out", tls_cert, "-days", "2",
                                 "-subj", "/CN=b1air-wayvnc"});
    }
    struct stat key_stat{}, cert_stat{};
    if (stat(tls_key.c_str(), &key_stat) != 0 || stat(tls_cert.c_str(), &cert_stat) != 0 ||
        !S_ISREG(key_stat.st_mode) || !S_ISREG(cert_stat.st_mode)) return false;
    chmod(tls_key.c_str(), 0600);
    chmod(tls_cert.c_str(), 0600);

    // WayVNC needs the password in its config while running. The config is
    // ephemeral, mode 0600, and lives below the private runtime directory.
    const std::string config_path = runtime_path("wayvnc.conf");
    // wayvnc refuses to start with auth on and no username ("Authentication
    // enabled, but missing username"), and this config never had one — so
    // the server exited the moment it was launched, every time. The login
    // name is what a VNC client's user field expects anyway.
    const struct passwd* pw = getpwuid(getuid());
    const std::string vnc_user = pw && pw->pw_name ? pw->pw_name : "b1air";
    char config_text[4096];
    const int config_size = std::snprintf(config_text, sizeof(config_text),
        "address=%s\nport=%d\nenable_auth=true\nrelax_encryption=false\n"
        "certificate_file=%s\nprivate_key_file=%s\nusername=%s\npassword=%s\n",
        bind_address.c_str(), port, tls_cert.c_str(), tls_key.c_str(), vnc_user.c_str(), vnc_password.c_str());
    const bool config_written = config_size >= 0 && static_cast<size_t>(config_size) < sizeof(config_text) &&
        write_private_file(config_path, std::string(config_text, static_cast<size_t>(config_size)));
    OPENSSL_cleanse(config_text, sizeof(config_text));
    if (!config_written) return false;

    const std::string pid_file = runtime_path("wayvnc.pid");
    const std::string log_path = runtime_path("wayvnc.log");
    const pid_t child = fork();
    if (child < 0) return false;
    if (child == 0) {
        (void)setsid();
        const int log_fd = open(log_path.c_str(), O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC | O_NOFOLLOW, 0600);
        const int null_fd = open("/dev/null", O_RDONLY | O_CLOEXEC);
        if (log_fd < 0 || null_fd < 0) _exit(126);
        dup2(null_fd, STDIN_FILENO);
        dup2(log_fd, STDOUT_FILENO);
        dup2(log_fd, STDERR_FILENO);
        if (null_fd > STDERR_FILENO) close(null_fd);
        if (log_fd > STDERR_FILENO) close(log_fd);
        execlp("wayvnc", "wayvnc", "--render-cursor", "-C", config_path.c_str(), nullptr);
        _exit(127);
    }
    if (!write_private_file(pid_file, std::to_string(child) + "\n")) {
        (void)::kill(child, SIGTERM);
        return false;
    }
    return true;
}

bool SystemControl::remote_desktop_stop() {
    const std::string pid_file = runtime_path("wayvnc.pid");
    const pid_t pid = runtime_pid(pid_file);
    if (pid > 0) {
        (void)::kill(pid, SIGTERM);
        std::this_thread::sleep_for(std::chrono::milliseconds(150));
        (void)::kill(pid, SIGKILL);
    }
    unlink(pid_file.c_str());
    // The config contains the VNC password. It must not survive the server.
    unlink(runtime_path("wayvnc.conf").c_str());
    unlink(runtime_path("wayvnc-tls.key").c_str());
    unlink(runtime_path("wayvnc-tls.crt").c_str());
    return true;
}

bool SystemControl::remote_desktop_toggle() {
    const pid_t pid = runtime_pid(runtime_path("wayvnc.pid"));
    if (pid > 0 && ::kill(pid, 0) == 0) {
        return remote_desktop_stop();
    } else {
        return remote_desktop_start();
    }
}

// Established TCP connections whose local port is `port`, from the kernel's
// own tables — no wayvncctl, which not every wayvnc build ships.
static int count_established_on_port(int port) {
    int n = 0;
    for (const char* table : {"/proc/net/tcp", "/proc/net/tcp6"}) {
        std::ifstream in(table);
        std::string line;
        std::getline(in, line);                       // header
        while (std::getline(in, line)) {
            std::istringstream row(line);
            std::string slot, local, remote, state;
            if (!(row >> slot >> local >> remote >> state)) continue;
            const size_t colon = local.rfind(':');
            if (colon == std::string::npos || state != "01") continue;   // 01 = ESTABLISHED
            if (std::stoi(local.substr(colon + 1), nullptr, 16) == port) ++n;
        }
    }
    return n;
}

// The port the running server was started on, from its config.
static int running_vnc_port(const std::string& config_path) {
    std::ifstream in(config_path);
    std::string line;
    while (std::getline(in, line))
        if (line.rfind("port=", 0) == 0) {
            try { return std::stoi(line.substr(5)); } catch (...) {}
        }
    return 5900;
}

std::string SystemControl::remote_desktop_status_json() {
    const pid_t pid = runtime_pid(runtime_path("wayvnc.pid"));
    bool running = pid > 0 && ::kill(pid, 0) == 0;
    if (!running) {
        unlink(runtime_path("wayvnc.pid").c_str());
        unlink(runtime_path("wayvnc.conf").c_str());
        unlink(runtime_path("wayvnc-tls.key").c_str());
        unlink(runtime_path("wayvnc-tls.crt").c_str());
    }
    const char* bind = std::getenv("B1AIR_DEV_MODE");
    bool dev_mode = bind && std::string(bind) == "1";
    std::string ip = dev_mode ? exec_cmd("ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}'") : "127.0.0.1";
    while (!ip.empty() && (ip.back() == '\n' || ip.back() == '\r' || ip.back() == ' ')) ip.pop_back();
    if (ip.empty()) ip = "127.0.0.1";
    
    std::string json = "{";
    const int port = running ? running_vnc_port(runtime_path("wayvnc.conf")) : 5900;
    json += "\"running\":" + std::string(running ? "true" : "false") + ",";
    json += "\"port\":" + std::to_string(port) + ",";
    json += "\"clients\":" + std::to_string(running ? count_established_on_port(port) : 0) + ",";
    json += "\"available\":" + std::string(util::command_exists("wayvnc") ? "true" : "false") + ",";
    json += "\"ip\":\"" + ip + "\",";
    {
        const struct passwd* pw = getpwuid(getuid());
        json += "\"username\":\"" + util::escape_json(pw && pw->pw_name ? pw->pw_name : "") + "\",";
    }
    json += "\"promptFreeScreencast\":" + std::string(is_screencast_prompt_free() ? "true" : "false") + ",";
    json += "\"uinputReady\":" + std::string(access("/dev/uinput", W_OK) == 0 ? "true" : "false");
    json += "}";
    return json;
}

bool SystemControl::set_screencast_prompt_free(bool enable) {
    const char* home = std::getenv("HOME");
    if (!home) return false;
    const char* dev_mode = std::getenv("B1AIR_DEV_MODE");
    if (enable && (!dev_mode || std::string(dev_mode) != "1")) return false;
    std::string dir = std::string(home) + "/.config/xdg-desktop-portal-wlr";
    if (dir.find_first_of("'\";$`&|<>") != std::string::npos) return false;
    mkdir((std::string(home) + "/.config").c_str(), 0700);
    mkdir(dir.c_str(), 0700);
    std::string cfg = dir + "/config";
    std::string content = "[screencast]\nmax_fps=60\nchooser_type=" + std::string(enable ? "none" : "simple") + "\n";
    return write_private_file(cfg, content);
}

bool SystemControl::is_screencast_prompt_free() {
    const char* home = std::getenv("HOME");
    if (!home) return true;
    std::string cfg = std::string(home) + "/.config/xdg-desktop-portal-wlr/config";
    std::ifstream in(cfg);
    if (!in) return false;
    std::string line;
    while (std::getline(in, line)) {
        if (line.find("chooser_type=none") != std::string::npos) {
            return true;
        }
    }
    return false;
}

bool SystemControl::sidecar_create_virtual_display(int width, int height) {
    SwayIPC ipc;
    if (!ipc.connect()) return false;
    ipc.send_command(0, "create_output");
    std::this_thread::sleep_for(std::chrono::milliseconds(100));
    ipc.send_command(0, "output HEADLESS-1 mode " + std::to_string(width) + "x" + std::to_string(height));
    return true;
}

bool SystemControl::sidecar_remove_virtual_display() {
    SwayIPC ipc;
    if (!ipc.connect()) return false;
    ipc.send_command(0, "output HEADLESS-1 unplug");
    return true;
}

// ── Milestone 1: OCR, QR Code Generator & QuickLook ──────────────────────────

bool SystemControl::qr_generate(const std::string& text, const std::string& out_path) {
    if (text.empty()) return false;
    std::string path = out_path.empty() ? runtime_path(("qr-" + std::to_string(getpid()) + ".png").c_str()) : out_path;
    if (!run_argv_status({"qrencode", "-s", "8", "-m", "2", "-o", path, "--", text})) return false;

    const std::string png = read_file_string(path);
    if (!png.empty()) (void)run_argv_with_raw_stdin({"wl-copy", "-t", "image/png"}, png);
    notify_user("QR Code Generator", "QR Code Generated", "Image copied to clipboard", path);
    return true;
}

bool SystemControl::ocr_screen(const std::string& geom) {
    std::string g = geom;
    if (g.empty()) {
        g = exec_cmd("slurp 2>/dev/null");
        if (g.empty()) return false; // User canceled
    }
    if (!valid_geometry(g)) return false;

    std::string tmp_img = runtime_path(("ocr-" + std::to_string(getpid()) + ".png").c_str());
    if (!run_argv_status({"grim", "-g", g, tmp_img})) return false;

    std::string text = run_argv_capture({"tesseract", tmp_img, "stdout"});
    unlink(tmp_img.c_str());

    // Trim whitespace
    while (!text.empty() && (text.back() == '\n' || text.back() == '\r' || text.back() == ' ')) text.pop_back();
    while (!text.empty() && (text.front() == '\n' || text.front() == '\r' || text.front() == ' ')) text.erase(0, 1);

    if (text.empty()) {
        notify_user("Screen OCR", "No text recognized", "Selection did not contain readable text");
        return false;
    }

    // Send OCR text through stdin; never place recognized content in a shell command.
    (void)run_argv_with_raw_stdin({"wl-copy"}, text);

    std::string preview = text.substr(0, 70);
    for (char& c : preview) if (c == '\'' || c == '"') c = ' ';
    (void)run_argv_capture({"notify-send", "-a", "Screen OCR", "Text Copied to Clipboard", preview + "..."});
    return true;
}

bool SystemControl::quicklook_open(const std::string& path) {
    if (path.empty()) return false;
    char resolved[PATH_MAX];
    if (!realpath(path.c_str(), resolved)) return false;
    (void)run_argv_status({"b1air-shell", "open", "quicklook", std::string(resolved)});
    return true;
}

// ── Milestone 2: Advanced Window Management & Screen Assistants ──────────────

bool SystemControl::pip_toggle() {
    SwayIPC ipc;
    if (!ipc.connect()) return false;

    std::string tree = ipc.get_tree();
    if (tree.empty()) return false;

    // Is the focused window already in PiP?
    //
    // This used to find "focused":true — which sway, pretty-printing, never
    // writes — and then guess at the surrounding object with rfind('{') and
    // find('}'), a window that lands inside the node's own nested rect. It
    // never found a mark, so toggling off did nothing and the same window was
    // pinned again on every press.
    bool in_pip = false;
    try {
        walk_tree(nlohmann::json::parse(tree), [&](const nlohmann::json& n) {
            if (!n.value("focused", false) || !n.contains("marks") || !n["marks"].is_array()) return;
            for (const auto& mark : n["marks"])
                if (mark.is_string() && mark.get<std::string>() == "pip") in_pip = true;
        });
    } catch (const std::exception&) {
        return false;
    }

    if (in_pip) {
        ipc.send_command(0, "unmark pip, sticky disable, floating disable");
        notify_user("Picture-in-Picture", "PiP Disabled", "Restored window to tiled layout");
        return true;
    }

    // PiP Geometry: 480x270 at bottom right (1920x1080 standard offset)
    int sw = 1920, sh = 1080;
    focused_output_size(ipc.get_outputs(), sw, sh);

    int pw = 480;
    int ph = 270;
    int px = sw - pw - 24;
    int py = sh - ph - 48;

    std::string sway_cmd = "floating enable, sticky enable, border pixel 2, resize set " + 
                           std::to_string(pw) + " " + std::to_string(ph) + 
                           ", move position " + std::to_string(px) + " " + std::to_string(py) + 
                           ", mark pip";
    ipc.send_command(0, sway_cmd);
    notify_user("Picture-in-Picture", "PiP Enabled", "Pinned window to bottom-right");
    return true;
}

std::string SystemControl::pip_status() {
    SwayIPC ipc;
    if (!ipc.connect()) return "{\"active\":false}";
    std::string tree = ipc.get_tree();
    bool active = (tree.find("\"pip\"") != std::string::npos);
    return active ? "{\"active\":true}" : "{\"active\":false}";
}

bool SystemControl::force_quit() {
    // slurp -p selects a single pixel/point
    std::string point = exec_cmd("slurp -p -b '#f7768e66' -c '#f7768e' 2>/dev/null");
    if (point.empty()) return false;

    int click_x = 0, click_y = 0;
    if (sscanf(point.c_str(), "%d,%d", &click_x, &click_y) != 2) return false;

    SwayIPC ipc;
    if (!ipc.connect()) return false;
    std::string tree = ipc.get_tree();

    // Traverse Sway tree JSON to find window container enclosing click_x, click_y
    int target_pid = 0;
    std::string target_name = "Application";

    // Find the window under the pointer.
    //
    // This used to scan for "pid": , then rfind the nearest "rect": within 400
    // bytes and read it with an sscanf format that had no spaces in it:
    //
    //   sscanf(..., "\"rect\":{\"x\":%d,\"y\":%d,...")
    //
    // Sway pretty-prints, so the text is `"rect": {\n  "x": 0,` and the format
    // matched nothing; "name":" never matched either. The pointer was never
    // resolved to a window and every force-quit fell through to killing the
    // focused one instead — which is not the same window when the click was
    // meant to pick a different one. The "nearest rect within 400 bytes" was
    // guesswork besides: a node's own rect is the one that belongs to it.
    try {
        const auto parsed = nlohmann::json::parse(tree);
        walk_tree(parsed, [&](const nlohmann::json& n) {
            if (target_pid > 0 || !is_window(n)) return;
            const int pid = n.value("pid", 0);
            if (pid <= 0 || !n.contains("rect") || !n["rect"].is_object()) return;

            const auto& r = n["rect"];
            const int x = r.value("x", 0), y = r.value("y", 0);
            const int w = r.value("width", 0), h = r.value("height", 0);
            if (click_x < x || click_x > x + w || click_y < y || click_y > y + h) return;

            target_pid = pid;
            target_name = json_str(n, "name", "Application");
        });
    } catch (const std::exception&) {
        // Fall through to killing the focused window.
    }

    if (target_pid > 0) {
        kill(target_pid, SIGTERM);
        std::this_thread::sleep_for(std::chrono::milliseconds(150));
        kill(target_pid, SIGKILL);
        ipc.send_command(0, "kill");
        const std::string notice = "Closed " + target_name + " (PID " + std::to_string(target_pid) + ")";
        (void)run_argv_capture({"notify-send", "-a", "Force Quit", "-u", "critical",
                                 "Terminated Window", notice});
        return true;
    }

    // Fallback: kill focused window
    ipc.send_command(0, "kill");
    notify_user("Force Quit", "Window Closed", "Sent kill signal to window");
    return true;
}

bool SystemControl::cursor_locate() {
    if (!run_argv_status({"b1air-shell", "toggle", "ruler"}))
        notify_user("b1air", "Cursor Located", "Look here!");
    return true;
}

bool SystemControl::zones_apply(int zone_id) {
    SwayIPC ipc;
    if (!ipc.connect()) return false;

    int sw = 1920, sh = 1080;
    focused_output_size(ipc.get_outputs(), sw, sh);

    int bar_h = 48;
    int gap = 12;
    int avail_w = sw - (gap * 2);
    int avail_h = sh - bar_h - (gap * 2);
    int top_y = bar_h + gap;
    int left_x = gap;

    int x = left_x, y = top_y, w = avail_w, h = avail_h;

    switch (zone_id) {
        case 1: // Left 1/2
            w = (avail_w - gap) / 2;
            break;
        case 2: // Right 1/2
            w = (avail_w - gap) / 2;
            x = left_x + w + gap;
            break;
        case 3: // Left 1/3
            w = (avail_w - gap * 2) / 3;
            break;
        case 4: // Mid 1/3
            w = (avail_w - gap * 2) / 3;
            x = left_x + w + gap;
            break;
        case 5: // Right 1/3
            w = (avail_w - gap * 2) / 3;
            x = left_x + (w + gap) * 2;
            break;
        case 6: // Left 2/3
            w = ((avail_w - gap * 2) / 3) * 2 + gap;
            break;
        case 7: // Right 2/3
            w = ((avail_w - gap * 2) / 3) * 2 + gap;
            x = left_x + (avail_w - w);
            break;
        case 8: // Top 1/2
            h = (avail_h - gap) / 2;
            break;
        case 9: // Bottom 1/2
            h = (avail_h - gap) / 2;
            y = top_y + h + gap;
            break;
        default:
            return false;
    }

    std::string sway_cmd = "floating enable, resize set " + std::to_string(w) + " " + std::to_string(h) + 
                           ", move position " + std::to_string(x) + " " + std::to_string(y);
    ipc.send_command(0, sway_cmd);
    return true;
}

// ── Milestone 3: Audio Subsystem, Recording & Multimedia Ecosystem ───────────

bool SystemControl::audio_switch_output() {
    // 1. List short sinks from PulseAudio/PipeWire
    std::string sinks_raw = exec_cmd_full("pactl list short sinks 2>/dev/null");
    std::vector<std::string> sink_names;
    std::vector<std::string> sink_descs;

    if (!sinks_raw.empty()) {
        std::istringstream stream(sinks_raw);
        std::string line;
        while (std::getline(stream, line)) {
            if (line.empty()) continue;
            std::istringstream lstream(line);
            std::string id, name;
            lstream >> id >> name;
            if (!name.empty()) {
                sink_names.push_back(name);
                sink_descs.push_back(name);
            }
        }
    }

    if (sink_names.empty()) {
        // Fallback: try wpctl status
        notify_user("Audio Switcher", "No Output Devices", "No secondary sinks found");
        return false;
    }

    std::string current_default = exec_cmd("pactl get-default-sink 2>/dev/null");
    int current_idx = -1;
    for (size_t i = 0; i < sink_names.size(); ++i) {
        if (sink_names[i] == current_default) {
            current_idx = static_cast<int>(i);
            break;
        }
    }

    int next_idx = (current_idx + 1) % sink_names.size();
    std::string target_sink = sink_names[next_idx];

    if (!run_argv_with_stdin({"pactl", "set-default-sink", target_sink}, "")) {
        (void)run_argv_with_stdin({"wpctl", "set-default", target_sink}, "");
    }

    std::string friendly_name = target_sink;
    if (friendly_name.find("analog") != std::string::npos || friendly_name.find("speaker") != std::string::npos) {
        friendly_name = "Built-in Speakers";
    } else if (friendly_name.find("headphone") != std::string::npos || friendly_name.find("headset") != std::string::npos) {
        friendly_name = "Headphones / Headset";
    } else if (friendly_name.find("hdmi") != std::string::npos) {
        friendly_name = "HDMI / DisplayPort Audio";
    }

    (void)run_argv_capture({"notify-send", "-a", "Audio Switcher", "-i", "audio-speakers", "Audio Output Switched", friendly_name});
    return true;
}

bool SystemControl::mic_rnnoise_is_active() {
    const std::string flag_path = runtime_path("rnnoise.active");
    return access(flag_path.c_str(), F_OK) == 0;
}

bool SystemControl::mic_rnnoise_set(bool enable) {
    if (enable) {
        if (!write_private_file(runtime_path("rnnoise.active"), "1\n")) return false;
        // Launch PipeWire filter-chain RNNoise source if config exists and track its PID.
        const pid_t child = spawn_argv_detached({"pipewire", "-c", "filter-chain/source-rnnoise.conf"});
        if (child <= 0 || !write_private_file(runtime_path("rnnoise.pid"), std::to_string(child) + "\n")) {
            unlink(runtime_path("rnnoise.active").c_str());
            if (child > 0) (void)::kill(child, SIGTERM);
            return false;
        }
        notify_user("Microphone", "AI Noise Suppression: ON", "Deep-learning background filter active", "audio-input-microphone");
    } else {
        unlink(runtime_path("rnnoise.active").c_str());
        const pid_t child = runtime_pid(runtime_path("rnnoise.pid"));
        if (child > 0) (void)::kill(child, SIGTERM);
        unlink(runtime_path("rnnoise.pid").c_str());
        notify_user("Microphone", "AI Noise Suppression: OFF", "Standard microphone input restored", "audio-input-microphone");
    }
    return true;
}

bool SystemControl::mic_rnnoise_toggle() {
    return mic_rnnoise_set(!mic_rnnoise_is_active());
}

bool SystemControl::record_gif(const std::string& geom) {
    std::string g = geom;
    if (g.empty()) {
        g = exec_cmd("slurp 2>/dev/null");
        if (g.empty()) return false;
    }
    if (!valid_geometry(g)) return false;

    const char* home = std::getenv("HOME");
    std::string out_dir = home ? (std::string(home) + "/Pictures/Screenshots") : "/tmp";
    std::error_code mkdir_ec;
    std::filesystem::create_directories(out_dir, mkdir_ec);
    if (mkdir_ec) return false;

    auto now = std::chrono::system_clock::to_time_t(std::chrono::system_clock::now());
    char ts[64];
    std::strftime(ts, sizeof(ts), "%Y-%m-%d_%H-%M-%S", std::localtime(&now));
    std::string gif_path = out_dir + "/recording_" + std::string(ts) + ".gif";
    std::string tmp_mp4 = runtime_path(("gif-" + std::to_string(getpid()) + ".mp4").c_str());

    notify_user("Screen-to-GIF", "⏺ Recording GIF", "Capturing 5-second region animation...");

    // Capture short region clip (5s)
    const std::vector<std::string> wf_args = {"wf-recorder", "-g", g, "-d", "5", "-f", tmp_mp4};
    if (!run_argv_status(wf_args)) {
        const pid_t screenrec_pid = spawn_argv_detached({"wl-screenrec", "-g", g, "-f", tmp_mp4});
        if (screenrec_pid > 0) {
            std::this_thread::sleep_for(std::chrono::seconds(5));
            (void)::kill(screenrec_pid, SIGINT);
            (void)::waitpid(screenrec_pid, nullptr, WNOHANG);
        }
    }

    // Two-pass optimal palette conversion to GIF
    (void)run_argv_status({"ffmpeg", "-y", "-i", tmp_mp4, "-vf",
                           "fps=15,scale=flags=lanczos,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse",
                           gif_path});
    unlink(tmp_mp4.c_str());

    // Optional lossless optimization if gifsicle is installed
    (void)run_argv_status({"gifsicle", "-O3", "--lossy=30", "-o", gif_path, gif_path});

    // Copy to clipboard
    const std::string gif_data = read_file_string(gif_path);
    if (!gif_data.empty()) (void)run_argv_with_raw_stdin({"wl-copy", "-t", "image/gif"}, gif_data);
    notify_user("Screen-to-GIF", "GIF Saved & Copied", "Copied animated GIF to clipboard", gif_path);
    return true;
}

bool SystemControl::voice_memo() {
    const std::string pid_file = runtime_path("voice_memo.pid");
    if (access(pid_file.c_str(), F_OK) == 0) {
        // Stop recording
        const pid_t pid = runtime_pid(pid_file);
        if (pid > 0) (void)::kill(pid, SIGINT);
        unlink(pid_file.c_str());
        notify_user("Voice Memo", "⏹ Recording Stopped", "Saved audio memo to recordings folder");
        return true;
    }

    const char* home = std::getenv("HOME");
    std::string rec_dir = home ? (std::string(home) + "/Music/Recordings") : "/tmp";
    std::error_code ec;
    std::filesystem::create_directories(rec_dir, ec);
    if (ec) return false;

    auto now = std::chrono::system_clock::to_time_t(std::chrono::system_clock::now());
    char ts[64];
    std::strftime(ts, sizeof(ts), "%Y-%m-%d_%H-%M-%S", std::localtime(&now));
    std::string wav_path = rec_dir + "/memo_" + std::string(ts) + ".wav";

    const pid_t child = fork();
    if (child < 0) return false;
    if (child == 0) {
        const int null_fd = open("/dev/null", O_RDWR | O_CLOEXEC);
        if (null_fd < 0) _exit(126);
        dup2(null_fd, STDIN_FILENO); dup2(null_fd, STDOUT_FILENO); dup2(null_fd, STDERR_FILENO);
        if (null_fd > STDERR_FILENO) close(null_fd);
        execlp("pw-record", "pw-record", wav_path.c_str(), nullptr);
        _exit(127);
    }
    if (!write_private_file(pid_file, std::to_string(child) + "\n")) {
        (void)::kill(child, SIGTERM);
        return false;
    }

    notify_user("Voice Memo", "🎙️ Recording Started", "Press Super+Shift+V again to stop");
    return true;
}

// ── Milestone 4: Privacy, Security & System Health Maintenance ────────────────

std::string SystemControl::disk_sweeper_scan() {
    // The package cache of whichever manager this is; du totals the ones that
    // exist and complains about the rest on stderr. The JSON key keeps its old
    // name because the Settings page reads it.
    std::string pacman_cache = exec_cmd("du -shc /var/cache/pacman/pkg /var/cache/apt/archives "
                                        "/var/cache/dnf /var/cache/libdnf5 /var/cache/zypp/packages "
                                        "2>/dev/null | tail -n1 | cut -f1");
    if (pacman_cache.empty() || pacman_cache == "0") pacman_cache = "0 B";

    const char* home = std::getenv("HOME");
    std::string user_cache = "0 B";
    std::string thumb_cache = "0 B";
    if (home) {
        user_cache = run_argv_capture({"du", "-sh", std::string(home) + "/.cache"});
        thumb_cache = run_argv_capture({"du", "-sh", std::string(home) + "/.cache/thumbnails"});
        const auto trim_size = [](std::string value) {
                const size_t tab = value.find('\t');
                if (tab != std::string::npos) value.resize(tab);
                while (!value.empty() && (value.back() == '\n' || value.back() == '\r')) value.pop_back();
                return value;
            };
        if (!user_cache.empty()) user_cache = trim_size(user_cache);
        if (!thumb_cache.empty()) thumb_cache = trim_size(thumb_cache);
    }

    std::string journal = exec_cmd("journalctl --disk-usage 2>/dev/null | grep -oE '[0-9\\.]+[M|G|K]B' | head -1");
    if (journal.empty()) journal = "< 50 MB";

    std::string orphans = exec_cmd(
        "{ if command -v pacman >/dev/null 2>&1; then pacman -Qtdq; "
        "elif command -v apt-get >/dev/null 2>&1; then apt-get -s -o Debug::NoLocking=1 autoremove | grep '^Remv '; "
        "elif command -v dnf >/dev/null 2>&1; then dnf -q repoquery --unneeded; "
        "elif command -v zypper >/dev/null 2>&1; then zypper -q packages --unneeded | grep '^i'; "
        "fi; } 2>/dev/null | wc -l");
    if (orphans.empty()) orphans = "0";

    std::ostringstream json;
    json << "{"
         << "\"ok\":true,"
         << "\"pacman_cache\":\"" << pacman_cache << "\","
         << "\"user_cache\":\"" << user_cache << "\","
         << "\"thumbnails\":\"" << thumb_cache << "\","
         << "\"journal\":\"" << journal << "\","
         << "\"orphans\":" << orphans
         << "}";
    return json.str();
}

bool SystemControl::disk_sweeper_clean() {
    const char* home = std::getenv("HOME");
    if (home && *home) {
        const std::filesystem::path thumbnails = std::filesystem::path(home) / ".cache/thumbnails";
        std::error_code ec;
        if (std::filesystem::is_directory(thumbnails, ec)) {
            for (const auto& entry : std::filesystem::directory_iterator(
                     thumbnails, std::filesystem::directory_options::skip_permission_denied, ec)) {
                std::error_code remove_error;
                // remove() does not recurse through a symlink, so a malicious
                // thumbnail entry cannot redirect cleanup outside this cache.
                std::filesystem::remove(entry.path(), remove_error);
            }
        }
    }
    // Say what was actually cleaned. The package cache needs root, and
    // `sudo` from a session daemon with no terminal simply fails — so the
    // sweeper reported "Storage Cleaned • Reclaimed cache and thumbnail
    // storage" on machines where the package cache, usually the largest part
    // of it by far, had not been touched at all.
    std::vector<std::string> done;
    done.push_back("thumbnails");

    if (run_argv_status({"journalctl", "--vacuum-time=7d"}))
        done.push_back("journal");

    if (run_argv_status({"sudo", "-n", "paccache", "-rk2"})
        || run_argv_status({"sudo", "-n", "pacman", "-Sc", "--noconfirm"})
        || run_argv_status({"sudo", "-n", "apt-get", "clean"})
        || run_argv_status({"sudo", "-n", "dnf", "clean", "packages"})
        || run_argv_status({"sudo", "-n", "zypper", "clean", "--all"}))
        done.push_back("package cache");

    std::string summary = "Cleaned: ";
    for (size_t i = 0; i < done.size(); ++i)
        summary += (i ? ", " : "") + done[i];
    if (done.size() < 3)
        summary += ". The package cache needs root and was left alone.";

    notify_user("Disk Sweeper", "Storage cleaned", summary, "drive-harddisk");
    return true;
}

bool SystemControl::snapshot_create(const std::string& comment) {
    const std::string c = comment.empty() ? "b1air pre-update snapshot" : comment;

    // Both tools are optional and neither is in the package list, so a machine
    // with neither is the normal case, not an exotic one. This used to try
    // timeshift, then snapper, and then announce "Restore Point Created —
    // System snapshot saved successfully" whatever had happened: a machine
    // with neither installed was told its snapshot was saved. A false success
    // is worse than a silent failure, because it is acted on.
    if (run_argv_status({"timeshift", "--create", "--comments", c, "--tags", "O"})) {
        notify_user("System Restore", "Restore point created", "Saved with timeshift", "document-save");
        return true;
    }
    if (run_argv_status({"snapper", "create", "-d", c})) {
        notify_user("System Restore", "Restore point created", "Saved with snapper", "document-save");
        return true;
    }

    notify_user("System Restore", "No snapshot tool",
                "Install timeshift or snapper to create restore points.", "dialog-error");
    return false;
}

std::string SystemControl::snapshot_list() {
    std::string out = exec_cmd_full("timeshift --list 2>/dev/null | grep -E '>|([0-9]{4}-[0-9]{2}-[0-9]{2})' | head -5 || snapper list 2>/dev/null | tail -5");
    std::ostringstream json;
    json << "{\"ok\":true,\"has_snapshots\":" << (!out.empty() ? "true" : "false") << "}";
    return json.str();
}

bool SystemControl::vault_mount(const std::string& vault_path, const std::string& mount_point, const std::string& password) {
    if (vault_path.empty() || mount_point.empty()) return false;
    std::error_code ec;
    std::filesystem::create_directories(mount_point, ec);
    if (ec) return false;
    return run_argv_with_stdin({"gocryptfs", vault_path, mount_point}, password);
}

bool SystemControl::vault_unmount(const std::string& mount_point) {
    if (mount_point.empty()) return false;
    if (run_argv_status({"fusermount", "-u", mount_point})) return true;
    return run_argv_status({"umount", mount_point});
}

std::string SystemControl::vault_status() {
    std::string mounts = exec_cmd_full("mount | grep -E 'gocryptfs|cryfs|encfs' | awk '{print $3}'");
    return mounts.empty() ? "{\"active\":false,\"mounts\":[]}" : "{\"active\":true}";
}

bool SystemControl::kill_process(int pid, bool force) {
    if (pid <= 1) return false;
    return (::kill(pid, force ? SIGKILL : SIGTERM) == 0);
}

std::string SystemControl::get_system_stats_json() {
    // 1. CPU calculation via /proc/stat
    static unsigned long long s_prev_idle = 0, s_prev_total = 0;
    double cpu_pct = 0.0;
    {
        std::ifstream f("/proc/stat");
        std::string cpu;
        unsigned long long u, n, s, i, io, irq, sirq, st;
        if (f >> cpu >> u >> n >> s >> i >> io >> irq >> sirq >> st) {
            unsigned long long idle = i + io;
            unsigned long long non_idle = u + n + s + irq + sirq + st;
            unsigned long long total = idle + non_idle;
            if (s_prev_total > 0 && total > s_prev_total) {
                unsigned long long d_total = total - s_prev_total;
                unsigned long long d_idle = idle - s_prev_idle;
                cpu_pct = (double)(d_total - d_idle) * 100.0 / (double)d_total;
                if (cpu_pct < 0.0) cpu_pct = 0.0;
                if (cpu_pct > 100.0) cpu_pct = 100.0;
            }
            s_prev_idle = idle;
            s_prev_total = total;
        }
    }

    // 2. Cores & CPU Model
    unsigned int cores = std::thread::hardware_concurrency();
    std::string cpu_model = "CPU";
    {
        std::ifstream f("/proc/cpuinfo");
        std::string line;
        while (std::getline(f, line)) {
            if (line.rfind("model name", 0) == 0 || line.rfind("Hardware", 0) == 0 || line.rfind("Processor", 0) == 0) {
                auto col = line.find(':');
                if (col != std::string::npos && col + 2 < line.size()) {
                    cpu_model = line.substr(col + 2);
                    // sanitize quotes
                    for (char& c : cpu_model) if (c == '"' || c == '\\') c = ' ';
                    break;
                }
            }
        }
    }

    // 3. Memory & Swap via /proc/meminfo
    long long total_kb = 0, avail_kb = 0, swap_total_kb = 0, swap_free_kb = 0;
    {
        std::ifstream f("/proc/meminfo");
        std::string key;
        long long val;
        std::string unit;
        while (f >> key >> val >> unit) {
            if (key == "MemTotal:") total_kb = val;
            else if (key == "MemAvailable:") avail_kb = val;
            else if (key == "SwapTotal:") swap_total_kb = val;
            else if (key == "SwapFree:") swap_free_kb = val;
        }
    }
    long long used_kb = total_kb - avail_kb;
    if (used_kb < 0) used_kb = 0;
    double mem_pct = total_kb > 0 ? ((double)used_kb * 100.0 / (double)total_kb) : 0.0;
    long long swap_used_kb = swap_total_kb - swap_free_kb;
    if (swap_used_kb < 0) swap_used_kb = 0;

    // 4. Disk Info via statvfs("/")
    double disk_total_gb = 0.0, disk_free_gb = 0.0, disk_pct = 0.0;
    struct statvfs fs;
    if (statvfs("/", &fs) == 0) {
        double total_bytes = (double)fs.f_blocks * (double)fs.f_frsize;
        double free_bytes = (double)fs.f_bavail * (double)fs.f_frsize;
        disk_total_gb = total_bytes / (1024.0 * 1024.0 * 1024.0);
        disk_free_gb = free_bytes / (1024.0 * 1024.0 * 1024.0);
        if (total_bytes > 0) {
            disk_pct = ((total_bytes - free_bytes) * 100.0) / total_bytes;
        }
    }

    // 5. Load average & Uptime
    std::string loadavg = "";
    {
        std::ifstream f("/proc/loadavg");
        std::string l1, l2, l3;
        if (f >> l1 >> l2 >> l3) loadavg = l1 + " " + l2 + " " + l3;
    }

    std::string uptime_str = "";
    {
        std::ifstream f("/proc/uptime");
        double up_sec = 0;
        if (f >> up_sec) {
            int hrs = (int)up_sec / 3600;
            int mins = ((int)up_sec % 3600) / 60;
            uptime_str = std::to_string(hrs) + "h " + std::to_string(mins) + "m";
        }
    }

    // 6. Top Processes via ps
    std::ostringstream proc_json;
    proc_json << "[";
    const std::string process_output = run_argv_capture({"ps", "-eo", "pid,pcpu,pmem,user,comm", "--sort=-pcpu"});
    std::istringstream process_stream(process_output);
    std::string line;
    bool first = true;
    // Skip the header and limit in-process instead of through a shell pipeline.
    std::getline(process_stream, line);
    int process_count = 0;
    while (process_count < 35 && std::getline(process_stream, line)) {
        std::istringstream fields(line);
        int pid;
        float pcpu, pmem;
        std::string user, comm;
        if (!(fields >> pid >> pcpu >> pmem >> user >> comm)) continue;
        if (!first) proc_json << ",";
        first = false;
        proc_json << "{\"pid\":" << pid
                  << ",\"cpu\":" << pcpu
                  << ",\"mem\":" << pmem
                  << ",\"user\":\"" << json_escape(user) << "\""
                  << ",\"name\":\"" << json_escape(comm) << "\"}";
        ++process_count;
    }
    proc_json << "]";

    std::ostringstream res;
    res << std::fixed << std::setprecision(1)
        << "{"
        << "\"cpu_pct\":" << cpu_pct << ","
        << "\"cpu_model\":\"" << cpu_model << "\","
        << "\"cores\":" << cores << ","
        << "\"ram_used_mb\":" << (used_kb / 1024) << ","
        << "\"ram_total_mb\":" << (total_kb / 1024) << ","
        << "\"ram_pct\":" << mem_pct << ","
        << "\"swap_used_mb\":" << (swap_used_kb / 1024) << ","
        << "\"swap_total_mb\":" << (swap_total_kb / 1024) << ","
        << "\"disk_total_gb\":" << disk_total_gb << ","
        << "\"disk_free_gb\":" << disk_free_gb << ","
        << "\"disk_pct\":" << disk_pct << ","
        << "\"load_avg\":\"" << loadavg << "\","
        << "\"uptime\":\"" << uptime_str << "\","
        << "\"processes\":" << proc_json.str()
        << "}";
    return res.str();
}

} // namespace b1air
