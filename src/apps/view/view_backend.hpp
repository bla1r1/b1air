#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QVariantMap>
#include <QImageReader>
#include <QFileInfo>
#include <QDir>

class ViewBackend : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString currentPath READ currentPath NOTIFY currentPathChanged)
    Q_PROPERTY(QString fileName READ fileName NOTIFY fileChanged)
    Q_PROPERTY(QString fileSize READ fileSize NOTIFY fileChanged)
    Q_PROPERTY(QString imageResolution READ imageResolution NOTIFY fileChanged)
    Q_PROPERTY(int fileIndex READ fileIndex NOTIFY fileChanged)
    Q_PROPERTY(int totalFiles READ totalFiles NOTIFY fileChanged)
    Q_PROPERTY(bool hasPrevious READ hasPrevious NOTIFY fileChanged)
    Q_PROPERTY(bool hasNext READ hasNext NOTIFY fileChanged)
    Q_PROPERTY(QVariantList filesInDir READ filesInDir NOTIFY directoryChanged)
    // What is open: "image", "video" or "audio". Pictures are shown, the
    // other two played, in the same window.
    Q_PROPERTY(QString kind READ kind NOTIFY fileChanged)
    // A picture with more than one frame (GIF, animated WebP): shown with
    // AnimatedImage, which plays it; Image shows the first frame only.
    Q_PROPERTY(bool animated READ animated NOTIFY fileChanged)
    // A picture's own size, turned as the camera held it: the window shows
    // it no larger than this.
    Q_PROPERTY(QSize imageSize READ imageSize NOTIFY fileChanged)

public:
    explicit ViewBackend(QObject* parent = nullptr);

    QString currentPath() const { return m_currentPath; }
    QString fileName() const { return m_fileName; }
    QString fileSize() const { return m_fileSize; }
    QString imageResolution() const { return m_resolution; }
    int fileIndex() const { return m_currentIndex; }
    int totalFiles() const { return m_imageList.size(); }
    bool hasPrevious() const { return m_currentIndex > 0; }
    bool hasNext() const { return m_currentIndex >= 0 && m_currentIndex < m_imageList.size() - 1; }
    QVariantList filesInDir() const { return m_filesInDir; }
    QString kind() const { return m_kind; }
    bool animated() const { return m_animated; }
    QSize imageSize() const { return m_imageSize; }
    /** "image", "video", "audio", or "" for a file the window can neither show nor play. */
    static QString kindOf(const QFileInfo& fi, bool sniff = false);
    /** Whether a film is in the folder opened: main.cpp draws on the GPU then. */
    bool folderHasVideo() const { return m_kinds.contains(QStringLiteral("video")); }
    /** The next one of the same kind — the next song after a song ends. "" at the end. */
    Q_INVOKABLE QString nextOfKind() const;

    Q_INVOKABLE void openFile(const QString& filePath);
    Q_INVOKABLE void next();
    Q_INVOKABLE void previous();
    Q_INVOKABLE void setWallpaper();
    Q_INVOKABLE QVariantMap getMetadata();

signals:
    void currentPathChanged();
    void fileChanged();
    void directoryChanged();

private:
    void scanDirectory(const QString& dirPath, const QString& currentFile);
    void updateFileInfo();

    QString m_currentPath;
    QString m_fileName;
    QString m_fileSize;
    QString m_resolution;
    int m_currentIndex = -1;
    QString m_kind;
    bool m_animated = false;
    QSize m_imageSize;
    QStringList m_imageList;
    QStringList m_kinds;      // kindOf each of m_imageList, in step
    QVariantList m_filesInDir;
};
