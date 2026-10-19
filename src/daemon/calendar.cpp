#include "calendar.hpp"

#include <algorithm>
#include <chrono>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <functional>
#include <map>
#include <set>
#include <sstream>
#include <fcntl.h>
#include <sys/wait.h>
#include <unistd.h>

#include <nlohmann/json.hpp>
#include <openssl/evp.h>
#include <regex>

#include "secret_store.hpp"

namespace fs = std::filesystem;
using namespace std::chrono;

namespace Calendar {
namespace {

// ── Reading ──────────────────────────────────────────────────────────────────

std::string read_file(const fs::path& p) {
    std::ifstream f(p, std::ios::binary);
    std::ostringstream s;
    s << f.rdbuf();
    return s.str();
}

std::string cache_dir() {
    const char* xdg = std::getenv("XDG_CACHE_HOME");
    const char* home = std::getenv("HOME");
    std::string base = xdg && *xdg ? xdg : std::string(home ? home : "/tmp") + "/.cache";
    return base + "/b1air/calendar";
}

// curl into a file beside the cached one, then over it: a failed fetch
// leaves the last good copy, which is what is read while offline.
bool fetch(const std::string& url, const fs::path& to) {
    const fs::path part = to.string() + ".part";
    const pid_t pid = fork();
    if (pid == 0) {
        // Its complaints are ours to report (errors), not stderr's.
        const int null_fd = open("/dev/null", O_WRONLY);
        if (null_fd >= 0) dup2(null_fd, STDERR_FILENO);
        execlp("curl", "curl", "-fsSL", "--max-time", "15", "--proto", "=http,https",
               "--proto-redir", "=http,https", "-o", part.c_str(), url.c_str(), (char*)nullptr);
        _exit(127);
    }
    if (pid < 0) return false;
    int status = 0;
    while (waitpid(pid, &status, 0) < 0 && errno == EINTR) {}
    std::error_code ec;
    if (!WIFEXITED(status) || WEXITSTATUS(status) != 0) {
        fs::remove(part, ec);
        return false;
    }
    fs::rename(part, to, ec);
    return !ec;
}

// ── CalDAV ───────────────────────────────────────────────────────────────────
//
// "icloud:<Apple ID>" and "caldav:https://user@host/path" (Nextcloud,
// Fastmail, any CalDAV server): the calendars of an account, found the way
// RFC 4791 and 6764 describe (the principal, its calendar home, the
// calendars in it), and the events of the coming days asked of each. The
// password — for iCloud an app-specific one, made at account.apple.com —
// is in the secret store as calendar-<md5 of the source>, put there by
// Settings; it goes to curl on its standard input, never on a command line.

std::string md5_hex(const std::string& s) {
    unsigned char d[EVP_MAX_MD_SIZE];
    unsigned int n = 0;
    EVP_Digest(s.data(), s.size(), d, &n, EVP_md5(), nullptr);
    static const char* hex = "0123456789abcdef";
    std::string out;
    for (unsigned i = 0; i < n; ++i) { out += hex[d[i] >> 4]; out += hex[d[i] & 15]; }
    return out;
}

struct Reply { int status = 0; std::string url, body; };

// One request: `config` (curl's own syntax: the user and password) on its
// standard input, the answer's code and final address after the body.
Reply dav(const std::string& method, const std::string& url, const std::string& depth,
          const std::string& body, const std::string& config) {
    int in_pipe[2], out_pipe[2];
    Reply r;
    if (pipe(in_pipe) != 0) return r;
    if (pipe(out_pipe) != 0) { close(in_pipe[0]); close(in_pipe[1]); return r; }
    const std::string marker = "\n@@b1air@@";
    const pid_t pid = fork();
    if (pid == 0) {
        dup2(in_pipe[0], STDIN_FILENO);
        dup2(out_pipe[1], STDOUT_FILENO);
        const int null_fd = open("/dev/null", O_WRONLY);
        if (null_fd >= 0) dup2(null_fd, STDERR_FILENO);
        close(in_pipe[0]); close(in_pipe[1]); close(out_pipe[0]); close(out_pipe[1]);
        const std::string depth_h = "Depth: " + depth;
        const std::string write_out = marker + "%{http_code} %{url_effective}";
        execlp("curl", "curl", "-sS", "-L", "--max-time", "20", "--proto", "=https", "--proto-redir", "=https",
               "-K", "-", "-X", method.c_str(), "-H", depth_h.c_str(),
               "-H", "Content-Type: application/xml; charset=utf-8", "--data-binary", body.c_str(),
               "-w", write_out.c_str(), url.c_str(), (char*)nullptr);
        _exit(127);
    }
    close(in_pipe[0]);
    close(out_pipe[1]);
    if (pid < 0) { close(in_pipe[1]); close(out_pipe[0]); return r; }
    for (size_t off = 0; off < config.size();) {
        const ssize_t n = write(in_pipe[1], config.data() + off, config.size() - off);
        if (n > 0) off += size_t(n); else if (n < 0 && errno == EINTR) continue; else break;
    }
    close(in_pipe[1]);
    std::string all;
    char buf[8192];
    ssize_t n;
    while ((n = read(out_pipe[0], buf, sizeof buf)) > 0 || (n < 0 && errno == EINTR))
        if (n > 0) all.append(buf, size_t(n));
    close(out_pipe[0]);
    int status = 0;
    while (waitpid(pid, &status, 0) < 0 && errno == EINTR) {}
    const size_t m = all.rfind(marker);
    if (m == std::string::npos) return r;
    r.body = all.substr(0, m);
    std::istringstream tail(all.substr(m + marker.size()));
    tail >> r.status >> r.url;
    return r;
}

// The text of every element named `name`, whatever namespace prefix the
// server gives it (d:href, D:href, href).
std::vector<std::string> elements(const std::string& xml, const std::string& name) {
    std::vector<std::string> out;
    const std::regex re("<(?:[A-Za-z0-9_-]+:)?" + name + R"((?:\s[^>]*)?>([\s\S]*?)</(?:[A-Za-z0-9_-]+:)?)" + name + ">");
    for (std::sregex_iterator it(xml.begin(), xml.end(), re), end; it != end; ++it) out.push_back((*it)[1]);
    return out;
}
std::string xml_text(std::string s) {
    if (s.rfind("<![CDATA[", 0) == 0) return s.substr(9, s.size() >= 12 ? s.size() - 12 : 0);
    const std::pair<const char*, const char*> ents[] = {
        {"&lt;", "<"}, {"&gt;", ">"}, {"&quot;", "\""}, {"&apos;", "'"}, {"&#13;", "\r"}, {"&#xD;", "\r"}, {"&amp;", "&"}};
    for (const auto& [from, to] : ents)
        for (size_t at; (at = s.find(from)) != std::string::npos;) s.replace(at, std::strlen(from), to);
    return s;
}
std::string trim(const std::string& s) {
    const size_t a = s.find_first_not_of(" \t\r\n"), b = s.find_last_not_of(" \t\r\n");
    return a == std::string::npos ? "" : s.substr(a, b - a + 1);
}
// An href against the address it came from: a path keeps that host.
std::string resolve(const std::string& base, const std::string& href) {
    if (href.rfind("http", 0) == 0) return href;
    const size_t host_end = base.find('/', base.find("://") + 3);
    return (host_end == std::string::npos ? base : base.substr(0, host_end)) + href;
}

std::string utc_stamp(sys_seconds t) {
    const auto d = floor<days>(t);
    const year_month_day ymd{d};
    const hh_mm_ss hms{t - d};
    char out[48];
    std::snprintf(out, sizeof out, "%04d%02u%02uT%02ld%02ld%02ldZ", int(ymd.year()), unsigned(ymd.month()),
                  unsigned(ymd.day()), long(hms.hours().count()), long(hms.minutes().count()), long(hms.seconds().count()));
    return out;
}

// Every event of the account in the window, as .ics texts; "" and an error
// when it cannot be read.
std::vector<std::string> load_caldav(const std::string& src, int hours_ahead, std::vector<std::string>& errors) {
    std::string base, user;
    if (src.rfind("icloud:", 0) == 0) {
        user = src.substr(7);
        base = "https://caldav.icloud.com/";
    } else {
        base = src.substr(7);   // after "caldav:"
        const size_t scheme = base.find("://");
        // The last @ before the path: a user name may be an address itself.
        const size_t slash = scheme == std::string::npos ? std::string::npos : base.find('/', scheme + 3);
        const size_t at = scheme == std::string::npos ? std::string::npos : base.rfind('@', slash);
        if (at != std::string::npos && at > scheme) {
            user = base.substr(scheme + 3, at - scheme - 3);
            base = base.substr(0, scheme + 3) + base.substr(at + 1);
        }
    }
    std::string password;
    b1air::SecretStore store;
    if (user.empty() || !store.get("calendar-" + md5_hex(src), password)) {
        errors.push_back(src + ": no password saved");
        return {};
    }
    auto quote = [](const std::string& v) {
        std::string q;
        for (char c : v) { if (c == '"' || c == '\\') q += '\\'; q += c; }
        return q;
    };
    const std::string config = "user = \"" + quote(user) + ":" + quote(password) + "\"\n";
    std::fill(password.begin(), password.end(), '\0');

    auto failed = [&](const Reply& r) {
        errors.push_back(src + (r.status == 401 || r.status == 403 ? ": the server refused the password"
                                : r.status == 0 ? ": could not reach the server"
                                : ": the server answered " + std::to_string(r.status)));
        return std::vector<std::string>{};
    };
    const std::string propfind = R"(<?xml version="1.0"?><d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav"><d:prop>)";

