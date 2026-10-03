#!/usr/bin/env bash
# build-swayfx.sh — swayfx with its own wlroots and scenefx, the way scroll
# (another sway fork) ships: the compositor builds against copies of its
# libraries placed in its own subprojects/, not against whatever wlroots the
# distribution has. Ubuntu 26.04 carries wlroots 0.19, swayfx 0.6 wants 0.20,
# and the next distribution will be off in some other direction; with the
# copies inside, that stops mattering.
#
# "Its own" still means one known version. wlroots changes its API in every
# minor release, so no compositor builds against "any" wlroots — the versions
# below are the set swayfx $SWAYFX_REF is written for, and they move together.
#
# The two libraries are installed beside the compositor, in a directory of
# their own ($PREFIX/lib/b1air-swayfx) that only this sway looks in (rpath),
# with no headers or pkg-config files: the system's wlroots, and anything
# built on it, are left exactly as they were and cannot pick these up.
# (Not static: scenefx carries copies of a few wlroots internals, which only
# stay apart when each library keeps its own symbols to itself.)
#
# Our own changes are patch series, src/swayfx/patches/*.patch onto swayfx and
# src/scenefx/patches/*.patch onto scenefx, applied in name order onto the
# pinned releases (see the README in src/swayfx). The installed build records
# a hash of them, so changing a patch rebuilds.
#
#   tools/build-swayfx.sh            build and install (sudo for the install)
#   tools/build-swayfx.sh --check    exit 0 if the installed build matches
#
# Every source can be pointed elsewhere (a mirror, a local clone):
#   SWAYFX_REPO SWAYFX_REF SCENEFX_REPO SCENEFX_REF WLROOTS_REPO WLROOTS_REF
#   PREFIX (/usr/local)  B1AIR_SWAYFX_SRC (where to build)
#
# What git, meson and the compiler say goes to a log file
# (B1AIR_SWAYFX_LOG, ~/.cache/b1air/swayfx-build.log), not the terminal: a
# few thousand lines of configure checks and third-party compiler notes in
# the middle of an install read like failures, when nothing failed. A step
# that does fail prints the end of the log and where it is.
# B1AIR_SWAYFX_VERBOSE=1 shows it all as it happens (CI does).
set -euo pipefail

