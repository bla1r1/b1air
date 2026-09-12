#include "session_manager.hpp"
#include <nlohmann/json.hpp>
#include "settings_manager.hpp"
#include "system_control.hpp"
#include "sway_ipc.hpp"
#include "focustime_db.hpp"
#include "daemon_dbus.hpp"
#include "runtime.hpp"
#include "proc_util.hpp"
#include <spawn.h>
#include <cstring>

#include <iostream>
#include <thread>
#include <vector>
#include <csignal>
#include <cstdlib>
#include <unistd.h>
#include <sys/stat.h>
#include <cstring>
#include <cctype>
#include <sys/wait.h>
#include <fcntl.h>
#include <filesystem>
#include <array>
#include <mutex>
#include <chrono>

namespace b1air {

static volatile sig_atomic_t g_session_running = 1;

static void session_sig_handler(int) {
    g_session_running = 0;
}

// ── Spawn helper that runs command in background detached ────────────────────
static void spawn_shell_detached(const std::string& cmd) {
    if (cmd.empty() || cmd.size() > 4096) return;
    const pid_t pid = fork();
    if (pid < 0) return;
    if (pid == 0) {
        setsid();
        setenv("QT_QPA_PLATFORM", "wayland;xcb", 1);
        const int null_fd = open("/dev/null", O_RDWR | O_CLOEXEC);
        if (null_fd >= 0) {
            dup2(null_fd, STDIN_FILENO); dup2(null_fd, STDOUT_FILENO); dup2(null_fd, STDERR_FILENO);
            if (null_fd > STDERR_FILENO) close(null_fd);
        }
        execl("/bin/sh", "sh", "-c", cmd.c_str(), static_cast<char*>(nullptr));
        _exit(127);
    }
}

// Every long-lived helper this session starts goes through util::spawn_detached,
// which double-forks so the grandchild is orphaned and reaped by init.
//
// This used to fork once and never wait, so the shell, the polkit agent and the
// rest stayed children of the daemon — and when one of them exited it became a
// zombie that nothing reaped, because the daemon runs waitpid() only for the
// commands it needs an exit status from. A zombie is still a process as far as
// pgrep is concerned, so `is_process_running("quickshell")` kept answering yes
// about a shell that had been dead for hours. That is not a tidiness problem:
// it is what made the shell's own restart check unable to see a crash.
static void spawn_argv_detached(const std::vector<std::string>& args) {
    (void)util::spawn_detached(args);
}

static bool run_status(const std::vector<std::string>& args) {
    if (args.empty()) return false;
    std::vector<char*> argv;
    for (const auto& arg : args) argv.push_back(const_cast<char*>(arg.c_str()));
    argv.push_back(nullptr);
    const pid_t pid = fork();
    if (pid < 0) return false;
    if (pid == 0) {
        const int null_fd = open("/dev/null", O_RDWR | O_CLOEXEC);
        if (null_fd >= 0) {
            dup2(null_fd, STDOUT_FILENO);
            dup2(null_fd, STDERR_FILENO);
            if (null_fd > STDERR_FILENO) close(null_fd);
        }
        execvp(argv[0], argv.data());
        _exit(127);
    }
    int status = 0;
    return waitpid(pid, &status, 0) == pid && WIFEXITED(status) && WEXITSTATUS(status) == 0;
}

static std::string run_capture(const std::vector<std::string>& args) {
    if (args.empty()) return {};
    int pipefd[2];
    if (pipe(pipefd) != 0) return {};
    const pid_t pid = fork();
    if (pid < 0) { close(pipefd[0]); close(pipefd[1]); return {}; }
    if (pid == 0) {
        dup2(pipefd[1], STDOUT_FILENO);
        close(pipefd[0]); close(pipefd[1]);
        std::vector<char*> argv;
        for (const auto& arg : args) argv.push_back(const_cast<char*>(arg.c_str()));
        argv.push_back(nullptr);
        execvp(argv[0], argv.data());
        _exit(127);
    }
    close(pipefd[1]);
    std::string output;
    std::array<char, 512> buffer{};
    ssize_t n;
    while ((n = read(pipefd[0], buffer.data(), buffer.size())) > 0) output.append(buffer.data(), static_cast<size_t>(n));
    close(pipefd[0]);
    int status = 0;
    waitpid(pid, &status, 0);
    return output;
}

static bool safe_custom_command(const std::string& cmd) {
    if (cmd.empty() || cmd.size() > 1024) return false;
    for (unsigned char c : cmd) {
        if (std::iscntrl(c) || c == ';' || c == '&' || c == '|' || c == '`' ||
            c == '$' || c == '<' || c == '>' || c == '\'' || c == '"' ||
            c == '(' || c == ')' || c == '{' || c == '}' || c == '\\') return false;
    }
    return true;
}

// A zombie is not running.
//
// pgrep lists processes in every state, defunct included, so this answered yes
// about a helper that had exited and was waiting to be reaped. `-r` restricts
// the match to running, sleeping and disk-wait — everything except Z and T —
// which is the question actually being asked here: is this thing still doing
// its job.
static bool is_process_running(const std::string& pattern) {
    return run_status({"pgrep", "-r", "DRSW", "-x", pattern})
        || run_status({"pgrep", "-r", "DRSW", "-f", pattern});
}

// ── Focus Tracker Thread ─────────────────────────────────────────────────────
namespace {

/**
 * swayidle's command line, from the settings file.
 *
 * "Automatic sleep" on the Power page wrote `autoSuspend` and nothing read
 * it: the suspend timeout went into this command whatever the toggle said,
 * so a machine with automatic sleep switched off still suspended itself on
 * the timer below the switch. The setting is honoured here — the timeout is
 * simply not part of the command when it is off.
 */
std::string build_swayidle_command(const DesktopSettings& settings) {
    const bool auto_suspend = SettingsManager::get_json_bool("autoSuspend", true);

    std::string cmd = "swayidle -w "
        "lock 'b1air-daemon lock' "
        // The dim timeout is already the desktop's "nobody is here" signal, so
        // the break reminder rides on it rather than running a second idle
        // watch. Without this, continuous screen time was only ever reset by
        // locking, and a machine that never locks reported "600 minutes at the
        // screen without a break" to someone who had been asleep for nine
        // hours.
        "timeout " + std::to_string(settings.dimTimeout) + " 'b1air-daemon ddc dim; b1air-daemon focus away' resume 'b1air-daemon ddc undim; b1air-daemon focus back' "
        "timeout " + std::to_string(settings.lockTimeout) + " 'b1air-daemon power lock' resume 'b1air-daemon ddc undim' "
        "timeout " + std::to_string(settings.dpmsTimeout) + " 'swaymsg \"output * dpms off\"' resume 'swaymsg \"output * dpms on\"; b1air-daemon ddc undim' ";

    if (auto_suspend) {
        cmd += "timeout " + std::to_string(settings.suspendTimeout) +
               " 'b1air-daemon power suspend' resume 'swaymsg \"output * dpms on\"; b1air-daemon ddc undim' ";
    }

    // `loginctl lock-session` only asks logind to emit the session's Lock
    // signal and returns immediately — it doesn't wait for our lock screen to
    // actually be up. That's fine when something is there to catch the signal,
    // but a lid-close suspend (handled entirely by logind's own
    // HandleLidSwitch, never touching b1air-daemon's suspend_system()) has
    // nothing subscribed to it, so the system suspended before the lock screen
    // had rendered — it only appeared to lock on resume, once the spawn that
    // started before sleep finally got to run. Calling the lock command
    // directly, the same one `lock` above uses, blocks before-sleep until the
    // screen is actually up.
    cmd += "before-sleep 'b1air-daemon lock'";
    return cmd;
}

} // namespace

bool SessionManager::restart_swayidle() {
    spawn_shell_detached("pkill -x swayidle");

    // pkill returns before the process is gone, and a new swayidle overlapping
    // the old one leaves two sets of timers running against the same seat —
    // the shorter one wins and the change appears not to have applied.
    //
    // A fixed pause rather than polling is_process_running(): that spawns two
    // pgreps per check, and pgrep counts a zombie as running, so a swayidle
    // that sway has not reaped yet would keep the loop going to its limit
    // every single time. swayidle exits on SIGTERM at once; a quarter second
    // is room to spare, and a stale one would be killed by the next reload
    // anyway.
    usleep(250 * 1000);

    spawn_shell_detached(build_swayidle_command(SettingsManager::load()));
    return true;
}

void SessionManager::run_focus_tracker() {
    // Every failure below used to be a bare `return`. Screen-time tracking then
    // stopped for the rest of the session with nothing said anywhere, and the
    // only symptom was FocusTime quietly reporting "No data" — which looks
    // exactly like a day with no activity.
    SwayIPC ipc;
    if (!ipc.connect()) {
        std::cerr << "[b1air-focus] no sway IPC connection; screen time will not be tracked\n";
        return;
    }

    // A second connection, used only for queries from inside the subscription
    // callback below.
    //
    // `ipc` is parked in subscribe_events()'s blocking read loop, and sway's IPC
    // is one request/one reply on a socket: sending GET_TREE down the subscribed
    // socket makes the tree reply and the event stream interleave, so the
    // callback reads an event where it expected the tree and the read loop then
    // reads the tree where it expected an event. The stream desynchronises on
    // the first window event and tracking stops — which is why the FocusTime
    // database had no new rows while sway was plainly emitting events.
    //
    // The autotiling split below already opens its own connection for exactly
    // this reason; the tree query needs the same treatment.
    SwayIPC query;
    if (!query.connect()) {
        std::cerr << "[b1air-focus] second sway IPC connection failed; screen time will not be tracked\n";
        return;
    }

    FocusTimeDB db;
    if (!db.open()) {
        std::cerr << "[b1air-focus] could not open the focustime database; screen time will not be tracked\n";
        return;
    }

    std::string current_app = "Desktop";
    std::string current_title = "";
    bool current_locked = false;
    auto last_switch_time = std::chrono::system_clock::now();

    // ── The two reminders the settings page offers ───────────────────────────
    //
    // "Hourly Eye Care & Break Reminders — send a gentle notification when
    // continuous screen time reaches 60 minutes" and "Daily Screen Time Limit
    // Goal". Both wrote a value into settings.json that nothing read, so
    // neither ever produced a notification.
    //
    // They belong here rather than in the shell because this is the process
    // that knows when the screen is locked, and continuous screen time means
    // nothing without that: a machine left locked overnight is not eighteen
    // hours of screen time.
    struct WatchState {
        std::mutex m;
        std::chrono::system_clock::time_point since = std::chrono::system_clock::now();
        bool locked = false;
        int64_t reminded_at_minutes = 0;
        std::string goal_notified_date;
    };
    static WatchState watch;

    auto notify = [](const std::string& title, const std::string& body,
                     const std::string& icon) {
        (void)util::spawn_detached({"notify-send", "-a", "FocusTime", "-i", icon, title, body});
    };

    std::thread reminder_th([&notify]() {
        // Its own database handle: SQLite connections are not for sharing
        // across threads, and the tracker's is busy on the event path.
        FocusTimeDB rdb;
        const bool have_db = rdb.open();

        while (g_session_running) {
            std::this_thread::sleep_for(std::chrono::seconds(60));
            if (!g_session_running) break;

            bool locked;
            int64_t minutes;
            int64_t reminded;
            std::chrono::system_clock::time_point since_tp;
            {
                std::lock_guard<std::mutex> lock(watch.m);
                locked = watch.locked;
                since_tp = watch.since;
                minutes = std::chrono::duration_cast<std::chrono::minutes>(
                    std::chrono::system_clock::now() - since_tp).count();
                reminded = watch.reminded_at_minutes;
            }
            if (locked) continue;

            // Away and back, as swayidle saw them. Being idle is not screen
            // time, and coming back from it starts a fresh stretch — the same
            // meaning locking has, arrived at without needing a lock screen.
            const auto mark = [](const char* name) -> std::chrono::system_clock::time_point {
                struct stat st {};
                if (::stat(b1air::runtime_path(name).c_str(), &st) != 0)
                    return std::chrono::system_clock::time_point::min();
                return std::chrono::system_clock::from_time_t(st.st_mtime);
            };
            const auto away = mark("focus-away");
            const auto back = mark("focus-back");

            if (away > back) continue;      // still idle; nobody to remind
            if (back > since_tp) {
                std::lock_guard<std::mutex> lock(watch.m);
                watch.since = back;
                watch.reminded_at_minutes = 0;
                continue;                   // re-measure on the next pass
            }

            // The settings page says "when continuous screen time reaches 60
            // minutes", so 60 it is — named rather than repeated, since the
            // same number decides both the threshold and where the next one
            // lands.
            constexpr int64_t kBreakReminderMinutes = 60;
            if (SettingsManager::get_json_bool("focusBreakReminders", true)
                    && minutes >= reminded + kBreakReminderMinutes) {
                const int64_t mark_at = (minutes / kBreakReminderMinutes) * kBreakReminderMinutes;
                {
                    std::lock_guard<std::mutex> lock(watch.m);
                    watch.reminded_at_minutes = mark_at;
                }
                notify("Time to look away",
                       std::to_string(mark_at) + " minutes at the screen without a break.",
                       "preferences-desktop-screensaver");
            }

            if (!have_db) continue;
            const int goal_hours = SettingsManager::get_json_int("dailyScreenTimeGoal", 8);
            if (goal_hours <= 0) continue;

            const DayStats today = rdb.get_stats_for_date("");
            if (today.total_active_seconds < static_cast<int64_t>(goal_hours) * 3600)
                continue;
            {
                std::lock_guard<std::mutex> lock(watch.m);
                if (watch.goal_notified_date == today.date) continue;
                watch.goal_notified_date = today.date;
            }
            notify("Daily screen time goal reached",
                   "You have passed " + std::to_string(goal_hours)
                       + (goal_hours == 1 ? " hour" : " hours") + " today.",
                   "appointment-soon");
        }
    });
    reminder_th.detach();

    auto flush_interval = [&](const std::string& new_app, const std::string& new_title, bool new_locked) {
        auto now = std::chrono::system_clock::now();
        int64_t start_ts = std::chrono::duration_cast<std::chrono::seconds>(last_switch_time.time_since_epoch()).count();
        int64_t end_ts = std::chrono::duration_cast<std::chrono::seconds>(now.time_since_epoch()).count();

        if (end_ts - start_ts >= 1 && !current_app.empty()) {
            db.log_interval(start_ts, end_ts, current_app, current_title, current_locked);
        }

        current_app = new_app;
        current_title = new_title;
        current_locked = new_locked;
        last_switch_time = now;
    };

    std::cerr << "[b1air-focus] tracking started\n";

    // Nothing thrown in here may leave it: this runs on a detached thread, so
    // an escaping exception is std::terminate for the whole session daemon,
    // not the end of one event. That is exactly how an XWayland window with a
    // null app_id used to end the session (see str_field in sway_ipc.cpp).
    auto on_event = [&]() {
        bool is_locked = (access(runtime_path("swaylock.lock").c_str(), F_OK) == 0);
        WindowInfo win = query.get_focused_window();
        std::string new_app = is_locked ? "Screen Locked" : (win.app_class.empty() ? "Desktop" : win.app_class);
        std::string new_title = is_locked ? "Locked" : win.title;

        if (is_locked != current_locked) {
            // Locking ends the stretch of screen time; unlocking starts a new
            // one. Without this the "60 minutes without a break" reminder
            // counted a locked machine as time at the screen.
            std::lock_guard<std::mutex> lock(watch.m);
            watch.locked = is_locked;
            watch.since = std::chrono::system_clock::now();
            watch.reminded_at_minutes = 0;
        }

        if (new_app != current_app || is_locked != current_locked) {
            flush_interval(new_app, new_title, is_locked);
        }
    };

    bool ok = ipc.subscribe_events({"window", "workspace"}, [&](const std::string&, const std::string&) {
        if (!g_session_running) return;
        try {
            on_event();
        } catch (const std::exception& e) {
            std::cerr << "[b1air-focus] event skipped: " << e.what() << "\n";
        }
    });

    // subscribe_events() only returns when the socket closes or the subscribe
    // handshake fails, so reaching here means tracking has stopped.
    std::cerr << "[b1air-focus] tracking stopped (subscribe returned "
              << (ok ? "true" : "false") << ")\n";

    flush_interval("", "", false);
}

// ── Autotiling: Hyprland's dwindle, in sway ──────────────────────────────────
//
// Whenever focus lands on a tiled window, the next split is set along its
// longer side, so each new window halves the one it opens next to and the
// layout spirals the way Hyprland's dwindle did. Without it sway lines every
// new window up in one row.
//
// This used to live inside the screen-time tracker's event handler, so the
// "Auto-Start FocusTime Daemon" switch on the Screen Time page quietly turned
// window tiling off as well, and any exception in the tracker ended both. It
// has its own thread and its own switch now (Window & Gaps → Automatic split,
// key `autotiling`).
void SessionManager::run_autotiler() {
    SwayIPC events;
    SwayIPC query;
    if (!events.connect() || !query.connect()) {
        std::cerr << "[b1air-tiling] no sway IPC connection; autotiling off\n";
        return;
    }
    // Windows already open when the daemon starts.
    {
        const WindowInfo win = query.get_focused_window();
        query.send_command(0, "[all] opacity 0.5");
        if (win.id > 0) query.send_command(0, "[con_id=" + std::to_string(win.id) + "] opacity 1");
    }
    events.subscribe_events({"window"}, [&](const std::string&, const std::string& payload) {
        if (!g_session_running) return;
        try {
            // Only focus changes and new windows move the split point. Parsed,
            // not substring-matched: sway pretty-prints its events.
            const auto evt = nlohmann::json::parse(payload, nullptr, false);
            const auto ch = evt.is_object() ? evt.find("change") : evt.end();
            const std::string change = (evt.is_object() && ch != evt.end() && ch->is_string())
                ? ch->get<std::string>() : "";
            if (change != "focus" && change != "new")
                return;

            // Unfocused windows at 50%, the focused one opaque, as on Hyprland.
            if (change == "focus") {
                const auto con = evt.find("container");
                if (con != evt.end() && con->is_object() && con->contains("id")
                    && (*con)["id"].is_number_integer()) {
                    query.send_command(0, "[all] opacity 0.5");
                    query.send_command(0, "[con_id=" + std::to_string((*con)["id"].get<int64_t>())
                                              + "] opacity 1");
                }
            }

            if (!SettingsManager::get_json_bool("autotiling", true)) return;
            const WindowInfo win = query.get_focused_window();
            if (win.app_class.empty() && win.title.empty()) return;
            if (win.floating || win.fullscreen || win.width <= 0 || win.height <= 0) return;
            query.send_command(0, win.width > win.height ? "split h" : "split v");
        } catch (const std::exception& e) {
            std::cerr << "[b1air-tiling] event skipped: " << e.what() << "\n";
        }
    });
}

int SessionManager::run_session() {
    std::signal(SIGINT, session_sig_handler);
    std::signal(SIGTERM, session_sig_handler);

    // Startup is occasionally slow enough to notice, with no clear single
    // cause — these timestamps turn the next slow boot into a log line
    // pointing at the actual step, instead of another guess.
    const auto t0 = std::chrono::steady_clock::now();
    auto mark = [&](const char* step) {
        const auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(
            std::chrono::steady_clock::now() - t0).count();
        // stderr, not stdout: sway (which execs this) has its own stdout
        // wired to /dev/null, so anything printed there — this session's
        // entire prior "[b1air-session] ..." log included — was never going
        // anywhere. stderr lands in ~/.local/share/sddm/wayland-session.log.
        std::cerr << "[b1air-session] +" << ms << "ms: " << step << "\n";
    };

    std::cout << "[b1air-session] Initializing native b1air Desktop Session Manager...\n";

    // A session started by a launcher/SSH helper may not inherit the variables
    // normally supplied by SDDM.  Without these, Qt/Quickshell cannot reach the
    // user's Wayland and D-Bus sessions, so every panel silently becomes a
    // no-op.  Derive only the standard per-user values; never import arbitrary
    // shell variables into the activation environment.
    if (!std::getenv("XDG_RUNTIME_DIR")) {
        setenv("XDG_RUNTIME_DIR", (std::string("/run/user/") + std::to_string(getuid())).c_str(), 1);
    }
    if (!std::getenv("DBUS_SESSION_BUS_ADDRESS")) {
        setenv("DBUS_SESSION_BUS_ADDRESS",
               (std::string("unix:path=") + std::getenv("XDG_RUNTIME_DIR")).append("/bus").c_str(), 1);
    }

    // 0. Auto-discover Wayland Display if unset
    const char* wdisp = std::getenv("WAYLAND_DISPLAY");
    if (!wdisp || strlen(wdisp) == 0) {
        const char* rundir = std::getenv("XDG_RUNTIME_DIR");
        if (rundir) {
            for (int i = 0; i < 5; ++i) {
                std::string sock = std::string(rundir) + "/wayland-" + std::to_string(i);
                if (access(sock.c_str(), F_OK) == 0) {
                    setenv("WAYLAND_DISPLAY", ("wayland-" + std::to_string(i)).c_str(), 1);
                    break;
                }
            }
        }
    }

    const char* swaysock = std::getenv("SWAYSOCK");
    if (!swaysock || strlen(swaysock) == 0) {
        std::error_code ec;
        const std::filesystem::path run_user = std::filesystem::path("/run/user") / std::to_string(getuid());
        std::filesystem::file_time_type newest{};
        std::string newest_socket;
        for (const auto& entry : std::filesystem::directory_iterator(run_user, ec)) {
            const std::string name = entry.path().filename().string();
            if (name.rfind("sway-ipc.", 0) != 0 || !name.ends_with(".sock")) continue;
            const auto mtime = entry.last_write_time(ec);
            if (newest_socket.empty() || mtime > newest) {
                newest = mtime;
                newest_socket = entry.path().string();
            }
        }
        if (!newest_socket.empty()) setenv("SWAYSOCK", newest_socket.c_str(), 1);
    }

    // 1. Export Wayland & Qt Environment
    setenv("XDG_CURRENT_DESKTOP", "sway", 1);
    setenv("XDG_SESSION_TYPE", "wayland", 1);
    setenv("QT_QPA_PLATFORM", "wayland;xcb", 1);
    setenv("QSG_RHI_BACKEND", "opengl", 1);
    setenv("QSG_RENDER_LOOP", "basic", 1);
    setenv("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1", 1);
    setenv("QT_AUTO_SCREEN_SCALE_FACTOR", "0", 1);
    setenv("MOZ_ENABLE_WAYLAND", "1", 1);

    // 2. DBus Activation Environment
    // Do not publish the whole login environment to every user service.  It may
    // contain credentials inherited from a shell, editor, or development tool.
    // Only export variables required to activate the desktop session.
    run_status({"dbus-update-activation-environment", "--systemd",
                "DBUS_SESSION_BUS_ADDRESS", "XDG_RUNTIME_DIR", "PATH", "HOME",
                "USER", "LANG", "WAYLAND_DISPLAY", "SWAYSOCK",
                "XDG_CURRENT_DESKTOP", "XDG_SESSION_DESKTOP", "XDG_SESSION_TYPE",
                "QT_QPA_PLATFORM", "QT_QUICK_BACKEND", "QSG_RHI_BACKEND",
                "QSG_RENDER_LOOP", "MOZ_ENABLE_WAYLAND", "GDK_BACKEND",
                "WLR_RENDERER", "WLR_RENDERER_ALLOW_SOFTWARE", "WLR_NO_HARDWARE_CURSORS"});
    mark("dbus-update-activation-environment done");

    // 3. GNOME / GTK Theme GSettings
    // Through appearance_apply, from the theme and Appearance -> Other
    // applications. This set gtk-theme to Tokyonight-Dark, which is not
    // installed, so GTK apps fell back to stock Adwaita.
    SystemControl::appearance_apply();
    mark("appearance applied");

    // 4. Load Desktop Settings
    DesktopSettings settings = SettingsManager::load();
    SettingsManager::apply_to_sway(settings);
    mark("settings loaded and applied");

    // 5. Restore Wallpaper
    SystemControl::wallpaper_restore();
    mark("wallpaper restored");

    // Night light was saved as on and never turned back on: the toggle kept
    // saying "Enabled" at every login over a screen at full blue.
    if (SettingsManager::get_json_bool("nightLightEnabled", false)) {
        SystemControl::night_light_on(SettingsManager::get_json_int("nightLightTemp", 4000), false);
        mark("night light restored");
    }

    // 6. Spawn Background Threads (Focus tracker, Gamepad inhibitor, Settings inotify watcher)
    //
    // "Auto-Start FocusTime Daemon — launch background activity tracker
    // automatically on login" was a switch with no reader: the tracker started
    // regardless, so someone who did not want their window activity recorded
    // had no way to say so. `b1air-daemon focus` still starts it by hand.
    std::thread tiling_th(SessionManager::run_autotiler);
    tiling_th.detach();

    if (SettingsManager::get_json_bool("focusDaemonAutoStart", true)) {
        std::thread focus_th(SessionManager::run_focus_tracker);
        focus_th.detach();
    } else {
        std::cerr << "[b1air-session] focus tracker not started (focusDaemonAutoStart is off)\n";
    }

    std::thread gamepad_th([&]() {
        while (g_session_running) {
            SystemControl::run_gamepad_inhibit();
            std::this_thread::sleep_for(std::chrono::seconds(2));
        }
    });
    gamepad_th.detach();

    int running_flag = 1;
    std::thread settings_th([&]() {
        SettingsManager::watch_and_apply(&running_flag);
    });
    settings_th.detach();

    // 7. Launch Polkit Agent
    if (!is_process_running("b1air-daemon polkit") && !is_process_running("polkit-gnome")) {
        spawn_argv_detached({"b1air-polkit-agent"});
    }

    // 9. Launch Swayidle
    if (!is_process_running("swayidle")) {
        spawn_shell_detached(build_swayidle_command(settings));
    }

    // 10. The desktop shell, and a supervisor that owns it.
    //
    // The shell used to be started once and never looked at again. If
    // quickshell exits — a crash, an OOM kill, a QML error that takes the
    // whole config down — the desktop loses its bar, every popup, the
    // notifications, the launcher, the lock screen and Alt+Tab, and the only
    // way back is a TTY.
    //
    // systemd units for this exist in .config/systemd/user with the right
    // Restart= lines and are deliberately not enabled: sway execs this daemon
    // directly, so enabling them would run the daemon twice. Supervision
    // belongs where the spawn already happens.
    //
    // The shell is a *direct* child of this thread, launched with posix_spawn
    // and waited on with waitpid. Two earlier attempts polled pgrep on a timer
    // instead and both were wrong in instructive ways: pgrep counts a defunct
    // process as running, so a crashed shell looked alive; and forking from a
    // thread to respawn deadlocked the child in the allocator, which hung the
    // supervisor itself after a single restart. Waiting on a child you own has
    // neither problem — waitpid returns exactly when the shell dies, and there
    // is no zombie because this is what reaps it.
    //
    // Restarts are capped. A shell that dies immediately and repeatedly is
    // broken rather than unlucky — a QML syntax error does exactly that — and
    // respawning it forever would bury the reason in the log and cost a core.
    const std::string qs_main = qml_entry("Main.qml");
    if (qs_main.empty()) {
        std::cerr << "[b1air-session] Main.qml not found; the shell cannot start\n";
    } else {
        std::thread shell_supervisor([qs_main]() {
            constexpr int kMaxRestarts = 5;
            constexpr int kFailureWindowSec = 120;
            // A shell that stayed up this long counts as healthy again, so a
            // crash next week does not inherit today's failure count.
            constexpr int kHealthySec = 300;

            int failures = 0;
            auto window_start = std::chrono::steady_clock::now();

            // A shell that is already up is not ours to supervise. The daemon
            // is restarted more often than the session is — every reinstall
            // does it — and spawning unconditionally gave the desktop two
            // bars, two launchers and two processes fighting over
            // org.freedesktop.Notifications. Wait it out instead: when the
            // one on screen exits, this thread takes over from a clean start
            // and owns every shell after it.
            // Exact process name, not is_process_running(), which falls back to
            // `pgrep -f` and so matches anything with the word anywhere in its
            // command line — a grep, an editor with the config open, a script
            // that mentions it. The supervisor then waits for that to exit and
            // the desktop comes up with no shell at all, which is how this was
            // found: a test script named the binary, the guard saw it, and the
            // bar never appeared.
            while (g_session_running
                   && run_status({"pgrep", "-r", "DRSW", "-x", "quickshell"})) {
                std::this_thread::sleep_for(std::chrono::seconds(2));
            }

            while (g_session_running) {
                // Everything the child needs, prepared before the spawn.
                const char* argv[] = {"quickshell", "-p", qs_main.c_str(), nullptr};

                posix_spawnattr_t attr;
                posix_spawnattr_init(&attr);
                posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETSID);

                pid_t pid = 0;
                const int rc = posix_spawnp(&pid, "quickshell", nullptr, &attr,
                                            const_cast<char* const*>(argv), environ);
                posix_spawnattr_destroy(&attr);

                if (rc != 0) {
                    std::cerr << "[b1air-session] could not start the shell: "
                              << std::strerror(rc) << "\n";
                    std::this_thread::sleep_for(std::chrono::seconds(5));
                    continue;
                }

                const auto started = std::chrono::steady_clock::now();
                int status = 0;
                while (waitpid(pid, &status, 0) < 0 && errno == EINTR) {}
                if (!g_session_running) break;

                const auto now = std::chrono::steady_clock::now();
                const auto uptime = std::chrono::duration_cast<std::chrono::seconds>(
                    now - started).count();

                if (uptime >= kHealthySec) {
                    failures = 0;
                    window_start = now;
                } else if (std::chrono::duration_cast<std::chrono::seconds>(
                               now - window_start).count() > kFailureWindowSec) {
                    failures = 0;
                    window_start = now;
                }

                if (++failures > kMaxRestarts) {
                    std::cerr << "[b1air-session] the shell has exited " << kMaxRestarts
                              << " times in " << kFailureWindowSec
                              << "s; not restarting it again\n";
                    (void)util::spawn_detached({"notify-send", "-u", "critical",
                        "-a", "b1air", "-i", "dialog-error",
                        "Desktop shell keeps crashing",
                        "Giving up after " + std::to_string(kMaxRestarts)
                            + " restarts. Run `quickshell -p " + qs_main + "` to see why."});
                    return;
                }

                std::cerr << "[b1air-session] the shell exited after " << uptime
                          << "s; restarting it (" << failures << "/" << kMaxRestarts << ")\n";
                // A moment's pause so a shell that fails instantly does not
                // spin the loop.
                std::this_thread::sleep_for(std::chrono::seconds(2));
            }
        });
        shell_supervisor.detach();
    }
    mark("shell supervisor started (the shell's own startup begins now, untimed)");

