#pragma once
// Gestures on the touch surface of an Apple Magic Mouse.
//
// Linux's hid-magicmouse driver turns one finger on the surface into scroll
// wheel events and reports every touch as multitouch slots on the same
// input device — which libinput, seeing a mouse, leaves alone. So no
// compositor sees two fingers on a Magic Mouse. This reads them from the
// device itself (it is not grabbed: the pointer, the clicks and the
// scrolling go on as before) and does what macOS does with them:
//
//   two fingers swiped sideways   the workspace beside this one
//   two fingers tapped twice      the workspace overview (Mission Control)
//
// The device node needs to be readable: install.sh puts the user in the
// `input` group.

#include <cstdint>
#include <string>
#include <vector>

struct input_event;

namespace b1air {

class MagicMouseGestures {
public:
    enum class Gesture { None, SwipeLeft, SwipeRight, DoubleTap };

    // The surface's extent in device units (from the device's absinfo).
    MagicMouseGestures(int min_x, int max_x, int min_y, int max_y);

    // One evdev event; returns what it completed, if anything. Gestures
    // complete on SYN_REPORT.
    Gesture feed(const input_event& ev);

    static const char* name(Gesture g);

private:
    struct Touch {
        bool active = false;
        int tracking = -1;
        double x = 0, y = 0;     // now
        double x0 = 0, y0 = 0;   // where it landed
        bool placed = false;     // x0/y0 taken
    };

    Gesture on_frame(uint64_t now_ms);
    int active_count() const;
    bool centroid(double& x, double& y) const;

    double width_, height_;
    std::vector<Touch> touches_;
    int slot_ = 0;

    // A contact: from the first finger down to the last one up.
    bool in_contact_ = false;
    uint64_t contact_start_ = 0;
    int contact_max_ = 0;          // most fingers at once
    double contact_travel_ = 0;    // furthest any finger moved, as a fraction
    bool contact_clicked_ = false;
    bool contact_swiped_ = false;

    // The two-finger swipe: from when the second finger landed.
    bool pair_ = false;
    double pair_cx0_ = 0, pair_cy0_ = 0;

    uint64_t last_tap_ = 0;
};

namespace magic_mouse {

// Session thread: finds Magic Mice as they come and go and acts on their
// gestures until the session ends. Never returns while running is true.
void run(const volatile int* running);

// `b1air-daemon magic-mouse status`: which devices were found, readable or not.
int print_status();

// `b1air-daemon magic-mouse replay`: feeds a script from stdin through the
// recogniser and prints what it saw, one gesture a line. For tests without
// the hardware. Lines: "t <ms>", "down <slot> <x> <y>", "move <slot> <x>
// <y>", "up <slot>", "click", "syn".
int replay();

} // namespace magic_mouse
} // namespace b1air
