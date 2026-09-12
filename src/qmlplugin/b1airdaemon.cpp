#include "b1airdaemon.hpp"
#include <QFile>
#include <malloc.h>
#include <QGuiApplication>
#include <QQmlEngine>
#include <QQuickWindow>
#include <cmath>
#include <QUrl>
#include <QImage>
#include <QColor>

#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusMetaType>
#include <QDBusPendingCall>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>
#include <QDir>
#include <QFileInfo>
#include <QProcess>
#include <QStandardPaths>

namespace {
constexpr auto kDaemonService = "org.b1air.Daemon";
constexpr auto kDaemonPath    = "/org/b1air/Daemon";
constexpr auto kDaemonIface   = "org.b1air.Daemon";

constexpr auto kShellService  = "org.b1air.Shell";
constexpr auto kShellPath     = "/org/b1air/Shell";
constexpr auto kShellIface    = "org.b1air.Shell";
}

B1airDaemon::B1airDaemon(QObject* parent)
    : QObject(parent), m_bus(QDBusConnection::sessionBus()) {

    // Needed once, for EqSetAll's "ai" argument: Qt does not marshal a plain
    // QVariantList as a typed int array without this.
    qDBusRegisterMetaType<QList<int>>();

    m_bus.connect(kDaemonService, kDaemonPath, kDaemonIface, "VolumeChanged",
                  this, SIGNAL(volumeChanged(int, bool)));
    m_bus.connect(kDaemonService, kDaemonPath, kDaemonIface, "BrightnessChanged",
                  this, SIGNAL(brightnessChanged(int)));
    m_bus.connect(kDaemonService, kDaemonPath, kDaemonIface, "WallpaperChanged",
                  this, SIGNAL(wallpaperChanged(QString)));
    m_bus.connect(kShellService, kShellPath, kShellIface, "PanelStateChanged",
                  this, SIGNAL(panelStateChanged(QString, bool)));
    m_bus.connect(kShellService, kShellPath, kShellIface, "PanelRequested",
                  this, SIGNAL(panelRequested(QString, QString, QString)));
    m_bus.connect(kDaemonService, kDaemonPath, kDaemonIface, "CameraInUseChanged",
                  this, SLOT(onCameraInUseChanged(bool)));

    // The daemon may start after the shell, or be restarted under it.
    if (auto* iface = m_bus.interface()) {
        connect(iface, &QDBusConnectionInterface::NameOwnerChanged,
                this, &B1airDaemon::onNameOwnerChanged);
    }
    refreshAvailability();
}

void B1airDaemon::onNameOwnerChanged(const QString& name, const QString&, const QString&) {
    if (name == QLatin1String(kDaemonService)) refreshAvailability();
}

void B1airDaemon::refreshAvailability() {
    auto* iface = m_bus.interface();
    const bool now = iface && iface->isServiceRegistered(kDaemonService).value();
    if (now != m_available) {
        m_available = now;
        emit availableChanged();
    }
}

namespace {

// ~/.local/bin first: that is where `make install` puts the suite, and it is
// not on PATH in a KDE or GNOME session, which do not read the sway config.
QString findTool(const QString& name) {
    const QString local = QDir::homePath() + QStringLiteral("/.local/bin/") + name;
    if (QFileInfo(local).isExecutable())
        return local;
    const QString onPath = QStandardPaths::findExecutable(name);
    return onPath.isEmpty() ? name : onPath;
}

QStringList argStrings(const QVariantList& args) {
    QStringList out;
    for (const QVariant& v : args) {
        if (v.metaType() == QMetaType::fromType<QList<int>>()) {
            for (int i : v.value<QList<int>>()) out << QString::number(i);
        } else if (v.metaType() == QMetaType::fromType<bool>()) {
            out << (v.toBool() ? QStringLiteral("true") : QStringLiteral("false"));
        } else {
            out << v.toString();
        }
    }
    return out;
}

bool serviceMissing(const QDBusError& e) {
    return e.type() == QDBusError::ServiceUnknown || e.type() == QDBusError::NoServer
        || e.type() == QDBusError::Disconnected;
}

} // namespace

