// =============================================================================
// b1air-settings — the desktop's own settings panel, hosted without quickshell.
//
// This binary spent most of its life unable to load its own window. The
// settings UI imports Quickshell and Services, and Quickshell's qmldir declares
//
//     linktarget quickshell-coreplugin
//     optional plugin quickshell-coreplugin
//
// meaning the plugin is expected to be linked into the host binary. The
// `quickshell` process links it; a plain Qt application does not, so every
// launch died with "module Quickshell plugin quickshell-coreplugin not found",
// and the program was eventually reduced to exec'ing `b1air-shell` instead.
//
// It is the real panel now — literally the same QML files the shell renders,
// with no fork and no second design — because the surface those files need from
// Quickshell turned out to be small enough to provide: six types and three
// functions in src/compat, plus stand-ins for the device modules. See
// src/compat/qs_compat.hpp for the measurement.
//
// What that buys is the settings being reachable when the shell is the thing
// that is broken, which is exactly when they are hardest to reach and most
// likely to be needed.
// =============================================================================

#include "proc_scan.hpp"
#include <QGuiApplication>
#include <map>
#include <QJsonObject>
#include <QJsonDocument>
#include <QJsonArray>
#include <QFile>
#include <QDir>
#include <QQmlApplicationEngine>
#include <QQmlComponent>
#include <QQmlContext>

#include <cstdlib>
#include <cstdio>
#include <filesystem>
#include <fstream>
#include <set>
#include <cstring>
#include <iostream>
#include <string>
#include <unistd.h>

#include "qml_search.hpp"
#include "qs_compat.hpp"
#include "qs_services.hpp"

namespace {

// The setup's steps, in SetupWizard.qml's order, each with whether this
// machine has what it is about.
bool has_wifi() {
    std::error_code ec;
    for (const auto& e : std::filesystem::directory_iterator("/sys/class/net", ec))
        if (e.path().filename().string().rfind("wl", 0) == 0) return true;
    return false;
}

bool has_fingerprint_reader() {
    FILE* p = popen("b1air-daemon fingerprint status 2>/dev/null", "r");
    if (!p) return false;
    std::string out;
    char buf[512];
    while (fgets(buf, sizeof buf, p)) out += buf;
    pclose(p);
    return out.find("\"available\":true") != std::string::npos;
}

// The setup's steps and the news, from settings/setup-steps.json beside the
// shell's QML — the one list SetupWizard.qml reads too.
struct Step { QString id; int version = 1; int baseline = 0; QString needs; };
struct Spec { QList<Step> steps; QStringList news; };

Spec load_spec() {
    Spec spec;
    QJsonObject root;
    for (const QString& dir : b1air::app::qml_dirs(QString())) {
        QFile f(dir + "/settings/setup-steps.json");
        if (!f.open(QIODevice::ReadOnly)) continue;
        root = QJsonDocument::fromJson(f.readAll()).object();
        if (!root.isEmpty()) break;
    }
    for (const QJsonValue& v : root.value("steps").toArray()) {
        const QJsonObject o = v.toObject();
        spec.steps.append({o.value("id").toString(), o.value("version").toInt(1),
                           o.value("baseline").toInt(0), o.value("needs").toString()});
    }
    for (const QJsonValue& v : root.value("news").toArray())
        spec.news << v.toObject().value("id").toString();
    return spec;
}

std::string marker_path() {
    const char* xdg = getenv("XDG_CONFIG_HOME");
    const char* home = getenv("HOME");
    const std::string conf = (xdg && *xdg) ? xdg : std::string(home ? home : "") + "/.config";
    return conf + "/b1air/setup-done";
}

// "keyboard" (from before steps had versions: version 1), "keyboard@2",
// "news@0.2.2".
struct Seen { std::map<std::string, int> steps; std::set<std::string> news; bool any = false; };
Seen read_seen() {
    Seen seen;
    std::ifstream in(marker_path());
    for (std::string line; std::getline(in, line);) {
        if (line.empty()) continue;
        seen.any = true;
        const auto at = line.find('@');
        const std::string id = line.substr(0, at);
        if (id == "news") { if (at != std::string::npos) seen.news.insert(line.substr(at + 1)); continue; }
        const int v = at == std::string::npos ? 1 : std::atoi(line.c_str() + at + 1);
        seen.steps[id] = std::max(seen.steps[id], v);
    }
    return seen;
}

bool has_hardware(const QString& needs) {
    if (needs == "wifi") return has_wifi();
    if (needs == "fingerprint") return has_fingerprint_reader();
    return true;
}

// Steps not seen in their current version, that this machine can use, then
// "news" when an update brought news this account has not seen. After an
// install (nothing seen yet) there is no news: everything is new.
std::string first_run_page() {
    const Spec spec = load_spec();
    const Seen seen = read_seen();
    std::string page;
    for (const Step& s : spec.steps) {
        const auto it = seen.steps.find(s.id.toStdString());
        if (it != seen.steps.end() && it->second >= s.version) continue;
        if (!has_hardware(s.needs)) continue;
        page += "." + s.id.toStdString();
    }
    if (seen.any)
        for (const QString& n : spec.news)
            if (!seen.news.count(n.toStdString())) { page += ".news"; break; }
    return page.empty() ? "" : "setup" + page;
}

// --setup-baseline (update-dotfiles.sh): an account that predates the setup
// set these things up by hand, so the steps it had count as seen at their
// baseline version. Only when there is no marker yet.
int write_baseline() {
    const std::string path = marker_path();
    if (std::filesystem::exists(path)) return 0;
    std::filesystem::create_directories(std::filesystem::path(path).parent_path());
    std::ofstream out(path);
    for (const Step& s : load_spec().steps)
        if (s.baseline > 0) out << s.id.toStdString() << "@" << s.baseline << "\n";
    return out ? 0 : 1;
}

} // namespace

