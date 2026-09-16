// =============================================================================
// b1air-camera — the desktop's camera: preview, stills and video
//
// QtMultimedia does the capture; everything visible is CameraWindow.qml, found
// the same way every other app window is (qml_search.hpp).
// =============================================================================

#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QStandardPaths>
#include <QDir>
#include <iostream>
#include "qml_search.hpp"

int main(int argc, char* argv[]) {
    qputenv("QT_QPA_PLATFORM", "wayland;xcb");
    qputenv("QT_QUICK_CONTROLS_STYLE", "Basic");
    // Ui/Design loads ~/.config/b1air/theme.json over XMLHttpRequest;
    // Qt 6 blocks file:// reads for it unless this is set.
    qputenv("QML_XHR_ALLOW_FILE_READ", "1");
    qputenv("QSG_RENDER_LOOP", "basic");

    QGuiApplication app(argc, argv);
    app.setApplicationName("b1air-camera");
    app.setApplicationDisplayName("Camera");
    app.setDesktopFileName("b1air-camera");
    app.setOrganizationName("bla1r1");

    // Where the shots go. XDG's Pictures, with our own folder inside it, made
    // once so the first shutter press cannot fail on a missing directory.
    QString pictures = QStandardPaths::writableLocation(QStandardPaths::PicturesLocation);
    if (pictures.isEmpty())
        pictures = QDir::homePath() + "/Pictures";
    const QString shots = pictures + "/Camera";
    QDir().mkpath(shots);

    QQmlApplicationEngine engine;
    b1air::app::add_import_paths(engine, "camera");
    engine.rootContext()->setContextProperty("CameraDir", shots);

    QObject::connect(&engine, &QQmlApplicationEngine::warnings, [](const QList<QQmlError>& warnings) {
        for (const auto& w : warnings)
            std::cerr << "[b1air-camera QML] " << w.toString().toStdString() << "\n";
    });

    const QString qmlPath = b1air::app::find_window_qml("CameraWindow.qml", "camera");
    if (qmlPath.isEmpty()) {
        std::cerr << "[b1air-camera] Error: CameraWindow.qml not found!\n";
        return 1;
    }
    engine.load(QUrl::fromLocalFile(qmlPath));
    if (engine.rootObjects().isEmpty()) {
        std::cerr << "[b1air-camera] Error: Failed to load CameraWindow.qml\n";
        return 1;
    }
    return app.exec();
}
