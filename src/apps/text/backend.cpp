#include "backend.hpp"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>
#include <QSet>
#include <QStandardPaths>
#include <QTextStream>
#include <QUrl>
#include <QUuid>

namespace b1air {

// ── The tabs ─────────────────────────────────────────────────────────────────

QString TextTabs::Doc::name() const {
    return path.isEmpty() ? QStringLiteral("Untitled") : QFileInfo(path).fileName();
}

int TextTabs::rowCount(const QModelIndex& parent) const {
    return parent.isValid() ? 0 : int(m_docs.size());
}

QVariant TextTabs::data(const QModelIndex& index, int role) const {
    if (!index.isValid() || index.row() >= int(m_docs.size())) return {};
    const Doc& d = m_docs[size_t(index.row())];
    switch (role) {
    case DocIdRole: return d.id;
    case NameRole: return d.name();
    case PathRole: return d.path;
    case ModifiedRole: return d.modified();
    }
    return {};
}

QHash<int, QByteArray> TextTabs::roleNames() const {
    return {{DocIdRole, "docId"}, {NameRole, "name"}, {PathRole, "path"}, {ModifiedRole, "modified"}};
}

int TextTabs::indexOf(const QString& id) const {
    for (size_t i = 0; i < m_docs.size(); ++i)
        if (m_docs[i].id == id) return int(i);
    return -1;
}

int TextTabs::indexOfPath(const QString& path) const {
    for (size_t i = 0; i < m_docs.size(); ++i)
        if (!path.isEmpty() && m_docs[i].path == path) return int(i);
    return -1;
}

void TextTabs::append(Doc doc) {
    const int row = int(m_docs.size());
    beginInsertRows(QModelIndex(), row, row);
    m_docs.push_back(std::move(doc));
    endInsertRows();
    emit countChanged();
}

void TextTabs::remove(int row) {
    if (row < 0 || row >= int(m_docs.size())) return;
    beginRemoveRows(QModelIndex(), row, row);
    m_docs.erase(m_docs.begin() + row);
    endRemoveRows();
    emit countChanged();
}

void TextTabs::changed(int row) {
    if (row >= 0 && row < int(m_docs.size())) emit dataChanged(index(row), index(row));
}

// ── Files ────────────────────────────────────────────────────────────────────

namespace {

QString typeOf(const QString& path) {
    if (path.isEmpty()) return QStringLiteral("Plain Text");
    const QFileInfo fi(path);
    const QString ext = fi.suffix().toLower();
    const QString name = fi.fileName().toLower();
    if (ext == "cpp" || ext == "hpp" || ext == "cc" || ext == "c" || ext == "h") return "C/C++";
    if (ext == "py") return "Python";
    if (ext == "sh" || ext == "bash" || ext == "zsh") return "Shell Script";
    if (ext == "qml") return "QML";
    if (ext == "js" || ext == "ts") return "JavaScript";
    if (ext == "rs") return "Rust";
    if (ext == "json") return "JSON";
    if (ext == "md" || ext == "markdown") return "Markdown";
    if (ext == "conf" || ext == "ini" || ext == "cfg") return "Configuration";
    if (ext == "yaml" || ext == "yml") return "YAML";
    if (ext == "toml") return "TOML";
    if (ext == "html" || ext == "htm") return "HTML";
    if (ext == "css") return "CSS";
    if (name == "makefile" || name == "cmakelists.txt") return "Build Script";
    return "Plain Text";
}

bool readText(const QString& path, QString* out, QString* error) {
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        if (error) *error = file.errorString();
        return false;
    }
    QTextStream in(&file);
    *out = in.readAll();
    return true;
}

bool writeText(const QString& path, const QString& text, QString* error) {
    QDir().mkpath(QFileInfo(path).absolutePath());
    // QSaveFile writes beside the target and renames over it on commit, so a
    // full disk or a crash mid-write leaves the old file intact instead of a
    // truncated one.
    QSaveFile file(path);
    // A writable file in a directory we cannot create files in (some of
    // /etc, a shared folder) can still be written in place.
    file.setDirectWriteFallback(true);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Text)) {
        if (error) *error = file.errorString();
        return false;
    }
    {
        QTextStream out(&file);
        out << text;
    }
    if (!file.commit()) {
        if (error) *error = file.errorString();
        return false;
    }
    return true;
}

} // namespace

