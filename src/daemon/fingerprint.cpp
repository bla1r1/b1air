#include "fingerprint.hpp"

#include <nlohmann/json.hpp>
#include <systemd/sd-bus.h>

#include <cerrno>
#include <csignal>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <poll.h>
#include <string>
#include <sys/stat.h>
#include <unistd.h>
#include <vector>

namespace b1air::fingerprint {

namespace {

constexpr const char* kService = "net.reactivated.Fprint";
constexpr const char* kManagerPath = "/net/reactivated/Fprint/Manager";
constexpr const char* kManager = "net.reactivated.Fprint.Manager";
constexpr const char* kDevice = "net.reactivated.Fprint.Device";

volatile sig_atomic_t g_stop = 0;
void on_signal(int) { g_stop = 1; }

struct Bus {
    sd_bus* bus = nullptr;
    std::string device;   // the reader's object path, empty when there is none
    std::string error;    // why not, as fprintd or D-Bus said it
    Bus() {
        if (sd_bus_open_system(&bus) < 0) {
            bus = nullptr;
            error = "no-system-bus";
            return;
        }
        sd_bus_message* reply = nullptr;
        sd_bus_error e = SD_BUS_ERROR_NULL;
        if (sd_bus_call_method(bus, kService, kManagerPath, kManager, "GetDefaultDevice", &e, &reply, "") >= 0) {
            const char* path = nullptr;
            if (sd_bus_message_read(reply, "o", &path) >= 0 && path) device = path;
        } else {
            // NoSuchDevice: fprintd is there, the reader is not; ServiceUnknown:
            // fprintd is not installed.
            error = e.name ? e.name : "unknown";
        }
        sd_bus_error_free(&e);
        sd_bus_message_unref(reply);
    }
    ~Bus() {
        if (bus) sd_bus_flush_close_unref(bus);
    }
    // A method on the reader; on failure `err` gets fprintd's error name.
    bool call(const char* method, std::string* err, const char* sig = "", const char* arg = nullptr,
              sd_bus_message** out = nullptr) {
        sd_bus_error e = SD_BUS_ERROR_NULL;
        const int r = arg ? sd_bus_call_method(bus, kService, device.c_str(), kDevice, method, &e, out, sig, arg)
                          : sd_bus_call_method(bus, kService, device.c_str(), kDevice, method, &e, out, "");
        if (r < 0 && err) *err = e.name ? e.name : std::strerror(-r);
        sd_bus_error_free(&e);
        return r >= 0;
    }
};

std::string short_error(const std::string& name) {
    // net.reactivated.Fprint.Error.PermissionDenied -> PermissionDenied
    const auto dot = name.rfind('.');
    return dot == std::string::npos ? name : name.substr(dot + 1);
}

std::vector<std::string> enrolled(Bus& b) {
    std::vector<std::string> out;
    sd_bus_message* reply = nullptr;
    // The empty user is the caller.
    if (b.call("ListEnrolledFingers", nullptr, "s", "", &reply)) {
        char** fingers = nullptr;
        if (sd_bus_message_read_strv(reply, &fingers) >= 0 && fingers) {
            for (char** f = fingers; *f; ++f) {
                out.emplace_back(*f);
                free(*f);
            }
            free(fingers);
        }
    }
    sd_bus_message_unref(reply);
    return out;
}

// A property of the reader, by Properties.Get: fprintd names them with
// dashes ("num-enroll-stages"), which sd-bus's own property helpers refuse
// as member names.
sd_bus_message* property(Bus& b, const char* name, const char* type) {
    sd_bus_message* reply = nullptr;
    if (sd_bus_call_method(b.bus, kService, b.device.c_str(), "org.freedesktop.DBus.Properties", "Get", nullptr,
                           &reply, "ss", kDevice, name) < 0
        || sd_bus_message_enter_container(reply, 'v', type) < 0) {
        sd_bus_message_unref(reply);
        return nullptr;
    }
    return reply;
}

std::string property_string(Bus& b, const char* name) {
    std::string out;
    if (sd_bus_message* m = property(b, name, "s")) {
        const char* v = nullptr;
        if (sd_bus_message_read(m, "s", &v) >= 0 && v) out = v;
        sd_bus_message_unref(m);
    }
    return out;
}

int property_int(Bus& b, const char* name) {
    int32_t out = 0;
    if (sd_bus_message* m = property(b, name, "i")) {
        (void)sd_bus_message_read(m, "i", &out);
        sd_bus_message_unref(m);
    }
    return out;
}

// Is whoever started this still there: stdin a pipe that has been closed
// (the settings page stopped its Process) counts as gone.
bool reader_gone() {
    struct stat st{};
    if (fstat(STDIN_FILENO, &st) != 0 || !S_ISFIFO(st.st_mode)) return false;
    pollfd p{STDIN_FILENO, POLLIN, 0};
    if (poll(&p, 1, 0) <= 0) return false;
    if (p.revents & (POLLHUP | POLLERR)) return true;
    char buf[64];
    return read(STDIN_FILENO, buf, sizeof(buf)) == 0;
}

struct Scan {
    std::string last;
    bool done = false;
};

int on_status(sd_bus_message* m, void* data, sd_bus_error*) {
    auto* s = static_cast<Scan*>(data);
    const char* result = nullptr;
    int done = 0;
    if (sd_bus_message_read(m, "sb", &result, &done) < 0 || !result) return 0;
    s->last = result;
    s->done = done != 0;
    std::cout << "status " << result << std::endl;
    return 0;
}

// Claim the reader, start `start` (EnrollStart or VerifyStart), print every
// `signal` until it says done, stop it with `stop` and let the reader go.
int scan(const char* start, const char* arg, const char* signal, const char* stop, const char* success) {
    std::signal(SIGTERM, on_signal);
    std::signal(SIGINT, on_signal);
    Bus b;
    if (b.device.empty()) {
        std::cout << "done error " << short_error(b.error) << std::endl;
        return 2;
    }
    std::string err;
    if (!b.call("Claim", &err, "s", "")) {
        std::cout << "done error " << short_error(err) << std::endl;
        return 2;
    }
    Scan s;
    sd_bus_slot* slot = nullptr;
    sd_bus_match_signal(b.bus, &slot, kService, b.device.c_str(), kDevice, signal, on_status, &s);
    int rc = 1;
    if (!b.call(start, &err, "s", arg)) {
        std::cout << "done error " << short_error(err) << std::endl;
        rc = 2;
    } else {
        while (!s.done && !g_stop && !reader_gone()) {
            const int r = sd_bus_process(b.bus, nullptr);
            if (r < 0) break;
            if (r == 0) sd_bus_wait(b.bus, 250000);
        }
        (void)b.call(stop, nullptr);
        if (s.done) {
            std::cout << "done " << s.last << std::endl;
            rc = s.last == success ? 0 : 1;
        } else {
            std::cout << "done cancelled" << std::endl;
        }
    }
    sd_bus_slot_unref(slot);
    (void)b.call("Release", nullptr);
    return rc;
}

} // namespace

std::string status_json() {
    nlohmann::json j;
    Bus b;
    j["available"] = !b.device.empty();
    j["service"] = b.bus && short_error(b.error) != "ServiceUnknown" && b.error != "no-system-bus";
    j["device"] = "";
    j["stages"] = 0;
    j["scanType"] = "";
    j["enrolled"] = nlohmann::json::array();
    if (!b.device.empty()) {
        j["device"] = property_string(b, "name");
        j["stages"] = property_int(b, "num-enroll-stages");
        j["scanType"] = property_string(b, "scan-type");
        j["enrolled"] = enrolled(b);
    } else if (!b.error.empty()) {
        j["error"] = short_error(b.error);
    }
    return j.dump();
}

int enroll(const std::string& finger) {
    return scan("EnrollStart", finger.c_str(), "EnrollStatus", "EnrollStop", "enroll-completed");
}

int verify() {
    return scan("VerifyStart", "any", "VerifyStatus", "VerifyStop", "verify-match");
}

int remove(const std::string& finger) {
    Bus b;
    if (b.device.empty()) {
        std::cout << "done error " << short_error(b.error) << std::endl;
        return 2;
    }
    std::string err;
    if (!b.call("Claim", &err, "s", "")) {
        std::cout << "done error " << short_error(err) << std::endl;
        return 2;
    }
    const bool ok = finger == "all" ? b.call("DeleteEnrolledFingers2", &err)
                                    : b.call("DeleteEnrolledFinger", &err, "s", finger.c_str());
    (void)b.call("Release", nullptr);
    std::cout << (ok ? "done deleted" : "done error " + short_error(err)) << std::endl;
    return ok ? 0 : 1;
}

} // namespace b1air::fingerprint

