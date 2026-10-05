#pragma once

// =============================================================================
// The device-facing half of the compatibility layer.
//
// Services/ is imported as a directory, so every file in it has to resolve even
// when the window being built uses none of it — one unresolved import takes the
// whole directory down and the error names files that are perfectly fine. Six
// Quickshell modules are involved, and between them the shell asks for very
// little:
//
//   UPower       devices, displayDevice, and ten properties on a device
//   Pipewire     nodes, defaultAudioSink/Source, four properties on a node
//   Bluetooth    defaultAdapter, devices
//   Networking   devices, wifiEnabled
//   Mpris        players
//   Notifications  a server object the settings panel never reads
//
// These provide that shape. Where the data is cheap and honest to fetch it is
// fetched — UPower over D-Bus, PipeWire through wpctl, which this desktop
// already depends on. Where a standalone program has no business providing it
// at all, the object is present and empty rather than absent or invented: a
// second process must not register org.freedesktop.Notifications while the
// shell owns it, and a settings window has no reason to drive media players.
// =============================================================================

#include <QObject>
#include <QQmlEngine>
#include <QVariantList>
#include <QVariantMap>

namespace qscompat {

// ── A device, as the shell's QML expects to read one ──────────────────────────

class UPowerDevice : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool isLaptopBattery READ isLaptopBattery CONSTANT)
    Q_PROPERTY(bool isPresent READ isPresent CONSTANT)
    Q_PROPERTY(bool isRechargeable READ isRechargeable CONSTANT)
    Q_PROPERTY(qreal percentage READ percentage NOTIFY changed)
    Q_PROPERTY(qreal healthPercentage READ healthPercentage NOTIFY changed)
    Q_PROPERTY(int state READ state NOTIFY changed)
    Q_PROPERTY(QString model READ model CONSTANT)
    Q_PROPERTY(QString nativePath READ nativePath CONSTANT)
    Q_PROPERTY(qreal timeToEmpty READ timeToEmpty NOTIFY changed)
    Q_PROPERTY(qreal timeToFull READ timeToFull NOTIFY changed)

public:
    explicit UPowerDevice(QObject* parent = nullptr) : QObject(parent) {}

    bool isLaptopBattery() const { return m_laptop; }
    bool isPresent() const { return m_present; }
    bool isRechargeable() const { return m_rechargeable; }
    // Normalised 0..1, matching Quickshell — UPower's own Percentage is 0..100
    // and the shell's arithmetic assumes the former.
    qreal percentage() const { return m_percentage; }
    qreal healthPercentage() const { return m_health; }
    int state() const { return m_state; }
    QString model() const { return m_model; }
    QString nativePath() const { return m_nativePath; }
    qreal timeToEmpty() const { return m_toEmpty; }
    qreal timeToFull() const { return m_toFull; }

    void setFrom(const QVariantMap& props);

signals:
    void changed();

private:
    bool m_laptop = false, m_present = false, m_rechargeable = false;
    qreal m_percentage = 0, m_health = 0, m_toEmpty = 0, m_toFull = 0;
    int m_state = 0;
    QString m_model, m_nativePath;
};

/** `UPower.devices.values` in the shell's QML — a list wrapped in `.values`. */
class ObjectList : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantList values READ values NOTIFY valuesChanged)

public:
    explicit ObjectList(QObject* parent = nullptr) : QObject(parent) {}
    QVariantList values() const { return m_values; }
    void setValues(const QVariantList& v) { m_values = v; emit valuesChanged(); }

signals:
    void valuesChanged();

private:
    QVariantList m_values;
};

// ── UPower ───────────────────────────────────────────────────────────────────

class UPower : public QObject {
    Q_OBJECT
    Q_PROPERTY(QObject* devices READ devices CONSTANT)
    Q_PROPERTY(QObject* displayDevice READ displayDevice NOTIFY changed)

public:
    explicit UPower(QObject* parent = nullptr);

    QObject* devices() const { return m_devices; }
    QObject* displayDevice() const { return m_display; }

signals:
    void changed();

private:
    void refresh();

    ObjectList* m_devices = nullptr;
    UPowerDevice* m_display = nullptr;
};

// ── PipeWire ─────────────────────────────────────────────────────────────────

class PwAudio : public QObject {
    Q_OBJECT
    Q_PROPERTY(qreal volume READ volume WRITE setVolume NOTIFY changed)
    Q_PROPERTY(bool muted READ muted WRITE setMuted NOTIFY changed)

public:
    explicit PwAudio(QObject* parent = nullptr) : QObject(parent) {}
    qreal volume() const { return m_volume; }
    void setVolume(qreal v);
    bool muted() const { return m_muted; }
    void setMuted(bool m);
    void setNodeName(const QString& n) { m_node = n; }
    void apply(qreal v, bool m) { m_volume = v; m_muted = m; emit changed(); }

signals:
    void changed();

private:
    QString m_node;
    qreal m_volume = 0;
    bool m_muted = false;
};

