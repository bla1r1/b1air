// b1air-fido-uhid — the root half of the phone passkey (src/passkey).
//
// Browsers talk to security keys as HID devices (CTAPHID). b1air-passkey,
// running as the user, answers as one and carries the requests to the phone
// over caBLE; something has to make the HID device for it, and only root can
// open /dev/uhid. Handing the user /dev/uhid itself would hand out every kind
// of HID device — a keyboard among them, and with it keystrokes typed into
// any window — so this program is the only thing that holds it, and all it
// ever makes is one FIDO device with a fixed report descriptor. It moves
// 64-byte reports between that device and one connected client, nothing more.
//
// Who may connect: the user of the active session on seat0, the one whose
// browser the hidraw node is given to (udev's uaccess for security tokens).
// Another account on the machine, or the same one after a switch of user,
// is turned away or dropped.
//
// The device exists only while a client is connected: no b1air-passkey, or
// the setting off, and browsers see no key at all.

#include <linux/uhid.h>
#include <poll.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/un.h>
#include <systemd/sd-login.h>
#include <fcntl.h>
#include <unistd.h>

#include <cerrno>
#include <csignal>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>

namespace {

constexpr const char* kSocketDir = "/run/b1air-fido";
constexpr const char* kSocketPath = "/run/b1air-fido/fido.sock";
constexpr size_t kReport = 64;

// FIDO Alliance usage page, CTAPHID usage, 64-byte input and output reports,
// no report IDs (CTAP 2.1, §11.2.8.1).
constexpr unsigned char kDescriptor[] = {
    0x06, 0xD0, 0xF1,        // Usage Page (FIDO Alliance)
    0x09, 0x01,              // Usage (CTAPHID)
    0xA1, 0x01,              // Collection (Application)
    0x09, 0x20,              //   Usage (Input Report Data)
    0x15, 0x00,              //   Logical Minimum (0)
    0x26, 0xFF, 0x00,        //   Logical Maximum (255)
    0x75, 0x08,              //   Report Size (8)
    0x95, 0x40,              //   Report Count (64)
    0x81, 0x02,              //   Input (Data, Var, Abs)
    0x09, 0x21,              //   Usage (Output Report Data)
    0x15, 0x00,              //   Logical Minimum (0)
    0x26, 0xFF, 0x00,        //   Logical Maximum (255)
    0x75, 0x08,              //   Report Size (8)
    0x95, 0x40,              //   Report Count (64)
    0x91, 0x02,              //   Output (Data, Var, Abs)
    0xC0                     // End Collection
};

volatile sig_atomic_t g_stop = 0;

void log(const char* fmt, const char* arg = "") {
    std::fprintf(stderr, "b1air-fido-uhid: ");
    std::fprintf(stderr, fmt, arg);
    std::fputc('\n', stderr);
}

// The uid of seat0's active session, or -1 when there is none.
long activeUid() {
    uid_t uid = 0;
    if (sd_seat_get_active("seat0", nullptr, &uid) < 0) return -1;
    return static_cast<long>(uid);
}

bool writeEvent(int fd, const uhid_event& ev) {
    return write(fd, &ev, sizeof ev) == static_cast<ssize_t>(sizeof ev);
}

int createDevice() {
    const int fd = open("/dev/uhid", O_RDWR | O_CLOEXEC);
    if (fd < 0) {
        log("cannot open /dev/uhid: %s", std::strerror(errno));
        return -1;
    }
    uhid_event ev{};
    ev.type = UHID_CREATE2;
    std::snprintf(reinterpret_cast<char*>(ev.u.create2.name), sizeof ev.u.create2.name, "b1air phone passkey");
    std::snprintf(reinterpret_cast<char*>(ev.u.create2.phys), sizeof ev.u.create2.phys, "b1air-fido-uhid");
    std::memcpy(ev.u.create2.rd_data, kDescriptor, sizeof kDescriptor);
    ev.u.create2.rd_size = sizeof kDescriptor;
    ev.u.create2.bus = BUS_VIRTUAL;
    // pid.codes' test range: no vendor of real hardware uses it.
    ev.u.create2.vendor = 0x1209;
    ev.u.create2.product = 0x000A;
    ev.u.create2.version = 1;
    if (!writeEvent(fd, ev)) {
        log("cannot create the device: %s", std::strerror(errno));
        close(fd);
        return -1;
    }
    return fd;
}

void destroyDevice(int fd) {
    uhid_event ev{};
    ev.type = UHID_DESTROY;
    writeEvent(fd, ev);
    close(fd);
}

// One client, from connect to disconnect: the device lives exactly that long.
void serve(int client, uid_t uid) {
    const int dev = createDevice();
    if (dev < 0) return;
    log("device up");
    pollfd fds[2] = {{dev, POLLIN, 0}, {client, POLLIN, 0}};
    while (!g_stop) {
        const int n = poll(fds, 2, 2000);
        if (n < 0 && errno != EINTR) break;
        // The seat went to another user (or to the greeter): their browser
        // gets the hidraw node now, and must not reach this client.
        if (activeUid() != static_cast<long>(uid)) {
            log("the session is no longer active; dropping the client");
            break;
        }
        if (n <= 0) continue;
        if (fds[0].revents & POLLIN) {
            uhid_event ev{};
            if (read(dev, &ev, sizeof ev) <= 0) break;
            if (ev.type == UHID_OUTPUT) {
                // hidraw writes start with the report number, 0 here; the
                // kernel passes it on.
                const unsigned char* data = ev.u.output.data;
                size_t size = ev.u.output.size;
                if (size == kReport + 1) { ++data; --size; }
                if (size == kReport && send(client, data, kReport, MSG_NOSIGNAL) != static_cast<ssize_t>(kReport)) break;
            } else if (ev.type == UHID_GET_REPORT) {
                uhid_event reply{};
                reply.type = UHID_GET_REPORT_REPLY;
                reply.u.get_report_reply.id = ev.u.get_report.id;
                reply.u.get_report_reply.err = EIO;
                writeEvent(dev, reply);
            } else if (ev.type == UHID_SET_REPORT) {
                uhid_event reply{};
                reply.type = UHID_SET_REPORT_REPLY;
                reply.u.set_report_reply.id = ev.u.set_report.id;
                reply.u.set_report_reply.err = EIO;
                writeEvent(dev, reply);
            }
        }
        if (fds[0].revents & (POLLERR | POLLHUP)) break;
        if (fds[1].revents & POLLIN) {
            unsigned char buf[kReport + 1];
            const ssize_t got = recv(client, buf, sizeof buf, 0);
            if (got <= 0) break;
            // A report is 64 bytes; anything else is not one, and is dropped.
            if (got != static_cast<ssize_t>(kReport)) continue;
            uhid_event ev{};
            ev.type = UHID_INPUT2;
            ev.u.input2.size = kReport;
            std::memcpy(ev.u.input2.data, buf, kReport);
            if (!writeEvent(dev, ev)) break;
        }
        if (fds[1].revents & (POLLERR | POLLHUP)) break;
    }
    destroyDevice(dev);
    log("device down");
}

} // namespace

