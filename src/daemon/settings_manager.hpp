#pragma once
#include <string>
#include <vector>
#include <map>

namespace b1air {

struct DesktopSettings {
    // Keyboard & input
    std::string language = "us";
    std::string kbOptions = "grp:alt_shift_toggle,caps:escape";

    // Windows & Compositor
    int gapsInner = 8;
    int gapsOuter = 4;
    int borderWidth = 2;
    bool smartBorders = true;
    bool smartGaps = false;

    // Top bar
    int workspaceCount = 8;
    bool guideShortcut = true;
    bool topbarHelpIcon = false;
    std::string barPosition = "top";
    bool barShowWeather = true;
    bool barShowMedia = true;
    bool barShowTray = true;
    bool barClock24h = true;

    // Idle & Power
    //
    // These four must match the defaults in shell/qml/Services/Settings.qml.
    // They did not: the daemon fell back to 300/600/900/1200 while the Power
    // page displayed 240/300/600/1800, so on a machine with no value in
    // settings.json the page stated one number and swayidle was built with
    // another. Found by a third schema — an offline settings editor — 
    // disagreeing with both.
    int dimTimeout = 240;
    int lockTimeout = 300;
    int dpmsTimeout = 600;
    int suspendTimeout = 1800;

    // Autostart
    std::vector<std::string> autostartApps;
    std::vector<std::string> autostartCustom;

    // Monitors
    std::map<std::string, std::string> monitorWorkspaces;
};

class SettingsManager {
public:
    static std::string get_settings_filepath();
    static DesktopSettings load(const std::string& path = "");
    static bool save(const DesktopSettings& s, const std::string& path = "");

    static bool apply_to_sway(const DesktopSettings& s);
    static bool apply_from_file(const std::string& path = "");

    static std::string get_json_string(const std::string& key);

    // The struct above covers what apply_to_sway needs. These read anything
    // else in the file by name, for the settings only one caller cares about.
    static bool get_json_bool(const std::string& key, bool def);
    static int  get_json_int(const std::string& key, int def);
    static bool set_json_value(const std::string& key, const std::string& val);

    static int watch_and_apply(volatile int* running_flag);

    // ── Moving a configuration to another machine ────────────────────────────
    //
    // One JSON document holding the settings file and the small stores beside
    // it — themes, pinned apps, file-manager bookmarks — so a new machine can
    // be brought up to the same desktop by copying a single file.
    //
    // Three keys never travel, whether or not an older export contains them:
    // `monitors` is a display layout in physical positions, `barPrimaryOutput`
    // names an output, and `disabledAudioDevices` names sound cards. Carrying
    // those to another machine does not restore a preference, it describes
    // hardware that is not there — the bar would look for a screen by a name
    // nothing answers to.
    //
    // The weather API key is not in the settings file at all; it lives in the
    // secret store, and a credential does not belong in a document meant to be
    // copied around. It is entered again on the new machine.
    static bool config_export(const std::string& path);
    static bool config_import(const std::string& path);
};

} // namespace b1air
