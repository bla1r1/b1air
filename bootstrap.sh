#!/usr/bin/env bash
# =============================================================================
# bootstrap.sh — One-line Bootstrap for DotsFiles Setup
# (Arch, Debian/Ubuntu, Fedora, openSUSE)
# =============================================================================
set -euo pipefail

DEFAULT_REPO_URL="https://github.com/bla1r1/DotsFiles.git"
REPO_URL="${DOTFILES_REPO_URL:-${1:-$DEFAULT_REPO_URL}}"
PINNED_COMMIT="${DOTFILES_COMMIT:-}"

if [[ "$REPO_URL" != "$DEFAULT_REPO_URL" && "${DOTFILES_ALLOW_CUSTOM_REPO:-0}" != "1" ]]; then
    echo "[ERROR] Refusing an untrusted repository URL. Set DOTFILES_ALLOW_CUSTOM_REPO=1 explicitly for development."
    exit 1
fi

if [[ -n "${1:-}" && "$1" =~ ^https?://|^git@ ]]; then
    shift || true
fi

BRANCH="${DOTFILES_BRANCH:-main}"
TARGET_DIR="${DOTFILES_TARGET_DIR:-$HOME/.local/src/dotfiles}"
INSTALLER="ui"

EXTRA_ARGS=()
for arg in "$@"; do
    case "$arg" in
        --ui)  INSTALLER="ui"  ;;
        --cli) INSTALLER="cli" ;;
        *)     EXTRA_ARGS+=("$arg") ;;
    esac
done

if [[ ! "$BRANCH" =~ ^[A-Za-z0-9_][A-Za-z0-9._/-]*$ ]]; then
    echo "[ERROR] Invalid branch name."
    exit 1
fi

# The installer's lib/distro.sh is not on disk yet, so this is the same
# detection in miniature: just enough to get git and rsync installed.
detect_family() {
    local word
    for word in $(. /etc/os-release 2>/dev/null && echo "${ID:-} ${ID_LIKE:-}"); do
        case "$word" in
            arch|archarm|endeavouros|manjaro|cachyos|garuda)    echo arch;     return ;;
            debian|ubuntu|linuxmint|pop|elementary|zorin|neon)   echo debian;   return ;;
            fedora|nobara|ultramarine)                           echo fedora;   return ;;
            opensuse|opensuse-tumbleweed|opensuse-slowroll|suse) echo opensuse; return ;;
        esac
    done
    [[ -f /etc/arch-release ]] && echo arch
    return 0
}

FAMILY="$(detect_family)"
echo "[INFO] Installing base bootstrap dependencies (git, rsync)..."
case "$FAMILY" in
    arch)     sudo pacman -S --needed --noconfirm git rsync ;;
    debian)   sudo apt-get update && sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y git rsync ca-certificates ;;
    fedora)   sudo dnf install -y git rsync ;;
    opensuse) sudo zypper -n install git rsync ;;
    *)
        echo "[ERROR] Unsupported distribution. DotsFiles supports Arch, Debian/Ubuntu, Fedora and openSUSE (and derivatives)."
        exit 1 ;;
esac

if [[ -d "$TARGET_DIR/.git" ]]; then
    echo "[INFO] Updating existing repository in $TARGET_DIR..."
    git -C "$TARGET_DIR" fetch --all --prune
    git -C "$TARGET_DIR" checkout "$BRANCH"
    git -C "$TARGET_DIR" pull --ff-only
else
    echo "[INFO] Cloning DotsFiles repository into $TARGET_DIR..."
    mkdir -p "$(dirname "$TARGET_DIR")"
    git clone --branch "$BRANCH" "$REPO_URL" "$TARGET_DIR"
fi

if [[ -n "$PINNED_COMMIT" ]]; then
    if [[ ! "$PINNED_COMMIT" =~ ^[0-9a-fA-F]{40}$ ]]; then
        echo "[ERROR] DOTFILES_COMMIT must be a full 40-character commit hash."
        exit 1
    fi
    git -C "$TARGET_DIR" cat-file -e "$PINNED_COMMIT^{commit}" || {
        echo "[ERROR] Requested pinned commit is not available locally."
        exit 1
    }
    git -C "$TARGET_DIR" checkout --detach --quiet "$PINNED_COMMIT"
else
    echo "[ERROR] Refusing to execute an unpinned repository. Set DOTFILES_COMMIT to a verified 40-character commit hash."
    exit 1
fi

if [[ "$INSTALLER" == "ui" ]]; then
    SCRIPT="$TARGET_DIR/install-ui.sh"
    chmod +x "$SCRIPT"
    "$SCRIPT"
else
    SCRIPT="$TARGET_DIR/install.sh"
    chmod +x "$SCRIPT"
    "$SCRIPT" "${EXTRA_ARGS[@]}"
fi
