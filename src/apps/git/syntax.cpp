#include "syntax.hpp"

#include <QFileInfo>
#include <QSet>

namespace syntax {

namespace {

struct Lang {
    QStringList lineComments;
    QString blockOpen, blockClose;
    QString quotes;                // characters that open a string
    QString multilineQuotes;       // of those, the ones whose strings span lines
    bool tripleQuotes = false;     // Python's """ and '''
    bool tags = false;             // <name in HTML and XML
    bool dollarVars = false;       // $NAME and ${NAME} in shell
    bool capsTypes = true;         // Capitalised names coloured as types
    QSet<QString> keywords;
};

QSet<QString> words(const char* list) {
    QSet<QString> set;
    for (const auto& w : QString::fromLatin1(list).split(' ', Qt::SkipEmptyParts)) set.insert(w);
    return set;
}

const QSet<QString>& cFamily() {
    static const QSet<QString> s = words(
        "auto break case char const continue default do double else enum extern float for goto if inline int long "
        "register return short signed sizeof static struct switch typedef union unsigned void volatile while bool "
        "true false nullptr NULL class public private protected virtual override final template typename namespace "
        "using new delete this operator friend explicit constexpr consteval constinit noexcept static_cast "
        "dynamic_cast reinterpret_cast const_cast try catch throw mutable decltype concept requires co_await "
        "co_return co_yield signals slots emit Q_OBJECT Q_PROPERTY Q_INVOKABLE "
        "include define ifdef ifndef endif elif pragma undef "
        "package import interface extends implements abstract synchronized instanceof super throws final "
        "fun val var when object companion data sealed internal is in out lateinit by "
        "func let guard defer fileprivate open extension protocol self Self struct "
        "string object readonly sealed get set value base out ref params async await yield lock "
        "foreach namespace event delegate");
    return s;
}
const QSet<QString>& jsFamily() {
    static const QSet<QString> s = words(
        "var let const function return if else for while do switch case break continue new this typeof instanceof "
        "in of class extends super import export from default try catch finally throw async await yield null "
        "undefined true false delete void static get set as interface type enum implements namespace declare "
        "readonly private public protected abstract keyof infer is satisfies "
        "property signal alias required component pragma on");
    return s;
}
const QSet<QString>& pythonWords() {
    static const QSet<QString> s = words(
        "def class return if elif else for while in not and or is None True False import from as with try except "
        "finally raise lambda yield pass break continue global nonlocal async await self cls del assert match case print");
    return s;
}
const QSet<QString>& rustWords() {
    static const QSet<QString> s = words(
        "fn let mut pub struct enum impl trait use mod crate self Self super match if else loop while for in return "
        "as const static ref move where type unsafe async await dyn true false Some None Ok Err break continue extern "
        "macro_rules box i8 i16 i32 i64 i128 isize u8 u16 u32 u64 u128 usize f32 f64 bool char str String Vec Option Result");
    return s;
}
const QSet<QString>& goWords() {
    static const QSet<QString> s = words(
        "func package import var const type struct interface map chan go defer return if else for range switch case "
        "default break continue select nil true false fallthrough goto string int int8 int16 int32 int64 uint uint8 "
        "uint16 uint32 uint64 float32 float64 bool byte rune error any make new len cap append panic recover");
    return s;
}
const QSet<QString>& shellWords() {
    static const QSet<QString> s = words(
        "if then else elif fi for while until do done case esac in function return local export set unset source "
        "exit readonly declare shift trap eval exec break continue true false end begin switch not and or");
    return s;
}
const QSet<QString>& cmakeWords() {
    static const QSet<QString> s = words(
        "if else elseif endif foreach endforeach while endwhile function endfunction macro endmacro return set unset "
        "option project add_executable add_library add_subdirectory add_custom_command add_custom_target "
        "target_link_libraries target_include_directories target_compile_definitions target_compile_options "
        "target_sources find_package find_program find_library include install message cmake_minimum_required "
        "list string file configure_file pkg_check_modules AND OR NOT ON OFF TRUE FALSE PUBLIC PRIVATE INTERFACE REQUIRED");
    return s;
}
const QSet<QString>& dataWords() {
    static const QSet<QString> s = words("true false null yes no on off True False None");
    return s;
}

const Lang* langFor(const QString& fileName) {
    const QFileInfo fi(fileName);
    const QString name = fi.fileName();
    const QString ext = fi.suffix().toLower();

    static const Lang c{{"//"}, "/*", "*/", "\"'", "", false, false, false, true, cFamily()};
    static const Lang js{{"//"}, "/*", "*/", "\"'`", "`", false, false, false, true, jsFamily()};
    static const Lang css{{}, "/*", "*/", "\"'", "", false, false, false, false, words("important media import from to")};
    static const Lang py{{"#"}, "", "", "\"'", "", true, false, false, true, pythonWords()};
    static const Lang rs{{"//"}, "/*", "*/", "\"", "\"", false, false, false, true, rustWords()};
    static const Lang go{{"//"}, "/*", "*/", "\"'`", "`", false, false, false, true, goWords()};
    static const Lang sh{{"#"}, "", "", "\"'", "\"'", false, false, true, false, shellWords()};
    static const Lang cmake{{"#"}, "", "", "\"", "\"", false, false, true, false, cmakeWords()};
    static const Lang data{{"#"}, "", "", "\"'", "", false, false, false, false, dataWords()};
    static const Lang json{{"//"}, "", "", "\"", "", false, false, false, false, dataWords()};
    static const Lang xml{{}, "<!--", "-->", "\"'", "\"'", false, true, false, false, {}};
    static const Lang lua{{"--"}, "", "", "\"'", "", false, false, false, true,
                          words("and break do else elseif end false for function goto if in local nil not or repeat return then true until while")};
    static const Lang sql{{"--"}, "/*", "*/", "'\"", "", false, false, false, false,
                          words("select from where insert into values update set delete create table index drop alter "
                                "join left right inner outer on and or not null primary key foreign references as order "
                                "by group having limit offset distinct union all SELECT FROM WHERE INSERT INTO VALUES "
                                "UPDATE SET DELETE CREATE TABLE INDEX DROP ALTER JOIN LEFT RIGHT INNER OUTER ON AND OR "
                                "NOT NULL PRIMARY KEY FOREIGN REFERENCES AS ORDER BY GROUP HAVING LIMIT OFFSET DISTINCT UNION ALL")};

    static const QSet<QString> cExt = words("c h cc cpp cxx hpp hh hxx ino m mm java kt kts cs swift dart scala groovy gradle php glsl frag vert hlsl proto");
    static const QSet<QString> jsExt = words("js mjs cjs jsx ts tsx qml vue svelte");
    static const QSet<QString> shExt = words("sh bash zsh fish ksh install");
    static const QSet<QString> dataExt = words("yml yaml toml ini conf cfg desktop service timer socket properties env editorconfig gitignore gitattributes rules");
    static const QSet<QString> xmlExt = words("html htm xml svg xhtml ui qrc plist xsl xsd");

    if (name == "CMakeLists.txt" || ext == "cmake") return &cmake;
    if (name == "PKGBUILD" || name == "Makefile" || name == "makefile" || name == "Dockerfile"
        || name.startsWith(".bash") || name.startsWith(".zsh") || name == ".profile") return &sh;
    if (name.startsWith(".git") || name == ".env") return &data;
    if (cExt.contains(ext)) return &c;
    if (jsExt.contains(ext)) return &js;
    if (ext == "css" || ext == "scss" || ext == "less") return &css;
    if (ext == "py" || ext == "pyi") return &py;
    if (ext == "rs") return &rs;
    if (ext == "go") return &go;
    if (shExt.contains(ext)) return &sh;
    if (ext == "json" || ext == "jsonc" || ext == "json5") return &json;
    if (dataExt.contains(ext)) return &data;
    if (xmlExt.contains(ext)) return &xml;
    if (ext == "lua") return &lua;
    if (ext == "sql") return &sql;
    return nullptr;
}

void escapeInto(QString& out, QChar ch) {
    switch (ch.unicode()) {
    case ' ': out += QLatin1String("&nbsp;"); break;
    case '\t': out += QLatin1String("&nbsp;&nbsp;&nbsp;&nbsp;"); break;
    case '<': out += QLatin1String("&lt;"); break;
    case '>': out += QLatin1String("&gt;"); break;
    case '&': out += QLatin1String("&amp;"); break;
    case '"': out += QLatin1String("&quot;"); break;
    case '\r': break;
    default: out += ch;
    }
}

// Builds the lines, opening a colour again on the next line when a span
// (a block comment, a long string) runs past the end of one.
struct Writer {
    QStringList lines;
    QString line;
    QString open;     // colour of the span open now, or empty

