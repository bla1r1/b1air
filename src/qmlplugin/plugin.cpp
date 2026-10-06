// Classic extension plugin, deliberately not qt_add_qml_module's default.
//
// That macro produces a module in the "linked into the consuming executable"
// shape — the same shape that stops quickshell from handing its own types to
// other programs. The shell's QML is hosted by quickshell, so this module has
// to be loadable from disk by an engine we do not build.

#include <QQmlEngine>
#include <QQmlExtensionPlugin>
#include <qqml.h>

#include "b1airdaemon.hpp"
#include "sway_client.hpp"
#include "sys_util.hpp"
#include "thumbs.hpp"

class B1airDaemonPlugin : public QQmlExtensionPlugin {
    Q_OBJECT
    Q_PLUGIN_METADATA(IID QQmlExtensionInterface_iid)

public:
    void registerTypes(const char* uri) override {
        Q_ASSERT(uri == QLatin1String("B1air.Daemon"));
        qmlRegisterSingletonType<B1airDaemon>(
            uri, 1, 0, "Daemon",
            [](QQmlEngine* engine, QJSEngine*) -> QObject* {
                auto* d = new B1airDaemon();
                // trimMemory() needs the engine that hosts the shell.
                d->setEngine(engine);
                return d;
            });
        // sway's IPC, spoken directly (sway_client.hpp).
        qmlRegisterSingletonType<SwayClient>(
            uri, 1, 0, "Sway",
            [](QQmlEngine* engine, QJSEngine*) -> QObject* {
                auto* s = new SwayClient();
                s->setEngine(engine);
                return s;
            });
        // Files and PATH, in place of `bash -c` (sys_util.hpp).
        qmlRegisterSingletonType<SysUtil>(
            uri, 1, 0, "Sys",
            [](QQmlEngine*, QJSEngine*) -> QObject* { return new SysUtil(); });
    }

    // image://thumb/<path>, cached thumbnails (common/thumbs.hpp).
    void initializeEngine(QQmlEngine* engine, const char*) override {
        if (!engine->imageProvider(QStringLiteral("thumb")))
            engine->addImageProvider(QStringLiteral("thumb"), new b1air::ThumbProvider);
    }
};

#include "plugin.moc"
