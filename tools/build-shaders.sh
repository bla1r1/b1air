#!/usr/bin/env bash
# build-shaders.sh — compile the shell's shaders (src/shell/qml/**/shaders/*.frag)
# to the .qsb files Qt Quick loads, next to them. The .qsb files are in the
# tree, so installing needs no shader compiler; run this after editing a
# .frag, and commit both.
#
#   tools/build-shaders.sh           compile every shader
#   tools/build-shaders.sh --check   exit 1 if a .qsb is missing or stale
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
QSB=""
for c in qsb qsb6 "$(qtpaths6 --query QT_HOST_LIBEXECS 2>/dev/null)/qsb" \
         "$(qtpaths6 --query QT_HOST_BINS 2>/dev/null)/qsb" /usr/lib/qt6/bin/qsb /usr/lib/qt6/libexec/qsb; do
    if command -v "$c" >/dev/null 2>&1; then QSB="$(command -v "$c")"; break; fi
done
[[ -n "$QSB" ]] || { echo "build-shaders: no qsb (Qt Shader Tools) found" >&2; exit 2; }

# GLSL ES and desktop GL for OpenGL, HLSL and MSL for the other backends.
compile() { "$QSB" --glsl "100es,120,150" --hlsl 50 --msl 12 -o "$2" "$1"; }

status=0
while IFS= read -r -d '' frag; do
    qsb="$frag.qsb"
    if [[ "${1:-}" == "--check" ]]; then
        tmp="$(mktemp)"
        compile "$frag" "$tmp"
        if [[ ! -f "$qsb" ]] || ! cmp -s "$tmp" "$qsb"; then
            echo "stale: ${qsb#$ROOT/} (run tools/build-shaders.sh)"
            status=1
        fi
        rm -f "$tmp"
    else
        compile "$frag" "$qsb"
        echo "built: ${qsb#$ROOT/}"
    fi
done < <(find "$ROOT/src/shell/qml" -path '*/shaders/*.frag' -print0 | sort -z)
exit $status
