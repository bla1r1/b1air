// =============================================================================
// b1air-text — Native C++20 / Qt6 Minimal Text & Config Editor
// Zero JSON • Direct C++ Models • Wayland Native
// =============================================================================

#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QDir>
#include <QFile>
#include <QLocalServer>
#include <QLocalSocket>
#include <iostream>
#include <memory>
#include <unistd.h>
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
    QGuiApplication::setDesktopFileName("b1air-text");
    QGuiApplication app(argc, argv);
    app.setApplicationName("b1air-text");
    app.setApplicationDisplayName("Text Editor");
    app.setOrganizationName("bla1r1");

    // The files named on the command line, as absolute paths.
    QStringList files;
    for (int i = 1; i < argc; ++i) {
        const QString arg = QString::fromUtf8(argv[i]);
        if (!arg.startsWith('-')) files << b1air::app::path_arg(arg);
    }

    // One window, with a tab per file: a second `b1air-text` (a file opened
    // from Files, from the terminal) hands its files to the window already
    // open and goes. It used to be a window each, and the tabs and the
    // session would have been split between them.
    const QString socketName = QStringLiteral("b1air-text-") + QString::number(getuid());
    {
        QLocalSocket other;
        other.connectToServer(socketName);
        if (other.waitForConnected(500)) {
            other.write((files.join('\n') + '\n').toUtf8());
            other.waitForBytesWritten(1000);
            other.disconnectFromServer();
            return 0;
        }
    }

    // Before the engine, so it outlives it: locals go in reverse order, and
    // with the backend made second it went first at exit — every binding on
    // TextBackend in the still-living window read it as null on the way out
    // (TypeError … of null, a dozen a quit).
    b1air::TextBackend backend;
    // The tabs left open last time, unsaved changes included; then these.
    backend.restoreSession();
    for (const QString& f : files) backend.openFile(f);

    QQmlApplicationEngine engine;
    b1air::app::add_import_paths(engine, "text");

    QObject::connect(&engine, &QQmlApplicationEngine::warnings, [](const QList<QQmlError>& warnings) {
        for (const auto& w : warnings) {
            std::cerr << "[b1air-text QML] " << w.toString().toStdString() << "\n";
        }
    });

    QLocalServer server;
    QLocalServer::removeServer(socketName);   // one left by a crash
    server.setSocketOptions(QLocalServer::UserAccessOption);
    if (server.listen(socketName)) {
        QObject::connect(&server, &QLocalServer::newConnection, &server, [&server, &backend] {
            while (QLocalSocket* s = server.nextPendingConnection()) {
                auto buffer = std::make_shared<QByteArray>();
                QObject::connect(s, &QLocalSocket::readyRead, s, [s, buffer] { buffer->append(s->readAll()); });
                QObject::connect(s, &QLocalSocket::disconnected, s, [s, buffer, &backend] {
                    buffer->append(s->readAll());
                    for (const QString& f : QString::fromUtf8(*buffer).split('\n', Qt::SkipEmptyParts))
                        backend.openFile(f);
                    emit backend.raiseRequested();
                    s->deleteLater();
                });
            }
        });
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
