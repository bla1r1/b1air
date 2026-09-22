#include "sway_ipc.hpp"
#include "focustime_db.hpp"
#include "user_manager.hpp"
#include "system_control.hpp"
#include "settings_manager.hpp"
#include "session_manager.hpp"
#include "daemon_dbus.hpp"
#include "runtime.hpp"
#include "version.hpp"
#include "proc_util.hpp"

#include <iostream>
#include <string>
#include <vector>
#include <chrono>
#include <thread>
#include <csignal>
#include <cstdlib>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>

using namespace b1air;

static volatile sig_atomic_t g_running = 1;

static void handle_signal(int) {
    g_running = 0;
}

static void print_usage(const char* prog) {
    std::cout << "b1air-daemon — Native C++20 Desktop Suite & Session Manager\n\n"
              << "Usage: " << prog << " <command> [options...]\n\n"
              << "Core Desktop & Session Management:\n"
              << "  session                            Start full b1air desktop session (replaces all startup scripts)\n"
              << "  settings [apply|watch]             Manage & live-apply desktop configuration from settings.json\n"
              << "  monitors [restore|apply <json>]    Manage and apply multi-monitor layouts via Sway IPC\n"
              << "  focus                              Run event-driven Sway window focus tracker daemon\n"
              << "  stats [YYYY-MM-DD]                 Get FocusTime statistics as formatted JSON\n"
              << "  user get                           Get user profile details as formatted JSON\n"
              << "  user set-avatar <path>             Update user profile avatar and sync with SDDM\n"
              << "  user set-name <name>               Update user display / full name\n"
              << "  user set-shell <path>              Update user login shell\n"
              << "  user change-password               Launch secure interactive password prompt\n\n"
              << "Compositor & Top Bar Helpers:\n"
              << "  layout                             Get active keyboard layout shorthand (US, UA, DE...)\n"
              << "  fullscreen-toggle                  Toggle fullscreen & auto-center floating window\n"
              << "  wifi-status                        Get top-bar Wi-Fi JSON\n"
              << "  media-status                       Get top-bar Media Player JSON\n"
              << "  media-info                         Get full MPRIS & album art palette JSON for player\n"
              << "  weather [json|current|icon|temp]   Get live weather forecast JSON or current conditions\n"
              << "  schedule                           Get calendar schedule JSON\n"
              << "  appearance apply                   Colour GTK and Qt apps from the theme (Appearance page)\n"
              << "  open-default {terminal|files|browser}\n"
              << "                                     Launch the app chosen in Settings -> Default Apps\n"
              << "  diary                              Open or create today's Obsidian diary note\n"
              << "  dotfiles [status|sync|sys]         Git sync dotfiles repository or launch system upgrade\n"
              << "  updates [check|up]                 Get package updates JSON or launch system upgrade\n\n"
              << "Controls & Hardware:\n"
              << "  volume {get|up [N]|down [N]|mute}  Control audio sink volume & mute\n"
              << "  mic {get|toggle|mute}              Control microphone mute status\n"
              << "  eq {get|apply|preset <name>|set_band <idx> <val>}\n"
              << "                                     10-band EasyEffects equalizer control\n"
              << "  brightness {available|get|up [N]|down [N]|set <pct>}\n"
              << "                                     Control screen backlight brightness\n"
              << "  ddc {list|get <id>|set <id> <pct>|up [N]|down [N]|status|refresh|dim|undim}\n"
              << "                                     Control external monitor brightness via DDC/CI\n"
              << "  kbd-backlight {available|get|up [N]|down [N]|set <pct>|off}\n"
              << "                                     Control keyboard backlight\n"
              << "  wallpaper {set <file> [output]|random [dir]|restore|screens}\n"
              << "                                     Manage and apply desktop & SDDM wallpaper\n"
              << "  night-light {on [temp]|off|toggle|auto}\n"
              << "                                     Control color temperature & blue light filter\n"
              << "  term-theme {list|set <theme>}      List or switch b1air-term color palettes\n"
              << "  gamepad-inhibit                    Run daemon to inhibit idle when gamepads are active\n"
              << "  game-mode {on|off|toggle|status}   Control zero-overhead gaming optimizations\n"
              << "  power {lock|logout|suspend|reboot|shutdown}\n"
              << "                                     Execute session power state transitions\n"
              << "  battery [status|limit <20-100>|behaviour <auto|inhibit-charge|force-discharge>]\n"
              << "                                     Charge limit and charging behaviour, per pack\n"
              << "  capture [--geometry <geom>] [--edit] [--delay <s>] [--full|--area|--window]\n"
              << "                                     Capture screen, copy to clipboard & annotate\n"
              << "  record [toggle|stop] [--geometry <geom>] [--desk-vol <v>] [--mic-vol <v>]\n"
              << "                                     Hardware-accelerated GPU screen & audio recording\n"
              << "  scan-qr [geometry]                 Scan QR code on screen and decode\n"
              << "  polkit [agent|dialog <action> <msg> [user]]\n"
              << "                                     Native Polkit authentication agent & dialog\n"
              << "  reload                             Reload compositor and Quickshell\n"
              << "  lock [quickshell|swaylock]         Lock session with b1air theme\n"
              << "  version                            Print version information\n"
              << "  help                               Show this help message\n";
}

// ── Focus Tracker Daemon ─────────────────────────────────────────────────────
static int run_focus_tracker() {
    std::signal(SIGINT, handle_signal);
    std::signal(SIGTERM, handle_signal);

    // One implementation, in SessionManager. This used to be a second copy of
    // the same forty lines, and the two had already drifted: the tree query
    // here still ran on the socket the subscription was parked on, long after
    // that was fixed in the other. Running the tracker standalone and running
    // it inside a session now exercise the same code.
    SessionManager::run_focus_tracker();

    std::cout << "[b1air-focus] Daemon stopped gracefully.\n";
    return 0;
}

