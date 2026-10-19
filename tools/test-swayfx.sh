#!/usr/bin/env bash
# test-swayfx.sh — start our swayfx headless, on the software renderer, and
# check over IPC that each of our patches does what it says.
#
# No GPU and no screen needed (scenefx patch 0001 is what makes that
# possible), so this runs in CI as it runs here:
#
#   tools/test-swayfx.sh [path/to/swayfx]      default: swayfx on PATH
#
# Windows are opened with b1air-term, the desktop's own terminal. What is drawn is not
# looked at — that wants eyes — only what the compositor reports: the tree,
# the focused workspace, the replies to commands.
set -uo pipefail

SWAY="${1:-swayfx}"
command -v "$SWAY" >/dev/null || { echo "test-swayfx: no $SWAY" >&2; exit 2; }
command -v b1air-term >/dev/null || { echo "test-swayfx: b1air-term is needed to open windows" >&2; exit 2; }

RT="$(mktemp -d)"
LOG="$RT/sway.log"
export XDG_RUNTIME_DIR="$RT"
export WLR_BACKENDS=headless WLR_HEADLESS_OUTPUTS=1 WLR_LIBINPUT_NO_DEVICES=1
unset WAYLAND_DISPLAY SWAYSOCK WLR_RENDERER DISPLAY

cat > "$RT/config" <<'EOF'
output HEADLESS-1 resolution 1280x800 position 0 0
default_border none
gaps inner 0
EOF

# -V: sway says at the info level what the shortcuts test (0014) reads.
"$SWAY" -V -c "$RT/config" > "$LOG" 2>&1 &
SWAY_PID=$!
cleanup() {
    kill "$SWAY_PID" 2>/dev/null; wait "$SWAY_PID" 2>/dev/null
    [[ ${FAILED:-0} -ne 0 ]] && { echo "--- sway log ---"; tail -40 "$LOG"; }
    rm -rf "$RT"
}
trap cleanup EXIT

for _ in $(seq 1 100); do
    SWAYSOCK="$(ls "$RT"/sway-ipc.*.sock 2>/dev/null | head -1)"
    [[ -n "$SWAYSOCK" ]] && break
    sleep 0.1
done
export SWAYSOCK
[[ -n "$SWAYSOCK" ]] || { FAILED=1; echo "FAIL swayfx did not start"; exit 1; }

