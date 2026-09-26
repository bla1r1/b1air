#include "notify.hpp"

#include <systemd/sd-bus.h>

#include <cstdlib>

namespace b1air::util {

namespace {

// One hint, as notify-send spells it: TYPE:NAME:VALUE.
int append_hint(sd_bus_message* m, const std::string& spec) {
    const size_t a = spec.find(':');
    const size_t b = a == std::string::npos ? a : spec.find(':', a + 1);
    if (b == std::string::npos) return 0;
    const std::string type = spec.substr(0, a);
    const std::string name = spec.substr(a + 1, b - a - 1);
    const std::string value = spec.substr(b + 1);
    int r = sd_bus_message_open_container(m, 'e', "sv");
    if (r < 0) return r;
    if ((r = sd_bus_message_append(m, "s", name.c_str())) < 0) return r;
    if (type == "int") r = sd_bus_message_append(m, "v", "i", std::atoi(value.c_str()));
    else if (type == "byte") r = sd_bus_message_append(m, "v", "y", static_cast<uint8_t>(std::atoi(value.c_str())));
    else if (type == "boolean") r = sd_bus_message_append(m, "v", "b", value == "true" ? 1 : 0);
    else r = sd_bus_message_append(m, "v", "s", value.c_str());
    if (r < 0) return r;
    return sd_bus_message_close_container(m);
}

} // namespace

uint32_t notify(const Notification& n) {
    sd_bus* bus = nullptr;
    if (sd_bus_open_user(&bus) < 0) return 0;

    sd_bus_message* m = nullptr;
    sd_bus_message* reply = nullptr;
    uint32_t id = 0;
    int r = sd_bus_message_new_method_call(bus, &m, "org.freedesktop.Notifications",
                                           "/org/freedesktop/Notifications",
                                           "org.freedesktop.Notifications", "Notify");
    if (r >= 0) r = sd_bus_message_append(m, "susss", n.app.c_str(), n.replaces, n.icon.c_str(),
                                          n.title.c_str(), n.body.c_str());
    if (r >= 0) r = sd_bus_message_append(m, "as", 0);   // no actions
    if (r >= 0) r = sd_bus_message_open_container(m, 'a', "{sv}");
    if (r >= 0 && !n.urgency.empty()) {
        const uint8_t level = n.urgency == "low" ? 0 : n.urgency == "critical" ? 2 : 1;
        r = sd_bus_message_append(m, "{sv}", "urgency", "y", level);
    }
    for (const std::string& h : n.hints)
        if (r >= 0) r = append_hint(m, h);
    if (r >= 0) r = sd_bus_message_close_container(m);
    if (r >= 0) r = sd_bus_message_append(m, "i", n.timeout_ms);
    // A short wait: the notification server is the desktop shell, and a
    // shell that is restarting should not hold up whoever is notifying.
    if (r >= 0) r = sd_bus_call(bus, m, 2 * 1000 * 1000, nullptr, &reply);
    if (r >= 0) (void)sd_bus_message_read(reply, "u", &id);

    sd_bus_message_unref(reply);
    sd_bus_message_unref(m);
    sd_bus_flush_close_unref(bus);
    return id;
}

} // namespace b1air::util
