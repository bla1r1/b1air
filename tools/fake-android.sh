#!/usr/bin/env bash
# fake-android.sh — an Android phone in file-transfer mode, without a phone.
#
# The kernel plays the phone: dummy_hcd is a USB controller with a device
# side and a host side joined inside the machine, a USB gadget (configfs) on
# the device side says it is a Pixel in MTP mode, and uMTP-Responder answers
# MTP from an ordinary folder. To the rest of the system it is a USB device
# like any other: udev tags it, gvfs-mtp finds it, `gio mount` mounts it —
# the same path Files takes with a real phone, from the cable on.
#
#   sudo tools/fake-android.sh up   [DIR]   DIR is its storage (made, with a
#                                           few photos in DCIM/Camera, if new)
#   sudo tools/fake-android.sh down
#
# Needs root (modules, configfs), the dummy_hcd and libcomposite modules
# (Arch's kernel has both) and umtprd from uMTP-Responder
# (https://github.com/viveris/uMTP-Responder; `make` builds it in a minute):
# on PATH, or named by UMTPRD=/path/to/umtprd.
#
# FAKE_ANDROID_SERIAL sets the USB serial — "emulator-5554" joins it to a
# running Android emulator's adb, as one phone, the way Files joins a real
# phone's MTP and adb by serial.
set -euo pipefail

STATE=/run/b1air-fake-android
GADGET=/sys/kernel/config/usb_gadget/b1air-fake-android
FFS=/dev/ffs-b1air-mtp
SERIAL="${FAKE_ANDROID_SERIAL:-B1AIRTEST0001}"
# A Pixel in MTP mode: libmtp's udev rules know 18d1:4ee1, so it is tagged as
# an MTP device by vendor and product, as a real one is.
VID=0x18d1 PID=0x4ee1

die() { echo "fake-android: $*" >&2; exit 1; }
[[ $EUID -eq 0 ]] || die "run it with sudo"

owner_uid="${SUDO_UID:-0}" owner_gid="${SUDO_GID:-0}"

up() {
    local dir="${1:-/tmp/b1air-fake-android}"
    local umtprd="${UMTPRD:-$(command -v umtprd || true)}"
    [[ -x "$umtprd" ]] || die "umtprd not found: build uMTP-Responder and set UMTPRD=…/umtprd"
    [[ -d "$GADGET" ]] && die "already up (sudo $0 down first)"

    # Its storage, with something to import.
    if [[ ! -d "$dir/DCIM" ]]; then
        mkdir -p "$dir/DCIM/Camera" "$dir/Download" "$dir/Music"
        if command -v ffmpeg >/dev/null; then
            local i colour
            i=0
            for colour in teal orange purple; do
                i=$((i + 1))
                ffmpeg -v error -f lavfi -i "color=c=${colour}:s=1600x1200" -frames:v 1 \
                    "$dir/DCIM/Camera/PXL_2026100${i}_120000000.jpg"
            done
        fi
        echo "Copied here by b1air's fake Android." > "$dir/Download/readme.txt"
        chown -R "$owner_uid:$owner_gid" "$dir"
    fi
    dir="$(cd "$dir" && pwd)"

    modprobe dummy_hcd
    modprobe libcomposite
    mountpoint -q /sys/kernel/config || mount -t configfs none /sys/kernel/config

    mkdir -p "$GADGET"
    cd "$GADGET"
    echo "$VID" > idVendor
    echo "$PID" > idProduct
    echo 0x0100 > bcdDevice
    mkdir -p strings/0x409 configs/c.1/strings/0x409 functions/ffs.mtp
    echo "$SERIAL" > strings/0x409/serialnumber
    echo "Google" > strings/0x409/manufacturer
    echo "Pixel 7 (b1air test)" > strings/0x409/product
    echo "MTP" > configs/c.1/strings/0x409/configuration
    echo 500 > configs/c.1/MaxPower
    ln -s functions/ffs.mtp configs/c.1/

    mkdir -p "$FFS" "$STATE"
    mount -t functionfs mtp "$FFS"

    cat > "$STATE/umtprd.conf" <<EOF
loop_on_disconnect 1
storage "$dir" "Internal shared storage" "rw,uid=$owner_uid,gid=$owner_gid"
manufacturer "Google"
product "Pixel 7 (b1air test)"
serial "$SERIAL"
firmware_version "14"
mtp_extensions "microsoft.com: 1.0; android.com: 1.0;"
interface "MTP"
usb_vendor_id  $VID
usb_product_id $PID
usb_class 0x6
usb_subclass 0x1
usb_protocol 0x1
usb_dev_version 0x0100
usb_functionfs_mode 0x1
usb_dev_path   "$FFS/ep0"
usb_epin_path  "$FFS/ep1"
usb_epout_path "$FFS/ep2"
usb_epint_path "$FFS/ep3"
usb_max_packet_size 0x200
EOF
    "$umtprd" -conf "$STATE/umtprd.conf" > "$STATE/umtprd.log" 2>&1 &
    echo $! > "$STATE/umtprd.pid"

    # The descriptors have to be written to ep0 before the gadget binds.
    local i
    for i in $(seq 50); do [[ -e "$FFS/ep1" ]] && break; sleep 0.1; done
    [[ -e "$FFS/ep1" ]] || { tail "$STATE/umtprd.log" >&2; down; die "umtprd did not start"; }
    local udc
    udc="$(ls /sys/class/udc | grep -m1 dummy_udc)" || die "no dummy_udc"
    echo "$udc" > UDC
    echo "up: $dir as \"Pixel 7 (b1air test)\" ($SERIAL) — it shows in Files in a few seconds"
}

down() {
    if [[ -d "$GADGET" ]]; then
        echo "" > "$GADGET/UDC" 2>/dev/null || true
    fi
    if [[ -f "$STATE/umtprd.pid" ]]; then
        kill "$(cat "$STATE/umtprd.pid")" 2>/dev/null || true
        sleep 0.3
    fi
    mountpoint -q "$FFS" && umount "$FFS"
    rmdir "$FFS" 2>/dev/null || true
    if [[ -d "$GADGET" ]]; then
        rm -f "$GADGET/configs/c.1/ffs.mtp"
        rmdir "$GADGET/configs/c.1/strings/0x409" "$GADGET/configs/c.1" \
              "$GADGET/functions/ffs.mtp" "$GADGET/strings/0x409" "$GADGET" 2>/dev/null || true
    fi
    modprobe -r dummy_hcd 2>/dev/null || true
    rm -rf "$STATE"
    echo "down"
}

case "${1:-}" in
    up)   shift; up "$@" ;;
    down) down ;;
    *)    sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
