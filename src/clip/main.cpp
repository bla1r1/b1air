// b1air-clip — the clipboard, from the command line, without wl-clipboard.
//
//   b1air-clip copy [-t <mime>] [--primary] [--foreground] [-- <text>...]
//       Text from the arguments, or anything from stdin (as <mime>, or as
//       text). Stays in the background serving it until something else is
//       copied; --foreground stays in front instead.
//   b1air-clip paste [-t <mime>|text] [--primary] [--max <bytes>]
//       What is on the clipboard: its text, or the given type, written out
//       as it is (no newline added). Status 1 when there is nothing of that
//       type.
//   b1air-clip paste --list-types [--primary]
//       The types on offer, one a line.
//   b1air-clip watch [--primary] [--max <bytes>]
//       Every text copied from now on (the current one first), each
//       followed by \x1e; ends when stdin closes.
//   b1air-clip clear [--primary]
//
// --primary is the middle-click selection instead of the clipboard.
//
// wlr-data-control, the protocol clipboard managers use: it reads and sets
// the clipboard with no window and no keyboard focus, which is what a shell
// and a daemon need (Qt's own clipboard on Wayland works only for a window
// that has focus).
//
// The shell's clipboard history used to run `bash -c` around
// `wl-paste --watch sh -c 'wl-paste --type text | head -c 262144; printf …'`,
// with traps so the watcher did not outlive its parent, and a poll on a timer
// for compositors where the watch delivered nothing. This is that watch:
// one process, text only, a size limit, and it goes when its reader does.

#include <cerrno>
#include <dirent.h>
#include <cstdint>
#include <csignal>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fcntl.h>
#include <poll.h>
#include <string>
#include <unistd.h>
#include <vector>
#include <wayland-client.h>

#include "wlr-data-control-unstable-v1-client-protocol.h"

