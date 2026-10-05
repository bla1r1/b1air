#pragma once
// The desktop theme's colours for native programs (cairo): what Settings →
// Themes writes to ~/.config/b1air/theme.json for the whole suite, with
// Catppuccin Mocha, the built-in palette, wherever the file says nothing.

#include <cstdio>
#include <fstream>
#include <nlohmann/json.hpp>
#include <string>

#include "runtime.hpp"

namespace b1air {

struct Colour {
    double r = 0, g = 0, b = 0;
};

struct Palette {
    Colour ground{0x20 / 255.0, 0x23 / 255.0, 0x26 / 255.0};
    Colour low{0x1b / 255.0, 0x1e / 255.0, 0x20 / 255.0};
    Colour mid{0x29 / 255.0, 0x2c / 255.0, 0x30 / 255.0};
    Colour high{0x31 / 255.0, 0x36 / 255.0, 0x3b / 255.0};
    Colour text{0xfc / 255.0, 0xfc / 255.0, 0xfc / 255.0};
    Colour dim{0xb4 / 255.0, 0xbb / 255.0, 0xc2 / 255.0};
    Colour primary{0x3d / 255.0, 0xae / 255.0, 0xe9 / 255.0};
    Colour tertiary{0xb0 / 255.0, 0x7a / 255.0, 0xd9 / 255.0};
    Colour error{0xed / 255.0, 0x4b / 255.0, 0x5b / 255.0};
    Colour warn{0xfd / 255.0, 0xbc / 255.0, 0x4b / 255.0};
    Colour ok{0x2e / 255.0, 0xcc / 255.0, 0x71 / 255.0};

    static Palette load() {
        Palette p;
        std::ifstream in(home_dir() + "/.config/b1air/theme.json");
        if (!in) return p;
        const auto j = nlohmann::json::parse(in, nullptr, false);
        if (!j.is_object()) return p;
        const auto take = [&](const char* key, Colour& out) {
            if (!j.contains(key) || !j[key].is_string()) return;
            unsigned r = 0, g = 0, b = 0;
            const std::string v = j[key].get<std::string>();
            if (v.size() == 7 && std::sscanf(v.c_str(), "#%02x%02x%02x", &r, &g, &b) == 3) out = {r / 255.0, g / 255.0, b / 255.0};
        };
        take("ground", p.ground);
        take("low", p.low);
        take("mid", p.mid);
        take("high", p.high);
        take("text", p.text);
        take("textDim", p.dim);
        take("primary", p.primary);
        take("tertiary", p.tertiary);
        take("error", p.error);
        take("yellow", p.warn);
        take("green", p.ok);
        return p;
    }
};

} // namespace b1air
