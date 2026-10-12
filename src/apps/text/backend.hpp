#pragma once

#include <QAbstractListModel>
#include <QObject>
#include <QString>
#include <QTimer>
#include <vector>

namespace b1air {

/**
 * The open files, one tab each.
 *
 * The editor held one document: a file dropped on it, or opened from Files,
 * took the place of the one being edited. Now each is a tab, and what is in
 * them is kept as the session (see TextBackend::saveSession): a file edited
 * and not saved comes back after a restart as it was left, beside the file
 * on disk, which stays as it was until Save.
 */
class TextTabs : public QAbstractListModel {
    Q_OBJECT
    Q_PROPERTY(int count READ count NOTIFY countChanged)
public:
    enum Roles { DocIdRole = Qt::UserRole + 1, NameRole, PathRole, ModifiedRole };

    struct Doc {
        QString id;
        QString path;          // empty for a file not saved anywhere yet
        QString content;
        QString saved;         // as on disk when opened or last saved
        bool onDisk = false;   // saved is what the file holds
        int cursor = 0;
        bool draftWritten = false;   // the draft on disk is this content
        bool modified() const { return content != saved; }
        QString name() const;
    };

    explicit TextTabs(QObject* parent = nullptr) : QAbstractListModel(parent) {}
    int rowCount(const QModelIndex& parent = QModelIndex()) const override;
    QVariant data(const QModelIndex& index, int role) const override;
    QHash<int, QByteArray> roleNames() const override;
    int count() const { return int(m_docs.size()); }

    std::vector<Doc>& docs() { return m_docs; }
    const std::vector<Doc>& docs() const { return m_docs; }
    int indexOf(const QString& id) const;
    int indexOfPath(const QString& path) const;
    void append(Doc doc);
    void remove(int row);
    void changed(int row);   // name, path or modified

signals:
    void countChanged();

private:
    std::vector<Doc> m_docs;
};

class TextBackend : public QObject {
    Q_OBJECT

    Q_PROPERTY(QObject* tabs READ tabs CONSTANT)
    Q_PROPERTY(int currentIndex READ currentIndex WRITE setCurrentIndex NOTIFY currentChanged)
    Q_PROPERTY(QString currentId READ currentId NOTIFY currentChanged)
    // The tab in front.
    Q_PROPERTY(QString filePath READ filePath NOTIFY fileChanged)
    Q_PROPERTY(QString fileName READ fileName NOTIFY fileChanged)
    Q_PROPERTY(bool isModified READ isModified NOTIFY modifiedChanged)
    Q_PROPERTY(int lineCount READ lineCount NOTIFY statsChanged)
    Q_PROPERTY(int wordCount READ wordCount NOTIFY statsChanged)
    Q_PROPERTY(QString fileType READ fileType NOTIFY fileChanged)
    // Why the last open or save failed, in words; empty after a success.
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)
    // Where Save As starts for a file that has no path yet.
    Q_PROPERTY(QString suggestedPath READ suggestedPath NOTIFY fileChanged)

public:
    explicit TextBackend(QObject* parent = nullptr);
    ~TextBackend() override;

    QObject* tabs() const { return m_tabs; }
    int currentIndex() const { return m_current; }
    void setCurrentIndex(int i);
    QString currentId() const;

    QString filePath() const;
    QString fileName() const;
    bool isModified() const;
    int lineCount() const { return m_lineCount; }
    int wordCount() const { return m_wordCount; }
    QString fileType() const;
    QString lastError() const { return m_lastError; }
    QString suggestedPath() const;

    // What the tab with this id holds, and what was typed into it.
    Q_INVOKABLE QString contentOf(const QString& id) const;
    Q_INVOKABLE void setContentOf(const QString& id, const QString& content);
    Q_INVOKABLE int cursorOf(const QString& id) const;
    Q_INVOKABLE void setCursorOf(const QString& id, int position);
    Q_INVOKABLE bool isModifiedAt(int index) const;

    /** A file in a tab of its own; the one it is in already, if it is open. */
    Q_INVOKABLE bool openFile(const QString& path);
    /** The tab in front, to its file or to `path` (Save As). */
    Q_INVOKABLE bool saveFile(const QString& path = "");
    /** A new, empty tab. */
    Q_INVOKABLE void newFile();
    /** Close a tab, whatever is in it: the window asks first. */
    Q_INVOKABLE void closeTab(int index);
    /** The tab in front back to its file on disk: its changes let go. */
    Q_INVOKABLE void revertCurrent();

    /** The tabs and their unsaved text, written now (also on quitting). */
    void saveSession();
    /** The tabs the last session had open. */
    void restoreSession();

signals:
    void currentChanged();
    void fileChanged();
    void modifiedChanged();
    void statsChanged();
    void lastErrorChanged();
    // After every save attempt, so the window can say what happened.
    void saved(bool ok);
    // A tab's text replaced from here (opened again, reverted): its editor
    // takes it in.
    void contentReset(const QString& id);
    // Another `b1air-text` handed its files to this window (main.cpp).
    void raiseRequested();

private:
    TextTabs::Doc* current();
    const TextTabs::Doc* current() const;
    void updateStats();
    void setError(const QString& error);
    void scheduleSave();
    void currentWasChanged();
    static QString newId();
    QString stateDir() const;

    TextTabs* m_tabs;
    int m_current = -1;
    int m_lineCount = 1;
    int m_wordCount = 0;
    QString m_lastError;
    QTimer m_saveTimer;
};

} // namespace b1air
