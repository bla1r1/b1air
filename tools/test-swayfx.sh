#!/usr/bin/env bash
# test-swayfx.sh — start our swayfx headless, on the software renderer, and
# check over IPC that each of our patches does what it says.
#
# No GPU and no screen needed (scenefx patch 0001 is what makes that
# possible), so this runs in CI as it runs here:
#
#   tools/test-swayfx.sh [path/to/swayfx]      default: swayfx on PATH
#
# Windows are opened with foot, which must be installed. What is drawn is not
# looked at — that wants eyes — only what the compositor reports: the tree,
# the focused workspace, the replies to commands.
set -uo pipefail

SWAY="${1:-swayfx}"
command -v "$SWAY" >/dev/null || { echo "test-swayfx: no $SWAY" >&2; exit 2; }
command -v foot >/dev/null || { echo "test-swayfx: foot is needed to open windows" >&2; exit 2; }

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

"$SWAY" -c "$RT/config" > "$LOG" 2>&1 &
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
# open_window: one more foot, and wait until the compositor has it.
open_window() {
    local before; before="$(views)"
    msg exec "foot sh -c 'sleep 600'" >/dev/null
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
[[ "$r" == "H[foot V[foot foot]]" ]] && ok "autotile: dwindle spiral" || fail "autotile" "$r"
# Hyprland's togglesplit is sway's own `layout toggle split` ($mod+j): the
# pair the focused window is in turns from one above the other to side by side.
cmd layout toggle split >/dev/null
r="$(ws_repr 1)"
[[ "$r" == "H[foot H[foot foot]]" ]] && ok "togglesplit flips the pair" || fail "togglesplit" "$r"
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
[[ "$r" == "H[foot]" ]] && ok "special: a window opens on it" || fail "special window" "$r"
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
cmd move container to workspace special && [[ "$(ws_repr special)" == "H[foot foot]" ]] \
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

# ── Every command sway has is still found ────────────────────────────────────
# sway looks commands up by binary search; one patch adding its command out of
# alphabetical order made the ones after it unknown (workspace_auto_back_and_forth).
cmd workspace_auto_back_and_forth no && ok "workspace_auto_back_and_forth still found" \
    || fail "workspace_auto_back_and_forth unknown"

alive && ok "still running" || fail "swayfx died"
echo "test-swayfx: $PASS passed, $FAILED failed"
[[ $FAILED -eq 0 ]]
