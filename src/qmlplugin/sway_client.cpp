#include "sway_client.hpp"

#include <QDateTime>
#include <QDir>
#include <QHash>
#include <QRegularExpression>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QQmlEngine>

#include <unistd.h>

namespace {
constexpr char kMagic[] = "i3-ipc";
constexpr int kMagicLen = 6;
constexpr int kHeaderLen = kMagicLen + 8;

constexpr quint32 kRunCommand = 0;
constexpr quint32 kSubscribe = 2;
constexpr quint32 kEventBit = 0x80000000u;

quint32 queryType(const QString& what) {
    static const QHash<QString, quint32> types = {
        {"workspaces", 1}, {"outputs", 3}, {"tree", 4}, {"marks", 5},
        {"version", 7}, {"binding_modes", 8}, {"config", 9},
        {"inputs", 100}, {"seats", 101},
    };
    return types.value(what, 0);
}

QByteArray frame(quint32 type, const QByteArray& payload) {
    QByteArray out(kMagic, kMagicLen);
    char word[4];
    // The i3 protocol is in the host's byte order.
    const quint32 len = static_cast<quint32>(payload.size());
    memcpy(word, &len, 4);
    out.append(word, 4);
    memcpy(word, &type, 4);
    out.append(word, 4);
    return out + payload;
}
} // namespace

SwayClient::SwayClient(QObject* parent) : QObject(parent) {
    m_retry.setInterval(1000);
    m_retry.setSingleShot(true);
    connect(&m_retry, &QTimer::timeout, this, &SwayClient::connectBoth);

    connect(&m_query, &QLocalSocket::readyRead, this, &SwayClient::readQuery);
    connect(&m_events, &QLocalSocket::readyRead, this, &SwayClient::readEvents);
    for (QLocalSocket* s : {&m_query, &m_events}) {
        connect(s, &QLocalSocket::connected, this, [this] {
            if (m_up || m_query.state() != QLocalSocket::ConnectedState
                    || m_events.state() != QLocalSocket::ConnectedState)
                return;
            m_up = true;
            m_events.write(frame(kSubscribe,
                R"(["window","workspace","input","output","mode"])"));
            // Who is answering, for swayfx/compositorName.
            m_pending.enqueue({7, QJSValue(), true});
            m_query.write(frame(7, {}));
            for (const auto& w : std::as_const(m_waiting))
                request(w.first.first, w.first.second, w.second);
            m_waiting.clear();
            emit connectedChanged();
            if (m_everUp) emit reconnected();
            m_everUp = true;
        });
        connect(s, &QLocalSocket::disconnected, this, &SwayClient::dropped);
        connect(s, &QLocalSocket::errorOccurred, this, &SwayClient::dropped);
    }
    connectBoth();
}

// sway-ipc.<uid>.<pid>.sock: is the sway that made it still running? The
// file outlives it — a sway that crashed or was restarted leaves its socket
// behind, and a name that merely exists is no sign of anyone listening.
static bool socketAlive(const QString& path) {
    const QStringList parts = QFileInfo(path).fileName().split('.');
    return parts.size() >= 4 && QFileInfo::exists("/proc/" + parts.at(2));
}

// SWAYSOCK while its sway lives; otherwise the newest socket in the runtime
// directory whose sway does. The shell outlives a sway restart (the session
// keeps it), and with only SWAYSOCK it would knock on the dead one forever.
QString SwayClient::findSocket() {
    const QString env = qEnvironmentVariable("SWAYSOCK");
    if (!env.isEmpty() && QFileInfo::exists(env) && socketAlive(env)) return env;

    QString dir = qEnvironmentVariable("XDG_RUNTIME_DIR");
    if (dir.isEmpty()) dir = QStringLiteral("/run/user/%1").arg(getuid());
    QString best;
    QDateTime newest;
    const auto entries = QDir(dir).entryInfoList({QStringLiteral("sway-ipc.*.sock")},
                                                 QDir::System | QDir::Files);
    for (const QFileInfo& fi : entries) {
        if (!socketAlive(fi.absoluteFilePath())) continue;
        if (best.isEmpty() || fi.lastModified() > newest) {
            best = fi.absoluteFilePath();
            newest = fi.lastModified();
        }
    }
    return best;
}

void SwayClient::connectBoth() {
    const QString path = findSocket();
    if (path.isEmpty()) {
        m_retry.start();
        return;
    }
    m_queryBuf.clear();
    m_eventBuf.clear();
    m_query.connectToServer(path);
    m_events.connectToServer(path);
}