    // The principal, then its calendar home.
    Reply r = dav("PROPFIND", base, "0", propfind + "<d:current-user-principal/></d:prop></d:propfind>", config);
    if (r.status != 207) return failed(r);
    std::string principal = base;
    for (const auto& p : elements(r.body, "current-user-principal")) {
        const auto h = elements(p, "href");
        if (!h.empty()) principal = resolve(r.url, trim(h[0]));
    }
    r = dav("PROPFIND", principal, "0", propfind + "<c:calendar-home-set/></d:prop></d:propfind>", config);
    if (r.status != 207) return failed(r);
    std::string home;
    for (const auto& p : elements(r.body, "calendar-home-set")) {
        const auto h = elements(p, "href");
        if (!h.empty()) home = resolve(r.url, trim(h[0]));
    }
    if (home.empty()) { errors.push_back(src + ": no calendars on this account"); return {}; }

    // The calendars in it that hold events (not reminders' task lists).
    r = dav("PROPFIND", home, "1", propfind + "<d:resourcetype/><c:supported-calendar-component-set/></d:prop></d:propfind>", config);
    if (r.status != 207) return failed(r);
    std::vector<std::string> calendars;
    for (const auto& resp : elements(r.body, "response")) {
        const auto types = elements(resp, "resourcetype");
        if (types.empty() || types[0].find("calendar") == std::string::npos) continue;
        const auto comps = elements(resp, "supported-calendar-component-set");
        if (!comps.empty() && comps[0].find("VEVENT") == std::string::npos) continue;
        const auto h = elements(resp, "href");
        if (!h.empty()) calendars.push_back(resolve(r.url, trim(h[0])));
    }

