#pragma once

// What the calendar reader (calendar.cpp) and its accounts
// (calendar_accounts.cpp) share: requests through curl, with anything
// secret — a password, a token, a code — on its standard input as curl
// configuration, never on a command line another user could read; a little
// XML for CalDAV; the cache folder.

#include <chrono>
#include <filesystem>
#include <string>
#include <vector>

namespace Calendar::net {

struct Reply {
    int status = 0;       // 0: no answer at all
    std::string url;      // where it ended up, after redirects
    std::string body;
};

// One request. `args` are curl's own, nothing secret; `secret` is curl
// configuration ("user = …", "header = …", "data-binary = …" lines, made
// with cfg()) handed to it on its standard input.
Reply request(const std::string& method, const std::string& url,
              const std::vector<std::string>& args, const std::string& secret);

// A line of curl configuration, quoted as curl reads it.
std::string cfg(const std::string& key, const std::string& value);

std::string url_encode(const std::string& s);
std::string url_decode(const std::string& s);
std::string md5_hex(const std::string& s);
std::string base64url(const unsigned char* data, size_t n);
std::string base64url_decode(const std::string& s);
std::string random_token(size_t bytes);
std::string sha256_base64url(const std::string& s);

// The text of every element named `name`, whatever namespace prefix the
// server gives it (d:href, D:href, href).
std::vector<std::string> elements(const std::string& xml, const std::string& name);
std::string xml_text(std::string s);
std::string trim(const std::string& s);
// An href against the address it came from: a path keeps that host.
std::string resolve(const std::string& base, const std::string& href);

// 20261019T120000Z, and the 2026-10-19T12:00:00Z of JSON APIs.
std::string utc_stamp(std::chrono::sys_seconds t);
std::string utc_iso(std::chrono::sys_seconds t);
// "2026-10-19T10:00:00+02:00", "…Z", or no offset (then UTC); false if not a time.
bool parse_iso(const std::string& s, std::chrono::sys_seconds& out);

std::string read_file(const std::filesystem::path& p);
// Written readable by its owner alone: it may hold someone's calendar.
bool write_private(const std::filesystem::path& p, const std::string& text);
std::string cache_dir();

}