int main() {
    if (geteuid() != 0) {
        log("must run as root (it is a system service: b1air-fido-uhid.service)");
        return 1;
    }
    struct sigaction sa{};
    sa.sa_handler = [](int) { g_stop = 1; };
    sigaction(SIGTERM, &sa, nullptr);
    sigaction(SIGINT, &sa, nullptr);
    signal(SIGPIPE, SIG_IGN);

    mkdir(kSocketDir, 0755);
    unlink(kSocketPath);
    // SEQPACKET keeps each report a message of its own: no framing to get
    // out of step.
    const int srv = socket(AF_UNIX, SOCK_SEQPACKET | SOCK_CLOEXEC, 0);
    sockaddr_un addr{};
    addr.sun_family = AF_UNIX;
    std::snprintf(addr.sun_path, sizeof addr.sun_path, "%s", kSocketPath);
    if (srv < 0 || bind(srv, reinterpret_cast<sockaddr*>(&addr), sizeof addr) < 0 || listen(srv, 2) < 0) {
        log("cannot listen on %s", kSocketPath);
        return 1;
    }
    // Anyone may knock; the door is the uid check below.
    chmod(kSocketPath, 0666);

    while (!g_stop) {
        const int client = accept4(srv, nullptr, nullptr, SOCK_CLOEXEC);
        if (client < 0) {
            if (errno == EINTR) continue;
            break;
        }
        ucred cred{};
        socklen_t len = sizeof cred;
        if (getsockopt(client, SOL_SOCKET, SO_PEERCRED, &cred, &len) < 0
                || activeUid() != static_cast<long>(cred.uid)) {
            log("refused a client that is not the active session's user");
            close(client);
            continue;
        }
        serve(client, cred.uid);
        close(client);
    }
    close(srv);
    unlink(kSocketPath);
    return 0;
}
