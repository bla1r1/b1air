#include <QColor>
#include "notes_backend.hpp"
#include <QDateTime>
#include <QTextStream>
#include <QStandardPaths>
#include <QRegularExpression>
#include <QUuid>
#include <QSaveFile>
#include <QProcess>
#include <QCoreApplication>
#include <QTemporaryFile>
#include <iostream>
#include <algorithm>

NotesBackend::NotesBackend(QObject* parent) : QObject(parent) {
    ensureStorageDir();
    loadConfig();
    loadNotes();
}

void NotesBackend::ensureStorageDir() {
    m_storageDir = QDir::homePath() + "/.local/share/b1air-notes";
    QDir dir(m_storageDir);
    if (!dir.exists()) {
        dir.mkpath(".");
    }

    if (m_obsidianVault.isEmpty()) {
        QString defaultObs = QDir::homePath() + "/Documents/Obsidian";
        QDir obsDir(defaultObs);
        if (obsDir.exists()) {
            m_obsidianVault = defaultObs;
        }
    }
}

void NotesBackend::loadConfig() {
    QFile file(m_storageDir + "/config.json");
    if (file.open(QIODevice::ReadOnly)) {
        QJsonDocument doc = QJsonDocument::fromJson(file.readAll());
        QJsonObject obj = doc.object();
        m_obsidianVault = obj["obsidianVault"].toString();
        m_notionToken = obj["notionToken"].toString();
        m_notionDbId = obj["notionDbId"].toString();
    }
}

void NotesBackend::saveConfig() {
    QJsonObject obj;
    obj["obsidianVault"] = m_obsidianVault;
    obj["notionToken"] = m_notionToken;
    obj["notionDbId"] = m_notionDbId;

    QFile file(m_storageDir + "/config.json");
    if (file.open(QIODevice::WriteOnly)) {
        file.setPermissions(QFileDevice::ReadOwner | QFileDevice::WriteOwner);
        file.write(QJsonDocument(obj).toJson());
    }
}

QVariantList NotesBackend::noteList() const {
    QVariantList list;
    for (const auto& n : m_notes) {
        QVariantMap map;
        map["id"] = n.id;
        map["title"] = n.title;
        map["content"] = n.content;
        map["tags"] = n.tags;
        map["modified"] = n.modified;
        map["source"] = n.source;
        map["snippet"] = n.content.left(80).replace("\n", " ");
        list.append(map);
    }
    return list;
}

QString NotesBackend::currentTitle() const {
    for (const auto& n : m_notes) {
        if (n.id == m_currentId) return n.title;
    }
    return "";
}

QString NotesBackend::currentContent() const {
    for (const auto& n : m_notes) {
        if (n.id == m_currentId) return n.content;
    }
    return "";
}

QString NotesBackend::currentTags() const {
    for (const auto& n : m_notes) {
        if (n.id == m_currentId) return n.tags.join(", ");
    }
    return "";
}

void NotesBackend::loadNotes() {
    m_notes.clear();

    // 1. Scan Local Notes Directory
    QDir localDir(m_storageDir + "/notes");
    if (!localDir.exists()) localDir.mkpath(".");

    // Notes from before titles were file names are "note_<seconds>.md"; give
    // each the name of its first heading, which is what its title was.
    static const QRegularExpression legacyName("^note_\\d+(_\\d+)?$");
    for (const QFileInfo& fi : localDir.entryInfoList({"*.md"}, QDir::Files)) {
        if (!legacyName.match(fi.completeBaseName()).hasMatch()) continue;
        QFile f(fi.absoluteFilePath());
        if (!f.open(QIODevice::ReadOnly | QIODevice::Text)) continue;
        const QString first = QString::fromUtf8(f.readLine()).trimmed();
        f.close();
        if (!first.startsWith("# ")) continue;
        QFile::rename(fi.absoluteFilePath(), freeNotePath(localDir.absolutePath(), first.mid(2)));
    }

    QFileInfoList localFiles = localDir.entryInfoList(QStringList() << "*.md", QDir::Files, QDir::Time);
    for (const auto& fi : localFiles) {
        QFile file(fi.absoluteFilePath());
        if (file.open(QIODevice::ReadOnly | QIODevice::Text)) {
            QTextStream in(&file);
            QString content = in.readAll();
            
            NoteItem note;
            note.id = "local_" + fi.completeBaseName();
            note.title = fi.completeBaseName();
            note.content = content;
            note.modified = fi.lastModified().toString("MMM d, hh:mm");
            note.source = "local";
            note.filePath = fi.absoluteFilePath();
            
            note.tags = tagsIn(content);

            m_notes.append(note);
        }
    }

    // 2. Scan Obsidian Vault if exists
    if (!m_obsidianVault.isEmpty() && QDir(m_obsidianVault).exists()) {
        scanObsidianVault();
    }

    // If empty, create a welcome note
    if (m_notes.isEmpty()) {
        createNote("Getting Started with b1air-notes");
    } else if (std::none_of(m_notes.cbegin(), m_notes.cend(),
                            [this](const NoteItem& n) { return n.id == m_currentId; })) {
        // Nothing selected, or the selected note was renamed on disk since.
        m_currentId = m_notes[0].id;
    }

    emit notesChanged();
    emit currentNoteChanged();
}

