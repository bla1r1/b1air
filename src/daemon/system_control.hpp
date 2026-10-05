#pragma once
#include <string>
#include <vector>

namespace b1air {

class SystemControl {
public:
    // Game Mode controls
    static bool enable_game_mode();
    static bool disable_game_mode();
    static bool toggle_game_mode();
    static std::string get_game_mode_status_json();

    // Power & Session management
    static bool lock_session();   // blocks until opened
    // Non-blocking: spawns the lock screen and returns immediately, instead
    // of waiting for it to be dismissed. lock_session() waits for
    // run_lock()'s child to exit, which is fine for an explicit
    // "lock now" call but wrong for swayidle's before-sleep hook — logind
    // only grants a few seconds before forcing sleep regardless, so a
    // blocking call there gets killed mid-lock and looks like it never ran.
    static bool lock_session_async();
    static bool run_lock();
    static bool logout_session();
    static bool suspend_system();
    static bool reboot_system();
    static bool shutdown_system();

    // Multi-Monitor Layout Manager
    static bool monitors_restore();
    static bool monitors_apply(const std::string& layout_json);
    static bool monitors_save(const std::string& layout_json);
    // Saved layouts, one per set of screens: [{key, screens, saved, current}].
    static std::string monitors_profiles_json();
    static bool monitors_forget(const std::string& key);
    // Gives sway, ahead of time, the saved settings of each screen that would
    // complete a saved layout, so it comes up as saved when plugged in.
    static void monitors_arm_hotplug();
    // Re-applies the matching profile whenever the set of screens changes.
    // Blocks; the session runs it on its own thread.
    static void watch_outputs();

    // Screenshot helper

    /**
     * Is anything holding a /dev/video* device open right now.
     *
     * There is no kernel flag for "the camera is on": V4L2 exposes no in-use
     * attribute and the LED beside the lens is wired to the hardware, not to
     * anything readable. What there is, is the open file descriptor, so this
     * walks /proc looking for one. No process is spawned — this is readdir and
     * readlink, which is what `fuser` would do for us at the cost of a fork
     * every time we asked.
     *
     * Processes belonging to other users are skipped rather than reported as
     * an error: not being allowed to look is not the same as nothing being
     * there, but it is the best a session daemon can say.
     */
    static bool camera_in_use();

    // Layout helpers
    static std::string get_layout_shorthand();
    static bool toggle_fullscreen();
    static std::string get_wifi_status_json();
    static std::string get_media_status_json();

    // Dynamic Applications Scanner (.desktop parser)
    static std::string apps_list_json(const std::string& category = "all");

    // Power Profiles (performance, balanced, power-saver)
    static std::string power_profile_get();
    // power-profiles-daemon is there to switch: it answers on D-Bus.
    static bool power_profile_available();
    static bool power_profile_set(const std::string& profile);

    // Battery charge control: the limit the pack stops charging at, and what
    // the charger does while it is plugged in. Both are per-pack sysfs files,
    // and this machine has two packs — a single number would have described
    // whichever one was listed first.
    static std::string battery_status_json();
    static bool battery_limit_set(int percent);
    static bool battery_behaviour_set(const std::string& behaviour);

    // Caffeine / Idle Inhibitor (Stay Awake Mode)
    static bool caffeine_is_active();
    static bool caffeine_toggle();
    static bool caffeine_set(bool active);

    // Color Dropper / Pixel Picker
    static std::string pick_color();

    // Window Minimization
    static bool window_minimize();
    static bool window_restore(int64_t con_id = -1);
    static bool window_toggle_minimize();
    static bool window_maximize_toggle();
    static bool appearance_apply();
    static bool window_float_all_toggle();
    static bool window_opacity_toggle();
    static int window_count_minimized();
    static std::string window_list_minimized_json();
    static std::string window_list_open_json();

    // Remote Desktop & Screencast Management
    static bool remote_desktop_start(int port = 5900, const std::string& password = "");
    static bool remote_desktop_stop();
    static bool remote_desktop_toggle();
    static std::string remote_desktop_status_json();
    static bool set_screencast_prompt_free(bool enable);
    static bool is_screencast_prompt_free();
    static bool sidecar_create_virtual_display(int width = 1920, int height = 1080);
    static bool sidecar_remove_virtual_display();

