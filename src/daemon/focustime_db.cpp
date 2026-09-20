#include "proc_util.hpp"
#include "focustime_db.hpp"
#include <sys/stat.h>
#include <unistd.h>
#include <cstdlib>
#include <iostream>
#include <sstream>
#include <ctime>
#include <iomanip>
#include <algorithm>

namespace b1air {

FocusTimeDB::FocusTimeDB() {
    db_path_ = default_db_path();
}

FocusTimeDB::~FocusTimeDB() {
    close();
}

std::string FocusTimeDB::default_db_path() {
    const char* home = std::getenv("HOME");
    std::string base = home ? home : "/tmp";
    std::string dir = base + "/.local/share/focustime";
    // Recursive: a fresh account may not have ~/.local/share yet.
    util::mkdir_p(dir);
    return dir + "/focustime.db";
}

bool FocusTimeDB::open(const std::string& custom_path) {
    if (!custom_path.empty()) {
        db_path_ = custom_path;
    }
    if (sqlite3_open(db_path_.c_str(), &db_) != SQLITE_OK) {
        return false;
    }
    return init_schema();
}

void FocusTimeDB::close() {
    if (db_) {
        sqlite3_close(db_);
        db_ = nullptr;
    }
}

bool FocusTimeDB::init_schema() {
    if (!db_) return false;

    const char* schema = 
        "CREATE TABLE IF NOT EXISTS events ("
        "  id INTEGER PRIMARY KEY AUTOINCREMENT,"
        "  start_time INTEGER NOT NULL,"
        "  end_time INTEGER NOT NULL,"
        "  app_class TEXT NOT NULL,"
        "  window_title TEXT,"
        "  duration INTEGER NOT NULL,"
        "  is_locked INTEGER DEFAULT 0"
        ");"
        "CREATE INDEX IF NOT EXISTS idx_events_time ON events(start_time, end_time);"
        "CREATE INDEX IF NOT EXISTS idx_events_app ON events(app_class);";

    char* err = nullptr;
    if (sqlite3_exec(db_, schema, nullptr, nullptr, &err) != SQLITE_OK) {
        if (err) {
            sqlite3_free(err);
        }
        return false;
    }
    return run_migrations();
}

/**
 * One-time cleanup of rows whose app_class is not an app_class.
 *
 * The tracker used to take the focused window's *title* where it meant its
 * app_id, and for a while it recorded a bare workspace number. So the database
 * carries rows filed under "Files — ~ — Files", "Git — DotsFiles",
 * "Text Editor — env.sh — Text Editor", "System Monitor" and "1", and the
 * dashboard lists each of them as a separate application for ever.
 *
 * The rule is narrow on purpose. A Wayland app_id has no whitespace in it —
 * firefox, org.kde.dolphin, b1air-files — so a value containing a space was
 * never one, and neither was a value that is nothing but digits. The tracker's
 * own two sentinels, "Desktop" and "Screen Locked", are spelled out and kept.
 *
 * The rows are deleted rather than relabelled: a title cannot be mapped back to
 * the app_id it belonged to without guessing, and inventing the answer would be
 * worse than losing the hour. It runs once, recorded in `meta`.
 *
 * A one-word title — "Terminal" — is indistinguishable from an app_id and
 * survives. Widening the rule to catch it would mean treating a leading capital
 * as suspicious, and Alacritty's app_id really is "Alacritty".
 */
bool FocusTimeDB::run_migrations() {
    if (!db_) return false;

    const char* meta =
        "CREATE TABLE IF NOT EXISTS meta (key TEXT PRIMARY KEY, value TEXT);";
    if (sqlite3_exec(db_, meta, nullptr, nullptr, nullptr) != SQLITE_OK) return false;

    sqlite3_stmt* st = nullptr;
    bool done = false;
    if (sqlite3_prepare_v2(db_, "SELECT value FROM meta WHERE key='migration_app_class_v1';",
                           -1, &st, nullptr) == SQLITE_OK) {
        done = (sqlite3_step(st) == SQLITE_ROW);
    }
    sqlite3_finalize(st);
    if (done) return true;

    const char* cleanup =
        "DELETE FROM events "
        "WHERE app_class NOT IN ('Desktop','Screen Locked') "
        "  AND ( app_class LIKE '% %' "
        "     OR (app_class GLOB '[0-9]*' AND app_class NOT GLOB '*[^0-9]*') );";
    if (sqlite3_exec(db_, cleanup, nullptr, nullptr, nullptr) != SQLITE_OK) return false;
    const int removed = sqlite3_changes(db_);

    (void)sqlite3_exec(db_,
        "INSERT OR REPLACE INTO meta(key,value) VALUES('migration_app_class_v1','done');",
        nullptr, nullptr, nullptr);

    if (removed > 0) {
        std::cerr << "[b1air-focus] removed " << removed
                  << " screen-time rows filed under a window title instead of an app id\n";
    }
    return true;
}

bool FocusTimeDB::log_interval(int64_t start_ts, int64_t end_ts, const std::string& app_class, const std::string& title, bool is_locked) {
    if (!db_ || end_ts <= start_ts) return false;
    int64_t dur = end_ts - start_ts;

    const char* sql = "INSERT INTO events (start_time, end_time, app_class, window_title, duration, is_locked) VALUES (?, ?, ?, ?, ?, ?);";
    sqlite3_stmt* stmt = nullptr;
    if (sqlite3_prepare_v2(db_, sql, -1, &stmt, nullptr) != SQLITE_OK) {
        return false;
    }

    sqlite3_bind_int64(stmt, 1, start_ts);
    sqlite3_bind_int64(stmt, 2, end_ts);
    sqlite3_bind_text(stmt, 3, app_class.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_text(stmt, 4, title.c_str(), -1, SQLITE_TRANSIENT);
    sqlite3_bind_int64(stmt, 5, dur);
    sqlite3_bind_int(stmt, 6, is_locked ? 1 : 0);

    bool ok = (sqlite3_step(stmt) == SQLITE_DONE);
    sqlite3_finalize(stmt);
    return ok;
}

static std::pair<int64_t, int64_t> get_day_range(const std::string& date_str) {
    // Format "YYYY-MM-DD"
    struct tm tm_start = {};
    if (date_str.size() == 10 && strptime(date_str.c_str(), "%Y-%m-%d", &tm_start)) {
        tm_start.tm_hour = 0;
        tm_start.tm_min = 0;
        tm_start.tm_sec = 0;
        time_t start_ts = mktime(&tm_start);
        return { static_cast<int64_t>(start_ts), static_cast<int64_t>(start_ts + 86400) };
    }

    // Default today
    time_t now = time(nullptr);
    struct tm* l = localtime(&now);
    l->tm_hour = 0;
    l->tm_min = 0;
    l->tm_sec = 0;
    time_t today_start = mktime(l);
    return { static_cast<int64_t>(today_start), static_cast<int64_t>(today_start + 86400) };
}

DayStats FocusTimeDB::get_stats_for_date(const std::string& date_str) {
    DayStats stats;
    auto [start_ts, end_ts] = get_day_range(date_str);

    // The day actually queried, not the argument. get_day_range() falls back to
    // today for an empty or malformed date, but this used to echo the argument
    // back — so `b1air-daemon stats` with no date reported today's numbers under
    // "date": "", and anything reading that field to learn which day it was
    // looking at got nothing. A bad date now normalises to the day that was
    // really used instead of being repeated verbatim.
    {
        char buf[16] = {0};
        time_t day_start = static_cast<time_t>(start_ts);
        struct tm tm_day = {};
        if (localtime_r(&day_start, &tm_day) &&
            strftime(buf, sizeof(buf), "%Y-%m-%d", &tm_day) > 0) {
            stats.date = buf;
        } else {
            stats.date = date_str;
        }
    }

    if (!db_) return stats;

    // Sum active apps
    const char* app_sql = 
        "SELECT app_class, SUM(duration) as total_dur, COUNT(*) as cnt "
        "FROM events "
        "WHERE start_time >= ? AND start_time < ? AND is_locked = 0 AND app_class != 'Screen Locked' "
        "GROUP BY app_class "
        "ORDER BY total_dur DESC;";

    sqlite3_stmt* stmt = nullptr;
    if (sqlite3_prepare_v2(db_, app_sql, -1, &stmt, nullptr) == SQLITE_OK) {
        sqlite3_bind_int64(stmt, 1, start_ts);
        sqlite3_bind_int64(stmt, 2, end_ts);

        while (sqlite3_step(stmt) == SQLITE_ROW) {
            AppStat app;
            const unsigned char* cls = sqlite3_column_text(stmt, 0);
            app.app_class = cls ? reinterpret_cast<const char*>(cls) : "unknown";
            app.display_name = app.app_class;
            app.total_seconds = sqlite3_column_int64(stmt, 1);
            app.count = sqlite3_column_int(stmt, 2);
            stats.total_active_seconds += app.total_seconds;
            stats.apps.push_back(app);
        }
        sqlite3_finalize(stmt);
    }

    // Sum locked time
    const char* lock_sql = 
        "SELECT SUM(duration) FROM events WHERE start_time >= ? AND start_time < ? AND (is_locked = 1 OR app_class = 'Screen Locked');";
    if (sqlite3_prepare_v2(db_, lock_sql, -1, &stmt, nullptr) == SQLITE_OK) {
        sqlite3_bind_int64(stmt, 1, start_ts);
        sqlite3_bind_int64(stmt, 2, end_ts);
        if (sqlite3_step(stmt) == SQLITE_ROW) {
            stats.total_locked_seconds = sqlite3_column_int64(stmt, 0);
        }
        sqlite3_finalize(stmt);
    }

    return stats;
}


std::string FocusTimeDB::get_stats_json(const std::string& date_str) {
    DayStats stats = get_stats_for_date(date_str);

    std::ostringstream ss;
    ss << "{\n";
    ss << "  \"date\": \"" << util::escape_json(stats.date) << "\",\n";
    ss << "  \"total_active_seconds\": " << stats.total_active_seconds << ",\n";
    ss << "  \"total_locked_seconds\": " << stats.total_locked_seconds << ",\n";
    ss << "  \"apps\": [\n";

    for (size_t i = 0; i < stats.apps.size(); ++i) {
        const auto& a = stats.apps[i];
        ss << "    {\n";
        ss << "      \"app_class\": \"" << util::escape_json(a.app_class) << "\",\n";
        ss << "      \"display_name\": \"" << util::escape_json(a.display_name) << "\",\n";
        ss << "      \"total_seconds\": " << a.total_seconds << ",\n";
        ss << "      \"count\": " << a.count << "\n";
        ss << "    }" << (i + 1 < stats.apps.size() ? "," : "") << "\n";
    }

    ss << "  ]\n";
    ss << "}\n";
    return ss.str();
}

// ── Dashboard payload ────────────────────────────────────────────────────────
//
// The FocusTime window was written against a JSON shape nothing produced. It
// reads `total`, `average`, `yesterday`, `week`, `week_apps`, `week_heatmap`,
// `month` and `hourly`, and the only endpoint it could reach — `stats` — emits
// `date`, `total_active_seconds`, `total_locked_seconds` and `apps`. Not one
// key matched, so the window drew 0m everywhere and left the weekly chart, the
// month heatmap and the hourly chart as blank rectangles. Everything below
// exists to answer what that window actually asks for.
//
// Time is bucketed by an event's start: an event is one focused stretch in one
// application, which the tracker already splits when focus changes, so the
// cases where a stretch spans a bucket boundary are both rare and short.

namespace {

std::string iso_date(int64_t ts) {
    char buf[16] = {0};
    time_t t = static_cast<time_t>(ts);
    struct tm tm_v = {};
    if (localtime_r(&t, &tm_v) && strftime(buf, sizeof(buf), "%Y-%m-%d", &tm_v) > 0)
        return buf;
    return "";
}

/** Midnight `days` days away — via mktime, so a DST change does not shift it. */
int64_t day_offset(int64_t day_start, int days) {
    time_t t = static_cast<time_t>(day_start);
    struct tm tm_v = {};
    if (!localtime_r(&t, &tm_v)) return day_start + days * 86400;
    tm_v.tm_mday += days;
    tm_v.tm_hour = 0;
    tm_v.tm_min = 0;
    tm_v.tm_sec = 0;
    tm_v.tm_isdst = -1;
    return static_cast<int64_t>(mktime(&tm_v));
}

/** 0 = Monday … 6 = Sunday, which is the order the week strip is drawn in. */
int weekday_mon0(int64_t day_start) {
    time_t t = static_cast<time_t>(day_start);
    struct tm tm_v = {};
    if (!localtime_r(&t, &tm_v)) return 0;
    return (tm_v.tm_wday + 6) % 7;
}

std::string short_day_name(int64_t day_start) {
    static const char* names[7] = { "Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun" };
    return names[weekday_mon0(day_start)];
}

std::string day_and_month(int64_t day_start) {
    char buf[32] = {0};
    time_t t = static_cast<time_t>(day_start);
    struct tm tm_v = {};
    if (localtime_r(&t, &tm_v) && strftime(buf, sizeof(buf), "%-d %b", &tm_v) > 0)
        return buf;
    return "";
}

} // namespace

int64_t FocusTimeDB::active_seconds_between(int64_t start_ts, int64_t end_ts,
                                            const std::string& app_class) {
    if (!db_) return 0;
    const std::string sql =
        "SELECT COALESCE(SUM(duration), 0) FROM events "
        "WHERE start_time >= ? AND start_time < ? AND is_locked = 0 "
        "AND app_class != 'Screen Locked'"
        + std::string(app_class.empty() ? "" : " AND app_class = ?") + ";";
    sqlite3_stmt* stmt = nullptr;
    int64_t total = 0;
    if (sqlite3_prepare_v2(db_, sql.c_str(), -1, &stmt, nullptr) == SQLITE_OK) {
        sqlite3_bind_int64(stmt, 1, start_ts);
        sqlite3_bind_int64(stmt, 2, end_ts);
        if (!app_class.empty())
            sqlite3_bind_text(stmt, 3, app_class.c_str(), -1, SQLITE_TRANSIENT);
        if (sqlite3_step(stmt) == SQLITE_ROW)
            total = sqlite3_column_int64(stmt, 0);
        sqlite3_finalize(stmt);
    }
    return total;
}

std::vector<int64_t> FocusTimeDB::half_hour_buckets(int64_t day_start,
                                                    const std::string& app_class) {
    // 48 half-hour slots, which is what the window's hourly chart is drawn in.
    std::vector<int64_t> buckets(48, 0);
    if (!db_) return buckets;

    const std::string sql =
        "SELECT start_time, duration FROM events "
        "WHERE start_time >= ? AND start_time < ? AND is_locked = 0 "
        "AND app_class != 'Screen Locked'"
        + std::string(app_class.empty() ? "" : " AND app_class = ?") + ";";
    sqlite3_stmt* stmt = nullptr;
    if (sqlite3_prepare_v2(db_, sql.c_str(), -1, &stmt, nullptr) == SQLITE_OK) {
        sqlite3_bind_int64(stmt, 1, day_start);
        sqlite3_bind_int64(stmt, 2, day_offset(day_start, 1));
        if (!app_class.empty())
            sqlite3_bind_text(stmt, 3, app_class.c_str(), -1, SQLITE_TRANSIENT);
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            const int64_t offset = sqlite3_column_int64(stmt, 0) - day_start;
            const int64_t dur = sqlite3_column_int64(stmt, 1);
            if (offset < 0) continue;
            int slot = static_cast<int>(offset / 1800);
            if (slot < 0) slot = 0;
            if (slot > 47) slot = 47;
            buckets[static_cast<size_t>(slot)] += dur;
        }
        sqlite3_finalize(stmt);
    }
    return buckets;
}

std::vector<AppStat> FocusTimeDB::top_apps_between(int64_t start_ts, int64_t end_ts) {
    std::vector<AppStat> out;
    if (!db_) return out;

    const char* sql =
        "SELECT app_class, SUM(duration) AS total_dur, COUNT(*) AS cnt FROM events "
        "WHERE start_time >= ? AND start_time < ? AND is_locked = 0 "
        "AND app_class != 'Screen Locked' "
        "GROUP BY app_class ORDER BY total_dur DESC;";
    sqlite3_stmt* stmt = nullptr;
    if (sqlite3_prepare_v2(db_, sql, -1, &stmt, nullptr) == SQLITE_OK) {
        sqlite3_bind_int64(stmt, 1, start_ts);
        sqlite3_bind_int64(stmt, 2, end_ts);
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            AppStat a;
            const unsigned char* cls = sqlite3_column_text(stmt, 0);
            a.app_class = cls ? reinterpret_cast<const char*>(cls) : "unknown";
            a.display_name = a.app_class;
            a.total_seconds = sqlite3_column_int64(stmt, 1);
            a.count = sqlite3_column_int(stmt, 2);
            out.push_back(a);
        }
        sqlite3_finalize(stmt);
    }
    return out;
}

