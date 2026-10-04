#!/usr/bin/env bash
# test-fingerprint.sh — the daemon's fingerprint verbs (src/daemon/fingerprint.cpp)
# against fprintd driving libfprint's virtual reader: status, enrolling one
# touch at a time, a finger that does not match and one that does, deleting.
#
#   sudo tools/test-fingerprint.sh [path/to/b1air-daemon]
#
# For a container (CI) or a chroot: it starts its own system bus, polkitd
# with a rule that lets the test use the reader, and fprintd with
# FP_VIRTUAL_DEVICE, and stops them again. It will not touch a machine whose
# system bus is already running.
set -uo pipefail
BIN="${1:-b1air-daemon}"
command -v "$BIN" >/dev/null || { echo "test-fingerprint: no $BIN" >&2; exit 2; }
[[ $EUID -eq 0 ]] || { echo "test-fingerprint: needs root (it starts a system bus)" >&2; exit 2; }
[[ -S /run/dbus/system_bus_socket ]] && { echo "test-fingerprint: a system bus is running; not on a live system" >&2; exit 2; }
FPRINTD=""
for f in /usr/libexec/fprintd /usr/lib/fprintd/fprintd /usr/lib/fprintd; do [[ -x $f && ! -d $f ]] && FPRINTD=$f; done
[[ -n $FPRINTD ]] || { echo "test-fingerprint: fprintd is not installed" >&2; exit 2; }
POLKITD=""
for p in /usr/lib/polkit-1/polkitd /usr/libexec/polkitd /usr/lib/polkit/polkitd; do [[ -x $p ]] && POLKITD=$p; done

PASS=0 FAILED=0
ok()   { echo "ok   $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL $1${2:+: $2}"; FAILED=$((FAILED + 1)); }

SOCK="$(mktemp -u /tmp/fpvirt.XXXXXX)"
RULE=/etc/polkit-1/rules.d/00-b1air-test-fingerprint.rules
mkdir -p /run/dbus /etc/polkit-1/rules.d
echo 'polkit.addRule(function(a) { if (a.id.indexOf("net.reactivated.fprint") == 0) return polkit.Result.YES; });' > "$RULE"
rm -f /run/dbus/pid   # one left by a bus that is gone (the socket is not there)
dbus-daemon --system --fork --print-pid > /tmp/b1air-fp-bus.pid 2>/dev/null
[[ -S /run/dbus/system_bus_socket ]] || { echo "test-fingerprint: could not start a system bus" >&2; rm -f "$RULE"; exit 2; }
[[ -n $POLKITD ]] && { "$POLKITD" --no-debug >/dev/null 2>&1 & echo $! > /tmp/b1air-fp-polkit.pid; }
sleep 1
FP_VIRTUAL_DEVICE="$SOCK" "$FPRINTD" -t >/tmp/b1air-fprintd.log 2>&1 &
FPID=$!
cleanup() {
    kill "$FPID" 2>/dev/null
    [[ -f /tmp/b1air-fp-polkit.pid ]] && kill "$(cat /tmp/b1air-fp-polkit.pid)" 2>/dev/null
    kill "$(cat /tmp/b1air-fp-bus.pid)" 2>/dev/null
    rm -f "$RULE" /tmp/b1air-fp-*.pid /run/dbus/system_bus_socket /run/dbus/pid
}
trap cleanup EXIT
for _ in $(seq 1 50); do "$BIN" fingerprint status | grep -q '"available":true' && break; sleep 0.2; done
"$BIN" fingerprint status | grep -q '"available":true' \
    || { echo "test-fingerprint: fprintd did not come up: $(tail -3 /tmp/b1air-fprintd.log)" >&2; exit 2; }

send() { python3 -c 'import socket,sys
s=socket.socket(socket.AF_UNIX); s.connect(sys.argv[1]); s.sendall(sys.argv[2].encode()); s.shutdown(socket.SHUT_WR); s.recv(64); s.close()' "$SOCK" "$1"; }
reader_open() { for _ in $(seq 1 50); do [[ -S $SOCK ]] && python3 -c 'import socket,sys; s=socket.socket(socket.AF_UNIX); s.connect(sys.argv[1])' "$SOCK" 2>/dev/null && return 0; sleep 0.2; done; return 1; }
field() { python3 -c 'import json,sys; v=json.load(sys.stdin)[sys.argv[1]]; print(",".join(v) if isinstance(v,list) else v)' "$1"; }

status="$("$BIN" fingerprint status)"
[[ "$(field available <<<"$status")" == True && "$(field stages <<<"$status")" -gt 0 ]] \
    && ok "fprintd's reader is found, with its number of touches" || fail "status" "$status"

out="$(mktemp)"
"$BIN" fingerprint enroll right-index-finger > "$out" &
E=$!
reader_open
stages="$(field stages <<<"$status")"
for _ in $(seq 1 "$stages"); do send "SCAN finger-a"; sleep 0.3; done
wait $E; rc=$?
[[ $rc -eq 0 && "$(grep -c 'status enroll-stage-passed' "$out")" -eq $((stages - 1)) ]] && tail -1 "$out" | grep -q "done enroll-completed" \
    && ok "enrolling: a line a touch, then completed" || fail "enroll" "rc=$rc $(tr '\n' '|' < "$out")"
[[ "$("$BIN" fingerprint status | field enrolled)" == right-index-finger ]] && ok "the finger is listed" || fail "enrolled list"

"$BIN" fingerprint verify > "$out" & V=$!
reader_open; send "SCAN finger-b"; wait $V
tail -1 "$out" | grep -q "done verify-no-match" && ok "another finger does not match" || fail "verify no-match" "$(cat "$out")"
"$BIN" fingerprint verify > "$out" & V=$!
reader_open; send "SCAN finger-a"; wait $V; rc=$?
[[ $rc -eq 0 ]] && tail -1 "$out" | grep -q "done verify-match" && ok "the enrolled finger matches" || fail "verify match" "$(cat "$out")"

"$BIN" fingerprint enroll left-thumb > "$out" & E=$!
reader_open; kill "$E"; wait "$E"
grep -q "done cancelled" "$out" && ok "stopping an enrolment lets the reader go" || fail "cancel" "$(cat "$out")"
"$BIN" fingerprint status >/dev/null   # the reader is free again for:

"$BIN" fingerprint delete all >/dev/null
[[ -z "$("$BIN" fingerprint status | field enrolled)" ]] && ok "deleting removes it" || fail "delete"
rm -f "$out"

echo "test-fingerprint: $PASS passed, $FAILED failed"
[[ $FAILED -eq 0 ]]
