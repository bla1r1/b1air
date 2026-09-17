#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>
#include <QNetworkAccessManager>
#include <QNetworkReply>
#include <QJsonObject>
#include <QJsonDocument>
#include <QJsonArray>
#include <QDir>
#include <QFile>

struct NoteItem {
    QString id;
    QString title;
    QString content;
    QStringList tags;
    QString modified;
    QString source; // "local", "obsidian", "notion"
    QString filePath;
};

class NotesBackend : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantList noteList READ noteList NOTIFY notesChanged)
    Q_PROPERTY(QString currentNoteId READ currentNoteId NOTIFY currentNoteChanged)
    Q_PROPERTY(QString currentTitle READ currentTitle NOTIFY currentNoteChanged)
    Q_PROPERTY(QString currentContent READ currentContent NOTIFY currentNoteChanged)
    Q_PROPERTY(QString currentTags READ currentTags NOTIFY currentNoteChanged)
    Q_PROPERTY(QString syncStatus READ syncStatus NOTIFY syncStatusChanged)
    Q_PROPERTY(QString obsidianVaultPath READ obsidianVaultPath NOTIFY obsidianVaultChanged)
    Q_PROPERTY(bool isNotionConfigured READ isNotionConfigured NOTIFY notionConfigChanged)

public:
    explicit NotesBackend(QObject* parent = nullptr);

    QVariantList noteList() const;
    QString currentNoteId() const { return m_currentId; }
    QString currentTitle() const;
    QString currentContent() const;
    QString currentTags() const;
    QString syncStatus() const { return m_syncStatus; }
    QString obsidianVaultPath() const { return m_obsidianVault; }
    bool isNotionConfigured() const { return !m_notionToken.isEmpty() && !m_notionDbId.isEmpty(); }

    Q_INVOKABLE void loadNotes();
    Q_INVOKABLE void selectNote(const QString& id);
    Q_INVOKABLE void createNote(const QString& title = "Untitled");
    Q_INVOKABLE void saveCurrentNote(const QString& title, const QString& content, const QString& tags);
    Q_INVOKABLE void deleteNote(const QString& id);
    Q_INVOKABLE void setObsidianVault(const QString& path);
    Q_INVOKABLE void setNotionCredentials(const QString& token, const QString& dbId);
    Q_INVOKABLE void syncWithNotion();
    Q_INVOKABLE void syncWithObsidian();
    // Ask b1air-files for a folder and use it as the Obsidian vault. The only
    // way to set one was editing config.json by hand.
    Q_INVOKABLE void chooseObsidianVault();
    Q_INVOKABLE QString renderMarkdownToHtml(const QString& markdown,
                                            const QVariantMap& palette = {});

signals:
    void notesChanged();
    void currentNoteChanged();
    void syncStatusChanged();
    void obsidianVaultChanged();
    void notionConfigChanged();

private:
    void ensureStorageDir();
    void scanObsidianVault();
    void saveConfig();
    void loadConfig();
    static QStringList tagsIn(const QString& content);
    static QString safeFileTitle(const QString& title);
    static QString freeNotePath(const QString& dir, const QString& title, const QString& except = QString());

    QList<NoteItem> m_notes;
    QString m_currentId;
    QString m_storageDir;
    QString m_obsidianVault;
    QString m_notionToken;
    QString m_notionDbId;
    QString m_syncStatus = "Ready";

    QNetworkAccessManager m_netManager;
};
