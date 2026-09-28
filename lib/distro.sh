# shellcheck shell=bash
# =============================================================================
# lib/distro.sh — distribution detection and a thin package-manager layer
#
# Sourced by install.sh, install-ui.sh and update-dotfiles.sh, so the three of
# them agree on what "this system" is and how to put a package on it. Nothing
# here prints to stdout except functions whose output is their return value.
#
# Families, not distributions: everything is keyed on the package manager, and
# derivatives are folded into the family they take their packages from.
#
#   arch      pacman (+ AUR)    Arch, EndeavourOS, Manjaro, CachyOS, Garuda
#   debian    apt               Debian 13+, Ubuntu 25.04+, Mint, Pop!_OS, ...
#   fedora    dnf               Fedora 40+, Nobara, Ultramarine
#   opensuse  zypper            openSUSE Tumbleweed / Slowroll
# =============================================================================

B1AIR_FAMILIES="arch debian fedora opensuse"

# Prints the family name, or nothing when the system is not one we know.
detect_distro() {
    [[ -r /etc/os-release ]] || { [[ -f /etc/arch-release ]] && echo arch; return 0; }
    local id id_like word
    id="$(. /etc/os-release && echo "${ID:-}")"
    id_like="$(. /etc/os-release && echo "${ID_LIKE:-}")"
    for word in $id $id_like; do
        case "$word" in
            arch|archarm|endeavouros|manjaro|cachyos|garuda)  echo arch;     return 0 ;;
            debian|ubuntu|linuxmint|pop|elementary|zorin|neon) echo debian;   return 0 ;;
            fedora|nobara|ultramarine)                         echo fedora;   return 0 ;;
            opensuse|opensuse-tumbleweed|opensuse-slowroll|suse) echo opensuse; return 0 ;;
        esac
    done
    return 0
}

distro_pretty_name() {
    (. /etc/os-release 2>/dev/null && echo "${PRETTY_NAME:-${NAME:-Linux}}") || echo Linux
}

# ── Package queries ──────────────────────────────────────────────────────────

# pkg_installed <family> <pkg>
pkg_installed() {
    local family="$1" pkg="$2"
    case "$family" in
        arch)     pacman -Qi "$pkg" >/dev/null 2>&1 || pacman -Qg "$pkg" >/dev/null 2>&1 ;;
        debian)   [[ "$(dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null)" == "install ok installed" ]] ;;
        fedora|opensuse) rpm -q --whatprovides "$pkg" >/dev/null 2>&1 ;;
        *) return 1 ;;
    esac
}

# pkg_available <family> <pkg> — is there something in the configured
# repositories by that name (installed or not)?
pkg_available() {
    local family="$1" pkg="$2"
    case "$family" in
        arch)     pacman -Si "$pkg" >/dev/null 2>&1 || pacman -Sg "$pkg" >/dev/null 2>&1 ;;
        # `apt-cache show` succeeds for purely virtual names too, which then
        # fail to install; a real candidate version is the honest test.
        # Captured first, not piped into `grep -q`: grep exits at the first
        # match, apt-cache dies of SIGPIPE, and under `set -o pipefail` the
        # whole test reads as "not available" for packages that are.
        debian)   local policy
                  policy="$(apt-cache policy "$pkg" 2>/dev/null)"
                  grep -qE '^[[:space:]]*Candidate:[[:space:]]+[^(]' <<< "$policy" ;;
        # A capability such as pkgconfig(libseat) is looked up by what
        # provides it; a plain name by name.
        fedora)   if [[ "$pkg" == *"("* ]]; then
                      [[ -n "$(dnf -q repoquery --whatprovides "$pkg" 2>/dev/null)" ]]
                  else
                      dnf -q info "$pkg" >/dev/null 2>&1
                  fi ;;
        opensuse) if [[ "$pkg" == *"("* ]]; then
                      zypper -n -q search --provides -x "$pkg" >/dev/null 2>&1
                  else
                      zypper -n -q search -x "$pkg" >/dev/null 2>&1
                  fi ;;
        *) return 1 ;;
    esac
}

