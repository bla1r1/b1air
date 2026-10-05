// b1air-shot — choosing what to capture: a region to take a picture of or to
// record, or to read QR codes from. It was ScreenshotOverlay.qml, a whole
// Quickshell process with a QML engine started on every press of Print.
//
//   b1air-shot [--edit]      --edit: Enter opens the picture in the editor
//
// One layer-shell surface over the focused screen, drawn with cairo:
//   - drag to select; drag an edge or a corner to resize, Shift-drag to move;
//     the last selection comes back (~/.cache/qs_screenshot_geom);
//   - a toolbar beside the selection: picture or video, Capture, edit, QR,
//     whole screen, close; for video, the desktop sound and the microphone
//     (mute, level, which microphone) and Record;
//   - QR: the codes found are framed and offered to copy or, for a link,
//     to open.
// Enter captures, Tab switches picture and video, Escape or a right click
// leaves. The capture itself is the daemon's (`b1air-daemon capture`,
// `record toggle`), started once this surface is gone from the screen.

#include <algorithm>
#include <cairo.h>
#include <cerrno>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fcntl.h>
#include <fstream>
#include <nlohmann/json.hpp>
#include <poll.h>
#include <sstream>
#include <string>
#include <sys/mman.h>
#include <sys/wait.h>
#include <thread>
#include <unistd.h>
#include <vector>
#include <wayland-client.h>
#include <wayland-cursor.h>
#include <xkbcommon/xkbcommon.h>

#include "i18n.hpp"
#include "palette.hpp"
#include "runtime.hpp"
#include "sway_ipc.hpp"
#include "system_control.hpp"
// The protocol names an argument `namespace`, which C++ reserves.
#define namespace namespace_
#include "wlr-layer-shell-unstable-v1-client-protocol.h"
#undef namespace

namespace {

using b1air::Colour;

struct Rect {
    double x = 0, y = 0, w = 0, h = 0;
    bool contains(double px, double py) const { return w > 0 && px >= x && px < x + w && py >= y && py < y + h; }
};

// What a press on the selection does: draw a new one, move it, or pull one
// of its edges or corners.
enum Mode { New = 1, Move = 2, TopLeft = 3, Top = 4, TopRight = 5, Left = 6, Right = 7, BottomLeft = 8, Bottom = 9, BottomRight = 10 };

enum class Button {
    None, Photo, Video, Capture, Record, Edit, Qr, Maximize, Close,
    DeskMute, DeskSlider, MicMute, MicSlider, MicList, MicItem, QrCopy, QrOpen, QrClose
};

struct Hit {
    Rect r;
    Button b;
    int index = 0;   // which microphone, which QR result
};

struct Mic {
    std::string name, description;
};

struct QrResult {
    Rect box;          // where the code is, on this surface
    std::string text;
    bool found = false;
};

struct Output {
    struct wl_output* output = nullptr;
    std::string name;
    int32_t scale = 1;
};

struct App {
    struct wl_display* display = nullptr;
    struct wl_compositor* compositor = nullptr;
    struct wl_shm* shm = nullptr;
    struct wl_seat* seat = nullptr;
    struct zwlr_layer_shell_v1* layer_shell = nullptr;
    std::vector<Output*> outputs;

    struct wl_surface* surface = nullptr;
    struct zwlr_layer_surface_v1* layer = nullptr;
    Output* on = nullptr;
    int width = 0, height = 0;
    bool configured = false;
    bool done = false;

    struct wl_keyboard* keyboard = nullptr;
    struct xkb_context* xkb = nullptr;
    struct xkb_state* xkb_state = nullptr;
    bool shift = false;

    struct wl_pointer* pointer = nullptr;
    uint32_t pointer_serial = 0;
    struct wl_cursor_theme* cursor_theme = nullptr;
    struct wl_surface* cursor_surface = nullptr;
    std::string cursor_name;
    double px = 0, py = 0;

    // The screen's place in the layout, for the daemon's global geometry.
    int offset_x = 0, offset_y = 0;

    // Selection, in surface coordinates.
    double start_x = 0, start_y = 0, end_x = 0, end_y = 0;
    bool has_selection = false, selecting = false, maximized = false;
    double pre[4] = {0, 0, 0, 0};       // before "whole screen" or video
    int mode = New;
    double anchor_x = 0, anchor_y = 0, init[4] = {0, 0, 0, 0};

    bool edit = false;
    bool video = false;
    double desk_vol = 1.0, mic_vol = 1.0;
    bool desk_mute = false, mic_mute = false;
    std::string mic_device;
    std::vector<Mic> mics;
    bool mic_list_open = false;
    Button dragging_slider = Button::None;

    std::vector<QrResult> qr;
    bool qr_shown = false;

