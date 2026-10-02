#include "settings_manager.hpp"
#include <filesystem>
#include <nlohmann/json.hpp>
#include "sway_ipc.hpp"

#include <iostream>
#include <fstream>
#include <sstream>
#include <cstdlib>
#include <unistd.h>
#include <sys/stat.h>
#if defined(__linux__)
#include <sys/inotify.h>
#endif
#include <poll.h>
#include <algorithm>
#include <cstring>
#include <cctype>
#include <thread>
#include <mutex>
#include <cstdio>

namespace b1air {

std::string SettingsManager::get_settings_filepath() {
    const char* env_path = std::getenv("SWAY_SETTINGS_FILE");
    if (env_path && *env_path) return env_path;

    const char* home = std::getenv("HOME");
    return std::string(home ? home : "/tmp") + "/.config/sway/settings.json";
}

// ── Ultra-fast string-based JSON extractor helpers (zero regex overhead) ────
static std::string read_file_contents(const std::string& path) {
    std::ifstream in(path);
    if (!in) return "";
    std::stringstream buffer;
    buffer << in.rdbuf();
    return buffer.str();
}

static std::string find_json_string(const std::string& json, const std::string& key, const std::string& fallback) {
    std::string needle = "\"" + key + "\"";
    size_t pos = json.find(needle);
    if (pos == std::string::npos) return fallback;
    size_t colon = json.find(':', pos + needle.size());
    if (colon == std::string::npos) return fallback;
    size_t quote1 = json.find('"', colon + 1);
    if (quote1 == std::string::npos) return fallback;
    size_t quote2 = json.find('"', quote1 + 1);
    if (quote2 == std::string::npos) return fallback;
    return json.substr(quote1 + 1, quote2 - quote1 - 1);
}

static int find_json_int(const std::string& json, const std::string& key, int fallback) {
    std::string needle = "\"" + key + "\"";
    size_t pos = json.find(needle);
    if (pos == std::string::npos) return fallback;
    size_t colon = json.find(':', pos + needle.size());
    if (colon == std::string::npos) return fallback;
    size_t start = json.find_first_of("0123456789-", colon + 1);
    if (start == std::string::npos) return fallback;
    size_t end = json.find_first_not_of("0123456789", start + (json[start] == '-' ? 1 : 0));
    std::string num = (end == std::string::npos) ? json.substr(start) : json.substr(start, end - start);
    try { return std::stoi(num); } catch (...) { return fallback; }
}

static bool find_json_bool(const std::string& json, const std::string& key, bool fallback) {
    std::string needle = "\"" + key + "\"";
    size_t pos = json.find(needle);
    if (pos == std::string::npos) return fallback;
    size_t colon = json.find(':', pos + needle.size());
    if (colon == std::string::npos) return fallback;
    size_t t = json.find("true", colon + 1);
    size_t f = json.find("false", colon + 1);
    size_t comma = json.find_first_of(",}\n\r", colon + 1);
    if (t != std::string::npos && (comma == std::string::npos || t < comma)) return true;
    if (f != std::string::npos && (comma == std::string::npos || f < comma)) return false;
    return fallback;
}

static std::vector<std::string> find_json_string_array(const std::string& json, const std::string& key) {
    std::vector<std::string> res;
    std::string needle = "\"" + key + "\"";
    size_t pos = json.find(needle);
    if (pos == std::string::npos) return res;
    size_t arr_start = json.find('[', pos + needle.size());
    if (arr_start == std::string::npos) return res;
    size_t arr_end = json.find(']', arr_start);
    if (arr_end == std::string::npos) return res;

    size_t cur = arr_start + 1;
    while (cur < arr_end) {
        size_t q1 = json.find('"', cur);
        if (q1 == std::string::npos || q1 >= arr_end) break;
        size_t q2 = json.find('"', q1 + 1);
        if (q2 == std::string::npos || q2 > arr_end) break;
        res.push_back(json.substr(q1 + 1, q2 - q1 - 1));
        cur = q2 + 1;
    }
    return res;
}

static bool valid_sway_token(const std::string& value, size_t max_len = 256) {
    if (value.empty() || value.size() > max_len) return false;
    for (unsigned char c : value) {
        if (!(std::isalnum(c) || c == '_' || c == '-' || c == ',' || c == ':' || c == '+')) return false;
    }
    return true;
}

static std::string json_quote(const std::string& value) {
    std::string out = "\"";
    for (unsigned char c : value) {
        if (c == '\\') out += "\\\\";
        else if (c == '\"') out += "\\\"";
        else if (c == '\n') out += "\\n";
        else if (c == '\r') out += "\\r";
        else if (c == '\t') out += "\\t";
        else if (c < 0x20) return "";
        else out += static_cast<char>(c);
    }
    out += '"';
    return out;
}

DesktopSettings SettingsManager::load(const std::string& path_arg) {
    std::string path = path_arg.empty() ? get_settings_filepath() : path_arg;
    DesktopSettings s;

    std::string content = read_file_contents(path);
    if (content.empty()) {
        // Create default settings.json
        save(s, path);
        return s;
    }

    s.language = find_json_string(content, "language", s.language);
    s.kbOptions = find_json_string(content, "kbOptions", s.kbOptions);

    s.gapsInner = find_json_int(content, "gapsInner", s.gapsInner);
    s.gapsOuter = find_json_int(content, "gapsOuter", s.gapsOuter);
    s.borderWidth = find_json_int(content, "borderWidth", s.borderWidth);
    s.smartBorders = find_json_bool(content, "smartBorders", s.smartBorders);
    s.smartGaps = find_json_bool(content, "smartGaps", s.smartGaps);

    s.workspaceCount = find_json_int(content, "workspaceCount", s.workspaceCount);
    s.guideShortcut = find_json_bool(content, "guideShortcut", s.guideShortcut);
    s.topbarHelpIcon = find_json_bool(content, "topbarHelpIcon", s.topbarHelpIcon);
    s.barPosition = find_json_string(content, "barPosition", s.barPosition);
    s.barShowWeather = find_json_bool(content, "barShowWeather", s.barShowWeather);
    s.barShowMedia = find_json_bool(content, "barShowMedia", s.barShowMedia);
    s.barShowTray = find_json_bool(content, "barShowTray", s.barShowTray);
    s.barClock24h = find_json_bool(content, "barClock24h", s.barClock24h);

    s.dimTimeout = find_json_int(content, "dimTimeout", s.dimTimeout);
    s.lockTimeout = find_json_int(content, "lockTimeout", s.lockTimeout);
    s.dpmsTimeout = find_json_int(content, "dpmsTimeout", s.dpmsTimeout);
    s.suspendTimeout = find_json_int(content, "suspendTimeout", s.suspendTimeout);

    // Keep numeric settings within compositor/systemd-safe bounds before they
    // are interpolated into the trusted idle command below.
    s.gapsInner = std::clamp(s.gapsInner, 0, 100);
    s.gapsOuter = std::clamp(s.gapsOuter, 0, 100);
    s.borderWidth = std::clamp(s.borderWidth, 0, 20);
    s.workspaceCount = std::clamp(s.workspaceCount, 1, 100);
    s.dimTimeout = std::clamp(s.dimTimeout, 0, 86400);
    s.lockTimeout = std::clamp(s.lockTimeout, 0, 86400);
    s.dpmsTimeout = std::clamp(s.dpmsTimeout, 0, 86400);
    s.suspendTimeout = std::clamp(s.suspendTimeout, 0, 86400);

    s.autostartApps = find_json_string_array(content, "autostartApps");

    // autostartCustom was declared, iterated by the session and never read, so
    // every program added on the Startup page was saved and then not started.
    // The page writes objects rather than strings, which the substring helpers
    // above cannot walk, hence a real parse for this one key.
    try {
        const auto doc = nlohmann::json::parse(content);
        const auto it = doc.find("autostartCustom");
        if (it != doc.end() && it->is_array()) {
            for (const auto& entry : *it) {
                std::string cmd;
                if (entry.is_string()) {
                    cmd = entry.get<std::string>();
                } else if (entry.is_object()) {
                    if (!entry.value("enabled", true)) continue;
                    cmd = entry.value("command", "");
                }
                // An entry picked from the app list carries its desktop file's
                // Exec line, field codes and all: `firefox %u` would open a
                // tab for the literal URL "%u".
                std::istringstream words(cmd);
                std::string word, clean;
                while (words >> word) {
                    if (word.size() == 2 && word[0] == '%') continue;
                    clean += (clean.empty() ? "" : " ") + word;
                }
                if (!clean.empty()) s.autostartCustom.push_back(clean);
            }
        }
    } catch (const std::exception&) {
        // A half-written file: autostart nothing rather than something wrong.
    }

    return s;
}

bool SettingsManager::save(const DesktopSettings& s, const std::string& path_arg) {
    std::string path = path_arg.empty() ? get_settings_filepath() : path_arg;

    size_t last_slash = path.rfind('/');
    if (last_slash != std::string::npos) {
        std::string dir = path.substr(0, last_slash);
        mkdir(dir.c_str(), 0755);
    }

    std::ofstream out(path);
    if (!out) return false;

    out << "{\n"
        << "  \"language\": " << json_quote(s.language) << ",\n"
        << "  \"kbOptions\": " << json_quote(s.kbOptions) << ",\n"
        << "  \"gapsInner\": " << s.gapsInner << ",\n"
        << "  \"gapsOuter\": " << s.gapsOuter << ",\n"
        << "  \"borderWidth\": " << s.borderWidth << ",\n"
        << "  \"smartBorders\": " << (s.smartBorders ? "true" : "false") << ",\n"
        << "  \"smartGaps\": " << (s.smartGaps ? "true" : "false") << ",\n"
        << "  \"workspaceCount\": " << s.workspaceCount << ",\n"
        << "  \"guideShortcut\": " << (s.guideShortcut ? "true" : "false") << ",\n"
        << "  \"topbarHelpIcon\": " << (s.topbarHelpIcon ? "true" : "false") << ",\n"
        << "  \"barPosition\": " << json_quote(s.barPosition) << ",\n"
        << "  \"barShowWeather\": " << (s.barShowWeather ? "true" : "false") << ",\n"
        << "  \"barShowMedia\": " << (s.barShowMedia ? "true" : "false") << ",\n"
        << "  \"barShowTray\": " << (s.barShowTray ? "true" : "false") << ",\n"
        << "  \"barClock24h\": " << (s.barClock24h ? "true" : "false") << ",\n"
        << "  \"dimTimeout\": " << s.dimTimeout << ",\n"
        << "  \"lockTimeout\": " << s.lockTimeout << ",\n"
        << "  \"dpmsTimeout\": " << s.dpmsTimeout << ",\n"
        << "  \"suspendTimeout\": " << s.suspendTimeout << ",\n"
        << "  \"autostartApps\": [";

    for (size_t i = 0; i < s.autostartApps.size(); ++i) {
        out << json_quote(s.autostartApps[i]) << (i + 1 < s.autostartApps.size() ? ", " : "");
    }

    out << "]\n}\n";
    out.close();
    return true;
}

// ── Apply Settings directly to Sway IPC & configs ─────────────────────────────
// Keyboard layouts and the switch shortcut.
//
// This used to rewrite the xkb lines inside conf.d/input.conf and do nothing
// else. Two things followed from that. Nothing told the running sway, so a
// layout added on the Keyboard page did not exist until the next login — and
// removing one was broken on the page besides, so the list only ever grew
// (us,ua,de,ru on the machine this was found on, with sway still running
// us,ua). And input.conf is a shipped file: install.sh copies it over the top,
// so the next install quietly put the layouts back.
//
// Now the choice lives in custom_keyboard.conf, which the sway config includes
// after input.conf, and is sent to the running compositor as well. Only when
// it changes: setting xkb_layout rebuilds the keymap and drops the active
// layout back to the first, and this runs on every write to settings.json —
// moving a volume slider would otherwise have switched you out of Ukrainian.
static void apply_keyboard(SwayIPC* ipc, const std::string& layout, const std::string& options) {
    static std::mutex m;
    static std::string applied_layout, applied_options;

    if (!valid_sway_token(layout, 128)) return;
    // Empty options are legitimate (no switch shortcut at all); anything else
    // must be a plain xkb token list.
    if (!options.empty() && !valid_sway_token(options, 256)) return;

    std::lock_guard<std::mutex> lock(m);
    if (layout == applied_layout && options == applied_options) return;

    const char* home = std::getenv("HOME");
    const std::string path = std::string(home ? home : "") + "/.config/sway/conf.d/custom_keyboard.conf";
    const std::string tmp = path + ".tmp";
    {
        std::ofstream out(tmp);
        if (!out) return;
        out << "# Generated by b1air Settings -> Keyboard. Rewritten whenever the layouts\n"
            << "# or the switch shortcut change there, so hand edits do not survive.\n"
            << "# Included after conf.d/input.conf, which holds the shipped defaults.\n\n"
            << "input type:keyboard {\n"
            << "    xkb_layout \"" << layout << "\"\n"
            << "    xkb_options \"" << options << "\"\n"
            << "}\n";
        if (!out.good()) return;
    }
    if (std::rename(tmp.c_str(), path.c_str()) != 0) return;

    // With no compositor to tell, the file is still right for the next login,
    // but this is not "applied" — the first call that can reach sway should.
    if (!ipc) return;
    // Quoted: sway splits a command line on commas, so an unquoted
    // "xkb_layout us,de" applied "us" and then failed on a command named "de".
    ipc->send_command(0, "input type:keyboard xkb_layout \"" + layout + "\"");
    ipc->send_command(0, "input type:keyboard xkb_options \"" + options + "\"");
    applied_layout = layout;
    applied_options = options;
}

static bool command_ok(const std::string& reply) {
    const auto j = nlohmann::json::parse(reply, nullptr, false);
    return j.is_array() && !j.empty() && j[0].is_object() && j[0].value("success", false);
}

bool SettingsManager::apply_compositor_extras(SwayIPC& ipc) {
    // Settings → Animations. Each of these is our swayfx's own (or swayfx
    // 0.6+'s, for the duration); any other sway refuses them harmlessly.
    const auto pick = [](const std::string& v, std::initializer_list<const char*> allowed, const char* def) {
        for (const char* a : allowed) if (v == a) return std::string(a);
        return std::string(def);
    };

    // Unfocused windows drawn at this much opacity; 100% is off.
    const int inactive = std::clamp(get_json_int("inactiveOpacityPercent", 50), 10, 100);
    (void)ipc.send_command(0, "inactive_opacity " + std::to_string(inactive / 100.0).substr(0, 4));

    // 0 turns every animation off: windows and workspaces alike.
    const int duration = std::clamp(get_json_int("animationDuration", 200), 0, 1000);
    (void)ipc.send_command(0, "animation_duration_ms " + std::to_string(duration));

    // Workspaces slide sideways (or fade), and a three-finger swipe moves
    // them with the fingers (src/swayfx/patches/0003, 0004). "Natural" in
    // Settings is the workspace following the fingers, which is the patch's
    // own default; off, it turns round. Where this is taken, the
    // three-finger bindgestures in input.conf are never reached for
    // sideways swipes; on any other sway they still switch workspaces at the
    // end of the swipe.
    (void)ipc.send_command(0, "workspace_animation "
        + pick(get_json_string("workspaceAnimation"), {"slide", "fade"}, "slide"));
    (void)ipc.send_command(0, !get_json_bool("touchpadSwipeWorkspace", true)
        ? std::string("workspace_swipe off")
        : std::string("workspace_swipe 3") + (get_json_bool("touchpadNaturalSwipe", true) ? "" : " invert"));

    // How windows open and close (patch 0006); popin grows from a share of
    // the final size.
    const std::string window = pick(get_json_string("windowAnimation"), {"popin", "fade", "slide", "none"}, "popin");
    (void)ipc.send_command(0, "window_animation " + window + (window == "popin"
        ? " " + std::to_string(std::clamp(get_json_int("popinPercent", 80), 10, 100)) : std::string()));

    // Mod+S calls up the special workspace, as under Hyprland, where the
    // compositor has it (src/swayfx/patches/0005) and Settings has not
    // turned it off; keybinds.conf keeps it on the scratchpad, and that is
    // put back when it is off. Asked without an argument, to learn whether
    // the command exists without showing or hiding anything: a sway that
    // knows it wants an argument, one that does not names it unknown.
    const bool has_special =
        ipc.send_command(0, "special_workspace").find("Unknown/invalid command") == std::string::npos;
    if (has_special && get_json_bool("specialWorkspace", true)) {
        (void)ipc.send_command(0, "bindsym --to-code $mod+s special_workspace toggle");
        (void)ipc.send_command(0, "bindsym --to-code $mod+ctrl+shift+s move container to workspace special");
    } else if (has_special) {
        (void)ipc.send_command(0, "special_workspace hide");
        (void)ipc.send_command(0, "bindsym --to-code $mod+s scratchpad show");
        (void)ipc.send_command(0, "bindsym --to-code $mod+ctrl+shift+s move scratchpad");
    }

    // Mod+O lays every workspace of the screen out side by side (patch
    // 0007); a click or Enter goes to one, Escape leaves. Asked the same way.
    const bool has_overview =
        ipc.send_command(0, "overview").find("Unknown/invalid command") == std::string::npos;
    // Four fingers up bring it in with the fingers (overview_swipe), when
    // the four-finger gestures are on in Mouse & Touchpad.
    if (has_overview && get_json_bool("workspaceOverview", true)) {
        (void)ipc.send_command(0, "bindsym --to-code $mod+o overview toggle");
        (void)ipc.send_command(0, get_json_bool("touchpadFourFinger", true)
            ? "overview_swipe 4" : "overview_swipe off");
    } else if (has_overview) {
        (void)ipc.send_command(0, "overview hide");
        (void)ipc.send_command(0, "overview_swipe off");
        (void)ipc.send_command(0, "unbindsym --to-code $mod+o");
    }
    return command_ok(ipc.send_command(0, std::string("autotile ")
        + (get_json_bool("autotiling", true) ? "enable" : "disable")));
}

bool SettingsManager::apply_to_sway(const DesktopSettings& s) {
    SwayIPC ipc;
    const bool connected = ipc.connect();
    if (connected) {
        apply_compositor_extras(ipc);
        ipc.send_command(0, "gaps inner all set " + std::to_string(s.gapsInner));
        ipc.send_command(0, "gaps outer all set " + std::to_string(s.gapsOuter));
        // `gaps outer` sets all four edges, and look-and-feel.conf keeps the
        // top one at zero (see there for why). Without this, every write to
        // settings.json — any toggle on any page — opened a band under the bar.
        ipc.send_command(0, "gaps top all set 0");
        ipc.send_command(0, "default_border pixel " + std::to_string(s.borderWidth));
        ipc.send_command(0, std::string("smart_borders ") + (s.smartBorders ? "on" : "off"));
        ipc.send_command(0, std::string("smart_gaps ") + (s.smartGaps ? "on" : "off"));

        for (const auto& [mon, ws] : s.monitorWorkspaces) {
            ipc.send_command(0, "workspace " + ws + " output " + mon);
        }
        apply_primary_output(ipc, s, false);
    }

    apply_keyboard(connected ? &ipc : nullptr, s.language, s.kbOptions);

    // The native Quickshell bar observes settings through the shell reload;
    // there is no legacy Waybar process to signal.
    return true;
}

void SettingsManager::apply_primary_output(SwayIPC& ipc, const DesktopSettings& s, bool focus) {
    const std::string primary = get_json_string("barPrimaryOutput");
    if (primary.empty()) return;

    // Only a display that is connected and on; a docked laptop's remembered
    // monitor may be away.
    const auto outputs = nlohmann::json::parse(ipc.send_command(3), nullptr, false);   // GET_OUTPUTS
    bool present = false;
    if (outputs.is_array())
        for (const auto& o : outputs)
            if (o.value("name", "") == primary && o.value("active", false)) present = true;
    if (!present) return;

    std::string quoted = "\"";
    for (char c : primary) { if (c == '"' || c == '\\') quoted += '\\'; quoted += c; }
    quoted += '"';

    // Workspace 1 is the main display's, unless it was given to another one.
    bool mapped = false;
    for (const auto& [mon, ws] : s.monitorWorkspaces)
        if (ws == "1") mapped = true;
    if (!mapped) {
        (void)ipc.send_command(0, "workspace 1 output " + quoted);
        // The assignment only governs where it is created next; one that
        // already exists elsewhere is moved, without leaving the focus there.
        const auto wss = nlohmann::json::parse(ipc.send_command(1), nullptr, false);   // GET_WORKSPACES
        std::string focused_ws, ws1_output;
        if (wss.is_array())
            for (const auto& w : wss) {
                if (w.value("focused", false)) focused_ws = w.value("name", "");
                if (w.value("name", "") == "1") ws1_output = w.value("output", "");
            }
        if (!ws1_output.empty() && ws1_output != primary) {
            // sway moves only the focused workspace: go to 1, move it, and
            // (but at login) go back to where the focus was.
            (void)ipc.send_command(0, "workspace number 1; move workspace to output " + quoted);
            if (!focus && !focused_ws.empty() && focused_ws != "1")
                (void)ipc.send_command(0, "workspace \"" + focused_ws + "\"");
        }
    }
    if (focus)
        (void)ipc.send_command(0, "focus output " + quoted);
}

bool SettingsManager::apply_from_file(const std::string& path) {
    DesktopSettings s = load(path);
    return apply_to_sway(s);
}

std::string SettingsManager::get_json_string(const std::string& key) {
    std::string path = get_settings_filepath();
    std::string content = read_file_contents(path);
    return find_json_string(content, key, "");
}

bool SettingsManager::get_json_bool(const std::string& key, bool def) {
    return find_json_bool(read_file_contents(get_settings_filepath()), key, def);
}

int SettingsManager::get_json_int(const std::string& key, int def) {
    return find_json_int(read_file_contents(get_settings_filepath()), key, def);
}

bool SettingsManager::set_json_value(const std::string& key, const std::string& val) {
    if (key.empty() || key.size() > 128 || key.find('"') != std::string::npos) return false;
    const std::string quoted_val = json_quote(val);
    if (quoted_val.empty()) return false;
    std::string path = get_settings_filepath();
    std::string content = read_file_contents(path);
    if (content.empty()) content = "{}";

    std::string needle = "\"" + key + "\"";
    size_t pos = content.find(needle);
    if (pos != std::string::npos) {
        size_t colon = content.find(':', pos + needle.size());
        if (colon != std::string::npos) {
            size_t comma = content.find_first_of(",}", colon + 1);
            if (comma != std::string::npos) {
                std::string new_val = " " + quoted_val;
                content.replace(colon + 1, comma - (colon + 1), new_val);
            }
        }
    } else {
        // Insert before last closing brace
        size_t last_brace = content.rfind('}');
        if (last_brace != std::string::npos) {
            std::string entry = (last_brace > 1 && content[last_brace - 1] != '{' ? ",\n  \"" : "  \"") + key + "\": " + quoted_val + "\n";
            content.insert(last_brace, entry);
        }
    }

    std::ofstream ofs(path);
    if (ofs) {
        ofs << content;
        return true;
    }
    return false;
}

// ── Native inotify watcher ───────────────────────────────────────────────────
int SettingsManager::watch_and_apply(volatile int* running_flag) {
    std::string settings_file = get_settings_filepath();
    apply_from_file(settings_file);

#if defined(__linux__)
    size_t slash = settings_file.rfind('/');
    std::string dir_path = (slash != std::string::npos) ? settings_file.substr(0, slash) : ".";
    std::string file_name = (slash != std::string::npos) ? settings_file.substr(slash + 1) : settings_file;

    int fd = inotify_init1(IN_NONBLOCK | IN_CLOEXEC);
    if (fd < 0) {
        std::cerr << "[b1air-settings] inotify_init1 failed\n";
        return 1;
    }

    int wd = inotify_add_watch(fd, dir_path.c_str(), IN_CLOSE_WRITE | IN_MOVED_TO | IN_CREATE);
    if (wd < 0) {
        std::cerr << "[b1air-settings] Failed to watch directory: " << dir_path << "\n";
        close(fd);
        return 1;
    }

    std::cout << "[b1air-settings] Live inotify watcher started for " << settings_file << "\n";

    struct pollfd pfd;
    pfd.fd = fd;
    pfd.events = POLLIN;

    char buf[4096] __attribute__((aligned(__alignof__(struct inotify_event))));

    while (running_flag && *running_flag) {
        int ret = poll(&pfd, 1, 500); // 500ms timeout
        if (ret > 0 && (pfd.revents & POLLIN)) {
            ssize_t len = read(fd, buf, sizeof(buf));
            if (len > 0) {
                const struct inotify_event* event;
                for (char* ptr = buf; ptr < buf + len; ptr += sizeof(struct inotify_event) + event->len) {
                    event = (const struct inotify_event*)ptr;
                    if (event->len > 0 && std::string(event->name) == file_name) {
                        std::cout << "[b1air-settings] Detected change in " << file_name << ", applying settings instantly...\n";
                        apply_from_file(settings_file);
                    }
                }
            }
        }
    }

    inotify_rm_watch(fd, wd);
    close(fd);
#else
    while (running_flag && *running_flag) {
        std::this_thread::sleep_for(std::chrono::seconds(2));
    }
#endif
    return 0;
}


// ── Moving a configuration to another machine ────────────────────────────────

namespace {

/** Keys that describe this machine's hardware rather than a preference. */
const char* const kLocalOnly[] = {
    "monitors",              // a display layout, in physical positions
    "barPrimaryOutput",      // names an output
    "disabledAudioDevices",  // names sound cards
};

bool is_local_only(const std::string& key) {
    for (const char* k : kLocalOnly)
        if (key == k) return true;
    return false;
}

std::string home_dir() {
    const char* h = std::getenv("HOME");
    return h ? h : "/tmp";
}

/** Reads a JSON file, or a null value if it is missing or malformed. */
nlohmann::json read_json(const std::string& path) {
    std::ifstream in(path);
    if (!in) return nullptr;
    try {
        nlohmann::json j;
        in >> j;
        return j;
    } catch (const std::exception&) {
        return nullptr;
    }
}

bool write_json(const std::string& path, const nlohmann::json& j) {
    const size_t slash = path.find_last_of('/');
    if (slash != std::string::npos)
        std::filesystem::create_directories(path.substr(0, slash));
    std::ofstream out(path);
    if (!out) return false;
    out << j.dump(2) << "\n";
    return out.good();
}

} // namespace

bool SettingsManager::config_export(const std::string& path) {
    nlohmann::json bundle;
    bundle["format"] = "b1air-config";
    bundle["version"] = 1;

    nlohmann::json settings = read_json(get_settings_filepath());
    if (!settings.is_object()) {
        std::cerr << "[b1air-config] no settings file to export\n";
        return false;
    }

    // Dropped here as well as on import: an export is a document people read
    // and send to each other, and it should not contain another machine's
    // monitor arrangement even if nothing would apply it.
    nlohmann::json portable = nlohmann::json::object();
    nlohmann::json skipped = nlohmann::json::array();
    for (auto it = settings.begin(); it != settings.end(); ++it) {
        if (is_local_only(it.key())) {
            skipped.push_back(it.key());
            continue;
        }
        portable[it.key()] = it.value();
    }
    bundle["settings"] = portable;
    bundle["skipped"] = skipped;

    const std::string b1 = home_dir() + "/.config/b1air";
    for (const auto& [name, file] : std::initializer_list<std::pair<const char*, const char*>>{
             {"pinnedApps", "/pinned_apps.json"},
             {"fileBookmarks", "/files_bookmarks.json"},
             {"theme", "/theme.json"}}) {
        nlohmann::json v = read_json(b1 + file);
        if (!v.is_null()) bundle[name] = v;
    }

    // Themes are files people write by hand, so they travel whole.
    nlohmann::json themes = nlohmann::json::object();
    std::error_code ec;
    for (const auto& e : std::filesystem::directory_iterator(b1 + "/themes", ec)) {
        if (ec) break;
        if (e.path().extension() != ".json") continue;
        nlohmann::json t = read_json(e.path().string());
        if (t.is_object()) themes[e.path().stem().string()] = t;
    }
    if (!themes.empty()) bundle["themes"] = themes;

    if (!write_json(path, bundle)) {
        std::cerr << "[b1air-config] could not write " << path << "\n";
        return false;
    }
    std::cout << "Exported " << portable.size() << " settings";
    if (!skipped.empty()) std::cout << " (" << skipped.size() << " machine-specific left out)";
    std::cout << " to " << path << "\n";
    return true;
}

bool SettingsManager::config_import(const std::string& path) {
    nlohmann::json bundle = read_json(path);
    if (!bundle.is_object() || bundle.value("format", "") != "b1air-config") {
        std::cerr << "[b1air-config] " << path << " is not a b1air configuration export\n";
        return false;
    }

    nlohmann::json current = read_json(get_settings_filepath());
    if (!current.is_object()) current = nlohmann::json::object();

    int applied = 0, refused = 0;
    const nlohmann::json& incoming = bundle["settings"];
    if (incoming.is_object()) {
        for (auto it = incoming.begin(); it != incoming.end(); ++it) {
            // Refused on the way in too, so a hand-edited or older export
            // cannot put another machine's screens into this one's settings.
            if (is_local_only(it.key())) { ++refused; continue; }
            current[it.key()] = it.value();
            ++applied;
        }
    }
    if (!write_json(get_settings_filepath(), current)) {
        std::cerr << "[b1air-config] could not write the settings file\n";
        return false;
    }

    const std::string b1 = home_dir() + "/.config/b1air";
    if (bundle.contains("pinnedApps"))    write_json(b1 + "/pinned_apps.json", bundle["pinnedApps"]);
    if (bundle.contains("fileBookmarks")) write_json(b1 + "/files_bookmarks.json", bundle["fileBookmarks"]);
    if (bundle.contains("theme"))         write_json(b1 + "/theme.json", bundle["theme"]);
    if (bundle.contains("themes") && bundle["themes"].is_object())
        for (auto it = bundle["themes"].begin(); it != bundle["themes"].end(); ++it)
            write_json(b1 + "/themes/" + it.key() + ".json", it.value());

    std::cout << "Imported " << applied << " settings";
    if (refused) std::cout << " (" << refused << " machine-specific refused)";
    std::cout << ". Log out and back in, or run `b1air-shell reload`.\n";
    return true;
}

} // namespace b1air
