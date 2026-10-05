#pragma once

#include <cstdint>
#include <map>
#include <string>

// Which picture goes where, as the daemon writes it.
//
//   ~/.cache/current_wallpaper.jpg       every screen, unless told otherwise
//   ~/.config/b1air/wallpapers.json      the exceptions:
//     { "outputs":    { "<make model serial>": "<path>" },
//       "workspaces": { "<workspace name>":    "<path>" },
//       "transitionMs": 400 }
//
// A workspace's own picture wins over its screen's, which wins over the
// shared one. The file's first shape was the "outputs" map alone at the top
// level; that still reads.
struct WallpaperConfig {
    std::string global;
    std::map<std::string, std::string> outputs;
    std::map<std::string, std::string> workspaces;
    int transition_ms = 400;
    uint32_t ground = 0x202326;   // the theme's backdrop, where there is no picture

    static WallpaperConfig load();

    // The picture for a screen showing a workspace; empty for none.
    std::string pick(const std::string& output_identity, const std::string& workspace) const;

    static std::string config_dir();      // ~/.config/b1air
    static std::string cache_dir();       // ~/.cache
    static std::string copies_dir();      // ~/.cache/b1air/wallpapers
};
