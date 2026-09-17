#pragma once

#include <QObject>
#include <QString>
#include <QFileInfo>
#include <QFile>
#include <QTextStream>
#include <QDir>

namespace b1air {

class TextBackend : public QObject {
    Q_OBJECT

    Q_PROPERTY(QString filePath READ filePath NOTIFY fileChanged)
    Q_PROPERTY(QString fileName READ fileName NOTIFY fileChanged)
    Q_PROPERTY(QString fileContent READ fileContent WRITE setFileContent NOTIFY contentChanged)
    Q_PROPERTY(bool isModified READ isModified WRITE setIsModified NOTIFY modifiedChanged)
    Q_PROPERTY(int lineCount READ lineCount NOTIFY statsChanged)
    Q_PROPERTY(int wordCount READ wordCount NOTIFY statsChanged)
    Q_PROPERTY(QString fileType READ fileType NOTIFY fileChanged)
    // Why the last open or save failed, in words; empty after a success.
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)
    // Where Save As starts for a file that has no path yet.
    Q_PROPERTY(QString suggestedPath READ suggestedPath NOTIFY fileChanged)

public:
    explicit TextBackend(QObject* parent = nullptr);
    virtual ~TextBackend() = default;

    QString filePath() const { return m_filePath; }
    QString fileName() const { return m_fileName; }
    QString fileContent() const { return m_content; }
    // Invokable as well as the property's setter: QML calls it as a method
    // on every keystroke, and a plain setter is not callable that way — it
    // threw "is not a function" on each key, so nothing typed ever reached
    // the backend and Ctrl+S wrote the file back exactly as it was opened.
    Q_INVOKABLE void setFileContent(const QString& content);

    bool isModified() const { return m_isModified; }
    void setIsModified(bool mod);

    int lineCount() const { return m_lineCount; }
    int wordCount() const { return m_wordCount; }
    QString fileType() const { return m_fileType; }
    QString lastError() const { return m_lastError; }
    QString suggestedPath() const;

    Q_INVOKABLE bool openFile(const QString& path);
    Q_INVOKABLE bool saveFile(const QString& path = "");
    Q_INVOKABLE void newFile();

signals:
    void fileChanged();
    void contentChanged();
    void modifiedChanged();
    void statsChanged();
    void lastErrorChanged();
    // After every save attempt, so the window can say what happened.
    void saved(bool ok);

private:
    void updateStats();
    void detectFileType();
    void setError(const QString& error);

    QString m_filePath;
    QString m_fileName = "Untitled";
    QString m_content;
    bool m_isModified = false;
    int m_lineCount = 1;
    int m_wordCount = 0;
    QString m_fileType = "Plain Text";
    QString m_lastError;
};

} // namespace b1air
