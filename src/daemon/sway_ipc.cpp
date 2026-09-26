#include "sway_ipc.hpp"
#include <functional>
#include <nlohmann/json.hpp>

#include <iostream>
#include <vector>
#include <cstring>
#include <cstdlib>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <dirent.h>
#include <sys/stat.h>

namespace b1air {

static const char* I3_MAGIC = "i3-ipc";
static const size_t I3_MAGIC_LEN = 6;
static const size_t I3_HEADER_LEN = 14;

SwayIPC::SwayIPC() {
    socket_path_ = find_socket_path();
}

SwayIPC::~SwayIPC() {
    disconnect();
}

// sway-ipc.<uid>.<pid>.sock outlives its sway (a crash, a restart), so a
// name that exists says nothing; the pid in it says whether anyone listens.
static bool sway_socket_alive(const std::string& path) {
    const std::string name = path.substr(path.rfind('/') + 1);
    // sway-ipc . <uid> . <pid> . sock
    const size_t a = name.find('.'), b = name.find('.', a + 1), c = name.find('.', b + 1);
    if (a == std::string::npos || b == std::string::npos || c == std::string::npos) return false;
    return access(("/proc/" + name.substr(b + 1, c - b - 1)).c_str(), F_OK) == 0;
}

// SWAYSOCK (or I3SOCK) while its sway lives; otherwise the newest live
// socket in the runtime directory. The first one found was taken before, and
// a directory that had seen a sway restart held dead ones to find first.
std::string SwayIPC::find_socket_path() {
    for (const char* var : {"SWAYSOCK", "I3SOCK"}) {
        const char* env = std::getenv(var);
        if (env && env[0] != '\0' && access(env, F_OK) == 0
                && (std::strncmp(var, "I3SOCK", 6) == 0 || sway_socket_alive(env)))
            return env;
    }

    const char* xdg = std::getenv("XDG_RUNTIME_DIR");
    const std::string dir_path = xdg && *xdg ? xdg : "/run/user/" + std::to_string(getuid());
    std::string best;
    time_t newest = 0;
    if (DIR* dir = opendir(dir_path.c_str())) {
        while (struct dirent* entry = readdir(dir)) {
            if (std::strncmp(entry->d_name, "sway-ipc.", 9) != 0) continue;
            const std::string path = dir_path + "/" + entry->d_name;
            struct stat st {};
            if (!sway_socket_alive(path) || stat(path.c_str(), &st) != 0) continue;
            if (best.empty() || st.st_mtime > newest) {
                best = path;
                newest = st.st_mtime;
            }
        }
        closedir(dir);
    }
    if (!best.empty()) return best;
    // Nothing alive: the variable as given, so the error names it.
    const char* env = std::getenv("SWAYSOCK");
    return env ? env : "";
}

bool SwayIPC::connect() {
    if (fd_ >= 0) return true;
    if (socket_path_.empty()) {
        socket_path_ = find_socket_path();
        if (socket_path_.empty()) return false;
    }

    fd_ = ::socket(AF_UNIX, SOCK_STREAM, 0);
    if (fd_ < 0) return false;

    struct sockaddr_un addr;
    std::memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    std::strncpy(addr.sun_path, socket_path_.c_str(), sizeof(addr.sun_path) - 1);

    if (::connect(fd_, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        ::close(fd_);
        fd_ = -1;
        return false;
    }

    return true;
}

void SwayIPC::disconnect() {
    if (fd_ >= 0) {
        ::close(fd_);
        fd_ = -1;
    }
}

bool SwayIPC::send_message(uint32_t type, const std::string& payload) {
    if (fd_ < 0 && !connect()) {
        return false;
    }

    uint32_t len = static_cast<uint32_t>(payload.size());
    std::vector<uint8_t> buffer(I3_HEADER_LEN + len);

    std::memcpy(buffer.data(), I3_MAGIC, I3_MAGIC_LEN);
    std::memcpy(buffer.data() + 6, &len, sizeof(len));
    std::memcpy(buffer.data() + 10, &type, sizeof(type));
    if (len > 0) {
        std::memcpy(buffer.data() + I3_HEADER_LEN, payload.data(), len);
    }

    size_t total = 0;
    while (total < buffer.size()) {
        ssize_t n = ::write(fd_, buffer.data() + total, buffer.size() - total);
        if (n <= 0) {
            disconnect();
            return false;
        }
        total += n;
    }

    return true;
}

bool SwayIPC::read_message(uint32_t& out_type, std::string& out_payload) {
    if (fd_ < 0) {
        return false;
    }

    uint8_t header[I3_HEADER_LEN];
    size_t total = 0;
    while (total < I3_HEADER_LEN) {
        ssize_t n = ::read(fd_, header + total, I3_HEADER_LEN - total);
        if (n <= 0) {
            disconnect();
            return false;
        }
        total += n;
    }

    if (std::memcmp(header, I3_MAGIC, I3_MAGIC_LEN) != 0) {
        disconnect();
        return false;
    }

    uint32_t len = 0;
    std::memcpy(&len, header + 6, sizeof(len));
    std::memcpy(&out_type, header + 10, sizeof(out_type));

    out_payload.resize(len);
    total = 0;
    while (total < len) {
        ssize_t n = ::read(fd_, &out_payload[total], len - total);
        if (n <= 0) {
            disconnect();
            return false;
        }
        total += n;
    }

    return true;
}

std::string SwayIPC::send_command(uint32_t type, const std::string& payload) {
    if (!send_message(type, payload)) {
        return "";
    }
    uint32_t resp_type = 0;
    std::string response;
    if (!read_message(resp_type, response)) {
        return "";
    }
    return response;
}

bool SwayIPC::run_command(const std::string& cmd) {
    if (!is_connected() && !connect()) return false;
    const auto reply = nlohmann::json::parse(send_command(0, cmd), nullptr, false);
    if (!reply.is_array() || reply.empty()) return false;
    for (const auto& r : reply)
        if (!r.is_object() || !r.value("success", false)) return false;
    return true;
}

bool SwayIPC::run(const std::string& cmd) {
    SwayIPC ipc;
    return ipc.run_command(cmd);
}

std::string SwayIPC::get_tree() {
    return send_command(4); // 4 = GET_TREE
}

std::string SwayIPC::get_inputs() {
    return send_command(100); // 100 = GET_INPUTS
}

std::string SwayIPC::get_outputs() {
    return send_command(3); // 3 = GET_OUTPUTS
}

// Quick helper to search for focused window in tree JSON
// Find the focused node in sway's tree and fill `out` from it.
//
// This used to slice the JSON by hand: find `"focused":true`, take the nearest
// `{` before it and the nearest `}` after, and read fields out of a ~300 byte
// window around that. Both ends were wrong. The nearest `{` going backwards
// lands inside one of the nested objects sway emits before "focused" — rect,
// window_rect, deco_rect, geometry — not at the start of the window node; and
// the window was far too short: measured against a live tree, `app_id` sits
// 1083 bytes *after* "focused", well outside it.
//
// So app_id was never once extracted. The old code papered over that by falling
// back to the node's `name`, which is why the screen-time database filled up
// with window titles ("Git — DotsFiles") and workspace names ("1") in the
// column meant to hold application classes — the single largest "app" in
// b1air-daemon stats was a workspace number.
//
// nlohmann::json is already a dependency of this daemon, so the tree is parsed
// as the structured document it is.
// A string field, or the fallback when the field is missing *or null*.
//
// nlohmann's value("key", "") only falls back when the key is absent; a key
// that is present with the wrong type throws. sway reports "app_id": null for
// every XWayland window and "name": null for split containers, so focusing
// GitHub Desktop, Steam or Discord threw out of here, through the focus
// tracker's event callback, into std::terminate — and took the whole session
// daemon with it: settings stopped applying, autotiling stopped, the shell's
// D-Bus service went away. Found as a SIGABRT core from a live session.
static std::string str_field(const nlohmann::json& n, const char* key, const std::string& fallback = "") {
    auto it = n.find(key);
    return (it != n.end() && it->is_string()) ? it->get<std::string>() : fallback;
}

static bool parse_focused_node(const std::string& json_text, WindowInfo& out) {
    nlohmann::json tree;
    try {
        tree = nlohmann::json::parse(json_text);
    } catch (...) {
        return false;
    }

    const nlohmann::json* found = nullptr;

    // Depth-first for the node carrying focused:true. Only containers can be
    // application windows; a focused workspace or output means nothing is.
    std::function<void(const nlohmann::json&)> walk = [&](const nlohmann::json& n) {
        if (found || !n.is_object()) return;
        auto fo = n.find("focused");
        if (fo != n.end() && fo->is_boolean() && fo->get<bool>()) {
            found = &n;
            return;
        }
        for (const char* key : {"nodes", "floating_nodes"}) {
            auto it = n.find(key);
            if (it != n.end() && it->is_array()) {
                for (const auto& child : *it) {
                    walk(child);
                    if (found) return;
                }
            }
        }
    };
    walk(tree);

    if (!found) return false;
    const nlohmann::json& node = *found;

    const std::string type = str_field(node, "type");
    if (type != "con" && type != "floating_con") {
        // A workspace or output has focus, so no window does. Reported as
        // focused with an empty class, which is what the session tracker
        // records as "Desktop".
        out.focused = true;
        out.title = str_field(node, "name");
        return true;
    }

    out.focused = true;
    out.id = (node.contains("id") && node["id"].is_number()) ? node["id"].get<long long>() : 0;
    out.title = str_field(node, "name");

    // Wayland gives app_id; XWayland gives window_properties.class.
    out.app_class = str_field(node, "app_id");
    if (out.app_class.empty()) {
        auto wp = node.find("window_properties");
        if (wp != node.end() && wp->is_object())
            out.app_class = str_field(*wp, "class");
    }

    out.fullscreen = node.contains("fullscreen_mode") && node["fullscreen_mode"].is_number()
                     && node["fullscreen_mode"].get<int>() > 0;

    const std::string floating = str_field(node, "floating");
    out.floating = (floating == "auto_on" || floating == "user_on")
                   || type == "floating_con";

    auto rect = node.find("rect");
    if (rect != node.end() && rect->is_object()) {
        auto num = [&](const char* k) {
            auto f = rect->find(k);
            return (f != rect->end() && f->is_number()) ? f->get<int>() : 0;
        };
        out.width  = num("width");
        out.height = num("height");
    }

    return true;
}


WindowInfo SwayIPC::get_focused_window() {
    WindowInfo info;
    std::string tree = get_tree();
    if (!tree.empty()) {
        parse_focused_node(tree, info);
    }
    return info;
}

bool SwayIPC::toggle_fullscreen() {
    WindowInfo win = get_focused_window();
    if (win.fullscreen) {
        send_command(0, "fullscreen disable");
        if (win.floating) {
            send_command(0, "resize set width 1280 px height 720 px; move position center");
        }
    } else {
        send_command(0, "fullscreen enable");
    }
    return true;
}

bool SwayIPC::subscribe_events(const std::vector<std::string>& events, EventCallback callback) {
    if (fd_ < 0 && !connect()) {
        return false;
    }

    // Format JSON array: ["window", "workspace"]
    std::string payload = "[";
    for (size_t i = 0; i < events.size(); ++i) {
        payload += "\"" + events[i] + "\"";
        if (i + 1 < events.size()) payload += ",";
    }
    payload += "]";

    if (!send_message(2, payload)) { // 2 = SUBSCRIBE
        return false;
    }

    uint32_t resp_type = 0;
    std::string response;
    if (!read_message(resp_type, response)) {
        return false;
    }

    // Read loop
    while (true) {
        uint32_t evt_type = 0;
        std::string evt_payload;
        if (!read_message(evt_type, evt_payload)) {
            break;
        }

        // Mask out the highest bit indicating an event
        uint32_t pure_type = evt_type & 0x7FFFFFFF;
        std::string type_name = "unknown";
        if (pure_type == 0) type_name = "workspace";
        else if (pure_type == 3) type_name = "window";
        else if (pure_type == 4) type_name = "barconfig_update";
        else if (pure_type == 5) type_name = "mode";
        else if (pure_type == 6) type_name = "shutdown";
        else if (pure_type == 7) type_name = "tick";

        callback(type_name, evt_payload);
    }

    return true;
}

} // namespace b1air
