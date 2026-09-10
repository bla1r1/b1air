#include "b1airdaemon.hpp"

#include <QDBusConnectionInterface>
#include <QDBusMessage>
#include <QDBusMetaType>
#include <QDBusPendingCall>
#include <QDBusPendingCallWatcher>
#include <QDBusPendingReply>

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

void B1airDaemon::call(const QString& service, const QString& path, const QString& iface,
                       const QString& method, const QVariantList& args) {
    if (!m_bus.isConnected()) {
        emit failed(method, QStringLiteral("No session bus connection."));
        return;
    }

    QDBusMessage msg = QDBusMessage::createMethodCall(service, path, iface, method);
    msg.setArguments(args);

    auto* watcher = new QDBusPendingCallWatcher(m_bus.asyncCall(msg), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this,
            [this, method](QDBusPendingCallWatcher* w) {
        QDBusPendingReply<> reply = *w;
        if (reply.isError()) {
            const QDBusError e = reply.error();
            QString detail = e.message();
            if (detail.isEmpty()) detail = e.name();
            if (e.type() == QDBusError::ServiceUnknown)
                detail = QStringLiteral("b1air-daemon is not running.");
            emit failed(method, detail);
        }
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
    QDBusMessage msg = QDBusMessage::createMethodCall(kDaemonService, kDaemonPath,
                                                     kDaemonIface, "GetStats");
    msg.setArguments({query});

    auto* watcher = new QDBusPendingCallWatcher(m_bus.asyncCall(msg), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this,
            [this, tag](QDBusPendingCallWatcher* w) {
        QDBusPendingReply<QString> reply = *w;
        if (reply.isError()) emit failed(QStringLiteral("GetStats"), reply.error().message());
        else emit statsReady(tag, reply.value());
        w->deleteLater();
    });
}

void B1airDaemon::requestRemoteStatus(const QString& tag) {
    QDBusMessage msg = QDBusMessage::createMethodCall(kDaemonService, kDaemonPath,
                                                     kDaemonIface, "RemoteStatus");
    auto* watcher = new QDBusPendingCallWatcher(m_bus.asyncCall(msg), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this,
            [this, tag](QDBusPendingCallWatcher* w) {
        QDBusPendingReply<QString> reply = *w;
        if (reply.isError()) emit failed(QStringLiteral("RemoteStatus"), reply.error().message());
        else emit remoteStatusReady(tag, reply.value());
        w->deleteLater();
    });
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
    QDBusMessage msg = QDBusMessage::createMethodCall(kDaemonService, kDaemonPath,
                                                     kDaemonIface, "DotfilesStatus");
    auto* watcher = new QDBusPendingCallWatcher(m_bus.asyncCall(msg), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this,
            [this, tag](QDBusPendingCallWatcher* w) {
        QDBusPendingReply<QString> reply = *w;
        if (reply.isError()) emit failed(QStringLiteral("DotfilesStatus"), reply.error().message());
        else emit dotfilesStatusReady(tag, reply.value());
        w->deleteLater();
    });
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
    QDBusMessage msg = QDBusMessage::createMethodCall(kDaemonService, kDaemonPath,
                                                     kDaemonIface, "ScanQr");
    msg.setArguments({geometry});
    auto* watcher = new QDBusPendingCallWatcher(m_bus.asyncCall(msg), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this,
            [this, tag](QDBusPendingCallWatcher* w) {
        QDBusPendingReply<QString> reply = *w;
        if (reply.isError()) emit failed(QStringLiteral("ScanQr"), reply.error().message());
        else emit scanQrReady(tag, reply.value());
        w->deleteLater();
    });
}

void B1airDaemon::requestVersion(const QString& tag) {
    QDBusMessage msg = QDBusMessage::createMethodCall(kDaemonService, kDaemonPath,
                                                     kDaemonIface, "GetVersion");
    auto* watcher = new QDBusPendingCallWatcher(m_bus.asyncCall(msg), this);
    connect(watcher, &QDBusPendingCallWatcher::finished, this,
            [this, tag](QDBusPendingCallWatcher* w) {
        QDBusPendingReply<QString> reply = *w;
        if (reply.isError()) emit failed(QStringLiteral("GetVersion"), reply.error().message());
        else emit versionReady(tag, reply.value());
        w->deleteLater();
    });
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
void B1airDaemon::switcherAdvance() {
    call(kShellService, kShellPath, kShellIface, "SwitcherAdvance");
}
void B1airDaemon::switcherConfirm() {
    call(kShellService, kShellPath, kShellIface, "SwitcherConfirm");
}

void B1airDaemon::onCameraInUseChanged(bool inUse) {
    if (m_cameraInUse == inUse)
        return;
    m_cameraInUse = inUse;
    emit cameraInUseChanged(inUse);
}
