#pragma once

// =============================================================================
// Screen and keyboard backlight, without brightnessctl.
//
// Read straight from sysfs; written through logind's Session.SetBrightness,
// which is what lets an ordinary user change it (brightnessctl does the same
// when it is not setuid), with a direct sysfs write as the fallback for a
// system whose udev rules hand the file to the user.
//
// Percentages are linear in what is read back — the number the slider shows
// is the number the hardware has. Relative steps (keys) go through the same
// perceptual curve brightnessctl's -e4 used, so each press looks like the
// same change at the dark end as at the bright end.
// =============================================================================

#include <string>

namespace b1air::backlight {

struct Device {
    std::string subsystem;   // "backlight" or "leds"
    std::string name;
    long max = 0;
    explicit operator bool() const { return !name.empty() && max > 0; }
};

Device screen();     // the panel's backlight, firmware before platform before raw
Device keyboard();   // a *kbd_backlight LED, if there is one

long raw(const Device& d);
bool set_raw(const Device& d, long value);

int percent(const Device& d);                   // linear 0..100
bool set_percent(const Device& d, int pct);     // linear
bool step(const Device& d, int delta_pct, long floor = 0);   // through the curve

} // namespace b1air::backlight
