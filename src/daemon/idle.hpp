#pragma once
// b1air-idle: what happens when nobody is at the machine, run inside the
// session daemon. It replaces swayidle.
//
// The compositor reports idleness (ext-idle-notify-v1, which honours the
// idle inhibitors of a playing video or a fullscreen game), stage by stage
// from Settings → Power:
//
//   dim       the backlight and DDC monitors go down; the screens that are
//             not the main one go off
//   lock      the lock screen
//   screens   every screen off
//   suspend   sleep, when automatic sleep is on
//
// and input undoes them. While locked, only the main screen comes back on
// input: the lock screen is shown there, and the others stay dark until it
// is opened (Settings → Power, "lockSecondaryOff").
//
// Before the machine sleeps it locks and waits for the lock screen to be up
// (a logind delay inhibitor, as swayidle -w did), and logind's Lock signal —
// `loginctl lock-session`, a lid set to lock — locks too.
//
// Caffeine and a gamepad in use hold every stage off; a change of the
// settings applies at once. Both reach this thread as files in the runtime
// directory, so nothing has to be restarted for them.

namespace b1air::idle {

// The session thread. Returns when *running drops to 0.
void run(const volatile int* running);

// Settings changed, or the hold did: look again. From any process.
void reload();

// The lock screen says it is up ("locked") or gone (anything else); it
// writes this file itself (Lock.qml).
bool locked();

} // namespace b1air::idle
