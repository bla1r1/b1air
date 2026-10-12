#!/usr/bin/env bash
# build-xdpw.sh — xdg-desktop-portal-wlr, the screencast portal RustDesk and
# every other screen sharer on sway goes through, with our patches.
#
# The distribution's portal is left installed and untouched. Ours goes to
# $PREFIX/libexec/b1air/ and a drop-in for the user service
# (/etc/systemd/user/xdg-desktop-portal-wlr.service.d/b1air.conf) starts it
# instead; D-Bus activates that service, so everything that asks for the
# portal gets ours. Removing the drop-in brings the stock one back.
#
# Why: 0.8.4 asks the compositor for a second frame on a capture session that
# still has one in flight when a stream pauses and resumes quickly — RustDesk
# does exactly that on every connection — and the protocol error takes the
# portal down: the viewer gets a black screen. src/xdpw/patches/ fixes it.
#
#   tools/build-xdpw.sh            build and install (sudo for the install)
#   tools/build-xdpw.sh --check    exit 0 if the installed build matches
#
#   XDPW_REPO XDPW_REF PREFIX (/usr/local)  B1AIR_XDPW_SRC (where to build)
# Build output goes to B1AIR_XDPW_LOG (~/.cache/b1air/xdpw-build.log).
set -euo pipefail

XDPW_REPO="${XDPW_REPO:-https://github.com/emersion/xdg-desktop-portal-wlr.git}"
XDPW_REF="${XDPW_REF:-v0.8.4}"
PREFIX="${PREFIX:-/usr/local}"
SRC="${B1AIR_XDPW_SRC:-${XDG_CACHE_HOME:-$HOME/.cache}/b1air/xdpw-src}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
shopt -s nullglob
PATCHES=("$ROOT"/src/xdpw/patches/*.patch)
shopt -u nullglob
PATCH_HASH="none"
[[ ${#PATCHES[@]} -gt 0 ]] && PATCH_HASH="$(cat "${PATCHES[@]}" | sha256sum | cut -c1-12)"

BIN="$PREFIX/libexec/b1air/xdg-desktop-portal-wlr"
DROPIN_DIR="/etc/systemd/user/xdg-desktop-portal-wlr.service.d"
STAMP="$PREFIX/share/b1air/xdpw.stamp"
WANT="xdpw $XDPW_REF patches $PATCH_HASH"

if [[ "${1:-}" == "--check" ]]; then
    [[ -x "$BIN" && -f "$DROPIN_DIR/b1air.conf" && -f "$STAMP" && "$(cat "$STAMP")" == "$WANT" ]]
    exit
fi

LOG="${B1AIR_XDPW_LOG:-${XDG_CACHE_HOME:-$HOME/.cache}/b1air/xdpw-build.log}"
mkdir -p "$(dirname "$LOG")"
: > "$LOG"

run() {   # run <what> <command...>: output to the log, its end on failure
    local what="$1"; shift
    echo "build-xdpw: $what"
    "$@" >>"$LOG" 2>&1 && return 0
    echo "build-xdpw: failed while: $what" >&2
    tail -n 30 "$LOG" | sed 's/^/    /' >&2
    exit 1
}
as_root() { if [[ -w "$PREFIX" && -w /etc ]]; then "$@"; else sudo "$@"; fi; }

echo "build-xdpw: $WANT (log: $LOG)"
rm -rf "$SRC"
mkdir -p "$(dirname "$SRC")"
run "fetching xdg-desktop-portal-wlr $XDPW_REF" \
    git clone --quiet --depth 1 --branch "$XDPW_REF" -c advice.detachedHead=false "$XDPW_REPO" "$SRC"
for patch in "${PATCHES[@]}"; do
    run "applying $(basename "$patch")" git -C "$SRC" apply --whitespace=nowarn "$patch"
done
run "configuring" meson setup "$SRC/build" "$SRC" --buildtype=release \
    -Dman-pages=disabled -Dsystemd=disabled
run "compiling" meson compile -C "$SRC/build"

as_root install -Dm755 "$SRC/build/xdg-desktop-portal-wlr" "$BIN"
as_root install -d "$DROPIN_DIR"
printf '%s\n' \
    "# b1air: the portal built by tools/build-xdpw.sh (patched); remove this" \
    "# file to go back to the distribution's." \
    "[Service]" "ExecStart=" "ExecStart=$BIN" \
    | as_root tee "$DROPIN_DIR/b1air.conf" >/dev/null
as_root mkdir -p "$(dirname "$STAMP")"
echo "$WANT" | as_root tee "$STAMP" >/dev/null
rm -rf "$SRC"

# The running portal is the old one until it restarts; a screen share in
# progress drops and its app asks again.
if systemctl --user is-active --quiet xdg-desktop-portal-wlr.service 2>/dev/null; then
    systemctl --user daemon-reload
    systemctl --user restart xdg-desktop-portal-wlr.service && echo "build-xdpw: portal restarted"
else
    systemctl --user daemon-reload 2>/dev/null || true
fi
echo "build-xdpw: done — $BIN"
