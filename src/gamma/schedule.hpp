#pragma once
// When the night light is warm, and how warm: the settings file, the
// schedule, and the sun. Nothing here talks to Wayland, so `b1air-gamma
// --print` can show what the running one would do, and the tests can ask.

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <ctime>
#include <fstream>
#include <optional>
#include <sstream>
#include <string>
#include <unistd.h>

namespace gamma_schedule {

constexpr int kMin = 1000, kMax = 6500;
// How long the change at either end of the night takes.
constexpr int kTransitionMinutes = 30;

enum class Mode { Always, Hours, Sun };

struct Config {
    int temp = 4000;            // the warm end
    Mode mode = Mode::Always;
    int from = 20 * 60;         // minutes after midnight, local time
    int to = 7 * 60;
    std::optional<double> lat, lon;   // unset: from the time zone
};

inline int clamp_kelvin(long k) { return static_cast<int>(std::clamp<long>(k, kMin, kMax)); }

// "HH:MM" → minutes after midnight, or -1.
inline int parse_hhmm(const std::string& s) {
    int h = -1, m = -1;
    char extra = 0;
    if (std::sscanf(s.c_str(), "%d:%d%c", &h, &m, &extra) != 2) return -1;
    if (h < 0 || h > 23 || m < 0 || m > 59) return -1;
    return h * 60 + m;
}

inline std::string hhmm(int minutes) {
    minutes = ((minutes % 1440) + 1440) % 1440;
    char buf[8];
    std::snprintf(buf, sizeof(buf), "%02d:%02d", minutes / 60, minutes % 60);
    return buf;
}

inline std::optional<double> parse_number(const std::string& s) {
    char* end = nullptr;
    const double v = std::strtod(s.c_str(), &end);
    if (!end || end == s.c_str() || *end != '\0' || !std::isfinite(v)) return std::nullopt;
    return v;
}

// key=value lines (temp, mode, from, to, lat, lon). A file holding only a
// number is a fixed temperature, which is what the first version wrote.
inline Config parse(const std::string& text) {
    Config c;
    std::istringstream in(text);
    std::string line;
    while (std::getline(in, line)) {
        while (!line.empty() && (line.back() == '\r' || line.back() == ' ')) line.pop_back();
        const auto eq = line.find('=');
        if (eq == std::string::npos) {
            if (auto k = parse_number(line)) c.temp = clamp_kelvin(std::lround(*k));
            continue;
        }
        const std::string key = line.substr(0, eq), value = line.substr(eq + 1);
        if (key == "temp") {
            if (auto k = parse_number(value)) c.temp = clamp_kelvin(std::lround(*k));
        } else if (key == "mode") {
            c.mode = value == "hours" ? Mode::Hours : value == "sun" ? Mode::Sun : Mode::Always;
        } else if (key == "from") {
            if (int m = parse_hhmm(value); m >= 0) c.from = m;
        } else if (key == "to") {
            if (int m = parse_hhmm(value); m >= 0) c.to = m;
        } else if (key == "lat") {
            if (auto v = parse_number(value); v && std::fabs(*v) <= 90) c.lat = v;
        } else if (key == "lon") {
            if (auto v = parse_number(value); v && std::fabs(*v) <= 180) c.lon = v;
        }
    }
    return c;
}

// ── Where the sun is ─────────────────────────────────────────────────────────

// The time zone's name: $TZ, or what /etc/localtime points into.
inline std::string zone_name() {
    if (const char* tz = std::getenv("TZ"); tz && *tz) return tz[0] == ':' ? tz + 1 : tz;
    char buf[512] = {0};
    const ssize_t n = readlink("/etc/localtime", buf, sizeof(buf) - 1);
    if (n <= 0) return {};
    const std::string target(buf, static_cast<size_t>(n));
    const auto at = target.find("zoneinfo/");
    return at == std::string::npos ? std::string() : target.substr(at + 9);
}

// ±DDMM or ±DDDMMSS, as zone1970.tab writes coordinates.
inline double tab_coordinate(const std::string& s, int degree_digits) {
    if (s.size() < static_cast<size_t>(1 + degree_digits + 2)) return 0;
    const double sign = s[0] == '-' ? -1 : 1;
    const double deg = std::atof(s.substr(1, degree_digits).c_str());
    const double min = std::atof(s.substr(1 + degree_digits, 2).c_str());
    const double sec = s.size() >= static_cast<size_t>(1 + degree_digits + 4)
                     ? std::atof(s.substr(1 + degree_digits + 2, 2).c_str()) : 0;
    return sign * (deg + min / 60 + sec / 3600);
}

// The time zone's principal city, from tzdata's own table: close enough to
// put sunset within minutes for most of a zone, with nothing to ask and no
// network. A location in the settings overrides it.
inline bool zone_location(double& lat, double& lon, std::string* name = nullptr) {
    const std::string zone = zone_name();
    if (zone.empty()) return false;
    for (const char* tab : {"/usr/share/zoneinfo/zone1970.tab", "/usr/share/zoneinfo/zone.tab"}) {
        std::ifstream f(tab);
        std::string line;
        while (std::getline(f, line)) {
            if (line.empty() || line[0] == '#') continue;
            std::istringstream fields(line);
            std::string codes, coords, tz;
            if (!(fields >> codes >> coords >> tz) || tz != zone) continue;
            // The longitude starts at the second sign.
            const auto split = coords.find_first_of("+-", 1);
            if (split == std::string::npos) continue;
            const std::string la = coords.substr(0, split), lo = coords.substr(split);
            lat = tab_coordinate(la, 2);
            lon = tab_coordinate(lo, 3);
            if (name) *name = zone;
            return true;
        }
    }
    return false;
}

enum class Sun { Normal, AlwaysUp, AlwaysDown };

// Sunrise and sunset, local minutes after midnight, on the day `when` falls
// in. The almanac algorithm (US Naval Observatory, 1990) with the usual
// 90°50′ zenith: within a minute or two of the published tables, which is
// more than a night light needs.
inline Sun sun_times(std::time_t when, double lat, double lon, int& rise, int& set) {
    std::tm local{};
    localtime_r(&when, &local);
    const double day = local.tm_yday + 1;
    const double lng_hour = lon / 15.0;
    const double zenith = 90.833 * M_PI / 180.0;
    const double rad = M_PI / 180.0;

    auto compute = [&](bool rising, double& local_hours) -> Sun {
        const double t = day + ((rising ? 6.0 : 18.0) - lng_hour) / 24.0;
        const double m = 0.9856 * t - 3.289;
        double l = m + 1.916 * std::sin(m * rad) + 0.020 * std::sin(2 * m * rad) + 282.634;
        l = std::fmod(l + 360.0, 360.0);
        double ra = std::atan(0.91764 * std::tan(l * rad)) / rad;
        ra = std::fmod(ra + 360.0, 360.0);
        ra += std::floor(l / 90.0) * 90.0 - std::floor(ra / 90.0) * 90.0;
        ra /= 15.0;
        const double sin_dec = 0.39782 * std::sin(l * rad);
        const double cos_dec = std::cos(std::asin(sin_dec));
        const double cos_h = (std::cos(zenith) - sin_dec * std::sin(lat * rad)) / (cos_dec * std::cos(lat * rad));
        if (cos_h > 1) return Sun::AlwaysDown;
        if (cos_h < -1) return Sun::AlwaysUp;
        double h = rising ? 360.0 - std::acos(cos_h) / rad : std::acos(cos_h) / rad;
        h /= 15.0;
        const double big_t = h + ra - 0.06571 * t - 6.622;
        const double ut = std::fmod(big_t - lng_hour + 48.0, 24.0);
        local_hours = ut + static_cast<double>(local.tm_gmtoff) / 3600.0;
        return Sun::Normal;
    };
    double r = 0, s = 0;
    const Sun a = compute(true, r);
    const Sun b = compute(false, s);
    if (a != Sun::Normal) return a;
    if (b != Sun::Normal) return b;
    rise = static_cast<int>(std::lround(r * 60)) % 1440;
    set = static_cast<int>(std::lround(s * 60)) % 1440;
    rise = (rise + 1440) % 1440;
    set = (set + 1440) % 1440;
    return Sun::Normal;
}

// ── How warm, now ────────────────────────────────────────────────────────────

// 0 by day, 1 at night: warming over the half hour after `from`, cooling
// over the half hour after `to`. Midnight in between is fine.
inline double night_fraction(int now, int from, int to) {
    const int night_len = ((to - from) % 1440 + 1440) % 1440;
    if (night_len == 0) return 0;
    const int since_from = ((now - from) % 1440 + 1440) % 1440;
    if (since_from < night_len)
        return std::min(1.0, since_from / static_cast<double>(kTransitionMinutes));
    const int since_to = ((now - to) % 1440 + 1440) % 1440;
    return std::max(0.0, 1.0 - since_to / static_cast<double>(kTransitionMinutes));
}

struct Window {
    bool known = false;   // false: no location for Mode::Sun
    Sun sun = Sun::Normal;
    int from = 0, to = 0;
};

inline Window night_window(const Config& c, std::time_t when) {
    Window w;
    if (c.mode == Mode::Hours) {
        w.known = true;
        w.from = c.from;
        w.to = c.to;
    } else if (c.mode == Mode::Sun) {
        double lat = 0, lon = 0;
        if (c.lat && c.lon) { lat = *c.lat; lon = *c.lon; w.known = true; }
        else w.known = zone_location(lat, lon);
        if (w.known) {
            int rise = 0, set = 0;
            w.sun = sun_times(when, lat, lon, rise, set);
            w.from = set;
            w.to = rise;
        }
    }
    return w;
}

inline double target_kelvin(const Config& c, std::time_t when) {
    if (c.mode == Mode::Always) return c.temp;
    const Window w = night_window(c, when);
    double night = 1;   // a sun schedule with nowhere to put the sun: warm
    if (w.known) {
        if (w.sun == Sun::AlwaysUp) night = 0;
        else if (w.sun == Sun::AlwaysDown) night = 1;
        else {
            std::tm local{};
            localtime_r(&when, &local);
            night = night_fraction(local.tm_hour * 60 + local.tm_min, w.from, w.to);
        }
    }
    return kMax + (c.temp - kMax) * night;
}

} // namespace gamma_schedule
