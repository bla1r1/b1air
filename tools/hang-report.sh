#!/usr/bin/env bash
# =============================================================================
# hang-report.sh — what a frozen b1air app is doing, captured while it is frozen
#
# Run it while the window is hung (from another terminal, a TTY, or SSH):
#
#     tools/hang-report.sh                # b1air-term
#     tools/hang-report.sh b1air-git      # any other app of the suite
#
# It samples the app's threads several times over a few seconds and writes
# everything to ~/b1air-hang-<app>-<time>.txt. The stacks need ptrace, which
# Arch, Debian and Fedora restrict to root by default, so that one step asks
# for sudo; everything else runs as you.
# =============================================================================
set -uo pipefail

APP="${1:-b1air-term}"
SAMPLES="${SAMPLES:-6}"
OUT="$HOME/b1air-hang-${APP}-$(date +%Y%m%d-%H%M%S).txt"

section() { printf '\n===== %s =====\n' "$*"; }

pids="$(pgrep -x "$APP" || true)"
if [[ -z "$pids" ]]; then
    echo "No running '$APP' process." >&2
    exit 1
fi

stack_of() {
    local pid="$1"
    if command -v gdb >/dev/null 2>&1; then
        sudo gdb -p "$pid" -batch -nx \
            -ex "set pagination off" \
            -ex "thread apply all bt 25" 2>/dev/null \
            | grep -E '^(Thread|#)' || echo "(gdb could not attach)"
    elif command -v eu-stack >/dev/null 2>&1; then
        sudo env DEBUGINFOD_URLS= eu-stack -p "$pid" -n 25 2>/dev/null \
            || echo "(eu-stack could not attach)"
    else
        echo "(install gdb or elfutils for stacks)"
    fi
}

{
    section "when / what"
    date
    echo "app: $APP   pids: $(echo $pids)"
    uname -r
    (. /etc/os-release 2>/dev/null && echo "$PRETTY_NAME")

    section "compositor"
    # The binary that is running, not whichever `sway` is first on PATH.
    sway_pid="$(pgrep -x sway | head -n1)"
    if [[ -n "$sway_pid" ]]; then
        "$(readlink -f "/proc/$sway_pid/exe")" --version 2>&1 | head -n1
    else
        echo "sway is not running"
    fi
    if command -v swaymsg >/dev/null 2>&1; then
        t=$(date +%s%N)
        swaymsg -t get_version >/dev/null 2>&1 \
            && echo "swaymsg answered in $(( ($(date +%s%N) - t) / 1000000 )) ms" \
            || echo "swaymsg did not answer"
        swaymsg -t get_tree 2>/dev/null \
            | grep -cE '"(app_id|class)": "[^"]+' \
            | sed 's/^/windows in tree: /'
        swaymsg -t get_tree 2>/dev/null | grep -E '"opacity"' | sort | uniq -c
    fi

    section "session processes"
    ps -o pid,ppid,etime,stat,pcpu,rss,args -u "$USER" \
        | grep -E 'b1air|quickshell|sway|PID' | grep -v -e grep -e hang-report

    for pid in $pids; do
        section "process $pid"
        tr '\0' ' ' < "/proc/$pid/cmdline"; echo
        grep -E '^(State|Threads|VmRSS|SigIgn|SigBlk)' "/proc/$pid/status"
        echo "env:"; tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null \
            | grep -E '^(QT_|QSG_|WAYLAND_DISPLAY|XDG_SESSION_TYPE|B1AIR_)' | sed 's/^/  /'
        echo "fds: $(ls "/proc/$pid/fd" 2>/dev/null | wc -l)"

        section "thread states over ${SAMPLES} samples (pid $pid)"
        # Per thread: state and kernel wait channel. A main thread stuck in R
        # is busy; stuck in S on the same wchan every time is blocked.
        for i in $(seq 1 "$SAMPLES"); do
            echo "-- sample $i"
            for task in /proc/$pid/task/*; do
                tid="${task##*/}"
                printf '  %-8s %-18s %s %s\n' "$tid" "$(cat "$task/comm" 2>/dev/null)" \
                    "$(awk '{print $3}' "$task/stat" 2>/dev/null)" \
                    "$(cat "$task/wchan" 2>/dev/null)"
            done
            sleep 0.5
        done

        section "CPU used by $pid during 3 s"
        a=$(awk '{print $14+$15}' "/proc/$pid/stat"); sleep 3; b=$(awk '{print $14+$15}' "/proc/$pid/stat")
        echo "$(( (b - a) * 100 / $(getconf CLK_TCK) / 3 ))% of one core"

        section "stacks of $pid (3 snapshots)"
        for i in 1 2 3; do
            echo "-- snapshot $i"
            stack_of "$pid"
            sleep 1
        done
    done
} > "$OUT" 2>&1

echo "Report written to: $OUT"
