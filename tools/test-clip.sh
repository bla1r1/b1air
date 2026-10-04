#!/usr/bin/env bash
# test-clip.sh — b1air-clip against the running compositor: copy and paste
# of text and of other types, the primary selection, clearing, the watch the
# shell's clipboard history reads, and that a copy server goes away once
# replaced, even when a reader stopped reading from it.
#
#   tools/test-clip.sh [path/to/b1air-clip]
#
# Needs WAYLAND_DISPLAY (a session; test-session.sh runs it inside one).
# Leaves the clipboard empty.
set -uo pipefail
BIN="${1:-b1air-clip}"
command -v "$BIN" >/dev/null || { echo "test-clip: no $BIN" >&2; exit 2; }
[[ -n "${WAYLAND_DISPLAY:-}" ]] || { echo "test-clip: no WAYLAND_DISPLAY" >&2; exit 2; }

PASS=0 FAILED=0
ok()   { echo "ok   $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL $1${2:+: $2}"; FAILED=$((FAILED + 1)); }
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
servers() { pgrep -u "$(id -u)" -f "^$(basename "$BIN") copy" -c 2>/dev/null || true; }
# A copy server is up once the paste answers; give it a moment.
settle() { sleep 0.3; }

"$BIN" copy -- "plain words"; settle
[[ "$("$BIN" paste)" == "plain words" ]] && ok "text from the arguments" || fail "text from the arguments" "$("$BIN" paste)"

printf 'Привіт, світ ✓\nsecond line\n\n' > "$TMP/utf8"
"$BIN" copy < "$TMP/utf8"; settle
"$BIN" paste > "$TMP/utf8.out"
cmp -s "$TMP/utf8" "$TMP/utf8.out" && ok "UTF-8 from stdin, newlines kept" || fail "UTF-8 from stdin"

"$BIN" copy -- "--not-an-option"; settle
[[ "$("$BIN" paste)" == "--not-an-option" ]] && ok "text starting with a dash, after --" || fail "dash text"

head -c 200000 /dev/urandom > "$TMP/blob.png"
"$BIN" copy -t image/png < "$TMP/blob.png"; settle
"$BIN" paste -t image/png > "$TMP/blob.out"
cmp -s "$TMP/blob.png" "$TMP/blob.out" && ok "binary data by type, byte for byte" || fail "binary by type"
"$BIN" paste --list-types | grep -qx "image/png" && ok "--list-types names the type" || fail "--list-types"
if "$BIN" paste >/dev/null 2>&1; then fail "text paste of an image succeeded"
else ok "no text on the clipboard: status 1"; fi

head -c 300000 /dev/zero | tr '\0' 'x' > "$TMP/big"
"$BIN" copy < "$TMP/big"; settle
[[ "$("$BIN" paste --max 1000 | wc -c)" -eq 1000 ]] && ok "--max cuts the paste" || fail "--max"
[[ "$("$BIN" paste | wc -c)" -eq 300000 ]] && ok "no limit without --max" || fail "unlimited paste"

"$BIN" copy -- "clipboard stays"; settle
"$BIN" copy --primary -- "middle click"; settle
if [[ "$("$BIN" paste --primary)" == "middle click" && "$("$BIN" paste)" == "clipboard stays" ]]; then
    ok "primary selection, apart from the clipboard"
else
    fail "primary selection" "primary '$("$BIN" paste --primary 2>&1)', clipboard '$("$BIN" paste 2>&1)'"
fi
"$BIN" clear --primary; settle

# The watch: the current text first, then each new one, \x1e after each;
# an image in between is not text and is skipped. Closing stdin ends it.
mkfifo "$TMP/in"
"$BIN" watch --max 262144 < "$TMP/in" > "$TMP/watch.out" &
watcher=$!
exec 7> "$TMP/in"
sleep 0.5
"$BIN" copy -- "one"; settle
"$BIN" copy -t image/png < "$TMP/blob.png"; settle
printf 'two\nlines' | "$BIN" copy; settle
exec 7>&-
for _ in $(seq 1 30); do kill -0 "$watcher" 2>/dev/null || break; sleep 0.1; done
if kill -0 "$watcher" 2>/dev/null; then fail "the watch outlived its stdin"; kill "$watcher"
else ok "the watch ends when stdin closes"; fi
got="$(tr '\036' '|' < "$TMP/watch.out")"
[[ "$got" == $'clipboard stays|one|two\nlines|' ]] && ok "the watch reports each text, images skipped" \
    || fail "watch output" "$(printf '%q' "$got")"

# Replaced copy servers exit — also one whose reader stopped reading: the
# paste streams into a pipe nobody reads, so the server's writes fill it.
"$BIN" copy < "$TMP/big"; settle
( "$BIN" paste | sleep 9 ) &
staller=$!
sleep 1
"$BIN" copy -- "after the stall"; settle
for _ in $(seq 1 80); do [[ "$(servers)" -le 1 ]] && break; sleep 0.1; done
[[ "$(servers)" -le 1 ]] && ok "replaced servers exit, stalled reader or not" || fail "copy servers left" "$(servers)"
[[ "$("$BIN" paste)" == "after the stall" ]] && ok "the new text is served meanwhile" || fail "paste after the stall"
kill "$staller" 2>/dev/null; wait "$staller" 2>/dev/null

"$BIN" clear; settle
"$BIN" clear --primary; settle
if ! "$BIN" paste >/dev/null 2>&1 && ! "$BIN" paste --primary >/dev/null 2>&1; then ok "clear empties both"
else fail "clear"; fi
for _ in $(seq 1 30); do [[ "$(servers)" -eq 0 ]] && break; sleep 0.1; done
[[ "$(servers)" -eq 0 ]] && ok "no copy server left after clear" || fail "servers after clear" "$(servers)"

echo "test-clip: $PASS passed, $FAILED failed"
[[ "$FAILED" -eq 0 ]]
