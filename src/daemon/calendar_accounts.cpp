#include "calendar_accounts.hpp"
#include "calendar_net.hpp"

#include <algorithm>
#include <cstring>
#include <map>
#include <set>
#include <sstream>
#include <arpa/inet.h>
#include <netinet/in.h>
#include <poll.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <unistd.h>

#include <nlohmann/json.hpp>

#include "secret_store.hpp"

using namespace std::chrono;
using nlohmann::json;
namespace fs = std::filesystem;

// The suite's own registrations with Google and Microsoft, given at build
// time (-DB1AIR_GOOGLE_CLIENT_ID=… and the rest; docs/CALENDAR-SIGNIN.md
// says how to make them) or in the environment. A desktop app's client
// "secret" is not one — Google hands it to every copy — but it is asked for.
#ifndef B1AIR_GOOGLE_CLIENT_ID
#define B1AIR_GOOGLE_CLIENT_ID ""
#endif
#ifndef B1AIR_GOOGLE_CLIENT_SECRET
#define B1AIR_GOOGLE_CLIENT_SECRET ""
#endif
#ifndef B1AIR_MICROSOFT_CLIENT_ID
#define B1AIR_MICROSOFT_CLIENT_ID ""
#endif

namespace Calendar {
namespace {

using namespace net;

std::string env_or(const char* name, const char* built) {
    const char* v = std::getenv(name);
    return v && *v ? v : built;
}

struct Provider {
    std::string name, auth, token, scope, client_id, client_secret;
};
Provider provider(const std::string& name) {
    if (name == "google")
        return {name, "https://accounts.google.com/o/oauth2/v2/auth", "https://oauth2.googleapis.com/token",
                "openid email https://www.googleapis.com/auth/calendar.readonly",
                env_or("B1AIR_GOOGLE_CLIENT_ID", B1AIR_GOOGLE_CLIENT_ID),
                env_or("B1AIR_GOOGLE_CLIENT_SECRET", B1AIR_GOOGLE_CLIENT_SECRET)};
    if (name == "microsoft")
        return {name, "https://login.microsoftonline.com/common/oauth2/v2.0/authorize",
                "https://login.microsoftonline.com/common/oauth2/v2.0/token",
                "offline_access User.Read Calendars.Read",
                env_or("B1AIR_MICROSOFT_CLIENT_ID", B1AIR_MICROSOFT_CLIENT_ID), ""};
    return {};
}

// ── A source, taken apart ────────────────────────────────────────────────────

struct Account {
    std::string kind;                // icloud, caldav, google, microsoft
    std::string key;                 // the source before any #
    std::string user, base;          // CalDAV: who, and where
    std::set<std::string> hidden;    // calendars not read
};

Account parse(const std::string& src) {
    Account a;
    const size_t hash = src.find('#');
    a.key = src.substr(0, hash);
    if (hash != std::string::npos && src.compare(hash, 6, "#hide=") == 0) {
        std::istringstream list(url_decode(src.substr(hash + 6)));
        std::string id;
        while (std::getline(list, id)) if (!id.empty()) a.hidden.insert(id);
    }
    const size_t colon = a.key.find(':');
    a.kind = a.key.substr(0, colon);
    const std::string rest = colon == std::string::npos ? "" : a.key.substr(colon + 1);
    if (a.kind == "icloud") {
        a.user = rest;
        a.base = "https://caldav.icloud.com/";
    } else if (a.kind == "caldav") {
        a.base = rest;
        const size_t scheme = a.base.find("://");
        // The last @ before the path: a user name may be an address itself.
        const size_t slash = scheme == std::string::npos ? std::string::npos : a.base.find('/', scheme + 3);
        const size_t at = scheme == std::string::npos ? std::string::npos : a.base.rfind('@', slash);
        if (at != std::string::npos && at > scheme) {
            a.user = a.base.substr(scheme + 3, at - scheme - 3);
            a.base = a.base.substr(0, scheme + 3) + a.base.substr(at + 1);
        }
    } else {
        a.user = rest;
    }
    return a;
}

std::string secret_name(const Account& a) { return "calendar-" + md5_hex(a.key); }

// Why it could not be read, as a word Settings puts into a sentence.
std::string why(const Reply& r) {
    return r.status == 401 || r.status == 403 ? "refused" : r.status == 0 ? "unreachable"
         : "status " + std::to_string(r.status);
}

struct Cal { std::string id, name, color; };

// ── CalDAV ───────────────────────────────────────────────────────────────────

std::string caldav_auth(const Account& a, std::string& error) {
    std::string password;
    b1air::SecretStore store;
    if (a.user.empty() || !store.get(secret_name(a), password) || password.empty()) {
        error = "no-password";
        return "";
    }
    const std::string c = cfg("user", a.user + ":" + password);
    std::fill(password.begin(), password.end(), '\0');
    return c;
}

const std::vector<std::string> kXml = {"-H", "Content-Type: application/xml; charset=utf-8"};
std::vector<std::string> xml_args(const std::string& depth, const std::string& body) {
    std::vector<std::string> args = kXml;
    args.insert(args.end(), {"-H", "Depth: " + depth, "--data-binary", body});
    return args;
}

// The principal, its calendar home, and the calendars in it that hold events
// (not reminders' task lists): RFC 4791 and 6764.
std::vector<Cal> caldav_calendars(const Account& a, const std::string& auth, std::string& error) {
    const std::string pf = R"(<?xml version="1.0"?><d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav" xmlns:x="http://apple.com/ns/ical/"><d:prop>)";
    Reply r = request("PROPFIND", a.base, xml_args("0", pf + "<d:current-user-principal/></d:prop></d:propfind>"), auth);
    if (r.status != 207) { error = why(r); return {}; }
    std::string principal = a.base;
    for (const auto& p : elements(r.body, "current-user-principal")) {
        const auto h = elements(p, "href");
        if (!h.empty()) principal = resolve(r.url, trim(h[0]));
    }
    r = request("PROPFIND", principal, xml_args("0", pf + "<c:calendar-home-set/></d:prop></d:propfind>"), auth);
    if (r.status != 207) { error = why(r); return {}; }
    std::string home;
    for (const auto& p : elements(r.body, "calendar-home-set")) {
        const auto h = elements(p, "href");
        if (!h.empty()) home = resolve(r.url, trim(h[0]));
    }
    if (home.empty()) { error = "no-calendars"; return {}; }
    r = request("PROPFIND", home, xml_args("1", pf + "<d:resourcetype/><d:displayname/><x:calendar-color/>"
                                                 "<c:supported-calendar-component-set/></d:prop></d:propfind>"), auth);
    if (r.status != 207) { error = why(r); return {}; }
    std::vector<Cal> out;
    for (const auto& resp : elements(r.body, "response")) {
        const auto types = elements(resp, "resourcetype");
        if (types.empty() || types[0].find("calendar") == std::string::npos) continue;
        const auto comps = elements(resp, "supported-calendar-component-set");
        if (!comps.empty() && !comps[0].empty() && comps[0].find("VEVENT") == std::string::npos) continue;
        const auto h = elements(resp, "href");
        if (h.empty()) continue;
        Cal c;
        c.id = resolve(r.url, trim(h[0]));
        const auto n = elements(resp, "displayname");
        c.name = n.empty() ? "" : xml_text(trim(n[0]));
        const auto col = elements(resp, "calendar-color");
        c.color = col.empty() ? "" : trim(col[0]).substr(0, 7);
        if (c.name.empty()) c.name = c.id;
        out.push_back(c);
    }
    if (out.empty()) error = "no-calendars";
    return out;
}

void caldav_load(const Account& a, int hours, AccountData& data, std::string& error) {
    const std::string auth = caldav_auth(a, error);
    if (auth.empty()) return;
    const auto cals = caldav_calendars(a, auth, error);
    if (!error.empty()) return;
    const sys_seconds now = floor<seconds>(system_clock::now());
    const std::string query = R"(<?xml version="1.0"?><c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">)"
        "<d:prop><c:calendar-data/></d:prop><c:filter><c:comp-filter name=\"VCALENDAR\"><c:comp-filter name=\"VEVENT\">"
        "<c:time-range start=\"" + utc_stamp(now - days{1}) + "\" end=\"" + utc_stamp(now + std::chrono::hours{hours}) + "\"/>"
        "</c:comp-filter></c:comp-filter></c:filter></c:calendar-query>";
    for (const auto& c : cals) {
        if (a.hidden.count(c.id)) continue;
        const Reply q = request("REPORT", c.id, xml_args("1", query), auth);
        if (q.status != 207) continue;
        for (const auto& d : elements(q.body, "calendar-data")) data.ics.push_back(xml_text(trim(d)));
    }
}

