#!/usr/bin/env bash
# test-gamma.sh — what b1air-gamma (src/gamma) would do, asked with --print:
# the colour at a temperature, the hours a schedule keeps, and sunset and
# sunrise against published tables. No screen needed.
#
#   tools/test-gamma.sh [path/to/b1air-gamma]
set -uo pipefail
BIN="${1:-b1air-gamma}"
command -v "$BIN" >/dev/null || { echo "test-gamma: no $BIN" >&2; exit 2; }

PASS=0 FAILED=0
ok()   { echo "ok   $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL $1${2:+: $2}"; FAILED=$((FAILED + 1)); }
at() { TZ="$1" date -d "$2" +%s; }            # at <zone> <local time> → unix time
field() { sed -n "s/^$1=//p"; }
minutes() { local h=${1%%:*} m=${1##*:}; echo $((10#$h * 60 + 10#$m)); }
near() {    # near <name> <got HH:MM> <want HH:MM> — within 3 minutes
    local d=$(( $(minutes "$2") - $(minutes "$3") ))
    (( d < 0 )) && d=$(( -d ))
    (( d <= 3 )) && ok "$1 ($2)" || fail "$1" "got $2, published $3"
}

[[ "$("$BIN" 6500 --print | field rgb)" == "1.000 1.000 1.000" ]] && ok "6500 K is white" || fail "6500 K"
rgb="$("$BIN" 3400 --print | field rgb)"
read -r r g b <<<"$rgb"
awk -v r="$r" -v g="$g" -v b="$b" 'BEGIN { exit !(r == 1 && g < 1 && b < g) }' \
    && ok "3400 K takes blue away first ($rgb)" || fail "3400 K colour" "$rgb"
[[ "$("$BIN" 200 --print | field temp)" == 1000 ]] && ok "out of range is clamped" || fail "clamping"

# Set hours across midnight, half an hour of change at each end.
h=(--mode hours --from 22:00 --to 06:30 --temp 3000)
want="21:59=6500 22:15=4750 23:00=3000 03:00=3000 06:30=3000 06:45=4750 07:00=6500 12:00=6500"
got=""
for pair in $want; do
    t=${pair%%=*}
    got+="$t=$(TZ=UTC "$BIN" --print "${h[@]}" --at "$(at UTC "2026-03-01 $t")" | field temp) "
done
[[ "${got% }" == "$want" ]] && ok "set hours, over midnight, with the fades" || fail "set hours" "$got"

# Sunset and sunrise, from the time zone's city (tzdata's zone1970.tab).
night="$(TZ=Europe/Kyiv "$BIN" --print --mode sun --at "$(at Europe/Kyiv '2026-06-21 12:00')" | field night)"
near "Kyiv midsummer sunset" "${night%-*}" 21:12
near "Kyiv midsummer sunrise" "${night#*-}" 04:47
night="$(TZ=America/New_York "$BIN" --print --mode sun --at "$(at America/New_York '2026-12-21 12:00')" | field night)"
near "New York midwinter sunset" "${night%-*}" 16:31
near "New York midwinter sunrise" "${night#*-}" 07:16
# A given location wins over the time zone's.
night="$(TZ=Europe/London "$BIN" --print --mode sun --lat 55.95 --lon -3.19 --at "$(at Europe/London '2026-06-21 12:00')" | field night)"
near "Edinburgh (given location) midsummer sunset" "${night%-*}" 22:02
out="$(TZ=Europe/Oslo "$BIN" --print --mode sun --lat 69.65 --lon 18.96 --temp 3400 --at "$(at Europe/Oslo '2026-12-21 12:00')")"
[[ "$(field night <<<"$out")" == all && "$(field temp <<<"$out")" == 3400 ]] \
    && ok "polar night: warm all day" || fail "polar night" "$out"
out="$(TZ=Europe/Oslo "$BIN" --print --mode sun --lat 69.65 --lon 18.96 --at "$(at Europe/Oslo '2026-06-21 23:59')")"
[[ "$(field night <<<"$out")" == none && "$(field temp <<<"$out")" == 6500 ]] \
    && ok "midnight sun: never warm" || fail "midnight sun" "$out"

# The settings file the daemon writes, and the bare number the first
# version wrote.
f="$(mktemp)"
printf 'temp=2900\nmode=hours\nfrom=08:00\nto=09:00\n' > "$f"
[[ "$(TZ=UTC "$BIN" --print --config "$f" --at "$(at UTC '2026-01-01 08:45')" | field temp)" == 2900 ]] \
    && ok "settings from the file" || fail "settings file"
echo 4100 > "$f"
[[ "$("$BIN" --print --config "$f" | field temp)" == 4100 ]] && ok "a bare temperature in the file" || fail "bare number"
rm -f "$f"

echo "test-gamma: $PASS passed, $FAILED failed"
[[ "$FAILED" -eq 0 ]]
