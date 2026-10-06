#!/usr/bin/env bash
# nested.sh — the b1air session in a window of the desktop you are in (KDE,
# GNOME, another sway), to try a new build without logging out.
#
#   tools/nested.sh
#
# Runs swayfx with the wlroots Wayland backend: it becomes one window of the
# desktop it was started from, and the window can be resized like any other.
# It uses the installed b1air (update-dotfiles.sh first) and your own
# ~/.config, so what is set inside stays set.
#
# Kept apart from the desktop outside: the session's config hands
# WAYLAND_DISPLAY and XDG_CURRENT_DESKTOP to systemd and D-Bus, which in the
# outer session would send the next app you start from its menu into this
# window. So it runs with a runtime directory and a D-Bus session of its own;
# sound still goes to the outer PipeWire.
#
# Close it with the session's own exit (Mod+Shift+E) or by closing the window.
set -euo pipefail

host_rt="${XDG_RUNTIME_DIR:?no XDG_RUNTIME_DIR}"
host_wl="${WAYLAND_DISPLAY:?start it from a Wayland session}"
case "$host_wl" in /*) ;; *) host_wl="$host_rt/$host_wl" ;; esac
[[ -S "$host_wl" ]] || { echo "nested: $host_wl is not a Wayland socket" >&2; exit 1; }

compositor="$(command -v swayfx || command -v sway || true)"
[[ -n "$compositor" ]] || { echo "nested: neither swayfx nor sway is installed" >&2; exit 1; }

rt="$(mktemp -d "${TMPDIR:-/tmp}/b1air-nested.XXXXXX")"
chmod 700 "$rt"
trap 'rm -rf "$rt"' EXIT

unset DISPLAY SWAYSOCK I3SOCK DBUS_SESSION_BUS_ADDRESS
export XDG_RUNTIME_DIR="$rt"
export WAYLAND_DISPLAY="$host_wl"          # the outer desktop, by its full path
export WLR_BACKENDS=wayland
export XDG_CURRENT_DESKTOP=sway XDG_SESSION_TYPE=wayland
# Sound: the outer session's PipeWire and its PulseAudio socket.
export PIPEWIRE_RUNTIME_DIR="$host_rt"
[[ -S "$host_rt/pulse/native" ]] && export PULSE_SERVER="unix:$host_rt/pulse/native"

log="${XDG_CACHE_HOME:-$HOME/.cache}/b1air-nested.log"
mkdir -p "$(dirname "$log")"
echo "nested: $compositor in a window; its log is $log"
# Appended, with a line per run: the run before the one that went wrong is
# often the one that says why.
echo "===== $(date '+%F %T') nested session =====" >> "$log"
dbus-run-session -- "$compositor" >> "$log" 2>&1