void B1airDaemon::runFallback(const QString& service, const QString& method, const QVariantList& args,
                              std::function<void(const QString&)> ready) {
    QString program;
    QStringList argv;
    if (service == QLatin1String(kShellService)) {
        const QStringList a = argStrings(args);
        program = findTool(QStringLiteral("b1air-shell"));
        if (method == QLatin1String("Toggle"))           argv << QStringLiteral("toggle") << a.value(0);
        else if (method == QLatin1String("Open"))        argv << QStringLiteral("open") << a.value(0) << a.value(1);
        else if (method == QLatin1String("Close"))       argv << QStringLiteral("close") << a.value(0);
        else                                             argv << QStringLiteral("forceReload");
    } else {
        program = findTool(QStringLiteral("b1air-daemon"));
        argv << QStringLiteral("dbus-call") << method << argStrings(args);
    }

    auto* proc = new QProcess(this);
    connect(proc, &QProcess::finished, this,
            [this, proc, method, ready](int code, QProcess::ExitStatus status) {
        if (status == QProcess::NormalExit && code == 0) {
            if (ready) ready(QString::fromUtf8(proc->readAllStandardOutput()).trimmed());
        } else {
            emit failed(method, QStringLiteral("b1air-daemon is not running, and running it directly failed: ")
                                + QString::fromUtf8(proc->readAllStandardError()).trimmed());
        }
        proc->deleteLater();
    });
    connect(proc, &QProcess::errorOccurred, this, [this, proc, method](QProcess::ProcessError e) {
        if (e != QProcess::FailedToStart) return;
        emit failed(method, QStringLiteral("b1air-daemon is not running and could not be started."));
        proc->deleteLater();
    });
    proc->start(program, argv);
}

void B1airDaemon::call(const QString& service, const QString& path, const QString& iface,
                       const QString& method, const QVariantList& args) {
    // Straight to the fallback when nobody owns the name: a round trip only
    // to be told so is a notification the user did not need.
    if (!m_bus.isConnected() || (service == QLatin1String(kDaemonService) && !m_available)) {
        runFallback(service, method, args);
        return;
    }

    QDBusMessage msg = QDBusMessage::createMethodCall(service, path, iface, method);
    msg.setArguments(args);

    auto* watcher = new QDBusPendingCallWatcher(m_bus.asyncCall(msg), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this,
            [this, service, method, args](QDBusPendingCallWatcher* w) {
        QDBusPendingReply<> reply = *w;
        if (reply.isError()) {
            const QDBusError e = reply.error();
            if (serviceMissing(e)) {
                runFallback(service, method, args);
            } else {
                emit failed(method, e.message().isEmpty() ? e.name() : e.message());
            }
        }
        w->deleteLater();
    });
}

void B1airDaemon::request(const QString& method, const QVariantList& args,
                          std::function<void(const QString&)> ready) {
    if (!m_bus.isConnected() || !m_available) {
        runFallback(QString::fromLatin1(kDaemonService), method, args, ready);
        return;
    }
    QDBusMessage msg = QDBusMessage::createMethodCall(kDaemonService, kDaemonPath, kDaemonIface, method);
    msg.setArguments(args);
    auto* watcher = new QDBusPendingCallWatcher(m_bus.asyncCall(msg), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this,
            [this, method, args, ready](QDBusPendingCallWatcher* w) {
        QDBusPendingReply<QString> reply = *w;
        if (!reply.isError())
            ready(reply.value());
        else if (serviceMissing(reply.error()))
            runFallback(QString::fromLatin1(kDaemonService), method, args, ready);
        else
            emit failed(method, reply.error().message());
        w->deleteLater();
    });
}

// ── org.b1air.Daemon ────────────────────────────────────────────────────────
void B1airDaemon::lock()  { call(kDaemonService, kDaemonPath, kDaemonIface, "Lock"); }
void B1airDaemon::reload() { call(kDaemonService, kDaemonPath, kDaemonIface, "Reload"); }
void B1airDaemon::toggleMute() { call(kDaemonService, kDaemonPath, kDaemonIface, "ToggleMute"); }