TextBackend::TextBackend(QObject* parent) : QObject(parent), m_tabs(new TextTabs(this)) {
    // What is typed is written to the session a second after typing stops,
    // so a crash or a power cut loses at most that second.
    m_saveTimer.setSingleShot(true);
    m_saveTimer.setInterval(1000);
    connect(&m_saveTimer, &QTimer::timeout, this, &TextBackend::saveSession);
    if (auto* app = QCoreApplication::instance())
        connect(app, &QCoreApplication::aboutToQuit, this, &TextBackend::saveSession);
}

TextBackend::~TextBackend() {
    if (m_saveTimer.isActive()) saveSession();
}

QString TextBackend::newId() {
    return QUuid::createUuid().toString(QUuid::WithoutBraces).left(12);
}

TextTabs::Doc* TextBackend::current() {
    auto& docs = m_tabs->docs();
    return m_current >= 0 && m_current < int(docs.size()) ? &docs[size_t(m_current)] : nullptr;
}

const TextTabs::Doc* TextBackend::current() const {
    const auto& docs = m_tabs->docs();
    return m_current >= 0 && m_current < int(docs.size()) ? &docs[size_t(m_current)] : nullptr;
}

QString TextBackend::currentId() const { return current() ? current()->id : QString(); }
QString TextBackend::filePath() const { return current() ? current()->path : QString(); }
QString TextBackend::fileName() const { return current() ? current()->name() : QStringLiteral("Untitled"); }
bool TextBackend::isModified() const { return current() && current()->modified(); }
QString TextBackend::fileType() const { return typeOf(filePath()); }

bool TextBackend::isModifiedAt(int index) const {
    const auto& docs = m_tabs->docs();
    return index >= 0 && index < int(docs.size()) && docs[size_t(index)].modified();
}

void TextBackend::setCurrentIndex(int i) {
    if (i < 0 || i >= m_tabs->count() || i == m_current) return;
    m_current = i;
    currentWasChanged();
    scheduleSave();
}

void TextBackend::currentWasChanged() {
    updateStats();
    emit currentChanged();
    emit fileChanged();
    emit modifiedChanged();
}

QString TextBackend::contentOf(const QString& id) const {
    const int i = m_tabs->indexOf(id);
    return i >= 0 ? m_tabs->docs()[size_t(i)].content : QString();
}

void TextBackend::setContentOf(const QString& id, const QString& content) {
    const int i = m_tabs->indexOf(id);
    if (i < 0) return;
    TextTabs::Doc& d = m_tabs->docs()[size_t(i)];
    if (d.content == content) return;
    const bool was = d.modified();
    d.content = content;
    d.draftWritten = false;
    if (d.modified() != was) {
        m_tabs->changed(i);
        if (i == m_current) emit modifiedChanged();
    }
    if (i == m_current) updateStats();
    scheduleSave();
}

int TextBackend::cursorOf(const QString& id) const {
    const int i = m_tabs->indexOf(id);
    return i >= 0 ? m_tabs->docs()[size_t(i)].cursor : 0;
}

void TextBackend::setCursorOf(const QString& id, int position) {
    const int i = m_tabs->indexOf(id);
    if (i < 0 || m_tabs->docs()[size_t(i)].cursor == position) return;
    m_tabs->docs()[size_t(i)].cursor = position;
    scheduleSave();
}

void TextBackend::newFile() {
    TextTabs::Doc d;
    d.id = newId();
    m_tabs->append(std::move(d));
    m_current = m_tabs->count() - 1;
    currentWasChanged();
    scheduleSave();
}

