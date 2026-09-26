#pragma once

// =============================================================================
// Desktop notifications, sent straight to org.freedesktop.Notifications over
// the session bus — what notify-send does, without starting notify-send.
//
// The daemon ran it for every toast (a keyboard-backlight step, each focus
// reminder, a failed start), and a missing libnotify-bin package meant those
// notices silently went nowhere. sd-bus is already linked for the daemon's own
// interface.
//
//   util::notify({.app = "Night Light", .title = "Night Light Enabled",
//                 .body = "Warm color temperature active", .icon = "weather-clear-night"});
// =============================================================================

#include <cstdint>
#include <string>
#include <vector>

namespace b1air::util {

struct Notification {
    // Every member has a default, so a designated initializer may leave any
    // of them out.
    std::string app{};
    std::string title{};
    std::string body{};
    std::string icon{};
    std::string urgency{};               // "low", "normal" (default), "critical"
    std::vector<std::string> hints{};    // notify-send's -h: "string:name:value", "int:name:3", "boolean:name:true"
    int timeout_ms = -1;               // -1: the server decides
    uint32_t replaces = 0;
};

// The id the server gave it; 0 when there was no one to send it to.
uint32_t notify(const Notification& n);

} // namespace b1air::util
