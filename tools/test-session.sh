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

# The overview, where the compositor has it (our swayfx): from an empty
# workspace 2, Mod+O, Left to workspace 1 (the terminal's), Enter goes there.
# KEY_2=3, KEY_O=24, KEY_LEFT=105, KEY_ENTER=28
if ! swaymsg overview 2>&1 | grep -q "Unknown/invalid command"; then
    "$VKB" logo 3; sleep 1
    "$VKB" logo 24; sleep 1
    "$VKB" - 105; sleep 0.3
    "$VKB" - 28; sleep 1
    [[ "$(ws)" == 1 ]] && ok "Mod+O, Left, Enter goes to workspace 1" || fail "overview by keys" "on $(ws)"
fi

# A screen plugged in comes up as its saved layout says, set by the
# compositor at the moment it appears (monitors_arm_hotplug), not first as
# sway's default and then moved: here a layout with a second screen below,
# at 1.5x, is saved, armed, and the screen created.
PROFILES="$HOME/.config/b1air/display-profiles.json"
saved_profiles="$(cat "$PROFILES" 2>/dev/null || echo '{}')"
python3 - "$PROFILES" <<'PY'
import json, sys
json.dump({"HEADLESS-1 + HEADLESS-2": {"saved": 0, "layout": [
    {"name": "HEADLESS-1", "id": "HEADLESS-1", "resW": 1280, "resH": 800, "rate": 60, "sysScale": 1.0, "x": 0, "y": 0},
    {"name": "HEADLESS-2", "id": "HEADLESS-2", "resW": 1280, "resH": 800, "rate": 60, "sysScale": 1.5, "x": 0, "y": 800}]}},
    open(sys.argv[1], "w"))
PY
b1air-daemon monitors arm
swaymsg -q create_output
first=""
for _ in $(seq 1 50); do
    first="$(swaymsg -t get_outputs -r | python3 -c 'import json,sys
for o in json.load(sys.stdin):
    if o["name"] == "HEADLESS-2": print(o["rect"]["x"], o["rect"]["y"], o["scale"])')"
    [[ -n "$first" ]] && break; sleep 0.02
done
[[ "$first" == "0 800 1.5" ]] && ok "a plugged-in screen comes up as saved" || fail "plugged-in screen" "${first:-never appeared}"
swaymsg -q output HEADLESS-2 unplug
printf '%s\n' "$saved_profiles" > "$PROFILES"
sleep 1

# The lock screen, when the account has a password to test with
# (B1AIR_TEST_PASSWORD): locked, shortcuts are refused; the password opens
# it; shortcuts work again. A lock that cannot be opened, or that leaves the
# session refusing keys after it, is the other way to lose every shortcut.
if [[ -n "${B1AIR_TEST_PASSWORD:-}" ]]; then
    declare -A KEY=([a]=30 [b]=48 [c]=46 [d]=32 [e]=18 [f]=33 [g]=34 [h]=35 [i]=23 [j]=36 [k]=37 [l]=38 [m]=50
                    [n]=49 [o]=24 [p]=25 [q]=16 [r]=19 [s]=31 [t]=20 [u]=22 [v]=47 [w]=17 [x]=45 [y]=21 [z]=44
                    [1]=2 [2]=3 [3]=4 [4]=5 [5]=6 [6]=7 [7]=8 [8]=9 [9]=10 [0]=11)
    lock_up() { pgrep -u "$(id -u)" -f 'Lock.qml' >/dev/null; }
    b1air-daemon lock
    for _ in $(seq 1 50); do lock_up && break; sleep 0.2; done
    sleep 2
    if lock_up; then ok "the lock screen is up"; else fail "the lock screen did not come up"; fi
    before="$(ws)"
    "$VKB" logo 4; sleep 1
    [[ "$(ws)" == "$before" ]] && ok "locked: Mod+3 is refused" || fail "locked, yet Mod+3 switched" "$(ws)"
    codes=()
    for (( i = 0; i < ${#B1AIR_TEST_PASSWORD}; i++ )); do codes+=("${KEY[${B1AIR_TEST_PASSWORD:$i:1}]}"); done
    "$VKB" - "${codes[@]}" 28      # the password, then Enter
    for _ in $(seq 1 50); do lock_up || break; sleep 0.2; done
    if ! lock_up; then ok "the password opens the lock"; else fail "the lock did not open"; fi
    sleep 1
    "$VKB" logo 4; sleep 1
    [[ "$(ws)" == 3 ]] && ok "unlocked: Mod+3 works again" || fail "after unlocking, Mod+3" "on $(ws)"
fi

echo "test-session: $PASS passed, $FAILED failed"
[[ $FAILED -eq 0 ]]
