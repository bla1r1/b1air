#pragma once

// =============================================================================
// Sway — sway's IPC, as a QML singleton.
//
// The shell talked to sway by spawning `swaymsg`: about forty places, a
// process for every click and every refresh, the reply parsed out of stdout,
// and events taken from a `swaymsg -t subscribe` kept alive by a bash loop
// that reaped the previous one with pgrep — which, with a bar on each of two
// screens, meant each bar killing the other's subscription in turn.
//
// This is the same protocol spoken directly: one socket for commands and
// queries (answered in order, so each reply goes to the callback that asked),
// one subscribed socket for events. Both find sway's socket themselves and
// come back after sway restarts; `reconnected` says so, for anyone holding
// state from before.
//
//   Sway.command("workspace " + Sway.quote(name))
//   Sway.command("[con_id=" + id + "] focus", ok => { ... })
//   Sway.query("workspaces", list => topBar.workspacesList = list)
//   Connections { target: Sway; function onWindowEvent(e) { ... } }
// =============================================================================

#include <QByteArray>
#include <QJSValue>
#include <QJsonObject>
#include <QJsonValue>
#include <QLocalSocket>
#include <QObject>
#include <QQueue>
#include <QString>
#include <QTimer>
#include <QVariant>

class QQmlEngine;

class SwayClient : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool connected READ connected NOTIFY connectedChanged)
    // Which compositor answers, from its get_version: swayFX adds
    // `sway_original_version`, which plain sway does not have. Unknown
    // (swayfx true, names empty) until the first answer.
    Q_PROPERTY(bool swayfx READ swayfx NOTIFY versionChanged)
    Q_PROPERTY(QString compositorName READ compositorName NOTIFY versionChanged)   // "swayFX 0.6", "sway 1.11"
    Q_PROPERTY(QString versionText READ versionText NOTIFY versionChanged)         // as `sway --version` prints it

public:
    explicit SwayClient(QObject* parent = nullptr);

    void setEngine(QQmlEngine* engine) { m_engine = engine; }
    bool connected() const { return m_up; }
    bool swayfx() const { return m_swayfx; }
    QString compositorName() const { return m_compositorName; }
    QString versionText() const { return m_versionText; }

    /**
     * Runs a sway command (several, separated by ';', as in the config).
     * The callback, if given, gets true when every part succeeded, and the
     * reply list as sway sent it.
     */
    Q_INVOKABLE void command(const QString& cmd, const QJSValue& callback = QJSValue());

    /**
     * Asks sway something: "workspaces", "outputs", "tree", "inputs",
     * "marks", "version", "config", "seats", "binding_modes". The callback
     * gets the parsed reply; nothing is called if sway is not there.
     */
    Q_INVOKABLE void query(const QString& what, const QJSValue& callback);

    /** A command argument quoted for sway: "name with \"quotes\"". */
    Q_INVOKABLE static QString quote(const QString& arg);

    /** For C++ callers (the shell binary): fire and forget. */
    void send(const QString& cmd) { command(cmd); }

signals:
    void connectedChanged();
    void versionChanged();
    // Sway came back on a new socket: refetch anything kept from before.
    void reconnected();
    void windowEvent(const QJsonObject& event);
    void workspaceEvent(const QJsonObject& event);
    void inputEvent(const QJsonObject& event);
    void outputEvent(const QJsonObject& event);
    void modeEvent(const QJsonObject& event);

private:
    struct Pending {
        quint32 type;
        QJSValue callback;
        bool version = false;   // our own get_version, not a caller's
    };

    static QString findSocket();
    void connectBoth();
    void dropped();
    void request(quint32 type, const QByteArray& payload, const QJSValue& callback);
    void readQuery();
    void readEvents();
    template <typename F> static void drain(QByteArray& buf, F&& each);
    // Replies go to QML as QJson values, which become real JS arrays and
    // objects; a QVariantList arrives as a list wrapper that Array.isArray()
    // says is not an array, and every caller checks that.
    void call(const QJSValue& callback, const QJSValueList& args);
    QJSValue toJs(const QJsonValue& v) const;

    QQmlEngine* m_engine = nullptr;
    QLocalSocket m_query;
    QLocalSocket m_events;
    QByteArray m_queryBuf;
    QByteArray m_eventBuf;
    QQueue<Pending> m_pending;
    // Asked before the socket was up: sent on connect, in order.
    QList<QPair<QPair<quint32, QByteArray>, QJSValue>> m_waiting;
    QTimer m_retry;
    bool m_up = false;
    bool m_swayfx = true;
    QString m_compositorName;
    QString m_versionText;
    bool m_everUp = false;
};
