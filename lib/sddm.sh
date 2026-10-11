# shell=bash
# =============================================================================
# lib/sddm.sh — the login screen: theme, sddm.conf and the shared wallpaper
#
# Sourced by install.sh and update-dotfiles.sh. Only install.sh used to put the
# theme down, so an update left /usr/share/sddm/themes/b1air at whatever the
# first install shipped, and a fix to the theme never reached the login screen.
#
# /var/cache/wallpaper is how the desktop talks to the greeter (sddm runs as
# its own user and cannot read $HOME): b1air-daemon puts the wallpaper and the
# palette there, group `wallpaper`, of which this user and sddm are members.
# =============================================================================

# deploy_sddm_theme <repo_dir> [dry_run]
deploy_sddm_theme() {
    local repo="$1" dry="${2:-0}"
    local src="$repo/usr/share/sddm/themes/b1air" dst="/usr/share/sddm/themes/b1air"
    local group="wallpaper" user="${SUDO_USER:-$USER}"
    local cache_dir="/var/cache/wallpaper" cache_wall="/var/cache/wallpaper/current.jpg"

    if [[ "$dry" -eq 1 ]]; then
        log "Would install the SDDM theme to $dst, /etc/sddm.conf and $cache_dir"
        return 0
    fi

    if [[ -d "$src" ]]; then
        sudo install -d -m 755 "$dst"
        sudo rsync -a --delete --chown=root:root "$src/" "$dst/"
        if sudo diff -rq "$src" "$dst" >/dev/null; then
            ok "Login screen theme installed to $dst"
        else
            warn "The login screen theme in $dst differs from the repo after copying it."
        fi
    fi
    if [[ -f "$repo/etc/sddm.conf" ]]; then
        sudo install -Dm644 "$repo/etc/sddm.conf" /etc/sddm.conf
    fi

    sudo groupadd -f "$group"
    sudo install -d -o root -g "$group" -m 2775 "$cache_dir"
    id "$user" >/dev/null 2>&1 && sudo usermod -aG "$group" "$user" || true
    id sddm >/dev/null 2>&1 && sudo usermod -aG "$group" sddm || true

    # A picture for the very first login: the one the desktop starts on too
    # (wallpaper restore), so the two match. Only where there is none yet —
    # or an empty one, which an older b1air-daemon left behind when it could
    # not copy over a root-owned file — never over the one the user chose.
    # Owned by the user, so the daemon can replace it without the group.
    if [[ ! -s "$cache_wall" ]]; then
        local seed="$repo/.wallpapers/Sky/clouds-day.jpg"
        [[ -f "$seed" ]] || seed="$(find "$repo/.wallpapers" -maxdepth 2 -type f \( -iname '*.jpg' -o -iname '*.png' \) 2>/dev/null | head -n 1 || true)"
        [[ -n "$seed" && -f "$seed" ]] && sudo install -o "$user" -g "$group" -m 664 "$seed" "$cache_wall"
    fi
}