    void begin(const QString& color) {
        end();
        if (color.isEmpty()) return;
        line += QStringLiteral("<font color=\"%1\">").arg(color);
        open = color;
    }
    void end() {
        if (open.isEmpty()) return;
        line += QLatin1String("</font>");
        open.clear();
    }
    void put(QChar ch) {
        if (ch == '\n') {
            const QString color = open;
            end();
            lines << line;
            line.clear();
            if (!color.isEmpty()) begin(color);
            return;
        }
        escapeInto(line, ch);
    }
    void put(const QString& s) { for (QChar ch : s) put(ch); }
    void word(const QString& s, const QString& color) {
        if (color.isEmpty()) { put(s); return; }
        begin(color);
        put(s);
        end();
    }
    QStringList finish() {
        end();
        lines << line;
        return lines;
    }
};

bool isIdentStart(QChar c) { return c.isLetter() || c == '_'; }
bool isIdent(QChar c) { return c.isLetterOrNumber() || c == '_'; }

} // namespace

bool knows(const QString& fileName) {
    return langFor(fileName) != nullptr;
}

QStringList highlight(const QString& text, const QString& fileName, const Palette& p) {
    const Lang* lang = langFor(fileName);
    if (!lang || p.isEmpty()) return {};

    Writer w;
    const int n = text.size();
    int i = 0;
    auto at = [&](int k) { return k < n ? text.at(k) : QChar(); };
    auto startsHere = [&](const QString& token) { return !token.isEmpty() && text.mid(i, token.size()) == token; };

    while (i < n) {
        const QChar c = text.at(i);

        // Comments: to the end of the line, or to the closing token.
        bool comment = false;
        for (const auto& lc : lang->lineComments) {
            // "#" in shell only where a word starts: "$#", "a#b" are not comments.
            if (!startsHere(lc)) continue;
            if (lc == "#" && lang->dollarVars && i > 0 && !text.at(i - 1).isSpace()) continue;
            int e = text.indexOf('\n', i);
            if (e < 0) e = n;
            w.begin(p.comment);
            w.put(text.mid(i, e - i));
            w.end();
            i = e;
            comment = true;
            break;
        }
        if (comment) continue;
        if (startsHere(lang->blockOpen)) {
            int e = text.indexOf(lang->blockClose, i + lang->blockOpen.size());
            e = e < 0 ? n : e + lang->blockClose.size();
            w.begin(p.comment);
            w.put(text.mid(i, e - i));
            w.end();
            i = e;
            continue;
        }

        // Strings, with backslash escapes; one-line kinds stop at the newline.
        if (lang->quotes.contains(c)) {
            const bool triple = lang->tripleQuotes && at(i + 1) == c && at(i + 2) == c;
            const QString close = triple ? QString(3, c) : QString(c);
            const bool multiline = triple || lang->multilineQuotes.contains(c);
            int j = i + close.size();
            while (j < n) {
                const QChar d = text.at(j);
                if (d == '\\' && c != '\'' ) { j += 2; continue; }
                if (d == '\\' && c == '\'' && !lang->dollarVars) { j += 2; continue; }
                if (d == '\n' && !multiline) break;
                if (text.mid(j, close.size()) == close) { j += close.size(); break; }
                ++j;
            }
            j = qMin(j, n);
            w.begin(p.string);
            w.put(text.mid(i, j - i));
            w.end();
            i = j;
            continue;
        }

        // A tag's name in HTML and XML.
        if (lang->tags && c == '<' && (isIdentStart(at(i + 1)) || at(i + 1) == '/')) {
            int j = i + 1;
            if (at(j) == '/') ++j;
            while (j < n && (isIdent(text.at(j)) || text.at(j) == ':' || text.at(j) == '-' || text.at(j) == '.')) ++j;
            w.put(text.mid(i, 1));
            w.word(text.mid(i + 1, j - i - 1), p.keyword);
            i = j;
            continue;
        }

        // $NAME, ${NAME} in shell.
        if (lang->dollarVars && c == '$' && (isIdentStart(at(i + 1)) || at(i + 1) == '{')) {
            int j = i + 1;
            if (at(j) == '{') {
                const int e = text.indexOf('}', j);
                j = e < 0 ? n : e + 1;
            } else {
                while (j < n && isIdent(text.at(j))) ++j;
            }
            w.word(text.mid(i, j - i), p.type);
            i = j;
            continue;
        }

        // Numbers: digits with what may follow them (0x1F, 1.5e3, 10u, 1_000).
        if (c.isDigit() && (i == 0 || !isIdent(text.at(i - 1)))) {
            int j = i + 1;
            while (j < n && (text.at(j).isLetterOrNumber() || text.at(j) == '.' || text.at(j) == '_')) ++j;
            w.word(text.mid(i, j - i), p.number);
            i = j;
            continue;
        }

        if (isIdentStart(c)) {
            int j = i + 1;
            while (j < n && isIdent(text.at(j))) ++j;
            const QString word = text.mid(i, j - i);
            // A preprocessor line's word after '#'.
            const bool directive = i > 0 && text.at(i - 1) == '#' && lang->lineComments.contains("//");
            QString color;
            if (lang->keywords.contains(word) || directive) color = p.keyword;
            else if (lang->capsTypes && word.at(0).isUpper() && word.size() > 1) color = p.type;
            w.word(word, color);
            i = j;
            continue;
        }

        w.put(c);
        ++i;
    }
    QStringList lines = w.finish();
    // A file ending in a newline has no line after it.
    if (text.endsWith('\n') && !lines.isEmpty() && lines.last().isEmpty()) lines.removeLast();
    return lines;
}

} // namespace syntax
