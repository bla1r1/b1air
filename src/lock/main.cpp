// b1air-lock — the lock screen when the shell's own (Lock.qml) cannot run:
// Quickshell missing or broken, the QML not found. It was swaylock, with
// two dozen colour flags to make it look like the desktop.
//
//   b1air-lock
//
// Every screen shows its own wallpaper, blurred and darkened, the time, the
// date and the password field — one password, the same on every screen. The
// password is checked through PAM (the "b1air-lock"
// service if /etc/pam.d has one, else "login") on a thread of its own, so
// the screen keeps drawing while it is checked.
//
// The session's idle thread is told the lock is up and when it is opened
// ($XDG_RUNTIME_DIR/b1air/lock-state), as Lock.qml tells it: other screens
// dark while locked, the dim on lock, the lock before sleep.
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
#include <poll.h>
#include <pwd.h>
#include <security/pam_appl.h>
#include <string>
#include <sys/eventfd.h>
#include <sys/mman.h>
#include <sys/timerfd.h>
#include <thread>
#include <unistd.h>
#include <vector>
#include <wayland-client.h>
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
};

struct App {
    struct wl_display* display = nullptr;
    struct wl_compositor* compositor = nullptr;
    struct wl_shm* shm = nullptr;
    struct wl_seat* seat = nullptr;
    struct wl_keyboard* keyboard = nullptr;
    struct ext_session_lock_manager_v1* manager = nullptr;
    struct ext_session_lock_v1* lock = nullptr;
    std::vector<Output*> outputs;

    struct xkb_context* xkb = nullptr;
    struct xkb_keymap* keymap = nullptr;
    struct xkb_state* xkb_state = nullptr;

    std::string password;
    Status status = Status::Idle;
    bool caps = false;
    bool locked = false;
    bool finished = false;   // the compositor refused, or it is over
    bool unlocked = false;

    std::string user;
    std::string lang;
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
    const char* days[7];
    const char* months[12];
};

const Words kEn = {"Enter password", "Checking…", "Access denied", "Authentication unavailable", "Caps Lock is on",
                   "Or touch the fingerprint reader", "Fingerprint not recognised",
                   {"Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"},
                   {"January", "February", "March", "April", "May", "June", "July", "August", "September",
                    "October", "November", "December"}};
const Words kUk = {"Введіть пароль", "Перевірка…", "Доступ заборонено", "Автентифікація недоступна",
                   "Увімкнено Caps Lock", "Або прикладіть палець", "Відбиток не розпізнано",
                   {"неділя", "понеділок", "вівторок", "середа", "четвер", "пʼятниця", "субота"},
                   {"січня", "лютого", "березня", "квітня", "травня", "червня", "липня", "серпня", "вересня",
                    "жовтня", "листопада", "грудня"}};