    // The events overlapping the window, from each.
    const sys_seconds now = floor<seconds>(system_clock::now());
    const std::string query = R"(<?xml version="1.0"?><c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">)"
        "<d:prop><c:calendar-data/></d:prop><c:filter><c:comp-filter name=\"VCALENDAR\"><c:comp-filter name=\"VEVENT\">"
        "<c:time-range start=\"" + utc_stamp(now - days{1}) + "\" end=\"" + utc_stamp(now + hours{hours_ahead}) + "\"/>"
        "</c:comp-filter></c:comp-filter></c:filter></c:calendar-query>";
    std::vector<std::string> out;
    for (const auto& cal : calendars) {
        const Reply q = dav("REPORT", cal, "1", query, config);
        if (q.status != 207) continue;
        for (const auto& data : elements(q.body, "calendar-data")) out.push_back(xml_text(trim(data)));
    }
    return out;
}

// What a source holds: every .ics text in it.
std::vector<std::string> load_source(std::string src, int hours_ahead, std::vector<std::string>& errors) {
    std::vector<std::string> out;
    if (src.rfind("icloud:", 0) == 0 || src.rfind("caldav:", 0) == 0) {
        // Kept like a link's copy: read at most every fifteen minutes, and
        // the last one used while offline.
        std::error_code ec;
        fs::create_directories(cache_dir(), ec);
        const fs::path file = fs::path(cache_dir()) / (md5_hex(src) + ".dav");
        const bool fresh = fs::exists(file, ec)
            && fs::last_write_time(file, ec) > fs::file_time_type::clock::now() - minutes(15);
        if (!fresh) {
            const size_t before = errors.size();
            const auto got = load_caldav(src, std::max(hours_ahead, 24 * 7), errors);
            if (errors.size() == before) {
                std::ofstream f(file, std::ios::binary | std::ios::trunc);
                fs::permissions(file, fs::perms::owner_read | fs::perms::owner_write, ec);
                for (const auto& t : got) f << t << "\n\x1e\n";
            }
        }
        if (fs::exists(file, ec)) {
            std::istringstream all(read_file(file));
            std::string chunk, line;
            while (std::getline(all, line)) {
                if (line == "\x1e") { out.push_back(chunk); chunk.clear(); }
                else chunk += line + "\n";
            }
        }
        return out;
    }
    if (src.rfind("webcal://", 0) == 0) src = "https://" + src.substr(9);
    if (src.rfind("http://", 0) == 0 || src.rfind("https://", 0) == 0) {
        std::error_code ec;
        fs::create_directories(cache_dir(), ec);
        const fs::path file = fs::path(cache_dir()) / (std::to_string(std::hash<std::string>{}(src)) + ".ics");
        const bool fresh = fs::exists(file, ec)
            && fs::last_write_time(file, ec) > fs::file_time_type::clock::now() - minutes(15);
        if (!fresh && !fetch(src, file) && !fs::exists(file, ec))
            errors.push_back("could not fetch " + src);
        if (fs::exists(file, ec)) out.push_back(read_file(file));
        return out;
    }
    if (src.rfind("~/", 0) == 0) {
        const char* home = std::getenv("HOME");
        src = std::string(home ? home : "") + src.substr(1);
    }
    std::error_code ec;
    if (fs::is_directory(src, ec)) {
        for (auto it = fs::recursive_directory_iterator(src, fs::directory_options::skip_permission_denied, ec);
             it != fs::recursive_directory_iterator(); it.increment(ec)) {
            if (ec) break;
            if (it->is_regular_file(ec) && it->path().extension() == ".ics")
                out.push_back(read_file(it->path()));
        }
    } else if (fs::is_regular_file(src, ec)) {
        out.push_back(read_file(src));
    } else {
        errors.push_back("no such calendar: " + src);
    }
    return out;
}

