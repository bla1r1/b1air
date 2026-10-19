#pragma once

#include <string>
#include <vector>

// Calendar events, read from iCalendar (RFC 5545) sources, for the focus
// mode that comes on during meetings (Services/Notifications, "meeting").
//
// A source is a .ics file, a folder of them (a vdir, as vdirsyncer and khal
// keep a CalDAV calendar), or an http(s) link to one (a calendar's private
// address, as Google, Outlook, Nextcloud and Fastmail give out). A link is
// fetched at most every fifteen minutes into ~/.cache/b1air/calendar and read
// from there, so a meeting is still known while offline.
//
// Recurring events are expanded (RRULE: daily, weekly, monthly and yearly,
// with INTERVAL, COUNT, UNTIL, BYDAY and BYMONTHDAY; EXDATE; RECURRENCE-ID
// overrides), in the time zone the event was written in, so a weekly 10:00
// stays at 10:00 across a change to summer time.
namespace Calendar {

// Events overlapping now .. now + `hours`, as JSON:
// {"events":[{"title","location","start","end","allDay","busy"}], "errors":[…]}
// `start`/`end` in milliseconds since the epoch. `busy` is false for an
// all-day event and one marked free (TRANSP:TRANSPARENT).
std::string events_json(const std::vector<std::string>& sources, int hours);

}
