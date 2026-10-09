#include "file_index.hpp"
#include "proc_util.hpp"
#include "settings_manager.hpp"

#include <sqlite3.h>
#include <dirent.h>
#include <sys/resource.h>
#include <sys/stat.h>
#include <sys/syscall.h>
#include <unistd.h>

#include <algorithm>
#include <chrono>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <string>
#include <thread>
#include <unordered_map>
#include <unordered_set>
#include <vector>

namespace b1air::file_index {
namespace {

constexpr int kPassSeconds = 120;   // how often the folders are looked at again
constexpr int kMaxDepth = 16;

std::string home() {
    const char* h = std::getenv("HOME");
    return h ? h : "/tmp";
}

std::string db_path() {
    const char* cache = std::getenv("XDG_CACHE_HOME");
    const std::string dir = (cache && *cache ? std::string(cache) : home() + "/.cache") + "/b1air";
    util::mkdir_p(dir);
    return dir + "/files-index.db";
}

bool skipped(const char* name) {
    return name[0] == '.' || !std::strcmp(name, "node_modules") || !std::strcmp(name, "__pycache__");
}

// ── SQLite ──────────────────────────────────────────────────────────────────

class Db {
public:
    bool open(bool create) {
        if (sqlite3_open_v2(db_path().c_str(), &db_,
                            create ? SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE : SQLITE_OPEN_READONLY,
                            nullptr) != SQLITE_OK)
            return false;
        sqlite3_busy_timeout(db_, 2000);
        if (!create) return true;
        return exec(
            "PRAGMA journal_mode=WAL;"
            "PRAGMA synchronous=NORMAL;"
            "CREATE TABLE IF NOT EXISTS files("
            "  id INTEGER PRIMARY KEY, path TEXT UNIQUE NOT NULL, dir TEXT NOT NULL,"
            "  name TEXT NOT NULL, lname TEXT NOT NULL, is_dir INTEGER NOT NULL, mtime INTEGER NOT NULL);"
            "CREATE INDEX IF NOT EXISTS files_dir ON files(dir);"
            "CREATE TABLE IF NOT EXISTS dirs(path TEXT PRIMARY KEY, mtime INTEGER NOT NULL);"
            "CREATE VIRTUAL TABLE IF NOT EXISTS names USING fts5("
            "  name, content='files', content_rowid='id', tokenize='trigram');"
            "CREATE TRIGGER IF NOT EXISTS files_ai AFTER INSERT ON files BEGIN"
            "  INSERT INTO names(rowid, name) VALUES (new.id, new.name); END;"
            "CREATE TRIGGER IF NOT EXISTS files_ad AFTER DELETE ON files BEGIN"
            "  INSERT INTO names(names, rowid, name) VALUES ('delete', old.id, old.name); END;");
    }
    ~Db() { if (db_) sqlite3_close(db_); }
    bool exec(const char* sql) { return sqlite3_exec(db_, sql, nullptr, nullptr, nullptr) == SQLITE_OK; }
    sqlite3_stmt* prepare(const char* sql) {
        sqlite3_stmt* s = nullptr;
        sqlite3_prepare_v2(db_, sql, -1, &s, nullptr);
        return s;
    }
    sqlite3* raw() { return db_; }
private:
    sqlite3* db_ = nullptr;
};

struct Stmt {
    sqlite3_stmt* s;
    explicit Stmt(sqlite3_stmt* st) : s(st) {}
    ~Stmt() { sqlite3_finalize(s); }
    Stmt& text(int i, const std::string& v) { sqlite3_bind_text(s, i, v.c_str(), int(v.size()), SQLITE_TRANSIENT); return *this; }
    Stmt& num(int i, long long v) { sqlite3_bind_int64(s, i, v); return *this; }
    bool row() { return sqlite3_step(s) == SQLITE_ROW; }
    void done() { sqlite3_step(s); sqlite3_reset(s); sqlite3_clear_bindings(s); }
    void reset() { sqlite3_reset(s); sqlite3_clear_bindings(s); }
    std::string col_text(int i) { const auto* t = sqlite3_column_text(s, i); return t ? reinterpret_cast<const char*>(t) : ""; }
    long long col_num(int i) { return sqlite3_column_int64(s, i); }
};

// ── Ranking ─────────────────────────────────────────────────────────────────

// Lower case for comparing names: ASCII, Latin-1 and Cyrillic, the scripts
// names here are written in. UTF-8 in, UTF-8 out.
std::string fold(const std::string& s) {
    std::string out;
    out.reserve(s.size());
    for (size_t i = 0; i < s.size();) {
        unsigned char c = s[i];
        if (c < 0x80) { out += char(c >= 'A' && c <= 'Z' ? c + 32 : c); ++i; continue; }
        unsigned cp = 0; int n = 0;
        if ((c & 0xE0) == 0xC0) { cp = c & 0x1F; n = 1; }
        else if ((c & 0xF0) == 0xE0) { cp = c & 0x0F; n = 2; }
        else if ((c & 0xF8) == 0xF0) { cp = c & 0x07; n = 3; }
        else { out += char(c); ++i; continue; }
        if (i + n >= s.size()) { out.append(s, i, std::string::npos); break; }   // cut short
        for (int k = 1; k <= n; ++k) cp = (cp << 6) | (static_cast<unsigned char>(s[i + k]) & 0x3F);
        if (cp >= 0x0410 && cp <= 0x042F) cp += 0x20;          // А-Я
        else if (cp >= 0x0400 && cp <= 0x040F) cp += 0x50;     // Ѐ-Џ (Ё, Є, І, Ї, Ў…)
        else if (cp == 0x0490) cp = 0x0491;                    // Ґ
        else if (cp >= 0xC0 && cp <= 0xDE && cp != 0xD7) cp += 0x20;
        if (cp < 0x800) { out += char(0xC0 | (cp >> 6)); out += char(0x80 | (cp & 0x3F)); }
        else if (cp < 0x10000) { out += char(0xE0 | (cp >> 12)); out += char(0x80 | ((cp >> 6) & 0x3F)); out += char(0x80 | (cp & 0x3F)); }
        else { out += char(0xF0 | (cp >> 18)); out += char(0x80 | ((cp >> 12) & 0x3F)); out += char(0x80 | ((cp >> 6) & 0x3F)); out += char(0x80 | (cp & 0x3F)); }
        i += n + 1;
    }
    return out;
}

size_t utf8_length(const std::string& s) {
    size_t n = 0;
    for (unsigned char c : s) n += (c & 0xC0) != 0x80;
    return n;
}

// ── Crawling ────────────────────────────────────────────────────────────────

class Crawler {
public:
    explicit Crawler(Db& db, const volatile int* running)
        : db_(db), running_(running),
          dir_mtime_(db.prepare("SELECT mtime FROM dirs WHERE path = ?")),
          set_dir_(db.prepare("INSERT INTO dirs(path, mtime) VALUES (?, ?) "
                              "ON CONFLICT(path) DO UPDATE SET mtime = excluded.mtime")),
          children_(db.prepare("SELECT name, is_dir FROM files WHERE dir = ?")),
          subdirs_(db.prepare("SELECT path FROM files WHERE dir = ? AND is_dir = 1")),
          insert_(db.prepare("INSERT OR IGNORE INTO files(path, dir, name, lname, is_dir, mtime) VALUES (?, ?, ?, ?, ?, ?)")),
          remove_(db.prepare("DELETE FROM files WHERE path = ?")),
          remove_tree_(db.prepare("DELETE FROM files WHERE path >= ? AND path < ?")),
          remove_dirs_(db.prepare("DELETE FROM dirs WHERE path = ? OR (path >= ? AND path < ?)")) {}

