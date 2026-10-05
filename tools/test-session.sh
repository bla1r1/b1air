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
    # The daemon gave it the four-finger swipe up.
    if swaymsg -q debug_overview_swipe begin 4 2>/dev/null; then ok "four fingers up bring in the overview"
    else fail "overview_swipe is not set to 4 fingers"; fi
    swaymsg -q debug_overview_swipe cancel 2>/dev/null
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

# The clipboard history: the shell watches the clipboard (b1air-clip watch)
# and keeps what is copied, in the secret store.
mark="test-session clipboard $$"
b1air-clip copy -- "$mark"
found=""
for _ in $(seq 1 30); do
    b1air-secret-service get clipboard-history 2>/dev/null | grep -qF "$mark" && { found=1; break; }
    sleep 0.2
done
[[ -n "$found" ]] && ok "copied text lands in the clipboard history" || fail "the clipboard history missed a copy"

# Large copies do not stop the history saving: the store refuses anything
# over 1 MB, and four 300 KB copies used to be the end of every later save.
for n in 1 2 3 4; do
    head -c 300000 /dev/zero | tr '\0' "$n" | b1air-clip copy; sleep 0.6
done
mark2="after the big ones $$"
b1air-clip copy -- "$mark2"
found=""
for _ in $(seq 1 30); do
    b1air-secret-service get clipboard-history 2>/dev/null | grep -qF "$mark2" && { found=1; break; }
    sleep 0.2
done
size="$(b1air-secret-service get clipboard-history 2>/dev/null | wc -c)"
[[ -n "$found" && "$size" -lt 1048576 ]] && ok "the clipboard history keeps saving after large copies ($size bytes)" \
    || fail "the clipboard history after large copies" "found=${found:-no} size=$size"

# b1air-clip itself, in this session.
while IFS= read -r line; do
    case "$line" in
        "ok   "*) ok "clip: ${line#ok   }" ;;
        "FAIL "*) rest="${line#FAIL }"; fail "clip: $rest" ;;
    esac
done < <("$here/test-clip.sh" 2>&1)

# Night light on a screen that has no gamma control (a headless one): the
# daemon says it could not, rather than claiming success, and leaves no
# b1air-gamma behind. Where the screen has it, it stays on.
if b1air-daemon night-light on 3500 --quiet >/dev/null 2>&1; then
    running b1air-gamma && ok "night light holds the screen" || fail "night light said on, nothing running"
    b1air-daemon night-light off --quiet >/dev/null 2>&1
else
    running '^b1air-gamma' && fail "a failed night light left b1air-gamma running" \
        || ok "night light reports a screen without gamma control"
fi

# Print: the region overlay (b1air-shot) comes up; with a selection kept
# from before, Enter captures exactly that region, and the overlay goes.
# Then Escape closes one without capturing. KEY_SYSRQ (Print)=99, KEY_ENTER=28,
# KEY_ESC=1.
shots="$HOME/Pictures/Screenshots"
mkdir -p "$HOME/.cache"; echo "100,80,320,200" > "$HOME/.cache/qs_screenshot_geom"; echo false > "$HOME/.cache/qs_screenshot_mode"
before_shots="$(ls "$shots" 2>/dev/null | wc -l)"
"$VKB" - 99
for _ in $(seq 1 30); do running '^b1air-shot' && break; sleep 0.1; done
if running '^b1air-shot'; then
    ok "Print brings up the region overlay"
    sleep 0.5
    "$VKB" - 28
    for _ in $(seq 1 50); do [[ "$(ls "$shots" 2>/dev/null | wc -l)" -gt "$before_shots" ]] && break; sleep 0.2; done
    newest="$(ls -t "$shots"/* 2>/dev/null | head -1)"
    size="$([[ -n "$newest" ]] && python3 -c 'import struct,sys; d=open(sys.argv[1],"rb").read(24); print("%dx%d" % struct.unpack(">II", d[16:24]))' "$newest" 2>/dev/null)"
    [[ "$size" == 320x200 ]] && ! running '^b1air-shot' && ok "Enter captures the selected region (320x200), and the overlay goes" \
        || fail "capture from the overlay" "file ${newest:-none}, size ${size:-?}"
    "$VKB" - 99
    for _ in $(seq 1 30); do running '^b1air-shot' && break; sleep 0.1; done
    sleep 0.5
    "$VKB" - 1
    for _ in $(seq 1 30); do running '^b1air-shot' || break; sleep 0.1; done
    ! running '^b1air-shot' && ok "Escape closes it" || fail "Escape left the overlay up"