void NotesBackend::scanObsidianVault() {
    QDir obsDir(m_obsidianVault);
    QFileInfoList files = obsDir.entryInfoList(QStringList() << "*.md", QDir::Files, QDir::Time);
    for (const auto& fi : files) {
        QFile file(fi.absoluteFilePath());
        if (file.open(QIODevice::ReadOnly | QIODevice::Text)) {
            QTextStream in(&file);
            QString content = in.readAll();

            NoteItem note;
            note.id = "obs_" + fi.completeBaseName();
            note.title = fi.completeBaseName();
            note.content = content;
            note.modified = fi.lastModified().toString("MMM d, hh:mm");
            note.source = "obsidian";
            note.filePath = fi.absoluteFilePath();

            note.tags = tagsIn(content);

            m_notes.append(note);
        }
    }
}

void NotesBackend::selectNote(const QString& id) {
    m_currentId = id;
    emit currentNoteChanged();
}

void NotesBackend::createNote(const QString& title) {
    // The first note anyone sees explains itself; every note after that
    // starts empty. Each used to be the same "Task 1 / Task 2 / #ideas"
    // template, which then had to be deleted line by line.
    const bool welcome = m_notes.isEmpty();
    NoteItem note;
    // Milliseconds plus a counter: two notes made within one second had the
    // same id, and the second one's file replaced the first.
    static int counter = 0;
    note.id = "note_" + QString::number(QDateTime::currentMSecsSinceEpoch()) + "_" + QString::number(++counter);
    note.title = title.trimmed().isEmpty() ? "Untitled" : title.trimmed();
    note.content = welcome
        ? "# " + note.title + "\n\nStart writing notes, ideas, or todo lists here...\n\n- [ ] Task 1\n- [ ] Task 2\n\n#ideas #b1air"
        : QString();
    note.tags = tagsIn(note.content);
    note.modified = QDateTime::currentDateTime().toString("MMM d, hh:mm");
    note.source = "local";
    // The file is named after the title, the way Obsidian names its notes:
    // the title is read back from the file name, so it survives a restart.
    note.filePath = freeNotePath(m_storageDir + "/notes", note.title);
    note.title = QFileInfo(note.filePath).completeBaseName();

    QSaveFile file(note.filePath);
    if (file.open(QIODevice::WriteOnly | QIODevice::Text)) {
        file.write(note.content.toUtf8());
        file.commit();
    }

    m_notes.prepend(note);
    m_currentId = note.id;

    emit notesChanged();
    emit currentNoteChanged();
}

QStringList NotesBackend::tagsIn(const QString& content) {
    QStringList tags;
    static const QRegularExpression tagRe("(?:^|\\s)(#[\\p{L}\\p{N}_/-]+)");
    auto it = tagRe.globalMatch(content);
    while (it.hasNext()) {
        const QString t = it.next().captured(1);
        if (!tags.contains(t)) tags.append(t);
    }
    return tags;
}

// A title as a file name: no path separators or characters other systems
// refuse, not hidden, not empty.
QString NotesBackend::safeFileTitle(const QString& title) {
    QString t = title.trimmed();
    static const QRegularExpression bad(R"([/\\:*?"<>|\x00-\x1f])");
    t.replace(bad, "-");
    while (t.startsWith('.')) t.remove(0, 1);
    if (t.size() > 120) t.truncate(120);
    return t.isEmpty() ? QStringLiteral("Untitled") : t;
}