    std::vector<Hit> hits;
    b1air::Palette pal;
    b1air::I18n tr;
} g;

double sel_x() { return std::min(g.start_x, g.end_x); }
double sel_y() { return std::min(g.start_y, g.end_y); }
double sel_w() { return std::fabs(g.end_x - g.start_x); }
double sel_h() { return std::fabs(g.end_y - g.start_y); }

std::string geometry() {
    char buf[96];
    std::snprintf(buf, sizeof(buf), "%ld,%ld %ldx%ld", std::lround(sel_x()) + g.offset_x, std::lround(sel_y()) + g.offset_y,
                  std::lround(sel_w()), std::lround(sel_h()));
    return buf;
}

// ── Remembered between runs ──────────────────────────────────────────────────

std::string cache(const char* name) { return b1air::home_dir() + "/.cache/" + name; }

std::string read_all(const std::string& path) {
    std::ifstream in(path);
    std::stringstream ss;
    ss << in.rdbuf();
    return ss.str();
}

void write_all(const std::string& path, const std::string& text) {
    std::ofstream out(path, std::ios::trunc);
    out << text;
}

void load_state() {
    double x = 0, y = 0, w = 0, h = 0;
    if (std::sscanf(read_all(cache("qs_screenshot_geom")).c_str(), "%lf,%lf,%lf,%lf", &x, &y, &w, &h) == 4 && w > 10 && h > 10) {
        g.start_x = x, g.start_y = y, g.end_x = x + w, g.end_y = y + h;
        g.has_selection = true;
    }
    g.video = read_all(cache("qs_screenshot_mode")).rfind("true", 0) == 0;
    // desk volume, desk muted, mic volume, mic muted, mic device
    std::stringstream ss(read_all(cache("qs_audio_prefs")));
    std::string f[5];
    for (auto& s : f) std::getline(ss, s, ',');
    if (!f[0].empty()) g.desk_vol = std::clamp(std::atof(f[0].c_str()), 0.0, 1.0);
    g.desk_mute = f[1] == "true";
    if (!f[2].empty()) g.mic_vol = std::clamp(std::atof(f[2].c_str()), 0.0, 1.0);
    g.mic_mute = f[3] == "true";
    g.mic_device = f[4];
    while (!g.mic_device.empty() && std::isspace(static_cast<unsigned char>(g.mic_device.back()))) g.mic_device.pop_back();
}

void save_selection() {
    if (!g.has_selection || g.video) return;
    char buf[96];
    std::snprintf(buf, sizeof(buf), "%ld,%ld,%ld,%ld", std::lround(sel_x()), std::lround(sel_y()), std::lround(sel_w()),
                  std::lround(sel_h()));
    write_all(cache("qs_screenshot_geom"), buf);
}

void save_audio() {
    char buf[64];
    std::snprintf(buf, sizeof(buf), "%.2f,%s,%.2f,%s,", g.desk_vol, g.desk_mute ? "true" : "false", g.mic_vol,
                  g.mic_mute ? "true" : "false");
    write_all(cache("qs_audio_prefs"), buf + g.mic_device);
}

// ── Running things ───────────────────────────────────────────────────────────

std::string capture_output(const std::vector<std::string>& argv) {
    int fds[2];
    if (pipe2(fds, O_CLOEXEC) != 0) return {};
    const pid_t pid = fork();
    if (pid == 0) {
        dup2(fds[1], STDOUT_FILENO);
        const int null_fd = open("/dev/null", O_WRONLY);
        if (null_fd >= 0) dup2(null_fd, STDERR_FILENO);
        std::vector<char*> args;
        for (const auto& a : argv) args.push_back(const_cast<char*>(a.c_str()));
        args.push_back(nullptr);
        execvp(args[0], args.data());
        _exit(127);
    }
    close(fds[1]);
    std::string out;
    char buf[4096];
    ssize_t n;
    while ((n = read(fds[0], buf, sizeof(buf))) > 0) out.append(buf, static_cast<size_t>(n));
    close(fds[0]);
    if (pid > 0) waitpid(pid, nullptr, 0);
    return out;
}

void run_detached(const std::vector<std::string>& argv) {
    const pid_t pid = fork();
    if (pid == 0) {
        setsid();
        if (fork() == 0) {
            const int null_fd = open("/dev/null", O_RDWR);
            if (null_fd >= 0) dup2(null_fd, STDIN_FILENO), dup2(null_fd, STDOUT_FILENO), dup2(null_fd, STDERR_FILENO);
            std::vector<char*> args;
            for (const auto& a : argv) args.push_back(const_cast<char*>(a.c_str()));
            args.push_back(nullptr);
            execvp(args[0], args.data());
            _exit(127);
        }
        _exit(0);
    }
    if (pid > 0) waitpid(pid, nullptr, 0);
}

// The microphones PulseAudio's interface (pipewire-pulse) knows, without
// the monitors of the outputs.
void load_mics() {
    std::stringstream ss(capture_output({"pactl", "list", "sources"}));
    std::string line;
    Mic cur;
    const auto push = [&] {
        if (!cur.name.empty() && cur.name.size() > 8 && cur.name.compare(cur.name.size() - 8, 8, ".monitor") == 0) cur = {};
        if (!cur.name.empty()) g.mics.push_back(cur);
        cur = {};
    };
    while (std::getline(ss, line)) {
        const auto start = line.find_first_not_of(" \t");
        if (start == std::string::npos) continue;
        line = line.substr(start);
        if (line.rfind("Source #", 0) == 0) push();
        else if (line.rfind("Name: ", 0) == 0) cur.name = line.substr(6);
        else if (line.rfind("Description: ", 0) == 0) cur.description = line.substr(13);
    }
    push();
    if (g.mic_device.empty() && !g.mics.empty()) {
        g.mic_device = g.mics.front().name;
        save_audio();
    }
}

// ── Drawing ──────────────────────────────────────────────────────────────────

constexpr const char* kFont = "Fira Sans";
constexpr const char* kIconFont = "JetBrainsMono Nerd Font Mono";

void set(cairo_t* cr, const Colour& c, double a = 1.0) { cairo_set_source_rgba(cr, c.r, c.g, c.b, a); }

void font(cairo_t* cr, double size, bool bold, bool icon = false) {
    cairo_select_font_face(cr, icon ? kIconFont : kFont, CAIRO_FONT_SLANT_NORMAL,
                           bold ? CAIRO_FONT_WEIGHT_BOLD : CAIRO_FONT_WEIGHT_NORMAL);
    cairo_set_font_size(cr, size);
}

double text_width(cairo_t* cr, const std::string& s) {
    cairo_text_extents_t e;
    cairo_text_extents(cr, s.c_str(), &e);
    return e.x_advance;
}

void rounded(cairo_t* cr, const Rect& r, double radius) {
    radius = std::min(radius, std::min(r.w, r.h) / 2);
    cairo_new_sub_path(cr);
    cairo_arc(cr, r.x + r.w - radius, r.y + radius, radius, -M_PI / 2, 0);
    cairo_arc(cr, r.x + r.w - radius, r.y + r.h - radius, radius, 0, M_PI / 2);
    cairo_arc(cr, r.x + radius, r.y + r.h - radius, radius, M_PI / 2, M_PI);
    cairo_arc(cr, r.x + radius, r.y + radius, radius, M_PI, 3 * M_PI / 2);
    cairo_close_path(cr);
}

// Text centred in a box both ways.
void boxed(cairo_t* cr, const std::string& s, const Rect& r) {
    cairo_font_extents_t fe;
    cairo_font_extents(cr, &fe);
    cairo_move_to(cr, r.x + (r.w - text_width(cr, s)) / 2, r.y + (r.h + fe.ascent - fe.descent) / 2);
    cairo_show_text(cr, s.c_str());
    cairo_new_path(cr);
}

bool hovered(const Rect& r) { return r.contains(g.px, g.py); }

// A round button: an icon, and a word after it if there is one.
double button_width(cairo_t* cr, const std::string& label) {
    if (label.empty()) return 36;
    font(cr, 13, true);
    return 36 + 6 + text_width(cr, label);
}

void button(cairo_t* cr, double x, double y, const std::string& icon, const std::string& label, bool danger, Button b,
            int index = 0) {
    const Rect r{x, y, button_width(cr, label), 36};
    if (hovered(r)) {
        rounded(cr, r, 18);
        if (danger) set(cr, g.pal.error, 0.2);
        else set(cr, g.pal.high);
        cairo_fill(cr);
    }
    const Colour& ink = danger ? g.pal.error : g.pal.text;
    set(cr, ink);
    font(cr, 18, false, true);
    if (label.empty()) {
        boxed(cr, icon, r);
    } else {
        const double iw = text_width(cr, icon);
        font(cr, 13, true);
        const double tw = text_width(cr, label);
        const double left = r.x + (r.w - iw - 6 - tw) / 2;
        font(cr, 18, false, true);
        boxed(cr, icon, {left, r.y, iw, r.h});
        font(cr, 13, true);
        boxed(cr, label, {left + iw + 6, r.y, tw, r.h});
    }
    g.hits.push_back({r, b, index});
}

void separator(cairo_t* cr, double x, double y) {
    set(cr, g.pal.mid);
    cairo_rectangle(cr, x, y + 10, 2, 32);
    cairo_fill(cr);
}

// Mute icon, a level slider, and for the microphone the list arrow.
double audio_width(bool dropdown) { return 30 + 4 + 60 + (dropdown ? 4 + 20 : 0); }

void audio(cairo_t* cr, double x, double y, const char* on, const char* off, double value, bool muted, Button mute,
           Button slider, bool dropdown, bool up) {
    const Rect icon{x, y + 11, 30, 30};
    if (hovered(icon)) {
        cairo_arc(cr, icon.x + 15, icon.y + 15, 15, 0, 2 * M_PI);
        set(cr, g.pal.high);
        cairo_fill(cr);
    }
    set(cr, muted ? g.pal.error : g.pal.text);
    font(cr, 16, false, true);
    boxed(cr, muted ? off : on, icon);
    g.hits.push_back({icon, mute});

    const Rect track{x + 34, y + 24, 60, 4};
    const Colour& fill = muted ? g.pal.dim : g.pal.tertiary;
    rounded(cr, track, 2);
    set(cr, g.pal.high);
    cairo_fill(cr);
    rounded(cr, {track.x, track.y, track.w * value, track.h}, 2);
    set(cr, fill);
    cairo_fill(cr);
    cairo_arc(cr, track.x + track.w * value, track.y + 2, 6, 0, 2 * M_PI);
    cairo_fill(cr);
    g.hits.push_back({{track.x - 6, y + 12, track.w + 12, 28}, slider});

    if (dropdown) {
        const Rect arrow{x + 98, y + 11, 20, 30};
        set(cr, g.pal.text);
        font(cr, 16, false, true);
        boxed(cr, up ? "󰅃" : "󰅀", arrow);
        g.hits.push_back({arrow, Button::MicList});
    }
}

void draw_toolbar(cairo_t* cr) {
    const auto& tr = g.tr;
    // What is on it, left to right, to measure first.
    const double seg = 80, gap = 8;
    double w = 8 + seg + gap + 2 + gap;
    if (g.video) {
        w += audio_width(false) + gap + audio_width(true) + gap + 2 + gap + button_width(cr, tr("Record")) + gap + 36;
    } else {
        w += button_width(cr, tr("Capture")) + gap + 36 + gap + 36 + gap + 2 + gap + 36 + gap + 36;
    }
    w += 8;
    const double h = 52;
    const double sx = sel_x(), sy = sel_y(), sw = sel_w(), sh = sel_h();
    const bool below = sy + sh + h + 15 <= g.height;
    const bool above = sy - h - 15 >= 0;
    const bool inside = sh >= h + 30 && sw >= w + 20;
    if (!below && !above && !inside) return;
    const double x = std::max(10.0, std::min(g.width - w - 10.0, sx + sw / 2 - w / 2));
    const double y = below ? sy + sh + 15 : above ? sy - h - 15 : sy + sh - h - 15;
    const Rect bar{x, y, w, h};
    rounded(cr, bar, 26);
    set(cr, g.pal.low);
    cairo_fill_preserve(cr);
    set(cr, g.pal.high);
    cairo_set_line_width(cr, 2);
    cairo_stroke(cr);

    double cx = x + 8;
    // Picture | video.
    const Rect segr{cx, y + 8, seg, 36};
    rounded(cr, segr, 18);
    set(cr, g.pal.mid);
    cairo_fill(cr);
    const Rect photo{cx + 4, y + 12, seg / 2 - 4, 28}, video{cx + seg / 2, y + 12, seg / 2 - 4, 28};
    rounded(cr, g.video ? video : photo, 14);
    set(cr, g.pal.high);
    cairo_fill(cr);
    font(cr, 16, false, true);
    set(cr, g.video ? g.pal.dim : g.pal.text);
    boxed(cr, "󰄄", photo);
    set(cr, g.video ? g.pal.text : g.pal.dim);
    boxed(cr, "󰕧", video);
    g.hits.push_back({photo, Button::Photo});
    g.hits.push_back({video, Button::Video});
    cx += seg + gap;
    separator(cr, cx, y);
    cx += 2 + gap;

    const bool up = y + 200 > g.height;
    if (g.video) {
        audio(cr, cx, y, "󰓃", "󰓄", g.desk_vol, g.desk_mute, Button::DeskMute, Button::DeskSlider, false, up);
        cx += audio_width(false) + gap;
        const double mic_x = cx;
        audio(cr, cx, y, "󰍬", "󰍭", g.mic_vol, g.mic_mute, Button::MicMute, Button::MicSlider, true, up);
        cx += audio_width(true) + gap;
        separator(cr, cx, y);
        cx += 2 + gap;
        button(cr, cx, y + 8, "󰑊", tr("Record"), true, Button::Record);
        cx += button_width(cr, tr("Record")) + gap;
        button(cr, cx, y + 8, "󰅖", "", true, Button::Close);

        if (g.mic_list_open) {
            const double lw = 280;
            const double row = 32;
            const double lh = g.mics.empty() ? 40 : std::min(180.0, g.mics.size() * (row + 4) + 4);
            const Rect list{std::max(10.0, std::min(g.width - lw - 10.0, mic_x - 40)), up ? y - lh - 8 : y + h + 8, lw, lh};
            rounded(cr, list, 8);
            set(cr, g.pal.low);
            cairo_fill_preserve(cr);
            set(cr, g.pal.high);
            cairo_set_line_width(cr, 2);
            cairo_stroke(cr);
            g.hits.push_back({list, Button::None});   // a click on its padding is not a click elsewhere
            if (g.mics.empty()) {
                set(cr, g.pal.dim);
                font(cr, 12, false);
                boxed(cr, tr("No Microphones (Install pulseaudio)"), list);
            }
            double ry = list.y + 4;
            for (size_t i = 0; i < g.mics.size() && ry + row <= list.y + list.h; ++i, ry += row + 4) {
                const Rect r{list.x + 4, ry, list.w - 8, row};
                if (hovered(r)) {
                    rounded(cr, r, 6);
                    set(cr, g.pal.mid);
                    cairo_fill(cr);
                }
                cairo_save(cr);
                cairo_rectangle(cr, r.x + 6, r.y, r.w - 12, r.h);
                cairo_clip(cr);
                set(cr, g.mics[i].name == g.mic_device ? g.pal.tertiary : g.pal.text);
                font(cr, 12, false);
                cairo_font_extents_t fe;
                cairo_font_extents(cr, &fe);
                cairo_move_to(cr, r.x + 6, r.y + (r.h + fe.ascent - fe.descent) / 2);
                cairo_show_text(cr, (g.mics[i].description.empty() ? g.mics[i].name : g.mics[i].description).c_str());
                cairo_restore(cr);
                cairo_new_path(cr);
                g.hits.push_back({r, Button::MicItem, static_cast<int>(i)});
            }
        }
    } else {
        button(cr, cx, y + 8, "󰄄", tr("Capture"), false, Button::Capture);
        cx += button_width(cr, tr("Capture")) + gap;
        button(cr, cx, y + 8, "󰏫", "", false, Button::Edit);
        cx += 36 + gap;
        button(cr, cx, y + 8, "󰐲", "", false, Button::Qr);
        cx += 36 + gap;
        separator(cr, cx, y);
        cx += 2 + gap;
        button(cr, cx, y + 8, g.maximized ? "󰊔" : "󰊓", "", false, Button::Maximize);
        cx += 36 + gap;
        button(cr, cx, y + 8, "󰅖", "", true, Button::Close);
    }
}

void draw_qr(cairo_t* cr) {
    const auto& tr = g.tr;
    for (size_t i = 0; i < g.qr.size(); ++i) {
        const QrResult& q = g.qr[i];
        if (q.found && q.box.w > 0) {
            const Rect b{q.box.x - 5, q.box.y - 5, q.box.w + 10, q.box.h + 10};
            rounded(cr, b, 8);
            set(cr, g.pal.ok, 0.25);
            cairo_fill_preserve(cr);
            set(cr, g.pal.ok);
            cairo_set_line_width(cr, 3);
            cairo_stroke(cr);
        }
        // The pill: the text, copy, open for a link, close.
        std::string text = q.found ? q.text : tr("No QR code found.");
        font(cr, 13, true);
        while (text.size() > 4 && text_width(cr, text) > 400) {
            size_t cut = text.size() - 1;
            while (cut > 0 && (static_cast<unsigned char>(text[cut]) & 0xC0) == 0x80) --cut;
            text = text.substr(0, cut);
            if (text_width(cr, text + "…") <= 400) { text += "…"; break; }
        }
        const bool link = q.found && (q.text.rfind("http://", 0) == 0 || q.text.rfind("https://", 0) == 0);
        const double tw = text_width(cr, text);
        double pw = 16 + 8 + tw + 8 + 2 + 8 + 36 + 16;
        if (q.found) pw += 2 + 8 + 36 + 8 + (link ? 36 + 8 : 0);
        const double ph = 52;
        const double cx = q.box.w > 0 ? q.box.x + q.box.w / 2 : sel_x() + sel_w() / 2;
        const double top = q.box.w > 0 ? q.box.y : sel_y() + sel_h() / 2;
        const bool fits_top = top - ph - 15 >= sel_y();
        const double x = std::max(10.0, std::min(g.width - pw - 10.0, cx - pw / 2));
        const double y = q.box.w > 0 ? (fits_top ? top - ph - 15 : top + q.box.h + 15) : top;
        const Rect pill{x, y, pw, ph};
        rounded(cr, pill, 26);
        set(cr, g.pal.low);
        cairo_fill_preserve(cr);
        set(cr, q.found ? g.pal.ok : g.pal.error);
        cairo_set_line_width(cr, 2);
        cairo_stroke(cr);
        g.hits.push_back({pill, Button::None, static_cast<int>(i)});
        double px = x + 24;
        set(cr, q.found ? g.pal.text : g.pal.error);
        font(cr, 13, true);
        boxed(cr, text, {px, y, tw, ph});
        px += tw + 8;
        if (q.found) {
            separator(cr, px, y);
            px += 2 + 8;
            button(cr, px, y + 8, "󰆏", "", false, Button::QrCopy, static_cast<int>(i));
            px += 36 + 8;
            if (link) {
                button(cr, px, y + 8, "󰌹", "", false, Button::QrOpen, static_cast<int>(i));
                px += 36 + 8;
            }
        }
        separator(cr, px, y);
        px += 2 + 8;
        button(cr, px, y + 8, "󰅖", "", true, Button::QrClose, static_cast<int>(i));
    }
}

void buffer_release(void*, struct wl_buffer* buffer) { wl_buffer_destroy(buffer); }
const struct wl_buffer_listener kBufferListener = {buffer_release};

void draw() {
    if (!g.configured || g.width <= 0 || g.height <= 0 || g.done) return;
    const int scale = std::max(1, g.on ? g.on->scale : 1);
    const int w = g.width * scale, h = g.height * scale, stride = w * 4;
    const size_t size = static_cast<size_t>(stride) * h;
    const int fd = memfd_create("b1air-shot", MFD_CLOEXEC);
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
        cairo_image_surface_create_for_data(static_cast<unsigned char*>(data), CAIRO_FORMAT_ARGB32, w, h, stride);
    cairo_t* cr = cairo_create(target);
    cairo_scale(cr, scale, scale);
    g.hits.clear();
    const auto& p = g.pal;
    const double W = g.width, H = g.height;
    const bool shown = g.selecting || g.has_selection;

    // The dim, with the selection cut out of it.
    cairo_set_operator(cr, CAIRO_OPERATOR_SOURCE);
    cairo_set_fill_rule(cr, CAIRO_FILL_RULE_EVEN_ODD);
    cairo_rectangle(cr, 0, 0, W, H);
    if (shown) cairo_rectangle(cr, sel_x(), sel_y(), sel_w(), sel_h());
    set(cr, p.ground, 0.5);
    cairo_fill(cr);
    cairo_set_fill_rule(cr, CAIRO_FILL_RULE_WINDING);
    if (shown) {
        cairo_rectangle(cr, sel_x(), sel_y(), sel_w(), sel_h());
        cairo_set_source_rgba(cr, 0, 0, 0, 0);
        cairo_fill(cr);
    }
    cairo_set_operator(cr, CAIRO_OPERATOR_OVER);

    if (!shown) {
        set(cr, p.text);
        font(cr, 24, true);
        boxed(cr, g.video ? g.tr("Click Record (Portal handles area selection)") : g.tr("Select region to capture"),
              {0, 0, W, H});
    } else {
        const bool qr_ok = g.qr_shown && std::any_of(g.qr.begin(), g.qr.end(), [](const QrResult& q) { return q.found; });
        const Colour& edge = qr_ok ? p.ok : g.video ? p.error : p.tertiary;
        cairo_rectangle(cr, sel_x(), sel_y(), sel_w(), sel_h());
        set(cr, edge, qr_ok ? 0.15 : 0.05);
        cairo_fill_preserve(cr);
        set(cr, edge);
        cairo_set_line_width(cr, 4);
        cairo_stroke(cr);
        if (!g.video && !g.qr_shown) {
            for (int i = 0; i < 4; ++i) {
                const double hx = i % 2 ? sel_x() + sel_w() : sel_x(), hy = i / 2 ? sel_y() + sel_h() : sel_y();
                cairo_arc(cr, hx, hy, 10, 0, 2 * M_PI);
                set(cr, p.text);
                cairo_fill_preserve(cr);
                set(cr, p.tertiary);
                cairo_set_line_width(cr, 4);
                cairo_stroke(cr);
            }
        }
        if (g.qr_shown && !g.selecting) draw_qr(cr);
        else if (g.has_selection && !g.selecting) draw_toolbar(cr);
    }

    cairo_destroy(cr);
    cairo_surface_flush(target);
    cairo_surface_destroy(target);
    munmap(data, size);
    struct wl_shm_pool* pool = wl_shm_create_pool(g.shm, fd, static_cast<int32_t>(size));
    struct wl_buffer* buffer = wl_shm_pool_create_buffer(pool, 0, w, h, stride, WL_SHM_FORMAT_ARGB8888);
    wl_shm_pool_destroy(pool);
    close(fd);
    wl_buffer_add_listener(buffer, &kBufferListener, nullptr);
    wl_surface_set_buffer_scale(g.surface, scale);
    wl_surface_attach(g.surface, buffer, 0, 0);
    wl_surface_damage_buffer(g.surface, 0, 0, w, h);
    wl_surface_commit(g.surface);
}

// Off the screen, so that grim does not capture the dim and the toolbar: no
// buffer, and a moment for the compositor to draw a frame without it.
void hide() {
    wl_surface_attach(g.surface, nullptr, 0, 0);
    wl_surface_commit(g.surface);
    wl_display_roundtrip(g.display);
    std::this_thread::sleep_for(std::chrono::milliseconds(120));
}

// ── Doing ────────────────────────────────────────────────────────────────────

void set_video(bool on) {
    if (on == g.video) return;
    g.video = on;
    write_all(cache("qs_screenshot_mode"), on ? "true\n" : "false\n");
    if (on) {
        // The microphones, the first time they are wanted (pactl, a moment).
        static bool listed = false;
        if (!listed) listed = true, load_mics();
        // A recording is of the whole screen; the portal asks for the area.
        g.pre[0] = g.start_x, g.pre[1] = g.start_y, g.pre[2] = g.end_x, g.pre[3] = g.end_y;
        g.start_x = 0, g.start_y = 0, g.end_x = g.width, g.end_y = g.height;
        g.has_selection = true;
    } else {
        g.start_x = g.pre[0], g.start_y = g.pre[1], g.end_x = g.pre[2], g.end_y = g.pre[3];
        g.has_selection = sel_w() >= 10 && sel_h() >= 10;
        g.mic_list_open = false;
    }
}

void toggle_maximize() {
    if (g.video) return;
    if (!g.maximized) {
        g.pre[0] = g.start_x, g.pre[1] = g.start_y, g.pre[2] = g.end_x, g.pre[3] = g.end_y;
        g.start_x = 0, g.start_y = 0, g.end_x = g.width, g.end_y = g.height;
        g.maximized = true;
    } else {
        g.start_x = g.pre[0], g.start_y = g.pre[1], g.end_x = g.pre[2], g.end_y = g.pre[3];
        g.maximized = false;
    }
    g.has_selection = true;
    save_selection();
}

void capture(bool editor) {
    if (!g.has_selection) return;
    save_selection();
    const std::string geom = geometry();
    hide();
    std::vector<std::string> args = {"b1air-daemon", "capture", "--geometry", geom};
    if (editor) args.push_back("--edit");
    run_detached(args);
    g.done = true;
}

void record() {
    char dv[16], mv[16];
    std::snprintf(dv, sizeof(dv), "%.2f", g.desk_vol);
    std::snprintf(mv, sizeof(mv), "%.2f", g.mic_vol);
    const std::string geom = geometry();
    hide();
    std::vector<std::string> args = {"b1air-daemon", "record", "toggle", "--geometry", geom,
                                     "--desk-vol", dv, "--desk-mute", g.desk_mute ? "true" : "false",
                                     "--mic-vol", mv, "--mic-mute", g.mic_mute ? "true" : "false"};
    const bool safe = !g.mic_device.empty() && std::all_of(g.mic_device.begin(), g.mic_device.end(), [](char c) {
        return std::isalnum(static_cast<unsigned char>(c)) || std::strchr("_.:@-", c);
    });
    if (safe) args.insert(args.end(), {"--mic-dev", g.mic_device});
    run_detached(args);
    g.done = true;
}

// zbar's frame is in the picture's pixels, which are the screen's: the
// screen's scale over, to this surface's.
void scan_qr() {
    const std::string geom = geometry();
    hide();
    const std::string res = b1air::SystemControl::scan_qr(geom);
    g.qr.clear();
    const double s = std::max(1, g.on ? g.on->scale : 1);
    std::stringstream ss(res);
    std::string line;
    while (std::getline(ss, line)) {
        const auto sep = line.find("|||");
        if (sep == std::string::npos) continue;
        int x = 0, y = 0, w = 0, h = 0;
        if (std::sscanf(line.c_str(), "%d,%d,%d,%d", &x, &y, &w, &h) != 4) continue;
        std::string text = line.substr(sep + 3);
        QrResult q;
        q.found = !(text == "NOT_FOUND" || text.rfind("ERROR:", 0) == 0) && !text.empty();
        // The daemon writes newlines as "\n" and keeps zbar's "QR-Code:" off.
        for (size_t p = text.find("\\n"); p != std::string::npos; p = text.find("\\n", p + 1)) text.replace(p, 2, "\n");
        if (text.rfind("QR-Code:", 0) == 0) text = text.substr(8);
        q.text = text;
        if (q.found && w > 0) q.box = {sel_x() + x / s, sel_y() + y / s, w / s, h / s};
        g.qr.push_back(q);
    }
    if (g.qr.empty()) g.qr.push_back({});
    g.qr_shown = true;
    // Back on the screen: a layer surface that was unmapped is mapped again
    // by a commit with no buffer and the configure that answers it, which
    // draws (layer_configure).
    g.configured = false;
    wl_surface_commit(g.surface);
}

void press(Button b, int index) {
    switch (b) {
    case Button::Photo: set_video(false); break;
    case Button::Video: set_video(true); break;
    case Button::Capture: capture(false); break;
    case Button::Edit: capture(true); break;
    case Button::Record: record(); break;
    case Button::Qr: scan_qr(); break;
    case Button::Maximize: toggle_maximize(); break;
    case Button::Close: g.done = true; break;
    case Button::DeskMute: g.desk_mute = !g.desk_mute; save_audio(); break;
    case Button::MicMute: g.mic_mute = !g.mic_mute; save_audio(); break;
    case Button::MicList: g.mic_list_open = !g.mic_list_open; break;
    case Button::MicItem:
        g.mic_device = g.mics[static_cast<size_t>(index)].name;
        g.mic_list_open = false;
        save_audio();
        break;
    case Button::QrCopy: run_detached({"b1air-clip", "copy", "--", g.qr[static_cast<size_t>(index)].text}); g.qr_shown = false; break;
    case Button::QrOpen: run_detached({"xdg-open", g.qr[static_cast<size_t>(index)].text}); g.done = true; break;
    case Button::QrClose: g.qr_shown = false; break;
    default: break;
    }
}

void slide(Button which, double x) {
    for (const Hit& h : g.hits)
        if (h.b == which) {
            const double v = std::clamp((x - (h.r.x + 6)) / (h.r.w - 12), 0.0, 1.0);
            (which == Button::DeskSlider ? g.desk_vol : g.mic_vol) = v;
            return;
        }
}

int interaction_mode(double mx, double my) {
    if (!g.has_selection) return New;
    if (g.shift) return Move;
    const double m = 20, x = sel_x(), y = sel_y(), w = sel_w(), h = sel_h();
    const bool left = std::fabs(mx - x) <= m, right = std::fabs(mx - (x + w)) <= m;
    const bool top = std::fabs(my - y) <= m, bottom = std::fabs(my - (y + h)) <= m;
    const bool within_x = mx >= x - m && mx <= x + w + m, within_y = my >= y - m && my <= y + h + m;
    if (top && left) return TopLeft;
    if (top && right) return TopRight;
    if (bottom && left) return BottomLeft;
    if (bottom && right) return BottomRight;
    if (top && within_x) return Top;
    if (bottom && within_x) return Bottom;
    if (left && within_y) return Left;
    if (right && within_y) return Right;
    return New;
}

const Hit* hit_at(double x, double y) {
    for (auto it = g.hits.rbegin(); it != g.hits.rend(); ++it)
        if (it->r.contains(x, y)) return &*it;
    return nullptr;
}

// ── Cursor ───────────────────────────────────────────────────────────────────

void set_cursor(const std::string& name) {
    if (!g.pointer || !g.cursor_theme || name == g.cursor_name) return;
    // Names from the cursor spec, then the X11 ones older themes still have.
    static const std::vector<std::pair<std::string, std::vector<const char*>>> kNames = {
        {"crosshair", {"crosshair", "cross", "tcross"}},
        {"move", {"grabbing", "move", "fleur"}},
        {"nwse", {"nwse-resize", "size_fdiag", "bottom_right_corner"}},
        {"nesw", {"nesw-resize", "size_bdiag", "bottom_left_corner"}},
        {"ns", {"ns-resize", "size_ver", "sb_v_double_arrow"}},
        {"ew", {"ew-resize", "size_hor", "sb_h_double_arrow"}},
        {"pointer", {"pointer", "hand2", "hand1"}},
        {"default", {"default", "left_ptr"}},
    };
    struct wl_cursor* c = nullptr;
    for (const auto& [key, names] : kNames)
        if (key == name)
            for (const char* n : names)
                if (!c) c = wl_cursor_theme_get_cursor(g.cursor_theme, n);
    if (!c) c = wl_cursor_theme_get_cursor(g.cursor_theme, "left_ptr");
    if (!c || c->image_count == 0) return;
    struct wl_cursor_image* img = c->images[0];
    wl_surface_attach(g.cursor_surface, wl_cursor_image_get_buffer(img), 0, 0);
    wl_surface_damage_buffer(g.cursor_surface, 0, 0, static_cast<int32_t>(img->width), static_cast<int32_t>(img->height));
    wl_surface_commit(g.cursor_surface);
    wl_pointer_set_cursor(g.pointer, g.pointer_serial, g.cursor_surface, static_cast<int32_t>(img->hotspot_x),
                          static_cast<int32_t>(img->hotspot_y));
    g.cursor_name = name;
}

void update_cursor() {
    if (hit_at(g.px, g.py)) return set_cursor("pointer");
    if (g.video || g.qr_shown) return set_cursor("default");
    switch (g.selecting ? g.mode : interaction_mode(g.px, g.py)) {
    case Move: return set_cursor("move");
    case TopLeft: case BottomRight: return set_cursor("nwse");
    case TopRight: case BottomLeft: return set_cursor("nesw");
    case Top: case Bottom: return set_cursor("ns");
    case Left: case Right: return set_cursor("ew");
    default: return set_cursor("crosshair");
    }
}

// ── Pointer ──────────────────────────────────────────────────────────────────

void pt_enter(void*, struct wl_pointer*, uint32_t serial, struct wl_surface*, wl_fixed_t x, wl_fixed_t y) {
    g.pointer_serial = serial;
    g.cursor_name.clear();
    g.px = wl_fixed_to_double(x);
    g.py = wl_fixed_to_double(y);
    update_cursor();
}
void pt_leave(void*, struct wl_pointer*, uint32_t, struct wl_surface*) {}

void pt_motion(void*, struct wl_pointer*, uint32_t, wl_fixed_t fx, wl_fixed_t fy) {
    g.px = wl_fixed_to_double(fx);
    g.py = wl_fixed_to_double(fy);
    if (g.dragging_slider != Button::None) {
        slide(g.dragging_slider, g.px);
        draw();
        return;
    }
    update_cursor();
    if (!g.selecting) {
        draw();   // hover
        return;
    }
    const double W = g.width, H = g.height;
    const double dx = g.px - g.anchor_x, dy = g.py - g.anchor_y;
    if (g.mode == New) {
        g.end_x = std::clamp(g.px, 0.0, W);
        g.end_y = std::clamp(g.py, 0.0, H);
    } else if (g.mode == Move) {
        const double x = std::clamp(g.init[0] + dx, 0.0, W - g.init[2]), y = std::clamp(g.init[1] + dy, 0.0, H - g.init[3]);
        g.start_x = x, g.start_y = y, g.end_x = x + g.init[2], g.end_y = y + g.init[3];
    } else {
        double nx = g.init[0], ny = g.init[1], nw = g.init[2], nh = g.init[3];
        if (g.mode == TopLeft || g.mode == Left || g.mode == BottomLeft) {
            nx = std::clamp(g.init[0] + dx, 0.0, g.init[0] + g.init[2] - 10);
            nw = g.init[2] + (g.init[0] - nx);
        }
        if (g.mode == TopRight || g.mode == Right || g.mode == BottomRight) nw = std::clamp(g.init[2] + dx, 10.0, W - g.init[0]);
        if (g.mode == TopLeft || g.mode == Top || g.mode == TopRight) {
            ny = std::clamp(g.init[1] + dy, 0.0, g.init[1] + g.init[3] - 10);
            nh = g.init[3] + (g.init[1] - ny);
        }
        if (g.mode == BottomLeft || g.mode == Bottom || g.mode == BottomRight) nh = std::clamp(g.init[3] + dy, 10.0, H - g.init[1]);
        g.start_x = nx, g.start_y = ny, g.end_x = nx + nw, g.end_y = ny + nh;
    }
    draw();
}

void pt_button(void*, struct wl_pointer*, uint32_t serial, uint32_t, uint32_t button, uint32_t state) {
    constexpr uint32_t kLeft = 0x110, kRight = 0x111;
    g.pointer_serial = serial;
    if (state == WL_POINTER_BUTTON_STATE_RELEASED) {
        if (button != kLeft) return;
        if (g.dragging_slider != Button::None) {
            g.dragging_slider = Button::None;
            save_audio();
        }
        if (g.selecting) {
            g.selecting = false;
            g.has_selection = sel_w() > 10 && sel_h() > 10;
            if (g.has_selection) save_selection();
        }
        update_cursor();
        draw();
        return;
    }
    if (button == kRight) {
        g.done = true;
        return;
    }
    if (button != kLeft) return;
    if (const Hit* h = hit_at(g.px, g.py)) {
        if (h->b == Button::DeskSlider || h->b == Button::MicSlider) {
            g.dragging_slider = h->b;
            slide(h->b, g.px);
        } else {
            const Button b = h->b;
            const int index = h->index;
            if (b != Button::MicList && b != Button::MicItem && b != Button::None) g.mic_list_open = false;
            press(b, index);
        }
        draw();
        return;
    }
    g.mic_list_open = false;
    if (g.video) {
        draw();
        return;
    }
    g.qr_shown = false;
    g.mode = interaction_mode(g.px, g.py);
    g.selecting = true;
    if (g.mode != New) g.maximized = false;
    g.anchor_x = g.px, g.anchor_y = g.py;
    g.init[0] = sel_x(), g.init[1] = sel_y(), g.init[2] = sel_w(), g.init[3] = sel_h();
    if (g.mode == New) {
        g.start_x = g.end_x = std::clamp(g.px, 0.0, static_cast<double>(g.width));
        g.start_y = g.end_y = std::clamp(g.py, 0.0, static_cast<double>(g.height));
        g.has_selection = false;
        g.maximized = false;
    }
    draw();
}

void pt_axis(void*, struct wl_pointer*, uint32_t, uint32_t, wl_fixed_t) {}
void pt_frame(void*, struct wl_pointer*) {}
void pt_axis_source(void*, struct wl_pointer*, uint32_t) {}
void pt_axis_stop(void*, struct wl_pointer*, uint32_t, uint32_t) {}
void pt_axis_discrete(void*, struct wl_pointer*, uint32_t, int32_t) {}

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

// ── Keyboard ─────────────────────────────────────────────────────────────────

void kb_keymap(void*, struct wl_keyboard*, uint32_t format, int32_t fd, uint32_t size) {
    if (format != WL_KEYBOARD_KEYMAP_FORMAT_XKB_V1) {
        close(fd);
        return;
    }
    char* map = static_cast<char*>(mmap(nullptr, size, PROT_READ, MAP_PRIVATE, fd, 0));
    close(fd);
    if (map == MAP_FAILED) return;
    struct xkb_keymap* keymap = xkb_keymap_new_from_string(g.xkb, map, XKB_KEYMAP_FORMAT_TEXT_V1, XKB_KEYMAP_COMPILE_NO_FLAGS);
    munmap(map, size);
    if (!keymap) return;
    if (g.xkb_state) xkb_state_unref(g.xkb_state);
    g.xkb_state = xkb_state_new(keymap);
    xkb_keymap_unref(keymap);
}
void kb_enter(void*, struct wl_keyboard*, uint32_t, struct wl_surface*, struct wl_array*) {}
void kb_leave(void*, struct wl_keyboard*, uint32_t, struct wl_surface*) {}

void kb_key(void*, struct wl_keyboard*, uint32_t, uint32_t, uint32_t key, uint32_t state) {
    if (state != WL_KEYBOARD_KEY_STATE_PRESSED || !g.xkb_state) return;
    const xkb_keysym_t sym = xkb_state_key_get_one_sym(g.xkb_state, key + 8);
    if (sym == XKB_KEY_Escape) {
        g.done = true;
    } else if (sym == XKB_KEY_Return || sym == XKB_KEY_KP_Enter) {
        if (g.video) record();
        else if (g.has_selection) capture(g.edit);
    } else if (sym == XKB_KEY_Tab) {
        set_video(!g.video);
        draw();
    }
}

void kb_modifiers(void*, struct wl_keyboard*, uint32_t, uint32_t depressed, uint32_t latched, uint32_t locked, uint32_t group) {
    if (!g.xkb_state) return;
    xkb_state_update_mask(g.xkb_state, depressed, latched, locked, 0, 0, group);
    g.shift = xkb_state_mod_name_is_active(g.xkb_state, XKB_MOD_NAME_SHIFT, XKB_STATE_MODS_EFFECTIVE) > 0;
    update_cursor();
}
void kb_repeat(void*, struct wl_keyboard*, int32_t, int32_t) {}
const struct wl_keyboard_listener kKeyboard = {kb_keymap, kb_enter, kb_leave, kb_key, kb_modifiers, kb_repeat};

// A keyboard or a mouse that goes (unplugged) and comes back is "none",
// then one again; the old object gets nothing after that, so it is let go
// and a new one taken.
void seat_capabilities(void*, struct wl_seat* seat, uint32_t caps) {
    const bool keyboard = (caps & WL_SEAT_CAPABILITY_KEYBOARD) != 0;
    if (keyboard && !g.keyboard) {
        g.keyboard = wl_seat_get_keyboard(seat);
        wl_keyboard_add_listener(g.keyboard, &kKeyboard, nullptr);
    } else if (!keyboard && g.keyboard) {
        if (wl_keyboard_get_version(g.keyboard) >= WL_KEYBOARD_RELEASE_SINCE_VERSION) wl_keyboard_release(g.keyboard);
        else wl_keyboard_destroy(g.keyboard);
        g.keyboard = nullptr;
    }
    const bool pointer = (caps & WL_SEAT_CAPABILITY_POINTER) != 0;
    if (pointer && !g.pointer) {
        g.pointer = wl_seat_get_pointer(seat);
        wl_pointer_add_listener(g.pointer, &kPointer, nullptr);
    } else if (!pointer && g.pointer) {
        if (wl_pointer_get_version(g.pointer) >= WL_POINTER_RELEASE_SINCE_VERSION) wl_pointer_release(g.pointer);
        else wl_pointer_destroy(g.pointer);
        g.pointer = nullptr;
        g.cursor_name.clear();
        if (g.selecting) {   // a drag cut short ends where it was
            g.selecting = false;
            g.has_selection = sel_w() > 10 && sel_h() > 10;
        }
        g.dragging_slider = Button::None;
    }
}
void seat_name(void*, struct wl_seat*, const char*) {}
const struct wl_seat_listener kSeat = {seat_capabilities, seat_name};

// ── Screens and the surface ──────────────────────────────────────────────────

void out_geometry(void*, struct wl_output*, int32_t, int32_t, int32_t, int32_t, int32_t, const char*, const char*, int32_t) {}
void out_mode(void*, struct wl_output*, uint32_t, int32_t, int32_t, int32_t) {}
void out_done(void*, struct wl_output*) {}
void out_scale(void* data, struct wl_output*, int32_t factor) { static_cast<Output*>(data)->scale = factor; }
void out_name(void* data, struct wl_output*, const char* name) { static_cast<Output*>(data)->name = name; }
void out_description(void*, struct wl_output*, const char*) {}
const struct wl_output_listener kOutput = {out_geometry, out_mode, out_done, out_scale, out_name, out_description};

void layer_configure(void*, struct zwlr_layer_surface_v1* surface, uint32_t serial, uint32_t width, uint32_t height) {
    zwlr_layer_surface_v1_ack_configure(surface, serial);
    g.width = static_cast<int>(width);
    g.height = static_cast<int>(height);
    g.configured = true;
    draw();
}
void layer_closed(void*, struct zwlr_layer_surface_v1*) { g.done = true; }
const struct zwlr_layer_surface_v1_listener kLayer = {layer_configure, layer_closed};

void registry_global(void*, struct wl_registry* registry, uint32_t name, const char* interface, uint32_t version) {
    if (std::strcmp(interface, wl_compositor_interface.name) == 0) {
        g.compositor = static_cast<wl_compositor*>(wl_registry_bind(registry, name, &wl_compositor_interface, 4));
    } else if (std::strcmp(interface, wl_shm_interface.name) == 0) {
        g.shm = static_cast<wl_shm*>(wl_registry_bind(registry, name, &wl_shm_interface, 1));
    } else if (std::strcmp(interface, wl_seat_interface.name) == 0 && !g.seat) {
        g.seat = static_cast<wl_seat*>(wl_registry_bind(registry, name, &wl_seat_interface, std::min(version, 7u)));
        wl_seat_add_listener(g.seat, &kSeat, nullptr);
    } else if (std::strcmp(interface, zwlr_layer_shell_v1_interface.name) == 0) {
        g.layer_shell = static_cast<zwlr_layer_shell_v1*>(
            wl_registry_bind(registry, name, &zwlr_layer_shell_v1_interface, std::min(version, 4u)));
    } else if (std::strcmp(interface, wl_output_interface.name) == 0) {
        auto* o = new Output;
        o->output = static_cast<wl_output*>(wl_registry_bind(registry, name, &wl_output_interface, std::min(version, 4u)));
        wl_output_add_listener(o->output, &kOutput, o);
        g.outputs.push_back(o);
    }
}
void registry_global_remove(void*, struct wl_registry*, uint32_t) {}
const struct wl_registry_listener kRegistry = {registry_global, registry_global_remove};

// The screen sway has focused, and where it sits in the layout.
std::string focused_output() {
    b1air::SwayIPC ipc;
    if (!ipc.connect()) return {};
    const auto outputs = nlohmann::json::parse(ipc.send_command(3), nullptr, false);   // GET_OUTPUTS
    if (!outputs.is_array()) return {};
    for (const auto& o : outputs) {
        if (!o.value("focused", false)) continue;
        if (o.contains("rect")) {
            g.offset_x = o["rect"].value("x", 0);
            g.offset_y = o["rect"].value("y", 0);
        }
        return o.value("name", std::string());
    }
    return {};
}

} // namespace

