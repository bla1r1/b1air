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
# Our own changes to swayfx are a patch series, src/swayfx/patches/*.patch,
# applied in name order onto the pinned release (see the README there). The
# installed build records a hash of them, so changing a patch rebuilds.
#
#   tools/build-swayfx.sh            build and install (sudo for the install)
#   tools/build-swayfx.sh --check    exit 0 if the installed build matches
#
# Every source can be pointed elsewhere (a mirror, a local clone):
#   SWAYFX_REPO SWAYFX_REF SCENEFX_REPO SCENEFX_REF WLROOTS_REPO WLROOTS_REF
#   PREFIX (/usr/local)  B1AIR_SWAYFX_SRC (where to build)
set -euo pipefail

SWAYFX_REPO="${SWAYFX_REPO:-https://github.com/WillPower3309/swayfx.git}"
SWAYFX_REF="${SWAYFX_REF:-0.6}"
SCENEFX_REPO="${SCENEFX_REPO:-https://github.com/wlrfx/scenefx.git}"
SCENEFX_REF="${SCENEFX_REF:-0.5}"
WLROOTS_REPO="${WLROOTS_REPO:-https://gitlab.freedesktop.org/wlroots/wlroots.git}"
WLROOTS_REF="${WLROOTS_REF:-0.20.2}"
PREFIX="${PREFIX:-/usr/local}"
SRC="${B1AIR_SWAYFX_SRC:-${XDG_CACHE_HOME:-$HOME/.cache}/b1air/swayfx-src}"

PATCH_DIR="${B1AIR_SWAYFX_PATCHES:-$(cd "$(dirname "$0")/.." && pwd)/src/swayfx/patches}"
shopt -s nullglob
PATCHES=("$PATCH_DIR"/*.patch)
shopt -u nullglob
PATCH_HASH="none"
if [[ ${#PATCHES[@]} -gt 0 ]]; then
    PATCH_HASH="$(cat "${PATCHES[@]}" | sha256sum | cut -c1-12)"
fi

STAMP="$PREFIX/share/b1air/swayfx.stamp"
WANT="swayfx $SWAYFX_REF scenefx $SCENEFX_REF wlroots $WLROOTS_REF patches $PATCH_HASH"

if [[ "${1:-}" == "--check" ]]; then
    [[ -x "$PREFIX/bin/swayfx" && -f "$STAMP" && "$(cat "$STAMP")" == "$WANT" ]]
    exit
fi

as_root() { if [[ -w "$PREFIX" ]]; then "$@"; else sudo "$@"; fi; }
fetch() {   # fetch <repo> <ref> <dir>
    git clone --quiet --depth 1 --branch "$2" -c advice.detachedHead=false "$1" "$3" || {
        echo "build-swayfx: could not fetch $1 at $2" >&2; exit 1; }
}

echo "build-swayfx: $WANT"
rm -rf "$SRC"
mkdir -p "$(dirname "$SRC")"
fetch "$SWAYFX_REPO" "$SWAYFX_REF" "$SRC"
mkdir -p "$SRC/subprojects"
fetch "$SCENEFX_REPO" "$SCENEFX_REF" "$SRC/subprojects/scenefx"
fetch "$WLROOTS_REPO" "$WLROOTS_REF" "$SRC/subprojects/wlroots"

# A patch that no longer applies stops the build here, with its name, rather
# than producing a swayfx that silently lacks it.
for patch in "${PATCHES[@]}"; do
    echo "build-swayfx: applying $(basename "$patch")"
    git -C "$SRC" apply --whitespace=nowarn "$patch" || {
        echo "build-swayfx: $(basename "$patch") does not apply to swayfx $SWAYFX_REF" >&2; exit 1; }
done

# swayfx's meson.build already looks in subprojects/ first (`fallback:`),
# and scenefx, a subproject itself, finds the same wlroots there.
#   libdir, rpath           the private library directory described above
#   force_fallback_for      take the copies even where a matching system
#                           wlroots exists, so every machine runs the same
#   backends drm,libinput   a real session; no nested X11 backend
#   renderers gles2         what sway uses; Vulkan would need glslang to build
LIBDIR="lib/b1air-swayfx"
meson setup "$SRC/build" "$SRC" \
    --prefix="$PREFIX" \
    --libdir="$LIBDIR" \
    --buildtype=release \
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
meson compile -C "$SRC/build"

# Runtime files only: the programs and the two libraries. No wlroots headers
# or .pc land in $PREFIX to be found by something else later.
as_root rm -rf "$PREFIX/$LIBDIR"
as_root meson install -C "$SRC/build" --tags runtime
# The session starts `swayfx` when there is one (usr/bin/b1air-session).
as_root ln -sf sway "$PREFIX/bin/swayfx"
# swayfx's own session entry would sit in the login screen next to b1air's.
as_root rm -f "$PREFIX/share/wayland-sessions/sway.desktop"
as_root mkdir -p "$(dirname "$STAMP")"
echo "$WANT" | as_root tee "$STAMP" >/dev/null

"$PREFIX/bin/swayfx" --version
rm -rf "$SRC"