QString NotesBackend::freeNotePath(const QString& dir, const QString& title, const QString& except) {
    const QString base = safeFileTitle(title);
    QString path = dir + "/" + base + ".md";
    for (int i = 2; QFileInfo::exists(path) && path != except; ++i)
        path = dir + "/" + base + " " + QString::number(i) + ".md";
    return path;
}

void NotesBackend::saveCurrentNote(const QString& title, const QString& content, const QString& tags) {
    Q_UNUSED(tags)  // tags are the #hashtags in the text; see tagsIn()
    for (auto& n : m_notes) {
        if (n.id != m_currentId) continue;
        const bool changed = n.content != content || n.title != title.trimmed();
        if (!changed) return;   // re-saving identical text rewrote the file and reset the editor
        n.content = content;
        n.tags = tagsIn(content);
        n.modified = QDateTime::currentDateTime().toString("MMM d, hh:mm");

        if (!n.filePath.isEmpty()) {
            // A new title renames the file; that is where the title lives.
            // It was only kept in memory, so every renamed note came back
            // after a restart as "note_1790853781".
            const QString wanted = safeFileTitle(title);
            if (wanted != QFileInfo(n.filePath).completeBaseName()) {
                const QString dir = QFileInfo(n.filePath).absolutePath();
                const QString target = freeNotePath(dir, wanted, n.filePath);
                if (QFile::rename(n.filePath, target)) n.filePath = target;
            }
            n.title = QFileInfo(n.filePath).completeBaseName();

            QSaveFile file(n.filePath);
            if (file.open(QIODevice::WriteOnly | QIODevice::Text)) {
                file.write(content.toUtf8());
                if (!file.commit()) {
                    m_syncStatus = "Could not save " + n.filePath;
                    emit syncStatusChanged();
                }
            }
        }
        break;
    }
    // The list (titles, snippets) changes; the editor's own text does not
    // need re-binding, so currentNoteChanged is not emitted for an edit.
    emit notesChanged();
}

void NotesBackend::deleteNote(const QString& id) {
    for (int i = 0; i < m_notes.size(); ++i) {
        if (m_notes[i].id == id) {
            // To the trash, like the file manager's delete, so a note removed
            // by mistake — including one in an Obsidian vault — comes back.
            const QString path = m_notes[i].filePath;
            if (!path.isEmpty() && QProcess::execute("gio", {"trash", path}) != 0)
                QFile::remove(path);
            m_notes.removeAt(i);
            break;
        }
    }

    if (!m_notes.isEmpty()) {
        m_currentId = m_notes[0].id;
    } else {
        m_currentId = "";
    }

    emit notesChanged();
    emit currentNoteChanged();
}

void NotesBackend::setObsidianVault(const QString& path) {
    m_obsidianVault = path;
    saveConfig();
    emit obsidianVaultChanged();
    loadNotes();
}

void NotesBackend::setNotionCredentials(const QString& token, const QString& dbId) {
    m_notionToken = token;
    m_notionDbId = dbId;
    saveConfig();
    emit notionConfigChanged();
}

void NotesBackend::syncWithObsidian() {
    // Without a vault this used to reload the local notes and report
    // "Obsidian Synced" — a success message for something it had not done.
    if (m_obsidianVault.isEmpty()) {
        chooseObsidianVault();
        return;
    }

    m_syncStatus = "Syncing Obsidian…";
    emit syncStatusChanged();
    loadNotes();
    m_syncStatus = "Synced with " + m_obsidianVault;
    emit syncStatusChanged();
}

void NotesBackend::chooseObsidianVault() {
    const QString out = QDir::tempPath() + "/b1air-notes-vault-" + QString::number(QCoreApplication::applicationPid());
    QFile::remove(out);
    auto* proc = new QProcess(this);
    connect(proc, &QProcess::finished, this, [this, proc, out](int, QProcess::ExitStatus) {
        QFile f(out);
        if (f.open(QIODevice::ReadOnly)) {
            const QString path = QString::fromUtf8(f.readAll()).trimmed();
            if (!path.isEmpty()) {
                setObsidianVault(path);
                m_syncStatus = "Obsidian vault: " + path;
                emit syncStatusChanged();
            }
        }
        QFile::remove(out);
        proc->deleteLater();
    });
    connect(proc, &QProcess::errorOccurred, this, [this, proc](QProcess::ProcessError e) {
        if (e != QProcess::FailedToStart) return;
        m_syncStatus = "Could not start b1air-files to choose a folder";
        emit syncStatusChanged();
        proc->deleteLater();
    });
    const QString start = m_obsidianVault.isEmpty() ? QDir::homePath() + "/Documents" : m_obsidianVault;
    proc->start("b1air-files", {"--pick-folder", out, QDir(start).exists() ? start : QDir::homePath()});
}

