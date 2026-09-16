#!/usr/bin/env bash
# =============================================================================
# mem-report.sh — who is using the memory, counted fairly
#
# Lists your processes by PSS (proportional set size): shared libraries are
# split between the processes that map them, so the column adds up to what
# your session really uses. RSS, which `top` shows, counts Qt once per Qt app
# and makes eight small apps look like a gigabyte. Programs with several
# processes (browsers, Electron apps) are summed under one name.
#
#     tools/mem-report.sh          # top 15
#     tools/mem-report.sh 30
# =============================================================================
set -uo pipefail
TOP="${1:-15}"

for p in $(pgrep -u "$USER"); do
    f="/proc/$p/smaps_rollup"
    [[ -r "$f" ]] || continue
    pss=$(awk '/^Pss:/{print $2}' "$f" 2>/dev/null) || continue
    [[ -n "$pss" ]] || continue
    printf '%s %s\n' "$pss" "$(cat "/proc/$p/comm" 2>/dev/null)"
done | awk '{kb[$2]+=$1; n[$2]++} END {for (c in kb) printf "%8.1f MB  %3d  %s\n", kb[c]/1024, n[c], c}' \
     | sort -rn | { printf '%11s  %3s  %s\n' "PSS" "#" "program"; head -n "$TOP"; }

awk '/^MemTotal:/{t=$2} /^MemAvailable:/{a=$2} END {printf "\nsystem: %.1f GB in use of %.1f GB (the top bar\x27s figure)\n", (t-a)/1048576, t/1048576}' /proc/meminfo
for p in $(pgrep -u "$USER"); do awk '/^Pss:/{print $2}' "/proc/$p/smaps_rollup" 2>/dev/null; done \
    | awk '{s+=$1} END {printf "your processes: %.1f GB — the rest is the kernel, system services and other users\n", s/1048576}'
