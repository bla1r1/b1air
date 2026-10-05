#include "idle.hpp"

#include "proc_scan.hpp"
#include "runtime.hpp"
#include "settings_manager.hpp"
#include "sway_ipc.hpp"
#include "system_control.hpp"

#include <nlohmann/json.hpp>
#include <systemd/sd-bus.h>
#include <wayland-client.h>

#include <algorithm>
#include <cerrno>
#include <chrono>
#include <cstring>
#include <fcntl.h>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <iostream>
#include <poll.h>
#include <string>
#include <sys/inotify.h>
#include <sys/stat.h>
#include <thread>
#include <unistd.h>
#include <vector>

#include "ext-idle-notify-v1-client-protocol.h"

namespace b1air::idle {

namespace {

std::string read_small(const std::string& path) {
    const int fd = open(path.c_str(), O_RDONLY | O_CLOEXEC);
    if (fd < 0) return {};
    char buf[64] = {0};
    const ssize_t n = read(fd, buf, sizeof(buf) - 1);
    close(fd);
    std::string s = n > 0 ? std::string(buf, static_cast<size_t>(n)) : std::string();
    while (!s.empty() && (s.back() == '\n' || s.back() == ' ')) s.pop_back();
    return s;
}

void touch(const std::string& path) {
    const int fd = open(path.c_str(), O_WRONLY | O_CREAT | O_CLOEXEC, 0600);
    if (fd < 0) return;
    futimens(fd, nullptr);
    close(fd);
}

bool held() {
    return access(runtime_path("caffeine.state").c_str(), F_OK) == 0
        || access(runtime_path("gamepad.state").c_str(), F_OK) == 0;
}

// ── Screens ──────────────────────────────────────────────────────────────────

struct Outputs {
    std::string primary;
    std::vector<std::string> others;
};

// The main screen as the shell has it (Screens.qml): the one chosen in
// Settings → Displays while it is connected, else the first sway lists.
Outputs outputs() {
    Outputs o;
    SwayIPC ipc;
    if (!ipc.connect()) return o;
    const auto list = nlohmann::json::parse(ipc.get_outputs(), nullptr, false);
    if (!list.is_array()) return o;
    std::vector<std::string> names;
    for (const auto& out : list)
        if (out.value("active", false)) names.push_back(out.value("name", ""));
    if (names.empty()) return o;
    const std::string pinned = SettingsManager::get_json_string("barPrimaryOutput");
    o.primary = names.front();
    for (const auto& n : names)
        if (n == pinned) o.primary = n;
    for (const auto& n : names)
        if (n != o.primary) o.others.push_back(n);
    return o;
}

std::string quoted(const std::string& name) {
    std::string q = "\"";
    for (char c : name) {
        if (c == '"' || c == '\\') q += '\\';
        q += c;
    }
    return q + "\"";
}

void power(const std::string& name, bool on) {
    (void)SwayIPC::run("output " + quoted(name) + " power " + (on ? "on" : "off"));
}

bool secondary_off_when_idle() { return SettingsManager::get_json_bool("idleSecondaryOff", true); }
bool secondary_off_when_locked() { return SettingsManager::get_json_bool("lockSecondaryOff", true); }

// Screens back on after input: all of them, or, while locked, the main one
// (the others stay dark until the lock is opened).
void wake_screens() {
    const Outputs o = outputs();
    if (!o.primary.empty()) power(o.primary, true);
    const bool keep_off = locked() && secondary_off_when_locked();
    for (const auto& n : o.others) power(n, !keep_off);
}

void secondaries(bool on) {
    for (const auto& n : outputs().others) power(n, on);
}

void focus_mark(const char* name) { touch(runtime_path(name)); }

// ── Stages ───────────────────────────────────────────────────────────────────

enum class Stage { Dim, Lock, Screens, Suspend };

struct Notification {
    Stage stage;
    int seconds;
    struct ext_idle_notification_v1* object = nullptr;
    bool idle = false;
};

void on_idled(Stage stage) {
    switch (stage) {
    case Stage::Dim:
        (void)SystemControl::ddc_dim();
        focus_mark("focus-away");   // the break reminder's "nobody is here"
        if (secondary_off_when_idle()) secondaries(false);
        break;
    case Stage::Lock:
        (void)SystemControl::lock_session_async();
        break;
    case Stage::Screens:
        (void)SwayIPC::run("output * power off");
        // "Lock when the screen turns off" (Settings → Power), for whoever
        // wants the screen off sooner than the lock — or no lock timer at all.
        if (SettingsManager::get_json_bool("lockWithScreenOff", false)) (void)SystemControl::lock_session_async();
        break;
    case Stage::Suspend:
        (void)SystemControl::suspend_system();
        break;
    }
}

void on_resumed(Stage stage) {
    switch (stage) {
    case Stage::Dim:
        // Locked with "Dim screen on lock": it stays dim until opened.
        if (!(locked() && SettingsManager::get_json_bool("dimOnLock", true))) (void)SystemControl::ddc_undim();
        focus_mark("focus-back");
        wake_screens();
        break;
    case Stage::Lock:
        break;
    case Stage::Screens:
    case Stage::Suspend:
        wake_screens();
        if (!(locked() && SettingsManager::get_json_bool("dimOnLock", true))) (void)SystemControl::ddc_undim();
        break;
    }
}

void notification_idled(void* data, struct ext_idle_notification_v1*) {
    auto* n = static_cast<Notification*>(data);
    n->idle = true;
    on_idled(n->stage);
}
void notification_resumed(void* data, struct ext_idle_notification_v1*) {
    auto* n = static_cast<Notification*>(data);
    if (!n->idle) return;
    n->idle = false;
    on_resumed(n->stage);
}
const struct ext_idle_notification_v1_listener kNotificationListener = {notification_idled, notification_resumed};

struct Wayland {
    struct wl_display* display = nullptr;
    struct wl_seat* seat = nullptr;
    struct ext_idle_notifier_v1* notifier = nullptr;
    std::vector<Notification*> stages;
};

void registry_global(void* data, struct wl_registry* registry, uint32_t name, const char* interface, uint32_t) {
    auto* w = static_cast<Wayland*>(data);
    if (std::strcmp(interface, wl_seat_interface.name) == 0 && !w->seat)
        w->seat = static_cast<wl_seat*>(wl_registry_bind(registry, name, &wl_seat_interface, 1));
    else if (std::strcmp(interface, ext_idle_notifier_v1_interface.name) == 0)
        // Version 1's notification: idle inhibitors (a video playing) count.
        w->notifier = static_cast<ext_idle_notifier_v1*>(
            wl_registry_bind(registry, name, &ext_idle_notifier_v1_interface, 1));
}
void registry_global_remove(void*, struct wl_registry*, uint32_t) {}
const struct wl_registry_listener kRegistry = {registry_global, registry_global_remove};

bool dim_stage_idle(const Wayland& w) {
    for (const auto* n : w.stages)
        if (n->stage == Stage::Dim && n->idle) return true;
    return false;
}

void clear_stages(Wayland& w) {
    for (auto* n : w.stages) {
        // A stage dropped while idle is undone, as input would have.
        if (n->idle) on_resumed(n->stage);
        ext_idle_notification_v1_destroy(n->object);
        delete n;
    }
    w.stages.clear();
}

// The timeouts for the power source now, in seconds, 0 for never. Plugged
// in: dimTimeout, lockTimeout, dpmsTimeout, suspendTimeout (with
// autoSuspend). On battery: the same keys with "Battery" after them, with
// shorter defaults — the profiles KDE and Windows keep.
struct Profile {
    bool battery = false;
    int dim = 0, lock = 0, screens = 0, suspend = 0;
    std::string key() const {
        return std::string(battery ? "battery/" : "ac/") + std::to_string(dim) + "/" + std::to_string(lock) + "/"
             + std::to_string(screens) + "/" + std::to_string(suspend);
    }
};

Profile profile() {
    Profile p;
    auto get = [](const char* key, int def) { return std::clamp(SettingsManager::get_json_int(key, def), 0, 86400); };
    p.battery = !SystemControl::on_ac_power();
    if (p.battery) {
        p.dim = get("dimTimeoutBattery", 120);
        p.lock = get("lockTimeoutBattery", 300);
        p.screens = get("dpmsTimeoutBattery", 300);
        p.suspend = get("suspendTimeoutBattery", 900);
    } else {
        const DesktopSettings s = SettingsManager::load();
        p.dim = s.dimTimeout;
        p.lock = s.lockTimeout;
        p.screens = s.dpmsTimeout;
        p.suspend = SettingsManager::get_json_bool("autoSuspend", true) ? s.suspendTimeout : 0;
    }
    return p;
}

// The stages for the settings as they are now; none while held awake.
void build_stages(Wayland& w) {
    clear_stages(w);
    if (held()) {
        std::cerr << "[b1air-idle] held awake (caffeine or a gamepad)\n";
        return;
    }
    const Profile p = profile();
    const std::pair<Stage, int> want[] = {
        {Stage::Dim, p.dim}, {Stage::Lock, p.lock}, {Stage::Screens, p.screens}, {Stage::Suspend, p.suspend}};
    for (const auto& [stage, seconds] : want) {
        if (seconds <= 0) continue;   // 0: never
        auto* n = new Notification{stage, seconds};
        n->object = ext_idle_notifier_v1_get_idle_notification(w.notifier, static_cast<uint32_t>(seconds) * 1000u, w.seat);
        ext_idle_notification_v1_add_listener(n->object, &kNotificationListener, n);
        w.stages.push_back(n);
    }
    auto shown = [](int v) { return v > 0 ? std::to_string(v) + "s" : std::string("never"); };
    std::cerr << "[b1air-idle] " << (p.battery ? "on battery" : "plugged in") << ": dim " << shown(p.dim)
              << ", lock " << shown(p.lock) << ", screens off " << shown(p.screens) << ", sleep "
              << shown(p.suspend) << "\n";
}

// What the stages are made of: when this has not changed, a write to the
// settings file (any toggle on any page) leaves the countdown alone.
std::string stage_key() { return profile().key(); }

// ── logind ───────────────────────────────────────────────────────────────────

struct Logind {
    sd_bus* bus = nullptr;
    int delay_fd = -1;   // held until the lock is up, then let go for sleep
    int keys_fd = -1;    // the lid and the power button are ours (see below)
};

// logind acts on the lid and the power button itself (HandleLidSwitch,
// HandlePowerKey), which is a system file and the same for every account.
// With a block inhibitor it leaves them to the session, which does what
// Settings → Power says — but only for what sway is actually bound to send
// here, so an older config without those bindings keeps logind's behaviour.
// The inhibitor goes with this process, and logind takes over again.
void take_keys(Logind& l) {
    if (l.keys_fd >= 0 || !l.bus) return;
    // The config as sway has it (GET_CONFIG gives the main file only, not
    // what it includes), and the conf.d files it includes; lines that are
    // not comments.
    std::string text;
    {
        SwayIPC ipc;
        if (ipc.connect()) {
            const auto config = nlohmann::json::parse(ipc.send_command(9), nullptr, false);   // GET_CONFIG
            if (config.is_object()) text = config.value("config", "");
        }
        std::error_code ec;
        for (const auto& e : std::filesystem::directory_iterator(home_dir() + "/.config/sway/conf.d", ec)) {
            if (e.path().extension() != ".conf") continue;
            std::ifstream f(e.path());
            text += "\n" + std::string(std::istreambuf_iterator<char>(f), std::istreambuf_iterator<char>());
        }
    }
    bool lid = false, key = false;
    std::istringstream lines(text);
    for (std::string line; std::getline(lines, line);) {
        const auto start = line.find_first_not_of(" \t");
        if (start == std::string::npos || line[start] == '#') continue;
        if (line.find("b1air-daemon lid close") != std::string::npos) lid = true;
        if (line.find("b1air-daemon power-key") != std::string::npos) key = true;
    }
    std::string what;
    if (lid) what = "handle-lid-switch";
    if (key) what += what.empty() ? "handle-power-key" : ":handle-power-key";
    if (what.empty()) return;
    sd_bus_message* reply = nullptr;
    sd_bus_error error = SD_BUS_ERROR_NULL;
    if (sd_bus_call_method(l.bus, "org.freedesktop.login1", "/org/freedesktop/login1",
                           "org.freedesktop.login1.Manager", "Inhibit", &error, &reply, "ssss",
                           what.c_str(), "b1air", "The lid and power button do what Settings says", "block") >= 0) {
        int fd = -1;
        if (sd_bus_message_read(reply, "h", &fd) >= 0 && fd >= 0) l.keys_fd = fcntl(fd, F_DUPFD_CLOEXEC, 3);
        std::cerr << "[b1air-idle] handling " << what << " (Settings → Power)\n";
    } else {
        std::cerr << "[b1air-idle] logind keeps the lid and power button: " << (error.message ? error.message : "refused") << "\n";
    }
    sd_bus_error_free(&error);
    sd_bus_message_unref(reply);
}

void take_delay(Logind& l) {
    if (l.delay_fd >= 0 || !l.bus) return;
    sd_bus_message* reply = nullptr;
    sd_bus_error error = SD_BUS_ERROR_NULL;
    if (sd_bus_call_method(l.bus, "org.freedesktop.login1", "/org/freedesktop/login1",
                           "org.freedesktop.login1.Manager", "Inhibit", &error, &reply, "ssss",
                           "sleep", "b1air", "Lock the screen before sleeping", "delay") >= 0) {
        int fd = -1;
        if (sd_bus_message_read(reply, "h", &fd) >= 0 && fd >= 0) l.delay_fd = fcntl(fd, F_DUPFD_CLOEXEC, 3);
    }
    sd_bus_error_free(&error);
    sd_bus_message_unref(reply);
}

void release_delay(Logind& l) {
    if (l.delay_fd >= 0) close(l.delay_fd);
    l.delay_fd = -1;
}

// Lock, and give the lock screen a moment to be up before letting go of
// the delay: otherwise the machine sleeps first and the desktop is what
// shows for a moment on waking.
void lock_and_wait() {
    (void)SystemControl::lock_session_async();
    for (int i = 0; i < 60 && !locked(); ++i) std::this_thread::sleep_for(std::chrono::milliseconds(50));
}

int on_prepare_for_sleep(sd_bus_message* m, void* data, sd_bus_error*) {
    auto* l = static_cast<Logind*>(data);
    int going = 0;
    if (sd_bus_message_read(m, "b", &going) < 0) return 0;
    if (going) {
        if (SettingsManager::get_json_bool("lockOnSleep", true)) lock_and_wait();
        release_delay(*l);
    } else {
        take_delay(*l);
        wake_screens();
        (void)SystemControl::ddc_undim();
    }
    return 0;
}

int on_lock_signal(sd_bus_message*, void*, sd_bus_error*) {
    (void)SystemControl::lock_session_async();
    return 0;
}

void open_logind(Logind& l) {
    if (sd_bus_open_system(&l.bus) < 0) {
        l.bus = nullptr;
        std::cerr << "[b1air-idle] no system bus: no lock before sleep\n";
        return;
    }
    sd_bus_match_signal(l.bus, nullptr, "org.freedesktop.login1", "/org/freedesktop/login1",
                        "org.freedesktop.login1.Manager", "PrepareForSleep", on_prepare_for_sleep, &l);
    // This session's Lock signal: `loginctl lock-session`, a lid or a power
    // key set to lock.
    if (const char* id = std::getenv("XDG_SESSION_ID"); id && *id) {
        sd_bus_message* reply = nullptr;
        sd_bus_error error = SD_BUS_ERROR_NULL;
        if (sd_bus_call_method(l.bus, "org.freedesktop.login1", "/org/freedesktop/login1",
                               "org.freedesktop.login1.Manager", "GetSession", &error, &reply, "s", id) >= 0) {
            const char* path = nullptr;
            if (sd_bus_message_read(reply, "o", &path) >= 0 && path)
                sd_bus_match_signal(l.bus, nullptr, "org.freedesktop.login1", path,
                                    "org.freedesktop.login1.Session", "Lock", on_lock_signal, nullptr);
        }
        sd_bus_error_free(&error);
        sd_bus_message_unref(reply);
    }
    take_delay(l);
    take_keys(l);
}

} // namespace

bool locked() { return read_small(runtime_path("lock-state")) == "locked"; }

void reload() { touch(runtime_path("idle-reload")); }

void run(const volatile int* running) {
    // The compositor first: the session starts this as sway comes up.
    Wayland w;
    for (int i = 0; *running && i < 100 && !w.display; ++i) {
        w.display = wl_display_connect(nullptr);
        if (!w.display) std::this_thread::sleep_for(std::chrono::milliseconds(200));
    }
    if (!w.display) {
        std::cerr << "[b1air-idle] no Wayland display; nothing will dim, lock or sleep on its own\n";
        return;
    }
    struct wl_registry* registry = wl_display_get_registry(w.display);
    wl_registry_add_listener(registry, &kRegistry, &w);
    wl_display_roundtrip(w.display);
    if (!w.seat || !w.notifier) {
        std::cerr << "[b1air-idle] the compositor has no ext-idle-notify; nothing will dim, lock or sleep on its own\n";
        wl_display_disconnect(w.display);
        return;
    }

    // "locked" left behind by a lock screen that is not running (it
    // crashed, or the session before this one had it up) would keep the
    // other screens dark on every wake.
    if (locked() && !proc::running("b1air-lock")) {
        const int fd = open(runtime_path("lock-state").c_str(), O_WRONLY | O_TRUNC | O_CLOEXEC);
        if (fd >= 0) {
            (void)!write(fd, "unlocked\n", 9);
            close(fd);
        }
    }

    const int in = inotify_init1(IN_NONBLOCK | IN_CLOEXEC);
    const std::string rt = runtime_dir();
    const std::filesystem::path settings_file = SettingsManager::get_settings_filepath();
    if (in >= 0) {
        inotify_add_watch(in, rt.c_str(), IN_CREATE | IN_DELETE | IN_CLOSE_WRITE | IN_MOVED_TO | IN_ATTRIB);
        inotify_add_watch(in, settings_file.parent_path().c_str(), IN_CLOSE_WRITE | IN_MOVED_TO);
    }

    Logind logind;
    open_logind(logind);

    build_stages(w);
    wl_display_flush(w.display);
    std::string last_key = stage_key();
    auto next_power_check = std::chrono::steady_clock::now() + std::chrono::seconds(5);
    bool was_locked = locked();
    bool dimmed_for_lock = false;
    bool was_held = held();

    while (*running) {
        while (wl_display_prepare_read(w.display) != 0) wl_display_dispatch_pending(w.display);
        wl_display_flush(w.display);

        pollfd fds[3] = {{wl_display_get_fd(w.display), POLLIN, 0}, {in, POLLIN, 0}, {-1, 0, 0}};
        int timeout = 1000;   // to notice *running
        if (logind.bus) {
            fds[2].fd = sd_bus_get_fd(logind.bus);
            fds[2].events = static_cast<short>(sd_bus_get_events(logind.bus));
            uint64_t usec = 0;
            if (sd_bus_get_timeout(logind.bus, &usec) >= 0 && usec != UINT64_MAX) {
                timespec now{};
                clock_gettime(CLOCK_MONOTONIC, &now);
                const uint64_t now_us = static_cast<uint64_t>(now.tv_sec) * 1000000u + static_cast<uint64_t>(now.tv_nsec) / 1000u;
                const uint64_t wait_ms = usec > now_us ? (usec - now_us) / 1000u : 0;
                if (wait_ms < static_cast<uint64_t>(timeout)) timeout = static_cast<int>(wait_ms);
            }
        }
        const int r = poll(fds, 3, timeout);
        if (r < 0 && errno != EINTR) { wl_display_cancel_read(w.display); break; }
        if (r > 0 && (fds[0].revents & POLLIN)) {
            if (wl_display_read_events(w.display) < 0) break;
        } else {
            wl_display_cancel_read(w.display);
        }
        if (r > 0 && (fds[0].revents & (POLLERR | POLLHUP))) break;
        if (wl_display_dispatch_pending(w.display) < 0) break;

        // A logind that went away (restarted, the bus closed) leaves its
        // socket hung up: poll returned at once on every pass and this loop
        // ran a core at 100% for the rest of the session. Dropped, and
        // connected again on the five-second check below.
        if (logind.bus) {
            int pr;
            while ((pr = sd_bus_process(logind.bus, nullptr)) > 0) {}
            const bool hung = r > 0 && fds[2].fd >= 0 && (fds[2].revents & (POLLHUP | POLLERR | POLLNVAL));
            if (pr < 0 || hung) {
                std::cerr << "[b1air-idle] lost the system bus; connecting again\n";
                release_delay(logind);
                if (logind.keys_fd >= 0) close(logind.keys_fd);
                logind.keys_fd = -1;
                sd_bus_flush_close_unref(logind.bus);
                logind.bus = nullptr;
            }
        }

        // Plugged in or unplugged: the other profile. Looked at every few
        // seconds — sysfs reads, no process.
        if (std::chrono::steady_clock::now() >= next_power_check) {
            next_power_check = std::chrono::steady_clock::now() + std::chrono::seconds(5);
            if (!logind.bus) open_logind(logind);
            const std::string key = stage_key();
            if (key != last_key) {
                last_key = key;
                build_stages(w);
            }
        }

        if (r > 0 && (fds[1].revents & POLLIN)) {
            alignas(inotify_event) char buf[4096];
            bool rebuild = false;
            while (true) {
                const ssize_t n = read(in, buf, sizeof(buf));
                if (n <= 0) break;
                for (char* p = buf; p < buf + n;) {
                    const auto* ev = reinterpret_cast<const inotify_event*>(p);
                    const std::string name = ev->len ? ev->name : "";
                    if (name == "idle-reload" || name == "caffeine.state" || name == "gamepad.state"
                        || name == settings_file.filename().string())
                        rebuild = true;
                    p += sizeof(inotify_event) + ev->len;
                }
            }
            // The lock screen came up or went away.
            const bool now_locked = locked();
            if (now_locked != was_locked) {
                was_locked = now_locked;
                if (secondary_off_when_locked()) secondaries(!now_locked);
                // "Dim screen on lock" (Settings → Power), however the lock
                // was started: a key, the timer, the lid, before sleep. It
                // used to happen only on the one path that waited for the
                // lock to close.
                if (now_locked && SettingsManager::get_json_bool("dimOnLock", true)) {
                    (void)SystemControl::ddc_dim();
                    dimmed_for_lock = true;
                } else if (!now_locked && dimmed_for_lock) {
                    // Unless the idle dim is still on (nobody touched
                    // anything): it undims itself on input.
                    if (!dim_stage_idle(w)) (void)SystemControl::ddc_undim();
                    dimmed_for_lock = false;
                }
            }
            if (rebuild) {
                const bool now_held = held();
                const std::string key = stage_key();
                const bool asked = access(runtime_path("idle-reload").c_str(), F_OK) == 0;
                if (now_held != was_held || key != last_key || asked) {
                    unlink(runtime_path("idle-reload").c_str());
                    build_stages(w);
                }
                last_key = key;
                was_held = now_held;
            }
        }
    }

    clear_stages(w);
    release_delay(logind);
    if (logind.keys_fd >= 0) close(logind.keys_fd);
    if (logind.bus) sd_bus_flush_close_unref(logind.bus);
    if (in >= 0) close(in);
    if (w.notifier) ext_idle_notifier_v1_destroy(w.notifier);
    wl_registry_destroy(registry);
    wl_display_disconnect(w.display);
}

} // namespace b1air::idle