const Words kRu = {"Введите пароль", "Проверка…", "Доступ запрещён", "Аутентификация недоступна",
                   "Включён Caps Lock", "Или приложите палец", "Отпечаток не распознан",
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

void centred_text(cairo_t* cr, const std::string& text, double cx, double y, double size, bool bold) {
    cairo_select_font_face(cr, "JetBrains Mono", CAIRO_FONT_SLANT_NORMAL,
                           bold ? CAIRO_FONT_WEIGHT_BOLD : CAIRO_FONT_WEIGHT_NORMAL);
    cairo_set_font_size(cr, size);
    cairo_text_extents_t e;
    cairo_text_extents(cr, text.c_str(), &e);
    cairo_move_to(cr, cx - e.width / 2 - e.x_bearing, y);
    cairo_show_text(cr, text.c_str());
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
    cairo_set_source_rgb(cr, 0x1a / 255.0, 0x1b / 255.0, 0x26 / 255.0);
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

    // The time and the date.
    cairo_set_source_rgba(cr, 0.95, 0.96, 1.0, 0.95);
    centred_text(cr, clock_text(), cx, cy - 90 * u, 150 * u, true);
    cairo_set_source_rgba(cr, 0.85, 0.87, 0.95, 0.85);
    centred_text(cr, date_text(), cx, cy - 40 * u, 24 * u, false);

    // The account, the field, and what is going on.
    centred_text(cr, g.user, cx, cy + 40 * u, 26 * u, true);
    const double fw = 360 * u, fh = 56 * u, fx = cx - fw / 2, fy = cy + 64 * u;
    const bool denied = g.status == Status::Denied || g.status == Status::Unavailable;
    rounded(cr, fx, fy, fw, fh, fh / 2);
    cairo_set_source_rgba(cr, 0.10, 0.11, 0.16, 0.65);
    cairo_fill_preserve(cr);
    if (denied) cairo_set_source_rgba(cr, 0.97, 0.46, 0.56, 0.9);
    else if (g.status == Status::Checking) cairo_set_source_rgba(cr, 0.88, 0.69, 0.41, 0.9);
    else cairo_set_source_rgba(cr, 0.48, 0.64, 0.97, g.password.empty() ? 0.35 : 0.9);
    cairo_set_line_width(cr, 2 * u);
    cairo_stroke(cr);

    // A dot a character (counted as UTF-8 code points), as many as fit.
    size_t chars = 0;
    for (unsigned char c : g.password)
        if ((c & 0xC0) != 0x80) ++chars;
    const size_t shown = std::min<size_t>(chars, 20);
    const double gap = 16 * u, r = 5 * u;
    double x = cx - (static_cast<double>(shown) - 1) * gap / 2;
    cairo_set_source_rgba(cr, 0.95, 0.96, 1.0, 0.95);
    for (size_t i = 0; i < shown; ++i, x += gap) {
        cairo_arc(cr, x, fy + fh / 2, r, 0, 2 * M_PI);
        cairo_fill(cr);
    }

    const Words& wd = words();
    std::string line = g.status == Status::Checking ? wd.checking
                     : g.status == Status::Denied ? wd.denied
                     : g.status == Status::Unavailable ? wd.unavailable
                     : wd.enter;
    if (denied) cairo_set_source_rgba(cr, 0.97, 0.46, 0.56, 0.95);
    else cairo_set_source_rgba(cr, 0.85, 0.87, 0.95, 0.75);
    centred_text(cr, line, cx, fy + fh + 36 * u, 18 * u, false);
    double below = fy + fh + 64 * u;
    if (g.caps) {
        cairo_set_source_rgba(cr, 0.88, 0.69, 0.41, 0.95);
        centred_text(cr, wd.caps, cx, below, 16 * u, false);
        below += 26 * u;
    }
    const bool miss = std::chrono::steady_clock::now() < g.fp_miss_until;
    if (g.fp_listening || miss) {
        if (miss) cairo_set_source_rgba(cr, 0.97, 0.46, 0.56, 0.95);
        else cairo_set_source_rgba(cr, 0.48, 0.64, 0.97, 0.9);
        centred_text(cr, miss ? wd.finger_miss : wd.finger, cx, below, 16 * u, false);
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
    draw_all();
}

void kb_modifiers(void*, struct wl_keyboard*, uint32_t, uint32_t depressed, uint32_t latched, uint32_t locked,
                  uint32_t group) {
    if (!g.xkb_state) return;
    xkb_state_update_mask(g.xkb_state, depressed, latched, locked, 0, 0, group);
    const bool caps = xkb_state_mod_name_is_active(g.xkb_state, XKB_MOD_NAME_CAPS, XKB_STATE_MODS_LOCKED) > 0;
    if (caps != g.caps) {
        g.caps = caps;
        draw_all();
    }
}

void kb_repeat(void*, struct wl_keyboard*, int32_t, int32_t) {}

const struct wl_keyboard_listener kKeyboard = {kb_keymap, kb_enter, kb_leave, kb_key, kb_modifiers, kb_repeat};

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
    if (const passwd* pw = getpwuid(getuid())) g.user = pw->pw_name;
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

    g.lock = ext_session_lock_manager_v1_lock(g.manager);
    ext_session_lock_v1_add_listener(g.lock, &kLock, nullptr);
    for (auto* o : g.outputs) make_lock_surface(o);

    // Once a second: the clock (redrawn when the minute turns).
    const int tfd = timerfd_create(CLOCK_MONOTONIC, TFD_CLOEXEC | TFD_NONBLOCK);
    itimerspec every{{1, 0}, {1, 0}};
    timerfd_settime(tfd, 0, &every, nullptr);
    std::string shown_clock = clock_text();

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
            if (now != shown_clock) {
                shown_clock = now;
                draw_all();
            }
        }
    }

    if (g.unlocked) write_state("unlocked");
    wl_display_flush(g.display);
    wl_display_disconnect(g.display);
    return g.unlocked ? 0 : 1;
}