int main(int argc, char** argv) {
    for (int i = 1; i < argc; ++i)
        if (std::string(argv[i]) == "--edit") g.edit = true;
    // Both: QS_SCREENSHOT_EDIT is what the daemon set for the QML overlay.
    if (const char* e = std::getenv("QS_SCREENSHOT_EDIT"); e && std::string(e) == "true") g.edit = true;
    g.pal = b1air::Palette::load();
    load_state();
    g.xkb = xkb_context_new(XKB_CONTEXT_NO_FLAGS);

    g.display = wl_display_connect(nullptr);
    if (!g.display) {
        std::fprintf(stderr, "b1air-shot: no Wayland display\n");
        return 1;
    }
    struct wl_registry* registry = wl_display_get_registry(g.display);
    wl_registry_add_listener(registry, &kRegistry, nullptr);
    wl_display_roundtrip(g.display);
    wl_display_roundtrip(g.display);   // the screens' names and scales
    if (!g.compositor || !g.shm || !g.layer_shell) {
        std::fprintf(stderr, "b1air-shot: the compositor has no wlr-layer-shell\n");
        return 1;
    }
    const std::string focused = focused_output();
    for (auto* o : g.outputs)
        if (o->name == focused) g.on = o;
    if (!g.on && !g.outputs.empty()) g.on = g.outputs.front();

    const char* cursor_size = std::getenv("XCURSOR_SIZE");
    const int cursor_px = (cursor_size ? std::atoi(cursor_size) : 24) * std::max(1, g.on ? g.on->scale : 1);
    g.cursor_theme = wl_cursor_theme_load(std::getenv("XCURSOR_THEME"), cursor_px > 0 ? cursor_px : 24, g.shm);
    g.cursor_surface = wl_compositor_create_surface(g.compositor);
    if (g.on) wl_surface_set_buffer_scale(g.cursor_surface, std::max(1, g.on->scale));

    g.surface = wl_compositor_create_surface(g.compositor);
    g.layer = zwlr_layer_shell_v1_get_layer_surface(g.layer_shell, g.surface, g.on ? g.on->output : nullptr,
                                                    ZWLR_LAYER_SHELL_V1_LAYER_OVERLAY, "b1air-shot");
    zwlr_layer_surface_v1_set_anchor(g.layer, ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP | ZWLR_LAYER_SURFACE_V1_ANCHOR_BOTTOM |
                                                  ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT | ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT);
    zwlr_layer_surface_v1_set_exclusive_zone(g.layer, -1);
    zwlr_layer_surface_v1_set_keyboard_interactivity(g.layer, ZWLR_LAYER_SURFACE_V1_KEYBOARD_INTERACTIVITY_EXCLUSIVE);
    zwlr_layer_surface_v1_add_listener(g.layer, &kLayer, nullptr);
    wl_surface_commit(g.surface);

    // The video mode's whole-screen selection needs the size.
    bool video_set = false;
    while (!g.done) {
        if (wl_display_dispatch(g.display) < 0) break;
        if (g.configured && !video_set) {
            video_set = true;
            if (g.video) {
                g.video = false;
                set_video(true);
                draw();
            }
        }
    }
    zwlr_layer_surface_v1_destroy(g.layer);
    wl_surface_destroy(g.surface);
    wl_display_flush(g.display);
    wl_display_disconnect(g.display);
    return 0;
}
