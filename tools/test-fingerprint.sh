#!/usr/bin/env bash
# test-fingerprint.sh — the daemon's fingerprint verbs (src/daemon/fingerprint.cpp)
# against fprintd driving libfprint's virtual reader: status, enrolling one
# touch at a time, a finger that does not match and one that does, deleting;
# and the login screen's PAM file with fingerprint login on, through PAM
# itself (tools/pam-try): a typed password works without the reader and is
# not held up by it, an empty one asks the reader, and off puts the file back
# as it was.
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

# ── The login screen ─────────────────────────────────────────────────────────
here="$(cd "$(dirname "$0")" && pwd)"
TMP="$(mktemp -d)"
FPUSER=b1air-fp-test FPPASS='b1air-fp-pass-1'
if ! command -v cc >/dev/null || ! cc -o "$TMP/pam-try" "$here/pam-try/pam-try.c" -lpam 2>/dev/null; then
    echo "skip the login screen: tools/pam-try does not build (cc, PAM headers)"
else
    # The pam_exec helper, root's, where the daemon looks for it.
    helper_added=""
    if [[ ! -x /usr/share/b1air/pam/b1air-empty-password ]]; then
        install -D -m 755 "$here/../src/pam/b1air-empty-password" /usr/share/b1air/pam/b1air-empty-password
        helper_added=1
    fi
    # A user with a password and a finger.
    useradd -M -s /bin/sh "$FPUSER" 2>/dev/null
    echo "$FPUSER:$FPPASS" | chpasswd
    as_user() { su -s /bin/sh "$FPUSER" -c "$*"; }
    as_user "'$(command -v "$BIN")' fingerprint enroll right-index-finger" > "$out" &
    E=$!
    reader_open
    for _ in $(seq 1 "$stages"); do send "SCAN finger-a"; sleep 0.3; done
    wait $E
    # The PAM files, copied: the test's sddm file is changed, not the system's.
    CONF="$TMP/pam.d"
    cp -a /etc/pam.d "$CONF"
    [[ -f "$CONF/sddm" ]] || cp "$CONF/login" "$CONF/sddm"
    cp "$CONF/sddm" "$TMP/sddm.orig"
    export B1AIR_TEST_SDDM_PAM="$CONF/sddm"
    login_status="$("$BIN" fingerprint login status)"
    [[ "$(field supported <<<"$login_status")" == True && "$(field enabled <<<"$login_status")" == False ]] \
        && ok "login: supported, off to begin with" || fail "login status" "$login_status"
    "$BIN" fingerprint login on >/dev/null
    grep -q 'pam_fprintd.so' "$CONF/sddm" && [[ "$("$BIN" fingerprint login status | field enabled)" == True ]] \
        && ok "login on: the block is in the login screen's file" || fail "login on" "$(cat "$CONF/sddm")"
    try() { "$TMP/pam-try" "$CONF" sddm "$FPUSER" "$1" 2>/dev/null; }

    t0=$SECONDS; try "$FPPASS" >/dev/null; rc=$?
    [[ $rc -eq 0 && $((SECONDS - t0)) -lt 5 ]] && ok "login: the typed password, no reader in the way" \
        || fail "login with the password" "rc=$rc in $((SECONDS - t0))s"
    t0=$SECONDS; try "wrong" >/dev/null; rc=$?
    [[ $rc -ne 0 && $((SECONDS - t0)) -lt 10 ]] && ok "login: a wrong password is refused without waiting for the reader" \
        || fail "login with a wrong password" "rc=$rc in $((SECONDS - t0))s"
    try "" > "$out" & P=$!
    reader_open; send "SCAN finger-a"; wait $P; rc=$?
    [[ $rc -eq 0 ]] && ok "login: an empty password and the right finger" || fail "login by finger" "$(cat "$out")"
    try "" > "$out" & P=$!
    for _ in 1 2 3; do reader_open; send "SCAN finger-b"; sleep 1; done
    wait $P; rc=$?
    [[ $rc -ne 0 ]] && ok "login: an empty password and another finger is refused" || fail "login by a wrong finger"

    "$BIN" fingerprint login off >/dev/null
    cmp -s "$CONF/sddm" "$TMP/sddm.orig" && ok "login off: the file is as it was" \
        || fail "login off" "$(diff "$TMP/sddm.orig" "$CONF/sddm")"

    # Where the block goes in each family's sddm file: just before the
    # password check, after the checks that must still be able to refuse.
    placed() {   # file, the line expected right after the block
        "$BIN" fingerprint login on >/dev/null 2>&1 || return 1
        grep -A1 '^# b1air: end' "$1" | tail -1 | grep -qF -- "$2"
    }
    printf '#%%PAM-1.0\nauth requisite pam_nologin.so\nauth required pam_succeed_if.so user != root quiet_success\n@include common-auth\n' > "$CONF/sddm"
    placed "$CONF/sddm" "@include common-auth" && ok "login: Debian's file, after nologin and not-root" || fail "Debian placement" "$(cat "$CONF/sddm")"
    printf '#%%PAM-1.0\nauth        include     system-login\n-auth       optional    pam_gnome_keyring.so\n' > "$CONF/sddm"
    placed "$CONF/sddm" "include     system-login" && ok "login: Arch's file" || fail "Arch placement" "$(cat "$CONF/sddm")"
    printf 'auth     [success=done ignore=ignore default=bad] pam_selinux_permit.so\nauth        substack      password-auth\nauth        include       postlogin\n' > "$CONF/sddm"
    placed "$CONF/sddm" "substack      password-auth" && ok "login: Fedora's file" || fail "Fedora placement" "$(cat "$CONF/sddm")"
    printf '#%%PAM-1.0\nauth     include        common-auth\naccount  include        common-account\n' > "$CONF/sddm"
    placed "$CONF/sddm" "include        common-auth" && ok "login: openSUSE's file" || fail "openSUSE placement" "$(cat "$CONF/sddm")"
    printf '#%%PAM-1.0\naccount include common-account\n' > "$CONF/sddm"
    ! "$BIN" fingerprint login on >/dev/null 2>&1 && ! grep -q b1air "$CONF/sddm" \
        && ok "login: a file with no password check is left alone" || fail "no-auth file" "$(cat "$CONF/sddm")"
    unset B1AIR_TEST_SDDM_PAM

    as_user "'$(command -v "$BIN")' fingerprint delete all" >/dev/null
    userdel "$FPUSER" 2>/dev/null
    [[ -n "$helper_added" ]] && rm -f /usr/share/b1air/pam/b1air-empty-password
fi
rm -rf "$TMP" "$out"

echo "test-fingerprint: $PASS passed, $FAILED failed"
[[ $FAILED -eq 0 ]]