    // Wi-Fi & Network interactive management
    static std::string wifi_list_json();
    static std::string wifi_connect(const std::string& ssid, const std::string& password = "");

    // Bluetooth interactive management
    static std::string bt_list_json();
    static bool bt_connect(const std::string& mac);
    static bool bt_disconnect(const std::string& mac);
    static bool bt_pair(const std::string& mac);

    // Volume & Microphone controls
    static int get_volume();
    static bool volume_up(int step = 5);
    static bool volume_down(int step = 5);
    static bool volume_toggle_mute();
    static std::string get_mic_status();
    static bool mic_toggle();

    // Screen Brightness controls
    static bool brightness_available();
    static int brightness_get();
    static bool brightness_up(int step = 5);
    static bool brightness_down(int step = 5);
    static bool brightness_set(int pct);

    // DDC/CI External Monitor Controls
    static std::string ddc_list_json(bool force_detect = false);
    static bool ddc_set(const std::string& id, int percent);
    static bool ddc_adjust_all(int step);
    static std::string ddc_status_json();
    static bool ddc_refresh();
    static bool ddc_dim();
    static bool ddc_undim();

    // Weather Forecast & Live Status
    static std::string weather_get_json(bool force = false);
    static std::string weather_get_current_info(const std::string& field = "current");
    static std::string weather_cached_info(const std::string& field = "current");
    static std::string weather_current_from(const std::string& json, const std::string& field);

    // Equalizer & EasyEffects Controls
    static std::string eq_get_state_json();
    static bool eq_set_band(int band_idx, int val);
    static bool eq_set_preset(const std::string& preset);
    static bool eq_set_all(const std::vector<int>& bands);
    static bool eq_apply();

    // Media Cover Art & Palette Extraction
    static std::string media_get_info_json();

    // Diary & Notes
    static bool diary_open();

    // Calendar Schedule
    static std::string schedule_get_json();

    // Dotfiles Git & Maintenance
    static std::string dotfiles_status_json();
    static bool dotfiles_sync();
    static bool dotfiles_sys();
    // Package cache and orphan cleanup, in a held terminal, for whichever
    // package manager this is. what: "cache" or "orphans".
    static bool packages_clean(const std::string& what);
    // The system upgrade's steps for this package manager, and running them
    // in the calling terminal (`b1air-daemon packages upgrade`).
    static std::vector<std::vector<std::string>> packages_upgrade_steps();
    static int packages_upgrade();
    // A freedesktop sound-theme event ("bell", "camera-shutter"), through
    // pw-play; on the default output, or on `target` (a PipeWire node name).
    static bool play_sound(const std::string& name, const std::string& target = {});
    // A wired connection's IPv4: method "auto", or "manual" with an address,
    // prefix, gateway and DNS server (the last two may be empty). Through
    // NetworkManager, or with `ip` directly where it does not manage the link.
    static bool ethernet_ipv4(const std::string& ifname, const std::string& method,
                              const std::string& address, const std::string& prefix,
                              const std::string& gateway, const std::string& dns);
    // `xdg-mime query default` for each type, one line each (empty if none).
    static std::vector<std::string> mime_defaults(const std::vector<std::string>& mimes);

    // Advanced Screen Capture, Recording, OCR & QR Scanner
    static bool capture(const std::string& mode = "full", const std::string& geom = "", bool edit = false,
                        int delay_override = -1);
    static bool run_screenshot_overlay(bool edit_mode = false);
    static bool record_toggle(const std::string& geom = "", double desk_vol = 1.0, double mic_vol = 1.0, bool desk_mute = false, bool mic_mute = false, const std::string& mic_dev = "");
    static bool record_stop();
    static std::string scan_qr(const std::string& geom = "");
    static bool qr_generate(const std::string& text, const std::string& out_path = "");
    static bool ocr_screen(const std::string& geom = "");

    // Advanced Window Management & Screen Assistants
    static bool pip_toggle();
    static std::string pip_status();
    static bool force_quit();
    static bool cursor_locate();
    static bool quicklook_open(const std::string& path);
    static bool zones_apply(int zone_id);

