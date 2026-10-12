#pragma once

#include <string>

// A screen for whoever is connected from afar, when there is none here.
//
// RustDesk and our VNC show what a screen shows; with the lid closed or no
// monitor plugged in there is nothing to show — a black picture, or none —
// and on a laptop the lid even put the machine to sleep under the person
// working on it. While a remote server is running (and, for screens that are
// only switched off, while someone is connected), a virtual output stands in:
// sway's own (create_output), the size of the screen it replaces, with the
// workspaces moved onto it. When a screen comes back — the lid opened, a
// monitor plugged in — or the remote server stops, it goes, and the
// workspaces return where they were.
namespace b1air::remote_display {

// The session's thread (session_manager.cpp).
void run(const volatile int* running);

// Looked at once now (the lid moved, a server started or stopped) rather
// than at the next tick.
void poke();

// The virtual output standing in now, or "".
std::string virtual_output();

} // namespace b1air::remote_display