bool TextBackend::openFile(const QString& path) {
    // A file:// URI (what xdg-open passes for %U) is percent-encoded:
    // cutting the scheme off left "%20" where the spaces were.
    QString clean = path.startsWith("file://") ? QUrl(path).toLocalFile() : path;
    if (clean.startsWith("~/")) clean = QDir::homePath() + clean.mid(1);
    clean = QFileInfo(clean).absoluteFilePath();

    // Open already: that tab, as it is (its changes are not thrown away).
    if (const int at = m_tabs->indexOfPath(clean); at >= 0) {
        setCurrentIndex(at);
        return true;
    }

    TextTabs::Doc d;
    d.id = newId();
    d.path = clean;
    QString error;
    if (readText(clean, &d.content, &error)) {
        d.saved = d.content;
        d.onDisk = true;
    } else if (QFileInfo::exists(clean)) {
        setError("Could not open " + clean + ": " + error);
        return false;
    }
    // A path that does not exist yet is a new file to be written there,
    // the way `b1air-text notes.txt` works in any editor.

    // An empty Untitled tab in front — the one a new window starts with —
    // is replaced rather than left behind the file.
    if (const TextTabs::Doc* c = current(); c && c->path.isEmpty() && c->content.isEmpty()) {
        const int replaced = m_current;
        m_tabs->append(std::move(d));
        m_current = m_tabs->count() - 1;
        m_tabs->remove(replaced);
        m_current = m_tabs->count() - 1;
    } else {
        m_tabs->append(std::move(d));
        m_current = m_tabs->count() - 1;
    }
    setError(QString());
    currentWasChanged();
    scheduleSave();
    return true;
}

bool TextBackend::saveFile(const QString& path) {
    TextTabs::Doc* d = current();
    if (!d) return false;
    QString target = path.isEmpty() ? d->path : path;
    if (target.startsWith("file://")) target = QUrl(target).toLocalFile();
    if (target.isEmpty()) {
        setError("This file has no name yet — choose where to save it.");
        emit saved(false);
        return false;
    }
    if (target.startsWith("~/")) target = QDir::homePath() + target.mid(1);
    target = QFileInfo(target).absoluteFilePath();

    QString error;
    if (!writeText(target, d->content, &error)) {
        setError("Could not save " + target + ": " + error);
        emit saved(false);
        return false;
    }
    d->path = target;
    d->saved = d->content;
    d->onDisk = true;
    m_tabs->changed(m_current);
    setError(QString());
    emit fileChanged();
    emit modifiedChanged();
    emit saved(true);
    scheduleSave();
    return true;
}

void TextBackend::closeTab(int index) {
    if (index < 0 || index >= m_tabs->count()) return;
    m_tabs->remove(index);
    if (m_tabs->count() == 0) {
        m_current = -1;
        newFile();   // a window always has a tab to type in
        return;
    }
    if (m_current >= index) m_current = std::max(0, m_current - 1);
    if (m_current >= m_tabs->count()) m_current = m_tabs->count() - 1;
    currentWasChanged();
    scheduleSave();
}

void TextBackend::revertCurrent() {
    TextTabs::Doc* d = current();
    if (!d || !d->modified()) return;
    // Read again: what is on disk now, which another program may have
    // changed since it was opened.
    if (d->onDisk) {
        QString text, error;
        if (readText(d->path, &text, &error)) d->saved = text;
    }
    d->content = d->saved;
    d->draftWritten = false;
    m_tabs->changed(m_current);
    emit contentReset(d->id);
    emit modifiedChanged();
    updateStats();
    scheduleSave();
}

