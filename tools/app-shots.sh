#!/usr/bin/env bash
# app-shots.sh [build-dir] [out-dir] — a picture of every app, with no
# compositor and no GPU: each runs on Qt's offscreen platform at 1920x1080
# and saves its window (B1AIR_GRAB, src/common/render_backend.hpp), and the
# design gallery (tools/ui-gallery.qml) is drawn beside them. The software
# renderer, so no glass: that needs a look on a screen.
#
# For checking a change to the design system across everything it touches;
# nothing here needs a screen, so it is safe to run inside a session.
set -u
here=$(cd "$(dirname "$0")/.." && pwd)
build=${1:-$here/src/build}
out=${2:-${TMPDIR:-/tmp}/b1air-shots}
mkdir -p "$out"

screen=$(mktemp --suffix=.json)
trap 'rm -f "$screen"' EXIT
cat > "$screen" <<'JSON'
{ "screens": [ { "name": "shots", "x": 0, "y": 0, "width": 1920, "height": 1080,
                 "logicalDpi": 96, "logicalBaseDpi": 96, "dpr": 1 } ] }
JSON

export QT_QPA_PLATFORM="offscreen:configfile=$screen"
export QML_IMPORT_PATH="$build/qml"
# Software: the offscreen platform has no OpenGL to draw into (the apps would
# take it, render_backend.hpp, and grab nothing). Glass draws its plain
# fallback then, as with Reduce Transparency.
export QT_QUICK_BACKEND=software
unset QSG_RHI_BACKEND

shoot() {  # name binary args...
    local name=$1 bin=$2; shift 2
    if [ ! -x "$build/bin/$bin" ]; then echo "  skip $name: no $bin"; return; fi
    if B1AIR_GRAB="$out/$name.png" timeout 30 "$build/bin/$bin" "$@" > "$out/$name.log" 2>&1; then
        backdrop "$out/$name.png"
        echo "  $out/$name.png"
    else
        echo "  FAIL $name (see $out/$name.log)"
    fi
}

# The windows are translucent: on a screen the compositor blurs the
# wallpaper under them. Put one under the pictures the same way, so what is
# judged is what is seen (B1AIR_SHOTS_WALLPAPER, else the first in
# ~/.wallpapers; needs python-pillow, without it they stay as grabbed).
wallpaper=${B1AIR_SHOTS_WALLPAPER:-$(find "$HOME/.wallpapers" -type f \( -iname '*.jpg' -o -iname '*.png' -o -iname '*.webp' \) 2>/dev/null | sort | head -n1)}
backdrop() {  # png
    [ -n "$wallpaper" ] || return 0
    python3 - "$1" "$wallpaper" <<'PY' 2>/dev/null || true
import sys
from PIL import Image, ImageFilter, ImageOps
shot = Image.open(sys.argv[1]).convert("RGBA")
wall = ImageOps.fit(Image.open(sys.argv[2]).convert("RGBA"), shot.size)
# swayfx: blur_passes 3, blur_radius 3 -- about a 12px gaussian
wall = wall.filter(ImageFilter.GaussianBlur(12))
Image.alpha_composite(wall, shot).convert("RGB").save(sys.argv[1])
PY
}

echo "app-shots -> $out"
shoot files    b1air-files    "$HOME"
shoot git      b1air-git      "$here"
shoot text     b1air-text     "$here/README.md"
shoot term     b1air-term
shoot monitor  b1air-monitor
shoot view     b1air-view     "$here/src/shell/qml/assets"
shoot settings b1air-settings --standalone appearance
if command -v qml6 >/dev/null || [ -x /usr/lib/qt6/bin/qml ]; then
    qml=$(command -v qml6 || echo /usr/lib/qt6/bin/qml)
    timeout 30 "$qml" "$here/tools/ui-gallery.qml" -- "$out/gallery.png" > "$out/gallery.log" 2>&1 \
        && echo "  $out/gallery.png" || echo "  FAIL gallery (see $out/gallery.log)"
fi
