#pragma once
// The shell's translations for native programs: the same JSON files the QML
// reads (Ui/i18n/<lang>.json, the English string as the key), so a string is
// translated once for the whole suite. The language is Settings → Keyboard →
// Interface language (uiLanguage), else the system's (LANGUAGE, LC_ALL,
// LC_MESSAGES, LANG). A missing file or string shows the English.
//
//   b1air::I18n tr;            // loads at construction
//   tr("Capture")              // "Зняти" in Ukrainian
//   tr("%1 ms", "300")         // %1… filled in

#include <cstdlib>
#include <fstream>
#include <nlohmann/json.hpp>
#include <string>
#include <unordered_map>

#include "runtime.hpp"
#include "settings_manager.hpp"

namespace b1air {

class I18n {
public:
    I18n() {
        lang_ = SettingsManager::get_json_string("uiLanguage");
        if (lang_.empty() || lang_ == "system") lang_ = system_language();
        if (lang_.empty() || lang_ == "en") return;
        const std::string main = qml_entry("Main.qml");
        if (main.empty()) return;
        const std::string dir = main.substr(0, main.rfind('/'));
        std::ifstream in(dir + "/Ui/i18n/" + lang_ + ".json");
        if (!in) return;
        const auto j = nlohmann::json::parse(in, nullptr, false);
        if (!j.is_object()) return;
        for (auto it = j.begin(); it != j.end(); ++it)
            if (it.value().is_string()) dict_[it.key()] = it.value().get<std::string>();
    }

    const std::string& language() const { return lang_; }

    std::string operator()(const std::string& english, const std::string& a1 = {}, const std::string& a2 = {}) const {
        const auto it = dict_.find(english);
        std::string s = it != dict_.end() && !it->second.empty() ? it->second : english;
        fill(s, "%1", a1);
        fill(s, "%2", a2);
        return s;
    }

private:
    static std::string system_language() {
        for (const char* var : {"LANGUAGE", "LC_ALL", "LC_MESSAGES", "LANG"}) {
            const char* v = std::getenv(var);
            if (!v || !*v || std::string(v) == "C" || std::string(v) == "POSIX") continue;
            std::string s = v;
            s = s.substr(0, s.find_first_of("_.@:-"));
            for (auto& c : s) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
            return s;
        }
        return "en";
    }
    static void fill(std::string& s, const char* mark, const std::string& value) {
        if (value.empty()) return;
        for (size_t p = s.find(mark); p != std::string::npos; p = s.find(mark, p + value.size()))
            s.replace(p, 2, value);
    }

    std::string lang_;
    std::unordered_map<std::string, std::string> dict_;
};

} // namespace b1air
