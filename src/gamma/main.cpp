// b1air-gamma — night light: every screen at a colour temperature, held
// all the time or by a schedule.
//
//   b1air-gamma                 settings from $XDG_RUNTIME_DIR/b1air/gamma
//   b1air-gamma <kelvin>        a fixed temperature, 1000..6500
//   b1air-gamma --config FILE   settings from FILE
//   b1air-gamma --print [--config FILE] [--at UNIX-TIME]
//                               what it would do, without a screen: the
//                               temperature, the night's hours, the colour
//
// Any of the settings below can also be given as --temp, --mode, --from,
// --to, --lat, --lon; they override the file's until the next SIGUSR1.
//
// The settings file, key=value lines (see schedule.hpp):
//
//   temp=3400     the warm end
//   mode=always   always warm | hours: from..to | sun: sunset..sunrise
//   from=20:00    for mode=hours
//   to=07:00
//   lat=50.45     for mode=sun; without them, the time zone's city
//   lon=30.52
//
// Changed settings take effect on SIGUSR1, without a restart: the screens
// fade to the new value. The schedule is looked at once a minute, on a timer
// that counts suspend, so a machine opened in the morning is not left amber.
// SIGTERM or SIGINT: it exits, and the compositor puts the screens back.
// When every screen refuses gamma control it says so and exits (status 3).
//
// wlr-gamma-control, the protocol wlsunset and gammastep use. This was
// wlsunset, which has no fixed-temperature mode: it was started with a
// one-kelvin gap between its night and day values so both ends came out at
// the chosen one, and restarted on every step of the Settings slider — a
// flash back to full white each time.

#include <algorithm>
#include <cerrno>
#include <cmath>
#include <csignal>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fcntl.h>
#include <poll.h>
#include <string>
#include <sys/mman.h>
#include <sys/signalfd.h>
#include <sys/timerfd.h>
#include <time.h>
#include <unistd.h>
#include <vector>
#include <wayland-client.h>

#include "schedule.hpp"
#include "wlr-gamma-control-unstable-v1-client-protocol.h"

namespace {

using gamma_schedule::kMin;
using gamma_schedule::kMax;
constexpr double kFadeMs = 600;

struct Screen {
    uint32_t name = 0;                       // registry name, for removal
    struct wl_output* output = nullptr;
    struct zwlr_gamma_control_v1* control = nullptr;
    uint32_t size = 0;                       // ramp length; 0 until told
    bool failed = false;
};

struct zwlr_gamma_control_manager_v1* g_manager = nullptr;
std::vector<Screen*> g_screens;

// The temperature's colour as red, green and blue multipliers, 1.0 at
// 6500 K. Tanner Helland's fit to the black-body colours, normalised so
// that 6500 K is exactly white rather than a hair off it.
void white_point(double kelvin, double rgb[3]) {
    auto raw = [](double k, double out[3]) {
        const double t = k / 100.0;
        double r, g, b;
        if (t <= 66) {
            r = 255;
            g = 99.4708025861 * std::log(t) - 161.1195681661;
        } else {
            r = 329.698727446 * std::pow(t - 60, -0.1332047592);
            g = 288.1221695283 * std::pow(t - 60, -0.0755148492);
        }
        if (t >= 66) b = 255;
        else if (t <= 19) b = 0;
        else b = 138.5177312231 * std::log(t - 10) - 305.0447927307;
        out[0] = std::clamp(r, 0.0, 255.0) / 255.0;
        out[1] = std::clamp(g, 0.0, 255.0) / 255.0;
        out[2] = std::clamp(b, 0.0, 255.0) / 255.0;
    };
    double ref[3];
    raw(kMax, ref);
    raw(kelvin, rgb);
    for (int i = 0; i < 3; ++i) rgb[i] = std::clamp(rgb[i] / ref[i], 0.0, 1.0);
}

// One screen's ramps, handed over in a memfd: red, then green, then blue,
// `size` 16-bit entries each.
void apply(Screen* s, double kelvin) {
    if (!s->control || s->failed || s->size == 0) return;
    double rgb[3];
    white_point(kelvin, rgb);
    std::vector<uint16_t> table(static_cast<size_t>(s->size) * 3);
    for (uint32_t i = 0; i < s->size; ++i) {
        const double v = s->size > 1 ? static_cast<double>(i) / (s->size - 1) : 1.0;
        for (int c = 0; c < 3; ++c)
            table[c * s->size + i] = static_cast<uint16_t>(std::lround(v * rgb[c] * 65535.0));
    }
    const int fd = memfd_create("b1air-gamma", MFD_CLOEXEC);
    if (fd < 0) return;
    const char* p = reinterpret_cast<const char*>(table.data());
    size_t left = table.size() * sizeof(uint16_t);
    while (left > 0) {
        const ssize_t n = write(fd, p, left);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) { close(fd); return; }
        p += n;
        left -= static_cast<size_t>(n);
    }
    lseek(fd, 0, SEEK_SET);
    zwlr_gamma_control_v1_set_gamma(s->control, fd);
    close(fd);
}