SWAYFX_REPO="${SWAYFX_REPO:-https://github.com/WillPower3309/swayfx.git}"
SWAYFX_REF="${SWAYFX_REF:-0.6}"
SCENEFX_REPO="${SCENEFX_REPO:-https://github.com/wlrfx/scenefx.git}"
SCENEFX_REF="${SCENEFX_REF:-0.5}"
WLROOTS_REPO="${WLROOTS_REPO:-https://gitlab.freedesktop.org/wlroots/wlroots.git}"
WLROOTS_REF="${WLROOTS_REF:-0.20.2}"
PREFIX="${PREFIX:-/usr/local}"
SRC="${B1AIR_SWAYFX_SRC:-${XDG_CACHE_HOME:-$HOME/.cache}/b1air/swayfx-src}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PATCH_DIR="${B1AIR_SWAYFX_PATCHES:-$ROOT/src/swayfx/patches}"
SCENEFX_PATCH_DIR="${B1AIR_SCENEFX_PATCHES:-$ROOT/src/scenefx/patches}"
shopt -s nullglob
PATCHES=("$PATCH_DIR"/*.patch)
SCENEFX_PATCHES=("$SCENEFX_PATCH_DIR"/*.patch)
shopt -u nullglob
PATCH_HASH="none"
if [[ $(( ${#PATCHES[@]} + ${#SCENEFX_PATCHES[@]} )) -gt 0 ]]; then
    PATCH_HASH="$(cat "${PATCHES[@]}" "${SCENEFX_PATCHES[@]}" | sha256sum | cut -c1-12)"
fi

STAMP="$PREFIX/share/b1air/swayfx.stamp"
WANT="swayfx $SWAYFX_REF scenefx $SCENEFX_REF wlroots $WLROOTS_REF patches $PATCH_HASH"

if [[ "${1:-}" == "--check" ]]; then
    [[ -x "$PREFIX/bin/swayfx" && -f "$STAMP" && "$(cat "$STAMP")" == "$WANT" ]]
    exit
fi

LOG="${B1AIR_SWAYFX_LOG:-${XDG_CACHE_HOME:-$HOME/.cache}/b1air/swayfx-build.log}"
mkdir -p "$(dirname "$LOG")"
: > "$LOG"

# run <what> <command...>: the command's output into the log; on failure
# the end of it, and where the rest is.
run() {
    local what="$1"; shift
    echo "build-swayfx: $what"
    if [[ "${B1AIR_SWAYFX_VERBOSE:-0}" == "1" ]]; then
        "$@" 2>&1 | tee -a "$LOG"
        [[ ${PIPESTATUS[0]} -eq 0 ]] && return 0
    elif "$@" >>"$LOG" 2>&1; then
        return 0
    fi
    echo "build-swayfx: failed while: $what" >&2
    echo "build-swayfx: the last lines of $LOG:" >&2
    tail -n 40 "$LOG" | sed 's/^/    /' >&2
    exit 1
}

as_root() { if [[ -w "$PREFIX" ]]; then "$@"; else sudo "$@"; fi; }
fetch() {   # fetch <repo> <ref> <dir>
    run "fetching $(basename "$1" .git) $2" \
        git clone --quiet --depth 1 --branch "$2" -c advice.detachedHead=false "$1" "$3"
}

echo "build-swayfx: $WANT (log: $LOG)"
rm -rf "$SRC"
mkdir -p "$(dirname "$SRC")"
fetch "$SWAYFX_REPO" "$SWAYFX_REF" "$SRC"
mkdir -p "$SRC/subprojects"
fetch "$SCENEFX_REPO" "$SCENEFX_REF" "$SRC/subprojects/scenefx"
fetch "$WLROOTS_REPO" "$WLROOTS_REF" "$SRC/subprojects/wlroots"

# A patch that no longer applies stops the build here, with its name, rather
# than producing a swayfx that silently lacks it.
apply_series() {   # apply_series <dir> <what> <patch>...
    local dir="$1" what="$2" patch; shift 2
    for patch in "$@"; do
        run "applying $(basename "$patch") to $what" \
            git -C "$dir" apply --whitespace=nowarn "$patch"
    done
}
apply_series "$SRC" "swayfx $SWAYFX_REF" "${PATCHES[@]}"
apply_series "$SRC/subprojects/scenefx" "scenefx $SCENEFX_REF" "${SCENEFX_PATCHES[@]}"

# swayfx's meson.build already looks in subprojects/ first (`fallback:`),
# and scenefx, a subproject itself, finds the same wlroots there.
#   libdir, rpath           the private library directory described above
#   force_fallback_for      take the copies even where a matching system
#                           wlroots exists, so every machine runs the same
#   backends drm,libinput   a real session; no nested X11 backend
#   renderers gles2         what sway uses; Vulkan would need glslang to build
#   werror false            a release meeting newer headers than it was written
#                           against warns (Arch's libinput 1.31 added a scroll
#                           method sway's switch does not name); it must still
#                           build, as the distributions build it
LIBDIR="lib/b1air-swayfx"
run "configuring" meson setup "$SRC/build" "$SRC" \
    --prefix="$PREFIX" \
    --libdir="$LIBDIR" \
    --buildtype=release \
    -Dwerror=false \
    -Dc_link_args="-Wl,-rpath,$PREFIX/$LIBDIR" \
    -Dforce_fallback_for=wlroots,scenefx \
    -Dwlroots:examples=false \
    -Dwlroots:backends=drm,libinput \
    -Dwlroots:renderers=gles2 \
    -Dwlroots:xwayland=enabled \
    -Dscenefx:examples=false \
    -Dscenefx:renderers=gles2 \
    -Dman-pages=disabled \
    -Ddefault-wallpaper=false \
    -Dbash-completions=false \
    -Dzsh-completions=false
run "compiling (a few minutes)" meson compile -C "$SRC/build"

# Runtime files only: the programs and the two libraries. No wlroots headers
# or .pc land in $PREFIX to be found by something else later.
as_root rm -rf "$PREFIX/$LIBDIR"
run "installing to $PREFIX" as_root meson install -C "$SRC/build" --tags runtime
# The session starts `swayfx` when there is one (usr/bin/b1air-session).
as_root ln -sf sway "$PREFIX/bin/swayfx"
# swayfx's own session entry would sit in the login screen next to b1air's.
as_root rm -f "$PREFIX/share/wayland-sessions/sway.desktop"
as_root mkdir -p "$(dirname "$STAMP")"
echo "$WANT" | as_root tee "$STAMP" >/dev/null

echo "build-swayfx: done — $("$PREFIX/bin/swayfx" --version)"
rm -rf "$SRC"