void B1airDaemon::volumeUp(int step) {
    call(kDaemonService, kDaemonPath, kDaemonIface, "VolumeUp", {step});
}
void B1airDaemon::volumeDown(int step) {
    call(kDaemonService, kDaemonPath, kDaemonIface, "VolumeDown", {step});
}
void B1airDaemon::brightnessUp(int step) {
    call(kDaemonService, kDaemonPath, kDaemonIface, "BrightnessUp", {step});
}
void B1airDaemon::brightnessDown(int step) {
    call(kDaemonService, kDaemonPath, kDaemonIface, "BrightnessDown", {step});
}
void B1airDaemon::brightnessSet(int value) {
    call(kDaemonService, kDaemonPath, kDaemonIface, "BrightnessSet", {value});
}
void B1airDaemon::setGameMode(bool enabled) {
    call(kDaemonService, kDaemonPath, kDaemonIface, "SetGameMode", {enabled});
}
void B1airDaemon::capture(const QString& mode) {
    call(kDaemonService, kDaemonPath, kDaemonIface, "Capture", {mode});
}
void B1airDaemon::power(const QString& action) {
    call(kDaemonService, kDaemonPath, kDaemonIface, "Power", {action});
}
void B1airDaemon::captureWithGeometry(const QString& mode, const QString& geometry, bool edit) {
    call(kDaemonService, kDaemonPath, kDaemonIface, "CaptureGeom", {mode, geometry, edit});
}

void B1airDaemon::requestStats(const QString& query, const QString& tag) {
    request(QStringLiteral("GetStats"), {query}, [this, tag](const QString& out) { emit statsReady(tag, out); });
}

void B1airDaemon::requestRemoteStatus(const QString& tag) {
    request(QStringLiteral("RemoteStatus"), {}, [this, tag](const QString& out) { emit remoteStatusReady(tag, out); });
}

void B1airDaemon::remoteStop() {
    call(kDaemonService, kDaemonPath, kDaemonIface, "RemoteStop");
}
void B1airDaemon::remotePromptFree(bool enabled) {
    call(kDaemonService, kDaemonPath, kDaemonIface, "RemotePromptFree", {enabled});
}
void B1airDaemon::sidecarCreate(int width, int height) {
    call(kDaemonService, kDaemonPath, kDaemonIface, "SidecarCreate", {width, height});
}
void B1airDaemon::sidecarRemove() {
    call(kDaemonService, kDaemonPath, kDaemonIface, "SidecarRemove");
}

void B1airDaemon::requestDotfilesStatus(const QString& tag) {
    request(QStringLiteral("DotfilesStatus"), {}, [this, tag](const QString& out) { emit dotfilesStatusReady(tag, out); });
}

void B1airDaemon::dotfilesSys() {
    call(kDaemonService, kDaemonPath, kDaemonIface, "DotfilesSys");
}
void B1airDaemon::dotfilesSync() {
    call(kDaemonService, kDaemonPath, kDaemonIface, "DotfilesSync");
}
void B1airDaemon::sweeperClean() {
    call(kDaemonService, kDaemonPath, kDaemonIface, "SweeperClean");
}

void B1airDaemon::zonesApply(int zoneId) {
    call(kDaemonService, kDaemonPath, kDaemonIface, "ZonesApply", {zoneId});
}
void B1airDaemon::micRnnoiseToggle() {
    call(kDaemonService, kDaemonPath, kDaemonIface, "MicRnnoiseToggle");
}
void B1airDaemon::powerProfileSet(const QString& name) {
    call(kDaemonService, kDaemonPath, kDaemonIface, "PowerProfileSet", {name});
}

void B1airDaemon::monitorsApply(const QString& layoutJson) {
    call(kDaemonService, kDaemonPath, kDaemonIface, "MonitorsApply", {layoutJson});
}
void B1airDaemon::ddcSet(const QString& id, int percent) {
    call(kDaemonService, kDaemonPath, kDaemonIface, "DdcSet", {id, percent});
}

void B1airDaemon::eqApply() {
    call(kDaemonService, kDaemonPath, kDaemonIface, "EqApply");
}
void B1airDaemon::eqSetBand(int band, int value) {
    call(kDaemonService, kDaemonPath, kDaemonIface, "EqSetBand", {band, value});
}
void B1airDaemon::eqSetPreset(const QString& name) {
    call(kDaemonService, kDaemonPath, kDaemonIface, "EqSetPreset", {name});
}
void B1airDaemon::eqSetAll(const QVariantList& bands) {
    QList<int> values;
    values.reserve(bands.size());
    for (const QVariant& v : bands) values.push_back(v.toInt());
    call(kDaemonService, kDaemonPath, kDaemonIface, "EqSetAll",
        {QVariant::fromValue(values)});
}

