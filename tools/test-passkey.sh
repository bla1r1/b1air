#!/usr/bin/env bash
# test-passkey.sh — b1air-passkey (src/passkey) as a browser sees it, without
# root, a HID device or a phone: this script stands in for b1air-fido-uhid's
# socket (B1AIR_FIDO_SOCKET) and speaks CTAPHID to it the way Firefox and
# Chromium do. What needs the phone — the QR code and the tunnel — is not
# reached: every request here is one the key answers by itself.
#
#   tools/test-passkey.sh [path/to/b1air-passkey]
set -uo pipefail
BIN="${1:-b1air-passkey}"
command -v "$BIN" >/dev/null || { echo "test-passkey: no $BIN" >&2; exit 2; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/home/.config/sway"
echo '{"passkeyPhone": true}' > "$work/home/.config/sway/settings.json"

python3 -I - "$BIN" "$work" <<'PY'
import os, socket, struct, subprocess, sys, time

bin_, work = sys.argv[1], sys.argv[2]
path = os.path.join(work, "fido.sock")
srv = socket.socket(socket.AF_UNIX, socket.SOCK_SEQPACKET)
srv.bind(path)
srv.listen(1)
env = dict(os.environ, HOME=os.path.join(work, "home"), B1AIR_FIDO_SOCKET=path)
key = subprocess.Popen([bin_], env=env, stderr=subprocess.DEVNULL)
srv.settimeout(10)
conn, _ = srv.accept()
conn.settimeout(3)

passed = failed = 0
def check(name, cond, detail=""):
    global passed, failed
    if cond:
        print("ok   " + name); passed += 1
    else:
        print("FAIL " + name + (": " + detail if detail else "")); failed += 1

BROADCAST = 0xffffffff
def send(cid, cmd, data):
    first = struct.pack(">IBH", cid, cmd, len(data)) + data[:57]
    conn.send(first.ljust(64, b"\0"))
    rest, seq = data[57:], 0
    while rest:
        conn.send((struct.pack(">IB", cid, seq) + rest[:59]).ljust(64, b"\0"))
        rest, seq = rest[59:], seq + 1

def recv(skip_keepalive=True):
    while True:
        pkt = conn.recv(64)
        cid, cmd, n = struct.unpack(">IBH", pkt[:7])
        data = pkt[7:7 + n]
        while len(data) < n:
            more = conn.recv(64)
            data += more[5:5 + min(59, n - len(data))]
        if skip_keepalive and cmd == 0xbb:
            continue
        return cid, cmd, data

# INIT on the broadcast channel: our nonce back, and a channel of our own.
nonce = os.urandom(8)
send(BROADCAST, 0x86, nonce)
cid, cmd, data = recv()
check("INIT answers on the broadcast channel", cid == BROADCAST and cmd == 0x86)
check("INIT echoes the nonce", data[:8] == nonce)
chan = struct.unpack(">I", data[8:12])[0]
check("INIT gives a channel", chan not in (0, BROADCAST))
check("capabilities: CBOR, no U2F", data[16] & 0x04 and data[16] & 0x08, hex(data[16]))

# PING longer than one report.
payload = bytes(range(200))
send(chan, 0x81, payload)
check("PING echoes 200 bytes", recv() == (chan, 0x81, payload))

# getInfo: OK and CBOR.
send(chan, 0x90, b"\x04")
cid, cmd, data = recv()
check("getInfo is OK", cmd == 0x90 and data[:1] == b"\x00", data[:1].hex())
check("getInfo says FIDO_2_1 and hybrid", b"FIDO_2_1" in data and b"hybrid" in data)

# A silent getAssertion (up: false) is "no credentials", with no QR.
# {1: "example.org", 2: h'00'*32, 5: {"up": false}}
silent = (b"\x02\xa3\x01\x6bexample.org\x02\x58\x20" + b"\0" * 32
          + b"\x05\xa1\x62up\xf4")
send(chan, 0x90, silent)
cid, cmd, data = recv()
check("silent getAssertion: no credentials", data == b"\x2e", data.hex())

# The same check with an allowList of two: "yes", both, the second through
# getNextAssertion — so Firefox sends the whole list on with the real request
# instead of making the key blink for "make.me.blink".
# {1: "example.org", 2: h'00'*32, 3: [{"id": h'01', "type": "public-key"},
#  {"id": h'02', "type": "public-key"}], 5: {"up": false}}
cred = lambda b: b"\xa2\x62id\x41" + bytes([b]) + b"\x64type\x6apublic-key"
listed = (b"\x02\xa4\x01\x6bexample.org\x02\x58\x20" + b"\0" * 32
          + b"\x03\x82" + cred(1) + cred(2) + b"\x05\xa1\x62up\xf4")
send(chan, 0x90, listed)
cid, cmd, data = recv()
check("silent check with an allowList: yes", data[:1] == b"\x00" and cred(1) in data, data[:8].hex())
check("it says there are two", b"\x05\x02" in data)
send(chan, 0x90, b"\x08")
cid, cmd, data = recv()
check("getNextAssertion gives the second", data[:1] == b"\x00" and cred(2) in data, data[:8].hex())
send(chan, 0x90, b"\x08")
cid, cmd, data = recv()
check("and then no more", data == b"\x30", data.hex())

# Firefox's blink request is refused at once: no QR code for it.
# {1: h'00'*32, 2: {"id": "make.me.blink"}, 3: {"id": h'00', "name": "x"},
#  4: [{"alg": -7, "type": "public-key"}]}
blink = (b"\x01\xa4\x01\x58\x20" + b"\0" * 32 + b"\x02\xa1\x62id\x6dmake.me.blink"
         + b"\x03\xa2\x62id\x41\x00\x64name\x61x"
         + b"\x04\x81\xa2\x63alg\x26\x64type\x6apublic-key")
send(chan, 0x90, blink)
cid, cmd, data = recv()
check("make.me.blink is refused, no QR", data == b"\x30", data.hex())

# authenticatorSelection waits (keepalives) until CANCEL, then KEEPALIVE_CANCEL.
send(chan, 0x90, b"\x0b")
cid, cmd, data = recv(skip_keepalive=False)
check("selection sends keepalives", cmd == 0xbb and data == b"\x02", f"{cmd:#x} {data.hex()}")
send(chan, 0x91, b"")
cid, cmd, data = recv()
check("CANCEL ends it with KEEPALIVE_CANCEL", cmd == 0x90 and data == b"\x2d", data.hex())

# U2F is not spoken.
send(chan, 0x83, b"\0" * 10)
cid, cmd, data = recv()
check("U2F MSG is an invalid command", cmd == 0xbf and data == b"\x01")

# Turned off in Settings: the key lets go of the device.
with open(os.path.join(work, "home/.config/sway/settings.json"), "w") as f:
    f.write('{"passkeyPhone": false}')
conn.settimeout(6)
try:
    gone = conn.recv(64) == b""
except socket.timeout:
    gone = False
check("turning it off closes the device", gone)

key.terminate()
print(f"\n{passed} passed, {failed} failed")
sys.exit(1 if failed else 0)
PY
