#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QDir>
#include <QFile>
#include <iostream>
#include "qml_search.hpp"
#include "view_backend.hpp"

int main(int argc, char* argv[]) {
    // Force Wayland, high performance rendering & basic render loop (0% idle CPU)
    setenv("QT_QPA_PLATFORM", "wayland;xcb", 1);
    // The software renderer unless the environment names another, like the
    // rest of the suite. The image is decoded at screen size now (see
    // ViewWindow.qml), so scaling and rotating it is light work for the CPU,
    // and OpenGL was half the window's memory: 149 MB against 73 MB with one
    // 4K wallpaper open (measured under llvmpipe; a real GPU's driver costs
    // less, but not nothing). QT_QUICK_BACKEND=opengl brings it back.
    setenv("QT_QUICK_BACKEND", "software", 0);
    setenv("QSG_RHI_BACKEND", "opengl", 0);
    setenv("QSG_RENDER_LOOP", "basic", 1);
    setenv("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1", 1);

    // Ui/Design loads ~/.config/b1air/theme.json over XMLHttpRequest;

    // Qt 6 blocks file:// reads for it unless this is set.

    qputenv("QML_XHR_ALLOW_FILE_READ", "1");


    QGuiApplication app(argc, argv);
    app.setApplicationName("b1air-view");
    app.setOrganizationName("b1air");

    ViewBackend viewBackend;

    // Check CLI argument for initial file
    QString initialFile = "";
    if (argc > 1) {
        initialFile = b1air::app::path_arg(QString::fromUtf8(argv[1]));
    } else {
        QStringList candidates = {
            QDir::homePath() + "/Pictures",
            QDir::homePath() + "/Pictures/Wallpapers",
            QDir::homePath() + "/DotsFiles/wallpapers",
            QDir::currentPath()
        };
        for (const auto& c : candidates) {
            QDir d(c);
            if (d.exists()) {
                QFileInfoList list = d.entryInfoList(QStringList() << "*.png" << "*.jpg" << "*.jpeg" << "*.webp", QDir::Files);
                if (!list.isEmpty()) {
                    initialFile = list[0].absoluteFilePath();
                    break;
                }
            }
        }
    }

    if (!initialFile.isEmpty()) {
        viewBackend.openFile(initialFile);
    }

    QQmlApplicationEngine engine;
    QObject::connect(&engine, &QQmlApplicationEngine::warnings, [](const QList<QQmlError>& warnings) {
        for (const auto& w : warnings) {
            std::cerr << "[b1air-view QML Warning] " << w.toString().toStdString() << "\n";
        }
    });

    engine.rootContext()->setContextProperty("ViewBackend", &viewBackend);

    b1air::app::add_import_paths(engine, "view");

    QString qmlPath = b1air::app::find_window_qml("ViewWindow.qml", "view");
    if (qmlPath.isEmpty()) {
        std::cerr << "[b1air-view] Error: ViewWindow.qml not found!\n";
        return 1;
    }

    engine.load(QUrl::fromLocalFile(qmlPath));
    if (engine.rootObjects().isEmpty()) {
        std::cerr << "[b1air-view] Error: Failed to load QML root component\n";
        return 1;
    }

    return app.exec();
}
