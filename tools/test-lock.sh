#!/usr/bin/env bash
# test-lock.sh — b1air-lock's look without a session to lock: lock/look.cpp
# painted to PNGs, one a state (waiting, typed, refused, the menu open, the
# password shown, a portrait screen), over a wallpaper.
#
#   tools/test-lock.sh OUTDIR [WALLPAPER]
#
# Needs g++ and the headers of cairo, fontconfig, libjpeg and libpng; the fonts are the desktop's (Inter, b1air
# Symbols) where fontconfig finds them.
set -euo pipefail
OUT="${1:?usage: test-lock.sh OUTDIR [WALLPAPER]}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WALL="${2:-$ROOT/.wallpapers/Mountains/dawn-ranges.jpg}"
mkdir -p "$OUT"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/preview.cpp" <<'CPP'
#include <cairo.h>
#include <cstdio>
#include <string>
#include "image.hpp"
#include "look.hpp"

int main(int argc, char** argv) {
    const std::string out = argv[1], wall = argv[2];
    struct Scene { const char* name; int w, h; void (*set)(look::View&); };
    const Scene scenes[] = {
        {"idle", 1920, 1080, [](look::View&) {}},
        {"typed", 1920, 1080, [](look::View& v) {
            v.password = "hunter22"; v.status = look::Status::Typing; v.layout = "US";
            v.caps = "Caps Lock is on"; v.finger = "Or touch the fingerprint reader"; }},
        {"denied", 1920, 1080, [](look::View& v) {
            v.password = "x"; v.status = look::Status::Denied; v.message = "Access denied"; v.battery_low = true;
            v.battery = "9%"; v.battery_icon = "󰁺"; }},
        {"menu", 1920, 1080, [](look::View& v) {
            v.menu_open = true; v.pointer = true; v.px = 1700; v.py = 1030; v.avatar = nullptr; }},
        {"reveal", 2560, 1440, [](look::View& v) {
            v.password = "correct horse"; v.reveal = true; v.status = look::Status::Checking; v.message = "Checking…"; }},
        {"portrait", 1080, 1920, [](look::View& v) { v.layout = "UA"; }},
    };
    for (const Scene& s : scenes) {
        cairo_surface_t* wp = cairo_image_surface_create(CAIRO_FORMAT_RGB24, s.w / 12, s.h / 12);
        cairo_surface_flush(wp);
        const bool ok = decode_cover(wall, s.w / 12, s.h / 12, 0x1a1b26,
                                     reinterpret_cast<uint32_t*>(cairo_image_surface_get_data(wp)),
                                     cairo_image_surface_get_stride(wp));
        cairo_surface_mark_dirty(wp);
        look::View v;
        v.width = s.w; v.height = s.h; v.wallpaper = ok ? wp : nullptr;
        v.name = "Alex Doe"; v.clock = "09:41"; v.date = "Saturday, October 17";
        v.placeholder = "Enter password";
        v.weather_icon = "󰖙"; v.weather_temp = "14°";
        v.battery = "73%"; v.battery_icon = "󰂀";
        v.items[0] = "Reboot"; v.items[1] = "Sleep"; v.items[2] = "Shut down";
        s.set(v);
        cairo_surface_t* target = cairo_image_surface_create(CAIRO_FORMAT_RGB24, s.w, s.h);
        cairo_t* cr = cairo_create(target);
        look::Hits hits;
        look::paint(cr, v, hits);
        cairo_destroy(cr);
        cairo_surface_write_to_png(target, (out + "/lock-" + s.name + ".png").c_str());
        cairo_surface_destroy(target);
        cairo_surface_destroy(wp);
        std::printf("%s/lock-%s.png\n", out.c_str(), s.name);
    }
}
CPP

g++ -std=c++20 -O1 -w -I"$ROOT/src/lock" -I"$ROOT/src/bg" -I"$ROOT/src/common" \
    $(pkg-config --cflags cairo fontconfig libjpeg libpng) "$TMP/preview.cpp" "$ROOT/src/lock/look.cpp" "$ROOT/src/bg/image.cpp" \
    $(pkg-config --libs cairo fontconfig libjpeg libpng) $(pkg-config --exists libwebp && echo -DB1AIR_HAVE_WEBP $(pkg-config --libs libwebp)) \
    -o "$TMP/preview"
"$TMP/preview" "$OUT" "$WALL"