PASS=0 FAILED=0
ok()   { echo "ok   $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL $1${2:+: $2}"; FAILED=$((FAILED + 1)); }
msg()  { swaymsg -- "$@"; }
# Succeeds when every part of a command succeeded.
cmd()  { msg "$@" 2>/dev/null | python3 -c 'import json,sys; sys.exit(0 if all(r.get("success") for r in json.load(sys.stdin)) else 1)'; }
focused_ws() { swaymsg -t get_workspaces -r | python3 -c 'import json,sys; print(next(w["name"] for w in json.load(sys.stdin) if w["focused"]))'; }
ws_repr() { swaymsg -t get_workspaces -r | python3 -c 'import json,sys; print(next((w.get("representation") or "") for w in json.load(sys.stdin) if w["name"]==sys.argv[1]))' "$1"; }
views() { swaymsg -t get_tree -r | python3 -c '
import json,sys
def walk(n):
    c = 1 if n.get("pid") and n.get("type") in ("con","floating_con") else 0
    return c + sum(walk(k) for k in n.get("nodes",[]) + n.get("floating_nodes",[]))
print(walk(json.load(sys.stdin)))'; }
# open_window: one more terminal, and wait until the compositor has it.
# Qt Quick drawn in software: headless there is no GPU.
open_window() {
    local before; before="$(views)"
    msg exec "env QT_QUICK_BACKEND=software b1air-term -e sh -c 'sleep 600'" >/dev/null
    for _ in $(seq 1 100); do [[ "$(views)" -gt "$before" ]] && return 0; sleep 0.1; done
    return 1
}
alive() { kill -0 "$SWAY_PID" 2>/dev/null; }

# ── It started at all ────────────────────────────────────────────────────────
if swaymsg -t get_version -r | grep -q sway_original_version; then ok "swayfx answers, as swayfx"
else fail "get_version" "not swayfx"; fi
if [[ ! -e /dev/dri ]]; then
    if grep -q "falling back to a renderer without effects" "$LOG"; then ok "no GPU: started on the fallback renderer"
    else fail "no GPU, but no fallback in the log"; fi
fi

# ── 0001 autotile ────────────────────────────────────────────────────────────
cmd autotile enable && ok "autotile enable" || fail "autotile enable"
msg workspace 1 >/dev/null
for _ in 1 2 3; do open_window || fail "a window did not open"; done
# 1280x800: the second window goes beside the first (wider than tall), the
# third under the second (640x800, taller than wide) — the dwindle spiral.
r="$(ws_repr 1)"
[[ "$r" == "H[b1air-term V[b1air-term b1air-term]]" ]] && ok "autotile: dwindle spiral" || fail "autotile" "$r"
# Hyprland's togglesplit is sway's own `layout toggle split` ($mod+j): the
# pair the focused window is in turns from one above the other to side by side.
cmd layout toggle split >/dev/null
r="$(ws_repr 1)"
[[ "$r" == "H[b1air-term H[b1air-term b1air-term]]" ]] && ok "togglesplit flips the pair" || fail "togglesplit" "$r"
cmd layout toggle split >/dev/null
cmd autotile disable && ok "autotile disable" || fail "autotile disable"
cmd autotile toggle && cmd autotile toggle && ok "autotile toggle" || fail "autotile toggle"

# ── 0002 inactive_opacity ────────────────────────────────────────────────────
cmd inactive_opacity 0.5 && ok "inactive_opacity 0.5" || fail "inactive_opacity 0.5"
cmd inactive_opacity 2 && fail "inactive_opacity takes 2" || ok "inactive_opacity refuses 2"
cmd focus left && cmd focus right && alive && ok "focus changes with inactive_opacity" || fail "focus with inactive_opacity"
cmd inactive_opacity 1 >/dev/null

# ── 0003 workspace_animation ─────────────────────────────────────────────────
cmd animation_duration_ms 150 >/dev/null
cmd workspace_animation slide && ok "workspace_animation slide" || fail "workspace_animation slide"
cmd workspace_animation wobble && fail "workspace_animation takes wobble" || ok "workspace_animation refuses wobble"
msg workspace 2 >/dev/null; open_window || fail "a window did not open on 2"
msg workspace 1 >/dev/null; sleep 0.3
msg workspace 2 >/dev/null; sleep 0.3
[[ "$(focused_ws)" == 2 ]] && alive && ok "slide: switching lands on the workspace" || fail "slide switch" "$(focused_ws)"
msg workspace 1 >/dev/null; sleep 0.3

# ── 0004 workspace_swipe ─────────────────────────────────────────────────────
cmd workspace_swipe 3 && ok "workspace_swipe 3" || fail "workspace_swipe 3"
swipe() {   # swipe <steps> <dx per step> end|cancel
    cmd debug_workspace_swipe begin 3 || return 1
    for _ in $(seq 1 "$1"); do cmd debug_workspace_swipe update "$2" || return 1; done
    cmd debug_workspace_swipe "$3"
}
swipe 3 -10 cancel && sleep 0.4
[[ "$(focused_ws)" == 1 ]] && ok "swipe: cancelled, stays" || fail "swipe cancel" "$(focused_ws)"
swipe 20 -40 end && sleep 0.4
[[ "$(focused_ws)" == 2 ]] && ok "swipe: carried through, next workspace" || fail "swipe end" "$(focused_ws)"
swipe 20 40 end && sleep 0.4
[[ "$(focused_ws)" == 1 ]] && ok "swipe: the other way, back" || fail "swipe back" "$(focused_ws)"
cmd workspace_swipe off && ok "workspace_swipe off" || fail "workspace_swipe off"
cmd debug_workspace_swipe begin 3 && fail "swipe begins while off" || ok "swipe refused while off"

# ── 0005 special_workspace ──────────────────────────────────────────────────
msg workspace 1 >/dev/null; sleep 0.2
cmd special_workspace toggle && ok "special_workspace toggle" || fail "special_workspace toggle"
[[ "$(focused_ws)" == special ]] && ok "special: shown" || fail "special show" "$(focused_ws)"
open_window || fail "a window did not open on special"
r="$(ws_repr special)"
[[ "$r" == "H[b1air-term]" ]] && ok "special: a window opens on it" || fail "special window" "$r"
cmd special_workspace toggle >/dev/null
[[ "$(focused_ws)" == 1 ]] && ok "special: put away, back on 1" || fail "special hide" "$(focused_ws)"
cmd special_workspace show && cmd special_workspace show && [[ "$(focused_ws)" == special ]] \
    && ok "special: show twice stays shown" || fail "special show twice" "$(focused_ws)"
cmd special_workspace hide >/dev/null
msg workspace 2 >/dev/null; sleep 0.3
cmd special_workspace show >/dev/null
cmd special_workspace hide >/dev/null
[[ "$(focused_ws)" == 2 ]] && ok "special: put away to wherever it was called from" || fail "special from 2" "$(focused_ws)"
msg workspace 1 >/dev/null; sleep 0.3
cmd workspace next_on_output >/dev/null; sleep 0.3
[[ "$(focused_ws)" == 2 ]] && ok "special: workspace next passes it by" || fail "next skips special" "$(focused_ws)"
cmd workspace next_on_output >/dev/null; sleep 0.3
[[ "$(focused_ws)" == 1 ]] && ok "special: and wraps around without it" || fail "next wraps" "$(focused_ws)"
cmd focus left >/dev/null
cmd move container to workspace special && [[ "$(ws_repr special)" == "H[b1air-term b1air-term]" ]] \
    && ok "special: move container to workspace special" || fail "move to special" "$(ws_repr special)"
cmd special_workspace sideways && fail "special_workspace takes sideways" || ok "special_workspace refuses sideways"

# ── 0006 window_animation ───────────────────────────────────────────────────
msg workspace 3 >/dev/null; sleep 0.2
for style in "popin 60" fade slide none popin; do
    if cmd window_animation $style; then
        open_window && sleep 0.3 && cmd kill && sleep 0.4 && alive \
            && ok "window_animation $style: a window opens and closes" \
            || fail "window_animation $style"
    else
        fail "window_animation $style refused"
    fi
done
cmd window_animation popin 150 && fail "popin takes 150%" || ok "popin refuses 150%"
cmd window_animation wobble && fail "window_animation takes wobble" || ok "window_animation refuses wobble"

# ── 0007 overview ───────────────────────────────────────────────────────────
# Workspaces 1, 2 and 3 have windows. Keys need a seat with devices, which
# this headless run has none of (tools/test-session.sh has them), so here
# the commands and what they leave behind are checked; clicks, from the
# seat's cursor, under 0011.
msg workspace 2 >/dev/null; sleep 0.3
cmd overview show && ok "overview show" || fail "overview show"
sleep 0.4
alive && [[ "$(focused_ws)" == 2 ]] && ok "overview: up, still on 2" || fail "overview up" "$(focused_ws)"
cmd workspace 1 >/dev/null; sleep 0.3
[[ "$(focused_ws)" == 1 ]] && alive && ok "overview: a switch while up" || fail "overview switch" "$(focused_ws)"
cmd overview toggle && sleep 0.4 && alive && ok "overview toggle: put away" || fail "overview toggle"
cmd overview toggle && cmd overview hide && sleep 0.4 && alive && ok "overview: toggle up, hide" || fail "overview toggle/hide"
open_window && sleep 0.3 && cmd kill && sleep 0.3 && alive \
    && ok "overview: windows open and close after it" || fail "windows after overview"
cmd overview sideways && fail "overview takes sideways" || ok "overview refuses sideways"
# overview_swipe: up with the fingers brings it in, down takes it away; a
# short one goes back; sideways is not ours.
cmd overview_swipe 4 && ok "overview_swipe 4" || fail "overview_swipe 4"
cmd overview_swipe 9 && fail "overview_swipe takes 9" || ok "overview_swipe refuses 9"
oswipe() {   # oswipe <steps> <dy per step> end|cancel
    cmd debug_overview_swipe begin 4 || return 1
    for _ in $(seq 1 "$1"); do cmd debug_overview_swipe update "$2" || return 1; done
    cmd debug_overview_swipe "$3"
}
oswipe 20 -20 end && sleep 0.4 && alive && ok "overview swipe up: in" || fail "overview swipe up"
oswipe 20 20 end && sleep 0.4 && alive && ok "overview swipe down: away" || fail "overview swipe down"
oswipe 3 -6 end && sleep 0.4 && alive && ok "overview swipe, short: back" || fail "overview short swipe"
cmd debug_overview_swipe begin 4 >/dev/null
cmd debug_overview_swipe update 0 40 && fail "a sideways swipe is taken" || ok "overview swipe: sideways handed over"
cmd debug_overview_swipe end >/dev/null
cmd debug_overview_swipe begin 3 && fail "3 fingers taken" || ok "overview swipe: other fingers not taken"
cmd overview_swipe off >/dev/null

# ── 0011 overview: windows dragged to another workspace ──────────────────────
# Pressed on a window in one workspace's cell and let go in another's, it
# goes there; pressed and let go in one place goes to that workspace. The
# seat's cursor is pressed and let go over IPC; where the cells are is
# worked out as the overview does (overview_cell, 1280x800, no bar).
cell_centre() { swaymsg -t get_workspaces -r | python3 -c '
import json, math, sys
names = [w["name"] for w in json.load(sys.stdin) if w["output"] == "HEADLESS-1" and w["name"] != "special"]
n = len(names); i = names.index(sys.argv[1])
W, H, GAP = 1280, 800, 24
cols = n if n <= 3 else math.ceil(math.sqrt(n)); rows = (n + cols - 1) // cols
m = 0.06 * min(W, H)
s = min((W - 2*m - (cols-1)*GAP) / cols / W, (H - 2*m - (rows-1)*GAP) / rows / H)
w, h = W*s, H*s
row, col = i // cols, i % cols
in_row = n - row*cols if row == rows - 1 else cols
x = (W - (in_row*w + (in_row-1)*GAP)) / 2 + col*(w + GAP)
y = (H - (rows*h + (rows-1)*GAP)) / 2 + row*(h + GAP)
print(round(x + w/2), round(y + h/2))' "$1"; }
cmd workspace dragb >/dev/null; open_window
cmd workspace draga >/dev/null; open_window
cmd overview show >/dev/null; sleep 0.4
read -r ax ay <<<"$(cell_centre draga)"; read -r bx by <<<"$(cell_centre dragb)"
cmd seat - cursor set "$ax" "$ay" >/dev/null; cmd seat - cursor press button1 >/dev/null
cmd seat - cursor set "$bx" "$by" >/dev/null; cmd seat - cursor release button1 >/dev/null
sleep 0.3
[[ "$(ws_repr dragb)" == "H[b1air-term b1air-term]" ]] && ok "overview: a window dragged to another workspace goes there" \
    || fail "overview drag" "dragb: $(ws_repr dragb)"
alive && [[ "$(focused_ws)" == draga ]] && ok "overview: still up, still on the workspace it was" \
    || fail "overview after the drag" "$(focused_ws)"
cmd seat - cursor press button1 >/dev/null; cmd seat - cursor release button1 >/dev/null
sleep 0.4
[[ "$(focused_ws)" == dragb ]] && ok "overview: a click goes to the workspace" || fail "overview click" "$(focused_ws)"
cmd '[workspace=dragb] kill' >/dev/null; sleep 0.3

# ── 0009 layer_effects blur_ignore_alpha ─────────────────────────────────────
# A layer that draws its own soft shadow keeps the blur to what is at least
# this opaque. The value reaches the surface: a layer-shell client (fuzzel,
# on the top layer) shows it in get_outputs; without fuzzel only the parsing
# is checked.
# One argument, quoted: over IPC a bare ';' would end the command.
cmd layer_effects launcher '"blur enable; blur_ignore_alpha 0.4"' && ok "blur_ignore_alpha 0.4" || fail "blur_ignore_alpha 0.4"
cmd layer_effects launcher '"blur_ignore_alpha 2"' && fail "blur_ignore_alpha takes 2" || ok "blur_ignore_alpha refuses 2"
cmd layer_effects launcher '"blur_ignore_alpha half"' && fail "blur_ignore_alpha takes half" || ok "blur_ignore_alpha refuses half"
# A list that does not parse is refused and leaves the rule that was there.
cmd layer_effects launcher '"blur enable; corner_radius 7"' >/dev/null
cmd layer_effects launcher '"nonsense"' && fail "layer_effects took nonsense" || ok "layer_effects refuses what does not parse"
if command -v fuzzel >/dev/null; then
    cmd layer_effects launcher '"blur enable; blur_ignore_alpha 0.4"' >/dev/null
    msg exec "sh -c 'printf \"a\\nb\\n\" | fuzzel --dmenu'" >/dev/null
    layer_alpha() { swaymsg -t get_outputs -r | python3 -c '
import json,sys
for o in json.load(sys.stdin):
    for l in o.get("layer_shell_surfaces", []):
        if l.get("namespace") == "launcher":
            e = l.get("effects", {}); print(e.get("blur_ignore_transparent"), e.get("blur_ignore_alpha")); sys.exit()
print("none")'; }
    r=none
    for _ in $(seq 1 50); do r="$(layer_alpha)"; [[ "$r" != none ]] && break; sleep 0.1; done
    [[ "$r" == "True 0.4"* ]] && ok "blur_ignore_alpha on the surface" || fail "blur_ignore_alpha on the surface" "$r"
    pkill -x fuzzel 2>/dev/null; sleep 0.2
else
    echo "skip blur_ignore_alpha on a surface: no fuzzel"
fi

# ── 0010 floating_snap, snap ─────────────────────────────────────────────────
cmd floating_snap 12 && ok "floating_snap 12" || fail "floating_snap 12"
cmd floating_snap -1 && fail "floating_snap took -1" || ok "floating_snap refuses -1"
cmd floating_snap far && fail "floating_snap took far" || ok "floating_snap refuses far"
cmd floating_snap off && ok "floating_snap off" || fail "floating_snap off"
# The focused window's rect and zone: "x y w h zone".
snapped() { swaymsg -t get_tree -r | python3 -c '
import json,sys
def walk(n):
    if n.get("focused"): return n
    for k in n.get("nodes",[]) + n.get("floating_nodes",[]):
        r = walk(k)
        if r: return r
n = walk(json.load(sys.stdin)) or {}
r = n.get("rect", {})
print(r.get("x"), r.get("y"), r.get("width"), r.get("height"), n.get("snapped"))'; }
# wait_snapped <expected>: the rect follows once the window has taken it.
wait_snapped() { local r; for _ in $(seq 1 50); do r="$(snapped)"; [[ "$r" == "$1" ]] && break; sleep 0.1; done; echo "$r"; }
cmd workspace snaptest >/dev/null
open_window
cmd snap left && fail "snap took a tiled window" || ok "snap refuses a tiled window"
cmd floating enable >/dev/null; cmd resize set 400 300 >/dev/null; cmd move position 100 100 >/dev/null
cmd snap sideways && fail "snap took sideways" || ok "snap refuses sideways"
cmd snap left >/dev/null
r="$(wait_snapped "0 0 640 800 left")"
[[ "$r" == "0 0 640 800 left" ]] && ok "snap left: the left half" || fail "snap left" "$r"
cmd snap top-right >/dev/null
r="$(wait_snapped "640 0 640 400 top-right")"
[[ "$r" == "640 0 640 400 top-right" ]] && ok "snap top-right: a quarter" || fail "snap top-right" "$r"
cmd snap restore >/dev/null
r="$(wait_snapped "760 50 400 300 none")"
[[ "$r" == "760 50 400 300 none" ]] && ok "snap restore: its size back, centred" || fail "snap restore" "$r"
cmd gaps inner current set 10 >/dev/null
cmd snap right >/dev/null
r="$(wait_snapped "645 10 625 780 right")"
[[ "$r" == "645 10 625 780 right" ]] && ok "snap right keeps the gaps" || fail "snap right with gaps" "$r"
cmd gaps inner current set 0 >/dev/null
cmd snap maximize >/dev/null
r="$(wait_snapped "0 0 1280 800 maximize")"
[[ "$r" == "0 0 1280 800 maximize" ]] && ok "snap maximize" || fail "snap maximize" "$r"
# A drag to an edge snaps to the same boxes, but cannot be tested here: the
# seat's `cursor set` moves the cursor without the motion a drag follows.
cmd floating disable >/dev/null
[[ "$(snapped)" == *" none" ]] && ok "tiled again, no longer snapped" || fail "snapped after floating disable" "$(snapped)"
cmd kill >/dev/null; sleep 0.2

# ── 0012 minimize_target: into the dock and out ─────────────────────────────
# Sent to the scratchpad a window shrinks into its target; shown, it grows out
# of it. Nothing of that is seen here (no GPU, and IPC reports where it is
# going), so: the target is kept and reported, the window is hidden and
# shown where it was, and nothing breaks while the copies are in flight.
cmd animation_duration_ms 200 >/dev/null; cmd window_animation popin 80 >/dev/null
cmd workspace mintest >/dev/null; open_window
cmd minimize_target 600 740 48 48 && ok "minimize_target 600 740 48 48" || fail "minimize_target"
target() { swaymsg -t get_tree -r | python3 -c '
import json,sys
def walk(n):
    if n.get("focused") or n.get("app_id") == "b1air-term" and n.get("minimize_target"): return n
    for k in n.get("nodes",[]) + n.get("floating_nodes",[]):
        r = walk(k)
        if r: return r
t = (walk(json.load(sys.stdin)) or {}).get("minimize_target")
print(" ".join(str(t[k]) for k in ("x","y","width","height")) if t else "none")'; }
[[ "$(target)" == "600 740 48 48" ]] && ok "minimize_target reported" || fail "minimize_target reported" "$(target)"
cmd minimize_target 1 2 3 && fail "minimize_target took three numbers" || ok "minimize_target refuses three numbers"
cmd minimize_target a b c d && fail "minimize_target took letters" || ok "minimize_target refuses letters"
cmd minimize_target 0 0 0 0 && fail "minimize_target took no size" || ok "minimize_target refuses no size"
cmd move scratchpad >/dev/null; sleep 0.4
[[ "$(ws_repr mintest)" == "" || "$(ws_repr mintest)" == "H[]" ]] && alive && ok "minimized: gone from the workspace" || fail "minimized" "$(ws_repr mintest)"
cmd scratchpad show >/dev/null; sleep 0.4
alive && [[ "$(views)" -ge 1 ]] && [[ "$(target)" == "600 740 48 48" ]] && ok "shown again, its target kept" \
    || fail "shown from the scratchpad" "$(target)"
# Hidden and shown again at once, and closed while the copy is in flight.
cmd scratchpad show >/dev/null; cmd scratchpad show >/dev/null; cmd scratchpad show >/dev/null
cmd minimize_target none >/dev/null; cmd scratchpad show >/dev/null
cmd '[app_id=b1air-term workspace=mintest] kill' >/dev/null; cmd '[app_id=b1air-term] kill' >/dev/null
sleep 0.5
alive && ok "minimize: toggled at once and closed in flight, still running" || fail "swayfx died minimizing"
cmd animation_duration_ms 0 >/dev/null

# ── 0013 zoom (scenefx 0004 wlr_scene_set_zoom) ─────────────────────────────
zoom_now() { swaymsg -t get_tree -r | python3 -c 'import json,sys; print(round(json.load(sys.stdin).get("zoom", -1), 3))'; }
cmd zoom 2 && [[ "$(zoom_now)" == 2.0 ]] && ok "zoom 2" || fail "zoom 2" "$(zoom_now)"
cmd zoom in && [[ "$(zoom_now)" == 2.5 ]] && ok "zoom in: 2.5" || fail "zoom in" "$(zoom_now)"
cmd zoom out && [[ "$(zoom_now)" == 2.0 ]] && ok "zoom out: 2" || fail "zoom out" "$(zoom_now)"
cmd zoom toggle && [[ "$(zoom_now)" == 1.0 ]] && ok "zoom toggle: off" || fail "zoom toggle off" "$(zoom_now)"
cmd zoom out && [[ "$(zoom_now)" == 1.0 ]] && ok "zoom out stays at 1" || fail "zoom out at 1" "$(zoom_now)"
cmd zoom 0.5 && fail "zoom took 0.5" || ok "zoom refuses 0.5"
cmd zoom 11 && fail "zoom took 11" || ok "zoom refuses 11"
cmd zoom big && fail "zoom took big" || ok "zoom refuses big"
# Magnified, what is under the cursor is still what a click goes to: of two
# windows side by side, a click on the right one, at 3x, focuses it.
focused_x() { swaymsg -t get_tree -r | python3 -c '
import json,sys
def walk(n):
    if n.get("focused"): return n
    for k in n.get("nodes",[]) + n.get("floating_nodes",[]):
        r = walk(k)
        if r: return r
print((walk(json.load(sys.stdin)) or {}).get("rect", {}).get("x"))'; }
cmd workspace zoomtest >/dev/null; open_window; open_window
cmd focus left >/dev/null
cmd seat - cursor set 960 400 >/dev/null
cmd zoom 3 >/dev/null
cmd seat - cursor set 961 400 >/dev/null
cmd seat - cursor press button1 >/dev/null; cmd seat - cursor release button1 >/dev/null
[[ "$(focused_x)" == 640 ]] && ok "zoomed 3x, a click goes to the window under the cursor" || fail "click while zoomed" "x=$(focused_x)"
# Two screens: only the one the cursor is on is magnified, and it moves
# with the cursor; the screen going away while magnified is let go.
zoom_out_name() { swaymsg -t get_tree -r | python3 -c 'import json,sys; print(json.load(sys.stdin).get("zoom_output", "none"))'; }
[[ "$(zoom_out_name)" == HEADLESS-1 ]] && ok "zoom: the screen with the cursor" || fail "zoom output" "$(zoom_out_name)"
cmd create_output >/dev/null; sleep 0.5
two="$(swaymsg -t get_outputs -r | python3 -c 'import json,sys; print(next((o["name"] for o in json.load(sys.stdin) if o["name"] != "HEADLESS-1"), ""))')"
if [[ -n "$two" ]]; then
    cmd output "$two" resolution 1280x800 position 1280 0 >/dev/null; sleep 0.3
    cmd seat - cursor set 1600 400 >/dev/null
    [[ "$(zoom_out_name)" == "$two" ]] && ok "zoom follows the cursor to the other screen" || fail "zoom on the second screen" "$(zoom_out_name)"
    cmd seat - cursor set 300 400 >/dev/null
    [[ "$(zoom_out_name)" == HEADLESS-1 ]] && ok "and back" || fail "zoom back to the first screen" "$(zoom_out_name)"
    cmd seat - cursor set 1600 400 >/dev/null
    cmd output "$two" unplug >/dev/null; sleep 0.5
    alive && [[ "$(zoom_out_name)" != "$two" ]] && ok "zoom: its screen unplugged, let go" || fail "zoom after unplug" "$(zoom_out_name)"
    cmd seat - cursor set 300 400 >/dev/null
else
    fail "create_output" "no second screen"
fi
cmd zoom reset && [[ "$(zoom_now)" == 1.0 ]] && [[ "$(zoom_out_name)" == none ]] && alive && ok "zoom reset" || fail "zoom reset" "$(zoom_now) $(zoom_out_name)"
cmd '[workspace=zoomtest] kill' >/dev/null; sleep 0.3

# ── Shortcuts in every layout (0014) ─────────────────────────────────────────
# bindsym --to-code takes the key from us, whatever the layouts and their
# order. Told by sway itself: a bindcode on the key expected replaces the
# translated bindsym, and sway logs the overwrite. On a sway without 0014
# a Cyrillic layout first leaves q untranslated, and nothing is replaced.
[[ "$(swaymsg -t get_version -r | python3 -c 'import json,sys; print(json.load(sys.stdin).get("b1air_keys_from_us", False))')" == True ]] \
    && ok "get_version says the keys come from us" || fail "get_version without b1air_keys_from_us"
n=0
key_on() {   # key_on <layouts> <keysym> <keycode>
    n=$((n + 1))
    cmd input type:keyboard xkb_layout "$1" >/dev/null
    cmd bindsym --to-code "Mod4+Ctrl+Shift+$2" exec "true k$n" >/dev/null
    cmd bindcode "Mod4+Ctrl+Shift+$3" exec "false k$n" >/dev/null
    sleep 0.1
    if grep -q "to \`exec false k$n\` from \`exec true k$n\`" "$LOG"; then
        ok "$1: $2 is key $3"
    else
        fail "$1: $2 is not key $3"
    fi
    cmd unbindcode "Mod4+Ctrl+Shift+$3" >/dev/null
    cmd unbindsym --to-code "Mod4+Ctrl+Shift+$2" >/dev/null
}
key_on "ru,ua" q 24
key_on "ru,ua" slash 61
key_on "ua,ru,us" t 28
key_on "de,ru" z 52       # where us has z, not where de has it
key_on "de,ru" minus 20   # and minus not on us's slash, which is de's
key_on "de,ru" slash 61
key_on "us,ru" period 60
key_on "ru" Cyrillic_ya 52   # what us does not have, from the layouts
cmd input type:keyboard xkb_layout us >/dev/null

# ── Every command sway has is still found ────────────────────────────────────
# sway looks commands up by binary search; one patch adding its command out of
# alphabetical order made the ones after it unknown (workspace_auto_back_and_forth).
cmd workspace_auto_back_and_forth no && ok "workspace_auto_back_and_forth still found" \
    || fail "workspace_auto_back_and_forth unknown"

alive && ok "still running" || fail "swayfx died"
echo "test-swayfx: $PASS passed, $FAILED failed"
[[ $FAILED -eq 0 ]]