double g_current = kMax;   // what the screens show now

void gamma_size(void* data, struct zwlr_gamma_control_v1*, uint32_t size) {
    auto* s = static_cast<Screen*>(data);
    s->size = size;
    apply(s, g_current);
}
void gamma_failed(void* data, struct zwlr_gamma_control_v1* control) {
    // Another program holds this screen's gamma, or the screen cannot do it.
    auto* s = static_cast<Screen*>(data);
    s->failed = true;
    zwlr_gamma_control_v1_destroy(control);
    s->control = nullptr;
}
const struct zwlr_gamma_control_v1_listener kControl = {gamma_size, gamma_failed};

void attach(Screen* s) {
    if (!g_manager || s->control || s->failed) return;
    s->control = zwlr_gamma_control_manager_v1_get_gamma_control(g_manager, s->output);
    zwlr_gamma_control_v1_add_listener(s->control, &kControl, s);
}

void registry_global(void*, struct wl_registry* registry, uint32_t name, const char* interface, uint32_t) {
    if (std::strcmp(interface, wl_output_interface.name) == 0) {
        auto* s = new Screen;
        s->name = name;
        s->output = static_cast<wl_output*>(wl_registry_bind(registry, name, &wl_output_interface, 1));
        g_screens.push_back(s);
        attach(s);
    } else if (std::strcmp(interface, zwlr_gamma_control_manager_v1_interface.name) == 0) {
        g_manager = static_cast<zwlr_gamma_control_manager_v1*>(
            wl_registry_bind(registry, name, &zwlr_gamma_control_manager_v1_interface, 1));
        for (auto* s : g_screens) attach(s);
    }
}
void registry_global_remove(void*, struct wl_registry*, uint32_t name) {
    for (auto it = g_screens.begin(); it != g_screens.end(); ++it) {
        Screen* s = *it;
        if (s->name != name) continue;
        if (s->control) zwlr_gamma_control_v1_destroy(s->control);
        wl_output_destroy(s->output);
        delete s;
        g_screens.erase(it);
        return;
    }
}
const struct wl_registry_listener kRegistry = {registry_global, registry_global_remove};

std::string default_config_path() {
    const char* rt = std::getenv("XDG_RUNTIME_DIR");
    return rt && *rt ? std::string(rt) + "/b1air/gamma" : std::string();
}

bool all_refused() {
    if (g_screens.empty()) return false;
    for (const auto* s : g_screens)
        if (!s->failed) return false;
    return true;
}

int print(const gamma_schedule::Config& c, std::time_t when) {
    using namespace gamma_schedule;
    const double k = target_kelvin(c, when);
    double rgb[3];
    white_point(k, rgb);
    std::printf("temp=%ld\n", std::lround(k));
    std::printf("mode=%s\n", c.mode == Mode::Hours ? "hours" : c.mode == Mode::Sun ? "sun" : "always");
    if (c.mode != Mode::Always) {
        const Window w = night_window(c, when);
        if (!w.known) std::printf("night=unknown\n");
        else if (w.sun == Sun::AlwaysUp) std::printf("night=none\n");
        else if (w.sun == Sun::AlwaysDown) std::printf("night=all\n");
        else std::printf("night=%s-%s\n", hhmm(w.from).c_str(), hhmm(w.to).c_str());
    }
    if (c.mode == Mode::Sun) {
        double lat = 0, lon = 0;
        std::string zone;
        if (c.lat && c.lon) std::printf("location=%.2f,%.2f\n", *c.lat, *c.lon);
        else if (zone_location(lat, lon, &zone)) std::printf("location=%.2f,%.2f %s\n", lat, lon, zone.c_str());
    }
    std::printf("rgb=%.3f %.3f %.3f\n", rgb[0], rgb[1], rgb[2]);
    return 0;
}

double now_ms() {
    timespec ts{};
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec * 1000.0 + ts.tv_nsec / 1e6;
}

} // namespace

