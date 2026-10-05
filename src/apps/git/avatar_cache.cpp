#include "avatar_cache.hpp"

#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QNetworkReply>
#include <QRegularExpression>
#include <QStandardPaths>
#include <QUrl>
#include <QUrlQuery>

namespace {

constexpr int kSize = 64;
constexpr qint64 kRefusalSeconds = 7 * 24 * 3600;

QNetworkRequest request(const QString& url) {
    QNetworkRequest r{QUrl(url)};
    r.setAttribute(QNetworkRequest::RedirectPolicyAttribute, QNetworkRequest::NoLessSafeRedirectPolicy);
    r.setTransferTimeout(15000);
    r.setHeader(QNetworkRequest::UserAgentHeader, QStringLiteral("b1air-git"));
    return r;
}

QString byEmail(const QString& email) {
    QUrl u(QStringLiteral("https://avatars.githubusercontent.com/u/e"));
    QUrlQuery q;
    q.addQueryItem(QStringLiteral("email"), email);
    q.addQueryItem(QStringLiteral("s"), QString::number(kSize));
    u.setQuery(q);
    return u.toString(QUrl::FullyEncoded);
}

} // namespace

AvatarCache::AvatarCache(QObject* parent) : QObject(parent) {
    m_dir = QStandardPaths::writableLocation(QStandardPaths::GenericCacheLocation) + "/b1air/avatars";
    QDir().mkpath(m_dir);
}

QString AvatarCache::fileFor(const QString& email, const char* ext) const {
    const QByteArray key = QCryptographicHash::hash(email.trimmed().toLower().toUtf8(), QCryptographicHash::Sha1).toHex();
    return m_dir + "/" + QString::fromLatin1(key) + ext;
}

QString AvatarCache::sourceFor(const QString& email) {
    static const QRegularExpression noreply(QStringLiteral("^(?:\\d+\\+)?([^@]+)@users\\.noreply\\.github\\.com$"),
                                            QRegularExpression::CaseInsensitiveOption);
    const auto m = noreply.match(email.trimmed());
    if (m.hasMatch())
        return QStringLiteral("https://github.com/%1.png?size=%2").arg(m.captured(1)).arg(kSize);
    return byEmail(email.trimmed());
}

QString AvatarCache::url(const QString& email) {
    if (email.isEmpty() || !email.contains('@')) return {};
    const auto it = m_known.constFind(email);
    if (it != m_known.constEnd()) return *it;

    const QString picture = fileFor(email, ".img");
    if (QFileInfo::exists(picture)) {
        const QString u = QUrl::fromLocalFile(picture).toString();
        m_known.insert(email, u);
        return u;
    }
    const QFileInfo none(fileFor(email, ".none"));
    if (none.exists() && none.lastModified().secsTo(QDateTime::currentDateTime()) < kRefusalSeconds) {
        m_known.insert(email, QString());
        return {};
    }
    fetch(email);
    return {};
}

void AvatarCache::fetchReference() {
    if (m_referenceAsked) return;
    m_referenceAsked = true;
    auto* reply = m_net.get(request(byEmail(QStringLiteral("nobody@b1air.invalid"))));
    connect(reply, &QNetworkReply::finished, this, [this, reply]() {
        reply->deleteLater();
        // Offline: nothing to compare with, and nothing will download either;
        // asked again on the next url() that needs it.
        if (reply->error() != QNetworkReply::NoError) {
            m_referenceAsked = false;
            for (const auto& e : std::as_const(m_waiting)) m_pending.remove(e);
            m_waiting.clear();
            return;
        }
        m_reference = reply->readAll();
        const QStringList waiting = m_waiting;
        m_waiting.clear();
        for (const auto& e : waiting) {
            m_pending.remove(e);
            fetch(e);
        }
    });
}

void AvatarCache::fetch(const QString& email) {
    if (m_pending.contains(email)) return;
    m_pending.insert(email);
    const QString source = sourceFor(email);
    const bool byAddress = source.contains(QStringLiteral("/u/e?"));
    if (byAddress && m_reference.isEmpty()) {
        m_waiting << email;
        fetchReference();
        return;
    }
    auto* reply = m_net.get(request(source));
    connect(reply, &QNetworkReply::finished, this, [this, reply, email, byAddress]() {
        reply->deleteLater();
        m_pending.remove(email);
        const int status = reply->attribute(QNetworkRequest::HttpStatusCodeAttribute).toInt();
        if (reply->error() != QNetworkReply::NoError) {
            // A 404 is an answer — that account has no picture; a network
            // error is not, and is asked again next time.
            if (status == 404) store(email, {});
            return;
        }
        const QByteArray data = reply->readAll();
        store(email, byAddress && data == m_reference ? QByteArray() : data);
    });
}

void AvatarCache::store(const QString& email, const QByteArray& data) {
    if (data.isEmpty()) {
        QFile none(fileFor(email, ".none"));
        if (none.open(QIODevice::WriteOnly)) none.close();
        m_known.insert(email, QString());
        return;
    }
    const QString path = fileFor(email, ".img");
    QFile f(path + ".part");
    if (!f.open(QIODevice::WriteOnly) || f.write(data) != data.size()) return;
    f.close();
    QFile::remove(path);
    if (!QFile::rename(path + ".part", path)) return;
    QFile::remove(fileFor(email, ".none"));
    m_known.insert(email, QUrl::fromLocalFile(path).toString());
    ++m_revision;
    emit changed();
}