// ── Parsing ──────────────────────────────────────────────────────────────────

struct Prop {
    std::string name;
    std::map<std::string, std::string> params;
    std::string value;
};

// Unfolded content lines (a line starting with a space or tab continues the
// one before it) split into name, parameters and value.
std::vector<Prop> parse_lines(const std::string& text) {
    std::vector<std::string> lines;
    std::istringstream in(text);
    std::string line;
    while (std::getline(in, line)) {
        if (!line.empty() && line.back() == '\r') line.pop_back();
        if (!line.empty() && (line[0] == ' ' || line[0] == '\t') && !lines.empty())
            lines.back() += line.substr(1);
        else
            lines.push_back(line);
    }
    std::vector<Prop> props;
    for (const auto& l : lines) {
        // The value starts at the first colon outside a quoted parameter.
        size_t colon = std::string::npos;
        bool quoted = false;
        for (size_t i = 0; i < l.size(); ++i) {
            if (l[i] == '"') quoted = !quoted;
            else if (l[i] == ':' && !quoted) { colon = i; break; }
        }
        if (colon == std::string::npos) continue;
        Prop p;
        p.value = l.substr(colon + 1);
        std::string head = l.substr(0, colon);
        size_t semi = head.find(';');
        p.name = head.substr(0, semi);
        std::transform(p.name.begin(), p.name.end(), p.name.begin(), ::toupper);
        while (semi != std::string::npos) {
            size_t next = head.find(';', semi + 1);
            std::string kv = head.substr(semi + 1, next == std::string::npos ? std::string::npos : next - semi - 1);
            size_t eq = kv.find('=');
            if (eq != std::string::npos) {
                std::string k = kv.substr(0, eq), v = kv.substr(eq + 1);
                std::transform(k.begin(), k.end(), k.begin(), ::toupper);
                if (v.size() >= 2 && v.front() == '"' && v.back() == '"') v = v.substr(1, v.size() - 2);
                p.params[k] = v;
            }
            semi = next;
        }
        props.push_back(std::move(p));
    }
    return props;
}