    // 12. Auto-tune compositor effects for software rasterizer / VM (KDE Plasma approach)
    //
    // glxinfo lives in mesa-utils and used to be missing, so this check quietly
    // did nothing and left blur and shadows enabled on a software rasterizer —
    // which is what made scrolling cost most of a core inside a VM. When the
    // tool is unavailable, fall back to looking for a DRM render node: no node
    // means no hardware renderer.
    const std::string glx_info = run_capture({"glxinfo"});
    bool software_render = glx_info.find("llvmpipe") != std::string::npos ||
                           glx_info.find("softpipe") != std::string::npos ||
                           glx_info.find("swrast")   != std::string::npos;
    if (glx_info.empty()) {
        // A virtual GPU still publishes a render node, so its presence proves
        // nothing; the DRM driver name is what distinguishes one.
        char drv[256] = {0};
        const ssize_t n = readlink("/sys/class/drm/card0/device/driver", drv, sizeof(drv) - 1);
        const std::string driver = n > 0 ? std::string(drv) : std::string();
        for (const char* virt : {"virtio", "vmwgfx", "qxl", "bochs", "vboxvideo"}) {
            if (driver.find(virt) != std::string::npos) { software_render = true; break; }
        }
        if (driver.empty()) software_render = true;  // no DRM device at all
    }
    if (software_render) {
        run_status({"swaymsg", "blur disable; shadows disable; default_dim_inactive 0.0"});
    }
    mark("glxinfo / renderer detection done");

