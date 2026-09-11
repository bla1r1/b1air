#pragma once

// =============================================================================
// B1air.Daemon — the running daemon, exposed to QML directly.
//
// The shell used to reach the daemon by spawning `b1air-daemon <verb>`: a
// process per click, with the exit code thrown away, so a failed action was
// indistinguishable from a successful one. The daemon has published a D-Bus
// interface the whole time; this is that interface, as a QML singleton.
//
// Calls are asynchronous and never block the UI thread. A call that fails
// emits failed(), which is the part the subprocess route could not provide.
// =============================================================================

#include <QObject>
#include <QVariantMap>
#include <QString>
#include <QDBusConnection>

class B1airDaemon : public QObject {
    Q_OBJECT

    // False when the daemon is not on the bus, so the UI can disable controls
    // instead of offering actions that cannot work.
    Q_PROPERTY(bool available READ available NOTIFY availableChanged)
    // Whether anything currently holds a /dev/video* device open. Pushed by the
    // daemon when it changes rather than polled: the walk of /proc that answers
    // it belongs on one side of the bus, not in every surface that asks.
    Q_PROPERTY(bool cameraInUse READ cameraInUse NOTIFY cameraInUseChanged)

public:
    explicit B1airDaemon(QObject* parent = nullptr);

    bool cameraInUse() const { return m_cameraInUse; }

    /**
     * A palette in Design.applyPalette()'s shape, derived from an image.
     *
     * matugen does this properly and is one `pacman -S` away, and it is the
     * honest alternative to what follows. It is not used because this suite has
     * spent its recent history taking dependencies *out* — SQLite, json and
     * libvterm are all carried now — and because the answer here only has to be
     * a coherent palette, not a faithful implementation of Material You.
     *
     * The wallpaper decides one thing: a hue. Everything structural is then
     * built from fixed lightness and saturation steps on that hue, which is
     * what guarantees the result is readable whatever the picture looks like —
     * a palette sampled directly from an image gives you two colours that are
     * nearly the same and text you cannot read on its own background.
     *
     * The semantic colours do not follow it. A red that is not red is not a
     * theme, it is a bug: error, warning and success keep their own hues and
     * borrow only the saturation.
     */
    Q_INVOKABLE QVariantMap paletteFromImage(const QString& path) const;

    bool available() const { return m_available; }

    // ── org.b1air.Daemon ────────────────────────────────────────────────────
    Q_INVOKABLE void lock();
    Q_INVOKABLE void reload();
    Q_INVOKABLE void volumeUp(int step = 5);
    Q_INVOKABLE void volumeDown(int step = 5);
    Q_INVOKABLE void toggleMute();
    Q_INVOKABLE void brightnessUp(int step = 5);
    Q_INVOKABLE void brightnessDown(int step = 5);
    Q_INVOKABLE void brightnessSet(int value);
    Q_INVOKABLE void setGameMode(bool enabled);
    Q_INVOKABLE void capture(const QString& mode);

    // Same implementation as capture(), with an explicit region and an
    // optional editor pass. The daemon used to have two independent screenshot
    // functions behind these two methods; the second one ignored every
    // screenshot setting and its window mode never worked, so it is gone.
    Q_INVOKABLE void captureWithGeometry(const QString& mode, const QString& geometry = QString(),
                                         bool edit = false);
    Q_INVOKABLE void power(const QString& action);

    // Reply arrives on statsReady(); `tag` is echoed back so a caller with
    // several queries in flight can tell them apart.
    Q_INVOKABLE void requestStats(const QString& query, const QString& tag = QString());

    // One version for the whole suite (daemon, shell, every b1air-* app) —
    // -> versionReady.
    Q_INVOKABLE void requestVersion(const QString& tag = QString());

    // Remote desktop / sidecar
    Q_INVOKABLE void requestRemoteStatus(const QString& tag = QString());  // -> remoteStatusReady
    Q_INVOKABLE void remoteStop();
    Q_INVOKABLE void remotePromptFree(bool enabled);
    Q_INVOKABLE void sidecarCreate(int width = 1920, int height = 1080);
    Q_INVOKABLE void sidecarRemove();

    // Dotfiles & maintenance
    Q_INVOKABLE void requestDotfilesStatus(const QString& tag = QString());  // -> dotfilesStatusReady
    Q_INVOKABLE void dotfilesSys();
    Q_INVOKABLE void dotfilesSync();
    Q_INVOKABLE void sweeperClean();

    // Zones, mic, power profile
    Q_INVOKABLE void zonesApply(int zoneId);
    Q_INVOKABLE void micRnnoiseToggle();
    Q_INVOKABLE void powerProfileSet(const QString& name);

    // Monitors & DDC
    Q_INVOKABLE void monitorsApply(const QString& layoutJson);
    Q_INVOKABLE void ddcSet(const QString& id, int percent);

    // Equalizer
    Q_INVOKABLE void eqApply();
    Q_INVOKABLE void eqSetBand(int band, int value);
    Q_INVOKABLE void eqSetPreset(const QString& name);
    Q_INVOKABLE void eqSetAll(const QVariantList& bands);

    // Screenshot QR scan
    Q_INVOKABLE void requestScanQr(const QString& geometry, const QString& tag = QString());  // -> scanQrReady

    // ── org.b1air.Shell ─────────────────────────────────────────────────────
    Q_INVOKABLE void togglePanel(const QString& panel);
    Q_INVOKABLE void openPanel(const QString& panel, const QString& arg = QString());
    Q_INVOKABLE void closePanel(const QString& panel = QString());
    Q_INVOKABLE void forceReload();

signals:
    void availableChanged();
    void failed(const QString& method, const QString& message);
    void statsReady(const QString& tag, const QString& json);
    void remoteStatusReady(const QString& tag, const QString& json);
    void scanQrReady(const QString& tag, const QString& text);
    void dotfilesStatusReady(const QString& tag, const QString& json);
    void versionReady(const QString& tag, const QString& version);

    // Relayed from the daemon.
    void volumeChanged(int value, bool muted);
    void brightnessChanged(int value);
    void wallpaperChanged(const QString& path);
    void panelStateChanged(const QString& panel, bool open);

    /**
     * The daemon asking this shell to open, close or cycle something.
     *
     * It used to ask by launching a whole `quickshell` process per keystroke,
     * purely to hand one string to the instance already running. This arrives
     * on the bus the shell is already connected to.
     */
    void panelRequested(const QString& action, const QString& panel, const QString& arg);
    void cameraInUseChanged(bool inUse);

private slots:
    void onNameOwnerChanged(const QString& name, const QString& oldOwner, const QString& newOwner);

private slots:
    void onCameraInUseChanged(bool inUse);

private:
    // Fire-and-report: dispatches asynchronously and turns a D-Bus error into
    // failed(), rather than dropping it the way execDetached did.
    void call(const QString& service, const QString& path, const QString& iface,
              const QString& method, const QVariantList& args = {});

    void refreshAvailability();

    QDBusConnection m_bus;
    bool m_available = false;
    bool m_cameraInUse = false;
};