    // Audio Output Switcher & RNNoise AI Noise Suppression (M3)
    static bool audio_switch_output();
    static bool mic_rnnoise_toggle();
    static bool mic_rnnoise_set(bool enable);
    static bool mic_rnnoise_is_active();
    static bool record_gif(const std::string& geom = "");
    static bool voice_memo();

    // Privacy, Disk Maintenance & Snapshots (M4)
    static std::string disk_sweeper_scan();
    static bool disk_sweeper_clean();
    static bool snapshot_create(const std::string& comment = "");
    static std::string snapshot_list();
    static bool vault_mount(const std::string& vault_path, const std::string& mount_point, const std::string& password);
    static bool vault_unmount(const std::string& mount_point);
    static std::string vault_status();

    // Keyboard Backlight controls
    static bool kbd_backlight_available();
    static int kbd_backlight_get();
    static bool kbd_backlight_inc(int step = 10);
    static bool kbd_backlight_dec(int step = 10);
    static bool kbd_backlight_set(int val);
    static bool kbd_backlight_off();

    // Wallpaper management
    static bool wallpaper_set(const std::string& filepath, const std::string& mode = "set");
    static bool wallpaper_random(const std::string& dir = "");
    static bool wallpaper_restore();
    // One screen's own wallpaper, kept by the screen's identity.
    static bool wallpaper_set_output(const std::string& filepath, const std::string& output);
    // One workspace's own wallpaper (drawn by b1air-bg), and taking a
    // screen's or a workspace's own back to the shared one.
    static bool wallpaper_set_workspace(const std::string& filepath, const std::string& workspace);
    // The picture b1air-bg shows on this screen now (its workspace's own,
    // the screen's own, or the shared one): for the lock screen.
    static std::string wallpaper_shown_on(const std::string& output);
    static bool wallpaper_unset(const std::string& output, const std::string& workspace = "");
    static std::string wallpaper_workspaces_json();
    static std::string wallpaper_overrides_path();
    // [{name, id, wallpaper}] for the connected screens.
    static std::string wallpaper_overrides_json();

    // Night Light & Day/Night Ambiance
    // When the night light is warm: always, between two times, or from
    // sunset to sunrise (at `location`, "lat,lon", or the time zone's city).
    struct NightSchedule {
        std::string mode = "always";   // always | hours | sun
        std::string from = "20:00";
        std::string to = "07:00";
        std::string location;
        static NightSchedule from_settings();
    };
    static bool night_light_on(int temp = 4000, bool announce = true);
    static bool night_light_on(int temp, bool announce, const NightSchedule& schedule);
    static bool night_light_off(bool announce = true);
    static bool night_light_toggle();

    // Power source: true on mains, or on a machine with no battery at all.
    static bool on_ac_power();
    // The lid and the power button, as Settings → Power says (sway binds
    // them to `b1air-daemon lid close|open` and `power-key`; the idle thread
    // tells logind to leave them to us while those bindings are there).
    static bool lid_event(bool closed);
    static bool power_key();

    // System updates and the brightness status line.
    //
    // These print a one-line JSON object — text, tooltip, class — which is the
    // shape Waybar's custom modules read. That is where it came from; the bar
    // has been this project's own since, and nothing in the shell parses it.
    // Kept because it is a reasonable thing for a status script to consume,
    // renamed because calling it "waybar" said it belonged to a program this
    // desktop does not ship.
    static std::string get_updates_json(bool force = false);
    static bool launch_system_upgrade();
    static bool open_default(const std::string& kind);

    // Terminal Themes
    static std::vector<std::string> term_theme_list();
    static bool term_theme_set(const std::string& theme);

    // Gamepad Idle Inhibitor
    static int run_gamepad_inhibit();

    // Desktop Reload
    static bool reload_desktop();

    // System Monitor & Task Manager
    static std::string get_system_stats_json();
    static bool kill_process(int pid, bool force = false);

    // Native Polkit Authentication Agent
    static int polkit_agent_run();
    static std::string polkit_prompt_dialog(const std::string& action_id, const std::string& message,
                                            const std::string& user = "", const std::string& cookie = "");
    static bool polkit_write_response(const std::string& path, const std::string& response);
};

} // namespace b1air
