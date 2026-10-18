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

# shellcheck disable=SC2034  # read by the scripts that source this file
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

# ── Editions ─────────────────────────────────────────────────────────────────
#
# An edition is a set of packages on top of another edition. minimal is the
# desktop itself: packages/<family>.txt and packages/arch-aur.txt. Every
# other one is a directory packages/editions/<name>/ holding
#
#   parent            the edition it adds to (one word: minimal, default, ...)
#   <family>.txt      what it adds, in the same format as packages/<family>.txt
#   arch-aur.txt      what it adds from the AUR
#   description       one line for the installer's menu
#
# so a new edition is a new directory: name its parent and list what it adds.
# The one installed is kept in /etc/b1air/edition, for update-dotfiles.sh.

B1AIR_EDITION_FILE=/etc/b1air/edition
B1AIR_DEFAULT_EDITION=default

# The editions there are, minimal first, one per line.
editions_available() {
    local repo="$1" dir
    echo minimal
    for dir in "$repo"/packages/editions/*/; do
        [[ -f "$dir/parent" ]] && basename "$dir"
    done
}

# edition_chain <repo> <edition> — minimal, then each edition down to the
# one asked for, one per line. Fails for an unknown edition or a loop.
edition_chain() {
    local repo="$1" ed="$2" chain=() parent seen=" "
    while [[ "$ed" != minimal ]]; do
        [[ -f "$repo/packages/editions/$ed/parent" ]] || return 1
        [[ "$seen" == *" $ed "* ]] && return 1
        seen+="$ed "
        chain=("$ed" "${chain[@]}")
        read -r parent < "$repo/packages/editions/$ed/parent" || return 1
        ed="${parent:-minimal}"
    done
    echo minimal
    printf '%s\n' "${chain[@]}"
}

# edition_lists <repo> <family|arch-aur> <edition> — the package list files
# that make up the edition, in order; only the ones that exist.
edition_lists() {
    local repo="$1" name="$2" ed="$3" layer file
    while IFS= read -r layer; do
        if [[ "$layer" == minimal ]]; then file="$repo/packages/$name.txt"
        else file="$repo/packages/editions/$layer/$name.txt"; fi
        [[ -f "$file" ]] && echo "$file"
    done < <(edition_chain "$repo" "$ed")
}

# The edition this machine was installed as; the default for one installed
# before there were editions, which had what default has now.
installed_edition() {
    local ed=""
    [[ -r "$B1AIR_EDITION_FILE" ]] && read -r ed < "$B1AIR_EDITION_FILE"
    echo "${ed:-$B1AIR_DEFAULT_EDITION}"
}

# edition_description <repo> <edition> — its line for a menu.
edition_description() {
    local repo="$1" ed="$2"
    if [[ "$ed" == minimal ]]; then echo "The desktop and its apps, nothing more"
    else head -n1 "$repo/packages/editions/$ed/description" 2>/dev/null || echo "$ed"; fi
}

# record_edition <edition> <dry-run 0|1> — into /etc/b1air/edition (sudo).
record_edition() {
    local ed="$1" dry="${2:-0}"
    if [[ "$dry" -eq 1 ]]; then echo "Would record edition '$ed' in $B1AIR_EDITION_FILE" >&2; return 0; fi
    sudo install -d -m 755 "$(dirname "$B1AIR_EDITION_FILE")" \
        && printf '%s\n' "$ed" | sudo tee "$B1AIR_EDITION_FILE" >/dev/null
}

# install_edition_flatpaks <repo> <edition> <dry-run 0|1> — the Flathub apps
# of every layer (packages/editions/*/flatpak.txt), for this account. A line
# is `<app id> [command]`: where the command is already there, the
# distribution's packages brought the app and the Flatpak is skipped.
install_edition_flatpaks() {
    local repo="$1" ed="$2" dry="${3:-0}" layer file id cmd todo=()
    while IFS= read -r layer; do
        file="$repo/packages/editions/$layer/flatpak.txt"
        [[ -f "$file" ]] || continue
        while read -r id cmd _; do
            [[ -z "$id" || "$id" == \#* ]] && continue
            [[ -n "${cmd:-}" ]] && command -v "$cmd" >/dev/null 2>&1 && continue
            flatpak info "$id" >/dev/null 2>&1 && continue
            todo+=("$id")
        done < "$file"
    done < <(edition_chain "$repo" "$ed")
    [[ ${#todo[@]} -gt 0 ]] || return 0
    if ! command -v flatpak >/dev/null 2>&1; then
        echo "flatpak is not installed; skipped from Flathub: ${todo[*]}" >&2
        return 0
    fi
    if [[ "$dry" -eq 1 ]]; then echo "Would install from Flathub (--user): ${todo[*]}" >&2; return 0; fi
    flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo >&2 \
        || { echo "Could not add Flathub; skipped: ${todo[*]}" >&2; return 0; }
    for id in "${todo[@]}"; do
        flatpak install --user --noninteractive flathub "$id" >&2 \
            || echo "Could not install $id from Flathub. Later: flatpak install --user flathub $id" >&2
    done
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

# arch_enable_multilib — switch on Arch's [multilib] repository, where Wine
# and its 32-bit libraries are. x86_64 only: there is no multilib, and no
# Wine, on aarch64. Prints nothing; returns non-zero when it could not.
arch_enable_multilib() {
    [[ "$(uname -m)" == x86_64 ]] || return 1
    grep -qE '^[[:space:]]*\[multilib\]' /etc/pacman.conf && return 0
    grep -qE '^#[[:space:]]*\[multilib\]' /etc/pacman.conf || return 1
    # The stock pacman.conf has the section commented out as two lines:
    # "#[multilib]" and the "#Include = …" right under it.
    sudo sed -i '/^#[[:space:]]*\[multilib\]/{s/^#[[:space:]]*//;n;s/^#[[:space:]]*//}' /etc/pacman.conf
}

# pm_install <family> <pkg...> — one transaction, fails as a whole.
# The Vulkan driver package for the GPU the kernel drives (Arch names).
vulkan_driver_package() {
    local d drivers=""
    for d in /sys/class/drm/card*/device/driver; do
        [[ -e "$d" ]] && drivers+=" $(basename "$(readlink -f "$d")")"
    done
    case "$drivers" in
        *" i915"*|*" xe"*) echo vulkan-intel ;;
        *" amdgpu"*|*" radeon"*) echo vulkan-radeon ;;
        *" nouveau"*) echo vulkan-nouveau ;;
        *" nvidia"*) echo nvidia-utils ;;
        *) echo vulkan-swrast ;;
    esac
}

pm_install() {
    local family="$1"; shift
    [[ $# -gt 0 ]] || return 0
    case "$family" in
        # Only what is missing (pacman -T, which knows provides too): given
        # an installed package, --needed still prints "warning: … is up to
        # date -- skipping" for each, a screenful that reads like trouble.
        arch)
            local missing=()
            mapfile -t missing < <(pacman -T "$@" 2>/dev/null)
            [[ ${#missing[@]} -gt 0 ]] || return 0
            # Not what something installed conflicts with: fprintd beside
            # the fprintd-clients-git a python-validity reader runs on. pacman
            # puts the whole list in one transaction, and that one conflict
            # failed it — inter-font and the rest never went in either.
            local conflicts keep=() p
            conflicts=" $(LC_ALL=C pacman -Qi 2>/dev/null | sed -n 's/^Conflicts With *: //p' \
                | tr -s ' ' '\n' | sed 's/[<>=].*//' | grep -vx 'None' | sort -u | tr '\n' ' ') "
            for p in "${missing[@]}"; do
                if [[ "$conflicts" == *" $p "* ]]; then
                    echo "  $p: left out, an installed package conflicts with it" >&2
                    continue
                fi
                keep+=("$p")
            done
            [[ ${#keep[@]} -gt 0 ]] || return 0
            # A Vulkan driver, when something asks for one (zed) and none is
            # installed: the one for this GPU. Left to pacman, --noconfirm
            # took its first offer, nvidia-utils, on an Intel laptop.
            if ! pacman -T vulkan-driver >/dev/null 2>&1 \
                    && LC_ALL=C pacman -Si "${keep[@]}" 2>/dev/null | grep '^Depends On' | grep -qw 'vulkan-driver'; then
                keep=("$(vulkan_driver_package)" "${keep[@]}")
            fi
            # One at a time when all at once fails, so one package that cannot
            # go in does not keep the others out.
            sudo pacman -S --needed --noconfirm "${keep[@]}" && return 0
            local failed=0
            for p in "${keep[@]}"; do
                sudo pacman -S --needed --noconfirm "$p" || failed=1
            done
            return "$failed" ;;
        # No recommends: every package the desktop needs is named explicitly,
        # and Debian's recommends for sddm and friends drag in half of Plasma.
        debian)   sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "$@" ;;
        fedora)   sudo dnf install -y "$@" ;;
        opensuse) sudo zypper -n install --no-recommends "$@" ;;
        *) return 1 ;;
    esac
}

# pm_remove <family> <pkg>... — the packages themselves, not what depends on
# them or what they pulled in: a package something else needs is refused by
# the package manager, and the caller keeps going.
pm_remove() {
    local family="$1"; shift
    [[ $# -gt 0 ]] || return 0
    case "$family" in
        arch)     sudo pacman -R --noconfirm "$@" ;;
        debian)   sudo env DEBIAN_FRONTEND=noninteractive apt-get remove -y "$@" ;;
        fedora)   sudo dnf remove -y --noautoremove "$@" ;;
        opensuse) sudo zypper -n remove --no-clean-deps "$@" ;;
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

# ── Arch: b1air as pacman packages ───────────────────────────────────────────
#
# On Arch the suite and our swayfx are built into packages
# (packaging/arch/b1air, packaging/arch/b1air-swayfx) and installed with
# pacman, so every file they put in the system is owned and removable. The
# other distributions still get `make install` and tools/build-swayfx.sh.
# B1AIR_NO_PACKAGE=1 keeps the old way on Arch too.

arch_packaging() {
    [[ "${DISTRO:-}" == arch && "${B1AIR_NO_PACKAGE:-0}" != 1 ]] && command -v makepkg >/dev/null 2>&1
}

# arch_package_current <name> — true when the installed package is the
# version its PKGBUILD in this checkout would build now.
arch_package_current() {
    local dir="$REPO_DIR/packaging/arch/$1" have want
    have="$(pacman -Q "$1" 2>/dev/null | cut -d' ' -f2)" || return 1
    want="$(cd "$dir" && makepkg --printsrcinfo 2>/dev/null \
        | awk '$1=="pkgver"{v=$3} $1=="pkgrel"{r=$3} END{print v"-"r}')"
    [[ -n "$have" && "$have" == "$want" ]]
}

# What `sudo make install` and install.sh's own copies put in /usr before
# there was a package. pacman will not install over a file it does not own,
# so the first package install takes these over (--overwrite); after that
# they are the package's.
B1AIR_PACKAGE_OVERWRITE=(
    '/usr/bin/b1air-*' '/usr/share/b1air/*' '/usr/share/b1air-shell/*'
    '/usr/share/applications/b1air-*' '/usr/share/icons/hicolor/scalable/apps/b1air-*'
    '/usr/share/icons/b1air-cursors/*' '/usr/share/fonts/b1air/*'
    '/usr/share/wayland-sessions/b1air.desktop' '/usr/share/xdg-desktop-portal/b1air-portals.conf'
    '/usr/share/sddm/themes/b1air/*' '/usr/lib/qt6/qml/B1air/*' '/usr/lib64/qt6/qml/B1air/*'
)

# arch_build_package <name> — build packaging/arch/<name> as this user
# (makepkg refuses root; -s asks sudo for the build dependencies only) and
# install the result with pacman. --ask 4 answers yes to "remove the
# conflicting package" (sway for b1air-swayfx), which --noconfirm answers no.
arch_build_package() {
    local dir="$REPO_DIR/packaging/arch/$1" files=() glob overwrite=()
    for glob in "${B1AIR_PACKAGE_OVERWRITE[@]}"; do overwrite+=(--overwrite "$glob"); done
    (cd "$dir" && makepkg -sf --noconfirm --needed) || return 1
    mapfile -t files < <(cd "$dir" && makepkg --packagelist)
    sudo pacman -U --noconfirm --ask 4 "${overwrite[@]}" "${files[@]}" || return 1
    # pacman does not flush: on btrfs a hard reset soon after leaves the
    # package's files at 0 bytes, the session and login theme with them.
    sync
    rm -f "${files[@]}"
}

# retire_unpackaged_b1air — what earlier installs put outside the package and
# would now shadow it: the suite and swayfx in /usr/local (ahead of /usr/bin
# on PATH), per-user copies in ~/.local/bin (ahead of both), and copies in
# /etc of a unit and udev rules the package ships in /usr/lib (/etc wins).
retire_unpackaged_b1air() {
    local sys=() f
    for f in /usr/local/bin/b1air-* /usr/local/lib/b1air-swayfx /usr/local/share/b1air \
             /etc/systemd/system/b1air-fido-uhid.service /etc/udev/rules.d/99-b1air-*.rules \
             /etc/udev/rules.d/99-uinput.rules; do
        [[ -e "$f" ]] && sys+=("$f")
    done
    # sway* in /usr/local only when it is ours (the stamp build-swayfx.sh left).
    if [[ -f /usr/local/share/b1air/swayfx.stamp ]]; then
        for f in /usr/local/bin/{sway,swayfx,swaybar,swaymsg,swaynag}; do
            [[ -e "$f" || -L "$f" ]] && sys+=("$f")
        done
    fi
    if (( ${#sys[@]} > 0 )); then
        sudo rm -rf "${sys[@]}"
        sudo systemctl daemon-reload 2>/dev/null || true
        sudo udevadm control --reload-rules 2>/dev/null || true
    fi
    rm -f "$HOME"/.local/bin/b1air-*
    hash -r
}

# ── Where the suite is installed, and configs that point there ───────────────
#
# install.sh puts the b1air binaries in /usr/bin as the b1air package (Arch),
# else in /usr/local/bin when it has root and in ~/.local/bin when it does not.
# The sway config and the systemd user units name that directory in one
# place each ($b1airBin, ExecStart/ExecReload), and the copies in this
# repository say ~/.local/bin. So every deployment of
# .config has to be "rendered" for this machine — or an update that copies the
# repository's variables.conf over the installed one leaves autostart and every
# key binding pointing at an empty directory: no daemon, no shell.

b1air_install_prefix() {
    if pacman -Qq b1air >/dev/null 2>&1; then
        echo /usr/bin
    elif [[ -x /usr/local/bin/b1air-daemon ]]; then
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

# Apps the suite no longer has, removed where an older install put them:
# the program, its desktop entry, its icon and its window's QML (which
# would otherwise sit in the shell's search path for ever). The user's own
# files are left alone — notes stay in ~/.local/share/b1air-notes.
#   notes: replaced by Zed as the editor on Mod+I.
B1AIR_RETIRED_APPS="notes"

# retire_old_apps — idempotent; asks for sudo only when there is something
# system-wide to remove.
retire_old_apps() {
    local app name window f sys=()
    for app in $B1AIR_RETIRED_APPS; do
        name="b1air-$app"
        window="${app^}Window.qml"
        for f in "/usr/local/bin/$name" "/usr/share/applications/$name.desktop" \
                 "/usr/share/icons/hicolor/scalable/apps/$name.svg" \
                 "/usr/share/b1air-shell/qml/$window"; do
            [[ -e "$f" ]] && sys+=("$f")
        done
        rm -f "$HOME/.local/bin/$name" "$HOME/.local/share/applications/$name.desktop" \
              "$HOME/.local/share/icons/hicolor/scalable/apps/$name.svg" \
              "$HOME/.config/b1air-shell/$window"
    done
    if (( ${#sys[@]} > 0 )); then
        sudo rm -f "${sys[@]}" && echo "${#sys[@]}"
        update-desktop-database /usr/share/applications >/dev/null 2>&1 || true
    fi
}

