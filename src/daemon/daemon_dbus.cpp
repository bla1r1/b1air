#include "proc_util.hpp"
#include "daemon_dbus.hpp"
#include "system_control.hpp"
#include "focustime_db.hpp"
#include "runtime.hpp"
#include "version.hpp"
#include <iostream>
#include <cstring>
#include <cstdlib>
#include <cctype>
#include <cerrno>
#include <unistd.h>
#include <fcntl.h>
#include <sys/wait.h>
#include <vector>

namespace b1air {

// The service intentionally lives on the user bus, but still verify the
// sender credentials before dispatching any state-changing operation. This
// keeps a future move to a broader bus or activation model fail-closed.
static bool sender_is_current_user(sd_bus_message *m, sd_bus_error *error) {
    uid_t sender_uid = static_cast<uid_t>(-1);
    sd_bus_creds* creds = nullptr;
    // SD_BUS_CREDS_UID alone only reads what the transport attached to the
    // message directly (raw SO_PEERCRED on a peer-to-peer connection). On a
    // session bus routed through dbus-broker — the normal case, and what
    // every real desktop install actually runs — the message carries no
    // socket-level UID at all, so this returned -ENODATA and rejected every
    // legitimate call. AUGMENT tells sd-bus to fall back to reading
    // /proc/<sender-pid>/status when the transport didn't attach it.
    const bool valid = sd_bus_query_sender_creds(m, SD_BUS_CREDS_UID | SD_BUS_CREDS_AUGMENT, &creds) >= 0 &&
                       sd_bus_creds_get_uid(creds, &sender_uid) >= 0 && sender_uid == getuid();
    sd_bus_creds_unref(creds);
    if (!valid) {
        sd_bus_error_set_const(error, SD_BUS_ERROR_ACCESS_DENIED,
                               "b1air.Daemon accepts calls only from the session user");
        return false;
    }
    return true;
}


#define REQUIRE_SESSION_USER() do { if (!sender_is_current_user(m, ret_error)) return -EACCES; } while (0)

static int method_lock(sd_bus_message *m, void *userdata, sd_bus_error *ret_error) {
    (void)userdata; (void)ret_error;
    REQUIRE_SESSION_USER();
    // lock_session() blocks until the lock screen is actually dismissed —
    // fine for a one-off CLI call, fatal here: sd-bus dispatches this on the
    // daemon's own event loop, so every other D-Bus call (volume, brightness,
    // Wi-Fi, ...) would hang for as long as the screen stayed locked.
    SystemControl::lock_session_async();
    return sd_bus_reply_method_return(m, "");
}

static int method_reload(sd_bus_message *m, void *userdata, sd_bus_error *ret_error) {
    (void)userdata; (void)ret_error;
    REQUIRE_SESSION_USER();
    util::spawn_detached({"swaymsg", "reload"});
    util::spawn_detached({"b1air-shell", "forceReload"});
    return sd_bus_reply_method_return(m, "");
}

static int method_volume_up(sd_bus_message *m, void *userdata, sd_bus_error *ret_error) {
    (void)userdata; (void)ret_error;
    REQUIRE_SESSION_USER();
    int step = 5;
    sd_bus_message_read(m, "i", &step);
    SystemControl::volume_up(step);
    return sd_bus_reply_method_return(m, "");
}

static int method_volume_down(sd_bus_message *m, void *userdata, sd_bus_error *ret_error) {
    (void)userdata; (void)ret_error;
    REQUIRE_SESSION_USER();
    int step = 5;
    sd_bus_message_read(m, "i", &step);
    SystemControl::volume_down(step);
    return sd_bus_reply_method_return(m, "");
}

static int method_volume_mute(sd_bus_message *m, void *userdata, sd_bus_error *ret_error) {
    (void)userdata; (void)ret_error;
    REQUIRE_SESSION_USER();
    SystemControl::volume_toggle_mute();
    return sd_bus_reply_method_return(m, "");
}

static int method_brightness_up(sd_bus_message *m, void *userdata, sd_bus_error *ret_error) {
    (void)userdata; (void)ret_error;
    REQUIRE_SESSION_USER();
    int step = 5;
    sd_bus_message_read(m, "i", &step);
    SystemControl::brightness_up(step);
    return sd_bus_reply_method_return(m, "");
}

static int method_brightness_down(sd_bus_message *m, void *userdata, sd_bus_error *ret_error) {
    (void)userdata; (void)ret_error;
    REQUIRE_SESSION_USER();
    int step = 5;
    sd_bus_message_read(m, "i", &step);
    SystemControl::brightness_down(step);
    return sd_bus_reply_method_return(m, "");
}

static int method_brightness_set(sd_bus_message *m, void *userdata, sd_bus_error *ret_error) {
    (void)userdata; (void)ret_error;
    REQUIRE_SESSION_USER();
    int pct = 50;
    sd_bus_message_read(m, "i", &pct);
    SystemControl::brightness_set(pct);
    return sd_bus_reply_method_return(m, "");
}

static int method_gamemode(sd_bus_message *m, void *userdata, sd_bus_error *ret_error) {
    (void)userdata; (void)ret_error;
    REQUIRE_SESSION_USER();
    int enabled = 0;
    sd_bus_message_read(m, "b", &enabled);
    if (enabled) SystemControl::enable_game_mode();
    else SystemControl::disable_game_mode();
    return sd_bus_reply_method_return(m, "");
}

static int method_capture(sd_bus_message *m, void *userdata, sd_bus_error *ret_error) {
    (void)userdata; (void)ret_error;
    REQUIRE_SESSION_USER();
    const char *mode = "full";
    sd_bus_message_read(m, "s", &mode);
    // One implementation. capture_screenshot() was a second copy of this
    // feature living behind this method: it ignored every screenshot setting,
    // wrote its own filename convention, and its window mode was broken the
    // same way capture()'s was. Callers of Capture get the real one now.
    SystemControl::capture(mode ? mode : "full", "", false);
    return sd_bus_reply_method_return(m, "");
}

// Capture with an explicit geometry and an optional editor pass. Both this
// and the plain Capture above reach SystemControl::capture(); this one simply
// passes the extra arguments.
static int method_capture_geom(sd_bus_message *m, void *userdata, sd_bus_error *ret_error) {
    (void)userdata; (void)ret_error;
    REQUIRE_SESSION_USER();
    const char *mode = "full";
    const char *geom = "";
    int edit = 0;
    sd_bus_message_read(m, "ssb", &mode, &geom, &edit);
    SystemControl::capture(mode ? mode : "full", geom ? geom : "", edit);
    return sd_bus_reply_method_return(m, "");
}

static int method_power(sd_bus_message *m, void *userdata, sd_bus_error *ret_error) {
    (void)userdata; (void)ret_error;
    REQUIRE_SESSION_USER();
    const char *action = "lock";
    sd_bus_message_read(m, "s", &action);
    std::string act = action ? action : "lock";
    if (act == "lock") SystemControl::lock_session_async();
    else if (act == "logout") SystemControl::logout_session();
    else if (act == "suspend") SystemControl::suspend_system();
    else if (act == "reboot") SystemControl::reboot_system();
    else if (act == "shutdown") SystemControl::shutdown_system();
    return sd_bus_reply_method_return(m, "");
}

// ── Remote desktop ───────────────────────────────────────────────────────────
static int method_remote_status(sd_bus_message *m, void *userdata, sd_bus_error *ret_error) {
    (void)userdata; (void)ret_error;
    REQUIRE_SESSION_USER();
    return sd_bus_reply_method_return(m, "s", SystemControl::remote_desktop_status_json().c_str());
}

static int method_remote_stop(sd_bus_message *m, void *userdata, sd_bus_error *ret_error) {
    (void)userdata; (void)ret_error;
    REQUIRE_SESSION_USER();
    SystemControl::remote_desktop_stop();
    return sd_bus_reply_method_return(m, "");
}

static int method_remote_prompt_free(sd_bus_message *m, void *userdata, sd_bus_error *ret_error) {
    (void)userdata; (void)ret_error;
    REQUIRE_SESSION_USER();
    int enabled = 0;
    sd_bus_message_read(m, "b", &enabled);
    SystemControl::set_screencast_prompt_free(enabled);
    return sd_bus_reply_method_return(m, "");
}

static int method_sidecar_create(sd_bus_message *m, void *userdata, sd_bus_error *ret_error) {
    (void)userdata; (void)ret_error;
    REQUIRE_SESSION_USER();
    int width = 1920, height = 1080;
    sd_bus_message_read(m, "ii", &width, &height);
    SystemControl::sidecar_create_virtual_display(width, height);
    return sd_bus_reply_method_return(m, "");
}

static int method_sidecar_remove(sd_bus_message *m, void *userdata, sd_bus_error *ret_error) {
    (void)userdata; (void)ret_error;
    REQUIRE_SESSION_USER();
    SystemControl::sidecar_remove_virtual_display();
    return sd_bus_reply_method_return(m, "");
}

// ── Dotfiles & maintenance ───────────────────────────────────────────────────
static int method_dotfiles_status(sd_bus_message *m, void *userdata, sd_bus_error *ret_error) {
    (void)userdata; (void)ret_error;
    REQUIRE_SESSION_USER();
    return sd_bus_reply_method_return(m, "s", SystemControl::dotfiles_status_json().c_str());
}

static int method_dotfiles_sys(sd_bus_message *m, void *userdata, sd_bus_error *ret_error) {
    (void)userdata; (void)ret_error;
    REQUIRE_SESSION_USER();
    SystemControl::dotfiles_sys();
    return sd_bus_reply_method_return(m, "");
}

static int method_dotfiles_sync(sd_bus_message *m, void *userdata, sd_bus_error *ret_error) {
    (void)userdata; (void)ret_error;
    REQUIRE_SESSION_USER();
    SystemControl::dotfiles_sync();
    return sd_bus_reply_method_return(m, "");
}

static int method_sweeper_clean(sd_bus_message *m, void *userdata, sd_bus_error *ret_error) {
    (void)userdata; (void)ret_error;
    REQUIRE_SESSION_USER();
    SystemControl::disk_sweeper_clean();
    return sd_bus_reply_method_return(m, "");
}

// ── Zones, mic, power profile ────────────────────────────────────────────────
static int method_zones_apply(sd_bus_message *m, void *userdata, sd_bus_error *ret_error) {
    (void)userdata; (void)ret_error;
    REQUIRE_SESSION_USER();
    int zone_id = 0;
    sd_bus_message_read(m, "i", &zone_id);
    SystemControl::zones_apply(zone_id);
    return sd_bus_reply_method_return(m, "");
}

static int method_mic_rnnoise_toggle(sd_bus_message *m, void *userdata, sd_bus_error *ret_error) {
    (void)userdata; (void)ret_error;
    REQUIRE_SESSION_USER();
    SystemControl::mic_rnnoise_toggle();
    return sd_bus_reply_method_return(m, "");
}

static int method_power_profile_set(sd_bus_message *m, void *userdata, sd_bus_error *ret_error) {
    (void)userdata; (void)ret_error;
    REQUIRE_SESSION_USER();
    const char *name = "balanced";
    sd_bus_message_read(m, "s", &name);
    SystemControl::power_profile_set(name ? name : "balanced");
    return sd_bus_reply_method_return(m, "");
}

// ── Monitors & DDC ────────────────────────────────────────────────────────────
static int method_monitors_apply(sd_bus_message *m, void *userdata, sd_bus_error *ret_error) {
    (void)userdata; (void)ret_error;
    REQUIRE_SESSION_USER();
    const char *layout_json = "";
    sd_bus_message_read(m, "s", &layout_json);
    SystemControl::monitors_apply(layout_json ? layout_json : "");
    return sd_bus_reply_method_return(m, "");
}

static int method_ddc_set(sd_bus_message *m, void *userdata, sd_bus_error *ret_error) {
    (void)userdata; (void)ret_error;
    REQUIRE_SESSION_USER();
    const char *id = "";
    int percent = 50;
    sd_bus_message_read(m, "si", &id, &percent);
    SystemControl::ddc_set(id ? id : "", percent);
    return sd_bus_reply_method_return(m, "");
}

// ── Equalizer ─────────────────────────────────────────────────────────────────
static int method_eq_apply(sd_bus_message *m, void *userdata, sd_bus_error *ret_error) {
    (void)userdata; (void)ret_error;
    REQUIRE_SESSION_USER();
    SystemControl::eq_apply();
    return sd_bus_reply_method_return(m, "");
}

static int method_eq_set_band(sd_bus_message *m, void *userdata, sd_bus_error *ret_error) {
    (void)userdata; (void)ret_error;
    REQUIRE_SESSION_USER();
    int band = 0, value = 0;
    sd_bus_message_read(m, "ii", &band, &value);
    SystemControl::eq_set_band(band, value);
    return sd_bus_reply_method_return(m, "");
}

static int method_eq_set_preset(sd_bus_message *m, void *userdata, sd_bus_error *ret_error) {
    (void)userdata; (void)ret_error;
    REQUIRE_SESSION_USER();
    const char *name = "Flat";
    sd_bus_message_read(m, "s", &name);
    SystemControl::eq_set_preset(name ? name : "Flat");
    return sd_bus_reply_method_return(m, "");
}

static int method_eq_set_all(sd_bus_message *m, void *userdata, sd_bus_error *ret_error) {
    (void)userdata; (void)ret_error;
    REQUIRE_SESSION_USER();
    std::vector<int> bands;
    int r = sd_bus_message_enter_container(m, SD_BUS_TYPE_ARRAY, "i");
    if (r < 0) return r;
    int32_t band_val = 0;
    while ((r = sd_bus_message_read_basic(m, SD_BUS_TYPE_INT32, &band_val)) > 0) {
        bands.push_back(band_val);
    }
    sd_bus_message_exit_container(m);
    SystemControl::eq_set_all(bands);
    return sd_bus_reply_method_return(m, "");
}

// ── Screenshot QR scan ────────────────────────────────────────────────────────
static int method_scan_qr(sd_bus_message *m, void *userdata, sd_bus_error *ret_error) {
    (void)userdata; (void)ret_error;
    REQUIRE_SESSION_USER();
    const char *geom = "";
    sd_bus_message_read(m, "s", &geom);
    return sd_bus_reply_method_return(m, "s", SystemControl::scan_qr(geom ? geom : "").c_str());
}

static int method_get_version(sd_bus_message *m, void *userdata, sd_bus_error *ret_error) {
    (void)userdata; (void)ret_error;
    return sd_bus_reply_method_return(m, "s", b1air::kVersion);
}

static int method_get_stats(sd_bus_message *m, void *userdata, sd_bus_error *ret_error) {
    (void)userdata; (void)ret_error;
    REQUIRE_SESSION_USER();
    const char *date = "";
    sd_bus_message_read(m, "s", &date);
    FocusTimeDB db;
    std::string res = "{}";
    if (db.open()) {
        res = db.get_stats_json(date ? date : "");
    }
    return sd_bus_reply_method_return(m, "s", res.c_str());
}

static const sd_bus_vtable daemon_vtable[] = {
    SD_BUS_VTABLE_START(0),
    SD_BUS_METHOD("Lock", "", "", method_lock, SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_METHOD("Reload", "", "", method_reload, SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_METHOD("VolumeUp", "i", "", method_volume_up, SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_METHOD("VolumeDown", "i", "", method_volume_down, SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_METHOD("ToggleMute", "", "", method_volume_mute, SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_METHOD("BrightnessUp", "i", "", method_brightness_up, SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_METHOD("BrightnessDown", "i", "", method_brightness_down, SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_METHOD("BrightnessSet", "i", "", method_brightness_set, SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_METHOD("SetGameMode", "b", "", method_gamemode, SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_METHOD("Capture", "s", "", method_capture, SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_METHOD("CaptureGeom", "ssb", "", method_capture_geom, SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_METHOD("Power", "s", "", method_power, SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_METHOD("GetVersion", "", "s", method_get_version, SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_METHOD("GetStats", "s", "s", method_get_stats, SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_METHOD("RemoteStatus", "", "s", method_remote_status, SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_METHOD("RemoteStop", "", "", method_remote_stop, SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_METHOD("RemotePromptFree", "b", "", method_remote_prompt_free, SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_METHOD("SidecarCreate", "ii", "", method_sidecar_create, SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_METHOD("SidecarRemove", "", "", method_sidecar_remove, SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_METHOD("DotfilesStatus", "", "s", method_dotfiles_status, SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_METHOD("DotfilesSys", "", "", method_dotfiles_sys, SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_METHOD("DotfilesSync", "", "", method_dotfiles_sync, SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_METHOD("SweeperClean", "", "", method_sweeper_clean, SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_METHOD("ZonesApply", "i", "", method_zones_apply, SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_METHOD("MicRnnoiseToggle", "", "", method_mic_rnnoise_toggle, SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_METHOD("PowerProfileSet", "s", "", method_power_profile_set, SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_METHOD("MonitorsApply", "s", "", method_monitors_apply, SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_METHOD("DdcSet", "si", "", method_ddc_set, SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_METHOD("EqApply", "", "", method_eq_apply, SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_METHOD("EqSetBand", "ii", "", method_eq_set_band, SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_METHOD("EqSetPreset", "s", "", method_eq_set_preset, SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_METHOD("EqSetAll", "ai", "", method_eq_set_all, SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_METHOD("ScanQr", "s", "s", method_scan_qr, SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_SIGNAL("VolumeChanged", "ib", 0),
    SD_BUS_SIGNAL("BrightnessChanged", "i", 0),
    SD_BUS_SIGNAL("WallpaperChanged", "s", 0),
    // Emitted when something opens or closes a /dev/video* device. The three
    // signals above it are declared and never emitted by anything — noted here
    // rather than quietly joined.
    SD_BUS_SIGNAL("CameraInUseChanged", "b", 0),
    SD_BUS_VTABLE_END
};

static std::string get_wayland_display() {
    const char *wdisp = std::getenv("WAYLAND_DISPLAY");
    if (!wdisp || strlen(wdisp) == 0) {
        const char *rundir = std::getenv("XDG_RUNTIME_DIR");
        if (rundir) {
            for (int i = 0; i < 5; ++i) {
                std::string sock = std::string(rundir) + "/wayland-" + std::to_string(i);
                if (access(sock.c_str(), F_OK) == 0) {
                    return "wayland-" + std::to_string(i);
                }
            }
        }
        return "wayland-1";
    }
    return wdisp;
}

// Panel names are QML object keys, not user text: an enum here duplicates
// WindowRegistry.js and silently drifts out of sync with it — "zones",
// "battery", "shelf" and half the other real panels were never in this list,
// so their keybinds fell straight through to method_shell's error path
// (or the equally broken bash fallback below). An unrecognised name is
// harmless: WindowRegistry.getLayout() just returns null and the shell
// no-ops. What actually needs blocking is shell metacharacters.
static bool valid_panel(const std::string& panel) {
    if (panel.empty() || panel.size() > 64) return false;
    for (unsigned char c : panel) {
        if (!(std::isalnum(c) || c == '-' || c == '_')) return false;
    }
    return true;
}

static bool safe_shell_arg(const std::string& value, size_t max_len = 4096) {
    if (value.empty() || value.size() > max_len) return value.empty();
    for (unsigned char c : value) {
        if (std::iscntrl(c) || c == '\'' || c == '"' || c == '`' || c == '$' ||
            c == ';' || c == '&' || c == '|' || c == '<' || c == '>') return false;
    }
    return true;
}

/**
 * Ask the running shell to do something, over the bus it is already on.
 *
 * Every one of the six handlers below used to answer by launching a whole
 * `quickshell` process — a second Qt/QML host, started, connected to the
 * already-running instance's socket, handed one string, and torn down — for
 * each Mod+C, each Alt+Tab press, each Alt+Tab release. It cost more than the
 * two-second polling loop the bar used to run, and it happened on a keystroke
 * rather than a timer.
 *
 * The shell is subscribed to this signal through the B1air.Daemon plugin, on
 * the session bus it already holds open, so this is a message rather than a
 * process. Nothing is spawned, and there is nothing to tear down.
 *
 * A signal reaches only a shell that is running — which is all the old spawn
 * could reach either: `quickshell ipc call` connects to an existing instance
 * and fails when there is none.
 */
static int emit_panel_request(sd_bus_message *m, const char *action,
                              const std::string &panel, const std::string &arg) {
    sd_bus *bus = sd_bus_message_get_bus(m);
    if (!bus) return 0;
    return sd_bus_emit_signal(bus, "/org/b1air/Shell", "org.b1air.Shell",
                              "PanelRequested", "sss", action, panel.c_str(), arg.c_str());
}

static int method_shell_toggle(sd_bus_message *m, void *userdata, sd_bus_error *ret_error) {
    (void)userdata; (void)ret_error;
    REQUIRE_SESSION_USER();
    const char *panel = "launcher";
    sd_bus_message_read(m, "s", &panel);
    std::string p = (panel && strlen(panel) > 0) ? panel : "launcher";
    if (!valid_panel(p)) return sd_bus_error_set_const(ret_error, SD_BUS_ERROR_INVALID_ARGS, "Invalid panel");
    emit_panel_request(m, "toggle", p, "");
    return sd_bus_reply_method_return(m, "");
}

static int method_shell_open(sd_bus_message *m, void *userdata, sd_bus_error *ret_error) {
    (void)userdata; (void)ret_error;
    REQUIRE_SESSION_USER();
    const char *panel = "launcher";
    const char *arg = "";
    sd_bus_message_read(m, "ss", &panel, &arg);
    std::string p = (panel && strlen(panel) > 0) ? panel : "launcher";
    std::string a = arg ? arg : "";
    if (!valid_panel(p) || !safe_shell_arg(a)) {
        return sd_bus_error_set_const(ret_error, SD_BUS_ERROR_INVALID_ARGS, "Invalid shell argument");
    }
    emit_panel_request(m, "open", p, a);
    return sd_bus_reply_method_return(m, "");
}

static int method_shell_close(sd_bus_message *m, void *userdata, sd_bus_error *ret_error) {
    (void)userdata; (void)ret_error;
    REQUIRE_SESSION_USER();
    emit_panel_request(m, "close", "", "");
    return sd_bus_reply_method_return(m, "");
}

static int method_shell_reload(sd_bus_message *m, void *userdata, sd_bus_error *ret_error) {
    (void)userdata; (void)ret_error;
    REQUIRE_SESSION_USER();
    emit_panel_request(m, "forceReload", "", "");
    return sd_bus_reply_method_return(m, "");
}

static const sd_bus_vtable shell_vtable[] = {
    SD_BUS_VTABLE_START(0),
    SD_BUS_METHOD("Toggle", "s", "", method_shell_toggle, SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_METHOD("Open", "ss", "", method_shell_open, SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_METHOD("Close", "s", "", method_shell_close, SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_METHOD("ForceReload", "", "", method_shell_reload, SD_BUS_VTABLE_UNPRIVILEGED),
    SD_BUS_SIGNAL("PanelStateChanged", "sb", 0),
    SD_BUS_SIGNAL("PanelRequested", "sss", 0),
    SD_BUS_VTABLE_END
};

int DaemonDBus::init_server(sd_bus **bus_out) {
    sd_bus *bus = nullptr;
    int r = sd_bus_open_user(&bus);
    if (r < 0) {
        std::cerr << "[b1air-daemon] Warning: Failed to connect to user D-Bus: " << strerror(-r) << "\n";
        return r;
    }

    r = sd_bus_add_object_vtable(bus, nullptr, "/org/b1air/Daemon", "org.b1air.Daemon", daemon_vtable, nullptr);
    if (r < 0) {
        std::cerr << "[b1air-daemon] Warning: Failed to register Daemon D-Bus vtable: " << strerror(-r) << "\n";
    }

    r = sd_bus_add_object_vtable(bus, nullptr, "/org/b1air/Shell", "org.b1air.Shell", shell_vtable, nullptr);
    if (r < 0) {
        std::cerr << "[b1air-daemon] Warning: Failed to register Shell D-Bus vtable: " << strerror(-r) << "\n";
    }

    sd_bus_request_name(bus, "org.b1air.Daemon", 0);
    sd_bus_request_name(bus, "org.b1air.Shell", 0);

    std::cout << "[b1air-daemon] Registered D-Bus services 'org.b1air.Daemon' and 'org.b1air.Shell'\n";
    *bus_out = bus;
    return 0;
}

int DaemonDBus::run_service() {
    sd_bus *bus = nullptr;
    int r = init_server(&bus);
    if (r < 0) return 1;

    std::cout << "[b1air-dbus] D-Bus service loop active. Listening on org.b1air.Daemon and org.b1air.Shell...\n";
    while (true) {
        r = sd_bus_process(bus, nullptr);
        if (r < 0) {
            std::cerr << "[b1air-dbus] Error processing D-Bus: " << strerror(-r) << "\n";
            break;
        }
        if (r > 0) continue;
        sd_bus_wait(bus, (uint64_t) -1);
    }
    sd_bus_unref(bus);
    return 0;
}

bool DaemonDBus::is_running() {
    sd_bus *bus = nullptr;
    if (sd_bus_open_user(&bus) < 0) return false;
    int has_owner = sd_bus_get_name_creds(bus, "org.b1air.Daemon", 0, nullptr) >= 0;
    sd_bus_unref(bus);
    return has_owner;
}

bool DaemonDBus::call_lock() {
    sd_bus *bus = nullptr;
    if (sd_bus_open_user(&bus) < 0) return false;
    int r = sd_bus_call_method(bus, "org.b1air.Daemon", "/org/b1air/Daemon", "org.b1air.Daemon", "Lock", nullptr, nullptr, "");
    sd_bus_unref(bus);
    return r >= 0;
}

bool DaemonDBus::call_reload() {
    sd_bus *bus = nullptr;
    if (sd_bus_open_user(&bus) < 0) return false;
    int r = sd_bus_call_method(bus, "org.b1air.Daemon", "/org/b1air/Daemon", "org.b1air.Daemon", "Reload", nullptr, nullptr, "");
    sd_bus_unref(bus);
    return r >= 0;
}

bool DaemonDBus::call_volume_up(int step) {
    sd_bus *bus = nullptr;
    if (sd_bus_open_user(&bus) < 0) return false;
    int r = sd_bus_call_method(bus, "org.b1air.Daemon", "/org/b1air/Daemon", "org.b1air.Daemon", "VolumeUp", nullptr, nullptr, "i", step);
    sd_bus_unref(bus);
    return r >= 0;
}

bool DaemonDBus::call_volume_down(int step) {
    sd_bus *bus = nullptr;
    if (sd_bus_open_user(&bus) < 0) return false;
    int r = sd_bus_call_method(bus, "org.b1air.Daemon", "/org/b1air/Daemon", "org.b1air.Daemon", "VolumeDown", nullptr, nullptr, "i", step);
    sd_bus_unref(bus);
    return r >= 0;
}

bool DaemonDBus::call_volume_mute() {
    sd_bus *bus = nullptr;
    if (sd_bus_open_user(&bus) < 0) return false;
    int r = sd_bus_call_method(bus, "org.b1air.Daemon", "/org/b1air/Daemon", "org.b1air.Daemon", "ToggleMute", nullptr, nullptr, "");
    sd_bus_unref(bus);
    return r >= 0;
}

bool DaemonDBus::call_brightness_up(int step) {
    sd_bus *bus = nullptr;
    if (sd_bus_open_user(&bus) < 0) return false;
    int r = sd_bus_call_method(bus, "org.b1air.Daemon", "/org/b1air/Daemon", "org.b1air.Daemon", "BrightnessUp", nullptr, nullptr, "i", step);
    sd_bus_unref(bus);
    return r >= 0;
}

bool DaemonDBus::call_brightness_down(int step) {
    sd_bus *bus = nullptr;
    if (sd_bus_open_user(&bus) < 0) return false;
    int r = sd_bus_call_method(bus, "org.b1air.Daemon", "/org/b1air/Daemon", "org.b1air.Daemon", "BrightnessDown", nullptr, nullptr, "i", step);
    sd_bus_unref(bus);
    return r >= 0;
}

bool DaemonDBus::call_brightness_set(int pct) {
    sd_bus *bus = nullptr;
    if (sd_bus_open_user(&bus) < 0) return false;
    int r = sd_bus_call_method(bus, "org.b1air.Daemon", "/org/b1air/Daemon", "org.b1air.Daemon", "BrightnessSet", nullptr, nullptr, "i", pct);
    sd_bus_unref(bus);
    return r >= 0;
}

bool DaemonDBus::call_game_mode(bool enabled) {
    sd_bus *bus = nullptr;
    if (sd_bus_open_user(&bus) < 0) return false;
    int r = sd_bus_call_method(bus, "org.b1air.Daemon", "/org/b1air/Daemon", "org.b1air.Daemon", "SetGameMode", nullptr, nullptr, "b", enabled ? 1 : 0);
    sd_bus_unref(bus);
    return r >= 0;
}

bool DaemonDBus::call_capture(const std::string& mode) {
    sd_bus *bus = nullptr;
    if (sd_bus_open_user(&bus) < 0) return false;
    int r = sd_bus_call_method(bus, "org.b1air.Daemon", "/org/b1air/Daemon", "org.b1air.Daemon", "Capture", nullptr, nullptr, "s", mode.c_str());
    sd_bus_unref(bus);
    return r >= 0;
}

bool DaemonDBus::call_power(const std::string& action) {
    sd_bus *bus = nullptr;
    if (sd_bus_open_user(&bus) < 0) return false;
    int r = sd_bus_call_method(bus, "org.b1air.Daemon", "/org/b1air/Daemon", "org.b1air.Daemon", "Power", nullptr, nullptr, "s", action.c_str());
    sd_bus_unref(bus);
    return r >= 0;
}

std::string DaemonDBus::call_get_stats(const std::string& date) {
    sd_bus *bus = nullptr;
    if (sd_bus_open_user(&bus) < 0) return "{}";
    sd_bus_message *reply = nullptr;
    sd_bus_error err = SD_BUS_ERROR_NULL;
    int r = sd_bus_call_method(bus, "org.b1air.Daemon", "/org/b1air/Daemon", "org.b1air.Daemon", "GetStats", &err, &reply, "s", date.c_str());
    std::string result = "{}";
    if (r >= 0 && reply) {
        const char *s = nullptr;
        if (sd_bus_message_read(reply, "s", &s) >= 0 && s) {
            result = s;
        }
        sd_bus_message_unref(reply);
    }
    sd_bus_error_free(&err);
    sd_bus_unref(bus);
    return result;
}

} // namespace b1air