class PwNode : public QObject {
    Q_OBJECT
    Q_PROPERTY(int id READ id CONSTANT)
    Q_PROPERTY(QString name READ name CONSTANT)
    Q_PROPERTY(QString description READ description CONSTANT)
    Q_PROPERTY(bool isSink READ isSink CONSTANT)
    Q_PROPERTY(bool isStream READ isStream CONSTANT)
    Q_PROPERTY(QObject* audio READ audio CONSTANT)

public:
    explicit PwNode(QObject* parent = nullptr) : QObject(parent), m_audio(new PwAudio(this)) {}

    int id() const { return m_id; }
    QString name() const { return m_name; }
    QString description() const { return m_description; }
    bool isSink() const { return m_isSink; }
    bool isStream() const { return m_isStream; }
    QObject* audio() const { return m_audio; }

    void init(int id, const QString& name, const QString& description,
              bool isSink, bool isStream, qreal volume, bool muted);

private:
    PwAudio* m_audio = nullptr;
    int m_id = 0;
    QString m_name, m_description;
    bool m_isSink = false, m_isStream = false;
};

class Pipewire : public QObject {
    Q_OBJECT
    Q_PROPERTY(QObject* nodes READ nodes CONSTANT)
    Q_PROPERTY(QObject* defaultAudioSink READ defaultAudioSink NOTIFY changed)
    Q_PROPERTY(QObject* defaultAudioSource READ defaultAudioSource NOTIFY changed)

public:
    explicit Pipewire(QObject* parent = nullptr);

    QObject* nodes() const { return m_nodes; }
    QObject* defaultAudioSink() const { return m_sink; }
    QObject* defaultAudioSource() const { return m_source; }

signals:
    void changed();

private:
    void refresh();

    ObjectList* m_nodes = nullptr;
    PwNode* m_sink = nullptr;
    PwNode* m_source = nullptr;
};

/**
 * Quickshell needs this to bind a node's live properties. Here the values are
 * read once per refresh, so it exists only so `PwObjectTracker { objects: … }`
 * keeps parsing.
 */
class PwObjectTracker : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantList objects READ objects WRITE setObjects NOTIFY objectsChanged)

public:
    explicit PwObjectTracker(QObject* parent = nullptr) : QObject(parent) {}
    QVariantList objects() const { return m_objects; }
    void setObjects(const QVariantList& o) { m_objects = o; emit objectsChanged(); }

signals:
    void objectsChanged();

private:
    QVariantList m_objects;
};

// ── Bluetooth, Networking, Mpris, Notifications ──────────────────────────────
//
// Present and empty. A settings window that is running because the desktop is
// not has no adapter state to report, no media players to drive, and must not
// take org.freedesktop.Notifications from a shell that may come back.

class Bluetooth : public QObject {
    Q_OBJECT
    Q_PROPERTY(QObject* defaultAdapter READ defaultAdapter CONSTANT)
    Q_PROPERTY(QObject* devices READ devices CONSTANT)

public:
    explicit Bluetooth(QObject* parent = nullptr) : QObject(parent), m_devices(new ObjectList(this)) {}
    QObject* defaultAdapter() const { return nullptr; }
    QObject* devices() const { return m_devices; }

private:
    ObjectList* m_devices = nullptr;
};

class Networking : public QObject {
    Q_OBJECT
    Q_PROPERTY(QObject* devices READ devices CONSTANT)
    Q_PROPERTY(bool wifiEnabled READ wifiEnabled NOTIFY changed)

public:
    explicit Networking(QObject* parent = nullptr) : QObject(parent), m_devices(new ObjectList(this)) {}
    QObject* devices() const { return m_devices; }
    bool wifiEnabled() const { return false; }

signals:
    void changed();

private:
    ObjectList* m_devices = nullptr;
};

class Mpris : public QObject {
    Q_OBJECT
    Q_PROPERTY(QObject* players READ players CONSTANT)

public:
    explicit Mpris(QObject* parent = nullptr) : QObject(parent), m_players(new ObjectList(this)) {}
    QObject* players() const { return m_players; }

private:
    ObjectList* m_players = nullptr;
};

class NotificationServer : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool keepOnReload MEMBER m_keepOnReload)
    Q_PROPERTY(bool imageSupported MEMBER m_imageSupported)
    Q_PROPERTY(bool actionsSupported MEMBER m_actionsSupported)
    Q_PROPERTY(bool bodyMarkupSupported MEMBER m_bodyMarkupSupported)
    Q_PROPERTY(bool bodySupported MEMBER m_bodySupported)
    Q_PROPERTY(bool persistenceSupported MEMBER m_persistenceSupported)
    // Services/Notifications.qml sets it; without the property here the
    // whole Services module failed to load in the standalone window.
    Q_PROPERTY(QVariantList extraHints MEMBER m_extraHints)

public:
    explicit NotificationServer(QObject* parent = nullptr) : QObject(parent) {}

signals:
    void notification(QObject* notification);

private:
    bool m_keepOnReload = false, m_imageSupported = false, m_actionsSupported = false;
    bool m_bodyMarkupSupported = false, m_bodySupported = false, m_persistenceSupported = false;
    QVariantList m_extraHints;
};

/** Registers everything in this header under its Quickshell module URI. */
void registerServiceTypes();

} // namespace qscompat