    void pass() {
        struct stat st{};
        if (stat(home().c_str(), &st) != 0) return;
        dev_ = st.st_dev;
        db_.exec("BEGIN");
        pending_ = 0;
        walk(home(), 0);
        db_.exec("COMMIT");
    }

private:
    bool alive() const { return *running_ && SettingsManager::get_json_bool("fileIndex", true); }

    // Committed every so often, so a search during the first long pass sees
    // what is in so far and the write lock is not held for minutes.
    void tick() {
        if (++pending_ < 2000) return;
        pending_ = 0;
        db_.exec("COMMIT");
        db_.exec("BEGIN");
    }

    void forget_tree(const std::string& path) {
        // Everything under path/: '/' + 1 is '0', the next byte up.
        const std::string lo = path + "/", hi = path + "0";
        remove_.text(1, path).done();
        remove_tree_.text(1, lo).text(2, hi).done();
        remove_dirs_.text(1, path).text(2, lo).text(3, hi).done();
    }

    void walk(const std::string& dir, int depth) {
        if (!*running_ || depth > kMaxDepth) return;
        struct stat st{};
        if (lstat(dir.c_str(), &st) != 0 || !S_ISDIR(st.st_mode) || st.st_dev != dev_) return;
        const long long mtime = static_cast<long long>(st.st_mtim.tv_sec) * 1000 + st.st_mtim.tv_nsec / 1000000;

        long long known = -1;
        dir_mtime_.text(1, dir);
        if (dir_mtime_.row()) known = dir_mtime_.col_num(0);
        dir_mtime_.reset();

        std::vector<std::string> subdirs;
        if (known == mtime) {
            // Nothing added, removed or renamed here: its folders as known.
            subdirs_.text(1, dir);
            while (subdirs_.row()) subdirs.push_back(subdirs_.col_text(0));
            subdirs_.reset();
        } else {
            read_dir(dir, subdirs);
            set_dir_.text(1, dir).num(2, mtime).done();
        }
        // Low and slow: the index is for later, the disk is for now.
        std::this_thread::sleep_for(std::chrono::microseconds(200));
        for (const auto& sub : subdirs) walk(sub, depth + 1);
    }

