#!/usr/bin/env bash
# =============================================================================
# DotsFiles Installation & Setup Script (Sway / b1air desktop)
#
# Supported: Arch Linux, Debian 13+ / Ubuntu 25.04+, Fedora 40+, and
# (experimentally) openSUSE Tumbleweed — plus their derivatives. The package
# lists live in packages/, the distribution layer in lib/distro.sh.
# =============================================================================
set -euo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/distro.sh
source "$REPO_DIR/lib/distro.sh"

# The daemon's dotfiles_sync/status/sys look for the repo by guessing among a
# few hardcoded paths, so a clone anywhere else silently made those features
# "repo not found" forever. Record the real path once, here, where the
# installer already knows it — no more guessing needed downstream.
REPO_PATH_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/b1air/dotfiles-repo"
BACKUP_DIR="$HOME/.dotfiles-backup-$(date +%Y%m%d-%H%M%S)"

# Quickshell is built from source where no distribution packages it. Pinned to
# a release tag: Quickshell uses private Qt API, and an arbitrary master
# commit is not something to hand an installer.
QUICKSHELL_REPO="${QUICKSHELL_REPO:-https://github.com/quickshell-mirror/quickshell.git}"
QUICKSHELL_REF="${QUICKSHELL_REF:-v0.3.1}"
QT_MIN_VERSION="6.6"

DISTRO=""
SKIP_PACKAGES=0
SKIP_DOTFILES=0
SKIP_SERVICES=0
NO_AUR=0
DRY_RUN=0
RESTART=0

# Colors
RESET="\e[0m"
BOLD="\e[1m"
GREEN="\e[32m"
YELLOW="\e[33m"
CYAN="\e[36m"
RED="\e[31m"
MAGENTA="\e[35m"

# ponytail: all chatter goes to stderr so $(...) captures only real return values
log()  { printf "\n${CYAN}[INFO]${RESET} %s\n" "$*" >&2; }
ok()   { printf "${GREEN}[OK]${RESET}   %s\n" "$*" >&2; }
warn() { printf "\n${YELLOW}[WARN]${RESET} %s\n" "$*" >&2; }
err()  { printf "\n${RED}[ERR]${RESET}  %s\n" "$*" >&2; }

# ponytail: flat list of finished step names; deleted on a fully successful run
STATE_FILE="${XDG_STATE_HOME:-$HOME/.local/state}/dotfiles-install.state"

init_state() {
    if [[ "$RESTART" -eq 1 ]]; then
        rm -f "$STATE_FILE"
    elif [[ -s "$STATE_FILE" ]]; then
        log "Resuming: $(grep -c . "$STATE_FILE") step(s) already done. Use --restart to redo everything."
    fi
    mkdir -p "$(dirname "$STATE_FILE")"
}

# step <name> <command...> — runs the command unless it already succeeded before
step() {
    local name="$1"; shift
    if [[ -f "$STATE_FILE" ]] && grep -qxF "$name" "$STATE_FILE"; then
        ok "Skipping '${name}' (done in a previous run)."
        return 0
    fi
    [[ "$DRY_RUN" -eq 1 ]] && { log "Would run step: $name"; return 0; }
    "$@"
    printf '%s\n' "$name" >> "$STATE_FILE"
}

usage() {
    cat <<EOF
${BOLD}DotsFiles Automated Installer${RESET}

Usage: $0 [options]

Options:
  --distro <family> Force the distribution family: ${B1AIR_FAMILIES// /, }
                    (detected from /etc/os-release by default)
  --skip-packages   Skip package installation
  --skip-dotfiles   Skip deploying ~/.config, desktop entries, wallpapers, SDDM theme
  --skip-services   Skip enabling system services (NetworkManager, bluetooth, SDDM)
  --no-aur          Arch: skip AUR packages (plain sway instead of swayfx).
                    Other distributions: skip downloads from upstream releases
                    (Nerd Font, starship, eza). Quickshell is always installed.
  --dry-run         Simulate installation without making system changes
  --restart         Ignore saved progress and run every step from scratch
  -h, --help        Show this help message and exit
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --distro)        DISTRO="${2:-}"; shift 2 ;;
            --distro=*)      DISTRO="${1#--distro=}"; shift ;;
            --skip-packages) SKIP_PACKAGES=1; shift ;;
            --skip-dotfiles) SKIP_DOTFILES=1; shift ;;
            --skip-services) SKIP_SERVICES=1; shift ;;
            --no-aur|--no-extras) NO_AUR=1; shift ;;
            --dry-run)       DRY_RUN=1; shift ;;
            --restart)       RESTART=1; shift ;;
            -h|--help)       usage; exit 0 ;;
            *) err "Unknown option: $1"; usage; exit 1 ;;
        esac
    done

    [[ -n "$DISTRO" ]] || DISTRO="$(detect_distro)"
    if [[ -z "$DISTRO" ]]; then
        err "Unsupported system: $(distro_pretty_name)."
        err "Supported families: ${B1AIR_FAMILIES}. If yours is a derivative of one, pass --distro <family>."
        exit 1
    fi
    if [[ " $B1AIR_FAMILIES " != *" $DISTRO "* ]]; then
        err "Unknown --distro '$DISTRO'. Expected one of: ${B1AIR_FAMILIES}."
        exit 1
    fi
}

ensure_sudo() {
    if [[ "$DRY_RUN" -eq 1 ]]; then return 0; fi
    sudo -v
}

# ── Preflight ────────────────────────────────────────────────────────────────