// ── Signing in: Google and Microsoft ─────────────────────────────────────────
//
// OAuth 2.0 for a desktop app (RFC 8252): the browser opens the provider's
// own sign-in page; it sends the browser back to a port on this machine with
// a code, which is exchanged — with the PKCE verifier only this process
// knows — for a refresh token. That token, and not any password, is kept.

json token_request(const Provider& p, const std::map<std::string, std::string>& fields, std::string& error) {
    std::string body;
    for (const auto& [k, v] : fields) body += (body.empty() ? "" : "&") + k + "=" + url_encode(v);
    const Reply r = request("POST", p.token, {"-H", "Content-Type: application/x-www-form-urlencoded"},
                            cfg("data-binary", body));
    json j = json::parse(r.body, nullptr, false);
    if (r.status != 200 || j.is_discarded() || !j.contains("access_token")) {
        error = r.status == 0 ? "unreachable"
              : j.is_object() && j.contains("error") ? "refused" : why(r);
        return {};
    }
    return j;
}

// A fresh access token from the kept refresh token (Microsoft hands out a
// new refresh token each time; it is kept in place of the old).
std::string access_token(const Account& a, std::string& error) {
    const Provider p = provider(a.kind);
    if (p.client_id.empty()) { error = "not-configured"; return ""; }
    std::string stored;
    b1air::SecretStore store;
    json s = store.get(secret_name(a), stored) ? json::parse(stored, nullptr, false) : json();
    std::fill(stored.begin(), stored.end(), '\0');
    if (!s.is_object() || !s.contains("refresh_token")) { error = "signed-out"; return ""; }
    std::map<std::string, std::string> f = {{"grant_type", "refresh_token"}, {"client_id", p.client_id},
                                            {"refresh_token", s["refresh_token"].get<std::string>()}};
    if (!p.client_secret.empty()) f["client_secret"] = p.client_secret;
    if (a.kind == "microsoft") f["scope"] = p.scope;
    const json t = token_request(p, f, error);
    if (t.is_null()) { if (error == "refused") error = "signed-out"; return ""; }
    if (t.contains("refresh_token") && t["refresh_token"] != s["refresh_token"]) {
        s["refresh_token"] = t["refresh_token"];
        store.set(secret_name(a), s.dump());
    }
    return t["access_token"].get<std::string>();
}