std::string unescape(const std::string& s) {
    std::string out;
    for (size_t i = 0; i < s.size(); ++i) {
        if (s[i] == '\\' && i + 1 < s.size()) {
            const char c = s[++i];
            out += (c == 'n' || c == 'N') ? '\n' : c;
        } else {
            out += s[i];
        }
    }
    return out;
}

// A time as written: a wall time in a zone (`zone` null: the machine's own,
// a "floating" time), or UTC.
struct When {
    local_seconds wall{};
    const time_zone* zone = nullptr;
    bool utc = false;
    bool date_only = false;
    bool ok = false;
};

sys_seconds to_sys(const When& w) {
    if (w.utc) return sys_seconds{w.wall.time_since_epoch()};
    const time_zone* z = w.zone ? w.zone : current_zone();
    // A wall time a change of clocks skips or repeats: the earlier reading.
    return z->to_sys(w.wall, choose::earliest);
}

const time_zone* zone_named(const std::string& name) {
    if (name.empty()) return nullptr;
    try { return locate_zone(name); } catch (...) {}
    // Outlook writes Windows names; the common ones, else the machine's zone.
    static const std::map<std::string, std::string> windows = {
        {"W. Europe Standard Time", "Europe/Berlin"}, {"Central Europe Standard Time", "Europe/Budapest"},
        {"Romance Standard Time", "Europe/Paris"}, {"GMT Standard Time", "Europe/London"},
        {"FLE Standard Time", "Europe/Kyiv"}, {"E. Europe Standard Time", "Europe/Chisinau"},
        {"Russian Standard Time", "Europe/Moscow"}, {"Eastern Standard Time", "America/New_York"},
        {"Central Standard Time", "America/Chicago"}, {"Mountain Standard Time", "America/Denver"},
        {"Pacific Standard Time", "America/Los_Angeles"}, {"UTC", "UTC"},
    };
    const auto it = windows.find(name);
    if (it != windows.end()) { try { return locate_zone(it->second); } catch (...) {} }
    return nullptr;
}

When parse_when(const std::string& v, const std::map<std::string, std::string>& params) {
    When w;
    if (v.size() < 8) return w;
    const int y = std::atoi(v.substr(0, 4).c_str());
    const unsigned mo = std::atoi(v.substr(4, 2).c_str()), d = std::atoi(v.substr(6, 2).c_str());
    const year_month_day ymd{year{y}, month{mo}, day{d}};
    if (!ymd.ok()) return w;
    w.wall = local_days{ymd};
    const auto vt = params.find("VALUE");
    if (v.size() < 15 || (vt != params.end() && vt->second == "DATE")) {
        w.date_only = true;
        w.ok = true;
        return w;
    }
    w.wall += hours{std::atoi(v.substr(9, 2).c_str())} + minutes{std::atoi(v.substr(11, 2).c_str())}
            + seconds{std::atoi(v.substr(13, 2).c_str())};
    w.utc = v.size() > 15 && v[15] == 'Z';
    const auto tz = params.find("TZID");
    if (!w.utc && tz != params.end()) w.zone = zone_named(tz->second);
    w.ok = true;
    return w;
}