// ── The D-Bus interface, without the bus ─────────────────────────────────────
//
// `b1air-daemon dbus-call <Method> [args…]` runs exactly what the session
// daemon's D-Bus handler for <Method> runs, in this process, and prints the
// method's string result if it has one.
//
// It is the fallback for the B1air.Daemon QML plugin. That plugin talked only
// to org.b1air.Daemon, which exists only while `b1air-daemon session` is up —
// so with the session daemon gone (it crashed on XWayland windows until
// recently), or under KDE or any other desktop where it never runs, every call
// failed and the Settings window put up a critical "DotfilesStatus failed"
// notification each time it looked for updates. The plugin runs this instead
// when the service is not there.
static int run_dbus_call(int argc, char* argv[]) {
    if (argc < 3) return 2;
    const std::string m = argv[2];
    auto arg = [&](int i, const std::string& def = "") -> std::string {
        return (argc > 3 + i) ? std::string(argv[3 + i]) : def;
    };
    auto num = [&](int i, int def) {
        try { return std::stoi(arg(i, std::to_string(def))); } catch (...) { return def; }
    };
    auto flag = [&](int i) { const std::string v = arg(i, "false"); return v == "true" || v == "1"; };

    if (m == "Lock")               SystemControl::lock_session_async();
    else if (m == "Reload")        { util::spawn_detached({"swaymsg", "reload"}); util::spawn_detached({"b1air-shell", "forceReload"}); }
    else if (m == "VolumeUp")      SystemControl::volume_up(num(0, 5));
    else if (m == "VolumeDown")    SystemControl::volume_down(num(0, 5));
    else if (m == "ToggleMute")    SystemControl::volume_toggle_mute();
    else if (m == "BrightnessUp")  SystemControl::brightness_up(num(0, 5));
    else if (m == "BrightnessDown") SystemControl::brightness_down(num(0, 5));
    else if (m == "BrightnessSet") SystemControl::brightness_set(num(0, 50));
    else if (m == "SetGameMode")   { if (flag(0)) SystemControl::enable_game_mode(); else SystemControl::disable_game_mode(); }
    else if (m == "Capture")       SystemControl::capture(arg(0, "full"), "", false);
    else if (m == "CaptureGeom")   SystemControl::capture(arg(0, "full"), arg(1), flag(2));
    else if (m == "Power") {
        const std::string act = arg(0, "lock");
        if (act == "lock") SystemControl::lock_session_async();
        else if (act == "logout") SystemControl::logout_session();
        else if (act == "suspend") SystemControl::suspend_system();
        else if (act == "reboot") SystemControl::reboot_system();
        else if (act == "shutdown") SystemControl::shutdown_system();
    }
    else if (m == "RemoteStatus")  std::cout << SystemControl::remote_desktop_status_json() << "\n";
    else if (m == "RemoteStop")    SystemControl::remote_desktop_stop();
    else if (m == "RemotePromptFree") SystemControl::set_screencast_prompt_free(flag(0));
    else if (m == "SidecarCreate") SystemControl::sidecar_create_virtual_display(num(0, 1920), num(1, 1080));
    else if (m == "SidecarRemove") SystemControl::sidecar_remove_virtual_display();
    else if (m == "DotfilesStatus") std::cout << SystemControl::dotfiles_status_json() << "\n";
    else if (m == "DotfilesSys")   SystemControl::dotfiles_sys();
    else if (m == "DotfilesSync")  SystemControl::dotfiles_sync();
    else if (m == "SweeperClean")  SystemControl::disk_sweeper_clean();
    else if (m == "ZonesApply")    SystemControl::zones_apply(num(0, 0));
    else if (m == "MicRnnoiseToggle") SystemControl::mic_rnnoise_toggle();
    else if (m == "PowerProfileSet") SystemControl::power_profile_set(arg(0, "balanced"));
    else if (m == "MonitorsApply") SystemControl::monitors_apply(arg(0));
    else if (m == "DdcSet")        SystemControl::ddc_set(arg(0), num(1, 50));
    else if (m == "EqApply")       SystemControl::eq_apply();
    else if (m == "EqSetBand")     SystemControl::eq_set_band(num(0, 0), num(1, 0));
    else if (m == "EqSetPreset")   SystemControl::eq_set_preset(arg(0, "Flat"));
    else if (m == "EqSetAll") {
        std::vector<int> bands;
        for (int i = 3; i < argc; ++i) { try { bands.push_back(std::stoi(argv[i])); } catch (...) {} }
        SystemControl::eq_set_all(bands);
    }
    else if (m == "ScanQr")        std::cout << SystemControl::scan_qr(arg(0)) << "\n";
    else if (m == "GetVersion")    std::cout << b1air::kVersion << "\n";
    else if (m == "GetStats") {
        FocusTimeDB db;
        std::cout << (db.open() ? db.get_stats_json(arg(0)) : std::string("{}")) << "\n";
    }
    else {
        std::cerr << "dbus-call: unknown method " << m << "\n";
        return 2;
    }
    return 0;
}

