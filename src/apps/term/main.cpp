// =============================================================================
// b1air-term — Native C++20 / Qt6 Desktop Terminal Emulator
// Zero JSON • libvterm • Wayland Native
// =============================================================================

#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QDir>
#include <QRegularExpression>
#include <QFile>
#include <iostream>
#include "qml_search.hpp"
#include "terminal_item.hpp"

int main(int argc, char* argv[]) {
    // The software renderer unless the environment names another. Nothing in
    // this window needs the GPU — no shader effects, no layers — and OpenGL
    // cost a large share of its memory: measured on this machine's Intel
    // GPU, 47 MB PSS with OpenGL against 33 MB without, same window.
    // It draws with QQuickPaintedItem, which paints into an image on the
    // CPU either way; OpenGL only added a texture copy of that image, and
    // 300,000 lines of output cost the same CPU time in both.
    // The image viewer and the camera keep the GPU; they scale images and
    // video.
    setenv("QT_QUICK_BACKEND", "software", 0);

    qputenv("QT_QPA_PLATFORM", "wayland;xcb");
    qputenv("QT_QUICK_CONTROLS_STYLE", "Basic");
    // Ui/Design loads ~/.config/b1air/theme.json over XMLHttpRequest;
    // Qt 6 blocks file:// reads for it unless this is set.
    qputenv("QML_XHR_ALLOW_FILE_READ", "1");
    qputenv("QSG_RENDER_LOOP", "basic");
    qputenv("QML_DISABLE_DISK_CACHE", "0");

    QGuiApplication app(argc, argv);
    app.setApplicationName("b1air-term");
    app.setApplicationDisplayName("Terminal");
    // --dropdown: the same terminal under its own app_id, which the sway
    // window rule turns into the panel that slides down from the top.
    // --hold: the window stays when the command given with -e ends, with its
    // exit code on screen, until a key is pressed — for a command whose
    // output is the point (the updater), instead of a shell's `read`.
    bool dropdown = false, hold = false;
    for (int i = 1; i < argc; ++i) {
        const QString a = QString::fromUtf8(argv[i]);
        if (a == QLatin1String("-e")) break;
        if (a == QLatin1String("--dropdown")) dropdown = true;
        if (a == QLatin1String("--hold")) hold = true;
    }
    app.setDesktopFileName(dropdown ? "b1air-dropdown" : "b1air-term");
    app.setOrganizationName("bla1r1");

    qmlRegisterType<b1air::TerminalItem>("B1Air.Term", 1, 0, "TerminalView");

    QQmlApplicationEngine engine;
    b1air::app::add_import_paths(engine, "term");

    QString initialCommand = "";
    QString initialDir = "";

    for (int i = 1; i < argc; ++i) {
        const QString raw = QString::fromUtf8(argv[i]);
        const QString arg = raw == "-e" ? raw : b1air::app::path_arg(raw);
        if (raw == QLatin1String("--dropdown") || raw == QLatin1String("--hold")) {
            continue;
        } else if (arg == "-e" && i + 1 < argc) {
            QStringList cmdParts;
            // Each argument quoted for the shell that runs it: joined bare,
            // `-e sh -c "echo a; read"` reached the shell as
            // `sh -c echo a; read`. Single quotes read the same in sh, bash,
            // zsh and fish for everything but a backslash.
            static const QRegularExpression plain(QStringLiteral("^[A-Za-z0-9_@%+=:,./-]+$"));
            for (int j = i + 1; j < argc; ++j) {
                QString part = QString::fromUtf8(argv[j]);
                if (!plain.match(part).hasMatch())
                    part = "'" + part.replace("'", "'\"'\"'") + "'";
                cmdParts << part;
            }
            initialCommand = cmdParts.join(" ");
            break;
        } else if (QDir(arg).exists()) {
            initialDir = QDir(arg).canonicalPath();
        }
    }

    engine.rootContext()->setContextProperty("InitialCommand", initialCommand);
    engine.rootContext()->setContextProperty("InitialDir", initialDir);
    engine.rootContext()->setContextProperty("HoldOnExit", hold && !initialCommand.isEmpty());

    QObject::connect(&engine, &QQmlApplicationEngine::warnings, [](const QList<QQmlError>& warnings) {
        for (const auto& w : warnings) {
            std::cerr << "[b1air-term QML] " << w.toString().toStdString() << "\n";
        }
    });

    QString qmlPath = b1air::app::find_window_qml("TermWindow.qml", "term");

    if (qmlPath.isEmpty()) {
        std::cerr << "[b1air-term] Error: TermWindow.qml not found!\n";
        return 1;
    }

    engine.load(QUrl::fromLocalFile(qmlPath));
    if (engine.rootObjects().isEmpty()) {
        std::cerr << "[b1air-term] Error: Failed to load TermWindow.qml\n";
        return 1;
    }

    return app.exec();
}