json api_get(const std::string& url, const std::string& token, std::string& error,
             const std::vector<std::string>& extra = {}) {
    const Reply r = request("GET", url, extra, cfg("header", "Authorization: Bearer " + token));
    json j = json::parse(r.body, nullptr, false);
    if (r.status != 200 || j.is_discarded()) { error = why(r); return {}; }
    return j;
}

std::vector<Cal> oauth_calendars(const Account& a, const std::string& token, std::string& error) {
    std::vector<Cal> out;
    if (a.kind == "google") {
        const json j = api_get("https://www.googleapis.com/calendar/v3/users/me/calendarList?minAccessRole=freeBusyReader", token, error);
        for (const auto& c : j.value("items", json::array()))
            out.push_back({c.value("id", ""), c.value("summaryOverride", c.value("summary", "")), c.value("backgroundColor", "")});
    } else {
        const json j = api_get("https://graph.microsoft.com/v1.0/me/calendars?$select=id,name,hexColor", token, error);
        for (const auto& c : j.value("value", json::array()))
            out.push_back({c.value("id", ""), c.value("name", ""), c.value("hexColor", "")});
    }
    if (out.empty() && error.empty()) error = "no-calendars";
    return out;
}

void oauth_load(const Account& a, int hours, AccountData& data, std::string& error) {
    const std::string token = access_token(a, error);
    if (token.empty()) return;
    const auto cals = oauth_calendars(a, token, error);
    if (!error.empty()) return;
    const sys_seconds now = floor<seconds>(system_clock::now());
    const std::string from = utc_iso(now - days{1}), to = utc_iso(now + std::chrono::hours{hours});
    for (const auto& c : cals) {
        if (a.hidden.count(c.id)) continue;
        std::string e;
        if (a.kind == "google") {
            const json j = api_get("https://www.googleapis.com/calendar/v3/calendars/" + url_encode(c.id)
                + "/events?singleEvents=true&maxResults=250&timeMin=" + url_encode(from) + "&timeMax=" + url_encode(to), token, e);
            for (const auto& ev : j.value("items", json::array())) {
                if (ev.value("status", "") == "cancelled") continue;
                Expanded x;
                x.title = ev.value("summary", "");
                x.location = ev.value("location", "");
                const json s = ev.value("start", json::object()), en = ev.value("end", json::object());
                x.all_day = s.contains("date");
                if (!parse_iso(s.value("dateTime", s.value("date", "")), x.start)) continue;
                if (!parse_iso(en.value("dateTime", en.value("date", "")), x.end)) x.end = x.start;
                // A date-only day is the machine's own day, not UTC's.
                if (x.all_day) {
                    const auto* z = current_zone();
                    x.start = z->to_sys(local_seconds{x.start.time_since_epoch()}, choose::earliest);
                    x.end = z->to_sys(local_seconds{x.end.time_since_epoch()}, choose::earliest);
                }
                bool declined = false;
                for (const auto& at : ev.value("attendees", json::array()))
                    if (at.value("self", false) && at.value("responseStatus", "") == "declined") declined = true;
                x.busy = !x.all_day && !declined && ev.value("transparency", "opaque") != "transparent";
                data.events.push_back(x);
            }
        } else {
            const json j = api_get("https://graph.microsoft.com/v1.0/me/calendars/" + url_encode(c.id)
                + "/calendarView?$top=250&$select=subject,location,start,end,isAllDay,showAs,isCancelled,responseStatus"
                + "&startDateTime=" + url_encode(from) + "&endDateTime=" + url_encode(to), token, e,
                {"-H", "Prefer: outlook.timezone=\"UTC\""});
            for (const auto& ev : j.value("value", json::array())) {
                if (ev.value("isCancelled", false)) continue;
                Expanded x;
                x.title = ev.value("subject", "");
                x.location = ev.value("location", json::object()).value("displayName", "");
                x.all_day = ev.value("isAllDay", false);
                if (!parse_iso(ev.value("start", json::object()).value("dateTime", ""), x.start)) continue;
                if (!parse_iso(ev.value("end", json::object()).value("dateTime", ""), x.end)) x.end = x.start;
                const std::string show = ev.value("showAs", "busy");
                const std::string resp = ev.value("responseStatus", json::object()).value("response", "");
                x.busy = !x.all_day && resp != "declined" && (show == "busy" || show == "tentative" || show == "oof");
                data.events.push_back(x);
            }
        }
    }
}

