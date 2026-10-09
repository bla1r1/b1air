#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickWindow>
#include <QDir>
#include <QFile>
#include <csignal>
#include <iostream>
#include "qml_search.hpp"
#include "view_backend.hpp"
#include "thumbs.hpp"

int main(int argc, char* argv[]) {
    // Started by a launcher that has since gone (gio open from Files), the
    // window's stderr can be a pipe nobody reads any more: a log line from
    // ffmpeg would kill it. Such a write fails quietly instead.
    signal(SIGPIPE, SIG_IGN);
    // Force Wayland
    setenv("QT_QPA_PLATFORM", "wayland;xcb", 1);
    // Which renderer is chosen below, once the file and its folder are known.
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

    // Pictures on the CPU: the image is decoded at screen size (see
    // ViewWindow.qml), so scaling and rotating it is light work, and OpenGL was
    // half the window's memory: 149 MB against 73 MB with one 4K wallpaper open
    // (measured under llvmpipe). Films on the GPU, whatever the session says:
    // the session exports QT_QUICK_BACKEND=software for every app, and Qt's
    // software renderer draws no video at all (Qt 6.11) — the film played,
    // its sound and its clock ran, over a black rectangle. OpenGL draws the
    // frames as textures (YUV turned to RGB in a shader, not on the CPU), and
    // takes the frames VA-API decodes on the GPU as they are. Not Vulkan:
    // Qt's video node crashed in it here (Intel UHD 620, Mesa).
    // The renderer cannot change once the window exists, so a folder with any
    // film in it — one the arrows may reach — gets the GPU from the start.
    if (viewBackend.folderHasVideo()) {
        if (qEnvironmentVariable("QT_QUICK_BACKEND") == QLatin1String("software")) unsetenv("QT_QUICK_BACKEND");
        setenv("QSG_RHI_BACKEND", "opengl", 1);
        // The threaded loop: frames are drawn off the GUI thread, so a busy
        // moment in QML does not drop them.
        unsetenv("QSG_RENDER_LOOP");
    } else {
        if (!qEnvironmentVariableIsSet("QT_QUICK_BACKEND")) QQuickWindow::setSceneGraphBackend(QStringLiteral("software"));
        setenv("QSG_RENDER_LOOP", "basic", 1);   // 0% CPU when idle
    }

    QQmlApplicationEngine engine;
    QObject::connect(&engine, &QQmlApplicationEngine::warnings, [](const QList<QQmlError>& warnings) {
        for (const auto& w : warnings) {
            std::cerr << "[b1air-view QML Warning] " << w.toString().toStdString() << "\n";
        }
    });

    engine.rootContext()->setContextProperty("ViewBackend", &viewBackend);
    // A frame of each film for the strip (common/thumbs, as Files has them).
    if (!engine.imageProvider("thumb")) engine.addImageProvider("thumb", new b1air::ThumbProvider);

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
