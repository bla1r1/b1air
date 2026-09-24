#include "wallpaper_config.hpp"

#include <nlohmann/json.hpp>

#include <algorithm>
#include <cstdlib>
#include <fstream>
#include <sstream>
#include <unistd.h>

namespace {

std::string home() {
    const char* h = std::getenv("HOME");
    return h && *h ? h : "/tmp";
}

nlohmann::json read_json(const std::string& path) {
    std::ifstream f(path);
    if (!f) return nlohmann::json::object();
    std::stringstream ss;
    ss << f.rdbuf();
    auto j = nlohmann::json::parse(ss.str(), nullptr, false);
    return j.is_object() ? j : nlohmann::json::object();
}

void read_map(const nlohmann::json& from, std::map<std::string, std::string>& into) {
    if (!from.is_object()) return;
    for (const auto& [key, value] : from.items())
        if (value.is_string() && !value.get<std::string>().empty())
            into[key] = value.get<std::string>();
}

bool parse_hex(const std::string& s, uint32_t& out) {
    if (s.size() != 7 && s.size() != 9) return false;
    if (s[0] != '#') return false;
    char* end = nullptr;
    const unsigned long v = std::strtoul(s.c_str() + 1, &end, 16);
    if (*end) return false;
    out = static_cast<uint32_t>(s.size() == 9 ? (v & 0xffffff) : v);   // #AARRGGBB drops alpha
    return true;
}

} // namespace

std::string WallpaperConfig::config_dir() { return home() + "/.config/b1air"; }
std::string WallpaperConfig::cache_dir() { return home() + "/.cache"; }
std::string WallpaperConfig::copies_dir() { return home() + "/.cache/b1air/wallpapers"; }

WallpaperConfig WallpaperConfig::load() {
    WallpaperConfig c;
    c.global = cache_dir() + "/current_wallpaper.jpg";

    const auto map = read_json(config_dir() + "/wallpapers.json");
    if (map.contains("outputs") || map.contains("workspaces")) {
        if (map.contains("outputs")) read_map(map["outputs"], c.outputs);
        if (map.contains("workspaces")) read_map(map["workspaces"], c.workspaces);
        if (map.contains("transitionMs") && map["transitionMs"].is_number_integer())
            c.transition_ms = std::clamp(map["transitionMs"].get<int>(), 0, 5000);
    } else {
        read_map(map, c.outputs);
    }

    const auto theme = read_json(config_dir() + "/theme.json");
    for (const char* key : {"ground", "crust"})
        if (theme.contains(key) && theme[key].is_string() && parse_hex(theme[key].get<std::string>(), c.ground))
            break;
    return c;
}

std::string WallpaperConfig::pick(const std::string& output_identity, const std::string& workspace) const {
    const auto readable = [](const std::string& p) { return !p.empty() && access(p.c_str(), R_OK) == 0; };
    if (const auto it = workspaces.find(workspace); it != workspaces.end() && readable(it->second)) return it->second;
    if (const auto it = outputs.find(output_identity); it != outputs.end() && readable(it->second)) return it->second;
    return readable(global) ? global : std::string();
}
