// b1air-bg — the desktop background. See CMakeLists.txt for why it is shaped
// the way it is.
//
//   b1air-bg            run (one per session; a second exits quietly)
//
// The pictures are chosen with `b1air-daemon wallpaper set …`; this only shows
// them, and follows what changes on its own: the files the daemon writes
// (inotify), the workspace each screen shows and the screens themselves
// (sway's IPC), and each screen's size and scale (Wayland).

#include "image.hpp"
#include "sway_ipc.hpp"
#include "wallpaper_config.hpp"

#include <wayland-client.h>
#include "alpha-modifier-v1-client-protocol.h"
#include "fractional-scale-v1-client-protocol.h"
#include "single-pixel-buffer-v1-client-protocol.h"
#include "viewporter-client-protocol.h"
// The protocol names an argument `namespace`, which C++ reserves.
#define namespace namespace_
#include "wlr-layer-shell-unstable-v1-client-protocol.h"
#undef namespace

#include <nlohmann/json.hpp>

#include <algorithm>
#include <chrono>
#include <climits>
#include <cmath>
#include <cstring>
#include <functional>
#include <fcntl.h>
#include <iostream>
#include <list>
#include <malloc.h>
#include <map>
#include <memory>
#include <optional>
#include <poll.h>
#include <sys/file.h>
#include <sys/inotify.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>
#include <vector>

namespace {

using Clock = std::chrono::steady_clock;
using std::chrono::milliseconds;

constexpr int kDecodeRetries = 3;

struct App;

// A new picture fading in over the old: a subsurface above the screen's own
// surface, its opacity stepped by the compositor each frame. When it reaches
// one, the picture moves to the screen's surface and this goes away.
struct Fade {
    wl_surface* surface = nullptr;
    wl_subsurface* subsurface = nullptr;
    wp_viewport* viewport = nullptr;
    wp_alpha_modifier_surface_v1* alpha = nullptr;
    wl_buffer* buffer = nullptr;
    wl_callback* frame = nullptr;
    Clock::time_point start;
    int ms = 0;
};

struct Output {
    App* app = nullptr;
    uint32_t global = 0;
    wl_output* output = nullptr;
    std::string name;
    int32_t output_scale = 1;
    int32_t preferred_scale = 0;    // wl_surface v6
    uint32_t scale120 = 0;          // wp_fractional_scale_v1

    wl_surface* surface = nullptr;
    zwlr_layer_surface_v1* layer = nullptr;
    wp_viewport* viewport = nullptr;
    wp_fractional_scale_v1* fractional = nullptr;
    uint32_t width = 0, height = 0;
    bool configured = false;

    std::string shown;              // the picture committed (or fading in)
    std::string failed;             // the last picture that would not decode
    int failures = 0;
    std::unique_ptr<Fade> fade;

    double scale() const {
        if (scale120) return scale120 / 120.0;
        if (preferred_scale > 0) return preferred_scale;
        return std::max(1, output_scale);
    }
};

struct App {
    wl_display* display = nullptr;
    wl_registry* registry = nullptr;
    wl_compositor* compositor = nullptr;
    uint32_t compositor_version = 0;
    wl_subcompositor* subcompositor = nullptr;
    wl_shm* shm = nullptr;
    zwlr_layer_shell_v1* layer_shell = nullptr;
    wp_viewporter* viewporter = nullptr;
    wp_fractional_scale_manager_v1* fractional = nullptr;
    wp_single_pixel_buffer_manager_v1* single_pixel = nullptr;
    wp_alpha_modifier_v1* alpha = nullptr;
    std::list<std::unique_ptr<Output>> outputs;

    WallpaperConfig config;
    SwayIpc ipc;
    std::map<std::string, std::string> identity;    // connector → make model serial
    std::map<std::string, std::string> workspace;   // connector → workspace shown
    bool have_outputs = false;
    bool have_workspaces = false;

