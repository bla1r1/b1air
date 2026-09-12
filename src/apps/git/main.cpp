#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QDir>
#include <QFile>
#include <iostream>
#include "../qml_search.hpp"
#include "git_backend.hpp"

int main(int argc, char* argv[]) {
    // Force Wayland, high performance rendering & basic render loop (0% idle CPU)
    setenv("QT_QPA_PLATFORM", "wayland;xcb", 1);
    // The software renderer, unless the environment asks for another. This
    // window is text, lines and flat rectangles — nothing the GPU draws better
    // — and bringing up OpenGL cost about 20 MB of the process's memory for the
    // driver and its buffers: measured on this machine's Intel GPU, 54 MB PSS
    // with OpenGL against 34 MB without, same repository, same window.
    setenv("QT_QUICK_BACKEND", "software", 0);
    setenv("QSG_RHI_BACKEND", "opengl", 1);
    setenv("QSG_RENDER_LOOP", "basic", 1);
    setenv("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1", 1);

    // Ui/Design loads ~/.config/b1air/theme.json over XMLHttpRequest;

    // Qt 6 blocks file:// reads for it unless this is set.

    qputenv("QML_XHR_ALLOW_FILE_READ", "1");


    QGuiApplication app(argc, argv);
    app.setApplicationName("b1air-git");
    app.setOrganizationName("b1air");

    GitBackend gitBackend;

    // Launched from the menu there is no argument, and the repo path stayed
    // empty — runGit() then early-returns for every call, so the whole window
    // came up blank and no button did anything.
    // Without an argument, startupRepo(): the working directory when that is a
    // repository, otherwise the last one open. This line used to open the
    // working directory unconditionally, which from the launcher is $HOME —
    // so the last repository was never restored.
    gitBackend.openRepo(argc > 1 ? QString::fromUtf8(argv[1]) : gitBackend.startupRepo());

    QQmlApplicationEngine engine;
    QObject::connect(&engine, &QQmlApplicationEngine::warnings, [](const QList<QQmlError>& warnings) {
        for (const auto& w : warnings) {
            std::cerr << "[b1air-git QML Warning] " << w.toString().toStdString() << "\n";
        }
    });

    engine.rootContext()->setContextProperty("GitBackend", &gitBackend);

    b1air::app::add_import_paths(engine, "git");

    QString qmlPath = b1air::app::find_window_qml("GitWindow.qml", "git");
    if (qmlPath.isEmpty()) {
        std::cerr << "[b1air-git] Error: GitWindow.qml not found!\n";
        return 1;
    }

    engine.load(QUrl::fromLocalFile(qmlPath));
    if (engine.rootObjects().isEmpty()) {
        std::cerr << "[b1air-git] Error: Failed to load QML root component\n";
        return 1;
    }

    return app.exec();
}