void B1airDaemon::requestScanQr(const QString& geometry, const QString& tag) {
    request(QStringLiteral("ScanQr"), {geometry}, [this, tag](const QString& out) { emit scanQrReady(tag, out); });
}

void B1airDaemon::requestVersion(const QString& tag) {
    request(QStringLiteral("GetVersion"), {}, [this, tag](const QString& out) { emit versionReady(tag, out); });
}

// ── org.b1air.Shell ─────────────────────────────────────────────────────────
void B1airDaemon::togglePanel(const QString& panel) {
    call(kShellService, kShellPath, kShellIface, "Toggle", {panel});
}
void B1airDaemon::openPanel(const QString& panel, const QString& arg) {
    call(kShellService, kShellPath, kShellIface, "Open", {panel, arg});
}
void B1airDaemon::closePanel(const QString& panel) {
    call(kShellService, kShellPath, kShellIface, "Close", {panel});
}
void B1airDaemon::forceReload() {
    call(kShellService, kShellPath, kShellIface, "ForceReload");
}

void B1airDaemon::onCameraInUseChanged(bool inUse) {
    if (m_cameraInUse == inUse)
        return;
    m_cameraInUse = inUse;
    emit cameraInUseChanged(inUse);
}

// ── Wallpaper palette ────────────────────────────────────────────────────────

namespace {

/** One role, as HSL on a given hue. */
QString tone(qreal hueDeg, qreal sat, qreal light) {
    QColor c;
    c.setHslF(std::fmod(std::fmod(hueDeg, 360.0) + 360.0, 360.0) / 360.0,
              qBound(0.0, sat, 1.0), qBound(0.0, light, 1.0));
    return c.name(QColor::HexRgb);
}

} // namespace

