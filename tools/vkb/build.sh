#!/usr/bin/env bash
# build.sh <out> — builds vkb; needs wayland-client, xkbcommon, wayland-scanner.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"; out="${1:-$here/vkb}"; tmp="$(mktemp -d)"
xml="$here/virtual-keyboard-unstable-v1.xml"   # from wlroots, MIT
wayland-scanner client-header "$xml" "$tmp/vkb-protocol.h"
wayland-scanner private-code "$xml" "$tmp/vkb-protocol.c"
cc -O2 -Wall -Wextra -I"$tmp" -o "$out" "$here/vkb.c" "$tmp/vkb-protocol.c" $(pkg-config --cflags --libs wayland-client xkbcommon)
rm -rf "$tmp"
