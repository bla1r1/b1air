#!/usr/bin/env bash
# check-install.sh — after install.sh, is the desktop actually wired up?
#
# Every program the sway config starts through $b1airBin — keybindings,
# autostart — must exist there and be executable. A clean install that stopped
# half way (it once did, on a missing ~/.local/share/icons) left the config in
# place but $b1airBin pointing at nothing, and every shortcut dead.
set -uo pipefail
CONF="${HOME}/.config/sway"
[[ -f "$CONF/config" ]] || { echo "check-install: no $CONF/config" >&2; exit 1; }

bin="$(sed -n 's/^set \$b1airBin[[:space:]]\+//p' "$CONF/conf.d/variables.conf" | head -1)"
bin="${bin//\$HOME/$HOME}"
[[ -n "$bin" && -d "$bin" ]] || { echo "check-install: \$b1airBin is '$bin', not a directory" >&2; exit 1; }

missing=0 checked=0
for prog in $(grep -ho '\$b1airBin/[A-Za-z0-9_-]\+' "$CONF"/conf.d/*.conf | sort -u | sed 's|\$b1airBin/||'); do
    checked=$((checked + 1))
    if [[ ! -x "$bin/$prog" ]]; then
        echo "check-install: missing $bin/$prog" >&2
        missing=$((missing + 1))
    fi
done
# And the ones started by name (`exec b1air-shell ...`): found through the
# session's PATH, which b1air-session puts $b1airBin and /usr/local/bin on.
for prog in $(grep -hoE '\bexec(_always)?[[:space:]]+(--no-startup-id[[:space:]]+)?b1air-[A-Za-z0-9_-]+' "$CONF"/conf.d/*.conf \
        | grep -oE 'b1air-[A-Za-z0-9_-]+$' | sort -u); do
    checked=$((checked + 1))
    if ! PATH="$bin:/usr/local/bin:$PATH" command -v "$prog" >/dev/null; then
        echo "check-install: missing $prog (started by name)" >&2
        missing=$((missing + 1))
    fi
done
for unit in "$HOME"/.config/systemd/user/b1air-*.service; do
    [[ -f "$unit" ]] || continue
    exe="$(sed -n 's/^ExecStart=\([^ ]*\).*/\1/p' "$unit" | head -1)"
    checked=$((checked + 1))
    [[ -x "$exe" ]] || { echo "check-install: $(basename "$unit") starts missing $exe" >&2; missing=$((missing + 1)); }
done
echo "check-install: \$b1airBin=$bin, $checked programs, $missing missing"
[[ $missing -eq 0 ]]