# ── Package actions (always through sudo; callers check DRY_RUN) ─────────────

pm_refresh() {
    local family="$1"
    case "$family" in
        arch)     sudo pacman -Sy --noconfirm ;;
        debian)   sudo apt-get update ;;
        fedora)   sudo dnf -y makecache ;;
        opensuse) sudo zypper -n refresh ;;
    esac
}

# pm_install <family> <pkg...> — one transaction, fails as a whole.
pm_install() {
    local family="$1"; shift
    [[ $# -gt 0 ]] || return 0
    case "$family" in
        arch)     sudo pacman -S --needed --noconfirm "$@" ;;
        # No recommends: every package the desktop needs is named explicitly,
        # and Debian's recommends for sddm and friends drag in half of Plasma.
        debian)   sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$@" ;;
        fedora)   sudo dnf install -y "$@" ;;
        opensuse) sudo zypper -n install --no-recommends "$@" ;;
        *) return 1 ;;
    esac
}

# The whiptail provider, which install-ui.sh needs before anything else.
whiptail_package() {
    case "$1" in
        arch) echo libnewt ;;
        debian) echo whiptail ;;
        fedora|opensuse) echo newt ;;
    esac
}

# ── Package lists ────────────────────────────────────────────────────────────
#
# packages/<name>.txt: whitespace-separated names, `#` starts a comment, and a
# leading `?` marks a package as optional — installed when the repositories
# have it, reported and skipped when they do not. Optional is for things that
# exist under that name on some releases of a family and not others; the
# desktop must start without every one of them.

# read_package_list <file> required|optional
read_package_list() {
    local file="$1" want="$2" line word
    [[ -f "$file" ]] || return 0
    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%%#*}"
        for word in $line; do
            if [[ "$word" == \?* ]]; then
                [[ "$want" == optional ]] && echo "${word#\?}"
            else
                [[ "$want" == required ]] && echo "$word"
            fi
        done
    done < "$file"
    return 0
}

# ── Qt ───────────────────────────────────────────────────────────────────────
#
# Debian keeps Qt under /usr/lib/<triplet>/qt6, Fedora and openSUSE under
# /usr/lib64/qt6, Arch under /usr/lib/qt6 — and only some of them put a
# `qmake6` on PATH. Ask whichever Qt tool exists rather than guess the path.

qt_query() {
    local var="$1" tool
    for tool in qmake6 qtpaths6 qmake-qt6 \
                /usr/lib/qt6/bin/qmake /usr/lib64/qt6/bin/qmake \
                /usr/lib/qt6/bin/qtpaths /usr/lib64/qt6/bin/qtpaths \
                /usr/lib/*-linux-gnu*/qt6/bin/qmake; do
        command -v "$tool" >/dev/null 2>&1 || continue
        case "$tool" in
            *qtpaths*) "$tool" --query "$var" 2>/dev/null && return 0 ;;
            *)         "$tool" -query "$var" 2>/dev/null && return 0 ;;
        esac
    done
    return 1
}

qt_qml_dir() {
    local dir
    dir="$(qt_query QT_INSTALL_QML)" && [[ -n "$dir" ]] && { echo "$dir"; return 0; }
    for dir in /usr/lib/qt6/qml /usr/lib64/qt6/qml /usr/lib/*-linux-gnu*/qt6/qml; do
        [[ -d "$dir" ]] && { echo "$dir"; return 0; }
    done
    echo /usr/lib/qt6/qml
}

