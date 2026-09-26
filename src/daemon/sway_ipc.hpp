#pragma once
#include <string>
#include <vector>
#include <functional>
#include <cstdint>

namespace b1air {

struct WindowInfo {
    std::string app_class;
    std::string title;
    bool focused = false;
    bool fullscreen = false;
    bool floating = false;
    int64_t id = 0;
    int width = 0;
    int height = 0;
};

class SwayIPC {
public:
    SwayIPC();
    ~SwayIPC();

    bool connect();
    void disconnect();
    bool is_connected() const { return fd_ >= 0; }

    std::string send_command(uint32_t type, const std::string& payload = "");
    // A sway command (several, ';'-separated); true when sway accepted every
    // part. Connects first if this one is not connected yet.
    bool run_command(const std::string& cmd);
    // The same on a connection of its own, for a one-off.
    static bool run(const std::string& cmd);
    std::string get_tree();
    std::string get_inputs();
    std::string get_outputs();
    WindowInfo get_focused_window();
    bool toggle_fullscreen();

    // Event listener loop (subscribes to window and workspace events)
    using EventCallback = std::function<void(const std::string& event_type, const std::string& payload)>;
    bool subscribe_events(const std::vector<std::string>& events, EventCallback callback);

private:
    int fd_ = -1;
    std::string socket_path_;

    bool send_message(uint32_t type, const std::string& payload);
    bool read_message(uint32_t& out_type, std::string& out_payload);
    std::string find_socket_path();
};

} // namespace b1air