    int inotify = -1;
    std::optional<Clock::time_point> reload_at, reconnect_at, retry_at, settle_at;
    bool running = true;
    int exit_code = 0;
};

void render(Output* o);
void finish_fade(Output* o);

void render_all(App& app) {
    for (auto& o : app.outputs) render(o.get());
}

// ── Buffers ─────────────────────────────────────────────────────────────────

// Shared memory the compositor maps; this process writes it once and lets go
// of its own mapping straight away.
wl_buffer* shm_buffer(App& app, int w, int h, const std::function<bool(uint32_t*, int)>& fill) {
    const int stride = w * 4;
    const size_t size = static_cast<size_t>(stride) * h;
    const int fd = memfd_create("b1air-bg", MFD_CLOEXEC);
    if (fd < 0) return nullptr;
    if (ftruncate(fd, static_cast<off_t>(size)) != 0) { close(fd); return nullptr; }
    void* data = mmap(nullptr, size, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (data == MAP_FAILED) { close(fd); return nullptr; }
    const bool ok = fill(static_cast<uint32_t*>(data), stride);
    munmap(data, size);
    if (!ok) { close(fd); return nullptr; }
    wl_shm_pool* pool = wl_shm_create_pool(app.shm, fd, static_cast<int32_t>(size));
    wl_buffer* buffer = wl_shm_pool_create_buffer(pool, 0, w, h, stride, WL_SHM_FORMAT_XRGB8888);
    wl_shm_pool_destroy(pool);
    close(fd);   // libwayland sends a duplicate
    return buffer;
}

wl_buffer* solid_buffer(App& app, int w, int h) {
    const uint32_t c = app.config.ground;
    if (app.single_pixel && app.viewporter) {
        const auto ch = [](uint32_t v) { return static_cast<uint32_t>((v & 0xff) * (UINT32_MAX / 255u)); };
        return wp_single_pixel_buffer_manager_v1_create_u32_rgba_buffer(
            app.single_pixel, ch(c >> 16), ch(c >> 8), ch(c), UINT32_MAX);
    }
    return shm_buffer(app, w, h, [&](uint32_t* px, int stride) {
        for (int y = 0; y < h; ++y)
            std::fill_n(reinterpret_cast<uint32_t*>(reinterpret_cast<char*>(px) + y * stride), w, 0xff000000u | c);
        return true;
    });
}

// ── Showing a picture ───────────────────────────────────────────────────────

void attach(Output* o, wl_surface* surface, wp_viewport* viewport, wl_buffer* buffer) {
    if (viewport) {
        wp_viewport_set_destination(viewport, static_cast<int32_t>(o->width), static_cast<int32_t>(o->height));
    } else {
        wl_surface_set_buffer_scale(surface, static_cast<int32_t>(std::ceil(o->scale())));
    }
    wl_surface_attach(surface, buffer, 0, 0);
    wl_surface_damage_buffer(surface, 0, 0, INT32_MAX, INT32_MAX);
    wl_surface_commit(surface);
}

void fade_frame(void* data, wl_callback* cb, uint32_t);
const wl_callback_listener fade_frame_listener = {.done = fade_frame};

void fade_step(Output* o) {
    Fade& f = *o->fade;
    const double t = std::chrono::duration<double, std::milli>(Clock::now() - f.start).count() / f.ms;
    if (t >= 1.0) {
        finish_fade(o);
        return;
    }
    const double eased = t < 0.5 ? 2 * t * t : 1 - std::pow(-2 * t + 2, 2) / 2;
    wp_alpha_modifier_surface_v1_set_multiplier(f.alpha, static_cast<uint32_t>(eased * UINT32_MAX));
    f.frame = wl_surface_frame(f.surface);
    wl_callback_add_listener(f.frame, &fade_frame_listener, o);
    wl_surface_commit(f.surface);
}

void fade_frame(void* data, wl_callback* cb, uint32_t) {
    auto* o = static_cast<Output*>(data);
    wl_callback_destroy(cb);
    if (!o->fade) return;
    o->fade->frame = nullptr;
    fade_step(o);
}

void drop_fade(Output* o) {
    if (!o->fade) return;
    Fade& f = *o->fade;
    if (f.frame) wl_callback_destroy(f.frame);
    if (f.alpha) wp_alpha_modifier_surface_v1_destroy(f.alpha);
    if (f.viewport) wp_viewport_destroy(f.viewport);
    if (f.subsurface) wl_subsurface_destroy(f.subsurface);
    if (f.surface) wl_surface_destroy(f.surface);
    if (f.buffer) wl_buffer_destroy(f.buffer);
    o->fade.reset();
}

// The picture fading in becomes the screen's own, at full opacity.
void finish_fade(Output* o) {
    if (!o->fade) return;
    attach(o, o->surface, o->viewport, o->fade->buffer);
    drop_fade(o);
}

void present(Output* o, wl_buffer* buffer, const std::string& key) {
    App& app = *o->app;
    const bool fade = app.alpha && app.subcompositor && app.viewporter
        && app.config.transition_ms > 0 && !o->shown.empty();
    // A picture arriving mid-fade: the one fading in is taken as arrived.
    finish_fade(o);
    o->shown = key;
    if (!fade) {
        attach(o, o->surface, o->viewport, buffer);
        // The compositor holds the buffer as long as it shows it.
        wl_buffer_destroy(buffer);
        return;
    }
    auto f = std::make_unique<Fade>();
    f->surface = wl_compositor_create_surface(app.compositor);
    f->subsurface = wl_subcompositor_get_subsurface(app.subcompositor, f->surface, o->surface);
    wl_subsurface_set_position(f->subsurface, 0, 0);
    wl_subsurface_set_desync(f->subsurface);
    f->viewport = wp_viewporter_get_viewport(app.viewporter, f->surface);
    f->alpha = wp_alpha_modifier_v1_get_surface(app.alpha, f->surface);
    wp_alpha_modifier_surface_v1_set_multiplier(f->alpha, 0);
    f->buffer = buffer;
    f->start = Clock::now();
    f->ms = app.config.transition_ms;
    f->frame = wl_surface_frame(f->surface);
    wl_callback_add_listener(f->frame, &fade_frame_listener, o);
    o->fade = std::move(f);
    attach(o, o->fade->surface, o->fade->viewport, buffer);
    wl_surface_commit(o->surface);   // places the subsurface
}

std::string picture_key(const std::string& path, int w, int h) {
    // The modification time is in the key: the daemon rewrites the shared
    // picture in place, and a new one under the old name is a new picture.
    struct stat st {};
    stat(path.c_str(), &st);
    return path + "|" + std::to_string(st.st_mtim.tv_sec) + "." + std::to_string(st.st_mtim.tv_nsec)
        + "|" + std::to_string(st.st_size) + "|" + std::to_string(w) + "x" + std::to_string(h);
}

void render(Output* o) {
    App& app = *o->app;
    if (!o->configured || !app.have_outputs || !app.have_workspaces || !o->width || !o->height) return;

    const auto id = app.identity.find(o->name);
    const auto ws = app.workspace.find(o->name);
    const std::string path = app.config.pick(id != app.identity.end() ? id->second : o->name,
                                             ws != app.workspace.end() ? ws->second : "");
    const double s = app.viewporter ? o->scale() : std::ceil(o->scale());
    const int bw = std::max(1, static_cast<int>(std::lround(o->width * s)));
    const int bh = std::max(1, static_cast<int>(std::lround(o->height * s)));

    char ground[16];
    std::snprintf(ground, sizeof ground, "#%06x", app.config.ground);
    const std::string key = path.empty() ? std::string("ground ") + ground + " " + std::to_string(bw) + "x" + std::to_string(bh)
                                         : picture_key(path, bw, bh);
    if (key == o->shown) return;
    if (key == o->failed && o->failures > kDecodeRetries) return;

    wl_buffer* buffer = path.empty()
        ? solid_buffer(app, bw, bh)
        : shm_buffer(app, bw, bh, [&](uint32_t* px, int stride) {
              return decode_cover(path, bw, bh, app.config.ground, px, stride);
          });
    // The decode went through the picture at its file's size; hand that back.
    malloc_trim(0);

    if (!buffer) {
        // Most likely caught halfway through being written; try again soon.
        o->failures = key == o->failed ? o->failures + 1 : 1;
        o->failed = key;
        if (o->failures <= kDecodeRetries) app.retry_at = Clock::now() + milliseconds(400 * o->failures);
        else std::cerr << "b1air-bg: could not read " << path << "\n";
        return;
    }
    o->failed.clear();
    o->failures = 0;
    present(o, buffer, key);
}

// ── Wayland objects ─────────────────────────────────────────────────────────

void layer_configure(void* data, zwlr_layer_surface_v1* layer, uint32_t serial, uint32_t w, uint32_t h) {
    auto* o = static_cast<Output*>(data);
    zwlr_layer_surface_v1_ack_configure(layer, serial);
    if (o->configured && w == o->width && h == o->height) {
        wl_surface_commit(o->surface);
        return;
    }
    o->width = w;
    o->height = h;
    o->configured = true;
    o->shown.clear();   // a picture cut for the old size would be stretched
    render(o);
}

void destroy_output(Output* o);

void layer_closed(void* data, zwlr_layer_surface_v1*) {
    auto* o = static_cast<Output*>(data);
    // The screen went away; its wl_output follows.
    drop_fade(o);
    if (o->layer) { zwlr_layer_surface_v1_destroy(o->layer); o->layer = nullptr; }
    o->configured = false;
}

const zwlr_layer_surface_v1_listener layer_listener = {
    .configure = layer_configure,
    .closed = layer_closed,
};

void fractional_scale(void* data, wp_fractional_scale_v1*, uint32_t scale) {
    auto* o = static_cast<Output*>(data);
    if (o->scale120 == scale) return;
    o->scale120 = scale;
    o->shown.clear();
    render(o);
}
const wp_fractional_scale_v1_listener fractional_listener = {.preferred_scale = fractional_scale};

void surface_enter(void*, wl_surface*, wl_output*) {}
void surface_leave(void*, wl_surface*, wl_output*) {}
void surface_preferred_scale(void* data, wl_surface*, int32_t factor) {
    auto* o = static_cast<Output*>(data);
    if (o->preferred_scale == factor) return;
    o->preferred_scale = factor;
    if (!o->scale120) { o->shown.clear(); render(o); }
}
void surface_preferred_transform(void*, wl_surface*, uint32_t) {}
const wl_surface_listener surface_listener = {
    .enter = surface_enter,
    .leave = surface_leave,
    .preferred_buffer_scale = surface_preferred_scale,
    .preferred_buffer_transform = surface_preferred_transform,
};

void create_surface(Output* o) {
    App& app = *o->app;
    o->surface = wl_compositor_create_surface(app.compositor);
    wl_surface_add_listener(o->surface, &surface_listener, o);
    if (app.viewporter) o->viewport = wp_viewporter_get_viewport(app.viewporter, o->surface);
    if (app.fractional) {
        o->fractional = wp_fractional_scale_manager_v1_get_fractional_scale(app.fractional, o->surface);
        wp_fractional_scale_v1_add_listener(o->fractional, &fractional_listener, o);
    }
    // Clicks on the desktop are not this program's to take.
    wl_region* none = wl_compositor_create_region(app.compositor);
    wl_surface_set_input_region(o->surface, none);
    wl_region_destroy(none);

    o->layer = zwlr_layer_shell_v1_get_layer_surface(app.layer_shell, o->surface, o->output,
                                                     ZWLR_LAYER_SHELL_V1_LAYER_BACKGROUND, "wallpaper");
    zwlr_layer_surface_v1_set_size(o->layer, 0, 0);
    zwlr_layer_surface_v1_set_anchor(o->layer,
        ZWLR_LAYER_SURFACE_V1_ANCHOR_TOP | ZWLR_LAYER_SURFACE_V1_ANCHOR_BOTTOM
        | ZWLR_LAYER_SURFACE_V1_ANCHOR_LEFT | ZWLR_LAYER_SURFACE_V1_ANCHOR_RIGHT);
    // Under the bar's exclusive zone too, to the very edge.
    zwlr_layer_surface_v1_set_exclusive_zone(o->layer, -1);
    zwlr_layer_surface_v1_add_listener(o->layer, &layer_listener, o);
    wl_surface_commit(o->surface);
}

void destroy_output(Output* o) {
    drop_fade(o);
    if (o->layer) zwlr_layer_surface_v1_destroy(o->layer);
    if (o->fractional) wp_fractional_scale_v1_destroy(o->fractional);
    if (o->viewport) wp_viewport_destroy(o->viewport);
    if (o->surface) wl_surface_destroy(o->surface);
    if (o->output) {
        if (wl_output_get_version(o->output) >= WL_OUTPUT_RELEASE_SINCE_VERSION) wl_output_release(o->output);
        else wl_output_destroy(o->output);
    }
}

void output_geometry(void*, wl_output*, int32_t, int32_t, int32_t, int32_t, int32_t, const char*, const char*, int32_t) {}
void output_mode(void*, wl_output*, uint32_t, int32_t, int32_t, int32_t) {}
void output_done(void* data, wl_output*) {
    auto* o = static_cast<Output*>(data);
    if (!o->surface) create_surface(o);
}
void output_scale(void* data, wl_output*, int32_t factor) {
    auto* o = static_cast<Output*>(data);
    o->output_scale = factor;
}
void output_name(void* data, wl_output*, const char* name) {
    static_cast<Output*>(data)->name = name ? name : "";
}
void output_description(void*, wl_output*, const char*) {}
const wl_output_listener output_listener = {
    .geometry = output_geometry,
    .mode = output_mode,
    .done = output_done,
    .scale = output_scale,
    .name = output_name,
    .description = output_description,
};

void registry_global(void* data, wl_registry* registry, uint32_t name, const char* iface, uint32_t version) {
    App& app = *static_cast<App*>(data);
    const auto is = [&](const wl_interface& i) { return std::strcmp(iface, i.name) == 0; };
    const auto bind = [&](const wl_interface& i, uint32_t max) {
        return wl_registry_bind(registry, name, &i, std::min(version, max));
    };
    if (is(wl_compositor_interface)) {
        app.compositor_version = std::min(version, 6u);
        app.compositor = static_cast<wl_compositor*>(bind(wl_compositor_interface, 6));
    } else if (is(wl_subcompositor_interface)) {
        app.subcompositor = static_cast<wl_subcompositor*>(bind(wl_subcompositor_interface, 1));
    } else if (is(wl_shm_interface)) {
        app.shm = static_cast<wl_shm*>(bind(wl_shm_interface, 1));
    } else if (is(zwlr_layer_shell_v1_interface)) {
        app.layer_shell = static_cast<zwlr_layer_shell_v1*>(bind(zwlr_layer_shell_v1_interface, 4));
    } else if (is(wp_viewporter_interface)) {
        app.viewporter = static_cast<wp_viewporter*>(bind(wp_viewporter_interface, 1));
    } else if (is(wp_fractional_scale_manager_v1_interface)) {
        app.fractional = static_cast<wp_fractional_scale_manager_v1*>(bind(wp_fractional_scale_manager_v1_interface, 1));
    } else if (is(wp_single_pixel_buffer_manager_v1_interface)) {
        app.single_pixel = static_cast<wp_single_pixel_buffer_manager_v1*>(bind(wp_single_pixel_buffer_manager_v1_interface, 1));
    } else if (is(wp_alpha_modifier_v1_interface)) {
        app.alpha = static_cast<wp_alpha_modifier_v1*>(bind(wp_alpha_modifier_v1_interface, 1));
    } else if (is(wl_output_interface)) {
        auto o = std::make_unique<Output>();
        o->app = &app;
        o->global = name;
        o->output = static_cast<wl_output*>(bind(wl_output_interface, 4));
        wl_output_add_listener(o->output, &output_listener, o.get());
        app.outputs.push_back(std::move(o));
    }
}

void registry_global_remove(void* data, wl_registry*, uint32_t name) {
    App& app = *static_cast<App*>(data);
    for (auto it = app.outputs.begin(); it != app.outputs.end(); ++it) {
        if ((*it)->global != name) continue;
        destroy_output(it->get());
        app.outputs.erase(it);
        return;
    }
}

const wl_registry_listener registry_listener = {
    .global = registry_global,
    .global_remove = registry_global_remove,
};

// ── sway ────────────────────────────────────────────────────────────────────

std::string output_identity(const nlohmann::json& o) {
    // As the daemon's output_identity(): the screen, not the port it is on.
    std::string id;
    for (const char* k : {"make", "model", "serial"}) {
        const std::string v = o.contains(k) && o[k].is_string() ? o[k].get<std::string>() : "";
        if (!v.empty() && v != "Unknown") id += (id.empty() ? "" : " ") + v;
    }
    return id.empty() && o.contains("name") && o["name"].is_string() ? o["name"].get<std::string>() : id;
}

void ipc_message(App& app, uint32_t type, const std::string& body) {
    const auto j = nlohmann::json::parse(body, nullptr, false);
    switch (type) {
    case SwayIpc::kGetOutputs:
        app.identity.clear();
        if (j.is_array())
            for (const auto& o : j)
                if (o.contains("name") && o["name"].is_string())
                    app.identity[o["name"].get<std::string>()] = output_identity(o);
        app.have_outputs = true;
        break;
    case SwayIpc::kGetWorkspaces:
        app.workspace.clear();
        if (j.is_array())
            for (const auto& ws : j)
                if (ws.value("visible", false) && ws.contains("output") && ws.contains("name"))
                    app.workspace[ws["output"].get<std::string>()] = ws["name"].get<std::string>();
        app.have_workspaces = true;
        break;
    case SwayIpc::kWorkspaceEvent:
        // Asked again rather than followed: "focus", "move", "rename" and
        // "empty" each change things differently, and one answer covers all.
        app.ipc.request(SwayIpc::kGetWorkspaces);
        return;
    case SwayIpc::kOutputEvent:
        app.ipc.request(SwayIpc::kGetOutputs);
        app.ipc.request(SwayIpc::kGetWorkspaces);
        return;
    case SwayIpc::kShutdownEvent:
        // sway is leaving, and so is its background.
        if (j.is_object() && j.value("change", "") == "exit") app.running = false;
        return;
    default:
        return;
    }
    if (app.have_outputs && app.have_workspaces) {
        app.settle_at.reset();
        render_all(app);
    }
}

void ipc_connect(App& app) {
    app.reconnect_at.reset();
    if (!app.ipc.connect(R"(["workspace","output","shutdown"])")) {
        app.reconnect_at = Clock::now() + std::chrono::seconds(1);
        return;
    }
    app.ipc.request(SwayIpc::kGetOutputs);
    app.ipc.request(SwayIpc::kGetWorkspaces);
}

// ── Files ───────────────────────────────────────────────────────────────────

// Watch descriptor → the file names in that directory that matter; empty for
// any of them.
std::map<int, std::vector<std::string>> g_watches;

void mkdir_p(const std::string& path) {
    for (size_t i = 1; i <= path.size(); ++i)
        if (i == path.size() || path[i] == '/') mkdir(path.substr(0, i).c_str(), 0755);
}

void watch_files(App& app) {
    app.inotify = inotify_init1(IN_NONBLOCK | IN_CLOEXEC);
    if (app.inotify < 0) return;
    // Written whole: a picture is seen when its writer closes it, so a
    // half-copied file is not read (and, if it is, is read again).
    const uint32_t mask = IN_CLOSE_WRITE | IN_MOVED_TO | IN_MOVED_FROM | IN_DELETE;
    const auto add = [&](const std::string& dir, std::vector<std::string> names) {
        mkdir_p(dir);
        const int wd = inotify_add_watch(app.inotify, dir.c_str(), mask);
        if (wd >= 0) g_watches[wd] = std::move(names);
    };
    add(WallpaperConfig::config_dir(), {"wallpapers.json", "theme.json"});
    add(WallpaperConfig::cache_dir(), {"current_wallpaper.jpg"});
    add(WallpaperConfig::copies_dir(), {});
}

void read_inotify(App& app) {
    alignas(inotify_event) char buf[8192];
    for (;;) {
        const ssize_t n = read(app.inotify, buf, sizeof buf);
        if (n <= 0) return;
        for (char* p = buf; p < buf + n;) {
            const auto* ev = reinterpret_cast<const inotify_event*>(p);
            p += sizeof(inotify_event) + ev->len;
            const auto it = g_watches.find(ev->wd);
            if (it == g_watches.end()) continue;
            const std::string name = ev->len ? ev->name : "";
            if (it->second.empty() || std::find(it->second.begin(), it->second.end(), name) != it->second.end())
                app.reload_at = Clock::now() + milliseconds(150);
        }
    }
}

// ── Loop ────────────────────────────────────────────────────────────────────

int timeout_ms(const App& app) {
    std::optional<Clock::time_point> next;
    const auto consider = [&](const std::optional<Clock::time_point>& t) {
        if (t && (!next || *t < *next)) next = t;
    };
    consider(app.reload_at);
    consider(app.reconnect_at);
    consider(app.retry_at);
    consider(app.settle_at);
    for (const auto& o : app.outputs)
        if (o->fade) consider(o->fade->start + milliseconds(o->fade->ms + 500));
    if (!next) return -1;
    const auto ms = std::chrono::duration_cast<milliseconds>(*next - Clock::now()).count();
    return static_cast<int>(std::clamp<long long>(ms + 1, 0, INT_MAX));
}

void run_timers(App& app) {
    const auto now = Clock::now();
    const auto due = [&](std::optional<Clock::time_point>& t) {
        if (!t || *t > now) return false;
        t.reset();
        return true;
    };
    if (due(app.reload_at)) {
        app.config = WallpaperConfig::load();
        render_all(app);
    }
    if (due(app.reconnect_at)) ipc_connect(app);
    if (due(app.retry_at)) render_all(app);
    if (due(app.settle_at)) {
        // sway never answered: show the shared picture rather than nothing.
        app.have_outputs = app.have_workspaces = true;
        render_all(app);
    }
    // A fade whose frames stopped coming — the background was covered, and a
    // covered surface is not drawn — finishes on the clock instead.
    for (auto& o : app.outputs)
        if (o->fade && now > o->fade->start + milliseconds(o->fade->ms + 500)) finish_fade(o.get());
}

bool single_instance() {
    const char* rt = std::getenv("XDG_RUNTIME_DIR");
    const std::string dir = std::string(rt && *rt ? rt : "/tmp") + "/b1air";
    mkdir(dir.c_str(), 0700);
    const int fd = open((dir + "/bg.lock").c_str(), O_RDWR | O_CREAT | O_CLOEXEC, 0600);
    // Held for the life of the process; the kernel lets go when it ends.
    return fd >= 0 && flock(fd, LOCK_EX | LOCK_NB) == 0;
}

} // namespace

int main() {
    // Every picture-sized block straight from mmap, so freeing it gives it
    // back at once; glibc would otherwise raise this threshold the first time
    // one is freed and keep the next in the heap.
    mallopt(M_MMAP_THRESHOLD, 256 * 1024);

    // Two would draw two backgrounds over each other.
    if (!single_instance()) return 0;

    App app;
    app.display = wl_display_connect(nullptr);
    if (!app.display) {
        std::cerr << "b1air-bg: no Wayland display\n";
        return 1;
    }
    app.registry = wl_display_get_registry(app.display);
    wl_registry_add_listener(app.registry, &registry_listener, &app);
    wl_display_roundtrip(app.display);
    if (!app.compositor || !app.shm || !app.layer_shell) {
        std::cerr << "b1air-bg: the compositor has no layer shell\n";
        return 1;
    }

    app.config = WallpaperConfig::load();
    watch_files(app);
    app.ipc.on_message = [&app](uint32_t type, const std::string& body) { ipc_message(app, type, body); };
    ipc_connect(app);
    app.settle_at = Clock::now() + milliseconds(1500);
    wl_display_roundtrip(app.display);   // outputs' names and first configures

    while (app.running) {
        while (wl_display_prepare_read(app.display) != 0) wl_display_dispatch_pending(app.display);
        wl_display_flush(app.display);

        pollfd fds[4];
        int n = 0;
        fds[n++] = {wl_display_get_fd(app.display), POLLIN, 0};
        const int qi = app.ipc.query_fd() >= 0 ? n : -1;
        if (qi >= 0) fds[n++] = {app.ipc.query_fd(), POLLIN, 0};
        const int ei = app.ipc.event_fd() >= 0 ? n : -1;
        if (ei >= 0) fds[n++] = {app.ipc.event_fd(), POLLIN, 0};
        const int ii = app.inotify >= 0 ? n : -1;
        if (ii >= 0) fds[n++] = {app.inotify, POLLIN, 0};

        if (poll(fds, static_cast<nfds_t>(n), timeout_ms(app)) < 0 && errno != EINTR) {
            wl_display_cancel_read(app.display);
            break;
        }
        if (fds[0].revents & POLLIN) {
            if (wl_display_read_events(app.display) < 0) { app.exit_code = 1; break; }
        } else {
            wl_display_cancel_read(app.display);
        }
        if (fds[0].revents & (POLLERR | POLLHUP)) { app.exit_code = 1; break; }
        if (wl_display_dispatch_pending(app.display) < 0) { app.exit_code = 1; break; }

        bool ipc_ok = true;
        if (qi >= 0 && fds[qi].revents) ipc_ok = app.ipc.read(fds[qi].fd) && ipc_ok;
        if (ei >= 0 && fds[ei].revents && app.ipc.connected()) ipc_ok = app.ipc.read(fds[ei].fd) && ipc_ok;
        if (!ipc_ok) {
            app.ipc.close();
            app.reconnect_at = Clock::now() + std::chrono::seconds(1);
        }
        if (ii >= 0 && fds[ii].revents) read_inotify(app);
        run_timers(app);
    }

    for (auto& o : app.outputs) destroy_output(o.get());
    wl_display_disconnect(app.display);
    return app.exit_code;
}
