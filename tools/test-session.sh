#!/usr/bin/env bash
# test-session.sh — log in the way the login screen does (b1air-session),
# headless and without a GPU, and check that the desktop came up and answers
# its shortcuts. For a fresh install: run it as the user install.sh set up.
#
#   tools/test-session.sh
#
# Keys are pressed with tools/vkb (a virtual keyboard sending real keycodes,
# so the config's --to-code bindings match). What is drawn is not looked at;
# what runs and what sway reports is.
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
RT="$(mktemp -d)"; chmod 700 "$RT"
VKB="$RT/vkb"
"$here/vkb/build.sh" "$VKB" || { echo "test-session: could not build vkb" >&2; exit 2; }

export XDG_RUNTIME_DIR="$RT" WLR_BACKENDS=headless WLR_HEADLESS_OUTPUTS=1 WLR_LIBINPUT_NO_DEVICES=1
unset WAYLAND_DISPLAY SWAYSOCK WLR_RENDERER DISPLAY
LOG="$RT/session.log"
setsid dbus-run-session -- b1air-session > "$LOG" 2>&1 &
SESSION=$!
cleanup() {
    [[ -n "${SWAYSOCK:-}" ]] && swaymsg exit >/dev/null 2>&1
    sleep 1; kill "$SESSION" 2>/dev/null; pkill -P "$SESSION" 2>/dev/null
    [[ ${FAILED:-0} -ne 0 ]] && { echo "--- session log ---"; tail -40 "$LOG"; }
    rm -rf "$RT"
}
trap cleanup EXIT

PASS=0 FAILED=0
ok()   { echo "ok   $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL $1${2:+: $2}"; FAILED=$((FAILED + 1)); }
for _ in $(seq 1 150); do
    SWAYSOCK="$(ls "$RT"/sway-ipc.*.sock 2>/dev/null | head -1)"; [[ -n "$SWAYSOCK" ]] && break; sleep 0.1
done
export SWAYSOCK WAYLAND_DISPLAY=wayland-1
[[ -n "$SWAYSOCK" ]] && ok "the compositor started" || { fail "the compositor did not start"; exit 1; }

running() { pgrep -u "$(id -u)" -f "$1" >/dev/null; }
for _ in $(seq 1 60); do running quickshell && running 'b1air-daemon session' && break; sleep 0.5; done
for p in 'b1air-daemon session' quickshell b1air-bg; do
    running "$p" && ok "$p is running" || fail "$p is not running"
done
sleep 3   # the daemon applies settings and the extra bindings after it starts

ws() { swaymsg -t get_workspaces -r | python3 -c 'import json,sys; print(next(w["name"] for w in json.load(sys.stdin) if w["focused"]))'; }
views() { swaymsg -t get_tree -r | python3 -c '
import json,sys
def walk(n): return (1 if n.get("pid") and n.get("type") in ("con","floating_con") else 0) + sum(walk(k) for k in n.get("nodes",[]) + n.get("floating_nodes",[]))
print(walk(json.load(sys.stdin)))'; }

# evdev keycodes: KEY_1=2, KEY_3=4, KEY_T=20
"$VKB" logo 4; sleep 1
[[ "$(ws)" == 3 ]] && ok "Mod+3 switches to workspace 3" || fail "Mod+3" "on $(ws)"
"$VKB" logo 2; sleep 1
[[ "$(ws)" == 1 ]] && ok "Mod+1 switches back" || fail "Mod+1" "on $(ws)"
before="$(views)"
"$VKB" logo 20
for _ in $(seq 1 50); do [[ "$(views)" -gt "$before" ]] && break; sleep 0.2; done
[[ "$(views)" -gt "$before" ]] && ok "Mod+T opens a terminal" || fail "Mod+T opened nothing"

echo "test-session: $PASS passed, $FAILED failed"
[[ $FAILED -eq 0 ]]
