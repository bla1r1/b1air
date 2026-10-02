#!/usr/bin/env bash
# test-magic-mouse.sh — the Magic Mouse gesture recogniser (src/daemon/
# magic_mouse.cpp) fed touch scripts, as the hardware would report them,
# through `b1air-daemon magic-mouse replay`. No device needed.
#
#   tools/test-magic-mouse.sh [path/to/b1air-daemon]
#
# Script lines: "t <ms>", "down|move <slot> <x> <y>", "up <slot>", "click",
# "syn" (end of a frame). The surface is about 2400 × 3600 units.
set -uo pipefail
BIN="${1:-b1air-daemon}"
command -v "$BIN" >/dev/null || { echo "test-magic-mouse: no $BIN" >&2; exit 2; }

PASS=0 FAILED=0
check() {   # check <name> <expected output> <<script
    local got; got="$("$BIN" magic-mouse replay | tr '\n' ' ' | sed 's/ $//')"
    if [[ "$got" == "$2" ]]; then echo "ok   $1"; PASS=$((PASS + 1))
    else echo "FAIL $1: got '${got}', expected '$2'"; FAILED=$((FAILED + 1)); fi
}

check "two fingers swiped left" "swipe-left" <<'S'
t 0
down 0 0 0
down 1 300 0
syn
t 20
move 0 -300 10
move 1 0 10
syn
t 40
move 0 -600 20
move 1 -300 20
syn
t 60
up 0
up 1
syn
S

check "two fingers swiped right" "swipe-right" <<'S'
t 0
down 0 0 0
down 1 300 0
syn
t 40
move 0 600 0
move 1 900 0
syn
t 80
up 0
up 1
syn
S

check "one swipe per contact, however far" "swipe-left" <<'S'
t 0
down 0 0 0
down 1 300 0
syn
t 30
move 0 -600 0
move 1 -300 0
syn
t 60
move 0 -1100 0
move 1 -800 0
syn
t 90
up 0
up 1
syn
S

check "two fingers tapped twice" "double-tap" <<'S'
t 1000
down 0 0 0
down 1 300 0
syn
t 1080
up 0
up 1
syn
t 1250
down 0 5 0
down 1 305 0
syn
t 1330
up 0
up 1
syn
S

check "a single tap is nothing" "" <<'S'
t 0
down 0 0 0
down 1 300 0
syn
t 80
up 0
up 1
syn
S

check "taps too far apart are nothing" "" <<'S'
t 0
down 0 0 0
down 1 300 0
syn
t 80
up 0
up 1
syn
t 900
down 0 0 0
down 1 300 0
syn
t 980
up 0
up 1
syn
S

check "one finger sideways (scrolling) is nothing" "" <<'S'
t 0
down 0 0 0
syn
t 50
move 0 900 0
syn
t 100
up 0
syn
S

check "a click is not a tap" "" <<'S'
t 0
down 0 0 0
down 1 300 0
syn
click
syn
t 80
up 0
up 1
syn
t 200
down 0 0 0
down 1 300 0
syn
t 280
up 0
up 1
syn
S

check "two fingers up and down are nothing" "" <<'S'
t 0
down 0 0 0
down 1 300 0
syn
t 50
move 0 50 -1500
move 1 350 -1500
syn
t 100
up 0
up 1
syn
S

check "three fingers swiped are nothing" "" <<'S'
t 0
down 0 0 0
down 1 300 0
down 2 600 0
syn
t 40
move 0 -700 0
move 1 -400 0
move 2 -100 0
syn
t 80
up 0
up 1
up 2
syn
S

echo "test-magic-mouse: $PASS passed, $FAILED failed"
[[ $FAILED -eq 0 ]]
