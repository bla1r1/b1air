#!/usr/bin/env bash
# =============================================================================
# install-ui.sh — Interactive TUI Installer for DotsFiles
# =============================================================================
set -euo pipefail

REPO_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_SCRIPT="$REPO_DIR/install.sh"
# shellcheck source=lib/distro.sh
source "$REPO_DIR/lib/distro.sh"
LOG="$HOME/.dotfiles-install-$(date +%Y%m%d-%H%M%S).log"

# Colors
RESET="\e[0m"
BOLD="\e[1m"
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
CYAN="\e[36m"
MAGENTA="\e[35m"

log()  { echo -e "${CYAN}[INFO]${RESET} $*" | tee -a "$LOG"; }
warn() { echo -e "${YELLOW}[WARN]${RESET} $*" | tee -a "$LOG"; }
ok()   { echo -e "${GREEN}[OK]${RESET}   $*" | tee -a "$LOG"; }
err()  { echo -e "${RED}[ERROR]${RESET}  $*" | tee -a "$LOG"; }

if [[ ! -f "$INSTALL_SCRIPT" ]]; then
    err "install.sh not found at: $INSTALL_SCRIPT"
    exit 1
fi

if [[ "$EUID" -eq 0 ]]; then
    echo -e "${RED}Please do NOT run this script as root or with sudo.${RESET}"
    exit 1
fi

mkdir -p "$(dirname "$LOG")"
echo "Install log: $LOG" | tee "$LOG"

DISTRO="$(detect_distro)"
if [[ -z "$DISTRO" ]]; then
    err "Unsupported system: $(distro_pretty_name). Supported families: ${B1AIR_FAMILIES}."
    err "For a derivative of one of them, run ./install.sh --distro <family> instead."
    exit 1
fi

if ! command -v whiptail >/dev/null 2>&1; then
    log "Installing whiptail dialog library..."
    [[ "$DISTRO" == "debian" ]] && sudo apt-get update -qq
    pm_install "$DISTRO" "$(whiptail_package "$DISTRO")"
fi

if [[ "$DISTRO" == "arch" ]]; then
    PACKAGES_LABEL="Install official Arch packages (Sway, Shell, GUI, Fonts, SDDM)"
    EXTRAS_LABEL="Install AUR packages (swayfx blur, wl-screenrec, cursors)"
    EXTRAS_SHORT="AUR Packages (swayfx, themes)"
else
    PACKAGES_LABEL="Install distribution packages (Sway, Qt 6, Quickshell, Fonts, SDDM)"
    EXTRAS_LABEL="Download extras from upstream (Nerd Font, starship, eza)"
    EXTRAS_SHORT="Upstream extras (Nerd Font, starship, eza)"
fi

# ── Welcome banner ────────────────────────────────────────────────────────────
whiptail --title "DotsFiles Setup" --msgbox \
"Welcome to the DotsFiles Interactive Installer!

System detected : $(distro_pretty_name) [${DISTRO}]
Log destination : $LOG

Controls:
• SPACEBAR : Select / Toggle option
• TAB / ARROWS : Navigate buttons
• ENTER : Confirm selection

Press OK to continue." \
    18 68

# ── Input group ───────────────────────────────────────────────────────────────
if ! groups "$USER" | grep -q '\binput\b'; then
    whiptail --title "Input Group" --msgbox \
"Your user is not in the 'input' group.

Adding your user to this group enables Wayland touchpad gestures
and backlight keys to work smoothly without root prompts.

The installer will add you automatically." \
        14 65
fi

# ── Main selection loop ───────────────────────────────────────────────────────
SKIP_PACKAGES=0
SKIP_DOTFILES=0
SKIP_SERVICES=0
NO_AUR=0

