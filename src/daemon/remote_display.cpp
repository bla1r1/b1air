#include "remote_display.hpp"

#include "idle.hpp"
#include "proc_util.hpp"
#include "runtime.hpp"
#include "settings_manager.hpp"
#include "sway_ipc.hpp"
#include "system_control.hpp"

#include <nlohmann/json.hpp>

#include <algorithm>
#include <ctime>
#include <atomic>
#include <chrono>
#include <cstdio>
#include <fcntl.h>
#include <fstream>
#include <glob.h>
#include <iostream>
#include <poll.h>
#include <sstream>
#include <sys/eventfd.h>
#include <sys/inotify.h>
#include <thread>
#include <unistd.h>
#include <vector>

namespace b1air::remote_display {

namespace {

using Clock = std::chrono::steady_clock;

struct Out {
    std::string name;
    bool active = false;
    bool power = false;
    int width = 0, height = 0;
    int refresh = 0;   // mHz
    double scale = 1.0;
};

// What this thread did, kept in the runtime directory so a daemon restarted
// in place (session-restart, on every install) takes over from itself.
// Written whole and renamed into place: the D-Bus thread reads it too.
struct State {
    std::string virt;                   // the output it made
    std::vector<std::string> disabled;  // the screens it put away for it
    // Between asking sway for an output and knowing its name: the outputs
    // there were before, so one made just as the daemon was replaced is
    // still found and taken back rather than left behind as a "screen".
    bool creating = false;
    std::vector<std::string> before;
};

std::atomic<int> g_event{-1};   // the running thread's wake-up, in this process

std::string state_path() { return runtime_path("remote-display.json"); }

State load() {
    State s;
    std::ifstream in(state_path());
    const auto j = nlohmann::json::parse(in, nullptr, false);
    if (!j.is_object()) return s;
    s.virt = j.value("virtual", std::string());
    s.creating = j.value("creating", false);
    if (j.contains("disabled") && j["disabled"].is_array())
        for (const auto& d : j["disabled"]) if (d.is_string()) s.disabled.push_back(d.get<std::string>());
    if (j.contains("before") && j["before"].is_array())
        for (const auto& d : j["before"]) if (d.is_string()) s.before.push_back(d.get<std::string>());
    return s;
}

void save(const State& s) {
    if (s.virt.empty() && s.disabled.empty() && !s.creating) {
        std::remove(state_path().c_str());
        return;
    }
    nlohmann::json j{{"virtual", s.virt}, {"disabled", s.disabled}};
    if (s.creating) {
        j["creating"] = true;
        j["before"] = s.before;
    }
    const std::string tmp = state_path() + ".tmp";
    {
        std::ofstream out(tmp, std::ios::trunc);
        out << j.dump() << "\n";
        if (!out) return;
    }
    std::rename(tmp.c_str(), state_path().c_str());
}

bool internal(const std::string& name) {
    return name.rfind("eDP", 0) == 0 || name.rfind("LVDS", 0) == 0 || name.rfind("DSI", 0) == 0;
}

std::string read_word(const std::string& path) {
    std::ifstream in(path);
    std::string w;
    in >> w;
    return w;
}

// The lid: as the session last heard it (lid_event writes it — the lid switch
// is not ACPI on every machine), else ACPI's own; open where there is none.
bool lid_closed() {
    glob_t g{};
    int found = 0;
    bool closed = false;
    if (glob("/proc/acpi/button/lid/*/state", 0, nullptr, &g) == 0) {
        for (size_t i = 0; i < g.gl_pathc; ++i) {
            std::ifstream in(g.gl_pathv[i]);
            std::string text((std::istreambuf_iterator<char>(in)), {});
            ++found;
            if (text.find("closed") != std::string::npos) closed = true;
        }
    }
    globfree(&g);
    if (found) return closed;
    // No ACPI lid: as the session last heard it (reset when the session
    // starts, so one left from before does not black out an open laptop).
    return read_word(runtime_path("lid-state")) == "closed";
}

std::vector<Out> outputs(SwayIPC& ipc) {
    std::vector<Out> out;
    const auto j = nlohmann::json::parse(ipc.get_outputs(), nullptr, false);
    if (!j.is_array()) return out;
    for (const auto& o : j) {
        Out x;
        x.name = o.value("name", std::string());
        x.active = o.value("active", false);
        // swayfx says "power"; sway before 1.8 "dpms".
        x.power = o.contains("power") ? o.value("power", true) : o.value("dpms", true);
        if (o.contains("current_mode") && o["current_mode"].is_object()) {
            x.width = o["current_mode"].value("width", 0);
            x.height = o["current_mode"].value("height", 0);
            x.refresh = o["current_mode"].value("refresh", 0);
        }
        if (o.contains("scale") && o["scale"].is_number()) x.scale = o["scale"].get<double>();
        if (!x.name.empty()) out.push_back(x);
    }
    return out;
}

void command(SwayIPC& ipc, const std::string& cmd) {
    (void)ipc.send_command(0, cmd);
}

std::string in_quotes(const std::string& name) { return "\"" + name + "\""; }

// wayvnc captures one output, by name: when that one goes (put away for the
// virtual one, or the virtual one unplugged) it is moved to `name`, or the
// viewer's picture would freeze on a screen that is no longer there.
void vnc_follow(const std::string& name) {
    if (name.empty() || !SystemControl::remote_state().vnc) return;
    (void)util::spawn_detached({"wayvncctl", "output-set", name});
}

// RustDesk keeps capturing the output it started on, and never starts its
// Wayland capture again by itself (it would ask for the screen again every
// few minutes otherwise, upstream says). A session under way when the
// screen changes is moved by restarting its server: RustDesk's service
// starts it again at once, and the viewer reconnects onto the screen there
// is now.
void rustdesk_follow(bool session) {
    if (!session) return;
    std::cerr << "[b1air-remote] the screen changed under a RustDesk session: its server restarts\n";
    (void)SystemControl::rustdesk_restart_server();
}

// The outputs that are neither the virtual one nor the tablet's (sidecar):
// the ones a person here can see.
std::vector<Out> physical(const std::vector<Out>& now, const State& st, const std::string& sidecar) {
    std::vector<Out> phys;
    for (const auto& o : now)
        if (o.name != st.virt && o.name != sidecar) phys.push_back(o);
    return phys;
}

// A virtual output the size of `like` (the screen it stands in for), with
// the screens in `put_away` disabled once it is up, so their workspaces
// move onto it.
bool create(SwayIPC& ipc, State& st, const std::vector<Out>& now, const Out& like,
            const std::vector<std::string>& put_away, bool rustdesk_session) {
    st.creating = true;
    st.before.clear();
    for (const auto& o : now) st.before.push_back(o.name);
    save(st);
    command(ipc, "create_output");
    std::string made;
    for (int i = 0; i < 20 && made.empty(); ++i) {
        std::this_thread::sleep_for(std::chrono::milliseconds(50));
        for (const auto& o : outputs(ipc))
            if (std::find(st.before.begin(), st.before.end(), o.name) == st.before.end()) made = o.name;
    }
    st.creating = false;
    st.before.clear();
    if (made.empty()) {
        std::cerr << "[b1air-remote] sway made no virtual output (create_output)\n";
        save(st);
        return false;
    }
    const int w = like.width > 0 ? like.width : 1920, h = like.height > 0 ? like.height : 1080;
    // With a refresh rate: sway makes the output with none (0 Hz), and the
    // screencast portal then offers PipeWire a stream with no frame rate —
    // RustDesk's pipeline never started, and the viewer saw black.
    std::ostringstream scale, rate;
    scale << (like.scale > 0 ? like.scale : 1.0);
    rate << (like.refresh > 0 ? like.refresh / 1000.0 : 60.0);
    command(ipc, "output " + in_quotes(made) + " mode " + std::to_string(w) + "x" + std::to_string(h)
                 + "@" + rate.str() + "Hz scale " + scale.str() + " enable");
    st.virt = made;
    save(st);
    for (const auto& name : put_away) {
        command(ipc, "output " + in_quotes(name) + " disable");
        st.disabled.push_back(name);
    }
    save(st);
    vnc_follow(made);
    rustdesk_follow(rustdesk_session);
    std::cerr << "[b1air-remote] " << made << " (" << w << "x" << h << ") stands in for "
              << (put_away.empty() ? std::string("no screen") : put_away.front()) << "\n";
    return true;
}

// The screens back, then the virtual one gone: sway returns each workspace
// to the screen it came from.
void restore(SwayIPC& ipc, State& st, bool lid, const std::string& sidecar, bool rustdesk_session) {
    for (const auto& name : st.disabled) {
        command(ipc, "output " + in_quotes(name) + " enable");
        if (internal(name) && lid) command(ipc, "output " + in_quotes(name) + " power off");
    }
    // VNC onto a screen someone can see before the virtual one goes: one
    // that is up and lit — a monitor plugged in, the laptop's own with its
    // lid open — never the panel under a closed lid.
    std::string back_to;
    for (const auto& o : physical(outputs(ipc), st, sidecar))
        if (o.active && o.power && !(lid && internal(o.name))) { back_to = o.name; break; }
    vnc_follow(back_to);
    const bool had_virtual = !st.virt.empty();
    if (had_virtual) {
        std::this_thread::sleep_for(std::chrono::milliseconds(300));
        command(ipc, "output " + in_quotes(st.virt) + " unplug");
        std::cerr << "[b1air-remote] " << st.virt << " gone\n";
        // Where every workspace landed, for the case of windows that were
        // not drawn after the lid opened until the overview was opened and
        // closed (not reproduced on a headless sway: this is to see it).
        std::this_thread::sleep_for(std::chrono::milliseconds(500));
        const auto ws = nlohmann::json::parse(ipc.send_command(1), nullptr, false);
        std::string where;
        if (ws.is_array())
            for (const auto& w : ws)
                where += " " + w.value("name", std::string()) + "@" + w.value("output", std::string())
                       + (w.value("visible", false) ? "+visible" : "") + (w.value("focused", false) ? "+focused" : "");
        const std::time_t t = std::time(nullptr);
        char at[16];
        std::strftime(at, sizeof(at), "%H:%M:%S", std::localtime(&t));
        std::cerr << "[b1air-remote] " << at << " workspaces now:" << where << "\n";
    }
    st = State{};
    save(st);
    if (had_virtual) rustdesk_follow(rustdesk_session);
}

// What to do, from one look.
enum class Act { None, Create, Wake, Restore };

Act decide(const State& st, const std::vector<Out>& now, const SystemControl::RemoteState& rs, bool lid,
           bool lid_keeps_up, bool enabled, const std::string& sidecar, Out* like,
           std::vector<std::string>* put_away) {
    const std::vector<Out> phys = physical(now, st, sidecar);
    const bool any_active = std::any_of(phys.begin(), phys.end(), [](const Out& o) { return o.active; });
    // Lit and in view: the laptop's own panel under a closed lid is not.
    const bool any_usable = std::any_of(phys.begin(), phys.end(), [&](const Out& o) {
        return o.active && o.power && !(lid && internal(o.name));
    });
    const bool serving = enabled && rs.serving();

    // Screens put away for a virtual one that is gone (unplugged by hand,
    // say): back, whatever else is true — never left disabled.
    if (st.virt.empty()) {
        if (!st.disabled.empty()) return Act::Restore;
    } else {
        bool release = !serving || any_usable;
        const bool lid_put_away = std::any_of(st.disabled.begin(), st.disabled.end(), internal);
        if (lid_put_away && !lid) release = true;   // the lid is open again
        return release ? Act::Restore : Act::None;
    }
    if (!serving) return Act::None;

    // A virtual screen ready before anyone connects, whenever there is no
    // screen here to show: nothing plugged in or enabled, or only the
    // laptop's own with its lid shut. Whoever connects is shown it from the
    // first frame, and nothing they capture goes away under them.
    if (!any_active) {
        for (const auto& o : phys) if (o.width > like->width) *like = o;
        return Act::Create;
    }
    // Only while the machine stays up with its lid shut: someone connected,
    // the lid's own action waiting for them to go, or a lid set to lock or
    // do nothing. With the lid set to sleep it sleeps, and moving every
    // window to a virtual screen on the way only moved them back on waking.
    bool only_lid = lid && lid_keeps_up;
    for (const auto& o : phys)
        if (o.active && !internal(o.name)) only_lid = false;
    if (only_lid) {
        for (const auto& o : phys)
            if (o.active) {
                if (o.width > like->width) *like = o;
                put_away->push_back(o.name);
            }
        return Act::Create;
    }
    // Someone connected, and the screens are dark because nobody is here
    // (idle): they are woken.
    if (rs.viewer() && !any_usable) return Act::Wake;
    return Act::None;
}

// Waits up to `ms` for a reason to look again: this process's poke, or the
// poke file written by another (the lid's command, Settings'). Anything
// else written in the runtime directory is no reason, and the wait goes on.
void wait_for_poke(int inotify_fd, int ms) {
    const auto until = Clock::now() + std::chrono::milliseconds(ms);
    while (true) {
        const auto left = std::chrono::duration_cast<std::chrono::milliseconds>(until - Clock::now()).count();
        if (left <= 0) return;
        pollfd fds[2] = {{g_event.load(), POLLIN, 0}, {inotify_fd, POLLIN, 0}};
        if (poll(fds, inotify_fd >= 0 ? 2 : 1, static_cast<int>(left)) <= 0) return;
        if (fds[0].revents & POLLIN) {
            uint64_t n;
            (void)!read(g_event.load(), &n, sizeof(n));
            return;
        }
        if (inotify_fd >= 0 && (fds[1].revents & POLLIN)) {
            alignas(inotify_event) char buf[4096];
            bool ours = false;
            ssize_t r;
            while ((r = read(inotify_fd, buf, sizeof(buf))) > 0)
                for (char* p = buf; p < buf + r;) {
                    const auto* ev = reinterpret_cast<const inotify_event*>(p);
                    if (ev->len && std::string(ev->name) == "remote-poke") ours = true;
                    p += sizeof(inotify_event) + ev->len;
                }
            if (ours) return;
        }
    }
}

} // namespace

void poke() {
    // In the daemon, the thread is woken; from anywhere else (the lid's and
    // Settings' short-lived commands) through a file it watches.
    if (const int fd = g_event.load(); fd >= 0) {
        const uint64_t one = 1;
        (void)!write(fd, &one, sizeof(one));
        return;
    }
    const int fd = open(runtime_path("remote-poke").c_str(), O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC, 0600);
    if (fd >= 0) close(fd);
}

std::string virtual_output() { return load().virt; }

void run(const volatile int* running) {
    g_event = eventfd(0, EFD_CLOEXEC | EFD_NONBLOCK);
    const int in = inotify_init1(IN_NONBLOCK | IN_CLOEXEC);
    if (in >= 0) inotify_add_watch(in, runtime_dir().c_str(), IN_CLOSE_WRITE | IN_CREATE);

    // A decision is acted on once it has held this long — the moment a
    // screen goes through (idle, a lid half closed, a monitor re-plugged)
    // does not move every window back and forth.
    constexpr auto kSettle = std::chrono::milliseconds(700);
    // The lid shut under someone working from afar did not put the machine
    // to sleep; once they have been gone this long, it does what the lid
    // does. A dropped Wi-Fi or a RustDesk relay reconnecting is shorter.
    constexpr auto kLidGrace = std::chrono::seconds(25);
    // wayvnc that keeps ending on the virtual screen is not restarted for ever.
    constexpr int kMaxRevives = 3;

    Act pending = Act::None;
    Clock::time_point pending_since{};
    bool vnc_revive = false;
    int vnc_port = 5900;
    int revives = 0;
    Clock::time_point revive_window = Clock::now();
    bool was_viewer = false;
    Clock::time_point viewer_gone = Clock::now();
    Clock::time_point create_again{};

    while (*running) {
        SwayIPC ipc;
        if (!ipc.connect()) {
            std::this_thread::sleep_for(std::chrono::seconds(2));
            continue;
        }
        State st = load();
        auto now = outputs(ipc);
        const std::string sidecar = read_word(runtime_path("sidecar-output"));

        // Made just as the daemon was replaced, its name never recorded:
        // found again by what was not there before.
        if (st.creating) {
            for (const auto& o : now)
                if (o.name.rfind("HEADLESS-", 0) == 0 && o.name != sidecar
                    && std::find(st.before.begin(), st.before.end(), o.name) == st.before.end())
                    st.virt = o.name;
            st.creating = false;
            st.before.clear();
            save(st);
        }
        // Unplugged by someone else: forgotten (what it put away comes back).
        if (!st.virt.empty() && std::none_of(now.begin(), now.end(), [&](const Out& o) { return o.name == st.virt; })) {
            st.virt.clear();
            save(st);
        }
        const bool lid = lid_closed();
        const bool enabled = SettingsManager::get_json_bool("remoteVirtualDisplay", true);
        SystemControl::RemoteState rs = SystemControl::remote_state();

        // wayvnc ended by itself as the last screen went (it has no other to
        // fall back on): it is still wanted, on the virtual screen.
        const auto phys = physical(now, st, sidecar);
        const bool any_active = std::any_of(phys.begin(), phys.end(), [](const Out& o) { return o.active; });
        if (rs.vnc_died) {
            if (Clock::now() - revive_window > std::chrono::minutes(5)) {
                revives = 0;
                revive_window = Clock::now();
            }
            if (!any_active && enabled && revives < kMaxRevives) {
                vnc_port = rs.vnc_port;
                vnc_revive = true;
            }
            // Read once: a server that ended with screens still here simply
            // stopped (or crashed), and is not started again behind anyone.
            std::remove(runtime_path("wayvnc.pid").c_str());
        }
        if (vnc_revive) rs.vnc = true;
        if (vnc_revive && !st.virt.empty()) {
            vnc_revive = false;
            ++revives;
            std::cerr << "[b1air-remote] VNC again, on the virtual screen\n";
            if (!SystemControl::remote_desktop_start(vnc_port, "")) std::cerr << "[b1air-remote] VNC did not start\n";
        }

        // Someone was connected and is not now.
        const bool viewer = rs.viewer();
        if (was_viewer && !viewer) {
            viewer_gone = Clock::now();
            // What idle skipped while they were here counts down again.
            idle::reload();
        }
        was_viewer = viewer;
        const std::string deferred = runtime_path("lid-deferred");
        bool lid_waiting = false;
        if (access(deferred.c_str(), F_OK) == 0) {
            if (!lid) {
                std::remove(deferred.c_str());
            } else if (!viewer && Clock::now() - viewer_gone >= kLidGrace) {
                std::remove(deferred.c_str());
                std::cerr << "[b1air-remote] nobody connected any more: what the lid does, now\n";
                // The screens back first: asleep with every window on the
                // virtual one, waking with the lid open showed nothing until
                // they had moved back.
                // Only when the lid puts it to sleep or off: a lid that locks
                // or does nothing keeps the virtual screen, and restoring
                // first only moved every window there and back again.
                const std::string action = SystemControl::lid_action();
                if ((action == "sleep" || action == "shutdown") && (!st.virt.empty() || !st.disabled.empty()))
                    restore(ipc, st, true, sidecar, false);
                (void)SystemControl::lid_event(true);
            } else {
                lid_waiting = true;
            }
        }

        Out like;
        std::vector<std::string> put_away;
        const std::string lid_does = SystemControl::lid_action();
        const bool lid_keeps_up = rs.viewer() || lid_waiting || access(deferred.c_str(), F_OK) == 0
                                  || (lid_does != "sleep" && lid_does != "shutdown");
        const Act act = decide(st, now, rs, lid, lid_keeps_up, enabled, sidecar, &like, &put_away);
        // The lid opened on a screen put away for the virtual one: back at
        // once — undoing is safe, and the settling is there for making one.
        // Waiting showed a dark panel, and the lock screen only on the
        // virtual screen, for a second after every wake.
        const bool lid_opened = act == Act::Restore && !lid
                                && std::any_of(st.disabled.begin(), st.disabled.end(), internal);
        if (act != pending && !lid_opened) {
            pending = act;
            pending_since = Clock::now();
        } else if (act != Act::None && (lid_opened || Clock::now() - pending_since >= kSettle)) {
            if (act == Act::Create) {
                // A sway that will not make one is asked again later, not
                // every second.
                if (Clock::now() >= create_again && !create(ipc, st, now, like, put_away, rs.rustdesk_session))
                    create_again = Clock::now() + std::chrono::seconds(30);
            }
            else if (act == Act::Restore) restore(ipc, st, lid, sidecar, rs.rustdesk_session);
            else if (act == Act::Wake) {
                for (const auto& o : phys)
                    if (o.active && !o.power && !(lid && internal(o.name)))
                        command(ipc, "output " + in_quotes(o.name) + " power on");
            }
            pending = Act::None;
        }
        ipc.disconnect();

        // A decision settling is looked at again soon, a lid action waiting
        // out its grace now and then; otherwise at a poke (an output event,
        // the lid, Settings) or after a while.
        wait_for_poke(in, pending != Act::None ? 350 : lid_waiting ? 2000 : 3000);
    }
    if (in >= 0) close(in);
    close(g_event.exchange(-1));
}

} // namespace b1air::remote_display
