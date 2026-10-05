#pragma once

#include <QHash>
#include <QNetworkAccessManager>
#include <QObject>
#include <QSet>
#include <QString>
#include <QStringList>

// =============================================================================
// GitHub avatars for commit authors, by email.
//
// The window drew initials in a coloured disc and nothing else. GitHub
// answers https://avatars.githubusercontent.com/u/e?email=… with the
// picture of the account that has the address — and with one and the same
// generated pattern for every address it does not know, which would have put
// the same purple squares beside every author without an account. So the
// picture is fetched here, compared with the one for an address nobody has,
// and kept only when it differs; the window keeps the initials otherwise.
// A users.noreply.github.com address names its account, and goes straight to
// github.com/<login>.png.
//
// Pictures and refusals are cached in ~/.cache/b1air/avatars, a refusal for
// a week, so a history of a thousand commits by ten people asks ten times.
// =============================================================================

class AvatarCache : public QObject {
    Q_OBJECT
    // Bumped whenever a picture arrives; bindings read it to look again.
    Q_PROPERTY(int revision READ revision NOTIFY changed)

public:
    explicit AvatarCache(QObject* parent = nullptr);

    int revision() const { return m_revision; }

    /** A file:// URL of the author's picture, or "" (and a fetch starts). */
    Q_INVOKABLE QString url(const QString& email);

signals:
    void changed();

private:
    void fetchReference();
    void fetch(const QString& email);
    void store(const QString& email, const QByteArray& data);
    QString fileFor(const QString& email, const char* ext) const;
    static QString sourceFor(const QString& email);

    QNetworkAccessManager m_net;
    QString m_dir;
    QByteArray m_reference;      // GitHub's picture for an unknown address
    bool m_referenceAsked = false;
    QStringList m_waiting;       // asked for before the reference was in
    QSet<QString> m_pending;
    QHash<QString, QString> m_known;   // email -> file URL, "" for none
    int m_revision = 0;
};