    void read_dir(const std::string& dir, std::vector<std::string>& subdirs) {
        std::unordered_map<std::string, bool> before;
        children_.text(1, dir);
        while (children_.row()) before.emplace(children_.col_text(0), children_.col_num(1) != 0);
        children_.reset();

        DIR* d = opendir(dir.c_str());
        if (!d) return;
        std::unordered_set<std::string> seen;
        while (dirent* e = readdir(d)) {
            if (!std::strcmp(e->d_name, ".") || !std::strcmp(e->d_name, "..") || skipped(e->d_name)) continue;
            const std::string name = e->d_name;
            const std::string path = dir + "/" + name;
            struct stat st{};
            if (lstat(path.c_str(), &st) != 0) continue;
            const bool is_dir = S_ISDIR(st.st_mode);
            seen.insert(name);
            if (is_dir) subdirs.push_back(path);
            auto it = before.find(name);
            if (it != before.end() && it->second == is_dir) continue;
            if (it != before.end()) forget_tree(path);   // a file became a folder, or back
            insert_.text(1, path).text(2, dir).text(3, name).text(4, fold(name)).num(5, is_dir ? 1 : 0)
                   .num(6, static_cast<long long>(st.st_mtim.tv_sec)).done();
            tick();
        }
        closedir(d);
        for (const auto& [name, was_dir] : before)
            if (!seen.count(name)) { forget_tree(dir + "/" + name); tick(); }
    }