// "PT1H30M", "P1D", "-PT15M".
seconds parse_duration(const std::string& v) {
    long total = 0, n = 0;
    bool neg = false;
    for (char c : v) {
        if (c == '-') neg = true;
        else if (std::isdigit(static_cast<unsigned char>(c))) n = n * 10 + (c - '0');
        else {
            if (c == 'W') total += n * 604800;
            else if (c == 'D') total += n * 86400;
            else if (c == 'H') total += n * 3600;
            else if (c == 'M') total += n * 60;
            else if (c == 'S') total += n;
            n = 0;
        }
    }
    return seconds{neg ? -total : total};
}

struct Event {
    std::string uid, title, location;
    When start;
    seconds length{0};
    bool has_rule = false;
    std::map<std::string, std::string> rule;
    std::set<sys_seconds> exdates;
    bool busy = true;
    bool cancelled = false;
    // An override of one occurrence of a recurring event (RECURRENCE-ID).
    bool is_override = false;
    sys_seconds replaces{};
};

std::vector<Event> parse_events(const std::string& text) {
    std::vector<Event> events;
    Event ev;
    bool in_event = false, has_end = false;
    When end;
    int depth = 0;   // inside a VALARM or the like, within the event
    for (const auto& p : parse_lines(text)) {
        if (p.name == "BEGIN") {
            if (p.value == "VEVENT") { ev = Event{}; in_event = true; has_end = false; end = When{}; depth = 0; }
            else if (in_event) ++depth;
            continue;
        }
        if (p.name == "END") {
            if (in_event && depth > 0) { --depth; continue; }
            if (p.value == "VEVENT" && in_event) {
                in_event = false;
                if (!ev.start.ok) continue;
                if (has_end && end.ok) ev.length = to_sys(end) - to_sys(ev.start);
                else if (ev.length == seconds{0} && ev.start.date_only) ev.length = days{1};
                if (ev.start.date_only) ev.busy = false;
                events.push_back(ev);
            }
            continue;
        }
        if (!in_event || depth > 0) continue;
        if (p.name == "UID") ev.uid = p.value;
        else if (p.name == "SUMMARY") ev.title = unescape(p.value);
        else if (p.name == "LOCATION") ev.location = unescape(p.value);
        else if (p.name == "DTSTART") ev.start = parse_when(p.value, p.params);
        else if (p.name == "DTEND") { end = parse_when(p.value, p.params); has_end = true; }
        else if (p.name == "DURATION") ev.length = parse_duration(p.value);
        else if (p.name == "TRANSP") ev.busy = p.value != "TRANSPARENT";
        else if (p.name == "STATUS") ev.cancelled = p.value == "CANCELLED";
        else if (p.name == "RECURRENCE-ID") {
            const When r = parse_when(p.value, p.params);
            if (r.ok) { ev.is_override = true; ev.replaces = to_sys(r); }
        } else if (p.name == "EXDATE") {
            std::istringstream list(p.value);
            std::string one;
            while (std::getline(list, one, ',')) {
                const When x = parse_when(one, p.params);
                if (x.ok) ev.exdates.insert(to_sys(x));
            }
        } else if (p.name == "RRULE") {
            ev.has_rule = true;
            std::istringstream parts(p.value);
            std::string kv;
            while (std::getline(parts, kv, ';')) {
                const size_t eq = kv.find('=');
                if (eq != std::string::npos) ev.rule[kv.substr(0, eq)] = kv.substr(eq + 1);
            }
        }
    }
    return events;
}

