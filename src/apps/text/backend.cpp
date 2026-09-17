#include "backend.hpp"

#include <QRegularExpression>
#include <QSaveFile>
#include <QUrl>
#include <QStandardPaths>

namespace b1air {

TextBackend::TextBackend(QObject* parent)
    : QObject(parent)
{
    updateStats();
}

void TextBackend::setFileContent(const QString& content) {
    if (m_content != content) {
        m_content = content;
        m_isModified = true;
        updateStats();
        emit contentChanged();
        emit modifiedChanged();
    }
}

void TextBackend::setIsModified(bool mod) {
    if (m_isModified != mod) {
        m_isModified = mod;
        emit modifiedChanged();
    }
}

bool TextBackend::openFile(const QString& path) {
    // A file:// URI (what xdg-open passes for %U) is percent-encoded:
    // cutting the scheme off left "%20" where the spaces were.
    QString cleanPath = path.startsWith("file://") ? QUrl(path).toLocalFile() : path;

    QFile file(cleanPath);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        // A path that does not exist yet is a new file to be written there,
        // the way `b1air-text notes.txt` works in any editor.
        if (!QFileInfo::exists(cleanPath)) {
            newFile();
            m_filePath = QFileInfo(cleanPath).absoluteFilePath();
            m_fileName = QFileInfo(cleanPath).fileName();
            detectFileType();
            emit fileChanged();
            return true;
        }
        setError("Could not open " + cleanPath + ": " + file.errorString());
        return false;
    }

    QTextStream in(&file);
    m_content = in.readAll();
    m_filePath = cleanPath;
    QFileInfo fi(cleanPath);
    m_fileName = fi.fileName();
    m_isModified = false;

    detectFileType();
    updateStats();
    setError(QString());

    emit fileChanged();
    emit contentChanged();
    emit modifiedChanged();
    return true;
}

bool TextBackend::saveFile(const QString& path) {
    QString targetPath = path.isEmpty() ? m_filePath : path;
    if (targetPath.startsWith("file://")) targetPath = QUrl(targetPath).toLocalFile();
    if (targetPath.isEmpty()) {
        setError("This file has no name yet — choose where to save it.");
        emit saved(false);
        return false;
    }
    if (targetPath.startsWith("~/")) targetPath = QDir::homePath() + targetPath.mid(1);

    // QSaveFile writes beside the target and renames over it on commit, so a
    // full disk or a crash mid-write leaves the old file intact instead of a
    // truncated one.
    QDir().mkpath(QFileInfo(targetPath).absolutePath());
    QSaveFile file(targetPath);
    // A writable file in a directory we cannot create files in (some of
    // /etc, a shared folder) can still be written in place.
    file.setDirectWriteFallback(true);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text)) {
        setError("Could not save " + targetPath + ": " + file.errorString());
        emit saved(false);
        return false;
    }
    {
        QTextStream out(&file);
        out << m_content;
    }
    if (!file.commit()) {
        setError("Could not save " + targetPath + ": " + file.errorString());
        emit saved(false);
        return false;
    }

    m_filePath = targetPath;
    QFileInfo fi(targetPath);
    m_fileName = fi.fileName();
    m_isModified = false;

    detectFileType();
    setError(QString());
    emit fileChanged();
    emit modifiedChanged();
    emit saved(true);
    return true;
}

QString TextBackend::suggestedPath() const {
    if (!m_filePath.isEmpty()) return m_filePath;
    QString dir = QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation);
    if (dir.isEmpty() || !QFileInfo(dir).isDir()) dir = QDir::homePath();
    return dir + "/Untitled.txt";
}

void TextBackend::setError(const QString& error) {
    if (m_lastError != error) {
        m_lastError = error;
        emit lastErrorChanged();
    }
}

void TextBackend::newFile() {
    m_filePath.clear();
    m_fileName = "Untitled";
    m_content.clear();
    m_isModified = false;
    m_fileType = "Plain Text";
    updateStats();

    emit fileChanged();
    emit contentChanged();
    emit modifiedChanged();
}

void TextBackend::updateStats() {
    m_lineCount = m_content.count('\n') + 1;
    if (m_content.isEmpty()) {
        m_wordCount = 0;
    } else {
        auto words = m_content.split(QRegularExpression("\\s+"), Qt::SkipEmptyParts);
        m_wordCount = words.size();
    }
    emit statsChanged();
}

void TextBackend::detectFileType() {
    if (m_filePath.isEmpty()) {
        m_fileType = "Plain Text";
        return;
    }

    QFileInfo fi(m_filePath);
    QString ext = fi.suffix().toLower();
    QString name = fi.fileName().toLower();

    if (ext == "cpp" || ext == "hpp" || ext == "cc" || ext == "c" || ext == "h") m_fileType = "C/C++";
    else if (ext == "py") m_fileType = "Python";
    else if (ext == "sh" || ext == "bash" || ext == "zsh") m_fileType = "Shell Script";
    else if (ext == "qml") m_fileType = "QML";
    else if (ext == "js" || ext == "ts") m_fileType = "JavaScript";
    else if (ext == "rs") m_fileType = "Rust";
    else if (ext == "json") m_fileType = "JSON";
    else if (ext == "md" || ext == "markdown") m_fileType = "Markdown";
    else if (ext == "conf" || ext == "ini" || ext == "cfg") m_fileType = "Configuration";
    else if (ext == "yaml" || ext == "yml") m_fileType = "YAML";
    else if (ext == "toml") m_fileType = "TOML";
    else if (ext == "html" || ext == "htm") m_fileType = "HTML";
    else if (ext == "css") m_fileType = "CSS";
    else if (name == "makefile" || name == "cmakelists.txt") m_fileType = "Build Script";
    else m_fileType = "Plain Text";
}

} // namespace b1air
