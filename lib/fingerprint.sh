# shellcheck shell=bash
# =============================================================================
# lib/fingerprint.sh — the right driver for this machine's fingerprint reader
#
# Sourced by install.sh and update-dotfiles.sh (after lib/distro.sh, and with
# their log/ok/warn functions defined). fprintd alone drives only the readers
# libfprint supports; many ThinkPads carry a Validity/Synaptics 06cb:009a, and
# many other laptops a Goodix, that need a driver of their own — so the
# reader stayed dead and Settings → User had nothing to enrol with.
#
# The reader is found by its USB id. libfprint's own hwdb, installed with it,
# says whether it supports that id; the table below names the driver for the
# ones it does not. Readers that need their firmware flashed first (the
# goodixtls forks) are left alone: that is not something to do unasked.
# =============================================================================

# id -> AUR package that drives it, replacing fprintd (python-validity) or
# libfprint (the Goodix builds).
declare -A B1AIR_FP_AUR=(
    [138a:0090]=python-validity [138a:0097]=python-validity
    [138a:009d]=python-validity [06cb:009a]=python-validity
    [27c6:5335]=libfprint-goodix53x5 [27c6:5385]=libfprint-goodix53x5 [27c6:5395]=libfprint-goodix53x5
    [27c6:533c]=libfprint-goodix-53xc
    [27c6:521d]=libfprint-goodix-521d [27c6:538d]=libfprint-goodix-521d
    [27c6:550a]=libfprint-2-tod1-goodix
    [27c6:55a2]=libfprint-goodix-55a2
)

# Vendors that make fingerprint readers and nothing else on a laptop's bus.
B1AIR_FP_VENDORS="06cb 138a 27c6 04f3 1c7a 10a5 2808 298d 08ff 147e 0483 05ba 2541 1491"

# Prints the reader's vendor:product, lower case, or nothing.
fingerprint_reader_id() {
    local d v p
    for d in /sys/bus/usb/devices/*; do
        [[ -r $d/idVendor && -r $d/idProduct ]] || continue
        v="$(<"$d/idVendor")"; p="$(<"$d/idProduct")"
        v="${v,,}"; p="${p,,}"
        [[ " $B1AIR_FP_VENDORS " == *" $v "* ]] || continue
        # Synaptics also makes touchpads; those are on i2c or PS/2, but a USB
        # one would be HID. A reader is vendor-specific (class ff) or none.
        if [[ -r $d/bDeviceClass && "$(<"$d/bDeviceClass")" == "03" ]]; then continue; fi
        echo "$v:$p"
        return 0
    done
}

# 0 when the installed libfprint lists the id as supported.
libfprint_supports() {
    local id="$1" hwdb
    hwdb="$(ls /usr/lib/udev/hwdb.d/*libfprint*.hwdb /lib/udev/hwdb.d/*libfprint*.hwdb 2>/dev/null | head -n1)"
    [[ -n "$hwdb" ]] || return 1
    local pat="usb:v${id%%:*}p${id##*:}"
    # Everything above "Known unsupported devices" is a driver's list.
    awk -v pat="${pat^^}" 'BEGIN{IGNORECASE=1} /^# Known unsupported/ {exit} index(toupper($0), toupper(pat)) == 1 {found=1; exit} END{exit !found}' "$hwdb"
}

# fingerprint_setup <family> [aur_helper] — installs what the reader needs.
# Safe to run on every install and update: does nothing when it is in place.
fingerprint_setup() {
    local family="$1" aur="${2:-}" id pkg
    id="$(fingerprint_reader_id)"
    [[ -n "$id" ]] || return 0
    pkg="${B1AIR_FP_AUR[$id]:-}"

    if [[ -z "$pkg" ]]; then
        if libfprint_supports "$id"; then
            ok "Fingerprint reader $id: supported by fprintd."
        elif pkg_installed "$family" fprintd || pkg_installed "$family" libfprint; then
            warn "Fingerprint reader $id is not supported by libfprint and b1air knows no driver for it."
            warn "Look it up at https://fprint.freedesktop.org/supported-devices.html"
        fi
        return 0
    fi

    if [[ "$family" != arch ]]; then
        warn "Fingerprint reader $id needs $pkg, which is packaged for Arch only; it stays unused here."
        return 0
    fi
    if pacman -Qq "$pkg" >/dev/null 2>&1; then
        ok "Fingerprint reader $id: driver $pkg is installed."
        return 0
    fi
    [[ -n "$aur" ]] || { warn "Fingerprint reader $id needs $pkg from the AUR (skipped: no AUR helper)."; return 0; }

    log "Fingerprint reader $id: installing its driver, $pkg..."
    # Both kinds conflict with what fprintd brought, and pacman's default
    # answer to a conflict under --noconfirm is no. Removed first, without
    # dependency checks: the replacement provides the same thing.
    if [[ "$pkg" == python-validity ]]; then
        pacman -Qq fprintd >/dev/null 2>&1 && sudo pacman -Rdd --noconfirm fprintd
    else
        pacman -Qq libfprint >/dev/null 2>&1 && sudo pacman -Rdd --noconfirm libfprint
    fi
    if ! "$aur" -S --needed --noconfirm "$pkg"; then
        warn "Installing $pkg failed; putting fprintd back."
        sudo pacman -S --needed --noconfirm fprintd || true
        return 0
    fi
    if [[ "$pkg" == python-validity ]]; then
        # The sensor runs on firmware Lenovo ships inside a Windows driver;
        # the package fetches and unpacks it. Then its two services.
        sudo validity-sensors-firmware || warn "Could not fetch the sensor's firmware; run: sudo validity-sensors-firmware"
        sudo systemctl enable --now python3-validity.service open-fprintd.service 2>/dev/null \
            || sudo systemctl enable --now python3-validity.service 2>/dev/null || true
    else
        # fprintd (and pam_fprintd) again, now on top of the Goodix libfprint.
        sudo pacman -S --needed --noconfirm fprintd || true
        sudo systemctl restart fprintd.service 2>/dev/null || true
    fi
    ok "Fingerprint reader $id: $pkg installed."
}