namespace {

struct wl_seat* g_seat = nullptr;
struct zwlr_data_control_manager_v1* g_manager = nullptr;
uint32_t g_manager_version = 0;   // the primary selection needs 2

// Text a source may offer, best first.
const char* const kTextTypes[] = {
    "text/plain;charset=utf-8", "text/plain", "UTF8_STRING", "STRING", "TEXT"};

void registry_global(void*, struct wl_registry* registry, uint32_t name, const char* interface,
                     uint32_t version) {
    if (std::strcmp(interface, wl_seat_interface.name) == 0 && !g_seat) {
        g_seat = static_cast<wl_seat*>(wl_registry_bind(registry, name, &wl_seat_interface, 1));
    } else if (std::strcmp(interface, zwlr_data_control_manager_v1_interface.name) == 0) {
        g_manager_version = version < 2 ? version : 2;
        g_manager = static_cast<zwlr_data_control_manager_v1*>(
            wl_registry_bind(registry, name, &zwlr_data_control_manager_v1_interface, g_manager_version));
    }
}
void registry_global_remove(void*, struct wl_registry*, uint32_t) {}
const struct wl_registry_listener kRegistry = {registry_global, registry_global_remove};

// ── Reading ─────────────────────────────────────────────────────────────────

struct Offer {
    struct zwlr_data_control_offer_v1* offer;
    std::vector<std::string> types;
};

std::vector<Offer> g_offers;

void offer_type(void*, struct zwlr_data_control_offer_v1* offer, const char* type) {
    for (auto& o : g_offers)
        if (o.offer == offer) o.types.emplace_back(type);
}
const struct zwlr_data_control_offer_v1_listener kOfferListener = {offer_type};

struct Reader {
    struct wl_display* display;
    size_t max;
    bool watch;
    bool primary;            // the middle-click selection, not the clipboard
    std::string type;        // paste -t: this type; empty or "text": text
    bool list = false;       // paste --list-types
    bool got = false;        // a selection event arrived
    bool found = false;      // ...and it had what was asked for
    bool finished = false;
};

const char* text_type_of(const Offer& o) {
    for (const char* want : kTextTypes)
        for (const auto& t : o.types)
            if (t == want) return want;
    return nullptr;
}

// The offer's data, at most `max` bytes. The source writes it into a pipe;
// it is read until the source closes its end. Kept in `out`, or, when `out`
// is null, passed straight to stdout as it comes (paste): a paste of a large
// image then never sits in memory whole.
bool read_offer(struct wl_display* display, Offer& o, const char* type, size_t max, std::string* out) {
    int fds[2];
    if (pipe2(fds, O_CLOEXEC) != 0) return false;
    zwlr_data_control_offer_v1_receive(o.offer, type, fds[1]);
    wl_display_flush(display);
    close(fds[1]);
    size_t total = 0;
    char buf[65536];
    for (;;) {
        pollfd p{fds[0], POLLIN, 0};
        // A source that never writes must not hang the watch.
        if (poll(&p, 1, 2000) <= 0) break;
        const ssize_t n = read(fds[0], buf, sizeof(buf));
        if (n > 0) {
            const size_t take = std::min(static_cast<size_t>(n), max - total);
            if (take > 0) {
                if (out) out->append(buf, take);
                else if (std::fwrite(buf, 1, take, stdout) != take) break;
                total += take;
            }
            // Past the limit: stop reading; the source sees the pipe close.
            if (total >= max) break;
        } else if (n < 0 && errno == EINTR) {
            continue;
        } else {
            break;
        }
    }
    close(fds[0]);
    return true;
}

void device_offer(void*, struct zwlr_data_control_device_v1*, struct zwlr_data_control_offer_v1* offer) {
    g_offers.push_back({offer, {}});
    zwlr_data_control_offer_v1_add_listener(offer, &kOfferListener, nullptr);
}

void forget_offers() {
    for (auto& o : g_offers) zwlr_data_control_offer_v1_destroy(o.offer);
    g_offers.clear();
}

void write_all(const std::string& data) {
    size_t off = 0;
    while (off < data.size()) {
        const size_t n = std::fwrite(data.data() + off, 1, data.size() - off, stdout);
        if (n == 0) break;
        off += n;
    }
}

// The selection (or the primary one) changed to `offer`, or to nothing.
void on_selection(Reader* r, struct zwlr_data_control_offer_v1* offer) {
    r->got = true;
    Offer* o = nullptr;
    for (auto& candidate : g_offers)
        if (candidate.offer == offer) o = &candidate;
    if (o && r->list) {
        for (const auto& t : o->types) std::printf("%s\n", t.c_str());
        r->found = !o->types.empty();
    } else if (o) {
        const char* type = nullptr;
        if (r->type.empty() || r->type == "text") {
            type = text_type_of(*o);
        } else {
            for (const auto& t : o->types)
                if (t == r->type) type = t.c_str();
        }
        if (type && r->watch) {
            std::string data;
            r->found = read_offer(r->display, *o, type, r->max, &data);
            if (!data.empty()) {
                write_all(data);
                std::fputc('\x1e', stdout);
            }
        } else if (type) {
            r->found = read_offer(r->display, *o, type, r->max, nullptr);
        }
        std::fflush(stdout);
    }
    // Every offer is announced right before its selection event, and each
    // is read at once: none is needed after this.
    forget_offers();
    if (!r->watch) r->finished = true;
}

void device_selection(void* data, struct zwlr_data_control_device_v1*,
                      struct zwlr_data_control_offer_v1* offer) {
    auto* r = static_cast<Reader*>(data);
    if (!r->primary) on_selection(r, offer);
}

void device_finished(void* data, struct zwlr_data_control_device_v1*) {
    static_cast<Reader*>(data)->finished = true;
}

void device_primary(void* data, struct zwlr_data_control_device_v1*, struct zwlr_data_control_offer_v1* offer) {
    auto* r = static_cast<Reader*>(data);
    if (r->primary) on_selection(r, offer);
}

const struct zwlr_data_control_device_v1_listener kDeviceListener = {
    device_offer, device_selection, device_finished, device_primary};

int read_clipboard(struct wl_display* display, Reader& r) {
    auto* device = zwlr_data_control_manager_v1_get_data_device(g_manager, g_seat);
    zwlr_data_control_device_v1_add_listener(device, &kDeviceListener, &r);
    if (!r.watch) {
        // The current selection arrives right after the device is made: a
        // roundtrip is enough to have it, empty or not.
        if (wl_display_roundtrip(display) < 0) return 1;
        if (!r.found && !r.list)
            std::fprintf(stderr, "b1air-clip: nothing%s%s on the %s\n", r.type.empty() ? "" : " of type ",
                         r.type.c_str(), r.primary ? "primary selection" : "clipboard");
        return r.found ? 0 : 1;
    }
    // Watching: the display and stdin. Stdin closing (the reader went away,
    // or stopped this Process) ends the watch, so it cannot outlive it.
    signal(SIGPIPE, SIG_DFL);
    while (!r.finished) {
        while (wl_display_prepare_read(display) != 0) wl_display_dispatch_pending(display);
        wl_display_flush(display);
        pollfd fds[2] = {{wl_display_get_fd(display), POLLIN, 0}, {STDIN_FILENO, POLLIN, 0}};
        const int n = poll(fds, 2, -1);
        if (n < 0 && errno != EINTR) { wl_display_cancel_read(display); break; }
        if (fds[0].revents & POLLIN) {
            if (wl_display_read_events(display) < 0) break;
            wl_display_dispatch_pending(display);
        } else {
            wl_display_cancel_read(display);
        }
        if (fds[0].revents & (POLLERR | POLLHUP)) break;
        if (fds[1].revents & (POLLIN | POLLHUP | POLLERR)) {
            char buf[256];
            if (read(STDIN_FILENO, buf, sizeof(buf)) <= 0) break;
        }
    }
    return 0;
}

// ── Writing ─────────────────────────────────────────────────────────────────

struct Source {
    std::string data;
    std::string type;
    bool primary = false;
    bool foreground = false;
    bool cancelled = false;
};

void source_send(void* data, struct zwlr_data_control_source_v1*, const char*, int32_t fd) {
    const auto* s = static_cast<Source*>(data);
    // Non-blocking writes, waiting on the reader for up to 5 s at a time: a
    // reader that takes its time still gets all of it, one that stops reading
    // does not keep this process stuck in write() forever.
    const int flags = fcntl(fd, F_GETFL);
    if (flags >= 0) fcntl(fd, F_SETFL, flags | O_NONBLOCK);
    size_t off = 0;
    while (off < s->data.size()) {
        const ssize_t n = write(fd, s->data.data() + off, s->data.size() - off);
        if (n > 0) { off += static_cast<size_t>(n); continue; }
        if (n < 0 && errno == EINTR) continue;
        if (n < 0 && (errno == EAGAIN || errno == EWOULDBLOCK)) {
            pollfd p{fd, POLLOUT, 0};
            const int r = poll(&p, 1, 5000);
            if (r > 0 && !(p.revents & (POLLERR | POLLHUP | POLLNVAL))) continue;
            if (r < 0 && errno == EINTR) continue;
        }
        break;
    }
    close(fd);
}

void source_cancelled(void* data, struct zwlr_data_control_source_v1*) {
    // Something else was copied: this one is done.
    static_cast<Source*>(data)->cancelled = true;
}

const struct zwlr_data_control_source_v1_listener kSourceListener = {source_send, source_cancelled};

int write_clipboard(struct wl_display* display, Source& s) {
    auto* device = zwlr_data_control_manager_v1_get_data_device(g_manager, g_seat);
    auto* source = zwlr_data_control_manager_v1_create_data_source(g_manager);
    zwlr_data_control_source_v1_add_listener(source, &kSourceListener, &s);
    if (s.type.empty() || s.type == "text") {
        for (const char* t : kTextTypes) zwlr_data_control_source_v1_offer(source, t);
    } else {
        zwlr_data_control_source_v1_offer(source, s.type.c_str());
    }
    if (s.primary) zwlr_data_control_device_v1_set_primary_selection(device, source);
    else zwlr_data_control_device_v1_set_selection(device, source);
    if (wl_display_roundtrip(display) < 0) return 1;

    // Serve it from the background, as wl-copy does: whoever ran this goes
    // on at once, and the data stays pasteable until something replaces it.
    if (!s.foreground) {
        const pid_t pid = fork();
        if (pid < 0) return 1;
        if (pid > 0) _exit(0);
        setsid();
        // Nothing of the caller's stays open here but the compositor's
        // socket: a pipe end inherited from whoever ran this would keep
        // their reader waiting for an end-of-file for as long as this
        // serves the clipboard.
        const int keep = wl_display_get_fd(display);
        if (DIR* fds = opendir("/proc/self/fd")) {
            std::vector<int> open_fds;
            while (const dirent* e = readdir(fds)) {
                const int fd = std::atoi(e->d_name);
                if (e->d_name[0] != '.' && fd > STDERR_FILENO && fd != keep && fd != dirfd(fds))
                    open_fds.push_back(fd);
            }
            closedir(fds);
            for (const int fd : open_fds) close(fd);
        }
        const int null_fd = open("/dev/null", O_RDWR);
        if (null_fd >= 0) {
            dup2(null_fd, STDIN_FILENO);
            dup2(null_fd, STDOUT_FILENO);
            dup2(null_fd, STDERR_FILENO);
            if (null_fd > STDERR_FILENO) close(null_fd);
        }
    }
    signal(SIGPIPE, SIG_IGN);   // a reader that hangs up mid-paste
    while (!s.cancelled && wl_display_dispatch(display) >= 0) {}
    return 0;
}

int clear_clipboard(struct wl_display* display, bool primary) {
    auto* device = zwlr_data_control_manager_v1_get_data_device(g_manager, g_seat);
    if (primary) zwlr_data_control_device_v1_set_primary_selection(device, nullptr);
    else zwlr_data_control_device_v1_set_selection(device, nullptr);
    return wl_display_roundtrip(display) < 0 ? 1 : 0;
}

int usage() {
    std::fputs("usage: b1air-clip copy [-t <mime>] [--primary] [--foreground] [-- <text>...]\n"
               "       b1air-clip paste [-t <mime>|text] [--primary] [--max <bytes>]\n"
               "       b1air-clip paste --list-types [--primary]\n"
               "       b1air-clip watch [--primary] [--max <bytes>]\n"
               "       b1air-clip clear [--primary]\n", stderr);
    return 2;
}

} // namespace