// Waits for the browser to come back to 127.0.0.1:<port>/?code=…&state=…,
// answering it with a page that says where to go next.
std::map<std::string, std::string> wait_for_redirect(int server, int seconds_left) {
    const std::string page =
        "<!doctype html><meta charset=utf-8><title>b1air</title>"
        "<style>body{font:16px system-ui,sans-serif;display:grid;place-items:center;height:90vh;margin:0;"
        "background:#f5f6f7;color:#1d1f21}@media(prefers-color-scheme:dark){body{background:#1b1e20;color:#eceff1}}"
        "div{text-align:center}h1{font-weight:600;font-size:22px}</style>"
        "<div><h1>&#10003;</h1><p>You can close this tab and go back to Settings.</p>"
        "<p>&#1052;&#1086;&#1078;&#1085;&#1086; &#1079;&#1072;&#1082;&#1088;&#1099;&#1090;&#1100; "
        "&#1074;&#1082;&#1083;&#1072;&#1076;&#1082;&#1091;.</p></div>";
    const auto deadline = steady_clock::now() + seconds{seconds_left};
    while (steady_clock::now() < deadline) {
        pollfd p{server, POLLIN, 0};
        const int left = int(duration_cast<milliseconds>(deadline - steady_clock::now()).count());
        if (poll(&p, 1, std::max(left, 0)) <= 0) break;
        const int c = accept(server, nullptr, nullptr);
        if (c < 0) continue;
        std::string req;
        char buf[4096];
        pollfd cp{c, POLLIN, 0};
        while (req.find("\r\n\r\n") == std::string::npos && req.size() < 16384 && poll(&cp, 1, 3000) > 0) {
            const ssize_t n = read(c, buf, sizeof buf);
            if (n <= 0) break;
            req.append(buf, size_t(n));
        }
        const size_t sp1 = req.find(' '), sp2 = req.find(' ', sp1 + 1);
        const std::string target = sp1 == std::string::npos || sp2 == std::string::npos ? "" : req.substr(sp1 + 1, sp2 - sp1 - 1);
        std::map<std::string, std::string> q;
        const size_t qm = target.find('?');
        if (qm != std::string::npos) {
            std::istringstream parts(target.substr(qm + 1));
            std::string kv;
            while (std::getline(parts, kv, '&')) {
                const size_t eq = kv.find('=');
                if (eq != std::string::npos) q[kv.substr(0, eq)] = url_decode(kv.substr(eq + 1));
            }
        }
        const bool ours = q.count("code") || q.count("error");
        const std::string resp = ours
            ? "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nConnection: close\r\nContent-Length: "
              + std::to_string(page.size()) + "\r\n\r\n" + page
            : std::string("HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
        (void)!write(c, resp.data(), resp.size());
        close(c);
        if (ours) return q;
    }
    return {};
}

void open_browser(const std::string& url) {
    const pid_t pid = fork();
    if (pid == 0) {
        setsid();
        if (fork() == 0) {
            execlp("xdg-open", "xdg-open", url.c_str(), (char*)nullptr);
            _exit(127);
        }
        _exit(0);
    }
    if (pid > 0) waitpid(pid, nullptr, 0);
}

json signin(const std::string& kind) {
    const Provider p = provider(kind);
    if (p.name.empty()) return {{"ok", false}, {"error", "unknown"}};
    if (p.client_id.empty()) return {{"ok", false}, {"error", "not-configured"}};

    const int server = socket(AF_INET, SOCK_STREAM | SOCK_CLOEXEC, 0);
    sockaddr_in addr{};
    addr.sin_family = AF_INET;
    addr.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    socklen_t len = sizeof addr;
    if (server < 0 || bind(server, (sockaddr*)&addr, sizeof addr) != 0 || listen(server, 4) != 0
        || getsockname(server, (sockaddr*)&addr, &len) != 0) {
        if (server >= 0) close(server);
        return {{"ok", false}, {"error", "unreachable"}};
    }
    // Microsoft registers "http://localhost"; Google takes the address itself.
    const std::string redirect = std::string(kind == "microsoft" ? "http://localhost:" : "http://127.0.0.1:")
                               + std::to_string(ntohs(addr.sin_port));
    const std::string verifier = random_token(48), state = random_token(16);
    std::string url = p.auth + "?response_type=code&client_id=" + url_encode(p.client_id)
        + "&redirect_uri=" + url_encode(redirect) + "&scope=" + url_encode(p.scope)
        + "&state=" + state + "&code_challenge=" + sha256_base64url(verifier) + "&code_challenge_method=S256";
    if (kind == "google") url += "&access_type=offline&prompt=consent";
    else url += "&prompt=select_account";
    open_browser(url);

    const auto q = wait_for_redirect(server, 300);
    close(server);
    if (q.empty()) return {{"ok", false}, {"error", "timeout"}};
    if (!q.count("code") || q.at("state") != state) return {{"ok", false}, {"error", "cancelled"}};

    std::string error;
    std::map<std::string, std::string> f = {{"grant_type", "authorization_code"}, {"client_id", p.client_id},
                                            {"code", q.at("code")}, {"code_verifier", verifier}, {"redirect_uri", redirect}};
    if (!p.client_secret.empty()) f["client_secret"] = p.client_secret;
    if (kind == "microsoft") f["scope"] = p.scope;
    const json t = token_request(p, f, error);
    if (t.is_null()) return {{"ok", false}, {"error", error}};
    if (!t.contains("refresh_token")) return {{"ok", false}, {"error", "no-refresh-token"}};

    // Who signed in: Google says in its ID token, Microsoft when asked.
    std::string who;
    const std::string access = t["access_token"].get<std::string>();
    if (kind == "google" && t.contains("id_token")) {
        const std::string id = t["id_token"].get<std::string>();
        const size_t a = id.find('.'), b = id.find('.', a + 1);
        const json claims = json::parse(base64url_decode(id.substr(a + 1, b - a - 1)), nullptr, false);
        if (claims.is_object()) who = claims.value("email", "");
    } else if (kind == "microsoft") {
        const json me = api_get("https://graph.microsoft.com/v1.0/me?$select=mail,userPrincipalName", access, error);
        if (me.is_object()) who = me.value("mail", json()).is_string() ? me.value("mail", "") : me.value("userPrincipalName", "");
    }
    if (who.empty()) return {{"ok", false}, {"error", "no-account"}};

    Account acc = parse(kind + ":" + who);
    b1air::SecretStore store;
    if (!store.set(secret_name(acc), json{{"refresh_token", t["refresh_token"]}}.dump()))
        return {{"ok", false}, {"error", "store"}};
    error.clear();
    json cals = json::array();
    for (const auto& c : oauth_calendars(acc, access, error))
        cals.push_back({{"id", c.id}, {"name", c.name}, {"color", c.color}});
    return {{"ok", true}, {"source", acc.key}, {"account", who}, {"calendars", cals}};
}

} // namespace

