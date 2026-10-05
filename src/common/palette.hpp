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
    Colour ground{0x1e / 255.0, 0x1e / 255.0, 0x2e / 255.0};
    Colour low{0x18 / 255.0, 0x18 / 255.0, 0x25 / 255.0};
    Colour mid{0x31 / 255.0, 0x32 / 255.0, 0x44 / 255.0};
    Colour high{0x45 / 255.0, 0x47 / 255.0, 0x5a / 255.0};
    Colour text{0xe0 / 255.0, 0xe5 / 255.0, 0xf8 / 255.0};
    Colour dim{0xaf / 255.0, 0xb6 / 255.0, 0xce / 255.0};
    Colour primary{0x89 / 255.0, 0xb4 / 255.0, 0xfa / 255.0};
    Colour tertiary{0xcb / 255.0, 0xa6 / 255.0, 0xf7 / 255.0};
    Colour error{0xf3 / 255.0, 0x8b / 255.0, 0xa8 / 255.0};
    Colour warn{0xf9 / 255.0, 0xe2 / 255.0, 0xaf / 255.0};
    Colour ok{0xa6 / 255.0, 0xe3 / 255.0, 0xa1 / 255.0};

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
