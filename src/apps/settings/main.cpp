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

std::string first_run_page() {
    const char* xdg = getenv("XDG_CONFIG_HOME");
    const char* home = getenv("HOME");
    const std::string conf = (xdg && *xdg) ? xdg : std::string(home ? home : "") + "/.config";
    std::set<std::string> seen;
    std::ifstream in(conf + "/b1air/setup-done");
    for (std::string line; std::getline(in, line);)
        if (!line.empty()) seen.insert(line);

    const std::pair<const char*, bool (*)()> steps[] = {
        {"keyboard", nullptr}, {"network", has_wifi}, {"theme", nullptr},
        {"wallpaper", nullptr}, {"user", nullptr}, {"fingerprint", has_fingerprint_reader}};
    std::string page;
    for (const auto& [id, available] : steps) {
        if (seen.count(id)) continue;
        if (available && !available()) continue;
        page += std::string(".") + id;
    }
    return page.empty() ? "" : "setup" + page;
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
    for (int i = 1; i < argc; ++i) {
        if (std::strcmp(argv[i], "--standalone") == 0) forceStandalone = true;
        else if (std::strcmp(argv[i], "--shell") == 0) forceShell = true;
        else if (std::strcmp(argv[i], "--first-run") == 0) firstRun = true;
        else if (argv[i][0] != '-') page = argv[i];
    }

    // --first-run (autostart.conf): the setup's steps that are new to this
    // account — not in ~/.config/b1air/setup-done, which SetupWizard.qml
    // writes — and that this machine can use. None: nothing opens.
    std::string setupPage;
    if (firstRun) {
        setupPage = first_run_page();
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