bool is_account(const std::string& src) {
    for (const char* k : {"icloud:", "caldav:", "google:", "microsoft:"})
        if (src.rfind(k, 0) == 0) return true;
    return false;
}

AccountData load_account(const std::string& src, int hours, std::vector<std::string>& errors) {
    AccountData data;
    const Account a = parse(src);
    std::error_code ec;
    fs::create_directories(cache_dir(), ec);
    const fs::path file = fs::path(cache_dir()) / (md5_hex(src) + ".account");
    const bool fresh = fs::exists(file, ec)
        && fs::last_write_time(file, ec) > fs::file_time_type::clock::now() - minutes(15);
    if (!fresh) {
        std::string error;
        AccountData got;
        if (a.kind == "icloud" || a.kind == "caldav") caldav_load(a, std::max(hours, 24 * 7), got, error);
        else oauth_load(a, std::max(hours, 24 * 7), got, error);
        if (error.empty()) {
            json evs = json::array();
            for (const auto& e : got.events)
                evs.push_back({{"title", e.title}, {"location", e.location}, {"allDay", e.all_day}, {"busy", e.busy},
                               {"start", e.start.time_since_epoch().count()}, {"end", e.end.time_since_epoch().count()}});
            write_private(file, json{{"ics", got.ics}, {"events", evs}}.dump());
        } else {
            errors.push_back(a.key + ": " + error);
        }
    }
    const json kept = fs::exists(file, ec) ? json::parse(read_file(file), nullptr, false) : json();
    if (kept.is_object()) {
        for (const auto& t : kept.value("ics", json::array())) data.ics.push_back(t.get<std::string>());
        for (const auto& e : kept.value("events", json::array())) {
            Expanded x;
            x.title = e.value("title", ""); x.location = e.value("location", "");
            x.all_day = e.value("allDay", false); x.busy = e.value("busy", true);
            x.start = sys_seconds{seconds{e.value("start", 0LL)}};
            x.end = sys_seconds{seconds{e.value("end", 0LL)}};
            data.events.push_back(x);
        }
    }
    return data;
}