while true; do
    CHECKLIST_ARGS=(
        "packages"  "$PACKAGES_LABEL" ON
        "aur"       "$EXTRAS_LABEL"   ON
        "dotfiles"  "Deploy ~/.config, wallpapers, and b1air SDDM theme"             ON
        "services"  "Enable core system services (NetworkManager, Bluetooth, SDDM)"   ON
    )

    CHOICES=$(whiptail --title "Select Installation Components" \
        --checklist \
        "Choose what to install:\n\n[SPACE] Toggle  |  [TAB] Switch buttons" \
        18 80 4 \
        "${CHECKLIST_ARGS[@]}" \
        3>&1 1>&2 2>&3) || {
            echo -e "\n${YELLOW}Installation cancelled by user.${RESET}" | tee -a "$LOG"
            exit 0
        }

    if [[ -z "$CHOICES" ]]; then
        whiptail --title "Warning" --msgbox \
            "No components were selected.\nPlease choose at least one item." \
            8 50
        continue
    fi

    SKIP_PACKAGES=1; SKIP_DOTFILES=1; SKIP_SERVICES=1; NO_AUR=1
    [[ "$CHOICES" == *"packages"* ]] && SKIP_PACKAGES=0
    [[ "$CHOICES" == *"aur"*      ]] && NO_AUR=0
    [[ "$CHOICES" == *"dotfiles"* ]] && SKIP_DOTFILES=0
    [[ "$CHOICES" == *"services"* ]] && SKIP_SERVICES=0

    # Build confirmation message
    confirm_msg="Your selected components:\n\n"
    [[ "$SKIP_PACKAGES" -eq 0 ]] && confirm_msg+="  ✔ Distribution Packages & Fonts\n" || confirm_msg+="  ✘ Skip Distribution Packages\n"
    [[ "$NO_AUR"        -eq 0 ]] && confirm_msg+="  ✔ ${EXTRAS_SHORT}\n"  || confirm_msg+="  ✘ Skip ${EXTRAS_SHORT}\n"
    [[ "$SKIP_DOTFILES" -eq 0 ]] && confirm_msg+="  ✔ Dotfiles & Tokyo Night SDDM Theme\n" || confirm_msg+="  ✘ Skip Dotfiles\n"
    [[ "$SKIP_SERVICES" -eq 0 ]] && confirm_msg+="  ✔ Core Services (NM, Bluetooth, SDDM)\n" || confirm_msg+="  ✘ Skip Services\n"
    confirm_msg+="\nReady to start installation?"

    if ! whiptail --title "Confirm Selection" --yesno "$(printf "%s" "$confirm_msg")" 16 65; then
        continue
    fi

    break
done

# ── Add user to input group ───────────────────────────────────────────────────
if ! groups "$USER" | grep -q '\binput\b'; then
    log "Adding $USER to input group..."
    sudo usermod -aG input "$USER" 2>/dev/null || warn "Failed to add to input group"
fi

# ── Build args and launch install.sh ──────────────────────────────────────────
ARGS=(--distro "$DISTRO")
[[ "$SKIP_PACKAGES" -eq 1 ]] && ARGS+=(--skip-packages)
[[ "$NO_AUR"        -eq 1 ]] && ARGS+=(--no-aur)
[[ "$SKIP_DOTFILES" -eq 1 ]] && ARGS+=(--skip-dotfiles)
[[ "$SKIP_SERVICES" -eq 1 ]] && ARGS+=(--skip-services)

log "Running installer with: ${ARGS[*]:-default options}"
bash "$INSTALL_SCRIPT" "${ARGS[@]}" 2>&1 | tee -a "$LOG"
exit_code="${PIPESTATUS[0]}"

if [[ "$exit_code" -eq 0 ]]; then
    whiptail --title "Installation Complete" --msgbox \
"🎉 Installation completed successfully!

Log file saved to:
  $LOG

Next steps:
• Reboot or log in to SDDM / Sway session.
• Press Mod+H anytime to open the interactive Desktop Guide.
• Customize your settings in Control Center (Top Right) -> Settings.

Enjoy your new desktop environment!" \
        18 68
else
    whiptail --title "Installation Warnings" --msgbox \
"⚠️ Installation finished with non-fatal warnings (exit code: $exit_code).

Review the detailed log file for details:
  $LOG" \
        12 65
fi

echo -e "\n${GREEN}[OK] Done.${RESET} Log: ${CYAN}$LOG${RESET}\n"
