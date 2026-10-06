#pragma once
#include <string>
#include <vector>
#include <cstdint>
#include <sqlite3.h>

namespace b1air {

struct AppStat {
    std::string app_class;
    std::string display_name;
    int64_t total_seconds = 0;
    int count = 0;
};

struct DayStats {
    std::string date;
    int64_t total_active_seconds = 0;
    int64_t total_locked_seconds = 0;
    std::vector<AppStat> apps;
};

class FocusTimeDB {
public:
    FocusTimeDB();
    ~FocusTimeDB();

    bool open(const std::string& custom_path = "");
    void close();

    bool log_interval(int64_t start_ts, int64_t end_ts, const std::string& app_class, const std::string& title, bool is_locked);
    /** Every recorded interval gone (Settings → Privacy). */
    bool forget_all();
    DayStats get_stats_for_date(const std::string& date_str);
    std::string get_stats_json(const std::string& date_str);

    /**
     * Everything the FocusTime window draws, for one day.
     *
     * The window reads `total`, `average`, `yesterday`, `week`, `week_apps`,
     * `week_heatmap`, `month` and `hourly`; `get_stats_json` above emits none
     * of them and calls the day total `total_active_seconds`, so every chart
     * and every headline number in that window came up empty or zero. This is
     * the shape it actually asks for.
     */
    std::string get_dashboard_json(const std::string& date_str,
                                   const std::string& app_class = "");

private:
    // Building blocks of get_dashboard_json, kept private: they answer one
    // aggregate each and mean nothing on their own.
    // `app_class` empty means every application; otherwise every figure is
    // restricted to that one, which is what selecting an app in the window
    // asks for.
    int64_t active_seconds_between(int64_t start_ts, int64_t end_ts,
                                   const std::string& app_class);
    std::vector<int64_t> half_hour_buckets(int64_t day_start,
                                           const std::string& app_class);
    std::vector<AppStat> top_apps_between(int64_t start_ts, int64_t end_ts);

    sqlite3* db_ = nullptr;
    std::string db_path_;

    bool init_schema();
    bool run_migrations();
    std::string default_db_path();
};

} // namespace b1air
