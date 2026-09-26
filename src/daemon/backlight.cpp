#include "backlight.hpp"

#include <systemd/sd-bus.h>

#include <algorithm>
#include <cmath>
#include <dirent.h>
#include <fstream>
#include <string>
#include <vector>

namespace b1air::backlight {

namespace {

std::string read_line(const std::string& path) {
    std::ifstream f(path);
    std::string s;
    std::getline(f, s);
    return s;
}

long read_long(const std::string& path) {
    try { return std::stol(read_line(path)); } catch (...) { return -1; }
}

std::vector<std::string> entries(const std::string& dir) {
    std::vector<std::string> out;
    if (DIR* d = opendir(dir.c_str())) {
        while (struct dirent* e = readdir(d))
            if (e->d_name[0] != '.') out.emplace_back(e->d_name);
        closedir(d);
    }
    std::sort(out.begin(), out.end());
    return out;
}

Device make(const std::string& subsystem, const std::string& name) {
    Device d;
    d.subsystem = subsystem;
    d.name = name;
    d.max = read_long("/sys/class/" + subsystem + "/" + name + "/max_brightness");
    return d;
}

std::string path(const Device& d, const char* file) {
    return "/sys/class/" + d.subsystem + "/" + d.name + "/" + file;
}

// The exponent brightnessctl's -e4 applied: perceived = linear^(1/4).
constexpr double kCurve = 4.0;

} // namespace

Device screen() {
    // The firmware interface knows the panel best; a raw one is the GPU
    // driver's own and is often the wrong scale on laptops that have both.
    for (const char* kind : {"firmware", "platform", "raw"})
        for (const auto& name : entries("/sys/class/backlight"))
            if (read_line("/sys/class/backlight/" + name + "/type") == kind)
                if (Device d = make("backlight", name)) return d;
    for (const auto& name : entries("/sys/class/backlight"))
        if (Device d = make("backlight", name)) return d;
    return {};
}

Device keyboard() {
    for (const auto& name : entries("/sys/class/leds"))
        if (name.find("kbd_backlight") != std::string::npos)
            if (Device d = make("leds", name)) return d;
    return {};
}

long raw(const Device& d) {
    return d ? read_long(path(d, "brightness")) : -1;
}

bool set_raw(const Device& d, long value) {
    if (!d) return false;
    value = std::clamp<long>(value, 0, d.max);

    sd_bus* bus = nullptr;
    bool ok = false;
    if (sd_bus_open_system(&bus) >= 0) {
        ok = sd_bus_call_method(bus, "org.freedesktop.login1", "/org/freedesktop/login1/session/auto",
                                "org.freedesktop.login1.Session", "SetBrightness", nullptr, nullptr,
                                "ssu", d.subsystem.c_str(), d.name.c_str(),
                                static_cast<uint32_t>(value)) >= 0;
        sd_bus_flush_close_unref(bus);
    }
    if (!ok) {
        std::ofstream f(path(d, "brightness"));
        ok = static_cast<bool>(f << value << "\n");
    }
    return ok;
}

int percent(const Device& d) {
    const long r = raw(d);
    if (!d || r < 0) return -1;
    return static_cast<int>(std::lround(100.0 * r / d.max));
}

bool set_percent(const Device& d, int pct) {
    if (!d) return false;
    return set_raw(d, std::lround(d.max * std::clamp(pct, 0, 100) / 100.0));
}

bool step(const Device& d, int delta_pct, long floor) {
    const long r = raw(d);
    if (!d || r < 0) return false;
    const double perceived = std::pow(static_cast<double>(r) / d.max, 1.0 / kCurve) * 100.0;
    const double next = std::clamp(perceived + delta_pct, 0.0, 100.0);
    long value = std::lround(d.max * std::pow(next / 100.0, kCurve));
    // A step that rounds to no change at the dark end still moves by one.
    if (value == r && delta_pct != 0) value += delta_pct > 0 ? 1 : -1;
    return set_raw(d, std::max(floor, value));
}

} // namespace b1air::backlight
