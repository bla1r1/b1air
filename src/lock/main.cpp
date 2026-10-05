// b1air-lock — the session's lock screen. It was swaylock, with two dozen
// colour flags to make it look like the desktop, and then the shell's
// Lock.qml; it is the only one now. Should it die while locked, the
// compositor keeps the session locked and the daemon starts another.
//
//   b1air-lock
//
// Every screen shows its own wallpaper, blurred and darkened, the time, the
// date, the account's picture and name and the password field — one
// password, the same on every screen — with the keyboard layout, the
// battery, the weather already fetched and a power menu (reboot, sleep,
// shut down) for the mouse. Colours are the desktop theme's
// (~/.config/b1air/theme.json). The password is checked through PAM (the
// "b1air-lock" service if /etc/pam.d has one, else "login") on a thread of
// its own, so the screen keeps drawing while it is checked.
//
// Native rather than QML because a lock has to be up before the machine
// sleeps and must not depend on a whole toolkit loading: this one is on the
// screen in a few milliseconds and a few megabytes.
//
// The session's idle thread is told the lock is up and when it is opened
// ($XDG_RUNTIME_DIR/b1air/lock-state): the other screens dark while
// locked, the dim on lock, the lock before sleep.
//
// Plain wayland-client, ext-session-lock-v1, cairo for the drawing and
// xkbcommon for the keys. Exits 0 once opened; while it runs the compositor
// keeps the session locked even if this process dies.

#include <algorithm>
#include <atomic>
#include <cairo.h>
#include <cerrno>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>
#include <fcntl.h>
#include <filesystem>
#include <fstream>
#include <nlohmann/json.hpp>
#include <poll.h>
#include <pwd.h>
#include <security/pam_appl.h>
#include <string>
#include <sys/eventfd.h>
#include <sys/mman.h>
#include <sys/timerfd.h>
#include <sys/wait.h>
#include <thread>
#include <unistd.h>
#include <vector>
#include <wayland-client.h>
#include <wayland-cursor.h>
#include <xkbcommon/xkbcommon.h>

#include "ext-session-lock-v1-client-protocol.h"
#include "fingerprint.hpp"
#include "image.hpp"            // b1air-bg's decoder
#include "runtime.hpp"
#include "settings_manager.hpp"
#include "system_control.hpp"

namespace {

// ── State ────────────────────────────────────────────────────────────────────

enum class Status { Idle, Typing, Checking, Denied, Unavailable };

struct Rect {
    double x = 0, y = 0, w = 0, h = 0;
    bool contains(double px, double py) const { return w > 0 && px >= x && px < x + w && py >= y && py < y + h; }
};

enum class Action { None, Menu, Reboot, Suspend, PowerOff, Reveal };

struct Output {
    uint32_t global = 0;
    struct wl_output* output = nullptr;
    std::string name;
    int32_t scale = 1;
    struct wl_surface* surface = nullptr;
    struct ext_session_lock_surface_v1* lock_surface = nullptr;
    uint32_t width = 0, height = 0;
    bool configured = false;
    cairo_surface_t* wallpaper = nullptr;   // small: drawn up, which blurs it
    bool wallpaper_tried = false;
    // Where the power button and its menu were drawn, for the pointer; and
    // the eye that shows the password.
    Rect power, items[3], eye;
};

struct Colour {
    double r, g, b;
};

// The desktop theme's colours, Breeze Dark's until it is read.
struct Palette {
    Colour ground{0x20 / 255.0, 0x23 / 255.0, 0x26 / 255.0};
    Colour mid{0x29 / 255.0, 0x2c / 255.0, 0x30 / 255.0};
    Colour text{0xfc / 255.0, 0xfc / 255.0, 0xfc / 255.0};
    Colour dim{0xb4 / 255.0, 0xbb / 255.0, 0xc2 / 255.0};
    Colour primary{0x3d / 255.0, 0xae / 255.0, 0xe9 / 255.0};
    Colour tertiary{0xb0 / 255.0, 0x7a / 255.0, 0xd9 / 255.0};
    Colour error{0xed / 255.0, 0x4b / 255.0, 0x5b / 255.0};
    Colour warn{0xfd / 255.0, 0xbc / 255.0, 0x4b / 255.0};
};

struct App {
    struct wl_display* display = nullptr;
    struct wl_compositor* compositor = nullptr;
    struct wl_shm* shm = nullptr;
    struct wl_seat* seat = nullptr;
    struct wl_keyboard* keyboard = nullptr;
    struct wl_pointer* pointer = nullptr;
    struct wl_cursor_theme* cursor_theme = nullptr;
    struct wl_surface* cursor_surface = nullptr;
    Output* pointer_on = nullptr;
    double px = 0, py = 0;
    bool menu_open = false;
    struct ext_session_lock_manager_v1* manager = nullptr;
    struct ext_session_lock_v1* lock = nullptr;
    std::vector<Output*> outputs;

    struct xkb_context* xkb = nullptr;
    struct xkb_keymap* keymap = nullptr;
    struct xkb_state* xkb_state = nullptr;

    std::vector<std::string> layouts;   // "US", "UA": the keymap's groups
    uint32_t group = 0;

    std::string password;
    bool reveal = false;   // the eye: the password as text, not dots
    Status status = Status::Idle;
    bool caps = false;
    bool locked = false;
    bool finished = false;   // the compositor refused, or it is over
    bool unlocked = false;

