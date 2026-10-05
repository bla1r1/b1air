# shell=bash
# =============================================================================
# lib/wallpapers.sh — the shipped wallpapers into ~/.wallpapers
#
# Sourced by install.sh and update-dotfiles.sh. The wallpapers sit in one
# folder per category (.wallpapers/Mountains/…, Sky/…), which Settings →
# Wallpaper shows as groups. Added, never replaced or deleted: the folder is
# where people are invited to put their own. The one exception is a copy an
# older version left loose at the top — the same picture, by content, as one
# that now has a category — which goes, or every one of them would show
# twice under its old number-name.
# =============================================================================

# sync_wallpapers <repo_dir> [dry_run]
sync_wallpapers() {
    local src="$1/.wallpapers" dst="$HOME/.wallpapers" dry="${2:-0}"
    [[ -d "$src" ]] || return 0
    [[ "$dry" -eq 1 ]] && { log "Would add the shipped wallpapers to ~/.wallpapers"; return 0; }
    mkdir -p "$dst"

    local -A shipped=()
    local f rel sum
    while IFS= read -r -d '' f; do
        rel="${f#"$src"/}"
        sum="$(sha1sum "$f" | cut -d' ' -f1)"
        shipped[$sum]="$rel"
        if [[ ! -e "$dst/$rel" ]]; then
            mkdir -p "$(dirname "$dst/$rel")"
            cp -a "$f" "$dst/$rel"
        fi
    done < <(find "$src" -mindepth 2 -maxdepth 2 -type f ! -name '.*' -print0)

    while IFS= read -r -d '' f; do
        sum="$(sha1sum "$f" | cut -d' ' -f1)"
        if [[ -n "${shipped[$sum]:-}" ]]; then
            rm -f "$f"
        fi
    done < <(find "$dst" -mindepth 1 -maxdepth 1 -type f ! -name '.*' -print0)
}
