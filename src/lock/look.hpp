// What b1air-lock draws, apart from how it gets to the screen: everything a
// screen shows, as a View, painted with cairo. main.cpp fills the View from
// its state and hands the result to the compositor; tools/test-lock.sh paints
// the same View to a PNG, so the look can be seen without a session to lock.
//
// The desktop's "Air" style, as the shell's panels and the login screen: the
// wallpaper blurred under a light veil, white words with a soft shadow, and
// light glass — white at a low opacity with a hairline of white round it —
// for the password, the pills and the buttons.

#pragma once

#include <cairo.h>
#include <string>

namespace look {

enum class Status { Idle, Typing, Checking, Denied, Unavailable };

struct Rect {
    double x = 0, y = 0, w = 0, h = 0;
    bool contains(double px, double py) const { return w > 0 && px >= x && px < x + w && py >= y && py < y + h; }
};

struct Colour {
    double r, g, b;
};

// The desktop theme's colours, Breeze Dark's until it is read.
struct Palette {
    Colour ground{0x20 / 255.0, 0x23 / 255.0, 0x26 / 255.0};
    Colour mid{0x29 / 255.0, 0x2c / 255.0, 0x30 / 255.0};
    Colour text{0xfc / 255.0, 0xfc / 255.0, 0xfc / 255.0};
    Colour dim{0xb4 / 255.0, 0xbb / 255.0, 0xc2 / 255.0};
    Colour primary{0x3d / 255.0, 0xae / 255.0, 0xe9 / 255.0};
    Colour tertiary{0xb0 / 255.0, 0x7a / 255.0, 0xd9 / 255.0};
    Colour error{0xed / 255.0, 0x4b / 255.0, 0x5b / 255.0};
    Colour warn{0xfd / 255.0, 0xbc / 255.0, 0x4b / 255.0};
};

// One screen's worth, in its logical size.
struct View {
    double width = 0, height = 0;
    cairo_surface_t* wallpaper = nullptr;   // small: drawn up, which blurs it
    cairo_surface_t* avatar = nullptr;      // square; without it, the initial
    std::string name, clock, date;

    std::string password;
    bool reveal = false;                    // the eye: as text, not dots
    Status status = Status::Idle;
    std::string layout;                     // "US"; empty with one layout
    std::string placeholder;                // in the field while it is empty
    std::string message;                    // under it: checking, refused
    std::string caps;                       // "Caps Lock is on", or empty
    std::string finger;                     // "Or touch the reader", or empty
    bool finger_miss = false;

    std::string weather_icon, weather_temp;
    std::string battery, battery_icon;      // "73%", empty without one
    bool battery_low = false;

    bool menu_open = false;
    std::string items[3];                   // reboot, sleep, shut down
    bool pointer = false;                   // the pointer is on this screen, at
    double px = 0, py = 0;

    Palette pal;
};

// Where the things the pointer can press were drawn.
struct Hits {
    Rect eye, power, items[3];
};

void paint(cairo_t* cr, const View& v, Hits& hits);

}  // namespace look
