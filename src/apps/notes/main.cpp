#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QDir>
#include <QFile>
#include <iostream>
#include "qml_search.hpp"
#include "notes_backend.hpp"

int main(int argc, char* argv[]) {
    // The software renderer unless the environment names another. Nothing in
    // this window needs the GPU — no shader effects, no layers — and OpenGL
    // cost a large share of its memory: measured on this machine's Intel
    // GPU, 48 MB PSS with OpenGL against 29 MB without, same window.
    // The image viewer and the camera keep the GPU; they scale images and
    // video.
    setenv("QT_QUICK_BACKEND", "software", 0);

    // Force Wayland, high performance rendering & basic render loop (0% idle CPU)
    setenv("QT_QPA_PLATFORM", "wayland;xcb", 1);
    setenv("QSG_RHI_BACKEND", "opengl", 1);
    setenv("QSG_RENDER_LOOP", "basic", 1);
    setenv("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1", 1);

    // Ui/Design loads ~/.config/b1air/theme.json over XMLHttpRequest;

    // Qt 6 blocks file:// reads for it unless this is set.

    qputenv("QML_XHR_ALLOW_FILE_READ", "1");


    QGuiApplication app(argc, argv);
    app.setApplicationName("b1air-notes");
    app.setOrganizationName("b1air");

    NotesBackend notesBackend;

    QQmlApplicationEngine engine;
    QObject::connect(&engine, &QQmlApplicationEngine::warnings, [](const QList<QQmlError>& warnings) {
        for (const auto& w : warnings) {
            std::cerr << "[b1air-notes QML Warning] " << w.toString().toStdString() << "\n";
        }
    });

    engine.rootContext()->setContextProperty("NotesBackend", &notesBackend);

    b1air::app::add_import_paths(engine, "notes");

    QString qmlPath = b1air::app::find_window_qml("NotesWindow.qml", "notes");
    if (qmlPath.isEmpty()) {
        std::cerr << "[b1air-notes] Error: NotesWindow.qml not found!\n";
        return 1;
    }

    engine.load(QUrl::fromLocalFile(qmlPath));
    if (engine.rootObjects().isEmpty()) {
        std::cerr << "[b1air-notes] Error: Failed to load QML root component\n";
        return 1;
    }

    return app.exec();
}
