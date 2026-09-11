// b1air Desktop Environment — local developer controller.
// Build: c++ -std=c++20 -O2 -Wall -Wextra tools/controller.cpp -o tools/controller
// The server is intentionally localhost-only and every request requires the
// per-process token printed at startup. Mutating actions use POST.

#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/socket.h>
#include <sys/wait.h>
#include <unistd.h>

#include <array>
#include <charconv>
#include <cctype>
#include <cerrno>
#include <cstring>
#include <cstdlib>
#include <iostream>
#include <random>
#include <sstream>
#include <string>
#include <unordered_map>
#include <vector>

namespace {

using Args = std::vector<std::string>;
const std::unordered_map<std::string, std::string> actions = {
    {"settings", "quickshell ipc call main toggleSettings"},
    {"launcher", "quickshell ipc call main toggleLauncher"},
    {"control", "quickshell ipc call main toggleControl"},
    {"clipboard", "quickshell ipc call main toggleClipboard"},
    {"focustime", "quickshell ipc call main toggleFocusTime"},
    {"calendar", "quickshell ipc call main toggleCalendar"},
    {"music", "quickshell ipc call main toggleMusic"},
    {"network", "quickshell ipc call main toggleNetwork"},
    {"keyboard", "quickshell ipc call main toggleKeyboard"},
    {"emoji", "quickshell ipc call main toggleEmoji"},
    {"session", "quickshell ipc call main toggleSession"},
    {"reload_shell", "quickshell ipc call main forceReload"},
    {"close_all", "quickshell ipc call main close"},
    {"notify_test", "notify-send -u normal B1air-OS test"},
    {"notify_warn", "notify-send -u critical Warning test"},
    {"gamemode", "b1air-daemon game-mode toggle"},
    {"remote_vnc", "b1air-daemon remote toggle"},
    {"sidecar", "b1air-daemon sidecar create 1920 1080"},
    {"sidecar_rm", "b1air-daemon sidecar remove"},
    {"lock", "b1air-daemon power lock"},
    {"terminal", "swaymsg exec b1air-term"},
    {"files", "swaymsg exec b1air-files"},
};

std::string random_token() {
    std::random_device rd;
    std::ostringstream out;
    for (int i = 0; i < 32; ++i) out << std::hex << (rd() & 0xf);
    return out.str();
}

bool constant_time_equal(const std::string& a, const std::string& b) {
    if (a.size() != b.size()) return false;
    unsigned char diff = 0;
    for (size_t i = 0; i < a.size(); ++i) diff |= static_cast<unsigned char>(a[i] ^ b[i]);
    return diff == 0;
}

std::string html(const std::string& token) {
    std::ostringstream h;
    h << "<!doctype html><meta charset=utf-8><title>b1air controller</title>"
      << "<style>body{font:16px sans-serif;background:#1a1b26;color:#c0caf5;padding:2em}";
    h << "button{margin:.3em;padding:.7em;background:#24283b;color:#c0caf5;border:1px solid #414868;border-radius:6px}";
    h << "</style><h1>b1air OS controller</h1><p>Local debug controller; token protected.</p><div id=x>";
    for (const auto& [name, _] : actions) h << "<button onclick=call('" << name << "')>" << name << "</button>";
    h << "</div><pre id=o></pre><script>const token='" << token << "';"
      << "async function call(action){let r=await fetch('/api/call',{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:'token='+encodeURIComponent(token)+'&action='+encodeURIComponent(action)});document.querySelector('#o').textContent=await r.text()}</script>";
    return h.str();
}

std::string response(const std::string& status, const std::string& type, const std::string& body) {
    return "HTTP/1.1 " + status + "\r\nContent-Type: " + type + "\r\nContent-Length: " +
           std::to_string(body.size()) + "\r\nConnection: close\r\n\r\n" + body;
}

std::string form_value(const std::string& body, const std::string& key) {
    const std::string needle = key + "=";
    const size_t start = body.find(needle);
    if (start == std::string::npos) return {};
    size_t end = body.find('&', start + needle.size());
    std::string value = body.substr(start + needle.size(), end == std::string::npos ? end : end - start - needle.size());
    for (size_t i = 0; i + 2 < value.size(); ++i) {
        if (value[i] == '%' && std::isxdigit(static_cast<unsigned char>(value[i + 1])) && std::isxdigit(static_cast<unsigned char>(value[i + 2]))) {
            unsigned v = 0;
            std::from_chars(value.data() + i + 1, value.data() + i + 3, v, 16);
            value.replace(i, 3, 1, static_cast<char>(v));
        } else if (value[i] == '+') value[i] = ' ';
    }
    return value;
}

std::string run_ssh(const std::string& script, const std::string& command) {
    int pipefd[2];
    if (pipe(pipefd) != 0) return "";
    const pid_t pid = fork();
    if (pid == 0) {
        dup2(pipefd[1], STDOUT_FILENO);
        dup2(pipefd[1], STDERR_FILENO);
        close(pipefd[0]); close(pipefd[1]);
        execl(script.c_str(), script.c_str(), command.c_str(), static_cast<char*>(nullptr));
        _exit(127);
    }
    close(pipefd[1]);
    std::string output;
    std::array<char, 4096> buf{};
    ssize_t n;
    while ((n = read(pipefd[0], buf.data(), buf.size())) > 0) output.append(buf.data(), static_cast<size_t>(n));
    close(pipefd[0]);
    int status = 0;
    waitpid(pid, &status, 0);
    return output;
}

void serve(int fd, const std::string& token, const std::string& ssh_script) {
    std::string request;
    std::array<char, 8192> buf{};
    ssize_t n;
    while ((n = recv(fd, buf.data(), buf.size(), 0)) > 0) {
        request.append(buf.data(), static_cast<size_t>(n));
        if (request.find("\r\n\r\n") != std::string::npos) break;
        if (request.size() > 65536) { close(fd); return; }
    }
    const size_t header_end = request.find("\r\n\r\n");
    if (header_end == std::string::npos) { close(fd); return; }
    std::istringstream first(request.substr(0, request.find("\r\n")));
    std::string method, target, version;
    first >> method >> target >> version;
    const size_t content_pos = request.find("Content-Length:");
    size_t content_length = 0;
    if (content_pos != std::string::npos) {
        const size_t value_start = content_pos + std::strlen("Content-Length:");
        const size_t value_end = request.find("\r\n", value_start);
        const std::string value = request.substr(value_start, value_end - value_start);
        const size_t first = value.find_first_not_of(" \t");
        const size_t last = value.find_last_not_of(" \t");
        if (first != std::string::npos) {
            const auto parsed = std::from_chars(value.data() + first, value.data() + last + 1, content_length);
            if (parsed.ec != std::errc{} || content_length > 65536) { close(fd); return; }
        }
    }
    while (request.size() < header_end + 4 + content_length) {
        n = recv(fd, buf.data(), buf.size(), 0);
        if (n <= 0) break;
        request.append(buf.data(), static_cast<size_t>(n));
    }
    const std::string body = request.substr(header_end + 4, content_length);
    const std::string token_value = method == "POST" ? form_value(body, "token") : form_value(target, "token");
    if (!constant_time_equal(token, token_value)) {
        const std::string out = response("403 Forbidden", "text/plain", "forbidden\n");
        send(fd, out.data(), out.size(), 0); close(fd); return;
    }
    if (method == "GET" && target.rfind("/", 0) == 0) {
        const std::string out = response("200 OK", "text/html; charset=utf-8", html(token));
        send(fd, out.data(), out.size(), 0);
    } else if (method == "POST" && target == "/api/call") {
        const std::string action = form_value(body, "action");
        const auto it = actions.find(action);
        const std::string out = it == actions.end() ? response("400 Bad Request", "text/plain", "unknown action\n")
                                                     : response("200 OK", "text/plain", run_ssh(ssh_script, it->second));
        send(fd, out.data(), out.size(), 0);
    } else {
        const std::string out = response("404 Not Found", "text/plain", "not found\n");
        send(fd, out.data(), out.size(), 0);
    }
    close(fd);
}

} // namespace