QString TextBackend::suggestedPath() const {
    if (!filePath().isEmpty()) return filePath();
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

void TextBackend::updateStats() {
    const QString text = current() ? current()->content : QString();
    m_lineCount = int(text.count('\n')) + 1;
    // Counted in one pass, on every key: split() made a list of every word
    // in the file to take its length.
    m_wordCount = 0;
    bool inWord = false;
    for (const QChar c : text) {
        const bool space = c.isSpace();
        if (!space && !inWord) ++m_wordCount;
        inWord = !space;
    }
    emit statsChanged();
}

// ── The session ──────────────────────────────────────────────────────────────
//
// ~/.local/state/b1air/text: session.json names the tabs, in order, and the
// one in front; drafts/<id>.txt holds the text of each tab that differs from
// its file (or has none). The file itself is never written but by Save, so
// after a restart both are there: the edit, in its tab, and the version on
// disk, which "Revert" goes back to.

QString TextBackend::stateDir() const {
    QString base = QStandardPaths::writableLocation(QStandardPaths::GenericStateLocation);
    if (base.isEmpty()) base = QDir::homePath() + "/.local/state";
    return base + "/b1air/text";
}

void TextBackend::scheduleSave() { m_saveTimer.start(); }

void TextBackend::saveSession() {
    m_saveTimer.stop();
    const QString dir = stateDir();
    const QString drafts = dir + "/drafts";
    QDir().mkpath(drafts);

    QJsonArray tabs;
    QSet<QString> keep;
    for (TextTabs::Doc& d : m_tabs->docs()) {
        // An empty Untitled tab is nothing to come back to.
        if (d.path.isEmpty() && d.content.isEmpty()) continue;
        QJsonObject t{{"id", d.id}, {"path", d.path}, {"cursor", d.cursor}};
        if (d.modified()) {
            const QString file = d.id + ".txt";
            keep.insert(file);
            if (!d.draftWritten) {
                QString error;
                d.draftWritten = writeText(drafts + "/" + file, d.content, &error);
            }
            t.insert("draft", file);
        }
        tabs.append(t);
    }
    // Drafts of tabs closed or saved since.
    for (const QString& f : QDir(drafts).entryList({"*.txt"}, QDir::Files))
        if (!keep.contains(f)) QFile::remove(drafts + "/" + f);

    int current = 0;
    for (int i = 0, shown = 0; i < m_tabs->count(); ++i) {
        const TextTabs::Doc& d = m_tabs->docs()[size_t(i)];
        if (d.path.isEmpty() && d.content.isEmpty()) continue;
        if (i == m_current) current = shown;
        ++shown;
    }
    QSaveFile f(dir + "/session.json");
    if (f.open(QIODevice::WriteOnly)) {
        f.write(QJsonDocument(QJsonObject{{"current", current}, {"tabs", tabs}}).toJson(QJsonDocument::Compact));
        f.commit();
    }
}

void TextBackend::restoreSession() {
    const QString dir = stateDir();
    QFile f(dir + "/session.json");
    if (f.open(QIODevice::ReadOnly)) {
        const QJsonObject root = QJsonDocument::fromJson(f.readAll()).object();
        for (const QJsonValue& v : root.value("tabs").toArray()) {
            const QJsonObject t = v.toObject();
            TextTabs::Doc d;
            d.id = t.value("id").toString();
            if (d.id.isEmpty() || m_tabs->indexOf(d.id) >= 0) d.id = newId();
            d.path = t.value("path").toString();
            d.cursor = t.value("cursor").toInt();
            QString error;
            if (!d.path.isEmpty() && readText(d.path, &d.saved, &error)) d.onDisk = true;
            const QString draft = t.value("draft").toString();
            QString text;
            if (!draft.isEmpty() && readText(dir + "/drafts/" + draft, &text, nullptr)) {
                d.content = text;
                d.draftWritten = true;
                // Kept under the id it was written as.
                d.id = draft.chopped(4);
            } else if (d.onDisk) {
                d.content = d.saved;
            } else {
                continue;   // its file is gone and nothing was kept of it
            }
            m_tabs->append(std::move(d));
        }
        m_current = std::clamp(root.value("current").toInt(), 0, std::max(0, m_tabs->count() - 1));
    }
    if (m_tabs->count() == 0) {
        newFile();
        return;
    }
    currentWasChanged();
}

} // namespace b1air