void SwayClient::dropped() {
    if (m_retry.isActive()) return;   // both sockets report it
    const bool was = m_up;
    m_up = false;
    m_retry.start();                  // before abort(), which reports again
    m_query.abort();
    m_events.abort();
    // Questions in flight will not be answered; the asker hears nothing, as
    // with a swaymsg that failed.
    m_pending.clear();
    if (was) emit connectedChanged();
}

void SwayClient::request(quint32 type, const QByteArray& payload, const QJSValue& callback) {
    if (!m_up) {
        // Kept for the connection; a command typed before sway answered
        // still happens. Bounded, so a missing sway does not grow this.
        if (m_waiting.size() < 64) m_waiting.append({{type, payload}, callback});
        return;
    }
    m_pending.enqueue({type, callback});
    m_query.write(frame(type, payload));
}

void SwayClient::command(const QString& cmd, const QJSValue& callback) {
    if (cmd.trimmed().isEmpty()) return;
    request(kRunCommand, cmd.toUtf8(), callback);
}

void SwayClient::query(const QString& what, const QJSValue& callback) {
    const quint32 type = queryType(what);
    if (!type) {
        qWarning("Sway.query: unknown question '%s'", qPrintable(what));
        return;
    }
    request(type, {}, callback);
}

QString SwayClient::quote(const QString& arg) {
    QString out = arg;
    out.replace('\\', QStringLiteral("\\\\")).replace('"', QStringLiteral("\\\""));
    return '"' + out + '"';
}

template <typename F>
void SwayClient::drain(QByteArray& buf, F&& each) {
    while (buf.size() >= kHeaderLen) {
        if (!buf.startsWith(kMagic)) {
            buf.clear();
            return;
        }
        quint32 len = 0, type = 0;
        memcpy(&len, buf.constData() + kMagicLen, 4);
        memcpy(&type, buf.constData() + kMagicLen + 4, 4);
        if (static_cast<quint64>(buf.size()) < kHeaderLen + static_cast<quint64>(len)) return;
        const QByteArray body = buf.mid(kHeaderLen, static_cast<qsizetype>(len));
        buf.remove(0, kHeaderLen + static_cast<qsizetype>(len));
        each(type, body);
    }
}

QJSValue SwayClient::toJs(const QJsonValue& v) const {
    return m_engine ? m_engine->toScriptValue(v) : QJSValue();
}

void SwayClient::call(const QJSValue& callback, const QJSValueList& args) {
    if (!callback.isCallable() || !m_engine) return;
    const QJSValue r = QJSValue(callback).call(args);
    if (r.isError())
        qWarning("Sway callback: %s", qPrintable(r.toString()));
}

void SwayClient::readQuery() {
    m_queryBuf += m_query.readAll();
    drain(m_queryBuf, [this](quint32 type, const QByteArray& body) {
        if (m_pending.isEmpty()) return;
        const Pending p = m_pending.dequeue();
        if (p.type != type) {
            // Out of step; nothing that follows can be matched. Start over.
            m_pending.clear();
            return;
        }
        const QJsonDocument doc = QJsonDocument::fromJson(body);
        if (p.version) {
            const QJsonObject v = doc.object();
            const QString human = v.value("human_readable").toString();
            const QString original = v.value("sway_original_version").toString();
            m_swayfx = v.contains("sway_original_version");
            // swayFX's human_readable is "0.6-fd71a6bd (date, branch)"; the
            // number is the part before the first '-' or ' '.
            const QString number = human.section(QRegularExpression("[- ]"), 0, 0);
            m_compositorName = (m_swayfx ? "swayFX " : "sway ") + number;
            m_versionText = m_swayfx
                ? "swayfx version " + human + " (based on sway " + original + ")"
                : "sway version " + human;
            emit versionChanged();
            return;
        }
        const QJsonValue reply = doc.isArray() ? QJsonValue(doc.array()) : QJsonValue(doc.object());
        if (type == kRunCommand) {
            bool ok = doc.isArray();
            for (const QJsonValue& r : doc.array())
                ok = ok && r.toObject().value("success").toBool();
            if (!ok)
                qWarning("Sway.command failed: %s", body.constData());
            call(p.callback, {QJSValue(ok), toJs(reply)});
        } else {
            call(p.callback, {toJs(reply)});
        }
    });
}

void SwayClient::readEvents() {
    m_eventBuf += m_events.readAll();
    drain(m_eventBuf, [this](quint32 type, const QByteArray& body) {
        if (!(type & kEventBit)) return;   // the subscribe reply
        const QJsonObject e = QJsonDocument::fromJson(body).object();
        switch (type & ~kEventBit) {
        case 0: emit workspaceEvent(e); break;
        case 1: emit outputEvent(e); break;
        case 2: emit modeEvent(e); break;
        case 3: emit windowEvent(e); break;
        case 0x15: emit inputEvent(e); break;
        default: break;
        }
    });
}