    Db& db_;
    const volatile int* running_;
    dev_t dev_ = 0;
    int pending_ = 0;
    Stmt dir_mtime_, set_dir_, children_, subdirs_, insert_, remove_, remove_tree_, remove_dirs_;
};

} // namespace

void run(const volatile int* running) {
    // Below everything else, for the CPU and for the disk.
    setpriority(PRIO_PROCESS, static_cast<id_t>(syscall(SYS_gettid)), 19);
    constexpr int kIoprioClassIdle = 3, kIoprioWhoProcess = 1;
    syscall(SYS_ioprio_set, kIoprioWhoProcess, static_cast<int>(syscall(SYS_gettid)), kIoprioClassIdle << 13);

    Db db;
    if (!db.open(true)) {
        std::cerr << "[file-index] cannot open " << db_path() << "\n";
        return;
    }
    Crawler crawler(db, running);
    bool wiped = false;
    while (*running) {
        if (SettingsManager::get_json_bool("fileIndex", true)) {
            wiped = false;
            crawler.pass();
        } else if (!wiped) {
            // Turned off: the names go too, not only the updates.
            db.exec("DELETE FROM files; DELETE FROM dirs; INSERT INTO names(names) VALUES ('rebuild'); VACUUM;");
            wiped = true;
        }
        for (int i = 0; i < kPassSeconds && *running; ++i)
            std::this_thread::sleep_for(std::chrono::seconds(1));
    }
}

int search_cli(const std::string& query, int limit) {
    std::string q = query;
    q.erase(0, q.find_first_not_of(" \t"));
    q.erase(q.find_last_not_of(" \t") + 1);
    if (q.empty()) return 0;
    // Off, or not made yet: the caller looks another way.
    if (!SettingsManager::get_json_bool("fileIndex", true)) return 3;
    Db db;
    if (!db.open(false)) return 3;
    {
        Stmt any(db.prepare("SELECT 1 FROM dirs LIMIT 1"));
        if (!any.s || !any.row()) return 3;
    }
    // Trigrams find three letters and more through the index; fewer are a
    // LIKE over the names, still quick for a home's worth.
    const bool trigram = utf8_length(q) >= 3;
    std::string arg;
    if (trigram) {
        arg = "\"";
        for (char c : q) arg += c == '"' ? std::string("\"\"") : std::string(1, c);
        arg += "\"";
    } else {
        // SQLite's LIKE folds only ASCII: the names are kept folded too.
        arg = "%" + fold(q) + "%";
    }
    Stmt find(db.prepare(trigram
        ? "SELECT f.path, f.name, f.is_dir, f.mtime FROM names JOIN files f ON f.id = names.rowid "
          "WHERE names MATCH ? LIMIT 5000"
        : "SELECT path, name, is_dir, mtime FROM files WHERE lname LIKE ? LIMIT 5000"));
    if (!find.s) return 1;
    find.text(1, arg);

    struct Hit { std::string path; int rank; size_t depth; size_t length; long long mtime; };
    std::vector<Hit> hits;
    const std::string fq = fold(q);
    while (find.row()) {
        const std::string name = fold(find.col_text(1));
        Hit h{find.col_text(0), 3, 0, name.size(), find.col_num(3)};
        if (name == fq) h.rank = 0;
        else if (name.rfind(fq, 0) == 0) h.rank = 1;
        else {
            // At the start of a word: "my report" for "rep".
            const size_t at = name.find(fq);
            if (at != std::string::npos && at > 0 && std::strchr(" _-.(", name[at - 1])) h.rank = 2;
        }
        h.depth = static_cast<size_t>(std::count(h.path.begin(), h.path.end(), '/'));
        hits.push_back(std::move(h));
    }
    std::sort(hits.begin(), hits.end(), [](const Hit& a, const Hit& b) {
        if (a.rank != b.rank) return a.rank < b.rank;
        if (a.depth != b.depth) return a.depth < b.depth;
        if (a.length != b.length) return a.length < b.length;
        return a.mtime > b.mtime;
    });
    for (int i = 0; i < limit && i < int(hits.size()); ++i) std::cout << hits[size_t(i)].path << "\n";
    return 0;
}

int update_cli() {
    Db db;
    if (!db.open(true)) return 1;
    static const volatile int always = 1;
    Crawler(db, &always).pass();
    return 0;
}

int reindex_cli() {
    Db db;
    if (!db.open(true)) return 1;
    // The folders forgotten: the next pass reads each one again.
    return db.exec("DELETE FROM dirs") ? 0 : 1;
}

} // namespace b1air::file_index