void NotesBackend::syncWithNotion() {
    // Nothing in the window sets these, so the message has to say where they
    // come from — otherwise the button is silent and there is no way to learn
    // what it wants.
    if (!isNotionConfigured()) {
        m_syncStatus = "Notion not configured. Add notionToken and notionDbId to "
                       + m_storageDir + "/config.json";
        emit syncStatusChanged();
        return;
    }

    m_syncStatus = "Syncing with Notion…";
    emit syncStatusChanged();

    QUrl url("https://api.notion.com/v1/databases/" + m_notionDbId + "/query");
    QNetworkRequest req(url);
    req.setHeader(QNetworkRequest::ContentTypeHeader, "application/json");
    req.setRawHeader("Authorization", ("Bearer " + m_notionToken).toUtf8());
    req.setRawHeader("Notion-Version", "2022-06-28");

    QNetworkReply* reply = m_netManager.post(req, "{}");
    connect(reply, &QNetworkReply::finished, [this, reply]() {
        if (reply->error() == QNetworkReply::NoError) {
            m_syncStatus = "Notion Synced";
        } else {
            m_syncStatus = "Notion Sync Error: " + reply->errorString();
        }
        emit syncStatusChanged();
        reply->deleteLater();
    });
}

namespace {

/**
 * A colour from the palette the caller passed, or the built-in fallback.
 *
 * The renderer used to carry fourteen Tokyo Night hex values, so the one part
 * of the desktop that renders a document ignored the theme picker entirely:
 * pick Catppuccin and every note stayed Tokyo Night. Settings/Themes has
 * offered creation, import and export since this suite gained them.
 *
 * The fallbacks are exactly the values they replace, so a caller that passes
 * nothing renders precisely as before.
 */
QString paletteColor(const QVariantMap& p, const char* key, const char* fallback) {
    const QVariant v = p.value(QLatin1String(key));
    if (v.isValid()) {
        const QColor c = v.value<QColor>();
        if (c.isValid())
            return c.name(QColor::HexRgb);
    }
    return QString::fromLatin1(fallback);
}

/** The same, as a CSS rgba() so a border can be a tint of the accent. */
QString paletteRgba(const QVariantMap& p, const char* key, const char* fallback, double alpha) {
    const QColor c(paletteColor(p, key, fallback));
    return QStringLiteral("rgba(%1,%2,%3,%4)")
        .arg(c.red()).arg(c.green()).arg(c.blue()).arg(alpha);
}

} // namespace

