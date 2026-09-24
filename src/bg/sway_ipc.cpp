#include "sway_ipc.hpp"

#include <cerrno>
#include <cstdlib>
#include <cstring>
#include <fcntl.h>
#include <sys/socket.h>
#include <sys/un.h>
#include <unistd.h>

namespace {
constexpr char kMagic[] = "i3-ipc";
constexpr size_t kMagicLen = 6;
constexpr size_t kHeaderLen = kMagicLen + 8;
}

int SwayIpc::open_socket() {
    const char* path = std::getenv("SWAYSOCK");
    if (!path || !*path) path = std::getenv("I3SOCK");
    if (!path || !*path) return -1;
    sockaddr_un addr{};
    addr.sun_family = AF_UNIX;
    if (std::strlen(path) >= sizeof addr.sun_path) return -1;
    std::strcpy(addr.sun_path, path);
    const int fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    if (fd < 0) return -1;
    if (::connect(fd, reinterpret_cast<sockaddr*>(&addr), sizeof addr) != 0) {
        ::close(fd);
        return -1;
    }
    return fd;
}

bool SwayIpc::send(int fd, uint32_t type, const std::string& payload) {
    std::string msg(kMagic, kMagicLen);
    const uint32_t len = static_cast<uint32_t>(payload.size());
    msg.append(reinterpret_cast<const char*>(&len), 4);
    msg.append(reinterpret_cast<const char*>(&type), 4);
    msg += payload;
    // Small, and the socket is blocking for writes: sway reads promptly.
    size_t done = 0;
    while (done < msg.size()) {
        const ssize_t n = ::write(fd, msg.data() + done, msg.size() - done);
        if (n < 0 && errno == EINTR) continue;
        if (n <= 0) return false;
        done += static_cast<size_t>(n);
    }
    return true;
}

bool SwayIpc::connect(const std::string& events_json) {
    close();
    query_fd_ = open_socket();
    event_fd_ = open_socket();
    if (!connected() || !send(event_fd_, kSubscribe, events_json)) {
        close();
        return false;
    }
    return true;
}

void SwayIpc::close() {
    if (query_fd_ >= 0) ::close(query_fd_);
    if (event_fd_ >= 0) ::close(event_fd_);
    query_fd_ = event_fd_ = -1;
    query_buf_.clear();
    event_buf_.clear();
}

bool SwayIpc::request(uint32_t type, const std::string& payload) {
    return query_fd_ >= 0 && send(query_fd_, type, payload);
}

bool SwayIpc::read(int fd) {
    std::string& buf = fd == query_fd_ ? query_buf_ : event_buf_;
    char chunk[16384];
    const ssize_t n = ::recv(fd, chunk, sizeof chunk, MSG_DONTWAIT);
    if (n == 0) return false;
    if (n < 0) return errno == EAGAIN || errno == EWOULDBLOCK || errno == EINTR;
    buf.append(chunk, static_cast<size_t>(n));

    while (buf.size() >= kHeaderLen) {
        if (buf.compare(0, kMagicLen, kMagic) != 0) return false;   // out of step
        uint32_t len = 0, type = 0;
        std::memcpy(&len, buf.data() + kMagicLen, 4);
        std::memcpy(&type, buf.data() + kMagicLen + 4, 4);
        if (buf.size() < kHeaderLen + len) break;
        const std::string body = buf.substr(kHeaderLen, len);
        buf.erase(0, kHeaderLen + len);
        if (on_message) on_message(type, body);
    }
    return true;
}
