#include "calendar_net.hpp"

#include <cstring>
#include <fstream>
#include <regex>
#include <sstream>
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

#include <openssl/evp.h>
#include <openssl/rand.h>

using namespace std::chrono;
namespace fs = std::filesystem;

namespace Calendar::net {

Reply request(const std::string& method, const std::string& url,
              const std::vector<std::string>& args, const std::string& secret) {
    int in_pipe[2], out_pipe[2];
    Reply r;
    if (pipe(in_pipe) != 0) return r;
    if (pipe(out_pipe) != 0) { close(in_pipe[0]); close(in_pipe[1]); return r; }
    const std::string marker = "\n@@b1air@@";
    std::vector<std::string> argv = {"curl", "-sS", "-L", "--max-time", "20", "--proto", "=https",
                                     "--proto-redir", "=https", "-K", "-", "-X", method};
    argv.insert(argv.end(), args.begin(), args.end());
    argv.push_back("-w");
    argv.push_back(marker + "%{http_code} %{url_effective}");
    argv.push_back(url);
    const pid_t pid = fork();
    if (pid == 0) {
        dup2(in_pipe[0], STDIN_FILENO);
        dup2(out_pipe[1], STDOUT_FILENO);
        const int null_fd = open("/dev/null", O_WRONLY);
        if (null_fd >= 0) dup2(null_fd, STDERR_FILENO);
        close(in_pipe[0]); close(in_pipe[1]); close(out_pipe[0]); close(out_pipe[1]);
        std::vector<char*> c;
        for (auto& a : argv) c.push_back(a.data());
        c.push_back(nullptr);
        execvp("curl", c.data());
        _exit(127);
    }
    close(in_pipe[0]);
    close(out_pipe[1]);
    if (pid < 0) { close(in_pipe[1]); close(out_pipe[0]); return r; }
    for (size_t off = 0; off < secret.size();) {
        const ssize_t n = write(in_pipe[1], secret.data() + off, secret.size() - off);
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

std::string cfg(const std::string& key, const std::string& value) {
    std::string q;
    for (char c : value) {
        if (c == '"' || c == '\\') q += '\\';
        if (c == '\n') { q += "\\n"; continue; }
        q += c;
    }
    return key + " = \"" + q + "\"\n";
}

std::string url_encode(const std::string& s) {
    static const char* hex = "0123456789ABCDEF";
    std::string out;
    for (unsigned char c : s) {
        if (std::isalnum(c) || c == '-' || c == '_' || c == '.' || c == '~') out += char(c);
        else { out += '%'; out += hex[c >> 4]; out += hex[c & 15]; }
    }
    return out;
}

std::string url_decode(const std::string& s) {
    std::string out;
    for (size_t i = 0; i < s.size(); ++i) {
        if (s[i] == '%' && i + 2 < s.size() && std::isxdigit((unsigned char)s[i + 1]) && std::isxdigit((unsigned char)s[i + 2])) {
            out += char(std::stoi(s.substr(i + 1, 2), nullptr, 16));
            i += 2;
        } else {
            out += s[i] == '+' ? ' ' : s[i];
        }
    }
    return out;
}

std::string md5_hex(const std::string& s) {
    unsigned char d[EVP_MAX_MD_SIZE];
    unsigned int n = 0;
    EVP_Digest(s.data(), s.size(), d, &n, EVP_md5(), nullptr);
    static const char* hex = "0123456789abcdef";
    std::string out;
    for (unsigned i = 0; i < n; ++i) { out += hex[d[i] >> 4]; out += hex[d[i] & 15]; }
    return out;
}

std::string base64url(const unsigned char* data, size_t n) {
    static const char* abc = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_";
    std::string out;
    for (size_t i = 0; i < n; i += 3) {
        const unsigned v = (unsigned(data[i]) << 16) | (i + 1 < n ? unsigned(data[i + 1]) << 8 : 0) | (i + 2 < n ? data[i + 2] : 0);
        out += abc[(v >> 18) & 63];
        out += abc[(v >> 12) & 63];
        if (i + 1 < n) out += abc[(v >> 6) & 63];
        if (i + 2 < n) out += abc[v & 63];
    }
    return out;
}

std::string base64url_decode(const std::string& s) {
    auto val = [](char c) -> int {
        if (c >= 'A' && c <= 'Z') return c - 'A';
        if (c >= 'a' && c <= 'z') return c - 'a' + 26;
        if (c >= '0' && c <= '9') return c - '0' + 52;
        if (c == '-' || c == '+') return 62;
        if (c == '_' || c == '/') return 63;
        return -1;
    };
    std::string out;
    unsigned acc = 0;
    int bits = 0;
    for (char c : s) {
        const int v = val(c);
        if (v < 0) continue;
        acc = (acc << 6) | unsigned(v);
        bits += 6;
        if (bits >= 8) { bits -= 8; out += char((acc >> bits) & 0xff); }
    }
    return out;
}

std::string random_token(size_t bytes) {
    std::vector<unsigned char> b(bytes);
    if (RAND_bytes(b.data(), int(b.size())) != 1) return "";
    return base64url(b.data(), b.size());
}

std::string sha256_base64url(const std::string& s) {
    unsigned char d[EVP_MAX_MD_SIZE];
    unsigned int n = 0;
    EVP_Digest(s.data(), s.size(), d, &n, EVP_sha256(), nullptr);
    return base64url(d, n);
}

std::vector<std::string> elements(const std::string& xml, const std::string& name) {
    std::vector<std::string> out;
    const std::regex re("<(?:[A-Za-z0-9_-]+:)?" + name + R"((?:\s[^>]*)?(?:/>|>([\s\S]*?)</(?:[A-Za-z0-9_-]+:)?)" + name + ">)");
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

std::string resolve(const std::string& base, const std::string& href) {
    if (href.rfind("http", 0) == 0) return href;
    const size_t host_end = base.find('/', base.find("://") + 3);
    return (host_end == std::string::npos ? base : base.substr(0, host_end)) + href;
}

namespace {
std::string stamp(sys_seconds t, const char* fmt) {
    const auto d = floor<days>(t);
    const year_month_day ymd{d};
    const hh_mm_ss hms{t - d};
    char out[48];
    std::snprintf(out, sizeof out, fmt, int(ymd.year()), unsigned(ymd.month()), unsigned(ymd.day()),
                  long(hms.hours().count()), long(hms.minutes().count()), long(hms.seconds().count()));
    return out;
}
}
std::string utc_stamp(sys_seconds t) { return stamp(t, "%04d%02u%02uT%02ld%02ld%02ldZ"); }
std::string utc_iso(sys_seconds t) { return stamp(t, "%04d-%02u-%02uT%02ld:%02ld:%02ldZ"); }

bool parse_iso(const std::string& s, sys_seconds& out) {
    int y, mo, d, h = 0, mi = 0, se = 0;
    if (std::sscanf(s.c_str(), "%4d-%2d-%2dT%2d:%2d:%2d", &y, &mo, &d, &h, &mi, &se) < 3) return false;
    const year_month_day ymd{year{y}, month{unsigned(mo)}, day{unsigned(d)}};
    if (!ymd.ok()) return false;
    out = sys_days{ymd} + hours{h} + minutes{mi} + seconds{se};
    // The offset after the time, if any: "+02:00", "-0500", "Z".
    const size_t t = s.find('T');
    if (t != std::string::npos) {
        const size_t sign = s.find_first_of("+-", t);
        if (sign != std::string::npos) {
            int oh = 0, om = 0;
            if (std::sscanf(s.c_str() + sign + 1, "%2d:%2d", &oh, &om) >= 1 ||
                std::sscanf(s.c_str() + sign + 1, "%2d%2d", &oh, &om) >= 1) {
                const minutes off = hours{oh} + minutes{om};
                out -= (s[sign] == '-' ? -off : off);
            }
        }
    }
    return true;
}

std::string read_file(const fs::path& p) {
    std::ifstream f(p, std::ios::binary);
    std::ostringstream s;
    s << f.rdbuf();
    return s.str();
}

bool write_private(const fs::path& p, const std::string& text) {
    const fs::path part = p.string() + ".part";
    const int fd = open(part.c_str(), O_WRONLY | O_CREAT | O_TRUNC | O_CLOEXEC | O_NOFOLLOW, 0600);
    if (fd < 0) return false;
    bool ok = true;
    for (size_t off = 0; off < text.size() && ok;) {
        const ssize_t n = write(fd, text.data() + off, text.size() - off);
        if (n > 0) off += size_t(n); else if (n < 0 && errno == EINTR) continue; else ok = false;
    }
    close(fd);
    std::error_code ec;
    if (ok) fs::rename(part, p, ec); else fs::remove(part, ec);
    return ok && !ec;
}

std::string cache_dir() {
    const char* xdg = std::getenv("XDG_CACHE_HOME");
    const char* home = std::getenv("HOME");
    std::string base = xdg && *xdg ? xdg : std::string(home ? home : "/tmp") + "/.cache";
    return base + "/b1air/calendar";
}

}