// ── Recurrence ───────────────────────────────────────────────────────────────

int weekday_index(const std::string& s) {
    static const char* names[] = {"SU", "MO", "TU", "WE", "TH", "FR", "SA"};
    for (int i = 0; i < 7; ++i) if (s == names[i]) return i;
    return -1;
}

// Every start of `ev` (in UTC) up to `until`, a few thousand at most.
std::vector<sys_seconds> occurrences(const Event& ev, sys_seconds until) {
    std::vector<sys_seconds> out;
    if (!ev.has_rule) { out.push_back(to_sys(ev.start)); return out; }

    const std::string freq = ev.rule.count("FREQ") ? ev.rule.at("FREQ") : "";
    const int interval = std::max(1, ev.rule.count("INTERVAL") ? std::atoi(ev.rule.at("INTERVAL").c_str()) : 1);
    const int count = ev.rule.count("COUNT") ? std::atoi(ev.rule.at("COUNT").c_str()) : -1;
    sys_seconds rule_end = until;
    if (ev.rule.count("UNTIL")) {
        const When u = parse_when(ev.rule.at("UNTIL"), {});
        // A date-only UNTIL includes that whole day.
        if (u.ok) rule_end = std::min(until, to_sys(u) + (u.date_only ? seconds{days{1}} - seconds{1} : seconds{0}));
    }
    // BYDAY: weekday and, for monthly and yearly rules, which one of the month ("-1FR").
    std::vector<std::pair<int, int>> byday;
    if (ev.rule.count("BYDAY")) {
        std::istringstream list(ev.rule.at("BYDAY"));
        std::string one;
        while (std::getline(list, one, ',')) {
            if (one.size() < 2) continue;
            const int wd = weekday_index(one.substr(one.size() - 2));
            const int nth = one.size() > 2 ? std::atoi(one.substr(0, one.size() - 2).c_str()) : 0;
            if (wd >= 0) byday.push_back({wd, nth});
        }
    }
    std::vector<int> bymonthday;
    if (ev.rule.count("BYMONTHDAY")) {
        std::istringstream list(ev.rule.at("BYMONTHDAY"));
        std::string one;
        while (std::getline(list, one, ',')) bymonthday.push_back(std::atoi(one.c_str()));
    }

    const local_days first_day = floor<days>(ev.start.wall);
    const auto time_of_day = ev.start.wall - first_day;
    const year_month_day ymd0{first_day};
    int emitted = 0;
    // Candidates in wall time, in order; each checked against the rule's end.
    auto emit = [&](local_days d) -> bool {
        if (d < first_day) return true;
        When w = ev.start;
        w.wall = d + time_of_day;
        const sys_seconds t = to_sys(w);
        if (t > rule_end) return false;
        if (count >= 0 && emitted >= count) return false;
        ++emitted;
        out.push_back(t);
        return out.size() < 5000;
    };
    auto month_days = [&](year_month ym) {
        std::vector<local_days> ds;
        const local_days start{ym / day{1}};
        const local_days stop{ym / last};
        if (!byday.empty()) {
            for (const auto& [wd, nth] : byday) {
                std::vector<local_days> hits;
                for (local_days d = start; d <= stop; d += days{1})
                    if (weekday{d}.c_encoding() == unsigned(wd)) hits.push_back(d);
                if (nth == 0) ds.insert(ds.end(), hits.begin(), hits.end());
                else if (nth > 0 && nth <= int(hits.size())) ds.push_back(hits[nth - 1]);
                else if (nth < 0 && -nth <= int(hits.size())) ds.push_back(hits[hits.size() + nth]);
            }
        } else if (!bymonthday.empty()) {
            const int last_day = int(unsigned(year_month_day{stop}.day()));
            for (int md : bymonthday) {
                const int dd = md > 0 ? md : last_day + md + 1;
                if (dd >= 1 && dd <= last_day) ds.push_back(start + days{dd - 1});
            }
        } else {
            const year_month_day c{ym / ymd0.day()};
            if (c.ok()) ds.push_back(local_days{c});
        }
        std::sort(ds.begin(), ds.end());
        return ds;
    };

    if (freq == "DAILY") {
        for (local_days d = first_day;; d += days{interval}) {
            if (!byday.empty()) {
                const int wd = int(weekday{d}.c_encoding());
                if (std::none_of(byday.begin(), byday.end(), [&](auto& b) { return b.first == wd; })) {
                    if (to_sys(When{d + time_of_day, ev.start.zone, ev.start.utc, false, true}) > rule_end) break;
                    continue;
                }
            }
            if (!emit(d)) break;
        }
    } else if (freq == "WEEKLY") {
        // Weeks counted from the one holding DTSTART, starting on Monday (WKST's default).
        const local_days week0 = first_day - (weekday{first_day} - Monday);
        std::vector<int> wds;
        for (const auto& b : byday) wds.push_back(b.first);
        if (wds.empty()) wds.push_back(int(weekday{first_day}.c_encoding()));
        bool go = true;
        for (local_days wk = week0; go; wk += weeks{interval}) {
            std::vector<local_days> ds;
            for (int wd : wds) ds.push_back(wk + (weekday{unsigned(wd)} - Monday));
            std::sort(ds.begin(), ds.end());
            for (local_days d : ds) if (!(go = emit(d))) break;
            if (to_sys(When{wk + time_of_day, ev.start.zone, ev.start.utc, false, true}) > rule_end) break;
        }
    } else if (freq == "MONTHLY") {
        bool go = true;
        for (year_month ym = ymd0.year() / ymd0.month(); go; ym += months{interval}) {
            for (local_days d : month_days(ym)) if (!(go = emit(d))) break;
            if (to_sys(When{local_days{ym / day{1}} + time_of_day, ev.start.zone, ev.start.utc, false, true}) > rule_end) break;
        }
    } else if (freq == "YEARLY") {
        bool go = true;
        for (year y = ymd0.year(); go; y += years{interval}) {
            for (local_days d : month_days(y / ymd0.month())) if (!(go = emit(d))) break;
            if (to_sys(When{local_days{y / January / 1} + time_of_day, ev.start.zone, ev.start.utc, false, true}) > rule_end) break;
        }
    } else {
        out.push_back(to_sys(ev.start));
    }
    return out;
}

} // namespace