    // 12. Autostart Applications from settings.json
    for (const auto& app : settings.autostartApps) {
        if (app == "telegram" && !is_process_running("telegram-desktop")) {
            spawn_argv_detached({"telegram-desktop", "-startintray"});
        } else if (app == "discord" && !is_process_running("discord") && !is_process_running("vesktop")) {
            if (access("/usr/bin/vesktop", X_OK) == 0) spawn_argv_detached({"vesktop", "--start-minimized"});
            else spawn_argv_detached({"discord", "--start-minimized"});
        } else if (app == "spotify" && !is_process_running("spotify")) {
            spawn_argv_detached({"spotify", "--minimized"});
        } else if (app == "steam" && !is_process_running("steam")) {
            spawn_argv_detached({"steam", "-silent"});
        }
    }

    for (const auto& custom_cmd : settings.autostartCustom) {
        // Custom autostart is intentionally shell-backed, but reject command
        // chaining and substitutions so a malformed settings file cannot turn
        // this into an arbitrary command injection primitive.
        if (safe_custom_command(custom_cmd)) {
            spawn_shell_detached(custom_cmd);
        }
    }

    mark("autostart apps launched");
    std::cout << "[b1air-session] All desktop services, UI, and background workers initialized.\n";

    sd_bus *dbus = nullptr;
    DaemonDBus::init_server(&dbus);