int main(int argc, char* argv[]) {
    // The software renderer unless the environment names another. Nothing in
    // this window needs the GPU — no shader effects, no layers — and OpenGL
    // cost a large share of its memory: measured on this machine's Intel
    // GPU, 103 MB PSS with OpenGL against 75 MB without, same window.
    // The image viewer and the camera keep the GPU; they scale images and
    // video.
    setenv("QT_QUICK_BACKEND", "software", 0);
    // Ui/Design reads ~/.config/b1air/theme.json over XMLHttpRequest, which
    // Qt 6 refuses on file:// unless this is set. The other apps set it
    // themselves; this one relied on b1air-session, so started from anywhere
    // else it drew the built-in palette instead of the chosen theme.
    setenv("QML_XHR_ALLOW_FILE_READ", "1", 0);

    // Prefer the panel already on screen.
    //
    // With the desktop up, the settings belong inside it: same window manager
    // placement, same keyboard handling, one process. This binary exists for
    // when there is no shell to put them in — so it looks first, and only hosts
    // the panel itself when nothing else will. `--standalone` forces its own
    // window; `--shell` forces the other way.
    const char* page = "";
    bool forceStandalone = false;
    bool forceShell = false;
    bool firstRun = false;
    bool printOnly = false;
    for (int i = 1; i < argc; ++i) {
        if (std::strcmp(argv[i], "--standalone") == 0) forceStandalone = true;
        else if (std::strcmp(argv[i], "--shell") == 0) forceShell = true;
        else if (std::strcmp(argv[i], "--first-run") == 0) firstRun = true;
        else if (std::strcmp(argv[i], "--print") == 0) printOnly = true;
        else if (std::strcmp(argv[i], "--setup-baseline") == 0) return write_baseline();
        else if (argv[i][0] != '-') page = argv[i];
    }

    // --first-run (autostart.conf): the setup's steps that are new to this
    // account, and an update's news (first_run_page). None: nothing opens.
    // With --print, the page is printed instead of opened.
    std::string setupPage;
    if (firstRun) {
        setupPage = first_run_page();
        if (printOnly) { std::cout << setupPage << "\n"; return 0; }
        if (setupPage.empty()) return 0;
        page = setupPage.c_str();
    }

    const bool shellRunning = b1air::proc::running("quickshell");
    if (forceShell || (shellRunning && !forceStandalone)) {
        if (std::strlen(page) > 0)
            execlp("b1air-shell", "b1air-shell", "open", "settings", page, (char*)nullptr);
        else
            execlp("b1air-shell", "b1air-shell", "toggle", "settings", (char*)nullptr);
        // execlp only returns on failure, and a failure here is not fatal:
        // hosting the panel is exactly the fallback this program is for.
        std::cerr << "[b1air-settings] b1air-shell would not run; opening a window instead\n";
    }

    QGuiApplication app(argc, argv);
    app.setApplicationName("b1air-settings");
    app.setDesktopFileName("b1air-settings");

    qscompat::registerCoreTypes();
    qscompat::registerServiceTypes();

    QQmlApplicationEngine engine;
    b1air::app::add_import_paths(engine, "settings");

    // Added last so it is searched first. This is what keeps `import Quickshell`
    // away from the real module on the default QML path — which cannot simply be
    // removed from the search, because QtQuick lives there too.
    engine.addImportPath(qscompat::moduleDir());

    if (std::strlen(page) > 0)
        qputenv("INITIAL_SETTINGS_PAGE", page);

    const QString qmlPath = b1air::app::find_window_qml("SettingsWindow.qml", "settings");
    if (qmlPath.isEmpty()) {
        std::cerr << "[b1air-settings] Error: SettingsWindow.qml not found\n";
        return 1;
    }

    QQmlComponent component(&engine, QUrl::fromLocalFile(qmlPath));
    QObject* root = component.isError() ? nullptr : component.create();
    if (!root) {
        std::cerr << "[b1air-settings] Error: failed to load " << qmlPath.toStdString() << "\n";
        for (const QQmlError& e : component.errors())
            std::cerr << "    " << e.toString().toStdString() << "\n";
        return 1;
    }

    return app.exec();
}