std::string events_json(const std::vector<std::string>& sources, int hours_ahead) {
    std::vector<std::string> errors;
    std::vector<Event> all;
    for (const auto& s : sources)
        for (const auto& text : load_source(s, hours_ahead, errors))
            for (auto& e : parse_events(text)) all.push_back(std::move(e));

    const sys_seconds now = floor<seconds>(system_clock::now());
    const sys_seconds until = now + hours{std::max(1, hours_ahead)};

    // Occurrences that an override moved or cancelled, by event.
    std::map<std::string, std::set<sys_seconds>> overridden;
    for (const auto& e : all)
        if (e.is_override) overridden[e.uid].insert(e.replaces);

    nlohmann::json list = nlohmann::json::array();
    for (const auto& e : all) {
        if (e.cancelled) continue;
        const auto& moved = overridden[e.uid];
        for (const sys_seconds start : occurrences(e, until)) {
            if (!e.is_override && (e.exdates.count(start) || moved.count(start))) continue;
            const sys_seconds end = start + e.length;
            if (end <= now || start >= until) continue;
            list.push_back({
                {"title", e.title}, {"location", e.location},
                {"start", duration_cast<milliseconds>(start.time_since_epoch()).count()},
                {"end", duration_cast<milliseconds>(end.time_since_epoch()).count()},
                {"allDay", e.start.date_only}, {"busy", e.busy}
            });
        }
    }
    std::sort(list.begin(), list.end(), [](const auto& a, const auto& b) { return a["start"] < b["start"]; });
    return nlohmann::json{{"events", list}, {"errors", errors}}.dump();
}

} // namespace Calendar
