#pragma once

#include <cstdint>
#include <functional>
#include <string>

// sway's IPC (the i3 protocol), for a poll() loop.
//
// Two connections, because a subscribed socket carries nothing but events
// from then on: one asks questions, the other listens. Messages are read as
// they arrive and handed to `on_message` whole; a dropped connection closes
// both, and the caller reconnects and asks everything afresh.
class SwayIpc {
public:
    static constexpr uint32_t kRunCommand = 0;
    static constexpr uint32_t kGetWorkspaces = 1;
    static constexpr uint32_t kSubscribe = 2;
    static constexpr uint32_t kGetOutputs = 3;
    static constexpr uint32_t kEventBit = 0x80000000u;
    static constexpr uint32_t kWorkspaceEvent = kEventBit | 0;
    static constexpr uint32_t kOutputEvent = kEventBit | 1;
    static constexpr uint32_t kShutdownEvent = kEventBit | 6;

    ~SwayIpc() { close(); }

    bool connect(const std::string& events_json);
    void close();
    bool connected() const { return query_fd_ >= 0 && event_fd_ >= 0; }

    int query_fd() const { return query_fd_; }
    int event_fd() const { return event_fd_; }

    bool request(uint32_t type, const std::string& payload = "");
    // Reads what is waiting on `fd`; false when the connection is gone.
    bool read(int fd);

    std::function<void(uint32_t type, const std::string& body)> on_message;

private:
    static int open_socket();
    static bool send(int fd, uint32_t type, const std::string& payload);

    int query_fd_ = -1;
    int event_fd_ = -1;
    std::string query_buf_;
    std::string event_buf_;
};