int main(int argc, char** argv) {
    using gamma_schedule::Config;
    std::string config_path = default_config_path();
    std::optional<int> fixed;
    std::string overrides;
    bool print_only = false;
    std::time_t at = std::time(nullptr);
    for (int i = 1; i < argc; ++i) {
        const std::string a = argv[i];
        if (a == "--print") print_only = true;
        else if (a == "--config" && i + 1 < argc) config_path = argv[++i];
        else if (a == "--at" && i + 1 < argc) at = static_cast<std::time_t>(std::atoll(argv[++i]));
        else if ((a == "--temp" || a == "--mode" || a == "--from" || a == "--to" || a == "--lat" || a == "--lon")
                 && i + 1 < argc)
            overrides += a.substr(2) + "=" + argv[++i] + "\n";
        else if (auto k = gamma_schedule::parse_number(a); k && !fixed) fixed = gamma_schedule::clamp_kelvin(std::lround(*k));
        else {
            std::fprintf(stderr, "usage: b1air-gamma [<kelvin> | --config FILE] [--print [--at UNIX-TIME]]\n");
            return 2;
        }
    }

    auto file_text = [&]() {
        std::ifstream f(config_path);
        std::stringstream ss;
        if (f) ss << f.rdbuf();
        return ss.str();
    };
    auto load = [&]() { return gamma_schedule::parse(file_text()); };
    // A temperature on the command line instead of the file, and options
    // over either; both until the first SIGUSR1 reads the file again.
    Config config = gamma_schedule::parse(
        (fixed ? "temp=" + std::to_string(*fixed) : file_text()) + "\n" + overrides);
    if (print_only) return print(config, at);

    sigset_t mask;
    sigemptyset(&mask);
    sigaddset(&mask, SIGUSR1);
    sigaddset(&mask, SIGTERM);
    sigaddset(&mask, SIGINT);
    sigaddset(&mask, SIGHUP);
    sigprocmask(SIG_BLOCK, &mask, nullptr);
    const int sfd = signalfd(-1, &mask, SFD_CLOEXEC | SFD_NONBLOCK);

    // Once a minute, counting time spent suspended: CLOCK_BOOTTIME fires at
    // once on resume if a minute went by asleep.
    const int tfd = timerfd_create(CLOCK_BOOTTIME, TFD_CLOEXEC | TFD_NONBLOCK);
    if (tfd >= 0) {
        itimerspec every{{60, 0}, {60, 0}};
        timerfd_settime(tfd, 0, &every, nullptr);
    }

    struct wl_display* display = wl_display_connect(nullptr);
    if (!display) {
        std::fprintf(stderr, "b1air-gamma: no Wayland display\n");
        return 1;
    }
    struct wl_registry* registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &kRegistry, nullptr);
    wl_display_roundtrip(display);
    if (!g_manager) {
        std::fprintf(stderr, "b1air-gamma: the compositor has no gamma control\n");
        return 1;
    }
    // The controls answer with their ramp size, or with failed.
    wl_display_roundtrip(display);
    if (all_refused()) {
        std::fprintf(stderr, "b1air-gamma: no screen accepts gamma control\n");
        return 3;
    }

    // From white to where the settings say, and later from wherever the
    // screens are to each new value.
    double from = kMax, to = gamma_schedule::target_kelvin(config, std::time(nullptr));
    double fade_start = now_ms();
    bool fading = true;
    auto retarget = [&](double k) {
        if (std::fabs(k - to) < 1 && !fading) return;
        from = g_current;
        to = k;
        fade_start = now_ms();
        fading = true;
    };

    while (true) {
        if (fading) {
            const double f = std::min(1.0, (now_ms() - fade_start) / kFadeMs);
            const double eased = f * f * (3 - 2 * f);
            g_current = from + (to - from) * eased;
            for (auto* s : g_screens) apply(s, g_current);
            if (f >= 1.0) fading = false;
        }

        while (wl_display_prepare_read(display) != 0) wl_display_dispatch_pending(display);
        if (wl_display_flush(display) < 0 && errno != EAGAIN) { wl_display_cancel_read(display); break; }

        pollfd fds[3] = {{wl_display_get_fd(display), POLLIN, 0}, {sfd, POLLIN, 0}, {tfd, POLLIN, 0}};
        const int r = poll(fds, tfd >= 0 ? 3 : 2, fading ? 16 : -1);
        if (r < 0 && errno != EINTR) { wl_display_cancel_read(display); break; }
        if (r > 0 && (fds[0].revents & POLLIN)) {
            if (wl_display_read_events(display) < 0) break;
        } else {
            wl_display_cancel_read(display);
        }
        if (r > 0 && (fds[0].revents & (POLLERR | POLLHUP))) break;
        if (wl_display_dispatch_pending(display) < 0) break;

        if (r > 0 && (fds[1].revents & POLLIN)) {
            signalfd_siginfo si{};
            bool quit = false;
            while (read(sfd, &si, sizeof(si)) == static_cast<ssize_t>(sizeof(si))) {
                if (si.ssi_signo == SIGUSR1) {
                    config = load();
                    retarget(gamma_schedule::target_kelvin(config, std::time(nullptr)));
                } else {
                    quit = true;
                }
            }
            if (quit) break;
        }

        if (tfd >= 0 && r > 0 && (fds[2].revents & POLLIN)) {
            uint64_t ticks = 0;
            if (read(tfd, &ticks, sizeof(ticks)) < 0 && errno != EAGAIN) break;
            if (config.mode != gamma_schedule::Mode::Always)
                retarget(gamma_schedule::target_kelvin(config, std::time(nullptr)));
        }
    }

    for (auto* s : g_screens) {
        if (s->control) zwlr_gamma_control_v1_destroy(s->control);
        wl_output_destroy(s->output);
        delete s;
    }
    g_screens.clear();
    if (g_manager) zwlr_gamma_control_manager_v1_destroy(g_manager);
    wl_registry_destroy(registry);
    wl_display_flush(display);
    wl_display_disconnect(display);
    return 0;
}