static void write_app_array(std::ostringstream& ss,
                            const std::vector<AppStat>& apps,
                            int64_t total) {
    ss << "[";
    for (size_t i = 0; i < apps.size(); ++i) {
        const auto& a = apps[i];
        const int percent = total > 0
            ? static_cast<int>((a.total_seconds * 100 + total / 2) / total) : 0;
        ss << "{\"name\":\"" << util::escape_json(a.display_name) << "\","
           << "\"class\":\"" << util::escape_json(a.app_class) << "\","
           << "\"icon\":\"" << util::escape_json(a.app_class) << "\","
           << "\"seconds\":" << a.total_seconds << ","
           << "\"percent\":" << percent << "}";
        if (i + 1 < apps.size()) ss << ",";
    }
    ss << "]";
}

std::string FocusTimeDB::get_dashboard_json(const std::string& date_str,
                                            const std::string& app_class) {
    auto [target_start, target_end] = get_day_range(date_str);

    const int64_t week_start = day_offset(target_start, -weekday_mon0(target_start));
    const int64_t week_end = day_offset(week_start, 7);

    std::ostringstream ss;
    ss << "{";
    ss << "\"selected_date\":\"" << util::escape_json(iso_date(target_start)) << "\",";

    const int64_t total = active_seconds_between(target_start, target_end, app_class);
    ss << "\"total\":" << total << ",";
    ss << "\"yesterday\":" << active_seconds_between(day_offset(target_start, -1), target_start, app_class) << ",";

    // Averaged over the days that actually have something recorded, not over a
    // flat 30: a machine used four days a week would otherwise report an
    // average that no day ever looked like.
    {
        int64_t sum = 0;
        int days_with_data = 0;
        for (int i = 0; i < 30; ++i) {
            const int64_t d0 = day_offset(target_start, -i);
            const int64_t s = active_seconds_between(d0, day_offset(d0, 1), app_class);
            if (s > 0) { sum += s; ++days_with_data; }
        }
        ss << "\"average\":" << (days_with_data > 0 ? sum / days_with_data : 0) << ",";
    }

    ss << "\"week_range\":\"" << util::escape_json(day_and_month(week_start))
       << " – " << util::escape_json(day_and_month(day_offset(week_start, 6))) << "\",";
    ss << "\"current\":\"\",";

    // ── Selected day ─────────────────────────────────────────────────────────
    const auto day_apps = top_apps_between(target_start, target_end);
    ss << "\"apps\":";
    write_app_array(ss, day_apps, total);
    ss << ",";

    {
        const auto buckets = half_hour_buckets(target_start, app_class);
        ss << "\"hourly\":[";
        for (size_t i = 0; i < buckets.size(); ++i) {
            ss << buckets[i];
            if (i + 1 < buckets.size()) ss << ",";
        }
        ss << "],";
    }

    // ── The week the selected day falls in ───────────────────────────────────
    ss << "\"week\":[";
    for (int i = 0; i < 7; ++i) {
        const int64_t d0 = day_offset(week_start, i);
        const int64_t d1 = day_offset(week_start, i + 1);
        ss << "{\"date\":\"" << util::escape_json(iso_date(d0)) << "\","
           << "\"day\":\"" << short_day_name(d0) << "\","
           << "\"total\":" << active_seconds_between(d0, d1, app_class) << ","
           << "\"is_target\":" << (d0 == target_start ? "true" : "false") << "}";
        if (i < 6) ss << ",";
    }
    ss << "],";

    ss << "\"week_heatmap\":[";
    for (int i = 0; i < 7; ++i) {
        const auto buckets = half_hour_buckets(day_offset(week_start, i), app_class);
        ss << "[";
        for (size_t j = 0; j < buckets.size(); ++j) {
            ss << buckets[j];
            if (j + 1 < buckets.size()) ss << ",";
        }
        ss << "]";
        if (i < 6) ss << ",";
    }
    ss << "],";

    {
        const int64_t week_total = active_seconds_between(week_start, week_end, app_class);
        const auto week_apps = top_apps_between(week_start, week_end);
        ss << "\"week_apps\":";
        write_app_array(ss, week_apps, week_total);
        ss << ",";
    }

    // ── The month the selected day falls in ──────────────────────────────────
    // Padded to a Monday-first grid: the window lays these out seven to a row,
    // so without the leading blanks the 1st would sit under whichever column
    // it happened to land in. Blanks carry total -1, which is the value the
    // delegate already treats as "not a day".
    {
        time_t t = static_cast<time_t>(target_start);
        struct tm tm_v = {};
        localtime_r(&t, &tm_v);
        tm_v.tm_mday = 1;
        tm_v.tm_hour = 0; tm_v.tm_min = 0; tm_v.tm_sec = 0; tm_v.tm_isdst = -1;
        const int64_t month_start = static_cast<int64_t>(mktime(&tm_v));

        struct tm next = tm_v;
        next.tm_mon += 1;
        next.tm_isdst = -1;
        const int64_t month_end = static_cast<int64_t>(mktime(&next));

        ss << "\"month\":[";
        bool first = true;
        const int lead = weekday_mon0(month_start);
        for (int i = 0; i < lead; ++i) {
            if (!first) ss << ",";
            ss << "{\"date\":\"\",\"total\":-1,\"is_target\":false}";
            first = false;
        }
        for (int64_t d0 = month_start; d0 < month_end; d0 = day_offset(d0, 1)) {
            if (!first) ss << ",";
            ss << "{\"date\":\"" << util::escape_json(iso_date(d0)) << "\","
               << "\"total\":" << active_seconds_between(d0, day_offset(d0, 1), app_class) << ","
               << "\"is_target\":" << (d0 == target_start ? "true" : "false") << "}";
            first = false;
        }
        ss << "]";
    }

    ss << "}\n";
    return ss.str();
}

} // namespace b1air
