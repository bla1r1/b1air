#pragma once
// The names of the files in the home folder, for Spotlight.
//
// Spotlight ran `find ~ -maxdepth 5 -iname "*q*"` for every query, under a
// one-and-a-half-second timeout: slow on a full home, and on a big one cut
// off before it had looked everywhere. Here the names are kept in SQLite
// (FTS5, trigrams: any part of a name, Cyrillic as well as Latin, in
// milliseconds), filled once and then kept up to date by looking at which
// folders changed — a folder's mtime moves when anything is added to it,
// taken from it or renamed in it, so only those are read again.
//
// What is left out: hidden files and folders, node_modules and
// __pycache__, other file systems mounted inside the home (a network share
// is not crawled), and symlinks (not followed).
//
//   b1air-daemon files search <query> [limit]   paths, best first
//   b1air-daemon files update                    one pass now
//   b1air-daemon files reindex                   read everything again

#include <string>

namespace b1air::file_index {

/** The indexing thread, for the session's life. Off while "fileIndex" is false. */
void run(const volatile int* running);

/** Print up to `limit` paths for `query`, one a line, best first. */
int search_cli(const std::string& query, int limit);

/** One pass now, in this process: what changed since the last one. */
int update_cli();

/** Forget the index; the running session's thread fills it again. */
int reindex_cli();

} // namespace b1air::file_index