    // The camera privacy watch rides on the loop below rather than taking a
    // thread of its own: sd_bus is not thread-safe, the loop already wakes at
    // least once a second, and the check is a walk of /proc with no process
    // spawned. Reported only when it changes, so a shell that is not listening
    // costs nothing.
    bool camera_was = false;
    auto camera_checked = std::chrono::steady_clock::now() - std::chrono::seconds(10);

    // Main session loop processing D-Bus messages with kernel epoll (0% CPU)
    while (g_session_running) {
        if (dbus) {
            const auto now = std::chrono::steady_clock::now();
            if (now - camera_checked >= std::chrono::seconds(2)) {
                camera_checked = now;
                const bool camera_now = SystemControl::camera_in_use();
                if (camera_now != camera_was) {
                    camera_was = camera_now;
                    (void)sd_bus_emit_signal(dbus, "/org/b1air/Daemon", "org.b1air.Daemon",
                                             "CameraInUseChanged", "b", camera_now);
                }
            }

            int r = sd_bus_process(dbus, nullptr);
            if (r < 0) {
                std::this_thread::sleep_for(std::chrono::milliseconds(100));
                continue;
            }
            if (r > 0) continue;
            sd_bus_wait(dbus, (uint64_t) 1000000);
        } else {
            std::this_thread::sleep_for(std::chrono::seconds(1));
        }
    }

    if (dbus) sd_bus_unref(dbus);

    running_flag = 0;
    std::cout << "[b1air-session] Session terminating gracefully.\n";
    return 0;
}

} // namespace b1air
