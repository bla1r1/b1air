// =============================================================================
// b1air-monitor — Native C++20 / Qt6 Activity Monitor & Task Manager
// Zero JSON • Direct C++ Models • Wayland Native
// =============================================================================

#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QDir>
#include <QFile>
#include <iostream>
#include "qml_search.hpp"
#include "render_backend.hpp"
#include "backend.hpp"

int main(int argc, char* argv[]) {
    // The GPU where there is one (render_backend.hpp).
    b1air::app::choose_renderer();

    qputenv("QT_QPA_PLATFORM", "wayland;xcb");
    qputenv("QT_QUICK_CONTROLS_STYLE", "Basic");
    // Ui/Design loads ~/.config/b1air/theme.json over XMLHttpRequest;
    // Qt 6 blocks file:// reads for it unless this is set.
    qputenv("QML_XHR_ALLOW_FILE_READ", "1");
    qputenv("QSG_RENDER_LOOP", "basic");
    qputenv("QML_DISABLE_DISK_CACHE", "0");

    // Before the application: Qt registers the app ID with the desktop
    // portal as it starts, and one set afterwards was refused as a second
    // registration (see b1air-term).
    QGuiApplication::setDesktopFileName("b1air-monitor");
    QGuiApplication app(argc, argv);
    app.setApplicationName("b1air-monitor");
    app.setApplicationDisplayName("System Monitor");
    app.setOrganizationName("bla1r1");

    // Before the engine, so it outlives it: locals go in reverse order, and
    // made after it the backend went first at exit, leaving the window's
    // bindings to read it as null on the way out.
    b1air::MonitorBackend backend;

    QQmlApplicationEngine engine;
    b1air::app::add_import_paths(engine, "monitor");

    QObject::connect(&engine, &QQmlApplicationEngine::warnings, [](const QList<QQmlError>& warnings) {
        for (const auto& w : warnings) {
            std::cerr << "[b1air-monitor QML] " << w.toString().toStdString() << "\n";
        }
    });

    engine.rootContext()->setContextProperty("MonitorBackend", &backend);

    QString qmlPath = b1air::app::find_window_qml("MonitorWindow.qml", "monitor");

    if (qmlPath.isEmpty()) {
        std::cerr << "[b1air-monitor] Error: MonitorWindow.qml not found!\n";
        return 1;
    }

    engine.load(QUrl::fromLocalFile(qmlPath));
    if (engine.rootObjects().isEmpty()) {
        std::cerr << "[b1air-monitor] Error: Failed to load QML root object\n";
        return 1;
    }

    return app.exec();
}
