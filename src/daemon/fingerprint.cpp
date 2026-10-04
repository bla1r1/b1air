#include "fingerprint.hpp"

#include <nlohmann/json.hpp>
#include <systemd/sd-bus.h>

#include <csignal>
#include <cstdio>
#include <cstring>
#include <iostream>
#include <poll.h>
#include <string>
#include <sys/stat.h>
#include <unistd.h>
#include <vector>

namespace b1air::fingerprint {

namespace {

constexpr const char* kService = "net.reactivated.Fprint";
constexpr const char* kManagerPath = "/net/reactivated/Fprint/Manager";
constexpr const char* kManager = "net.reactivated.Fprint.Manager";
constexpr const char* kDevice = "net.reactivated.Fprint.Device";

volatile sig_atomic_t g_stop = 0;
void on_signal(int) { g_stop = 1; }

struct Bus {
    sd_bus* bus = nullptr;
    std::string device;   // the reader's object path, empty when there is none
    std::string error;    // why not, as fprintd or D-Bus said it
    Bus() {
        if (sd_bus_open_system(&bus) < 0) {
            bus = nullptr;
            error = "no-system-bus";
            return;
        }
        sd_bus_message* reply = nullptr;
        sd_bus_error e = SD_BUS_ERROR_NULL;
        if (sd_bus_call_method(bus, kService, kManagerPath, kManager, "GetDefaultDevice", &e, &reply, "") >= 0) {
            const char* path = nullptr;
            if (sd_bus_message_read(reply, "o", &path) >= 0 && path) device = path;
        } else {
            // NoSuchDevice: fprintd is there, the reader is not; ServiceUnknown:
            // fprintd is not installed.
            error = e.name ? e.name : "unknown";
        }
        sd_bus_error_free(&e);
        sd_bus_message_unref(reply);
    }
    ~Bus() {
        if (bus) sd_bus_flush_close_unref(bus);
    }
    // A method on the reader; on failure `err` gets fprintd's error name.
    bool call(const char* method, std::string* err, const char* sig = "", const char* arg = nullptr,
              sd_bus_message** out = nullptr) {
        sd_bus_error e = SD_BUS_ERROR_NULL;
        const int r = arg ? sd_bus_call_method(bus, kService, device.c_str(), kDevice, method, &e, out, sig, arg)
                          : sd_bus_call_method(bus, kService, device.c_str(), kDevice, method, &e, out, "");
        if (r < 0 && err) *err = e.name ? e.name : std::strerror(-r);
        sd_bus_error_free(&e);
        return r >= 0;
    }
};

std::string short_error(const std::string& name) {
    // net.reactivated.Fprint.Error.PermissionDenied -> PermissionDenied
    const auto dot = name.rfind('.');
    return dot == std::string::npos ? name : name.substr(dot + 1);
}

std::vector<std::string> enrolled(Bus& b) {
    std::vector<std::string> out;
    sd_bus_message* reply = nullptr;
    // The empty user is the caller.
    if (b.call("ListEnrolledFingers", nullptr, "s", "", &reply)) {
        char** fingers = nullptr;
        if (sd_bus_message_read_strv(reply, &fingers) >= 0 && fingers) {
            for (char** f = fingers; *f; ++f) {
                out.emplace_back(*f);
                free(*f);
            }
            free(fingers);
        }
    }
    sd_bus_message_unref(reply);
    return out;
}

// A property of the reader, by Properties.Get: fprintd names them with
// dashes ("num-enroll-stages"), which sd-bus's own property helpers refuse
// as member names.
sd_bus_message* property(Bus& b, const char* name, const char* type) {
    sd_bus_message* reply = nullptr;
    if (sd_bus_call_method(b.bus, kService, b.device.c_str(), "org.freedesktop.DBus.Properties", "Get", nullptr,
                           &reply, "ss", kDevice, name) < 0
        || sd_bus_message_enter_container(reply, 'v', type) < 0) {
        sd_bus_message_unref(reply);
        return nullptr;
    }
    return reply;
}

std::string property_string(Bus& b, const char* name) {
    std::string out;
    if (sd_bus_message* m = property(b, name, "s")) {
        const char* v = nullptr;
        if (sd_bus_message_read(m, "s", &v) >= 0 && v) out = v;
        sd_bus_message_unref(m);
    }
    return out;
}

int property_int(Bus& b, const char* name) {
    int32_t out = 0;
    if (sd_bus_message* m = property(b, name, "i")) {
        (void)sd_bus_message_read(m, "i", &out);
        sd_bus_message_unref(m);
    }
    return out;
}

// Is whoever started this still there: stdin a pipe that has been closed
// (the settings page stopped its Process) counts as gone.
bool reader_gone() {
    struct stat st{};
    if (fstat(STDIN_FILENO, &st) != 0 || !S_ISFIFO(st.st_mode)) return false;
    pollfd p{STDIN_FILENO, POLLIN, 0};
    if (poll(&p, 1, 0) <= 0) return false;
    if (p.revents & (POLLHUP | POLLERR)) return true;
    char buf[64];
    return read(STDIN_FILENO, buf, sizeof(buf)) == 0;
}

struct Scan {
    std::string last;
    bool done = false;
};

int on_status(sd_bus_message* m, void* data, sd_bus_error*) {
    auto* s = static_cast<Scan*>(data);
    const char* result = nullptr;
    int done = 0;
    if (sd_bus_message_read(m, "sb", &result, &done) < 0 || !result) return 0;
    s->last = result;
    s->done = done != 0;
    std::cout << "status " << result << std::endl;
    return 0;
}

// Claim the reader, start `start` (EnrollStart or VerifyStart), print every
// `signal` until it says done, stop it with `stop` and let the reader go.
int scan(const char* start, const char* arg, const char* signal, const char* stop, const char* success) {
    std::signal(SIGTERM, on_signal);
    std::signal(SIGINT, on_signal);
    Bus b;
    if (b.device.empty()) {
        std::cout << "done error " << short_error(b.error) << std::endl;
        return 2;
    }
    std::string err;
    if (!b.call("Claim", &err, "s", "")) {
        std::cout << "done error " << short_error(err) << std::endl;
        return 2;
    }
    Scan s;
    sd_bus_slot* slot = nullptr;
    sd_bus_match_signal(b.bus, &slot, kService, b.device.c_str(), kDevice, signal, on_status, &s);
    int rc = 1;
    if (!b.call(start, &err, "s", arg)) {
        std::cout << "done error " << short_error(err) << std::endl;
        rc = 2;
    } else {
        while (!s.done && !g_stop && !reader_gone()) {
            const int r = sd_bus_process(b.bus, nullptr);
            if (r < 0) break;
            if (r == 0) sd_bus_wait(b.bus, 250000);
        }
        (void)b.call(stop, nullptr);
        if (s.done) {
            std::cout << "done " << s.last << std::endl;
            rc = s.last == success ? 0 : 1;
        } else {
            std::cout << "done cancelled" << std::endl;
        }
    }
    sd_bus_slot_unref(slot);
    (void)b.call("Release", nullptr);
    return rc;
}

} // namespace

std::string status_json() {
    nlohmann::json j;
    Bus b;
    j["available"] = !b.device.empty();
    j["service"] = b.bus && short_error(b.error) != "ServiceUnknown" && b.error != "no-system-bus";
    j["device"] = "";
    j["stages"] = 0;
    j["scanType"] = "";
    j["enrolled"] = nlohmann::json::array();
    if (!b.device.empty()) {
        j["device"] = property_string(b, "name");
        j["stages"] = property_int(b, "num-enroll-stages");
        j["scanType"] = property_string(b, "scan-type");
        j["enrolled"] = enrolled(b);
    } else if (!b.error.empty()) {
        j["error"] = short_error(b.error);
    }
    return j.dump();
}

int enroll(const std::string& finger) {
    return scan("EnrollStart", finger.c_str(), "EnrollStatus", "EnrollStop", "enroll-completed");
}

int verify() {
    return scan("VerifyStart", "any", "VerifyStatus", "VerifyStop", "verify-match");
}

int remove(const std::string& finger) {
    Bus b;
    if (b.device.empty()) {
        std::cout << "done error " << short_error(b.error) << std::endl;
        return 2;
    }
    std::string err;
    if (!b.call("Claim", &err, "s", "")) {
        std::cout << "done error " << short_error(err) << std::endl;
        return 2;
    }
    const bool ok = finger == "all" ? b.call("DeleteEnrolledFingers2", &err)
                                    : b.call("DeleteEnrolledFinger", &err, "s", finger.c_str());
    (void)b.call("Release", nullptr);
    std::cout << (ok ? "done deleted" : "done error " + short_error(err)) << std::endl;
    return ok ? 0 : 1;
}

} // namespace b1air::fingerprint