// ── Main Entry Point ─────────────────────────────────────────────────────────
int main(int argc, char* argv[]) {
    if (argc < 2) {
        print_usage(argv[0]);
        return 1;
    }

    std::string cmd = argv[1];

    if (cmd == "dbus" || cmd == "service" || cmd == "dbus-service") {
        return DaemonDBus::run_service();
    } else if (cmd == "session" || cmd == "start-session") {
        return SessionManager::run_session();
    } else if (cmd == "settings") {
        std::string sub = (argc >= 3) ? argv[2] : "apply";
        if (sub == "watch") {
            int running = 1;
            return SettingsManager::watch_and_apply(&running);
        } else {
            return SettingsManager::apply_from_file() ? 0 : 1;
        }
    } else if (cmd == "config") {
        const std::string sub = (argc >= 3) ? argv[2] : "";
        const std::string arg = (argc >= 4) ? argv[3] : "";
        if (sub == "export") {
            const std::string out = arg.empty()
                ? std::string(std::getenv("HOME") ? std::getenv("HOME") : "/tmp")
                      + "/b1air-config.json"
                : arg;
            return SettingsManager::config_export(out) ? 0 : 1;
        }
        if (sub == "import" && !arg.empty())
            return SettingsManager::config_import(arg) ? 0 : 1;
        std::cerr << "Usage: " << argv[0] << " config {export [file]|import <file>}\n";
        return 1;
    } else if (cmd == "camera") {
        // Prints and exits 0 when in use, 1 when not, so a script can branch
        // on either the word or the status.
        const bool used = SystemControl::camera_in_use();
        std::cout << (used ? "in-use" : "idle") << "\n";
        return used ? 0 : 1;
    } else if (cmd == "focus" || cmd == "focus-tracker") {
        // `focus away` / `focus back` are swayidle's, not a person's: they mark
        // the start and end of an idle stretch so the break reminder can tell
        // ten hours at the screen from ten hours asleep. A mark is a file whose
        // mtime is the whole message, which is why this touches rather than
        // writes — the tracker runs in another process and only ever stats it.
        const std::string mark = (argc >= 3) ? argv[2] : "";
        if (mark == "away" || mark == "back") {
            const std::string path = b1air::runtime_path(
                mark == "away" ? "focus-away" : "focus-back");
            const int fd = ::open(path.c_str(), O_WRONLY | O_CREAT, 0600);
            if (fd < 0) return 1;
            ::futimens(fd, nullptr);
            ::close(fd);
            return 0;
        }
        return run_focus_tracker();
    } else if (cmd == "gamepad-inhibit" || cmd == "joystick-inhibit") {
        return SystemControl::run_gamepad_inhibit();
    } else if (cmd == "stats") {
        std::string date_arg = (argc >= 3) ? argv[2] : "";
        if (DaemonDBus::is_running()) {
            std::cout << DaemonDBus::call_get_stats(date_arg) << "\n";
            return 0;
        }
        FocusTimeDB db;
        if (!db.open()) {
            std::cerr << "{\"error\":\"failed to open database\"}\n";
            return 1;
        }
        std::cout << db.get_stats_json(date_arg) << "\n";
        return 0;
    } else if (cmd == "focustime") {
        // What the FocusTime window reads. `stats` above answers a different,
        // older shape — different key names and none of the weekly, monthly or
        // hourly series — so the window drew every chart empty. Kept as a
        // separate command rather than changing `stats`, which other things
        // and any existing script still call.
        std::string date_arg;
        std::string app_arg;
        for (int i = 2; i < argc; ++i) {
            const std::string a = argv[i];
            if (a == "--app" && i + 1 < argc) {
                app_arg = argv[++i];
            } else if (date_arg.empty()) {
                date_arg = a;
            }
        }
        FocusTimeDB db;
        if (!db.open()) {
            std::cerr << "{\"error\":\"failed to open database\"}\n";
            return 1;
        }
        std::cout << db.get_dashboard_json(date_arg, app_arg);
        return 0;
    } else if (cmd == "user") {
        if (argc < 3) {
            std::cerr << "Usage: " << argv[0] << " user {get|set-avatar <path>|set-name <name>|set-shell <path>|change-password}\n";
            return 1;
        }
        std::string sub = argv[2];
        if (sub == "get") {
            std::cout << UserManager::get_user_info_json() << "\n";
            return 0;
        } else if (sub == "set-avatar") {
            if (argc < 4) {
                std::cerr << "Error: Missing image path\n";
                return 1;
            }
            return UserManager::set_avatar(argv[3]) ? 0 : 1;
        } else if (sub == "set-name") {
            if (argc < 4) {
                std::cerr << "Error: Missing name string\n";
                return 1;
            }
            return UserManager::set_name(argv[3]) ? 0 : 1;
        } else if (sub == "set-shell") {
            if (argc < 4) {
                std::cerr << "Error: Missing shell path\n";
                return 1;
            }
            return UserManager::set_shell(argv[3]) ? 0 : 1;
        } else if (sub == "change-password") {
            return UserManager::change_password() ? 0 : 1;
        } else {
            std::cerr << "Unknown user command: " << sub << "\n";
            return 1;
        }
    } else if (cmd == "layout" || cmd == "lang") {
        std::cout << SystemControl::get_layout_shorthand() << "\n";
        return 0;
    } else if (cmd == "fullscreen-toggle" || cmd == "fullscreen") {
        return SystemControl::toggle_fullscreen() ? 0 : 1;
    } else if (cmd == "window" || cmd == "win") {
        std::string sub = (argc >= 3) ? argv[2] : "toggle";
        if (sub == "minimize" || sub == "min") {
            return SystemControl::window_minimize() ? 0 : 1;
        } else if (sub == "restore" || sub == "unminimize") {
            int64_t id = (argc >= 4) ? std::stoll(argv[3]) : -1;
            return SystemControl::window_restore(id) ? 0 : 1;
        } else if (sub == "toggle") {
            return SystemControl::window_toggle_minimize() ? 0 : 1;
        } else if (sub == "list" || sub == "minimized") {
            std::cout << SystemControl::window_list_minimized_json() << "\n";
            return 0;
        } else if (sub == "count" || sub == "minimized-count") {
            int cnt = SystemControl::window_count_minimized();
            if (cnt > 0) std::cout << "󰖰 " << cnt << "\n";
            else std::cout << "\n";
            return 0;
        } else if (sub == "open" || sub == "all") {
            std::cout << SystemControl::window_list_open_json() << "\n";
            return 0;
        } else if (sub == "maximize") {
            return SystemControl::window_maximize_toggle() ? 0 : 1;
        } else if (sub == "float-all") {
            return SystemControl::window_float_all_toggle() ? 0 : 1;
        } else if (sub == "opacity-toggle") {
            return SystemControl::window_opacity_toggle() ? 0 : 1;
        } else {
            std::cerr << "Usage: " << argv[0] << " window {minimize|restore [id]|toggle|list|open|count|maximize|float-all|opacity-toggle}\n";
            return 1;
        }
    } else if (cmd == "color-picker" || cmd == "color" || cmd == "picker") {
        std::string col = SystemControl::pick_color();
        if (!col.empty()) {
            std::cout << col << "\n";
            return 0;
        }
        return 1;
    } else if (cmd == "wifi-status") {
        std::cout << SystemControl::get_wifi_status_json() << "\n";
        return 0;
    } else if (cmd == "wifi") {
        std::string sub = (argc >= 3) ? argv[2] : "status";
        if (sub == "list" || sub == "scan") {
            std::cout << SystemControl::wifi_list_json() << "\n";
            return 0;
        } else if (sub == "connect") {
            if (argc < 4) {
                std::cerr << "Usage: " << argv[0] << " wifi connect <ssid> [password]\n";
                return 1;
            }
            std::string ssid = argv[3];
            std::string pwd = (argc >= 5) ? argv[4] : "";
            std::cout << SystemControl::wifi_connect(ssid, pwd) << "\n";
            return 0;
        } else {
            std::cout << SystemControl::get_wifi_status_json() << "\n";
            return 0;
        }
    } else if (cmd == "bt" || cmd == "bluetooth") {
        std::string sub = (argc >= 3) ? argv[2] : "list";
        if (sub == "list" || sub == "scan" || sub == "devices") {
            std::cout << SystemControl::bt_list_json() << "\n";
            return 0;
        } else if (sub == "connect") {
            if (argc < 4) {
                std::cerr << "Usage: " << argv[0] << " bt connect <mac>\n";
                return 1;
            }
            return SystemControl::bt_connect(argv[3]) ? 0 : 1;
        } else if (sub == "disconnect") {
            if (argc < 4) {
                std::cerr << "Usage: " << argv[0] << " bt disconnect <mac>\n";
                return 1;
            }
            return SystemControl::bt_disconnect(argv[3]) ? 0 : 1;
        } else if (sub == "pair") {
            if (argc < 4) {
                std::cerr << "Usage: " << argv[0] << " bt pair <mac>\n";
                return 1;
            }
            return SystemControl::bt_pair(argv[3]) ? 0 : 1;
        } else {
            std::cerr << "Usage: " << argv[0] << " bt {list|connect <mac>|disconnect <mac>|pair <mac>}\n";
            return 1;
        }
    } else if (cmd == "media-status" || cmd == "media") {
        std::cout << SystemControl::get_media_status_json() << "\n";
        return 0;
    } else if (cmd == "media-info" || cmd == "media-art") {
        std::cout << SystemControl::media_get_info_json() << "\n";
        return 0;
    } else if (cmd == "remote") {
        std::string sub = (argc > 2) ? argv[2] : "status";
        if (sub == "start" || sub == "start-stdin") {
            int port = (argc > 3) ? std::atoi(argv[3]) : 5900;
            // Passwords must never be accepted from argv: they are visible in
            // /proc and process listings. The UI uses start-stdin instead.
            if (argc > 4) return 1;
            std::string pass;
            if (sub == "start-stdin") {
                std::getline(std::cin, pass);
                while (!pass.empty() && (pass.back() == '\r' || pass.back() == '\n')) pass.pop_back();
            }
            return SystemControl::remote_desktop_start(port, pass) ? 0 : 1;
        } else if (sub == "stop") {
            return SystemControl::remote_desktop_stop() ? 0 : 1;
        } else if (sub == "toggle") {
            return SystemControl::remote_desktop_toggle() ? 0 : 1;
        } else if (sub == "prompt-free") {
            if (argc < 4 || (std::string(argv[3]) != "on" && std::string(argv[3]) != "off")) return 1;
            bool en = std::string(argv[3]) == "on";
            return SystemControl::set_screencast_prompt_free(en) ? 0 : 1;
        } else {
            std::cout << SystemControl::remote_desktop_status_json() << "\n";
            return 0;
        }
    } else if (cmd == "sidecar") {
        std::string sub = (argc > 2) ? argv[2] : "create";
        if (sub == "remove" || sub == "destroy") {
            return SystemControl::sidecar_remove_virtual_display() ? 0 : 1;
        } else {
            int w = (argc > 3) ? std::atoi(argv[3]) : 1920;
            int h = (argc > 4) ? std::atoi(argv[4]) : 1080;
            return SystemControl::sidecar_create_virtual_display(w, h) ? 0 : 1;
        }
    } else if (cmd == "diary") {
        return SystemControl::diary_open() ? 0 : 1;
    } else if (cmd == "schedule") {
        std::cout << SystemControl::schedule_get_json() << "\n";
        return 0;
    } else if (cmd == "dotfiles") {
        std::string sub = (argc >= 3) ? argv[2] : "status";
        if (sub == "status") {
            std::cout << SystemControl::dotfiles_status_json() << "\n";
            return 0;
        } else if (sub == "sync" || sub == "update" || sub == "run") {
            return SystemControl::dotfiles_sync() ? 0 : 1;
        } else if (sub == "sys" || sub == "system") {
            return SystemControl::dotfiles_sys() ? 0 : 1;
        } else {
            std::cerr << "Usage: " << argv[0] << " dotfiles {status|sync|sys}\n";
            return 1;
        }
    } else if (cmd == "updates") {
        std::string sub = (argc >= 3) ? argv[2] : "check";
        if (sub == "up" || sub == "upgrade") {
            return SystemControl::launch_system_upgrade() ? 0 : 1;
        } else {
            std::cout << SystemControl::get_updates_json() << "\n";
            return 0;
        }
    } else if (cmd == "volume") {
        std::string sub = (argc >= 3) ? argv[2] : "get";
        // "Volume key step size" in Sound settings. The key bindings passed a
        // literal 5 and the setting was read by nothing, so the stepper moved
        // a number in settings.json and the keys kept moving the volume by 5.
        // The bindings now leave the step out and it comes from the file; an
        // explicit argument still wins, for anyone scripting it.
        int step = (argc >= 4)
            ? std::atoi(argv[3])
            : SettingsManager::get_json_int("audioStep", 5);
        if (step < 1) step = 1;
        if (step > 25) step = 25;
        if (sub == "get") {
            std::cout << SystemControl::get_volume() << "\n";
            return 0;
        } else if (sub == "up" || sub == "inc") {
            if (DaemonDBus::is_running()) return DaemonDBus::call_volume_up(step) ? 0 : 1;
            return SystemControl::volume_up(step) ? 0 : 1;
        } else if (sub == "down" || sub == "dec") {
            if (DaemonDBus::is_running()) return DaemonDBus::call_volume_down(step) ? 0 : 1;
            return SystemControl::volume_down(step) ? 0 : 1;
        } else if (sub == "mute" || sub == "toggle") {
            if (DaemonDBus::is_running()) return DaemonDBus::call_volume_mute() ? 0 : 1;
            return SystemControl::volume_toggle_mute() ? 0 : 1;
        } else {
            std::cerr << "Usage: " << argv[0] << " volume {get|up [N]|down [N]|mute}\n";
            return 1;
        }
    } else if (cmd == "mic") {
        std::string sub = (argc >= 3) ? argv[2] : "toggle";
        // "status" is the name; "waybar" is what it was called when a bar of
        // that name read it, and is kept so an existing script does not break.
        if (sub == "get" || sub == "status" || sub == "waybar") {
            std::string status = SystemControl::get_mic_status();
            std::cout << (status == "muted" ? "" : "") << "\n";
            return 0;
        } else if (sub == "toggle" || sub == "mute") {
            return SystemControl::mic_toggle() ? 0 : 1;
        } else {
            std::cerr << "Usage: " << argv[0] << " mic {get|toggle}\n";
            return 1;
        }
    } else if (cmd == "eq" || cmd == "equalizer") {
        std::string sub = (argc >= 3) ? argv[2] : "get";
        if (sub == "get") {
            std::cout << SystemControl::eq_get_state_json() << "\n";
            return 0;
        } else if (sub == "apply") {
            return SystemControl::eq_apply() ? 0 : 1;
        } else if (sub == "preset") {
            if (argc < 4) {
                std::cerr << "Usage: " << argv[0] << " eq preset <Flat|Bass|Treble|Vocal|Pop|Rock|Jazz|Classic>\n";
                return 1;
            }
            return SystemControl::eq_set_preset(argv[3]) ? 0 : 1;
        } else if (sub == "set_band") {
            if (argc < 5) {
                std::cerr << "Usage: " << argv[0] << " eq set_band <1..10> <gain>\n";
                return 1;
            }
            int band = std::atoi(argv[3]);
            int val = std::atoi(argv[4]);
            return SystemControl::eq_set_band(band, val) ? 0 : 1;
        } else if (sub == "set") {
            if (argc < 13) {
                std::cerr << "Usage: " << argv[0] << " eq set <b1> <b2> ... <b10>\n";
                return 1;
            }
            std::vector<int> b(10);
            for (int i = 0; i < 10; ++i) b[i] = std::atoi(argv[3 + i]);
            return SystemControl::eq_set_all(b) ? 0 : 1;
        } else {
            std::cerr << "Usage: " << argv[0] << " eq {get|apply|preset <name>|set_band <idx> <val>|set <b1..b10>}\n";
            return 1;
        }
    } else if (cmd == "brightness" || cmd == "backlight") {
        std::string sub = (argc >= 3) ? argv[2] : "get";
        int step = (argc >= 4) ? std::atoi(argv[3]) : 5;
        if (sub == "available") {
            return SystemControl::brightness_available() ? 0 : 1;
        } else if (sub == "get") {
            std::cout << SystemControl::brightness_get() << "\n";
            return 0;
        } else if (sub == "up" || sub == "inc") {
            if (DaemonDBus::is_running()) return DaemonDBus::call_brightness_up(step) ? 0 : 1;
            return SystemControl::brightness_up(step) ? 0 : 1;
        } else if (sub == "down" || sub == "dec") {
            if (DaemonDBus::is_running()) return DaemonDBus::call_brightness_down(step) ? 0 : 1;
            return SystemControl::brightness_down(step) ? 0 : 1;
        } else if (sub == "set") {
            if (DaemonDBus::is_running()) return DaemonDBus::call_brightness_set(step) ? 0 : 1;
            return SystemControl::brightness_set(step) ? 0 : 1;
        } else {
            std::cerr << "Usage: " << argv[0] << " brightness {available|get|up [N]|down [N]|set <pct>}\n";
            return 1;
        }
    } else if (cmd == "monitors") {
        std::string sub = (argc >= 3) ? argv[2] : "restore";
        if (sub == "restore") {
            return SystemControl::monitors_restore() ? 0 : 1;
        } else if (sub == "apply") {
            if (argc < 4) {
                std::cerr << "Usage: " << argv[0] << " monitors apply <layout-json>\n";
                return 1;
            }
            return SystemControl::monitors_apply(argv[3]) ? 0 : 1;
        } else if (sub == "save") {
            if (argc < 4) {
                std::cerr << "Usage: " << argv[0] << " monitors save <layout-json>\n";
                return 1;
            }
            return SystemControl::monitors_save(argv[3]) ? 0 : 1;
        } else if (sub == "profiles") {
            std::cout << SystemControl::monitors_profiles_json() << "\n";
            return 0;
        } else if (sub == "forget") {
            if (argc < 4) {
                std::cerr << "Usage: " << argv[0] << " monitors forget <profile-key>\n";
                return 1;
            }
            return SystemControl::monitors_forget(argv[3]) ? 0 : 1;
        } else {
            std::cerr << "Usage: " << argv[0] << " monitors {restore|apply <json>|save <json>|profiles|forget <key>}\n";
            return 1;
        }
    } else if (cmd == "ddc") {
        std::string sub = (argc >= 3) ? argv[2] : "status";
        if (sub == "list" || sub == "list-ddc" || sub == "has" || sub == "has-ddc") {
            std::cout << SystemControl::ddc_list_json(false) << "\n";
            return 0;
        } else if (sub == "refresh" || sub == "refresh-ddc") {
            std::cout << SystemControl::ddc_list_json(true) << "\n";
            return 0;
        } else if (sub == "status" || sub == "waybar") {
            std::cout << SystemControl::ddc_status_json() << "\n";
            return 0;
        } else if (sub == "set") {
            if (argc < 5) {
                std::cerr << "Usage: " << argv[0] << " ddc set <id> <percent>\n";
                return 1;
            }
            std::string id = argv[3];
            int pct = std::atoi(argv[4]);
            return SystemControl::ddc_set(id, pct) ? 0 : 1;
        } else if (sub == "up" || sub == "inc") {
            int step = (argc >= 4) ? std::atoi(argv[3]) : 5;
            return SystemControl::ddc_adjust_all(step) ? 0 : 1;
        } else if (sub == "down" || sub == "dec") {
            int step = (argc >= 4) ? std::atoi(argv[3]) : 5;
            return SystemControl::ddc_adjust_all(-step) ? 0 : 1;
        } else if (sub == "dim") {
            return SystemControl::ddc_dim() ? 0 : 1;
        } else if (sub == "undim") {
            return SystemControl::ddc_undim() ? 0 : 1;
        } else {
            std::cerr << "Usage: " << argv[0] << " ddc {list|set <id> <val>|up [N]|down [N]|status|refresh|dim|undim}\n";
            return 1;
        }
    } else if (cmd == "weather") {
        std::string sub = (argc >= 3) ? argv[2] : "json";
        if (sub == "json" || sub == "--json") {
            std::cout << SystemControl::weather_get_json(false) << "\n";
            return 0;
        } else if (sub == "refresh" || sub == "--getdata") {
            std::cout << SystemControl::weather_get_json(true) << "\n";
            return 0;
        } else {
            std::cout << SystemControl::weather_get_current_info(sub) << "\n";
            return 0;
        }
    } else if (cmd == "kbd-backlight" || cmd == "kbd") {
        std::string sub = (argc >= 3) ? argv[2] : "get";
        int step = (argc >= 4) ? std::atoi(argv[3]) : 10;
        if (sub == "available" || sub == "--available") {
            return SystemControl::kbd_backlight_available() ? 0 : 1;
        } else if (sub == "get" || sub == "--get") {
            std::cout << SystemControl::kbd_backlight_get() << "\n";
            return 0;
        } else if (sub == "up" || sub == "inc" || sub == "--inc") {
            return SystemControl::kbd_backlight_inc(step) ? 0 : 1;
        } else if (sub == "down" || sub == "dec" || sub == "--dec") {
            return SystemControl::kbd_backlight_dec(step) ? 0 : 1;
        } else if (sub == "set" || sub == "--set") {
            int val = (argc >= 4) ? std::atoi(argv[3]) : 50;
            return SystemControl::kbd_backlight_set(val) ? 0 : 1;
        } else if (sub == "off" || sub == "--off") {
            return SystemControl::kbd_backlight_off() ? 0 : 1;
        } else {
            std::cerr << "Usage: " << argv[0] << " kbd-backlight {available|get|up [N]|down [N]|set <val>|off}\n";
            return 1;
        }
    } else if (cmd == "wallpaper") {
        std::string sub = (argc >= 3) ? argv[2] : "restore";
        if (sub == "set") {
            if (argc < 4) {
                std::cerr << "Usage: " << argv[0] << " wallpaper set <path>\n";
                return 1;
            }
            // An optional output name: that screen only.
            if (argc >= 5) return SystemControl::wallpaper_set_output(argv[3], argv[4]) ? 0 : 1;
            return SystemControl::wallpaper_set(argv[3]) ? 0 : 1;
        } else if (sub == "random") {
            std::string dir = (argc >= 4) ? argv[3] : "";
            return SystemControl::wallpaper_random(dir) ? 0 : 1;
        } else if (sub == "restore") {
            return SystemControl::wallpaper_restore() ? 0 : 1;
        } else if (sub == "screens") {
            std::cout << SystemControl::wallpaper_overrides_json() << "\n";
            return 0;
        } else {
            std::cerr << "Usage: " << argv[0] << " wallpaper {set <file> [output]|random [dir]|restore|screens}\n";
            return 1;
        }
    } else if (cmd == "night-light" || cmd == "nightlight") {
        std::string sub = (argc >= 3) ? argv[2] : "toggle";
        // --quiet: the Settings page and the Control Center show the state
        // themselves, and the slider restarts wlsunset on every step.
        const bool quiet = argc >= 5 ? std::string(argv[4]) == "--quiet"
                         : (argc >= 4 && std::string(argv[3]) == "--quiet");
        if (sub == "on") {
            int temp = (argc >= 4 && std::string(argv[3]) != "--quiet") ? std::atoi(argv[3]) : 4000;
            return SystemControl::night_light_on(temp, !quiet) ? 0 : 1;
        } else if (sub == "off") {
            return SystemControl::night_light_off(!quiet) ? 0 : 1;
        } else if (sub == "toggle") {
            return SystemControl::night_light_toggle() ? 0 : 1;
        } else if (sub == "auto") {
            return SystemControl::night_light_auto() ? 0 : 1;
        } else {
            std::cerr << "Usage: " << argv[0] << " night-light {on [temp] [--quiet]|off [--quiet]|toggle|auto}\n";
            return 1;
        }
    } else if (cmd == "term-theme") {
        std::string sub = (argc >= 3) ? argv[2] : "list";
        if (sub == "list") {
            auto themes = SystemControl::term_theme_list();
            for (const auto& t : themes) std::cout << t << "\n";
            return 0;
        } else if (sub == "set") {
            if (argc < 4) {
                std::cerr << "Usage: " << argv[0] << " term-theme set <theme-name>\n";
                return 1;
            }
            return SystemControl::term_theme_set(argv[3]) ? 0 : 1;
        } else {
            return SystemControl::term_theme_set(sub) ? 0 : 1;
        }
    } else if (cmd == "reload") {
        if (DaemonDBus::is_running()) return DaemonDBus::call_reload() ? 0 : 1;
        return SystemControl::reload_desktop() ? 0 : 1;
    } else if (cmd == "monitor-json" || cmd == "sysinfo-json") {
        std::cout << SystemControl::get_system_stats_json() << "\n";
        return 0;
    } else if (cmd == "kill-process") {
        if (argc < 3) {
            std::cerr << "Usage: " << argv[0] << " kill-process <pid> [--force]\n";
            return 1;
        }
        int pid = std::atoi(argv[2]);
        bool force = (argc >= 4 && std::string(argv[3]) == "--force");
        return SystemControl::kill_process(pid, force) ? 0 : 1;
    } else if (cmd == "game-mode" || cmd == "gamemode") {
        std::string sub = (argc >= 3) ? argv[2] : "toggle";
        if (sub == "on" || sub == "enable") {
            if (DaemonDBus::is_running()) return DaemonDBus::call_game_mode(true) ? 0 : 1;
            return SystemControl::enable_game_mode() ? 0 : 1;
        } else if (sub == "off" || sub == "disable") {
            if (DaemonDBus::is_running()) return DaemonDBus::call_game_mode(false) ? 0 : 1;
            return SystemControl::disable_game_mode() ? 0 : 1;
        } else if (sub == "toggle") {
            return SystemControl::toggle_game_mode() ? 0 : 1;
        } else if (sub == "status") {
            std::cout << SystemControl::get_game_mode_status_json() << "\n";
            return 0;
        } else {
            std::cerr << "Usage: " << argv[0] << " game-mode {on|off|toggle|status}\n";
            return 1;
        }
    } else if (cmd == "power") {
        if (argc < 3) {
            std::cerr << "Usage: " << argv[0] << " power {lock|logout|suspend|reboot|shutdown|idle-reload}\n";
            return 1;
        }
        std::string sub = argv[2];
        // Before the D-Bus hand-off: restarting swayidle is a local operation
        // on this session's own processes, and the running daemon has no
        // Power method for it — sending it over the bus would just fail.
        // Settings calls this after changing an idle timeout so the new
        // timings apply to the session the user is looking at, not the next.
        if (sub == "idle-reload") return SessionManager::restart_swayidle() ? 0 : 1;
        if (DaemonDBus::is_running()) return DaemonDBus::call_power(sub) ? 0 : 1;
        if (sub == "lock") return SystemControl::lock_session_async() ? 0 : 1;
        if (sub == "logout") return SystemControl::logout_session() ? 0 : 1;
        if (sub == "suspend") return SystemControl::suspend_system() ? 0 : 1;
        if (sub == "reboot") return SystemControl::reboot_system() ? 0 : 1;
        if (sub == "shutdown" || sub == "poweroff") return SystemControl::shutdown_system() ? 0 : 1;
        std::cerr << "Unknown power command: " << sub << "\n";
        return 1;
    } else if (cmd == "power-profile" || cmd == "profile") {
        std::string sub = (argc >= 3) ? argv[2] : "get";
        if (sub == "get") {
            std::cout << SystemControl::power_profile_get() << "\n";
            return 0;
        } else if (sub == "set") {
            if (argc < 4) {
                std::cerr << "Usage: " << argv[0] << " power-profile set <performance|balanced|power-saver>\n";
                return 1;
            }
            return SystemControl::power_profile_set(argv[3]) ? 0 : 1;
        } else {
            return SystemControl::power_profile_set(sub) ? 0 : 1;
        }
    } else if (cmd == "battery") {
        std::string sub = (argc >= 3) ? argv[2] : "status";
        if (sub == "status" || sub == "get") {
            std::cout << SystemControl::battery_status_json() << "\n";
            return 0;
        } else if (sub == "limit") {
            if (argc < 4) {
                std::cerr << "Usage: " << argv[0] << " battery limit <20-100>\n";
                return 1;
            }
            return SystemControl::battery_limit_set(std::atoi(argv[3])) ? 0 : 1;
        } else if (sub == "behaviour" || sub == "behavior") {
            if (argc < 4) {
                std::cerr << "Usage: " << argv[0]
                          << " battery behaviour <auto|inhibit-charge|force-discharge>\n";
                return 1;
            }
            return SystemControl::battery_behaviour_set(argv[3]) ? 0 : 1;
        }
        std::cerr << "Unknown battery command: " << sub << "\n";
        return 1;
    } else if (cmd == "caffeine" || cmd == "idle-inhibit") {
        std::string sub = (argc >= 3) ? argv[2] : "toggle";
        if (sub == "status" || sub == "get") {
            std::cout << (SystemControl::caffeine_is_active() ? "active" : "inactive") << "\n";
            return 0;
        } else if (sub == "on" || sub == "enable") {
            return SystemControl::caffeine_set(true) ? 0 : 1;
        } else if (sub == "off" || sub == "disable") {
            return SystemControl::caffeine_set(false) ? 0 : 1;
        } else {
            return SystemControl::caffeine_toggle() ? 0 : 1;
        }
    } else if (cmd == "appearance") {
        return SystemControl::appearance_apply() ? 0 : 1;
    } else if (cmd == "dbus-call") {
        return run_dbus_call(argc, argv);
    } else if (cmd == "open-default") {
        const std::string kind = (argc >= 3) ? argv[2] : "";
        if (kind != "terminal" && kind != "files" && kind != "browser") {
            std::cerr << "Usage: " << argv[0] << " open-default {terminal|files|browser}\n";
            return 1;
        }
        return SystemControl::open_default(kind) ? 0 : 1;
    } else if (cmd == "apps" || cmd == "applications") {
        std::string cat = (argc >= 3) ? argv[2] : "all";
        std::cout << SystemControl::apps_list_json(cat) << "\n";
        return 0;
    } else if (cmd == "screenshot" || cmd == "capture") {
        std::string mode = "full";
        std::string geom = "";
        bool edit = false;
        int delay = -1;

        for (int i = 2; i < argc; ++i) {
            std::string arg = argv[i];
            if (arg == "--edit" || arg == "-e" || arg == "edit") edit = true;
            else if (arg == "--delay" || arg == "-d") {
                if (i + 1 < argc) { try { delay = std::stoi(argv[++i]); } catch (...) {} }
            }
            else if (arg == "--geometry" || arg == "-g") {
                if (i + 1 < argc) geom = argv[++i];
            } else if (arg == "--full" || arg == "full") mode = "full";
            else if (arg == "--area" || arg == "area") mode = "area";
            else if (arg == "--window" || arg == "window") mode = "window";
            else if (arg == "--select" || arg == "select") mode = "select";
            else if (!arg.empty() && arg.front() != '-') mode = arg;
            else {
                // Refused rather than ignored: an unknown option such as
                // --help used to fall through to a full-screen capture, saved
                // and copied to the clipboard.
                std::cerr << "Usage: " << argv[0] << " screenshot [full|area|window|select] "
                             "[--geometry <geom>] [--edit] [--delay <s>]\n";
                return 2;
            }
        }
        // "select" opens ScreenshotOverlay.qml — drag-to-select, annotate,
        // QR-scan and GIF recording — instead of an immediate blind capture.
        if (mode == "select") return SystemControl::run_screenshot_overlay(edit) ? 0 : 1;
        return SystemControl::capture(mode, geom, edit, delay) ? 0 : 1;
    } else if (cmd == "record") {
        std::string sub = (argc >= 3) ? argv[2] : "toggle";
        if (sub == "stop") return SystemControl::record_stop() ? 0 : 1;

        std::string geom = "";
        double desk_vol = 1.0;
        double mic_vol = 1.0;
        bool desk_mute = false;
        bool mic_mute = false;
        std::string mic_dev = "";

        for (int i = 2; i < argc; ++i) {
            std::string arg = argv[i];
            if (arg == "--geometry" || arg == "-g") {
                if (i + 1 < argc) geom = argv[++i];
            } else if (arg == "--desk-vol") {
                if (i + 1 < argc) desk_vol = std::atof(argv[++i]);
            } else if (arg == "--mic-vol") {
                if (i + 1 < argc) mic_vol = std::atof(argv[++i]);
            } else if (arg == "--desk-mute") {
                if (i + 1 < argc) desk_mute = (std::string(argv[++i]) == "true");
            } else if (arg == "--mic-mute") {
                if (i + 1 < argc) mic_mute = (std::string(argv[++i]) == "true");
            } else if (arg == "--mic-dev") {
                if (i + 1 < argc) mic_dev = argv[++i];
            }
        }
        return SystemControl::record_toggle(geom, desk_vol, mic_vol, desk_mute, mic_mute, mic_dev) ? 0 : 1;
    } else if (cmd == "scan-qr" || cmd == "qr-scan") {
        std::string geom = (argc >= 3) ? argv[2] : "";
        std::cout << SystemControl::scan_qr(geom) << "\n";
        return 0;
    } else if (cmd == "qr-gen" || cmd == "qr-generate") {
        if (argc < 3) {
            std::cerr << "Usage: " << argv[0] << " qr-gen <text> [out_path]\n";
            return 1;
        }
        std::string text = argv[2];
        std::string out = (argc >= 4) ? argv[3] : "";
        return SystemControl::qr_generate(text, out) ? 0 : 1;
    } else if (cmd == "ocr") {
        std::string geom = (argc >= 3) ? argv[2] : "";
        return SystemControl::ocr_screen(geom) ? 0 : 1;
    } else if (cmd == "pip") {
        std::string sub = (argc >= 3) ? argv[2] : "toggle";
        if (sub == "status") {
            std::cout << SystemControl::pip_status() << "\n";
            return 0;
        }
        return SystemControl::pip_toggle() ? 0 : 1;
    } else if (cmd == "force-quit" || cmd == "xkill") {
        return SystemControl::force_quit() ? 0 : 1;
    } else if (cmd == "cursor-locate" || cmd == "shake-find") {
        return SystemControl::cursor_locate() ? 0 : 1;
    } else if (cmd == "quicklook" || cmd == "preview") {
        if (argc < 3) {
            std::cerr << "Usage: " << argv[0] << " quicklook <file_path>\n";
            return 1;
        }
        return SystemControl::quicklook_open(argv[2]) ? 0 : 1;
    } else if (cmd == "zones") {
        int id = (argc >= 3) ? std::atoi(argv[2]) : 1;
        return SystemControl::zones_apply(id) ? 0 : 1;
    } else if (cmd == "audio-switch") {
        return SystemControl::audio_switch_output() ? 0 : 1;
    } else if (cmd == "mic-rnnoise" || cmd == "rnnoise") {
        std::string sub = (argc >= 3) ? argv[2] : "toggle";
        if (sub == "status") {
            std::cout << (SystemControl::mic_rnnoise_is_active() ? "active" : "inactive") << "\n";
            return 0;
        } else if (sub == "on" || sub == "enable") {
            return SystemControl::mic_rnnoise_set(true) ? 0 : 1;
        } else if (sub == "off" || sub == "disable") {
            return SystemControl::mic_rnnoise_set(false) ? 0 : 1;
        } else {
            return SystemControl::mic_rnnoise_toggle() ? 0 : 1;
        }
    } else if (cmd == "record-gif") {
        std::string geom = (argc >= 3) ? argv[2] : "";
        return SystemControl::record_gif(geom) ? 0 : 1;
    } else if (cmd == "voice-memo" || cmd == "dictation") {
        return SystemControl::voice_memo() ? 0 : 1;
    } else if (cmd == "sweeper" || cmd == "disk-sweeper") {
        std::string sub = (argc >= 3) ? argv[2] : "scan";
        if (sub == "clean") {
            return SystemControl::disk_sweeper_clean() ? 0 : 1;
        }
        std::cout << SystemControl::disk_sweeper_scan() << "\n";
        return 0;
    } else if (cmd == "snapshot") {
        std::string sub = (argc >= 3) ? argv[2] : "list";
        if (sub == "create") {
            std::string comment = (argc >= 4) ? argv[3] : "";
            return SystemControl::snapshot_create(comment) ? 0 : 1;
        }
        std::cout << SystemControl::snapshot_list() << "\n";
        return 0;
    } else if (cmd == "vault") {
        std::string sub = (argc >= 3) ? argv[2] : "status";
        if (sub == "status") {
            std::cout << SystemControl::vault_status() << "\n";
            return 0;
        } else if (sub == "unmount") {
            std::string mp = (argc >= 4) ? argv[3] : "";
            return SystemControl::vault_unmount(mp) ? 0 : 1;
        } else if (sub == "mount") {
            std::string vp = (argc >= 4) ? argv[3] : "";
            std::string mp = (argc >= 5) ? argv[4] : "";
            std::string pwd = (argc >= 6) ? argv[5] : "";
            return SystemControl::vault_mount(vp, mp, pwd) ? 0 : 1;
        }
        return 0;
    } else if (cmd == "lock") {
        if (DaemonDBus::is_running()) return DaemonDBus::call_lock() ? 0 : 1;
        // No explicit mode: this is the common path (swayidle, the lock
        // keybind) and should return as soon as the lock screen is spawned,
        // not block until it's dismissed. An explicit mode is a manual
        // debug override, where waiting for the real result is expected.
        if (argc < 3) return SystemControl::lock_session_async() ? 0 : 1;
        return SystemControl::lock_session(argv[2]) ? 0 : 1;
    } else if (cmd == "polkit" || cmd == "polkit-agent") {
        std::string sub = (argc >= 3) ? argv[2] : "agent";
        if (sub == "dialog") {
            std::string action_id = (argc >= 4) ? argv[3] : "org.freedesktop.policykit.exec";
            std::string msg = (argc >= 5) ? argv[4] : "Authentication is required.";
            std::string user = (argc >= 6) ? argv[5] : "";
            std::string pwd = SystemControl::polkit_prompt_dialog(action_id, msg, user);
            std::cout << pwd << "\n";
            return pwd.empty() ? 1 : 0;
        } else {
            return SystemControl::polkit_agent_run();
        }
    } else if (cmd == "polkit-write") {
        if (argc < 3) return 1;
        std::string response((std::istreambuf_iterator<char>(std::cin)), std::istreambuf_iterator<char>());
        return SystemControl::polkit_write_response(argv[2], response) ? 0 : 1;
    } else if (cmd == "version" || cmd == "-v" || cmd == "--version") {
        // Was a hardcoded "v2.5.0 ... Tokyo Night" — stale (the shell moved
        // to Catppuccin) and disconnected from anything real. version.hpp is
        // the one place this now gets bumped.
        std::cout << "b1air-daemon v" << b1air::kVersion << "\n";
        return 0;
    } else if (cmd == "help" || cmd == "-h" || cmd == "--help") {
        print_usage(argv[0]);
        return 0;
    } else {
        std::cerr << "Unknown command: " << cmd << "\n";
        print_usage(argv[0]);
        return 1;
    }
}
