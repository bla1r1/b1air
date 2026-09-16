// =============================================================================
// b1air-files — Native C++20 / Qt6 File Manager & Gallery Application
// =============================================================================

#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QUrl>
#include <iostream>
#include "qml_search.hpp"
#include "backend.hpp"

int main(int argc, char* argv[]) {
    // The software renderer unless the environment names another. Nothing in
    // this window needs the GPU — no shader effects, no layers — and OpenGL
    // cost a large share of its memory: measured on this machine's Intel
    // GPU, 53 MB PSS with OpenGL against 34 MB without, same window.
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
    app.setApplicationName("b1air-files");
    app.setApplicationDisplayName("Files");
    app.setDesktopFileName("b1air-files");
    app.setOrganizationName("bla1r1");

    // Before the engine, so it outlives it. Declared after, it was destroyed
    // first on exit, and the engine's teardown then re-evaluated every binding
    // on FilesBackend against null — eight TypeErrors each time the window
    // closed.
    b1air::FileManagerBackend backend;

    QQmlApplicationEngine engine;
    b1air::app::add_import_paths(engine, "files");

    QObject::connect(&engine, &QQmlApplicationEngine::warnings, [](const QList<QQmlError>& warnings) {
        for (const auto& w : warnings) {
            std::cerr << "[b1air-files QML] " << w.toString().toStdString() << "\n";
        }
    });

    // `--pick-folder <file> [start]`: another application wants a directory
    // chosen. The chooser bar appears, and the path is written to <file> when
    // it is confirmed — see FileManagerBackend::confirmPick(). Parsed before
    // the positional argument below, which is the ordinary "open here" case.
    QStringList args;
    for (int i = 1; i < argc; ++i) args << QString::fromUtf8(argv[i]);
    const int pickAt = args.indexOf(QStringLiteral("--pick-folder"));
    if (pickAt >= 0) {
        if (pickAt + 1 >= args.size()) {
            std::cerr << "[b1air-files] --pick-folder needs a file to write the result to\n";
            return 2;
        }
        backend.setPickResultPath(args.at(pickAt + 1));
        app.setApplicationDisplayName("Choose a folder");
        if (pickAt + 2 < args.size()) {
            const QFileInfo start(args.at(pickAt + 2));
            if (start.isDir()) backend.setCurrentPath(start.absoluteFilePath());
        }
        args.clear();   // nothing else on the line is a path to open
        argc = 1;
    }

    if (argc > 1) {
        // Desktop entries use %U, so callers (Firefox "Open Containing
        // Folder", xdg-open, etc.) pass a file:// URI, not a bare path.
        QUrl url(QString::fromUtf8(argv[1]));
        QString targetPath = url.isLocalFile() ? url.toLocalFile() : url.toString();

        QFileInfo fi(targetPath);
        if (fi.isDir()) {
            backend.setCurrentPath(fi.absoluteFilePath());
        } else if (fi.exists()) {
            // A specific file (e.g. a just-downloaded file) was passed:
            // land in its containing folder instead of doing nothing.
            backend.setCurrentPath(fi.absolutePath());
        }
    }
    engine.rootContext()->setContextProperty("FilesBackend", &backend);

    QString qmlPath = b1air::app::find_window_qml("FilesWindow.qml", "files");

    if (qmlPath.isEmpty()) {
        std::cerr << "[b1air-files] Error: FilesWindow.qml not found!\n";
        return 1;
    }

    engine.load(QUrl::fromLocalFile(qmlPath));
    if (engine.rootObjects().isEmpty()) {
        std::cerr << "[b1air-files] Error: Failed to load FilesWindow.qml\n";
        return -1;
    }

    return app.exec();
}