    std::string user;
    std::string name;                      // the full name, or the login
    std::string lang;
    Palette pal;
    cairo_surface_t* avatar = nullptr;     // ~/.face.icon, square
    std::string battery;                   // "73%", empty without one
    bool charging = false;
    int battery_level = 100;
    std::string weather_icon, weather_temp;
    int event_fd = -1;                     // the PAM thread's answer
    std::atomic<int> pam_result{0};        // 1 ok, -1 denied, -2 unavailable
    // Fingerprint (a second PAM conversation, pam_fprintd): listening, and
    // what the last touch did (1 matched, -1 a miss); the miss shows a while.
    std::atomic<bool> fp_listening{false};
    std::atomic<int> fp_result{0};
    std::chrono::steady_clock::time_point fp_miss_until{};
} g;

// ── Words ────────────────────────────────────────────────────────────────────

struct Words {
    const char* enter;
    const char* checking;
    const char* denied;
    const char* unavailable;
    const char* caps;
    const char* finger;
    const char* finger_miss;
    const char* reboot;
    const char* suspend;
    const char* poweroff;
    const char* days[7];
    const char* months[12];
};

const Words kEn = {"Enter password", "Checking…", "Access denied", "Authentication unavailable", "Caps Lock is on",
                   "Or touch the fingerprint reader", "Fingerprint not recognised",
                   "Reboot", "Sleep", "Shut down",
                   {"Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"},
                   {"January", "February", "March", "April", "May", "June", "July", "August", "September",
                    "October", "November", "December"}};
const Words kUk = {"Введіть пароль", "Перевірка…", "Доступ заборонено", "Автентифікація недоступна",
                   "Увімкнено Caps Lock", "Або прикладіть палець", "Відбиток не розпізнано",
                   "Перезавантажити", "Сон", "Вимкнути",
                   {"неділя", "понеділок", "вівторок", "середа", "четвер", "пʼятниця", "субота"},
                   {"січня", "лютого", "березня", "квітня", "травня", "червня", "липня", "серпня", "вересня",
                    "жовтня", "листопада", "грудня"}};
const Words kRu = {"Введите пароль", "Проверка…", "Доступ запрещён", "Аутентификация недоступна",
                   "Включён Caps Lock", "Или приложите палец", "Отпечаток не распознан",
                   "Перезагрузить", "Сон", "Выключить",
                   {"воскресенье", "понедельник", "вторник", "среда", "четверг", "пятница", "суббота"},
                   {"января", "февраля", "марта", "апреля", "мая", "июня", "июля", "августа", "сентября",
                    "октября", "ноября", "декабря"}};

const Words& words() { return g.lang == "uk" ? kUk : g.lang == "ru" ? kRu : kEn; }

std::string date_text() {
    const std::time_t now = std::time(nullptr);
    std::tm t{};
    localtime_r(&now, &t);
    const Words& w = words();
    char buf[128];
    if (&w == &kEn) std::snprintf(buf, sizeof(buf), "%s, %s %d", w.days[t.tm_wday], w.months[t.tm_mon], t.tm_mday);
    else std::snprintf(buf, sizeof(buf), "%s, %d %s", w.days[t.tm_wday], t.tm_mday, w.months[t.tm_mon]);
    return buf;
}

std::string clock_text() {
    const std::time_t now = std::time(nullptr);
    std::tm t{};
    localtime_r(&now, &t);
    char buf[16];
    std::strftime(buf, sizeof(buf), "%H:%M", &t);
    return buf;
}

// ── The lock-state file the idle thread reads ───────────────────────────────

void write_state(const char* state) {
    const std::string path = b1air::runtime_path("lock-state");
    const std::string tmp = path + ".tmp";
    const int fd = open(tmp.c_str(), O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0600);
    if (fd < 0) return;
    const std::string text = std::string(state) + "\n";
    (void)!write(fd, text.data(), text.size());
    close(fd);
    rename(tmp.c_str(), path.c_str());
}

// ── What the screen shows besides the password ──────────────────────────────

bool parse_colour(const nlohmann::json& j, const char* key, Colour& out) {
    if (!j.contains(key) || !j[key].is_string()) return false;
    const std::string v = j[key].get<std::string>();
    unsigned r = 0, gg = 0, b = 0;
    if (v.size() != 7 || std::sscanf(v.c_str(), "#%02x%02x%02x", &r, &gg, &b) != 3) return false;
    out = {r / 255.0, gg / 255.0, b / 255.0};
    return true;
}

// The palette Settings → Themes wrote for the whole desktop.
void load_palette() {
    std::ifstream in(b1air::home_dir() + "/.config/b1air/theme.json");
    if (!in) return;
    const auto j = nlohmann::json::parse(in, nullptr, false);
    if (!j.is_object()) return;
    parse_colour(j, "ground", g.pal.ground);
    parse_colour(j, "mid", g.pal.mid);
    parse_colour(j, "text", g.pal.text);
    parse_colour(j, "textDim", g.pal.dim);
    parse_colour(j, "primary", g.pal.primary);
    parse_colour(j, "tertiary", g.pal.tertiary);
    parse_colour(j, "error", g.pal.error);
    parse_colour(j, "yellow", g.pal.warn);
}

void set(cairo_t* cr, const Colour& c, double a = 1.0) { cairo_set_source_rgba(cr, c.r, c.g, c.b, a); }

// The account's picture where the login screen keeps it, and the full name
// from the account (what Settings → User sets), else the login.
void load_account() {
    if (const passwd* pw = getpwuid(getuid())) {
        g.user = pw->pw_name;
        std::string gecos = pw->pw_gecos ? pw->pw_gecos : "";
        gecos = gecos.substr(0, gecos.find(','));
        g.name = gecos.empty() ? g.user : gecos;
    }
    const std::string face = b1air::home_dir() + "/.face.icon";
    if (access(face.c_str(), R_OK) != 0) return;
    constexpr int kSide = 256;
    cairo_surface_t* s = cairo_image_surface_create(CAIRO_FORMAT_RGB24, kSide, kSide);
    cairo_surface_flush(s);
    if (decode_cover(face, kSide, kSide, 0x313244, reinterpret_cast<uint32_t*>(cairo_image_surface_get_data(s)),
                     cairo_image_surface_get_stride(s))) {
        cairo_surface_mark_dirty(s);
        g.avatar = s;
    } else {
        cairo_surface_destroy(s);
    }
}

std::string read_line(const std::filesystem::path& p) {
    std::ifstream in(p);
    std::string s;
    std::getline(in, s);
    return s;
}

// Every system battery together (energy, else charge, else the mean of the
// percentages), as UPower's display device adds them: a laptop with two
// packs showed the first one's figure. Peripherals (scope Device) are not
// the machine's.
void read_battery() {
    double now = 0, full = 0, pct = 0;
    int packs = 0;
    bool charging = false;
    std::error_code ec;
    for (const auto& e : std::filesystem::directory_iterator("/sys/class/power_supply", ec)) {
        const auto& d = e.path();
        if (read_line(d / "type") != "Battery" || read_line(d / "scope") == "Device") continue;
        ++packs;
        const std::string st = read_line(d / "status");
        charging = charging || st == "Charging" || st == "Full";
        for (const char* kind : {"energy", "charge"}) {
            const std::string n = read_line(d / (std::string(kind) + "_now")), f = read_line(d / (std::string(kind) + "_full"));
            if (!n.empty() && !f.empty()) {
                now += std::atof(n.c_str());
                full += std::atof(f.c_str());
                break;
            }
        }
        pct += std::atof(read_line(d / "capacity").c_str());
    }
    if (packs == 0) {
        g.battery.clear();
        return;
    }
    const int level = static_cast<int>(std::lround(full > 0 ? 100.0 * now / full : pct / packs));
    g.battery_level = std::clamp(level, 0, 100);
    g.battery = std::to_string(g.battery_level) + "%";
    g.charging = charging;
}

void read_weather() {
    const std::string w = b1air::SystemControl::weather_cached_info("current");
    const auto nl = w.find('\n');
    if (nl == std::string::npos) {
        g.weather_icon.clear();
        g.weather_temp.clear();
        return;
    }
    g.weather_icon = w.substr(0, nl);
    g.weather_temp = w.substr(nl + 1);
    while (!g.weather_temp.empty() && g.weather_temp.back() == '\n') g.weather_temp.pop_back();
}

// The layouts, in group order, named as the bar names them: the codes
// Settings → Keyboard wrote ("us,ua" gives US and UA) when there are as many
// as the keymap has, else the keymap's own names cut down ("English (US)"
// gives US). The keymap the compositor sends is compiled: it names its
// groups but no longer says which layouts they came from.
void read_layouts(struct xkb_keymap* keymap) {
    g.layouts.clear();
    const xkb_layout_index_t n = xkb_keymap_num_layouts(keymap);
    std::vector<std::string> codes;
    const std::string setting = b1air::SettingsManager::get_json_string("language");
    for (size_t start = 0; start <= setting.size();) {
        const size_t comma = std::min(setting.find(',', start), setting.size());
        std::string code = setting.substr(start, comma - start);
        code.erase(std::remove_if(code.begin(), code.end(), [](unsigned char c) { return std::isspace(c); }), code.end());
        if (!code.empty()) codes.push_back(code);
        start = comma + 1;
    }
    for (xkb_layout_index_t i = 0; i < n; ++i) {
        std::string code;
        if (codes.size() == n) {
            code = codes[i].substr(0, 3);
        } else {
            const char* name = xkb_keymap_layout_get_name(keymap, i);
            code = name ? name : "";
            const auto open = code.find('('), close = code.find(')');
            if (open != std::string::npos && close != std::string::npos && close > open)
                code = code.substr(open + 1, close - open - 1);
            code = code.substr(0, 2);
        }
        for (auto& c : code) c = static_cast<char>(std::toupper(static_cast<unsigned char>(c)));
        g.layouts.push_back(code);
    }
}

// The power menu's entries: `b1air-daemon power …`,
// detached so a reboot taking a while does not stop the drawing.
void run_power(Action a) {
    const char* what = a == Action::Reboot ? "reboot" : a == Action::Suspend ? "suspend" : "shutdown";
    const pid_t pid = fork();
    if (pid == 0) {
        if (fork() == 0) {
            execlp("b1air-daemon", "b1air-daemon", "power", what, static_cast<char*>(nullptr));
            _exit(127);
        }
        _exit(0);
    }
    if (pid > 0) waitpid(pid, nullptr, 0);
}

// ── Drawing ──────────────────────────────────────────────────────────────────

void load_wallpaper(Output* o) {
    if (o->wallpaper_tried || o->width == 0) return;
    o->wallpaper_tried = true;
    const std::string path = b1air::SystemControl::wallpaper_shown_on(o->name);
    if (path.empty()) return;
    // A twelfth of the screen, then drawn up to it with a smooth filter:
    // that is the blur, for nothing.
    const int w = std::max(16, static_cast<int>(o->width) / 12), h = std::max(9, static_cast<int>(o->height) / 12);
    cairo_surface_t* s = cairo_image_surface_create(CAIRO_FORMAT_RGB24, w, h);
    cairo_surface_flush(s);
    auto* pixels = reinterpret_cast<uint32_t*>(cairo_image_surface_get_data(s));
    if (!decode_cover(path, w, h, 0x1a1b26, pixels, cairo_image_surface_get_stride(s))) {
        cairo_surface_destroy(s);
        return;
    }
    cairo_surface_mark_dirty(s);
    o->wallpaper = s;
}

void rounded(cairo_t* cr, double x, double y, double w, double h, double r) {
    cairo_new_sub_path(cr);
    cairo_arc(cr, x + w - r, y + r, r, -M_PI / 2, 0);
    cairo_arc(cr, x + w - r, y + h - r, r, 0, M_PI / 2);
    cairo_arc(cr, x + r, y + h - r, r, M_PI / 2, M_PI);
    cairo_arc(cr, x + r, y + r, r, M_PI, 3 * M_PI / 2);
    cairo_close_path(cr);
}

// The desktop's: Design.qml's sans for words, its Nerd Font for icons.
constexpr const char* kFont = "Fira Sans";
constexpr const char* kIconFont = "JetBrainsMono Nerd Font Mono";

void font(cairo_t* cr, double size, bool bold, bool icon = false) {
    cairo_select_font_face(cr, icon ? kIconFont : kFont, CAIRO_FONT_SLANT_NORMAL,
                           bold ? CAIRO_FONT_WEIGHT_BOLD : CAIRO_FONT_WEIGHT_NORMAL);
    cairo_set_font_size(cr, size);
}

double text_width(cairo_t* cr, const std::string& text) {
    cairo_text_extents_t e;
    cairo_text_extents(cr, text.c_str(), &e);
    return e.x_advance;
}

// Text centred on cx, its baseline at y.
void centred_text(cairo_t* cr, const std::string& text, double cx, double y, double size, bool bold) {
    font(cr, size, bold);
    cairo_text_extents_t e;
    cairo_text_extents(cr, text.c_str(), &e);
    cairo_move_to(cr, cx - e.width / 2 - e.x_bearing, y);
    cairo_show_text(cr, text.c_str());
    cairo_new_path(cr);   // or the next arc is joined to where the text ended
}

// An icon then words, centred on cx.
void centred_line(cairo_t* cr, const std::string& icon, const std::string& text, double cx, double y, double size) {
    font(cr, size, false, true);
    const double iw = text_width(cr, icon), gap = size * 0.6;
    font(cr, size, false);
    const double tw = text_width(cr, text);
    const double x = cx - (iw + gap + tw) / 2;
    font(cr, size, false, true);
    cairo_move_to(cr, x, y);
    cairo_show_text(cr, icon.c_str());
    font(cr, size, false);
    cairo_move_to(cr, x + iw + gap, y);
    cairo_show_text(cr, text.c_str());
    cairo_new_path(cr);
}

// Text centred in a box, both ways.
void boxed_text(cairo_t* cr, const std::string& text, const Rect& r) {
    cairo_font_extents_t fe;
    cairo_font_extents(cr, &fe);
    cairo_text_extents_t e;
    cairo_text_extents(cr, text.c_str(), &e);
    cairo_move_to(cr, r.x + (r.w - e.x_advance) / 2, r.y + (r.h + fe.ascent - fe.descent) / 2);
    cairo_show_text(cr, text.c_str());
    cairo_new_path(cr);
}

// A pill of an icon and a word.
double pill_width(cairo_t* cr, double u, const std::string& icon, const std::string& text) {
    font(cr, 17 * u, false, true);
    const double iw = icon.empty() ? 0 : text_width(cr, icon);
    font(cr, 16 * u, false);
    const double tw = text.empty() ? 0 : text_width(cr, text);
    return 32 * u + iw + (icon.empty() || text.empty() ? 0 : 8 * u) + tw;
}

Rect pill(cairo_t* cr, double x, double y, double h, double u, const std::string& icon, const std::string& text,
          const Colour& ink, double fill_alpha) {
    const Rect r{x, y, pill_width(cr, u, icon, text), h};
    cairo_new_path(cr);
    rounded(cr, r.x, r.y, r.w, r.h, h / 2);
    set(cr, g.pal.ground, fill_alpha);
    cairo_fill_preserve(cr);
    set(cr, g.pal.text, 0.10);
    cairo_set_line_width(cr, 1 * u);
    cairo_stroke(cr);
    font(cr, 17 * u, false, true);
    cairo_font_extents_t fe;
    cairo_font_extents(cr, &fe);
    const double iw = icon.empty() ? 0 : text_width(cr, icon);
    set(cr, ink, 0.95);
    cairo_move_to(cr, x + 16 * u, y + (h + fe.ascent - fe.descent) / 2);
    cairo_show_text(cr, icon.c_str());
    font(cr, 16 * u, false);
    cairo_font_extents(cr, &fe);
    set(cr, g.pal.text, 0.9);
    cairo_move_to(cr, x + 16 * u + iw + (icon.empty() ? 0 : 8 * u), y + (h + fe.ascent - fe.descent) / 2);
    cairo_show_text(cr, text.c_str());
    cairo_new_path(cr);
    return r;
}

const char* battery_icon() {
    static const char* levels[] = {"󰂎", "󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"};
    if (g.charging) return "󰂄";
    return levels[std::clamp(g.battery_level / 10, 0, 10)];
}

void buffer_release(void*, struct wl_buffer* buffer) { wl_buffer_destroy(buffer); }
const struct wl_buffer_listener kBufferListener = {buffer_release};

void draw(Output* o) {
    if (!o->configured || o->width == 0 || o->height == 0) return;
    load_wallpaper(o);
    const int scale = std::max(1, o->scale);
    const int w = static_cast<int>(o->width) * scale, h = static_cast<int>(o->height) * scale;
    const int stride = w * 4;
    const size_t size = static_cast<size_t>(stride) * h;

    const int fd = memfd_create("b1air-lock", MFD_CLOEXEC);
    if (fd < 0 || ftruncate(fd, static_cast<off_t>(size)) != 0) {
        if (fd >= 0) close(fd);
        return;
    }
    void* data = mmap(nullptr, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (data == MAP_FAILED) {
        close(fd);
        return;
    }
    cairo_surface_t* target =
        cairo_image_surface_create_for_data(static_cast<unsigned char*>(data), CAIRO_FORMAT_RGB24, w, h, stride);
    cairo_t* cr = cairo_create(target);
    cairo_scale(cr, scale, scale);
    const double W = o->width, H = o->height;

    // The picture, blurred, and a veil over it.
    set(cr, g.pal.ground);
    cairo_paint(cr);
    if (o->wallpaper) {
        cairo_save(cr);
        cairo_scale(cr, W / cairo_image_surface_get_width(o->wallpaper), H / cairo_image_surface_get_height(o->wallpaper));
        cairo_set_source_surface(cr, o->wallpaper, 0, 0);
        cairo_pattern_set_filter(cairo_get_source(cr), CAIRO_FILTER_GOOD);
        cairo_pattern_set_extend(cairo_get_source(cr), CAIRO_EXTEND_PAD);
        cairo_paint(cr);
        cairo_restore(cr);
    }
    cairo_set_source_rgba(cr, 0, 0, 0, 0.35);
    cairo_paint(cr);

    const double u = std::min(W, H) / 1080.0;   // one unit at 1080p
    const double cx = W / 2, cy = H / 2;
    const Palette& p = g.pal;

    // The time and the date.
    set(cr, p.text, 0.96);
    centred_text(cr, clock_text(), cx, cy - 150 * u, 150 * u, true);
    set(cr, p.text, 0.80);
    centred_text(cr, date_text(), cx, cy - 100 * u, 24 * u, false);

    // The account: the picture in a ring, or the initial on a tinted disc.
    const double ar = 46 * u, ay = cy - 10 * u;
    cairo_new_path(cr);
    cairo_arc(cr, cx, ay, ar + 3 * u, 0, 2 * M_PI);
    set(cr, p.primary, 0.55);
    cairo_fill(cr);
    cairo_save(cr);
    cairo_arc(cr, cx, ay, ar, 0, 2 * M_PI);
    cairo_clip(cr);
    if (g.avatar) {
        const double side = cairo_image_surface_get_width(g.avatar);
        cairo_translate(cr, cx - ar, ay - ar);
        cairo_scale(cr, 2 * ar / side, 2 * ar / side);
        cairo_set_source_surface(cr, g.avatar, 0, 0);
        cairo_pattern_set_filter(cairo_get_source(cr), CAIRO_FILTER_GOOD);
        cairo_paint(cr);
    } else {
        set(cr, p.mid, 1.0);
        cairo_paint(cr);
        set(cr, p.primary, 1.0);
        std::string initial;
        if (!g.name.empty()) {   // the first code point, upper-cased if ASCII
            size_t n = 1;
            while (n < g.name.size() && (static_cast<unsigned char>(g.name[n]) & 0xC0) == 0x80) ++n;
            initial = g.name.substr(0, n);
            if (n == 1) initial[0] = static_cast<char>(std::toupper(static_cast<unsigned char>(initial[0])));
        }
        font(cr, 40 * u, true);
        boxed_text(cr, initial, {cx - ar, ay - ar, 2 * ar, 2 * ar});
    }
    cairo_restore(cr);
    set(cr, p.text, 0.95);
    centred_text(cr, g.name, cx, ay + ar + 40 * u, 26 * u, true);

    // The field: dots for what is typed, the layout at its right end.
    const double fw = 380 * u, fh = 56 * u, fx = cx - fw / 2, fy = ay + ar + 64 * u;
    const bool denied = g.status == Status::Denied || g.status == Status::Unavailable;
    rounded(cr, fx, fy, fw, fh, fh / 2);
    set(cr, p.ground, 0.70);
    cairo_fill_preserve(cr);
    if (denied) set(cr, p.error, 0.9);
    else if (g.status == Status::Checking) set(cr, p.warn, 0.9);
    else set(cr, p.primary, g.password.empty() ? 0.35 : 0.9);
    cairo_set_line_width(cr, 2 * u);
    cairo_stroke(cr);

    double layout_w = 0;
    if (g.layouts.size() > 1 && g.group < g.layouts.size()) {
        font(cr, 15 * u, true);
        const Rect lr{fx + fw - 64 * u, fy + 12 * u, 48 * u, fh - 24 * u};
        rounded(cr, lr.x, lr.y, lr.w, lr.h, lr.h / 2);
        set(cr, p.primary, 0.18);
        cairo_fill(cr);
        set(cr, p.primary, 0.95);
        boxed_text(cr, g.layouts[g.group], lr);
        layout_w = 64 * u;
    }

    // The eye at the left end, once something is typed: a click shows the
    // password as text, another hides it again. It hid what was typed with
    // no way to check it, and a typo was found by being refused.
    double eye_w = 0;
    o->eye = {};
    if (!g.password.empty()) {
        o->eye = {fx + 12 * u, fy + 10 * u, 40 * u, fh - 20 * u};
        eye_w = 52 * u;
        const bool over = g.pointer_on == o && o->eye.contains(g.px, g.py);
        if (over) {
            rounded(cr, o->eye.x, o->eye.y, o->eye.w, o->eye.h, o->eye.h / 2);
            set(cr, p.primary, 0.18);
            cairo_fill(cr);
        }
        font(cr, 20 * u, false, true);
        set(cr, g.reveal ? p.primary : p.dim, 0.95);
        boxed_text(cr, g.reveal ? "\U000F0209" : "\U000F0208", o->eye);   // eye-off / eye
    }

    const double inner_l = fx + 24 * u + eye_w, inner_r = fx + fw - 24 * u - layout_w;
    if (g.reveal && !g.password.empty()) {
        // As text, its end in view when it is wider than the field.
        cairo_save(cr);
        cairo_rectangle(cr, inner_l, fy, inner_r - inner_l, fh);
        cairo_clip(cr);
        font(cr, 20 * u, false);
        cairo_font_extents_t fe;
        cairo_font_extents(cr, &fe);
        const double tw = text_width(cr, g.password);
        const double tx = tw <= inner_r - inner_l ? (inner_l + inner_r - tw) / 2 : inner_r - tw;
        set(cr, p.text, 0.95);
        cairo_move_to(cr, tx, fy + (fh + fe.ascent - fe.descent) / 2);
        cairo_show_text(cr, g.password.c_str());
        cairo_new_path(cr);
        cairo_restore(cr);
    } else {
        // A dot a character (counted as UTF-8 code points), as many as fit.
        size_t chars = 0;
        for (unsigned char c : g.password)
            if ((c & 0xC0) != 0x80) ++chars;
        const double gap = 16 * u, r = 5 * u;
        const size_t fit = static_cast<size_t>(std::max(1.0, (inner_r - inner_l) / gap));
        const size_t shown = std::min(chars, fit);
        double x = (inner_l + inner_r) / 2 - (static_cast<double>(shown) - 1) * gap / 2;
        set(cr, p.text, 0.95);
        for (size_t i = 0; i < shown; ++i, x += gap) {
            cairo_arc(cr, x, fy + fh / 2, r, 0, 2 * M_PI);
            cairo_fill(cr);
        }
    }

    const Words& wd = words();
    std::string line = g.status == Status::Checking ? wd.checking
                     : g.status == Status::Denied ? wd.denied
                     : g.status == Status::Unavailable ? wd.unavailable
                     : wd.enter;
    if (denied) set(cr, p.error, 0.95);
    else set(cr, p.text, 0.70);
    centred_text(cr, line, cx, fy + fh + 36 * u, 18 * u, false);
    double below = fy + fh + 64 * u;
    if (g.caps) {
        set(cr, p.warn, 0.95);
        centred_line(cr, "󰪛", wd.caps, cx, below, 16 * u);
        below += 26 * u;
    }
    const bool miss = std::chrono::steady_clock::now() < g.fp_miss_until;
    if (g.fp_listening || miss) {
        set(cr, miss ? p.error : p.primary, 0.95);
        centred_line(cr, "󰈷", miss ? wd.finger_miss : wd.finger, cx, below, 16 * u);
    }

    // The corners: weather at the top left, the battery at the top right.
    const double ph = 40 * u, m = 28 * u;
    if (!g.weather_temp.empty()) pill(cr, m, m, ph, u, g.weather_icon, g.weather_temp, p.tertiary, 0.55);
    if (!g.battery.empty()) {
        const double bw = pill_width(cr, u, battery_icon(), g.battery);
        const bool low = !g.charging && g.battery_level <= 15;
        pill(cr, W - m - bw, m, ph, u, battery_icon(), g.battery, low ? p.error : p.primary, 0.55);
    }

    // The power menu, bottom right: the button, and when it is open, the
    // three things it does to its left.
    const double bs = 52 * u;
    o->power = {W - m - bs, H - m - bs, bs, bs};
    const bool hover_power = g.pointer_on == o && o->power.contains(g.px, g.py);
    cairo_new_path(cr);
    cairo_arc(cr, o->power.x + bs / 2, o->power.y + bs / 2, bs / 2, 0, 2 * M_PI);
    set(cr, g.menu_open ? p.error : p.ground, g.menu_open ? 0.25 : (hover_power ? 0.8 : 0.55));
    cairo_fill_preserve(cr);
    set(cr, p.text, 0.12);
    cairo_set_line_width(cr, 1 * u);
    cairo_stroke(cr);
    font(cr, 22 * u, false, true);
    set(cr, g.menu_open || hover_power ? p.error : p.text, 0.9);
    boxed_text(cr, "󰐥", o->power);
    for (auto& it : o->items) it = {};
    if (g.menu_open) {
        const char* icons[3] = {"󰜉", "󰒲", "󰐥"};
        const char* labels[3] = {wd.reboot, wd.suspend, wd.poweroff};
        const Colour* inks[3] = {&p.primary, &p.tertiary, &p.error};
        double right = o->power.x - 12 * u;
        for (int i = 2; i >= 0; --i) {
            const double w = pill_width(cr, u, icons[i], labels[i]);
            const bool hover = g.pointer_on == o && Rect{right - w, o->power.y + 6 * u, w, bs - 12 * u}.contains(g.px, g.py);
            o->items[i] = pill(cr, right - w, o->power.y + 6 * u, bs - 12 * u, u, icons[i], labels[i], *inks[i],
                               hover ? 0.85 : 0.6);
            right -= w + 10 * u;
        }
    }

    cairo_destroy(cr);
    cairo_surface_flush(target);
    cairo_surface_destroy(target);
    munmap(data, size);

    struct wl_shm_pool* pool = wl_shm_create_pool(g.shm, fd, static_cast<int32_t>(size));
    struct wl_buffer* buffer = wl_shm_pool_create_buffer(pool, 0, w, h, stride, WL_SHM_FORMAT_XRGB8888);
    wl_shm_pool_destroy(pool);
    close(fd);
    wl_buffer_add_listener(buffer, &kBufferListener, nullptr);
    wl_surface_set_buffer_scale(o->surface, scale);
    wl_surface_attach(o->surface, buffer, 0, 0);
    wl_surface_damage_buffer(o->surface, 0, 0, w, h);
    wl_surface_commit(o->surface);
}

void draw_all() {
    for (auto* o : g.outputs) draw(o);
}

// ── PAM ──────────────────────────────────────────────────────────────────────

int conversation(int count, const struct pam_message** msg, struct pam_response** resp, void* data) {
    auto* replies = static_cast<struct pam_response*>(calloc(static_cast<size_t>(count), sizeof(struct pam_response)));
    if (!replies) return PAM_BUF_ERR;
    const auto* password = static_cast<const std::string*>(data);
    for (int i = 0; i < count; ++i)
        if (msg[i]->msg_style == PAM_PROMPT_ECHO_OFF || msg[i]->msg_style == PAM_PROMPT_ECHO_ON)
            replies[i].resp = strdup(password->c_str());
    *resp = replies;
    return PAM_SUCCESS;
}

void check_password(std::string password) {
    const char* service = access("/etc/pam.d/b1air-lock", R_OK) == 0 ? "b1air-lock" : "login";
    const struct pam_conv conv = {conversation, &password};
    pam_handle_t* pam = nullptr;
    int result = -2;
    if (pam_start(service, g.user.c_str(), &conv, &pam) == PAM_SUCCESS) {
        const int r = pam_authenticate(pam, 0);
        result = r == PAM_SUCCESS ? 1 : (r == PAM_AUTH_ERR || r == PAM_USER_UNKNOWN || r == PAM_MAXTRIES) ? -1 : -2;
        pam_end(pam, r);
    }
    std::fill(password.begin(), password.end(), '\0');
    g.pam_result = result;
    const uint64_t one = 1;
    (void)!write(g.event_fd, &one, sizeof(one));
}

// The fingerprint, beside the password: pam_fprintd from the suite's own
// PAM file (pam/b1air-fingerprint, read from its directory with
// pam_start_confdir), over and over until it matches. Not started when the
// setting is off, no finger is enrolled, or the file is not installed.
std::string fingerprint_confdir() {
    for (const std::string& dir : {std::string("/usr/share/b1air/pam"), b1air::home_dir() + "/.local/share/b1air/pam"})
        if (access((dir + "/b1air-fingerprint").c_str(), R_OK) == 0) return dir;
    return {};
}

bool fingerprint_wanted() {
    if (!b1air::SettingsManager::get_json_bool("fingerprintUnlock", true)) return false;
    if (fingerprint_confdir().empty()) return false;
    const std::string status = b1air::fingerprint::status_json();
    return status.find("\"available\":true") != std::string::npos && status.find("\"enrolled\":[]") == std::string::npos;
}

void fingerprint_loop() {
#ifdef B1AIR_HAVE_PAM_CONFDIR
    const std::string dir = fingerprint_confdir();
    int errors = 0;
    while (errors < 3) {
        std::string nothing;   // pam_fprintd asks no questions; it says things
        const struct pam_conv conv = {conversation, &nothing};
        pam_handle_t* pam = nullptr;
        if (pam_start_confdir("b1air-fingerprint", g.user.c_str(), &conv, dir.c_str(), &pam) != PAM_SUCCESS) return;
        g.fp_listening = true;
        const uint64_t one = 1;
        (void)!write(g.event_fd, &one, sizeof(one));   // redraw: "or touch the reader"
        const int r = pam_authenticate(pam, 0);
        pam_end(pam, r);
        g.fp_listening = false;
        if (r == PAM_SUCCESS) {
            g.fp_result = 1;
            (void)!write(g.event_fd, &one, sizeof(one));
            return;
        }
        if (r == PAM_AUTH_ERR || r == PAM_MAXTRIES) {
            g.fp_result = -1;   // a finger that is not this one
            errors = 0;
        } else {
            ++errors;           // the reader gone, fprintd not answering
        }
        (void)!write(g.event_fd, &one, sizeof(one));
        std::this_thread::sleep_for(std::chrono::seconds(1));
    }
#endif
}

void submit() {
    if (g.password.empty() || g.status == Status::Checking) return;
    g.status = Status::Checking;
    std::thread(check_password, g.password).detach();
    std::fill(g.password.begin(), g.password.end(), '\0');
    g.password.clear();
    g.reveal = false;
    draw_all();
}

// ── Keyboard ─────────────────────────────────────────────────────────────────

void kb_keymap(void*, struct wl_keyboard*, uint32_t format, int32_t fd, uint32_t size) {
    if (format != WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1) {
        close(fd);
        return;
    }
    char* map = static_cast<char*>(mmap(nullptr, size, PROT_READ, MAP_PRIVATE, fd, 0));
    close(fd);
    if (map == MAP_FAILED) return;
    struct xkb_keymap* keymap = xkb_keymap_new_from_string(g.xkb, map, XKB_KEYMAP_FORMAT_TEXT_V1,
                                                           XKB_KEYMAP_COMPILE_NO_FLAGS);
    if (keymap) read_layouts(keymap);
    munmap(map, size);
    if (!keymap) return;
    if (g.xkb_state) xkb_state_unref(g.xkb_state);
    if (g.keymap) xkb_keymap_unref(g.keymap);
    g.keymap = keymap;
    g.xkb_state = xkb_state_new(keymap);
}

void kb_enter(void*, struct wl_keyboard*, uint32_t, struct wl_surface*, struct wl_array*) {}
void kb_leave(void*, struct wl_keyboard*, uint32_t, struct wl_surface*) {}

void kb_key(void*, struct wl_keyboard*, uint32_t, uint32_t, uint32_t key, uint32_t state) {
    if (state != WL_KEYBOARD_KEY_STATE_PRESSED || !g.xkb_state) return;
    const xkb_keycode_t code = key + 8;
    const xkb_keysym_t sym = xkb_state_key_get_one_sym(g.xkb_state, code);
    const bool ctrl = xkb_state_mod_name_is_active(g.xkb_state, XKB_MOD_NAME_CTRL, XKB_STATE_MODS_EFFECTIVE) > 0;
    const bool logo = xkb_state_mod_name_is_active(g.xkb_state, XKB_MOD_NAME_LOGO, XKB_STATE_MODS_EFFECTIVE) > 0;
    if (logo) return;   // Super+3 out of habit is not part of a password
    if (g.status == Status::Checking) return;
    if (g.status == Status::Denied || g.status == Status::Unavailable) g.status = Status::Typing;

    if (sym == XKB_KEY_Return || sym == XKB_KEY_KP_Enter) {
        submit();
        return;
    }
    if (sym == XKB_KEY_Escape && g.menu_open) {
        g.menu_open = false;
        draw_all();
        return;
    }
    if (sym == XKB_KEY_Escape || (ctrl && (sym == XKB_KEY_u || sym == XKB_KEY_U))) {
        std::fill(g.password.begin(), g.password.end(), '\0');
        g.password.clear();
    } else if (sym == XKB_KEY_BackSpace) {
        while (!g.password.empty()) {   // one code point
            const unsigned char c = static_cast<unsigned char>(g.password.back());
            g.password.pop_back();
            if ((c & 0xC0) != 0x80) break;
        }
    } else if (!ctrl) {
        char buf[16] = {0};
        const int n = xkb_state_key_get_utf8(g.xkb_state, code, buf, sizeof(buf));
        if (n > 0 && static_cast<unsigned char>(buf[0]) >= 0x20 && buf[0] != 0x7f) g.password.append(buf, static_cast<size_t>(n));
    }
    g.status = g.password.empty() ? Status::Idle : Status::Typing;
    if (g.password.empty()) g.reveal = false;   // shown again only when asked
    draw_all();
}

void kb_modifiers(void*, struct wl_keyboard*, uint32_t, uint32_t depressed, uint32_t latched, uint32_t locked,
                  uint32_t group) {
    if (!g.xkb_state) return;
    xkb_state_update_mask(g.xkb_state, depressed, latched, locked, 0, 0, group);
    const bool caps = xkb_state_mod_name_is_active(g.xkb_state, XKB_MOD_NAME_CAPS, XKB_STATE_MODS_LOCKED) > 0;
    if (caps != g.caps || group != g.group) {   // Caps Lock, or the layout switched
        g.caps = caps;
        g.group = group;
        draw_all();
    }
}

void kb_repeat(void*, struct wl_keyboard*, int32_t, int32_t) {}

const struct wl_keyboard_listener kKeyboard = {kb_keymap, kb_enter, kb_leave, kb_key, kb_modifiers, kb_repeat};

// ── Pointer: the power menu ──────────────────────────────────────────────────

Output* output_of(struct wl_surface* surface) {
    for (auto* o : g.outputs)
        if (o->surface == surface) return o;
    return nullptr;
}

void pt_enter(void*, struct wl_pointer* pointer, uint32_t serial, struct wl_surface* surface, wl_fixed_t x, wl_fixed_t y) {
    g.pointer_on = output_of(surface);
    g.px = wl_fixed_to_double(x);
    g.py = wl_fixed_to_double(y);
    // An arrow: a lock surface has no cursor of its own until it sets one.
    if (g.cursor_theme && g.cursor_surface) {
        struct wl_cursor* c = wl_cursor_theme_get_cursor(g.cursor_theme, "default");
        if (!c) c = wl_cursor_theme_get_cursor(g.cursor_theme, "left_ptr");
        if (c && c->image_count > 0) {
            struct wl_cursor_image* img = c->images[0];
            wl_surface_attach(g.cursor_surface, wl_cursor_image_get_buffer(img), 0, 0);
            wl_surface_damage_buffer(g.cursor_surface, 0, 0, static_cast<int32_t>(img->width), static_cast<int32_t>(img->height));
            wl_surface_commit(g.cursor_surface);
            wl_pointer_set_cursor(pointer, serial, g.cursor_surface, static_cast<int32_t>(img->hotspot_x),
                                  static_cast<int32_t>(img->hotspot_y));
        }
    }
}
void pt_leave(void*, struct wl_pointer*, uint32_t, struct wl_surface*) {
    Output* was = g.pointer_on;
    g.pointer_on = nullptr;
    if (was) draw(was);
}

Action hit(const Output* o, double x, double y) {
    if (o->power.contains(x, y)) return Action::Menu;
    if (o->eye.contains(x, y)) return Action::Reveal;
    if (!g.menu_open) return Action::None;
    if (o->items[0].contains(x, y)) return Action::Reboot;
    if (o->items[1].contains(x, y)) return Action::Suspend;
    if (o->items[2].contains(x, y)) return Action::PowerOff;
    return Action::None;
}

void pt_motion(void*, struct wl_pointer*, uint32_t, wl_fixed_t x, wl_fixed_t y) {
    if (!g.pointer_on) return;
    const Action before = hit(g.pointer_on, g.px, g.py);
    g.px = wl_fixed_to_double(x);
    g.py = wl_fixed_to_double(y);
    if (hit(g.pointer_on, g.px, g.py) != before) draw(g.pointer_on);   // hover in or out
}

void pt_button(void*, struct wl_pointer*, uint32_t, uint32_t, uint32_t button, uint32_t state) {
    constexpr uint32_t kLeft = 0x110;   // BTN_LEFT
    if (button != kLeft || state != WL_POINTER_BUTTON_STATE_PRESSED || !g.pointer_on) return;
    const Action a = hit(g.pointer_on, g.px, g.py);
    if (a == Action::Menu) {
        g.menu_open = !g.menu_open;
    } else if (a == Action::Reveal) {
        g.reveal = !g.reveal;
        g.menu_open = false;
    } else if (a != Action::None) {
        g.menu_open = false;
        run_power(a);
    } else {
        g.menu_open = false;   // a click anywhere else closes it
    }
    draw_all();
}

void pt_axis(void*, struct wl_pointer*, uint32_t, uint32_t, wl_fixed_t) {}
void pt_frame(void*, struct wl_pointer*) {}
void pt_axis_source(void*, struct wl_pointer*, uint32_t) {}
void pt_axis_stop(void*, struct wl_pointer*, uint32_t, uint32_t) {}
void pt_axis_discrete(void*, struct wl_pointer*, uint32_t, int32_t) {}

// Filled by name: the seat is bound at version 7 at most, so the later
// events (axis_value120 and on) never come, and older wayland headers do not
// have those members at all.
wl_pointer_listener pointer_listener() {
    wl_pointer_listener l{};
    l.enter = pt_enter;
    l.leave = pt_leave;
    l.motion = pt_motion;
    l.button = pt_button;
    l.axis = pt_axis;
    l.frame = pt_frame;
    l.axis_source = pt_axis_source;
    l.axis_stop = pt_axis_stop;
    l.axis_discrete = pt_axis_discrete;
    return l;
}
const wl_pointer_listener kPointer = pointer_listener();

// The keyboard comes and goes with the devices: a USB keyboard unplugged
// and plugged back is "no keyboard", then a keyboard again, and the old
// wl_keyboard object gets nothing after that. Released and taken anew —
// without this, a keyboard plugged back in could not open the lock.
void seat_capabilities(void*, struct wl_seat* seat, uint32_t caps) {
    const bool has = (caps & WL_SEAT_CAPABILITY_KEYBOARD) != 0;
    if (has && !g.keyboard) {
        g.keyboard = wl_seat_get_keyboard(seat);
        wl_keyboard_add_listener(g.keyboard, &kKeyboard, nullptr);
    } else if (!has && g.keyboard) {
        if (wl_keyboard_get_version(g.keyboard) >= WL_KEYBOARD_RELEASE_SINCE_VERSION) wl_keyboard_release(g.keyboard);
        else wl_keyboard_destroy(g.keyboard);
        g.keyboard = nullptr;
    }
    const bool mouse = (caps & WL_SEAT_CAPABILITY_POINTER) != 0;
    if (mouse && !g.pointer) {
        g.pointer = wl_seat_get_pointer(seat);
        wl_pointer_add_listener(g.pointer, &kPointer, nullptr);
    } else if (!mouse && g.pointer) {
        if (wl_pointer_get_version(g.pointer) >= WL_POINTER_RELEASE_SINCE_VERSION) wl_pointer_release(g.pointer);
        else wl_pointer_destroy(g.pointer);
        g.pointer = nullptr;
        g.pointer_on = nullptr;
    }
}
void seat_name(void*, struct wl_seat*, const char*) {}
const struct wl_seat_listener kSeat = {seat_capabilities, seat_name};

// ── Screens ──────────────────────────────────────────────────────────────────

void ls_configure(void* data, struct ext_session_lock_surface_v1* ls, uint32_t serial, uint32_t width, uint32_t height) {
    auto* o = static_cast<Output*>(data);
    ext_session_lock_surface_v1_ack_configure(ls, serial);
    if (o->width != width || o->height != height) {
        if (o->wallpaper) cairo_surface_destroy(o->wallpaper);
        o->wallpaper = nullptr;
        o->wallpaper_tried = false;
    }
    o->width = width;
    o->height = height;
    o->configured = true;
    draw(o);
}
const struct ext_session_lock_surface_v1_listener kLockSurface = {ls_configure};

void make_lock_surface(Output* o) {
    if (!g.lock || o->lock_surface) return;
    o->surface = wl_compositor_create_surface(g.compositor);
    o->lock_surface = ext_session_lock_v1_get_lock_surface(g.lock, o->surface, o->output);
    ext_session_lock_surface_v1_add_listener(o->lock_surface, &kLockSurface, o);
}

void out_geometry(void*, struct wl_output*, int32_t, int32_t, int32_t, int32_t, int32_t, const char*, const char*, int32_t) {}
void out_mode(void*, struct wl_output*, uint32_t, int32_t, int32_t, int32_t) {}
void out_done(void* data, struct wl_output*) {
    auto* o = static_cast<Output*>(data);
    if (o->configured) draw(o);
}
void out_scale(void* data, struct wl_output*, int32_t factor) { static_cast<Output*>(data)->scale = factor; }
void out_name(void* data, struct wl_output*, const char* name) { static_cast<Output*>(data)->name = name; }
void out_description(void*, struct wl_output*, const char*) {}
const struct wl_output_listener kOutput = {out_geometry, out_mode, out_done, out_scale, out_name, out_description};

void lock_locked(void*, struct ext_session_lock_v1*) {
    g.locked = true;
    write_state("locked");
    if (fingerprint_wanted()) std::thread(fingerprint_loop).detach();
}
void lock_finished(void*, struct ext_session_lock_v1*) {
    // Refused (another lock holds the session), or ended by the compositor.
    g.finished = true;
}
const struct ext_session_lock_v1_listener kLock = {lock_locked, lock_finished};

void registry_global(void*, struct wl_registry* registry, uint32_t name, const char* interface, uint32_t version) {
    if (std::strcmp(interface, wl_compositor_interface.name) == 0) {
        g.compositor = static_cast<wl_compositor*>(wl_registry_bind(registry, name, &wl_compositor_interface, 4));
    } else if (std::strcmp(interface, wl_shm_interface.name) == 0) {
        g.shm = static_cast<wl_shm*>(wl_registry_bind(registry, name, &wl_shm_interface, 1));
    } else if (std::strcmp(interface, wl_seat_interface.name) == 0 && !g.seat) {
        // Version 5 and up: a keyboard switched mid-way (another device) keeps
        // sending keys; on version 1 only the first device's ever arrived.
        g.seat = static_cast<wl_seat*>(wl_registry_bind(registry, name, &wl_seat_interface, std::min(version, 7u)));
        wl_seat_add_listener(g.seat, &kSeat, nullptr);
    } else if (std::strcmp(interface, ext_session_lock_manager_v1_interface.name) == 0) {
        g.manager = static_cast<ext_session_lock_manager_v1*>(
            wl_registry_bind(registry, name, &ext_session_lock_manager_v1_interface, 1));
    } else if (std::strcmp(interface, wl_output_interface.name) == 0) {
        auto* o = new Output;
        o->global = name;
        o->output = static_cast<wl_output*>(wl_registry_bind(registry, name, &wl_output_interface, std::min(version, 4u)));
        wl_output_add_listener(o->output, &kOutput, o);
        g.outputs.push_back(o);
        make_lock_surface(o);   // a screen plugged in while locked
    }
}

void registry_global_remove(void*, struct wl_registry*, uint32_t name) {
    for (auto it = g.outputs.begin(); it != g.outputs.end(); ++it) {
        Output* o = *it;
        if (o->global != name) continue;
        if (o->lock_surface) ext_session_lock_surface_v1_destroy(o->lock_surface);
        if (o->surface) wl_surface_destroy(o->surface);
        if (o->wallpaper) cairo_surface_destroy(o->wallpaper);
        wl_output_destroy(o->output);
        delete o;
        g.outputs.erase(it);
        return;
    }
}
const struct wl_registry_listener kRegistry = {registry_global, registry_global_remove};

} // namespace

int main() {
    load_account();
    load_palette();
    read_battery();
    read_weather();
    g.lang = b1air::SettingsManager::get_json_string("uiLanguage");
    g.xkb = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
    g.event_fd = eventfd(0, EFD_CLOEXEC | EFD_NONBLOCK);

    g.display = wl_display_connect(nullptr);
    if (!g.display) {
        std::fprintf(stderr, "b1air-lock: no Wayland display\n");
        return 1;
    }
    struct wl_registry* registry = wl_display_get_registry(g.display);
    wl_registry_add_listener(registry, &kRegistry, nullptr);
    wl_display_roundtrip(g.display);
    if (!g.compositor || !g.shm || !g.manager) {
        std::fprintf(stderr, "b1air-lock: the compositor has no ext-session-lock\n");
        return 1;
    }
    wl_display_roundtrip(g.display);   // the screens' names
    // The cursor theme the session uses, at its size.
    const char* cursor_size = std::getenv("XCURSOR_SIZE");
    g.cursor_theme = wl_cursor_theme_load(std::getenv("XCURSOR_THEME"), cursor_size ? std::atoi(cursor_size) : 24, g.shm);
    g.cursor_surface = wl_compositor_create_surface(g.compositor);

    g.lock = ext_session_lock_manager_v1_lock(g.manager);
    ext_session_lock_v1_add_listener(g.lock, &kLock, nullptr);
    for (auto* o : g.outputs) make_lock_surface(o);

    // Once a second: the clock (redrawn when the minute turns).
    const int tfd = timerfd_create(CLOCK_MONOTONIC, TFD_CLOEXEC | TFD_NONBLOCK);
    itimerspec every{{1, 0}, {1, 0}};
    timerfd_settime(tfd, 0, &every, nullptr);
    std::string shown_clock = clock_text();
    int ticks = 0;

    while (!g.finished && !g.unlocked) {
        while (wl_display_prepare_read(g.display) != 0) wl_display_dispatch_pending(g.display);
        wl_display_flush(g.display);
        pollfd fds[3] = {{wl_display_get_fd(g.display), POLLIN, 0}, {g.event_fd, POLLIN, 0}, {tfd, POLLIN, 0}};
        const int r = poll(fds, 3, -1);
        if (r < 0 && errno != EINTR) { wl_display_cancel_read(g.display); break; }
        if (r > 0 && (fds[0].revents & POLLIN)) {
            if (wl_display_read_events(g.display) < 0) break;
        } else {
            wl_display_cancel_read(g.display);
        }
        if (r > 0 && (fds[0].revents & (POLLERR | POLLHUP))) break;
        if (wl_display_dispatch_pending(g.display) < 0) break;

        if (r > 0 && (fds[1].revents & POLLIN)) {
            uint64_t n = 0;
            (void)!read(g.event_fd, &n, sizeof(n));
            const int fp = g.fp_result.exchange(0);
            if (fp == -1) g.fp_miss_until = std::chrono::steady_clock::now() + std::chrono::seconds(2);
            const int result = fp == 1 ? 1 : g.pam_result.exchange(0);
            if (result == 0) {
                draw_all();   // the fingerprint line changed
            } else if (result == 1 && g.locked) {
                ext_session_lock_v1_unlock_and_destroy(g.lock);
                g.lock = nullptr;
                wl_display_roundtrip(g.display);
                g.unlocked = true;
            } else {
                g.status = result == -1 ? Status::Denied : Status::Unavailable;
                draw_all();
            }
        }
        if (r > 0 && (fds[2].revents & POLLIN)) {
            uint64_t n = 0;
            (void)!read(tfd, &n, sizeof(n));
            // The "not recognised" line goes after its two seconds.
            if (g.fp_miss_until != std::chrono::steady_clock::time_point{}
                && std::chrono::steady_clock::now() >= g.fp_miss_until) {
                g.fp_miss_until = {};
                draw_all();
            }
            const std::string now = clock_text();
            bool redraw = now != shown_clock;
            shown_clock = now;
            // The battery and the weather, every half a minute.
            if (++ticks % 30 == 0) {
                const std::string battery = g.battery, temp = g.weather_temp;
                const bool charging = g.charging;
                read_battery();
                read_weather();
                redraw = redraw || battery != g.battery || charging != g.charging || temp != g.weather_temp;
            }
            if (redraw) draw_all();
        }
    }

    if (g.unlocked) write_state("unlocked");
    wl_display_flush(g.display);
    wl_display_disconnect(g.display);
    return g.unlocked ? 0 : 1;
}