int main(int argc, char** argv) {
    if (argc < 2) return usage();
    const std::string mode = argv[1];
    if (mode != "copy" && mode != "paste" && mode != "watch" && mode != "clear") return usage();

    size_t max = SIZE_MAX;
    std::string type;
    bool primary = false, foreground = false, list = false;
    Source source;
    bool have_args = false;
    for (int i = 2; i < argc; ++i) {
        const std::string a = argv[i];
        if (a == "--max" && i + 1 < argc && mode != "copy") {
            max = std::strtoull(argv[++i], nullptr, 10);
        } else if ((a == "-t" || a == "--type") && i + 1 < argc && (mode == "copy" || mode == "paste")) {
            type = argv[++i];
        } else if (a == "--primary" || a == "-p") {
            primary = true;
        } else if (a == "--foreground" && mode == "copy") {
            foreground = true;
        } else if ((a == "--list-types" || a == "-l") && mode == "paste") {
            list = true;
        } else if (a == "--" && mode == "copy") {
            for (int j = i + 1; j < argc; ++j) {
                if (j > i + 1) source.data += ' ';
                source.data += argv[j];
            }
            have_args = true;
            break;
        } else if (mode == "copy" && !a.empty() && a[0] != '-') {
            // Text with no "--" in front, as wl-copy takes it.
            for (int j = i; j < argc; ++j) {
                if (j > i) source.data += ' ';
                source.data += argv[j];
            }
            have_args = true;
            break;
        } else {
            return usage();
        }
    }
    if (mode == "copy" && !have_args) {
        char buf[65536];
        ssize_t n;
        while ((n = read(STDIN_FILENO, buf, sizeof(buf))) > 0 || (n < 0 && errno == EINTR))
            if (n > 0) source.data.append(buf, static_cast<size_t>(n));
    }

    struct wl_display* display = wl_display_connect(nullptr);
    if (!display) {
        std::fputs("b1air-clip: no Wayland display\n", stderr);
        return 1;
    }
    struct wl_registry* registry = wl_display_get_registry(display);
    wl_registry_add_listener(registry, &kRegistry, nullptr);
    wl_display_roundtrip(display);
    if (!g_seat || !g_manager) {
        std::fputs("b1air-clip: the compositor has no wlr-data-control\n", stderr);
        return 1;
    }
    if (primary && g_manager_version < 2) {
        std::fputs("b1air-clip: the compositor has no primary selection over data-control\n", stderr);
        return 1;
    }

    if (mode == "clear") return clear_clipboard(display, primary);
    if (mode == "copy") {
        source.type = type;
        source.primary = primary;
        source.foreground = foreground;
        return write_clipboard(display, source);
    }
    Reader r{display, max, mode == "watch", primary, type};
    r.list = list;
    return read_clipboard(display, r);
}