int main(int argc, char** argv) {
    int port = 8765;
    if (argc > 1) {
        const int parsed = std::atoi(argv[1]);
        if (parsed < 1024 || parsed > 65535) return 2;
        port = parsed;
    }
    const std::string token = random_token();
    const char* home = std::getenv("HOME");
    const std::string default_script = std::string(home ? home : "") + "/vm-arch/ssh.sh";
    const std::string ssh_script = std::getenv("B1AIR_SSH_SCRIPT") ? std::getenv("B1AIR_SSH_SCRIPT") : default_script;
    if (ssh_script.empty()) {
        std::cerr << "Set B1AIR_SSH_SCRIPT to the trusted SSH helper path\n";
        return 2;
    }
    const int server = socket(AF_INET, SOCK_STREAM, 0);
    if (server < 0) return 1;
    int one = 1; setsockopt(server, SOL_SOCKET, SO_REUSEADDR, &one, sizeof(one));
    sockaddr_in addr{}; addr.sin_family = AF_INET; addr.sin_port = htons(static_cast<uint16_t>(port));
    inet_pton(AF_INET, "127.0.0.1", &addr.sin_addr);
    if (bind(server, reinterpret_cast<sockaddr*>(&addr), sizeof(addr)) != 0 || listen(server, 8) != 0) return 1;
    std::cout << "b1air controller: http://127.0.0.1:" << port << "/?token=" << token << "\n";
    while (true) {
        const int client = accept(server, nullptr, nullptr);
        if (client >= 0) serve(client, token, ssh_script);
    }
}
