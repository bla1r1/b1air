#pragma once

// Calendar accounts, for calendar.cpp and the calendar-account verb:
//
//   icloud:<Apple ID>                 CalDAV at caldav.icloud.com, with an
//                                     app-specific password
//   caldav:https://user@host/path     any CalDAV server
//   google:<address>                  Google Calendar, signed in in the browser
//   microsoft:<address>               Outlook.com / Microsoft 365, the same
//
// A source may end in "#hide=<ids>" (url-encoded, one per line): calendars
// of the account that are not read. The secret — a password, or a sign-in's
// refresh token — is in the secret store as calendar-<md5 of the source
// before the #>.

#include <chrono>
#include <string>
#include <vector>

namespace Calendar {

// An event an account's server has already worked out (Google's and
// Microsoft's expand recurring events themselves).
struct Expanded {
    std::string title, location;
    std::chrono::sys_seconds start, end;
    bool all_day = false;
    bool busy = true;
};

struct AccountData {
    std::vector<std::string> ics;     // CalDAV: calendar objects as .ics text
    std::vector<Expanded> events;     // Google, Microsoft
};

bool is_account(const std::string& src);

// What the account holds for the next `hours`, read at most every fifteen
// minutes and kept for offline (readable by its owner alone).
AccountData load_account(const std::string& src, int hours, std::vector<std::string>& errors);

// calendar-account providers | check <source> | signin google|microsoft:
// JSON for Settings.
std::string account_command(const std::vector<std::string>& args);

}