QString NotesBackend::renderMarkdownToHtml(const QString& markdown, const QVariantMap& palette) {
    const QString h1     = paletteColor(palette, "heading1", "#7aa2f7");
    const QString h2     = paletteColor(palette, "heading2", "#bb9af7");
    const QString h3     = paletteColor(palette, "heading3", "#7dcfff");
    const QString body   = paletteColor(palette, "body",     "#c0caf5");
    const QString dim    = paletteColor(palette, "dim",      "#a9b1d6");
    const QString strong = paletteColor(palette, "strong",   "#ffffff");
    const QString accent = paletteColor(palette, "accent",   "#7aa2f7");
    const QString done   = paletteColor(palette, "done",     "#73daca");
    const QString codeBg = paletteColor(palette, "codeBg",   "#16161e");
    const QString codeFg = paletteColor(palette, "codeFg",   "#73daca");
    const QString inlBg  = paletteColor(palette, "inlineBg", "#24283b");
    const QString inlFg  = paletteColor(palette, "inlineFg", "#ff9e64");
    const QString rule   = paletteRgba(palette, "accent",    "#7aa2f7", 0.2);

    QString html = markdown;
    // HTML escape
    html.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;");

    // Headers
    html.replace(QRegularExpression("^### (.*)$", QRegularExpression::MultilineOption),
                 "<h3 style='color:" + h3 + ";margin:8px 0;'>\\1</h3>");
    html.replace(QRegularExpression("^## (.*)$", QRegularExpression::MultilineOption),
                 "<h2 style='color:" + h2 + ";margin:10px 0;'>\\1</h2>");
    html.replace(QRegularExpression("^# (.*)$", QRegularExpression::MultilineOption),
                 "<h1 style='color:" + h1 + ";margin:12px 0;border-bottom:1px solid " + rule + ";padding-bottom:4px;'>\\1</h1>");

    // Checkboxes
    html.replace(QRegularExpression("^- \\[x\\] (.*)$", QRegularExpression::MultilineOption),
                 "<p style='color:" + dim + ";margin:4px 0;'><span style='color:" + done + ";'>&#9745;</span> <strike>\\1</strike></p>");
    html.replace(QRegularExpression("^- \\[ \\] (.*)$", QRegularExpression::MultilineOption),
                 "<p style='color:" + body + ";margin:4px 0;'><span style='color:" + accent + ";'>&#9744;</span> \\1</p>");

    // Bullets
    html.replace(QRegularExpression("^- (.*)$", QRegularExpression::MultilineOption),
                 "<li style='color:" + body + ";margin:2px 0;'>\\1</li>");

    // Bold & Italic
    html.replace(QRegularExpression("\\*\\*(.*?)\\*\\*"), "<strong style='color:" + strong + ";'>\\1</strong>");
    html.replace(QRegularExpression("\\*(.*?)\\*"), "<em style='color:" + h2 + ";'>\\1</em>");

    // Code blocks
    html.replace(QRegularExpression("```([a-zA-Z]*)\n([\\s\\S]*?)```"),
                 "<pre style='background:" + codeBg + ";padding:8px;border-radius:6px;color:" + codeFg
                     + ";font-family:monospace;border:1px solid " + rule + ";'><code>\\2</code></pre>");
    html.replace(QRegularExpression("`([^`]+)`"),
                 "<code style='background:" + inlBg + ";padding:2px 6px;border-radius:4px;color:" + inlFg
                     + ";font-family:monospace;'>\\1</code>");

    // Tags.
    //
    // Anchored to a line start or whitespace on purpose. Unanchored, this rule
    // runs last and happily matches the hex colours in the style attributes
    // every rule above just emitted — `color:#7aa2f7;` became a tag span, which
    // tore the surrounding tag apart and dumped raw CSS into the rendered note:
    //
    //     #7aa2f7;margin:12px 0;border-bottom:...'>Getting Started
    //
    // A real tag is always preceded by a line start or a space; a colour in a
    // style attribute never is.
    //
    // No background on the span, either. It was styled as a rounded chip —
    // background, padding, border-radius — and Qt's rich text supports none of
    // those on an inline span. What it does support is the background colour,
    // so the chip rendered as a flat rectangular highlight tight around the
    // text: the exact look of selected text, on a line nobody had selected.
    html.replace(QRegularExpression("(^|\\s)#([a-zA-Z0-9_-]+)", QRegularExpression::MultilineOption),
                 "\\1<span style='color:" + accent + ";font-weight:600;'>#\\2</span>");

    // Newlines to <br>, then back out of the ones that are not line breaks.
    //
    // Every rule above turns a line into a *block* element — <p>, <h1>, <li>,
    // <pre> — and a block already ends its own line and carries its own
    // margins. Replacing the newline after one with <br/> stacked a whole
    // empty line box on top of those margins, and a blank line in the markdown
    // stacked a second: two consecutive checkbox items rendered 67px apart in
    // a 13px font. The preview looked double-spaced against an editor pane
    // showing the same lines adjacent.
    //
    // A newline between two pieces of plain text is still a line break, which
    // is why this is a subtraction rather than dropping the rule.
    html.replace("\n", "<br/>");
    static const QRegularExpression afterBlock(
        "(</(?:p|h1|h2|h3|li|pre|blockquote)>)(?:<br/>)+");
    static const QRegularExpression beforeBlock(
        "(?:<br/>)+(<(?:p|h1|h2|h3|li|pre|blockquote)[ >])");
    html.replace(afterBlock, "\\1");
    html.replace(beforeBlock, "\\1");

    return "<div style='font-family:sans-serif;color:" + body + ";font-size:13px;line-height:1.6;'>"
           + html + "</div>";
}