QVariantMap B1airDaemon::paletteFromImage(const QString& path) const {
    QVariantMap out;

    QString file = path;
    if (file.startsWith("file://"))
        file = QUrl(file).toLocalFile();

    QImage img(file);
    if (img.isNull())
        return out;                        // caller keeps whatever it had

    // Small enough that this is instant and that single stray pixels stop
    // deciding anything; large enough that a small bright subject still counts.
    img = img.scaled(96, 96, Qt::IgnoreAspectRatio, Qt::SmoothTransformation)
             .convertToFormat(QImage::Format_RGB32);

    // Hue histogram, weighted by how colourful and how well-lit each pixel is.
    // Grey and near-black pixels carry no hue, and a wallpaper is mostly those:
    // counting them would drag every result towards whatever the sky happens to
    // be doing.
    constexpr int kBuckets = 36;
    double weight[kBuckets] = {0};
    double litSum = 0;
    int litCount = 0;

    for (int y = 0; y < img.height(); ++y) {
        const QRgb* row = reinterpret_cast<const QRgb*>(img.constScanLine(y));
        for (int x = 0; x < img.width(); ++x) {
            const QColor c = QColor::fromRgb(row[x]);
            // float, not qreal: this Qt build's getHslF takes float*.
            float h = 0, s = 0, l = 0;
            c.getHslF(&h, &s, &l);
            litSum += l;
            ++litCount;
            if (h < 0 || s < 0.18 || l < 0.10 || l > 0.92)
                continue;
            const int b = qBound(0, int(h * kBuckets), kBuckets - 1);
            weight[b] += s * (1.0 - std::abs(l - 0.5));
        }
    }

    int best = -1;
    double bestWeight = 0;
    for (int i = 0; i < kBuckets; ++i)
        if (weight[i] > bestWeight) { bestWeight = weight[i]; best = i; }

    // A picture with no colour in it at all — a black-and-white photograph, a
    // solid grey — has no hue to offer. Rather than invent one, fall back to the
    // shipped accent's, so the result is the built-in palette's own family.
    const qreal hue = (best >= 0) ? (best + 0.5) * (360.0 / kBuckets) : 220.0;
    const qreal meanLight = litCount ? litSum / litCount : 0.2;

    // Structural roles: one hue, fixed steps. A wallpaper that is washed out
    // gets a slightly stronger tint so the theme still reads as coming from it.
    const qreal tint = (meanLight < 0.25) ? 0.24 : 0.18;

    out["ground"]         = tone(hue, tint,        0.08);
    out["lowest"]         = tone(hue, tint + 0.02, 0.05);
    out["low"]            = tone(hue, tint,        0.11);
    out["mid"]            = tone(hue, tint - 0.04, 0.19);
    out["high"]           = tone(hue, tint - 0.06, 0.26);
    out["highest"]        = tone(hue, tint - 0.08, 0.34);

    out["text"]           = tone(hue, 0.16, 0.91);
    out["textDim"]        = tone(hue, 0.13, 0.73);
    out["outline"]        = tone(hue, 0.11, 0.50);
    out["outlineVariant"] = tone(hue, 0.13, 0.29);

    out["primary"]        = tone(hue, 0.62, 0.70);
    out["primaryText"]    = tone(hue, 0.30, 0.08);
    out["primaryBox"]     = tone(hue, 0.26, 0.29);
    out["tertiary"]       = tone(hue + 55, 0.55, 0.74);

    // Decorative family: offsets from the wallpaper's hue, so the accents in the
    // Control Center's tiles stay related to each other and to the picture.
    out["blue"]     = tone(hue,        0.62, 0.70);
    out["sapphire"] = tone(hue + 20,   0.58, 0.68);
    out["mauve"]    = tone(hue + 45,   0.55, 0.74);
    out["pink"]     = tone(hue + 75,   0.55, 0.78);
    out["lavender"] = tone(hue - 25,   0.60, 0.80);
    out["teal"]     = tone(hue - 45,   0.50, 0.70);

    // Semantic colours keep their own hues and borrow only the saturation, so
    // "error" is still red on a green wallpaper.
    out["error"]     = tone(348, 0.65, 0.72);
    out["errorText"] = tone(hue, 0.30, 0.08);
    out["red"]       = tone(348, 0.65, 0.72);
    out["maroon"]    = tone(358, 0.55, 0.74);
    out["peach"]     = tone(25,  0.70, 0.72);
    out["yellow"]    = tone(45,  0.68, 0.76);
    out["green"]     = tone(120, 0.45, 0.72);

    return out;
}

void B1airDaemon::trimMemory() {
    if (m_engine) {
        m_engine->collectGarbage();
        m_engine->trimComponentCache();
    }
    for (QWindow* w : QGuiApplication::topLevelWindows()) {
        if (auto* qw = qobject_cast<QQuickWindow*>(w))
            qw->releaseResources();
    }
    malloc_trim(0);
}

int B1airDaemon::memoryMB() const {
    QFile f(QStringLiteral("/proc/self/smaps_rollup"));
    if (!f.open(QIODevice::ReadOnly)) return -1;
    // readAll, not atEnd/readLine: a /proc file reports a size of 0, so atEnd()
    // is true before anything is read and the loop never ran.
    for (const QByteArray& line : f.readAll().split('\n')) {
        if (line.startsWith("Pss:")) {
            // "Pss:  123456 kB"
            const QList<QByteArray> parts = line.simplified().split(' ');
            if (parts.size() >= 2) return int(parts[1].toLongLong() / 1024);
        }
    }
    return -1;
}

bool B1airDaemon::supervised() const {
    QFile stat(QStringLiteral("/proc/self/stat"));
    if (!stat.open(QIODevice::ReadOnly)) return false;
    // The command name is in parentheses and may contain spaces; the parent
    // pid is the second field after the closing one.
    const QByteArray s = stat.readAll();
    const int close = s.lastIndexOf(')');
    if (close < 0) return false;
    const QList<QByteArray> fields = s.mid(close + 2).split(' ');
    if (fields.size() < 2) return false;
    QFile comm(QStringLiteral("/proc/%1/comm").arg(QString::fromLatin1(fields[1])));
    if (!comm.open(QIODevice::ReadOnly)) return false;
    return comm.readAll().trimmed() == "b1air-daemon";
}
