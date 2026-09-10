#include <QColor>
#include "notes_backend.hpp"
#include <QDateTime>
#include <QTextStream>
#include <QStandardPaths>
#include <QRegularExpression>
#include <QUuid>
#include <iostream>

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

    QFileInfoList localFiles = localDir.entryInfoList(QStringList() << "*.md", QDir::Files, QDir::Time);
    for (const auto& fi : localFiles) {
        QFile file(fi.absoluteFilePath());
        if (file.open(QIODevice::ReadOnly | QIODevice::Text)) {
            QTextStream in(&file);
            QString content = in.readAll();
            
            NoteItem note;
            note.id = fi.baseName();
            note.title = fi.baseName();
            note.content = content;
            note.modified = fi.lastModified().toString("MMM d, hh:mm");
            note.source = "local";
            note.filePath = fi.absoluteFilePath();
            
            // Extract tags e.g. #ideas #todo
            QRegularExpression tagRe("#([a-zA-Z0-9_-]+)");
            auto matchIt = tagRe.globalMatch(content);
            while (matchIt.hasNext()) {
                note.tags.append(matchIt.next().captured(0));
            }

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
    } else if (m_currentId.isEmpty()) {
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
            note.id = "obs_" + fi.baseName();
            note.title = fi.baseName();
            note.content = content;
            note.modified = fi.lastModified().toString("MMM d, hh:mm");
            note.source = "obsidian";
            note.filePath = fi.absoluteFilePath();

            QRegularExpression tagRe("#([a-zA-Z0-9_-]+)");
            auto matchIt = tagRe.globalMatch(content);
            while (matchIt.hasNext()) {
                note.tags.append(matchIt.next().captured(0));
            }

            m_notes.append(note);
        }
    }
}

void NotesBackend::selectNote(const QString& id) {
    m_currentId = id;
    emit currentNoteChanged();
}

void NotesBackend::createNote(const QString& title) {
    NoteItem note;
    note.id = "note_" + QString::number(QDateTime::currentSecsSinceEpoch());
    note.title = title.isEmpty() ? "Untitled Note" : title;
    note.content = "# " + note.title + "\n\nStart writing notes, ideas, or todo lists here...\n\n- [ ] Task 1\n- [ ] Task 2\n\n#ideas #b1air";
    note.tags << "#ideas" << "#b1air";
    note.modified = QDateTime::currentDateTime().toString("MMM d, hh:mm");
    note.source = "local";
    note.filePath = m_storageDir + "/notes/" + note.id + ".md";

    QFile file(note.filePath);
    if (file.open(QIODevice::WriteOnly | QIODevice::Text)) {
        QTextStream out(&file);
        out << note.content;
    }

    m_notes.prepend(note);
    m_currentId = note.id;

    emit notesChanged();
    emit currentNoteChanged();
}

void NotesBackend::saveCurrentNote(const QString& title, const QString& content, const QString& tags) {
    for (auto& n : m_notes) {
        if (n.id == m_currentId) {
            n.title = title;
            n.content = content;
            n.tags = tags.split(",", Qt::SkipEmptyParts);
            for (auto& t : n.tags) t = t.trimmed();
            n.modified = QDateTime::currentDateTime().toString("MMM d, hh:mm");

            // Write to file
            if (!n.filePath.isEmpty()) {
                QFile file(n.filePath);
                if (file.open(QIODevice::WriteOnly | QIODevice::Text)) {
                    QTextStream out(&file);
                    out << content;
                }
            }
            break;
        }
    }

    emit notesChanged();
    emit currentNoteChanged();
}

void NotesBackend::deleteNote(const QString& id) {
    for (int i = 0; i < m_notes.size(); ++i) {
        if (m_notes[i].id == id) {
            if (!m_notes[i].filePath.isEmpty()) {
                QFile::remove(m_notes[i].filePath);
            }
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
        m_syncStatus = "No Obsidian vault. Set obsidianVault in "
                       + m_storageDir + "/config.json";
        emit syncStatusChanged();
        return;
    }

    m_syncStatus = "Syncing Obsidian…";
    emit syncStatusChanged();
    loadNotes();
    m_syncStatus = "Synced with " + m_obsidianVault;
    emit syncStatusChanged();
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
