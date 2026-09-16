// =============================================================================
// b1air-text — Native C++20 / Qt6 Minimal Text & Config Editor
// Zero JSON • Direct C++ Models • Wayland Native
// =============================================================================

#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QDir>
#include <QFile>
#include <iostream>
#include "qml_search.hpp"
#include "backend.hpp"

int main(int argc, char* argv[]) {
    // The software renderer unless the environment names another. Nothing in
    // this window needs the GPU — no shader effects, no layers — and OpenGL
    // cost a large share of its memory: measured on this machine's Intel
    // GPU, 49 MB PSS with OpenGL against 31 MB without, same window.
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
    app.setApplicationName("b1air-text");
    app.setApplicationDisplayName("Text Editor");
    app.setDesktopFileName("b1air-text");
    app.setOrganizationName("bla1r1");

    QQmlApplicationEngine engine;
    b1air::app::add_import_paths(engine, "text");

    QObject::connect(&engine, &QQmlApplicationEngine::warnings, [](const QList<QQmlError>& warnings) {
        for (const auto& w : warnings) {
            std::cerr << "[b1air-text QML] " << w.toString().toStdString() << "\n";
        }
    });

    b1air::TextBackend backend;
    if (argc > 1) {
        QString fileArg = QString::fromUtf8(argv[1]);
        backend.openFile(fileArg);
    }
    engine.rootContext()->setContextProperty("TextBackend", &backend);

    QString qmlPath = b1air::app::find_window_qml("TextWindow.qml", "text");

    if (qmlPath.isEmpty()) {
        std::cerr << "[b1air-text] Error: TextWindow.qml not found!\n";
        return 1;
    }

    engine.load(QUrl::fromLocalFile(qmlPath));
    if (engine.rootObjects().isEmpty()) {
        std::cerr << "[b1air-text] Error: Failed to load QML root object\n";
        return 1;
    }

    return app.exec();
}