std::string account_command(const std::vector<std::string>& args) {
    const std::string sub = args.empty() ? "" : args[0];
    if (sub == "providers") {
        return json{{"google", !provider("google").client_id.empty()},
                    {"microsoft", !provider("microsoft").client_id.empty()}}.dump();
    }
    if (sub == "signin" && args.size() >= 2) return signin(args[1]).dump();
    if (sub == "check" && args.size() >= 2) {
        // The account's calendars, read with what is saved for it: whether
        // the password or sign-in works, and what to offer to show.
        const Account a = parse(args[1]);
        std::string error;
        std::vector<Cal> cals;
        if (a.kind == "icloud" || a.kind == "caldav") {
            const std::string auth = caldav_auth(a, error);
            if (!auth.empty()) cals = caldav_calendars(a, auth, error);
        } else if (a.kind == "google" || a.kind == "microsoft") {
            const std::string token = access_token(a, error);
            if (!token.empty()) cals = oauth_calendars(a, token, error);
        } else {
            error = "unknown";
        }
        if (!error.empty()) return json{{"ok", false}, {"error", error}}.dump();
        json list = json::array();
        for (const auto& c : cals)
            list.push_back({{"id", c.id}, {"name", c.name}, {"color", c.color}, {"hidden", a.hidden.count(c.id) > 0}});
        return json{{"ok", true}, {"calendars", list}}.dump();
    }
    return json{{"ok", false}, {"error", "usage: calendar-account providers | check <source> | signin google|microsoft"}}.dump();
}

}