else
    fail "Print opened no overlay"
fi

# The lock screen, when the account has a password to test with
# (B1AIR_TEST_PASSWORD): locked, shortcuts are refused; the password opens
# it; shortcuts work again. A lock that cannot be opened, or that leaves the
# session refusing keys after it, is the other way to lose every shortcut.
if [[ -n "${B1AIR_TEST_PASSWORD:-}" ]]; then
    declare -A KEY=([a]=30 [b]=48 [c]=46 [d]=32 [e]=18 [f]=33 [g]=34 [h]=35 [i]=23 [j]=36 [k]=37 [l]=38 [m]=50
                    [n]=49 [o]=24 [p]=25 [q]=16 [r]=19 [s]=31 [t]=20 [u]=22 [v]=47 [w]=17 [x]=45 [y]=21 [z]=44
                    [1]=2 [2]=3 [3]=4 [4]=5 [5]=6 [6]=7 [7]=8 [8]=9 [9]=10 [0]=11)
    # b1air-lock, the default lock screen.
    lock_up() { pgrep -u "$(id -u)" -x b1air-lock >/dev/null; }
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

# Idle, as the session's own idle thread runs it (src/daemon/idle.cpp), with
# timeouts of seconds and a second screen: that screen goes dark when the
# main one dims, the lock comes up (with a password to test with), every
# screen goes off, input brings back the main one only while locked, and
# opening the lock brings back the other. Caffeine holds all of it off.
SETTINGS="$HOME/.config/sway/settings.json"
saved_settings="$(cat "$SETTINGS")"
idle_timeouts() {   # dim lock screens
    python3 - "$SETTINGS" "$@" <<'PY'
import json, sys
p, dim, lock, screens = sys.argv[1], *map(int, sys.argv[2:])
d = json.load(open(p))
d.update(dimTimeout=dim, lockTimeout=lock, dpmsTimeout=screens, autoSuspend=False,
         idleSecondaryOff=True, lockSecondaryOff=True)
json.dump(d, open(p, "w"), indent=2)
PY
}
power_of() { swaymsg -t get_outputs -r | python3 -c 'import json,sys
for o in json.load(sys.stdin):
    if o["name"] == sys.argv[1]: print("on" if o.get("power") else "off")' "$1"; }
before_outputs="$(swaymsg -t get_outputs -r | python3 -c 'import json,sys; print(" ".join(o["name"] for o in json.load(sys.stdin)))')"
swaymsg -q create_output; sleep 0.5
SECOND="$(swaymsg -t get_outputs -r | python3 -c 'import json,sys
old=sys.argv[1].split()
print(next((o["name"] for o in json.load(sys.stdin) if o["name"] not in old), ""))' "$before_outputs")"
MAIN="$(swaymsg -t get_outputs -r | python3 -c 'import json,sys; print(json.load(sys.stdin)[0]["name"])')"
lock_state() { cat "$XDG_RUNTIME_DIR/b1air/lock-state" 2>/dev/null; }
if [[ -n "${B1AIR_TEST_PASSWORD:-}" ]]; then idle_timeouts 2 4 6; else idle_timeouts 2 0 6; fi
b1air-daemon power idle-reload
sleep 3
[[ "$(power_of "$SECOND")" == off && "$(power_of "$MAIN")" == on ]] \
    && ok "idle: the other screen goes dark when the main one dims" \
    || fail "idle: dim stage" "main $(power_of "$MAIN"), other $(power_of "$SECOND")"
sleep 4
[[ "$(power_of "$MAIN")" == off ]] && ok "idle: every screen off after the screens timeout" \
    || fail "idle: screens stage" "main $(power_of "$MAIN")"
if [[ -n "${B1AIR_TEST_PASSWORD:-}" ]]; then
    [[ "$(lock_state)" == locked ]] && ok "idle: the lock came up, and says so" || fail "idle: lock stage" "$(lock_state)"
    "$VKB" - 42; sleep 1   # shift: input
    [[ "$(power_of "$MAIN")" == on && "$(power_of "$SECOND")" == off ]] \
        && ok "idle: input while locked brings back the main screen only" \
        || fail "idle: wake while locked" "main $(power_of "$MAIN"), other $(power_of "$SECOND")"
    "$VKB" - "${codes[@]}" 28
    for _ in $(seq 1 50); do [[ "$(lock_state)" != locked ]] && break; sleep 0.2; done
    sleep 1
    [[ "$(power_of "$SECOND")" == on ]] && ok "idle: opening the lock brings back the other screen" \
        || fail "idle: after unlock" "other $(power_of "$SECOND"), lock-state $(lock_state)"
else
    "$VKB" - 42; sleep 1
    [[ "$(power_of "$MAIN")" == on && "$(power_of "$SECOND")" == on ]] && ok "idle: input brings every screen back" \
        || fail "idle: wake" "main $(power_of "$MAIN"), other $(power_of "$SECOND")"
fi
b1air-daemon caffeine on >/dev/null 2>&1
sleep 8
[[ "$(power_of "$MAIN")" == on && "$(power_of "$SECOND")" == on && "$(lock_state)" != locked ]] \
    && ok "idle: Caffeine holds every stage off" || fail "idle: Caffeine" "main $(power_of "$MAIN"), other $(power_of "$SECOND")"
b1air-daemon caffeine off >/dev/null 2>&1
printf '%s\n' "$saved_settings" > "$SETTINGS"
b1air-daemon power idle-reload
swaymsg -q output "$SECOND" unplug

# b1air-lock killed while locked: the session stays locked (the compositor
# holds it), a new b1air-lock takes its place, and the password opens it.
type_password() { "$VKB" - "${codes[@]}" 28; }
if [[ -n "${B1AIR_TEST_PASSWORD:-}" ]]; then
    rm -f "$XDG_RUNTIME_DIR/b1air/lock-spawned"
    b1air-daemon lock
    for _ in $(seq 1 50); do pgrep -x b1air-lock >/dev/null && [[ "$(lock_state)" == locked ]] && break; sleep 0.2; done
    first="$(pgrep -x b1air-lock)"
    pkill -KILL -x b1air-lock
    for _ in $(seq 1 50); do second="$(pgrep -x b1air-lock)"; [[ -n "$second" && "$second" != "$first" ]] && break; sleep 0.2; done
    sleep 2   # "locked" comes before the keyboard is the lock's: keys before that go nowhere
    before="$(ws)"
    "$VKB" logo 2; sleep 1
    if [[ -n "$second" && "$second" != "$first" && "$(ws)" == "$before" ]]; then
        ok "b1air-lock killed while locked: a new one takes over, still locked"
    else
        fail "b1air-lock restarted" "first $first, now ${second:-none}, workspace $before -> $(ws)"
    fi
    type_password
    for _ in $(seq 1 50); do pgrep -x b1air-lock >/dev/null || break; sleep 0.2; done
    [[ "$(lock_state)" == unlocked ]] && ! pgrep -x b1air-lock >/dev/null \
        && ok "and the password opens it" || fail "the restarted b1air-lock did not open" "$(lock_state)"
fi

echo "test-session: $PASS passed, $FAILED failed"
[[ $FAILED -eq 0 ]]
