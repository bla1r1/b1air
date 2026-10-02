#include "magic_mouse.hpp"

#include "settings_manager.hpp"
#include "sway_ipc.hpp"

#include <cerrno>
#include <chrono>
#include <cmath>
#include <cstring>
#include <dirent.h>
#include <fcntl.h>
#include <iostream>
#include <linux/input.h>
#include <map>
#include <poll.h>
#include <sys/ioctl.h>
#include <sstream>
#include <sys/inotify.h>
#include <unistd.h>

namespace b1air {

namespace {

// Sideways travel of the two fingers, as a share of the surface's width,
// that makes a swipe; and how much more sideways than up or down it must be.
constexpr double kSwipeDistance = 0.18;
constexpr double kSwipeRatio = 1.5;
// A tap: down and up within this, moving no further than this share.
constexpr uint64_t kTapMs = 300;
constexpr double kTapTravel = 0.05;
// The second tap within this of the first.
constexpr uint64_t kDoubleTapMs = 450;

// The driver's own ranges for a Magic Mouse (hid-magicmouse.c), used by the
// replay when there is no device to ask.
constexpr int kMinX = -1100, kMaxX = 1258, kMinY = -1589, kMaxY = 2047;

uint64_t ms_of(const input_event& ev) {
    return static_cast<uint64_t>(ev.input_event_sec) * 1000
        + static_cast<uint64_t>(ev.input_event_usec) / 1000;
}

} // namespace

MagicMouseGestures::MagicMouseGestures(int min_x, int max_x, int min_y, int max_y)
    : width_(std::max(1, max_x - min_x)), height_(std::max(1, max_y - min_y)), touches_(16) {}

const char* MagicMouseGestures::name(Gesture g) {
    switch (g) {
    case Gesture::SwipeLeft:  return "swipe-left";
    case Gesture::SwipeRight: return "swipe-right";
    case Gesture::DoubleTap:  return "double-tap";
    case Gesture::None:       break;
    }
    return "none";
}

int MagicMouseGestures::active_count() const {
    int n = 0;
    for (const Touch& t : touches_) n += t.active ? 1 : 0;
    return n;
}

bool MagicMouseGestures::centroid(double& x, double& y) const {
    int n = 0;
    x = y = 0;
    for (const Touch& t : touches_) {
        if (!t.active) continue;
        x += t.x; y += t.y; ++n;
    }
    if (n == 0) return false;
    x /= n; y /= n;
    return true;
}

MagicMouseGestures::Gesture MagicMouseGestures::feed(const input_event& ev) {
    switch (ev.type) {
    case EV_ABS:
        switch (ev.code) {
        case ABS_MT_SLOT:
            slot_ = (ev.value >= 0 && ev.value < static_cast<int>(touches_.size())) ? ev.value : 0;
            break;
        case ABS_MT_TRACKING_ID: {
            Touch& t = touches_[slot_];
            t.tracking = ev.value;
            t.active = ev.value >= 0;
            if (t.active) t.placed = false;
            break;
        }
        case ABS_MT_POSITION_X:
            touches_[slot_].x = ev.value;
            break;
        case ABS_MT_POSITION_Y:
            touches_[slot_].y = ev.value;
            break;
        }
        return Gesture::None;
    case EV_KEY:
        // A real click while fingers rest on it is not a tap.
        if ((ev.code == BTN_LEFT || ev.code == BTN_RIGHT || ev.code == BTN_MIDDLE) && ev.value == 1)
            contact_clicked_ = true;
        return Gesture::None;
    case EV_SYN:
        if (ev.code == SYN_REPORT) return on_frame(ms_of(ev));
        return Gesture::None;
    }
    return Gesture::None;
}

MagicMouseGestures::Gesture MagicMouseGestures::on_frame(uint64_t now) {
    for (Touch& t : touches_) {
        if (t.active && !t.placed) {
            t.x0 = t.x; t.y0 = t.y; t.placed = true;
        }
    }
    const int n = active_count();
    Gesture result = Gesture::None;

    if (n > 0 && !in_contact_) {
        in_contact_ = true;
        contact_start_ = now;
        contact_max_ = 0;
        contact_travel_ = 0;
        contact_clicked_ = false;
        contact_swiped_ = false;
    }
    if (in_contact_) {
        contact_max_ = std::max(contact_max_, n);
        for (const Touch& t : touches_) {
            if (!t.active) continue;
            const double d = std::hypot((t.x - t.x0) / width_, (t.y - t.y0) / height_);
            contact_travel_ = std::max(contact_travel_, d);
        }
    }

    // Two fingers: watch their middle for a sideways swipe, once per contact.
    if (n == 2 && !pair_) {
        pair_ = centroid(pair_cx0_, pair_cy0_);
    } else if (n != 2) {
        pair_ = false;
    }
    if (pair_ && !contact_swiped_) {
        double cx, cy;
        centroid(cx, cy);
        const double dx = (cx - pair_cx0_) / width_;
        const double dy = (cy - pair_cy0_) / height_;
        if (std::fabs(dx) > kSwipeDistance && std::fabs(dx) > kSwipeRatio * std::fabs(dy)) {
            contact_swiped_ = true;
            result = dx < 0 ? Gesture::SwipeLeft : Gesture::SwipeRight;
        }
    }

    // All fingers up: was it a two-finger tap, and the second of two?
    if (n == 0 && in_contact_) {
        in_contact_ = false;
        const bool tap = contact_max_ == 2 && !contact_clicked_ && !contact_swiped_
            && now - contact_start_ <= kTapMs && contact_travel_ <= kTapTravel;
        if (tap) {
            if (last_tap_ && now - last_tap_ <= kDoubleTapMs) {
                last_tap_ = 0;
                result = Gesture::DoubleTap;
            } else {
                last_tap_ = now;
            }
        } else {
            last_tap_ = 0;
        }
    }
    return result;
}

namespace magic_mouse {

namespace {

struct Device {
    std::string path;
    std::string name;
    int fd = -1;
    MagicMouseGestures gestures;
};

bool test_bit(const unsigned long* bits, int bit) {
    constexpr int per = sizeof(unsigned long) * 8;
    return (bits[bit / per] >> (bit % per)) & 1UL;
}

// A Magic Mouse: an Apple device (USB or Bluetooth vendor id) that is a
// mouse (relative motion) and reports touches. The Magic Trackpad has no
// relative motion; libinput handles it as the touchpad it is.
bool is_magic_mouse(int fd, std::string& name, input_absinfo& ax, input_absinfo& ay) {
    input_id id{};
    if (ioctl(fd, EVIOCGID, &id) < 0) return false;
    if (id.vendor != 0x05ac && id.vendor != 0x004c) return false;
    unsigned long ev[(EV_MAX + 64) / 64]{}, rel[(REL_MAX + 64) / 64]{}, abs[(ABS_MAX + 64) / 64]{};
    if (ioctl(fd, EVIOCGBIT(0, sizeof(ev)), ev) < 0) return false;
    if (!test_bit(ev, EV_REL) || !test_bit(ev, EV_ABS)) return false;
    if (ioctl(fd, EVIOCGBIT(EV_REL, sizeof(rel)), rel) < 0 || !test_bit(rel, REL_X)) return false;
    if (ioctl(fd, EVIOCGBIT(EV_ABS, sizeof(abs)), abs) < 0) return false;
    if (!test_bit(abs, ABS_MT_POSITION_X) || !test_bit(abs, ABS_MT_TRACKING_ID)) return false;
    if (ioctl(fd, EVIOCGABS(ABS_MT_POSITION_X), &ax) < 0) return false;
    if (ioctl(fd, EVIOCGABS(ABS_MT_POSITION_Y), &ay) < 0) return false;
    char buf[256] = {0};
    ioctl(fd, EVIOCGNAME(sizeof(buf) - 1), buf);
    name = buf;
    return true;
}

// Each /dev/input/event* that is a Magic Mouse and not watched yet.
void discover(std::map<std::string, Device>& devices, bool verbose) {
    DIR* dir = opendir("/dev/input");
    if (!dir) return;
    static bool warned_access = false;
    while (dirent* e = readdir(dir)) {
        if (std::strncmp(e->d_name, "event", 5) != 0) continue;
        const std::string path = std::string("/dev/input/") + e->d_name;
        if (devices.count(path)) continue;
        const int fd = open(path.c_str(), O_RDONLY | O_NONBLOCK | O_CLOEXEC);
        if (fd < 0) {
            if (errno == EACCES && !warned_access && verbose) {
                warned_access = true;
                std::cerr << "[b1air-magicmouse] cannot read " << path
                          << ": not in the input group (install.sh adds you; log in again)\n";
            }
            continue;
        }
        std::string name;
        input_absinfo ax{}, ay{};
        if (!is_magic_mouse(fd, name, ax, ay)) {
            close(fd);
            continue;
        }
        if (verbose) std::cerr << "[b1air-magicmouse] " << name << " at " << path << "\n";
        devices.emplace(path, Device{path, name, fd,
            MagicMouseGestures(ax.minimum, ax.maximum, ay.minimum, ay.maximum)});
    }
    closedir(dir);
}

bool has_overview() {
    SwayIPC ipc;
    if (!ipc.connect()) return false;
    return ipc.send_command(0, "overview").find("Unknown/invalid command") == std::string::npos;
}

void act(MagicMouseGestures::Gesture g) {
    if (!SettingsManager::get_json_bool("magicMouseGestures", true)) return;
    // As on the touchpad: "natural" moves the content with the fingers, so
    // fingers going left bring in the workspace on the right.
    const bool natural = SettingsManager::get_json_bool("touchpadNaturalSwipe", true);
    switch (g) {
    case MagicMouseGestures::Gesture::SwipeLeft:
        (void)SwayIPC::run(natural ? "workspace next_on_output" : "workspace prev_on_output");
        break;
    case MagicMouseGestures::Gesture::SwipeRight:
        (void)SwayIPC::run(natural ? "workspace prev_on_output" : "workspace next_on_output");
        break;
    case MagicMouseGestures::Gesture::DoubleTap:
        (void)SwayIPC::run(has_overview() ? "overview toggle" : "exec b1air-shell toggle launchpad");
        break;
    case MagicMouseGestures::Gesture::None:
        break;
    }
}

} // namespace

void run(const volatile int* running) {
    std::map<std::string, Device> devices;
    const int ino = inotify_init1(IN_NONBLOCK | IN_CLOEXEC);
    if (ino >= 0) inotify_add_watch(ino, "/dev/input", IN_CREATE | IN_ATTRIB);
    discover(devices, true);

    while (*running) {
        std::vector<pollfd> fds;
        std::vector<std::string> paths;
        if (ino >= 0) fds.push_back({ino, POLLIN, 0});
        for (auto& [path, d] : devices) {
            fds.push_back({d.fd, POLLIN, 0});
            paths.push_back(path);
        }
        const int r = poll(fds.data(), fds.size(), ino >= 0 ? 2000 : 5000);
        if (r < 0 && errno != EINTR) break;

        size_t first_dev = 0;
        if (ino >= 0) {
            first_dev = 1;
            if (fds[0].revents & POLLIN) {
                char buf[4096];
                while (read(ino, buf, sizeof(buf)) > 0) {}
                // The node may not be readable the moment it appears:
                // udev sets its group a moment later (IN_ATTRIB covers it).
                discover(devices, true);
            }
        } else if (r == 0) {
            discover(devices, true);
        }

        for (size_t i = first_dev; i < fds.size(); ++i) {
            const std::string& path = paths[i - first_dev];
            Device& d = devices.at(path);
            if (fds[i].revents & (POLLERR | POLLHUP | POLLNVAL)) {
                std::cerr << "[b1air-magicmouse] " << d.name << " gone\n";
                close(d.fd);
                devices.erase(path);
                continue;
            }
            if (!(fds[i].revents & POLLIN)) continue;
            input_event evs[64];
            ssize_t n;
            bool gone = false;
            while ((n = read(d.fd, evs, sizeof(evs))) > 0) {
                for (ssize_t k = 0; k < n / static_cast<ssize_t>(sizeof(input_event)); ++k)
                    act(d.gestures.feed(evs[k]));
            }
            if (n < 0 && errno == ENODEV) gone = true;
            if (gone) {
                std::cerr << "[b1air-magicmouse] " << d.name << " gone\n";
                close(d.fd);
                devices.erase(path);
            }
        }
    }
    for (auto& [path, d] : devices) close(d.fd);
    if (ino >= 0) close(ino);
}

int print_status() {
    std::map<std::string, Device> devices;
    discover(devices, false);
    int unreadable = 0;
    if (DIR* dir = opendir("/dev/input")) {
        while (dirent* e = readdir(dir))
            if (std::strncmp(e->d_name, "event", 5) == 0
                    && access((std::string("/dev/input/") + e->d_name).c_str(), R_OK) != 0)
                ++unreadable;
        closedir(dir);
    }
    for (auto& [path, d] : devices) {
        std::cout << path << "\t" << d.name << "\n";
        close(d.fd);
    }
    if (devices.empty()) std::cout << "no Magic Mouse found\n";
    if (unreadable > 0)
        std::cout << unreadable << " input device(s) not readable: join the input group\n";
    return devices.empty() ? 1 : 0;
}

int replay() {
    MagicMouseGestures g(kMinX, kMaxX, kMinY, kMaxY);
    uint64_t now = 0;
    auto emit = [&](uint16_t type, uint16_t code, int32_t value) {
        input_event ev{};
        ev.input_event_sec = static_cast<decltype(ev.input_event_sec)>(now / 1000);
        ev.input_event_usec = static_cast<decltype(ev.input_event_usec)>((now % 1000) * 1000);
        ev.type = type; ev.code = code; ev.value = value;
        const auto r = g.feed(ev);
        if (r != MagicMouseGestures::Gesture::None) std::cout << MagicMouseGestures::name(r) << "\n";
    };
    static int next_id = 1;
    std::string line;
    while (std::getline(std::cin, line)) {
        std::istringstream in(line);
        std::string op;
        if (!(in >> op) || op[0] == '#') continue;
        if (op == "t") {
            in >> now;
        } else if (op == "down" || op == "move") {
            int slot, x, y;
            in >> slot >> x >> y;
            emit(EV_ABS, ABS_MT_SLOT, slot);
            if (op == "down") emit(EV_ABS, ABS_MT_TRACKING_ID, next_id++);
            emit(EV_ABS, ABS_MT_POSITION_X, x);
            emit(EV_ABS, ABS_MT_POSITION_Y, y);
        } else if (op == "up") {
            int slot;
            in >> slot;
            emit(EV_ABS, ABS_MT_SLOT, slot);
            emit(EV_ABS, ABS_MT_TRACKING_ID, -1);
        } else if (op == "click") {
            emit(EV_KEY, BTN_LEFT, 1);
            emit(EV_KEY, BTN_LEFT, 0);
        } else if (op == "syn") {
            emit(EV_SYN, SYN_REPORT, 0);
        }
    }
    return 0;
}

} // namespace magic_mouse
} // namespace b1air
