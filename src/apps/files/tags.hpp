#pragma once

#include <QString>
#include <QStringList>
#include <QVariantMap>

namespace b1air::tags {

/**
 * Colour tags on files, as a desktop's file manager has them: Red, Orange,
 * Yellow, Green, Blue, Purple, Gray.
 *
 * Kept on the file itself, in the extended attribute user.xdg.tags (comma
 * separated) — the freedesktop name Dolphin and KDE use, so a tag set in one
 * shows in the other. A small index (~/.config/b1air/tags.json) lists the
 * files tagged from here, so the sidebar can show "every Red file" without
 * walking the disk; an entry whose file lost the tag (or the file) is dropped
 * the next time it is read.
 */
const QStringList& colours();
QStringList read(const QString& path);
bool write(const QString& path, const QStringList& tags);
/** Add or remove `tag` on every path: removed if all of them have it. */
bool toggle(const QStringList& paths, const QString& tag);
/** The files that have `tag` now. */
QStringList pathsWith(const QString& tag);
/** {tag: count} for the sidebar. */
QVariantMap counts();

} // namespace b1air::tags