// ── The login screen ─────────────────────────────────────────────────────────

namespace b1air::fingerprint {

namespace {

constexpr const char* kBegin = "# b1air: fingerprint at the login screen (Settings → User). Begin.";
constexpr const char* kEnd = "# b1air: end.";
constexpr const char* kGreeterFlag = "/etc/b1air/fingerprint-login.qml";

std::string sddm_pam_file() {
    // Tests point it at a copy; pkexec clears the environment, so a real
    // change is always to the real file.
    const char* test = std::getenv("B1AIR_TEST_SDDM_PAM");
    return test && *test ? test : "/etc/pam.d/sddm";
}

bool root_owned_safe(const std::string& path) {
    struct stat st{};
    return stat(path.c_str(), &st) == 0 && st.st_uid == 0 && (st.st_mode & (S_IWGRP | S_IWOTH)) == 0;
}

// The helper pam_exec runs as root at the login screen: only one that root
// owns and nobody else can change, in a directory nobody else can change.
std::string empty_password_helper() {
    for (const char* dir : {"/usr/share/b1air/pam", "/usr/local/share/b1air/pam"}) {
        const std::string path = std::string(dir) + "/b1air-empty-password";
        if (access(path.c_str(), X_OK) == 0 && root_owned_safe(path) && root_owned_safe(dir)) return path;
    }
    return {};
}

bool have_pam_fprintd() {
    for (const char* dir : {"/usr/lib/security", "/usr/lib64/security", "/lib/security", "/lib64/security",
                            "/usr/lib/x86_64-linux-gnu/security", "/lib/x86_64-linux-gnu/security",
                            "/usr/lib/aarch64-linux-gnu/security", "/lib/aarch64-linux-gnu/security"})
        if (access((std::string(dir) + "/pam_fprintd.so").c_str(), R_OK) == 0) return true;
    return false;
}

std::vector<std::string> read_lines(const std::string& path, bool& ok) {
    std::vector<std::string> out;
    FILE* f = std::fopen(path.c_str(), "re");
    ok = f != nullptr;
    if (!f) return out;
    char* line = nullptr;
    size_t cap = 0;
    ssize_t n;
    while ((n = getline(&line, &cap, f)) >= 0) {
        std::string l(line, static_cast<size_t>(n));
        if (!l.empty() && l.back() == '\n') l.pop_back();
        out.push_back(l);
    }
    free(line);
    std::fclose(f);
    return out;
}

bool has_block(const std::vector<std::string>& lines) {
    for (const auto& l : lines)
        if (l == kBegin) return true;
    return false;
}

bool write_atomically(const std::string& path, const std::string& text, mode_t mode) {
    const std::string tmp = path + ".b1air-new";
    FILE* f = std::fopen(tmp.c_str(), "we");
    if (!f) return false;
    const bool wrote = std::fwrite(text.data(), 1, text.size(), f) == text.size();
    const bool closed = std::fclose(f) == 0;
    if (!wrote || !closed || chmod(tmp.c_str(), mode) != 0 || rename(tmp.c_str(), path.c_str()) != 0) {
        unlink(tmp.c_str());
        return false;
    }
    return true;
}

} // namespace

std::string login_status_json() {
    nlohmann::json j;
    bool ok = false;
    const auto lines = read_lines(sddm_pam_file(), ok);
    std::string why;
    if (!ok) why = "no-sddm";
    else if (!have_pam_fprintd()) why = "no-pam-fprintd";
    else if (empty_password_helper().empty()) why = "not-installed";
    j["supported"] = why.empty();
    j["enabled"] = ok && has_block(lines);
    if (!why.empty()) j["reason"] = why;
    return j.dump();
}

int login_set(bool on) {
    const std::string path = sddm_pam_file();
    bool ok = false;
    auto lines = read_lines(path, ok);
    if (!ok) {
        std::cerr << "fingerprint login: " << path << " cannot be read (is SDDM installed?)\n";
        return 2;
    }
    const std::string helper = empty_password_helper();
    if (on && (helper.empty() || !have_pam_fprintd())) {
        std::cerr << "fingerprint login: " << (helper.empty() ? "b1air-empty-password is not installed for root"
                                                               : "pam_fprintd is not installed") << "\n";
        return 2;
    }

    // Whatever block is there goes; with "on" a fresh one goes in.
    std::vector<std::string> out;
    bool inside = false;
    for (const auto& l : lines) {
        if (l == kBegin) inside = true;
        else if (inside && l == kEnd) inside = false;
        else if (!inside) out.push_back(l);
    }
    if (on) {
        // Just before the password check — the distribution's auth stack
        // (`@include common-auth`, `auth include system-login`, `auth
        // substack password-auth`) or pam_unix itself — and after whatever
        // comes first: pam_nologin, "not root" and the like must still be
        // able to refuse, and a `sufficient` line placed above them would
        // skip them.
        auto first_auth = out.end();
        for (auto it = out.begin(); it != out.end(); ++it) {
            std::vector<std::string> word;
            for (size_t i = 0; i < it->size();) {
                const size_t a = it->find_first_not_of(" \t", i);
                if (a == std::string::npos || (*it)[a] == '#') break;
                const size_t b = std::min(it->find_first_of(" \t", a), it->size());
                word.push_back(it->substr(a, b - a));
                i = b;
            }
            if (word.empty()) continue;
            const bool include_auth = word[0] == "@include" && word.size() > 1 && word[1].find("auth") != std::string::npos;
            const bool auth = word[0] == "auth" || word[0] == "-auth";
            const bool stack = auth && word.size() > 2 && (word[1] == "include" || word[1] == "substack");
            const bool unix_line = auth && word.size() > 2 && word[2].find("pam_unix") != std::string::npos;
            if (include_auth || stack || unix_line) {
                first_auth = it;
                break;
            }
        }
        if (first_auth == out.end()) {
            std::cerr << "fingerprint login: " << path << " has no password check to go before\n";
            return 2;
        }
        // An empty password: the helper succeeds and the reader is asked;
        // pam_fprintd matching is enough. A typed one: the helper fails and
        // the reader's line is skipped. Either way what follows is the
        // distribution's own stack, unchanged.
        out.insert(first_auth, {kBegin,
                                "auth  [success=ignore default=1]  pam_exec.so quiet expose_authtok " + helper,
                                "auth  sufficient  pam_fprintd.so max-tries=3 timeout=30",
                                kEnd});
    }
    std::string text;
    for (const auto& l : out) text += l + "\n";
    struct stat st{};
    const mode_t mode = stat(path.c_str(), &st) == 0 ? (st.st_mode & 07777) : 0644;
    if (!write_atomically(path, text, mode)) {
        std::cerr << "fingerprint login: cannot write " << path << ": " << std::strerror(errno) << "\n";
        return 1;
    }

    // For the greeter: present when on (a QML file, as it loads its palette).
    if (!std::getenv("B1AIR_TEST_SDDM_PAM")) {
        if (on) {
            mkdir("/etc/b1air", 0755);
            (void)write_atomically(kGreeterFlag, "import QtQuick\nQtObject {}\n", 0644);
        } else {
            unlink(kGreeterFlag);
        }
    }
    std::cout << (on ? "done enabled" : "done disabled") << std::endl;
    return 0;
}

} // namespace b1air::fingerprint
