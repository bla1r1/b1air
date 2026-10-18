#pragma once

#include <QString>
#include <QStringList>

// =============================================================================
// Colours for code in the diff, as GitHub Desktop has them.
//
// A small tokenizer, not a parser: keywords, strings, comments, numbers and
// capitalised names (types, mostly), for the languages people keep in git —
// the C family, JavaScript and QML, Python, Rust, Go, shell, CMake, JSON,
// YAML and TOML, HTML and XML. A whole file is read at once, both sides of a
// diff separately, so a comment or string that runs over several lines is
// coloured on all of them and not only inside the hunk where it starts.
//
// The result is one line of Qt's StyledText per line of the file: <font
// color> spans, the rest escaped, spaces as &nbsp; (StyledText runs spaces
// together) and tabs as four of them.
// =============================================================================

namespace syntax {

struct Palette {
    QString keyword, string, comment, number, type;
    bool isEmpty() const { return keyword.isEmpty(); }
};

/** Whether the file's name says which language it is in. */
bool knows(const QString& fileName);

/** Every line of text, coloured; empty when the language is not known. */
QStringList highlight(const QString& text, const QString& fileName, const Palette& palette);

} // namespace syntax