# Quickshell and the suite need Qt 6.6 or newer. On Debian-family systems that
# rules out Debian 12 and Ubuntu 24.04 (Qt 6.4), and finding that out from the
# candidate version costs nothing — rather than after installing a few hundred
# packages and failing in the middle of a compile.
preflight_checks() {
    [[ "${B1AIR_SKIP_QT_CHECK:-0}" == "1" ]] && return 0
    [[ "$DISTRO" == "debian" ]] || return 0
    command -v apt-cache >/dev/null 2>&1 || return 0

    local candidate
    candidate="$(apt-cache policy qt6-base-dev 2>/dev/null \
        | awk '/Candidate:/ {print $2; exit}' | sed -E 's/^[0-9]+://; s/[^0-9.].*$//')"
    if [[ -z "$candidate" || "$candidate" == "(none)" ]]; then
        warn "Could not determine the Qt version in your repositories (run 'sudo apt-get update'?). Continuing."
        return 0
    fi
    if ! version_ge "$candidate" "$QT_MIN_VERSION"; then
        err "$(distro_pretty_name) ships Qt ${candidate}; the b1air desktop needs Qt ${QT_MIN_VERSION} or newer."
        err "Use Debian 13 (trixie) or newer, or Ubuntu 25.04 or newer. Set B1AIR_SKIP_QT_CHECK=1 to try anyway."
        exit 1
    fi
    ok "Qt ${candidate} available (>= ${QT_MIN_VERSION})."
}

# ── Packages ─────────────────────────────────────────────────────────────────