# version_ge <a> <b> — true when dotted version a >= b.
version_ge() {
    [[ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n1)" == "$2" ]]
}

# ── Compositor ───────────────────────────────────────────────────────────────

# swayfx installs its binary as `sway` on Arch and Fedora, so the name alone
# says nothing; its version string does.
have_swayfx() {
    command -v swayfx >/dev/null 2>&1 && return 0
    command -v sway >/dev/null 2>&1 || return 1
    local version
    version="$(sway --version 2>&1)"
    grep -qi swayfx <<< "$version"
}

# Plain sway stops at every swayFX-only directive with "Unknown/invalid
# command" and a swaynag bar on each login. Comment those lines out of the
# deployed copy (never the repository's), and drop the `, blur disable` tails
# from window rules whose other half plain sway does understand. Idempotent:
# a commented line no longer starts with the keyword.
strip_swayfx_directives() {
    local dir="${1:-$HOME/.config/sway/conf.d}" f
    [[ -d "$dir" ]] || return 0
    for f in "$dir"/*.conf; do
        [[ -f "$f" ]] || continue
        sed -i -E \
            -e 's/^([[:space:]]*)((smart_)?corner_radius|blur(_[a-z_]+)?|shadows(_on_csd)?|shadow_[a-z_]+|default_dim_inactive|dim_inactive_colors\.[a-z]+|titlebar_separator|scratchpad_minimize|layer_effects)([[:space:]]|$)/\1# swayfx-only: \2\6/' \
            -e 's/,[[:space:]]*blur[[:space:]]+(enable|disable)//g' \
            "$f"
    done
}

# ── Where the suite is installed, and configs that point there ───────────────
#
# install.sh puts the b1air binaries in /usr/local/bin when it has root and in
# ~/.local/bin when it does not. The sway config and the systemd user units
# name that directory in one place each ($b1airBin, ExecStart/ExecReload), and
# the copies in this repository say ~/.local/bin. So every deployment of
# .config has to be "rendered" for this machine — or an update that copies the
# repository's variables.conf over the installed one leaves autostart and every
# key binding pointing at an empty directory: no daemon, no shell.

b1air_install_prefix() {
    if [[ -x /usr/local/bin/b1air-daemon ]]; then
        echo /usr/local/bin
    else
        echo "$HOME/.local/bin"
    fi
}

# render_config_tree <dir mirroring ~/.config> <prefix>
render_config_tree() {
    local dir="$1" prefix="$2" unit
    local vars="$dir/sway/conf.d/variables.conf"
    if [[ -f "$vars" ]]; then
        sed -i "s|^set \$b1airBin .*|set \$b1airBin ${prefix}|" "$vars"
    fi
    for unit in "$dir"/systemd/user/b1air-*.service; do
        [[ -f "$unit" ]] || continue
        sed -i "s|^ExecStart=.*/b1air-|ExecStart=${prefix}/b1air-|; s|^ExecReload=.*/b1air-|ExecReload=${prefix}/b1air-|" "$unit"
    done
    if ! have_swayfx; then
        strip_swayfx_directives "$dir/sway/conf.d"
    fi
}

# ── Desktop entries ──────────────────────────────────────────────────────────
#
# `make install` writes the suite's entries next to its binaries: /usr/share
# for a system install, ~/.local/share for a per-user one. Earlier versions of
# install.sh and the updater also copied them into ~/.local/share/applications
# with Exec=~/.local/bin/... — even when the binaries went to /usr/local/bin.
# A per-user entry shadows the system one of the same name, so the menu kept
# launching a path that did not exist. Remove those whose binary is gone.
#
# prune_stale_desktop_entries [backup dir]
prune_stale_desktop_entries() {
    local backup="${1:-}" dir="$HOME/.local/share/applications" f exe pruned=0
    [[ -d "$dir" ]] || return 0
    for f in "$dir"/b1air-*.desktop; do
        [[ -f "$f" ]] || continue
        exe="$(sed -n 's/^Exec=\([^ ]*\).*/\1/p' "$f" | head -n1)"
        [[ "$exe" == /* && ! -x "$exe" ]] || continue
        if [[ -n "$backup" ]]; then
            mkdir -p "$backup/applications"
            mv "$f" "$backup/applications/"
        else
            rm -f "$f"
        fi
        pruned=$((pruned + 1))
    done
    if (( pruned > 0 )); then
        update-desktop-database "$dir" >/dev/null 2>&1 || true
    fi
    echo "$pruned"
}