# Installs every listed package that is not there yet. Required packages go in
# one transaction and abort the install when it fails; optional ones are
# filtered to what the repositories actually carry, and a failing transaction
# is retried package by package so one conflict does not lose the rest.
install_package_set() {
    local list="$1" pkg
    local required=() optional=() missing_required=() to_optional=() unavailable=()

    mapfile -t required < <(read_package_list "$list" required)
    mapfile -t optional < <(read_package_list "$list" optional)

    for pkg in "${required[@]}"; do
        pkg_installed "$DISTRO" "$pkg" || missing_required+=("$pkg")
    done
    for pkg in "${optional[@]}"; do
        pkg_installed "$DISTRO" "$pkg" && continue
        if pkg_available "$DISTRO" "$pkg"; then
            to_optional+=("$pkg")
        else
            unavailable+=("$pkg")
        fi
    done

    if [[ ${#missing_required[@]} -gt 0 ]]; then
        log "Installing ${#missing_required[@]} package(s) from $(basename "$list")..."
        if [[ "$DRY_RUN" -eq 1 ]]; then
            log "Would install: ${missing_required[*]}"
        else
            # ponytail: a swallowed failure here means a "successful" install with nothing installed
            pm_install "$DISTRO" "${missing_required[@]}" || {
                err "Package installation failed — fix the error above and re-run (progress is saved)."
                exit 1; }
        fi
    fi

    if [[ ${#to_optional[@]} -gt 0 ]]; then
        log "Installing ${#to_optional[@]} optional package(s)..."
        if [[ "$DRY_RUN" -eq 1 ]]; then
            log "Would install (optional): ${to_optional[*]}"
        elif ! pm_install "$DISTRO" "${to_optional[@]}"; then
            warn "Optional packages failed as a group; retrying one at a time."
            for pkg in "${to_optional[@]}"; do
                pm_install "$DISTRO" "$pkg" || unavailable+=("$pkg")
            done
        fi
    fi

    [[ ${#unavailable[@]} -eq 0 ]] \
        || warn "Not available here, skipped (the desktop works without them): ${unavailable[*]}"
}

# install_one_of <pkg...> — the first candidate the repositories carry.
install_one_of() {
    local pkg
    for pkg in "$@"; do
        pkg_installed "$DISTRO" "$pkg" && return 0
    done
    for pkg in "$@"; do
        pkg_available "$DISTRO" "$pkg" || continue
        if [[ "$DRY_RUN" -eq 1 ]]; then log "Would install: $pkg"; return 0; fi
        pm_install "$DISTRO" "$pkg" && return 0
    done
    return 1
}

install_packages() {
    if [[ "$DRY_RUN" -eq 0 ]]; then
        log "Refreshing package databases..."
        pm_refresh "$DISTRO" || warn "Could not refresh the package databases; continuing with what is cached."
    fi
    install_package_set "$REPO_DIR/packages/${DISTRO}.txt"
}

enable_multilib_repo() {
    [[ "$DISTRO" == "arch" ]] || return 0
    # ponytail: 32-bit repo, needed later for steam/wine; it only exists on x86_64
    [[ "$(uname -m)" == "x86_64" ]] || { log "Skipping [multilib]: not available on $(uname -m)."; return 0; }

    local conf="/etc/pacman.conf"
    [[ -f "$conf" ]] || return 0
    grep -Eq '^[[:space:]]*\[multilib\]' "$conf" && return 0

    log "Enabling pacman [multilib] repository..."
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log "Would enable [multilib] in $conf"
        return 0
    fi

    sudo cp -n "$conf" "$conf.dotfiles-bak" 2>/dev/null || true
    if grep -Eq '^[[:space:]]*#[[:space:]]*\[multilib\]' "$conf"; then
        sudo sed -i '/^[[:space:]]*#[[:space:]]*\[multilib\]/,+1 s/^[[:space:]]*#[[:space:]]*//' "$conf"
    else
        printf '\n[multilib]\nInclude = /etc/pacman.d/mirrorlist\n' | sudo tee -a "$conf" >/dev/null
    fi
    # ponytail: no -Sy here; the packages step syncs databases anyway
}

# The compositor. swayFX where it can be had, plain sway otherwise — the
# session config is the same, minus the effects (see strip_swayfx_directives).
install_compositor() {
    case "$DISTRO" in
        arch)
            # swayfx comes from the AUR step; --no-aur means plain sway.
            [[ "$NO_AUR" -eq 1 ]] && install_one_of sway
            return 0 ;;
        debian)
            # Listed in packages/debian.txt: there is no swayfx package.
            return 0 ;;
    esac
    if pkg_installed "$DISTRO" sway && ! pkg_installed "$DISTRO" swayfx; then
        log "Plain sway is already installed; keeping it (install swayfx yourself for blur and rounded corners)."
        return 0
    fi
    if install_one_of swayfx; then
        ok "Compositor: swayfx"
    elif install_one_of sway; then
        warn "swayfx is not in your repositories — using plain sway (no blur or rounded corners)."
    else
        err "Neither swayfx nor sway could be installed."; exit 1
    fi
}

# ── Quickshell ───────────────────────────────────────────────────────────────

install_quickshell() {
    if command -v quickshell >/dev/null 2>&1 && [[ "${B1AIR_QUICKSHELL_FROM_SOURCE:-0}" != "1" ]]; then
        ok "Quickshell already installed: $(quickshell --version 2>/dev/null | head -n1)"
        return 0
    fi

    if [[ "${B1AIR_QUICKSHELL_FROM_SOURCE:-0}" != "1" ]]; then
        case "$DISTRO" in
            arch)
                install_one_of quickshell && return 0 ;;
            fedora)
                log "Enabling the errornointernet/quickshell COPR..."
                if [[ "$DRY_RUN" -eq 1 ]]; then
                    log "Would run: dnf copr enable errornointernet/quickshell; dnf install quickshell"
                    return 0
                fi
                if sudo dnf install -y 'dnf-command(copr)' \
                    && sudo dnf copr enable -y errornointernet/quickshell \
                    && sudo dnf install -y quickshell; then
                    return 0
                fi
                warn "COPR install failed; building Quickshell from source instead." ;;
            opensuse)
                install_one_of quickshell && return 0 ;;
        esac
    fi

    build_quickshell_from_source
}

build_quickshell_from_source() {
    log "Building Quickshell ${QUICKSHELL_REF} from source..."
    local deps="$REPO_DIR/packages/quickshell-build/${DISTRO}.txt"
    [[ -f "$deps" ]] && install_package_set "$deps"

    if [[ "$DRY_RUN" -eq 1 ]]; then
        log "Would clone $QUICKSHELL_REPO@$QUICKSHELL_REF, build it and install to /usr/local"
        return 0
    fi

    local qt_version
    qt_version="$(qt_query QT_VERSION || true)"
    if [[ -n "$qt_version" ]] && ! version_ge "$qt_version" "$QT_MIN_VERSION"; then
        err "Qt ${qt_version} is too old for Quickshell (needs ${QT_MIN_VERSION}+)."; exit 1
    fi

    local src="${XDG_CACHE_HOME:-$HOME/.cache}/b1air/quickshell-src"
    rm -rf "$src"
    mkdir -p "$(dirname "$src")"
    git clone --depth 1 --branch "$QUICKSHELL_REF" "$QUICKSHELL_REPO" "$src" >&2 || {
        err "Could not clone Quickshell from $QUICKSHELL_REPO."; exit 1; }

    # The crash handler needs cpptrace, which no distribution here packages.
    # The QML module goes where Qt looks for it, not under /usr/local.
    cmake -S "$src" -B "$src/build" -GNinja \
        -DCMAKE_BUILD_TYPE=RelWithDebInfo \
        -DCMAKE_INSTALL_PREFIX=/usr/local \
        -DINSTALL_QMLDIR="$(qt_qml_dir)" \
        -DCRASH_HANDLER=OFF \
        -DDISTRIBUTOR="b1air DotsFiles installer (source build)" >&2 || {
        err "Quickshell configure failed — a build dependency is missing (see above)."; exit 1; }
    cmake --build "$src/build" >&2 || { err "Quickshell build failed."; exit 1; }
    sudo cmake --install "$src/build" >&2 || { err "Quickshell install failed."; exit 1; }
    rm -rf "$src"
    hash -r
    command -v quickshell >/dev/null 2>&1 || { err "Quickshell installed but not on PATH."; exit 1; }
    ok "Quickshell ${QUICKSHELL_REF} installed to /usr/local"
}

# ── Extras the non-Arch repositories lack ────────────────────────────────────
#
# On Arch these come from the official repositories or the AUR. Elsewhere they
# come from the projects' own GitHub releases, into /usr/local — and only when
# nothing already provides them.

github_arch() {
    case "$(uname -m)" in
        x86_64|amd64) echo x86_64 ;;
        aarch64|arm64) echo aarch64 ;;
        *) return 1 ;;
    esac
}

# fetch_release_binary <name> <url> — a tarball holding the binary at its root.
fetch_release_binary() {
    local name="$1" url="$2" tmp
    command -v "$name" >/dev/null 2>&1 && return 0
    if [[ "$DRY_RUN" -eq 1 ]]; then log "Would download $name from $url"; return 0; fi
    tmp="$(mktemp -d)"
    if curl -fsSL "$url" -o "$tmp/archive.tar.gz" \
        && tar -xzf "$tmp/archive.tar.gz" -C "$tmp" \
        && [[ -f "$(find "$tmp" -type f -name "$name" | head -n1)" ]]; then
        sudo install -m 755 "$(find "$tmp" -type f -name "$name" | head -n1)" "/usr/local/bin/$name"
        ok "Installed $name to /usr/local/bin"
    else
        warn "Could not download $name; install it yourself for the full shell experience."
    fi
    rm -rf "$tmp"
}

install_nerd_font() {
    local fonts
    fonts="$(fc-list 2>/dev/null)"
    grep -qi "JetBrainsMono Nerd" <<< "$fonts" && return 0
    local dest="/usr/local/share/fonts/JetBrainsMonoNerd" tmp
    if [[ "$DRY_RUN" -eq 1 ]]; then log "Would install JetBrainsMono Nerd Font to $dest"; return 0; fi
    tmp="$(mktemp -d)"
    if curl -fsSL "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz" \
            -o "$tmp/font.tar.xz" \
        && tar -xJf "$tmp/font.tar.xz" -C "$tmp"; then
        sudo install -d -m 755 "$dest"
        sudo find "$tmp" -maxdepth 1 -name '*.ttf' -exec install -m 644 {} "$dest/" \;
        sudo fc-cache -f "$dest" >/dev/null 2>&1 || true
        ok "Installed JetBrainsMono Nerd Font"
    else
        warn "Could not download JetBrainsMono Nerd Font; icons in the terminal will be missing."
    fi
    rm -rf "$tmp"
}

install_extras() {
    [[ "$DISTRO" == "arch" ]] && return 0

    # Debian ships bat as `batcat` (a name clash with an older package); the
    # fish config and the post-install check both say `bat`.
    if ! command -v bat >/dev/null 2>&1 && command -v batcat >/dev/null 2>&1; then
        if [[ "$DRY_RUN" -eq 1 ]]; then log "Would link /usr/local/bin/bat -> batcat"
        else sudo ln -sf "$(command -v batcat)" /usr/local/bin/bat; fi
    fi

    if [[ "$NO_AUR" -eq 1 ]]; then
        warn "Skipping upstream downloads (--no-aur): Nerd Font, starship, eza."
        return 0
    fi

    install_nerd_font
    local arch
    if arch="$(github_arch)"; then
        fetch_release_binary starship \
            "https://github.com/starship/starship/releases/latest/download/starship-${arch}-unknown-linux-musl.tar.gz"
        fetch_release_binary eza \
            "https://github.com/eza-community/eza/releases/latest/download/eza_${arch}-unknown-linux-gnu.tar.gz"
    else
        warn "No prebuilt starship/eza for $(uname -m); skipping."
    fi
}

# ── GPU drivers ──────────────────────────────────────────────────────────────

# Display-controller vendors present on the PCI bus, read straight from sysfs:
# lspci would mean depending on pciutils, which is the same trap that left the
# software-rendering check silently disabled.
gpu_vendors() {
    local vendors=() dev class vendor
    for dev in /sys/bus/pci/devices/*; do
        [[ -r "$dev/class" && -r "$dev/vendor" ]] || continue
        class="$(< "$dev/class")"
        [[ "$class" == 0x03* ]] || continue     # 0x03xxxx = display controller
        vendor="$(< "$dev/vendor")"
        case "$vendor" in
            0x10de) vendors+=(nvidia) ;;
            0x1002) vendors+=(amd) ;;
            0x8086) vendors+=(intel) ;;
        esac
    done
    [[ ${#vendors[@]} -gt 0 ]] && printf '%s\n' "${vendors[@]}" | sort -u
    return 0
}

# The nvidia package is built against a specific kernel; the wrong variant
# leaves the module unbuilt and the session without a driver.
nvidia_package_for_kernel() {
    case "$(uname -r)" in
        *-lts)  echo "nvidia-lts" ;;
        *-arch*) echo "nvidia" ;;
        *)      echo "nvidia-dkms" ;;
    esac
}

# gpu_packages <vendor> — what to install for it on this family. Empty output
# means nothing safe to install automatically.
gpu_packages() {
    case "$DISTRO:$1" in
        arch:nvidia)     echo "$(nvidia_package_for_kernel) nvidia-utils" ;;
        arch:amd)        echo "vulkan-radeon libva-mesa-driver" ;;
        arch:intel)      echo "vulkan-intel intel-media-driver" ;;
        debian:amd)      echo "mesa-vulkan-drivers mesa-va-drivers" ;;
        debian:intel)    echo "mesa-vulkan-drivers intel-media-va-driver" ;;
        fedora:amd)      echo "mesa-vulkan-drivers mesa-va-drivers" ;;
        fedora:intel)    echo "mesa-vulkan-drivers intel-media-driver" ;;
        opensuse:amd)    echo "libvulkan_radeon" ;;
        opensuse:intel)  echo "libvulkan_intel intel-media-driver" ;;
    esac
}

install_gpu_drivers() {
    local virt
    virt="$(systemd-detect-virt 2>/dev/null || echo none)"
    if [[ "$virt" != "none" ]]; then
        log "Virtual machine ($virt) — skipping GPU drivers; mesa already covers it."
        return 0
    fi

    local vendors
    vendors="$(gpu_vendors)"
    if [[ -z "$vendors" ]]; then
        warn "No PCI display controller recognised; leaving graphics drivers alone."
        return 0
    fi

    local vendor pkgs pkg
    while read -r vendor; do
        [[ -n "$vendor" ]] || continue
        pkgs="$(gpu_packages "$vendor")"
        if [[ -z "$pkgs" ]]; then
            # NVIDIA outside Arch lives in non-free / RPM Fusion / Packman and
            # needs Secure Boot decisions an installer should not make.
            warn "${vendor^^} GPU detected — install its driver with your distribution's tool" \
                 "(Ubuntu: 'sudo ubuntu-drivers install'; Debian: nvidia-driver from non-free;" \
                 "Fedora: akmod-nvidia from RPM Fusion; openSUSE: the NVIDIA repository)."
            continue
        fi
        log "${vendor^^} GPU detected — installing: ${pkgs}"
        for pkg in $pkgs; do
            install_one_of "$pkg" || warn "Could not install $pkg (not in the enabled repositories?)."
        done
    done <<< "$vendors"
}

# ── AUR (Arch only) ──────────────────────────────────────────────────────────

ensure_aur_helper() {
    command -v yay  >/dev/null 2>&1 && { echo "yay";  return; }
    command -v paru >/dev/null 2>&1 && { echo "paru"; return; }

    if [[ "$DRY_RUN" -eq 1 ]]; then
        echo "yay"
        return
    fi

    local build_user="${SUDO_USER:-$USER}"
    if [[ "$build_user" == "root" ]]; then
        err "makepkg refuses to run as root. Run the installer as a normal user, or pass --no-aur."
        exit 1
    fi

    log "Installing yay (AUR helper)..."
    local tmpdir
    tmpdir="$(mktemp -d)"
    chown "$build_user" "$tmpdir"
    git clone https://aur.archlinux.org/yay.git "$tmpdir/yay" >&2
    chown -R "$build_user" "$tmpdir/yay"

    if [[ "$EUID" -eq 0 ]]; then
        sudo -u "$build_user" bash -c "cd '$tmpdir/yay' && makepkg -si --noconfirm" >&2
    else
        (cd "$tmpdir/yay" && makepkg -si --noconfirm) >&2
    fi
    rm -rf "$tmpdir"

    command -v yay >/dev/null 2>&1 || { warn "yay build failed."; exit 1; }
    echo "yay"
}

install_aur_packages() {
    local aur_helper="$1"
    local pkgs=()
    mapfile -t pkgs < <(read_package_list "$REPO_DIR/packages/arch-aur.txt" required)

    log "Installing AUR packages with ${aur_helper}..."
    for pkg in "${pkgs[@]}"; do
        pacman -Qi "$pkg" >/dev/null 2>&1 && continue
        if [[ "$DRY_RUN" -eq 1 ]]; then
            log "Would install AUR: $pkg"
        else
            # ponytail: no fallback to upstream sway — a different compositor is not a fix
            "$aur_helper" -S --needed --noconfirm "$pkg" || {
                err "Failed to install AUR package '$pkg'. Fix the error above and re-run."
                exit 1; }
        fi
    done
}

deploy_sddm_theme() {
    local sddm_src="$REPO_DIR/usr/share/sddm/themes/b1air"
    local sddm_dst="/usr/share/sddm/themes/b1air"
    local wallpaper_group="wallpaper"
    local installer_user="${SUDO_USER:-$USER}"
    local cache_dir="/var/cache/wallpaper"
    local cache_wall="$cache_dir/current.jpg"

    if [[ -d "$sddm_src" ]]; then
        log "Deploying b1air SDDM theme to $sddm_dst..."
        if [[ "$DRY_RUN" -eq 1 ]]; then
            log "Would install $sddm_src -> $sddm_dst"
        else
            sudo install -d -m 755 "$sddm_dst"
            sudo rsync -a --delete "$sddm_src/" "$sddm_dst/"
        fi
    fi

    if [[ -f "$REPO_DIR/etc/sddm.conf" ]]; then
        log "Installing /etc/sddm.conf..."
        if [[ "$DRY_RUN" -eq 1 ]]; then
            log "Would install $REPO_DIR/etc/sddm.conf -> /etc/sddm.conf"
        else
            sudo install -Dm644 "$REPO_DIR/etc/sddm.conf" "/etc/sddm.conf"
        fi
    fi

    # Shared wallpaper cache for SDDM background
    log "Configuring shared SDDM wallpaper cache in $cache_dir..."
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log "Would setup wallpaper group and permissions for $cache_dir"
    else
        sudo groupadd -f "$wallpaper_group"
        sudo install -d -o root -g "$wallpaper_group" -m 2775 "$cache_dir"
        id "$installer_user" >/dev/null 2>&1 && sudo usermod -aG "$wallpaper_group" "$installer_user" || true
        id sddm >/dev/null 2>&1 && sudo usermod -aG "$wallpaper_group" sddm || true

        local seed_wall=""
        if [[ -d "$REPO_DIR/.wallpapers" ]]; then
            seed_wall="$(find "$REPO_DIR/.wallpapers" -maxdepth 1 -type f \( -iname '*.jpg' -o -iname '*.png' \) | head -n 1 || true)"
        fi
        if [[ -n "$seed_wall" && -f "$seed_wall" ]]; then
            sudo install -o root -g "$wallpaper_group" -m 664 "$seed_wall" "$cache_wall"
        fi
    fi
}

deploy_session_files() {
    log "Deploying b1air FreeDesktop Wayland session files & portals..."
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log "Would install b1air.desktop, b1air-session, and b1air-portals.conf"
        return 0
    fi

    # 1. Wayland session entry for SDDM/GDM
    if [[ -f "$REPO_DIR/usr/share/wayland-sessions/b1air.desktop" ]]; then
        sudo install -d -m 755 /usr/share/wayland-sessions
        sudo install -m 644 "$REPO_DIR/usr/share/wayland-sessions/b1air.desktop" /usr/share/wayland-sessions/b1air.desktop
        ok "Installed /usr/share/wayland-sessions/b1air.desktop"
    fi

    # 2. b1air-session binary
    if [[ -f "$REPO_DIR/usr/bin/b1air-session" ]]; then
        sudo install -d -m 755 /usr/bin
        sudo install -m 755 "$REPO_DIR/usr/bin/b1air-session" /usr/bin/b1air-session
        ok "Installed /usr/bin/b1air-session"
    fi

    # 3. XDG Desktop Portals config
    if [[ -f "$REPO_DIR/usr/share/xdg-desktop-portal/b1air-portals.conf" ]]; then
        sudo install -d -m 755 /usr/share/xdg-desktop-portal
        sudo install -m 644 "$REPO_DIR/usr/share/xdg-desktop-portal/b1air-portals.conf" /usr/share/xdg-desktop-portal/b1air-portals.conf
        ok "Installed /usr/share/xdg-desktop-portal/b1air-portals.conf"
    fi

    # 4. udev rules (e.g. bluetoothd doesn't reliably notice its adapter
    # coming back after an rfkill unblock without a nudge)
    if [[ -d "$REPO_DIR/etc/udev/rules.d" ]]; then
        sudo install -d -m 755 /etc/udev/rules.d
        for rule in "$REPO_DIR"/etc/udev/rules.d/*.rules; do
            [[ -f "$rule" ]] || continue
            sudo install -m 644 "$rule" "/etc/udev/rules.d/$(basename "$rule")"
            ok "Installed /etc/udev/rules.d/$(basename "$rule")"
        done
        sudo udevadm control --reload-rules 2>/dev/null || true
    fi
}

deploy_dotfiles() {
    log "Deploying user dotfiles..."
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log "Would deploy .config, the cursor theme and .wallpapers to $HOME"
        deploy_sddm_theme
        deploy_session_files
        return 0
    fi

    mkdir -p "$BACKUP_DIR" "$HOME/.config"

    # Merge .config, keeping what is the user's.
    #
    # This was `rsync -a --delete "$REPO_DIR/.config/" "$HOME/.config/"`, and
    # --delete means "remove everything in the destination that is not in the
    # source". The destination is the whole of ~/.config, so a plain install
    # deleted every configuration directory belonging to any program this repo
    # does not ship — browsers, editors, whatever the user had — along with
    # ~/.config/b1air and ~/.config/b1air-term, which are this suite's own
    # theme and terminal state. The `mv` loop above it moved only the handful
    # of top-level names that collide into the backup; everything else was
    # simply gone.
    #
    # Three changes: the backup is a copy rather than a move, the sync no
    # longer deletes, and the two files the desktop writes at runtime are
    # excluded so an update does not reset them. settings.json holds every
    # choice made in Settings, and conf.d/custom_*.conf is generated from it
    # by the Mouse & Touchpad, Window & Gaps and Appearance pages and by the
    # keybinding editor.
    if [[ -d "$REPO_DIR/.config" ]]; then
        for item in "$REPO_DIR"/.config/*; do
            [[ -e "$item" ]] || continue
            local base
            base="$(basename "$item")"
            if [[ -e "$HOME/.config/$base" || -L "$HOME/.config/$base" ]]; then
                cp -a "$HOME/.config/$base" "$BACKUP_DIR/$base"
            fi
        done

        rsync -a \
            --exclude 'sway/settings.json' \
            --exclude 'sway/conf.d/custom_*.conf' \
            "$REPO_DIR/.config/" "$HOME/.config/"

        # A first install has nothing to keep, so it gets the shipped defaults.
        if [[ ! -f "$HOME/.config/sway/settings.json" ]]; then
            cp "$REPO_DIR/.config/sway/settings.json" "$HOME/.config/sway/settings.json"
        fi

        # Plain sway rejects every blur/shadow/corner line with a swaynag bar.
        if ! have_swayfx; then
            strip_swayfx_directives "$HOME/.config/sway/conf.d"
            ok "Plain sway: swayFX-only effects commented out in ~/.config/sway/conf.d"
        fi
    fi

    # Where Settings → Appearance → Theme keeps user themes. Created here so
    # the first Export has somewhere to land.
    mkdir -p "$HOME/.config/b1air/themes"

    # The suite's desktop entries and icons live with each app under
    # src/apps/<app>/ and are installed by `make install` (build_b1air_suite),
    # beside the binaries they launch.

    # The desktop's own cursor theme (src/cursors), named by input.conf and the
    # GTK settings. cp -a keeps its alias names as symlinks.
    if [[ -d "$REPO_DIR/.local/share/icons/b1air-cursors" ]]; then
        rm -rf "$HOME/.local/share/icons/b1air-cursors"
        cp -a "$REPO_DIR/.local/share/icons/b1air-cursors" "$HOME/.local/share/icons/"
    fi

    # Sync wallpapers. Added, not replaced: --delete here threw away every
    # wallpaper the user had put in the folder themselves, and the folder is
    # exactly the place they are invited to put them.
    if [[ -d "$REPO_DIR/.wallpapers" ]]; then
        rsync -a "$REPO_DIR/.wallpapers/" "$HOME/.wallpapers/"
    fi

    # deploy_sddm_theme was only ever called from the DRY_RUN branch above —
    # a real install never called it at all, so /usr/share/sddm/themes/b1air
    # and /etc/sddm.conf were never deployed on any machine that actually ran
    # this script for real. The dry-run preview lied about what would happen.
    deploy_sddm_theme

    # Deploy Wayland session files & portals
    deploy_session_files

    # Refresh user font cache
    fc-cache -f >/dev/null 2>&1 || true

    ok "Dotfiles deployed. Previous configs backed up in: $BACKUP_DIR"
}

configure_default_shell() {
    local fish
    fish="$(command -v fish 2>/dev/null || true)"
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log "Would set the login shell to ${fish:-fish}"
        return 0
    fi
    if [[ -z "$fish" ]]; then
        warn "Fish is not installed; keeping the current login shell."
        return 0
    fi
    if ! grep -Fxq "$fish" /etc/shells 2>/dev/null; then
        warn "$fish is not listed in /etc/shells; keeping the current login shell."
        return 0
    fi
    local current_shell
    current_shell="$(getent passwd "$USER" | cut -d: -f7)"
    if [[ "$current_shell" != "$fish" ]]; then
        chsh -s "$fish" "$USER" || sudo usermod -s "$fish" "$USER" || warn "Could not set Fish as the login shell."
    fi
}

# enable_first_unit <unit...> — unit names differ between distributions
# (vboxservice vs virtualbox-guest-utils, vmtoolsd vs open-vm-tools).
enable_first_unit() {
    local unit
    for unit in "$@"; do
        sudo systemctl enable --now "$unit" 2>/dev/null && return 0
    done
    return 0
}

detect_and_install_vm_guest_tools() {
    command -v systemd-detect-virt >/dev/null 2>&1 || return 0
    local virt
    virt="$(systemd-detect-virt 2>/dev/null || true)"
    [[ -n "$virt" && "$virt" != "none" ]] || return 0

    log "Detected Virtual Machine environment: $virt"
    case "$virt" in
        kvm|qemu|bochs)
            install_one_of qemu-guest-agent || warn "qemu-guest-agent not available."
            install_one_of spice-vdagent || warn "spice-vdagent not available."
            if [[ "$DRY_RUN" -eq 0 ]]; then
                enable_first_unit qemu-guest-agent
                # spice-vdagentd is the system side of clipboard/resolution
                # sync; without it, spice-vdagent in the session has nothing
                # to talk to and host<->guest copy-paste silently never works.
                enable_first_unit spice-vdagentd
            fi
            ;;
        oracle)
            install_one_of virtualbox-guest-utils virtualbox-guest-additions virtualbox-guest-tools \
                || warn "VirtualBox guest tools not available (Debian: enable contrib)."
            [[ "$DRY_RUN" -eq 0 ]] && enable_first_unit vboxservice virtualbox-guest-utils
            ;;
        vmware)
            install_one_of open-vm-tools || warn "open-vm-tools not available."
            [[ "$DRY_RUN" -eq 0 ]] && enable_first_unit vmtoolsd open-vm-tools
            ;;
    esac
    # The software rasterizer the session falls back to in a VM.
    install_one_of mesa libgl1-mesa-dri mesa-dri-drivers Mesa-dri || true
}

# Another display manager (GDM on Ubuntu and Fedora Workstation, LightDM on
# Mint) owns display-manager.service, and `systemctl enable sddm` refuses to
# replace that alias. Take it over explicitly, and say so.
enable_sddm() {
    local current
    current="$(readlink -f /etc/systemd/system/display-manager.service 2>/dev/null || true)"
    if [[ -n "$current" && "$(basename "$current")" != "sddm.service" ]]; then
        warn "Switching the display manager from $(basename "$current" .service) to SDDM."
        sudo systemctl disable "$(basename "$current")" 2>/dev/null || true
        sudo systemctl enable --force sddm || return 1
    else
        sudo systemctl enable sddm || return 1
    fi
    # Debian's own record of the default display manager, read by its
    # maintainer scripts; left stale it would hand the alias back on upgrade.
    if [[ -f /etc/X11/default-display-manager ]]; then
        command -v sddm | sudo tee /etc/X11/default-display-manager >/dev/null
    fi
}

enable_services() {
    log "Enabling system services..."
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log "Would enable: NetworkManager, bluetooth, power-profiles-daemon, cups, sddm"
        return 0
    fi

    sudo systemctl enable NetworkManager || warn "Failed to enable NetworkManager"
    sudo systemctl enable bluetooth || warn "Failed to enable Bluetooth"
    # Installed above, but inert until enabled: the shell's power-profile
    # switch talks to this daemon, and printing needs the cups socket.
    # (Fedora 41+ provides the same service through tuned-ppd.)
    sudo systemctl enable power-profiles-daemon 2>/dev/null \
        || sudo systemctl enable tuned 2>/dev/null \
        || warn "Failed to enable a power-profiles service"
    sudo systemctl enable cups.socket || warn "Failed to enable CUPS"
    # ponytail: SDDM last and strict — enabling it early boots the user into a broken session
    enable_sddm || { err "Failed to enable SDDM."; exit 1; }
}

build_b1air_suite() {
    log "Building and installing b1air-daemon & b1air-shell (Native C++20 Desktop Suite)..."
    if [[ -d "$REPO_DIR/src" ]]; then
        if command -v ccache >/dev/null 2>&1; then
            ccache -M 10G >/dev/null 2>&1 || true
        fi

        # 1. Daemon
        #
        # No `make clean` first. It threw away every object and the whole CMake
        # build directory on every run, so an install that changed one file
        # recompiled the entire suite — including a fresh CMake configure and a
        # full AUTOMOC pass. CMake tracks header dependencies, so an
        # incremental build in src/build is the right default;
        # B1AIR_CLEAN_BUILD=1 forces the old behaviour.
        if [[ "${B1AIR_CLEAN_BUILD:-0}" == "1" ]]; then
            make -C "$REPO_DIR/src" clean >/dev/null 2>&1 || true
        fi
        make -C "$REPO_DIR/src" -j"$(nproc 2>/dev/null || echo 4)" || {
            err "Failed to build the b1air suite — see the compiler output above."; exit 1; }

        # Installed for every user, not just this one.
        #
        # b1air-daemon and b1air-shell already went to /usr/local/bin while the
        # nine applications stayed in one user's ~/.local/bin — so a second
        # account on the same machine got a desktop whose apps were all
        # missing, and the desktop entries pointed into a home directory it
        # could not read. Everything goes to the same place now.
        #
        # Built above as this user and installed here as root: `sudo make`
        # would leave the object files and the CMake tree owned by root, and
        # the next ordinary build would fail on its own artefacts.
        #
        # environment.d stays in the user's home either way — it is a per-user
        # PATH file, and /usr/local/bin needs no help being on PATH.
        B1AIR_PREFIX="/usr/local/bin"
        if sudo make -C "$REPO_DIR/src" install \
                PREFIX=/usr/local/bin \
                DATADIR=/usr/share \
                QMLDIR=/usr/share/b1air-shell/qml \
                COMPATDIR=/usr/share/b1air-shell/qs-compat \
                CONFDIR="$HOME/.config" >/dev/null; then
            sudo chown -R "$USER" "$HOME/.config/environment.d" 2>/dev/null || true
            ok "b1air suite installed system-wide to /usr/local/bin"
        else
            warn "No root for a system-wide install; falling back to ~/.local."
            B1AIR_PREFIX="${HOME}/.local/bin"
            make -C "$REPO_DIR/src" PREFIX="${HOME}/.local/bin" install || {
                err "Failed to install the b1air suite."; exit 1; }
            ok "b1air suite installed to ~/.local/bin"
        fi

        # The one line every keybind, autostart entry and unit resolves the
        # binaries through, written to match where they actually landed, so a
        # fallback install does not leave 39 keybinds pointing at /usr/local.
        render_config_tree "$HOME/.config" "$B1AIR_PREFIX"
        ok "sway and the user units resolve the suite through ${B1AIR_PREFIX}"

        # Entries an older install left in ~/.local/share/applications, which
        # shadow the ones just installed and may name a binary that is gone.
        local pruned
        pruned="$(prune_stale_desktop_entries "$BACKUP_DIR")"
        if (( pruned > 0 )); then ok "Removed $pruned stale per-user desktop entries"; fi

        # 2. Native b1air-shell
        if [[ -d "$REPO_DIR/src/shell" ]]; then
            # The QML plugin has to sit on Qt's import path for quickshell to
            # find it. A system `make install` above put it there already; a
            # per-user one could not, so it is done here with sudo.
            local qml_dest
            qml_dest="$(qt_qml_dir)"
            if [[ -d "$REPO_DIR/src/build/qml/B1air" && "$B1AIR_PREFIX" != /usr/local/bin ]]; then
                sudo cp -r "$REPO_DIR/src/build/qml/B1air" "$qml_dest/" \
                    && ok "B1air.Daemon QML module installed to $qml_dest" \
                    || { err "Failed to install the B1air.Daemon QML module."; exit 1; }
            fi

            # The QML (shell, app windows, icons) and the compat tree went to
            # /usr/share/b1air-shell with `make install` above. It was copied a
            # second time here with rsync --delete, which now would delete the
            # icons that install put beside it.

            # b1air-shell is installed by `make install` above, along with
            # every other binary — it used to be copied separately here, which
            # is how it could end up in /usr/local/bin while the apps beside it
            # were in a home directory.
        fi
    fi
}

configure_remote_desktop_permissions() {
    log "Configuring uinput & screencast permissions for prompt-free remote desktop..."
    echo 'KERNEL=="uinput", GROUP="input", MODE="0660", OPTIONS+="static_node=uinput"' | sudo tee /etc/udev/rules.d/99-uinput.rules >/dev/null 2>&1 || true
    sudo udevadm control --reload-rules >/dev/null 2>&1 || true
    sudo udevadm trigger --name-match=uinput >/dev/null 2>&1 || true
    sudo usermod -aG input "$USER" >/dev/null 2>&1 || true

    # Battery charge control without a password prompt. The sysfs files are
    # root-owned 0644, so without this the charge limit on the Power page
    # raises a polkit dialog for every change — 99-b1air-power.rules hands
    # them to the `power` group, which exists on Arch already.
    sudo groupadd -f power >/dev/null 2>&1 || true
    sudo usermod -aG power "$USER" >/dev/null 2>&1 || true
    sudo udevadm trigger --subsystem-match=power_supply >/dev/null 2>&1 || true
}

post_install_checks() {
    [[ "$DRY_RUN" -eq 1 ]] && { log "Would verify the installed commands."; return 0; }
    log "Running environment verification..."
    # ponytail: every app must be present — this gate is what keeps SDDM off a broken system
    local commands=(sway swaylock sddm quickshell
        b1air-daemon b1air-polkit-agent b1air-secret-service b1air-shell
        b1air-files b1air-settings b1air-monitor b1air-term b1air-text
        b1air-view b1air-notes b1air-git b1air-camera)
    # The terminal niceties the fish config uses when present. Missing ones
    # cost a prettier prompt, not a working desktop.
    local recommended=(fish starship eza bat fzf)
    local missing=() missing_recommended=() cmd

    for cmd in "${commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1 && ! [[ -x "$HOME/.local/bin/$cmd" ]]; then
            missing+=("$cmd")
        fi
    done
    for cmd in "${recommended[@]}"; do
        command -v "$cmd" >/dev/null 2>&1 || missing_recommended+=("$cmd")
    done

    # An existing binary proves little if its QML module is absent — but where
    # the module lands differs between packagings, so this one only warns.
    local qml_dir
    qml_dir="$(qt_qml_dir)"
    [[ -d "$qml_dir/Quickshell" ]] || warn "No Quickshell QML module under $qml_dir; if the shell fails to start, reinstall Quickshell."
    [[ ${#missing_recommended[@]} -eq 0 ]] || warn "Recommended but missing: ${missing_recommended[*]}"

    if [[ ${#missing[@]} -eq 0 ]]; then
        ok "All essential commands verified."
    else
        err "Missing commands: ${missing[*]}"
        exit 1
    fi
}

aur_step() {
    local aur_helper
    aur_helper="$(ensure_aur_helper)"
    install_aur_packages "$aur_helper"
}

# xdg-user-dirs is in the package list, but the package alone does nothing:
# it ships its own XDG-autostart entry that would run xdg-user-dirs-update on
# first login, and sway (unlike GNOME/KDE/XFCE) never runs XDG autostart
# entries at all — nothing in this repo's autostart.conf does either. Every
# other DE creates ~/Downloads, ~/Documents etc. on first login; here that
# needs a direct, one-time call instead of a login hook that can never fire.
create_user_dirs() {
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log "Would run xdg-user-dirs-update to create ~/Downloads, ~/Documents, etc."
        return 0
    fi
    command -v xdg-user-dirs-update >/dev/null 2>&1 || return 0
    xdg-user-dirs-update
}

record_repo_path() {
    [[ -d "$REPO_DIR/.git" ]] || return 0
    if [[ "$DRY_RUN" -eq 1 ]]; then
        log "Would record dotfiles repo path: $REPO_DIR"
        return 0
    fi
    mkdir -p "$(dirname "$REPO_PATH_FILE")"
    printf '%s\n' "$REPO_DIR" > "$REPO_PATH_FILE"
}

main() {
    parse_args "$@"
    log "Operating as distro family: ${DISTRO} ($(distro_pretty_name))"
    ensure_sudo
    init_state
    record_repo_path

    if [[ "$SKIP_PACKAGES" -eq 0 ]]; then
        preflight_checks
        step multilib   enable_multilib_repo
        step packages   install_packages
        step compositor install_compositor
        step quickshell install_quickshell
        step gpu        install_gpu_drivers
        if [[ "$DISTRO" == "arch" ]]; then
            if [[ "$NO_AUR" -eq 0 ]]; then
                step aur    aur_step
            else
                warn "Skipping AUR packages (--no-aur)."
            fi
        else
            step extras install_extras
        fi
        step vm-tools   detect_and_install_vm_guest_tools
    else
        warn "Skipping packages installation (--skip-packages)."
    fi

    if [[ "$SKIP_DOTFILES" -eq 0 ]]; then
        # After deploy_dotfiles, not before: its rsync --delete on ~/.config
        # would otherwise wipe user-dirs.dirs right back out, since it is not
        # part of this repo's tracked .config tree.
        step dotfiles   deploy_dotfiles
        step user-dirs  create_user_dirs
        step suite      build_b1air_suite
        step remote-perms configure_remote_desktop_permissions
    else
        warn "Skipping dotfiles deployment."
    fi
    step default-shell  configure_default_shell

    # The login screen reads the desktop palette from /var/cache/wallpaper
    # (see usr/share/sddm/themes/b1air/components/Palette.qml). Nothing has
    # written it yet on a fresh machine, so the very first login would show the
    # theme's built-in fallback colours rather than the ones just installed.
    if command -v b1air-daemon >/dev/null 2>&1 || [[ -x "$HOME/.local/bin/b1air-daemon" ]]; then
        "$(command -v b1air-daemon || echo "$HOME/.local/bin/b1air-daemon")" appearance >/dev/null 2>&1 \
            && ok "Login screen palette published to /var/cache/wallpaper" \
            || warn "Could not publish the login screen palette; it will follow the first theme change."
    fi

    # ponytail: verify BEFORE enabling the display manager — a graphical login on a
    # half-installed system locks the user out of the desktop they cannot yet run
    post_install_checks

    if [[ "$SKIP_SERVICES" -eq 0 ]]; then
        step services   enable_services
    else
        warn "Skipping services configuration."
    fi

    rm -f "$STATE_FILE"

    printf "\n${GREEN}${BOLD}✓ Installation finished successfully!${RESET}\n"
    echo "Log in to Sway session to enjoy your environment."
}

main "$@"
