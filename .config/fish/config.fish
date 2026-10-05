# =============================================================================
# Fish Shell Configuration
# =============================================================================

if status is-interactive
    # Greeting
    # The greeting the old prompt opened with. Emptied at some point during the
    # move off tide; fastfetch below prints over it either way, but it is what
    # a shell that says "Welcome back" says.
    set -g fish_greeting "Welcome back, $USER 🐟"

    # ── Syntax highlighting ──────────────────────────────────────────────────
    # Named colours, not hex: they come from the terminal's palette, which
    # follows the desktop theme (Breeze or Adwaita, dark or light). Fixed
    # Tokyo Night hex values were pale pastels on a light terminal.
    set -g fish_color_normal normal
    set -g fish_color_command blue --bold
    set -g fish_color_keyword magenta
    set -g fish_color_quote green
    set -g fish_color_redirection cyan
    set -g fish_color_end yellow
    set -g fish_color_error red --bold
    set -g fish_color_param normal
    set -g fish_color_comment brblack
    set -g fish_color_selection --reverse
    set -g fish_color_search_match --reverse
    set -g fish_color_operator cyan
    set -g fish_color_escape magenta
    set -g fish_color_autosuggestion brblack
    set -g fish_color_cancel red

    # Pager colors
    set -g fish_pager_color_progress brblack
    set -g fish_pager_color_prefix cyan --bold
    set -g fish_pager_color_completion normal
    set -g fish_pager_color_description brblack
    set -g fish_pager_color_selected_background --reverse

    # ── Environment & Exports ────────────────────────────────────────────────
    set -gx EDITOR nvim
    set -gx VISUAL code
    set -gx BUN_INSTALL $HOME/.bun

    # PATH setup
    set -gx PATH $HOME/.local/bin $HOME/.cargo/bin $BUN_INSTALL/bin $PATH

    # ── Modern Tool Integrations ─────────────────────────────────────────────
    # Starship Prompt
    if type -q starship
        starship init fish | source
    end

    # Zoxide (Smart directory jumping)
    if type -q zoxide
        zoxide init fish | source
    end

    # ── Modern CLI Aliases ───────────────────────────────────────────────────
    # File listing (eza)
    if type -q eza
        alias ls 'eza --icons=auto --group-directories-first'
        alias l 'eza -lh --icons=auto --group-directories-first'
        alias ll 'eza -lha --icons=auto --sort=name --group-directories-first --git --header'
        alias ld 'eza -lhD --icons=auto'
        alias lt 'eza --tree --level=2 --icons=auto'
        alias tree 'eza --tree --icons=auto'
    else
        alias ls 'ls --color=auto'
        alias l 'ls -lh --color=auto'
        alias ll 'ls -lha --color=auto'
    end

    # File reading (bat). Debian and Ubuntu install it as `batcat`.
    if not type -q bat; and type -q batcat
        alias bat batcat
    end
    if type -q bat
        alias cat 'bat --style=plain --paging=never'
        alias preview 'bat --style=numbers --color=always'
    end

    # Safe deletion (trash-cli)
    if type -q trash
        alias rm 'trash -v'
    end

    # General navigation & shortcuts
    alias c 'clear'
    alias .. 'cd ..'
    alias ... 'cd ../..'
    alias .3 'cd ../../..'
    alias .4 'cd ../../../..'
    alias .5 'cd ../../../../..'
    alias mkdir 'mkdir -p'
    alias vim 'nvim'
    alias vc 'code'
    alias ff 'fastfetch'

    # ── Git Shortcuts ────────────────────────────────────────────────────────
    alias gs 'git status -sb'
    alias ga 'git add'
    alias gaa 'git add -A'
    alias gc 'git commit -v'
    alias gp 'git push'
    alias gpl 'git pull --rebase'
    alias gd 'git diff'
    alias gds 'git diff --staged'
    alias gb 'git branch'
    alias gco 'git checkout'
    alias glog "git log --graph --pretty=format:'%Cred%h%Creset -%C(yellow)%d%Creset %s %Cgreen(%cr) %C(bold blue)<%an>%Creset' --abbrev-commit"

    # ── Dotfiles & Desktop Environment Helpers ───────────────────────────────
    alias dots 'cd ~/.config/sway/../.. 2>/dev/null; or cd ~/Documents/GitHub/DotsFiles'
    alias dots-sync 'b1air-daemon dotfiles sync'
    alias dots-diff 'b1air-daemon dotfiles status'
    alias sway-reload 'swaymsg reload'
    alias qs-reload 'pkill -9 quickshell; quickshell -p ~/.config/quickshell/Main.qml >/dev/null 2>&1 & disown'
    alias game-mode 'b1air-daemon game-mode'
    alias b1air-lock 'b1air-daemon power lock'
    alias b1air-stats 'b1air-daemon stats'
    alias fs-toggle 'b1air-daemon fullscreen-toggle'

    # ── Fastfetch on Startup ─────────────────────────────────────────────────
    if test -z "$TMUX" && type -q fastfetch
        fastfetch
    end
end

# =============================================================================
# Helper Functions
# =============================================================================

# Create directory and enter it
function mkcd --description "Create a directory and enter it immediately"
    if test (count $argv) -eq 0
        echo "Usage: mkcd <directory_path>"
        return 1
    end
    mkdir -p $argv[1]; and cd $argv[1]
end

# Safe universal archive extractor
function ex --description "Extract any archive automatically"
    if test (count $argv) -eq 0
        echo "Usage: ex <archive_file>"
        return 1
    end
    if test -f $argv[1]
        switch $argv[1]
            case '*.tar.bz2'
                tar xjf $argv[1]
            case '*.tar.gz'
                tar xzf $argv[1]
            case '*.bz2'
                bunzip2 $argv[1]
            case '*.rar'
                unrar x $argv[1]
            case '*.gz'
                gunzip $argv[1]
            case '*.tar'
                tar xf $argv[1]
            case '*.tbz2'
                tar xjf $argv[1]
            case '*.tgz'
                tar xzf $argv[1]
            case '*.zip'
                unzip $argv[1]
            case '*.Z'
                uncompress $argv[1]
            case '*.7z'
                7z x $argv[1]
            case '*.tar.xz'
                tar xf $argv[1]
            case '*.tar.zst'
                tar --zstd -xf $argv[1]
            case '*'
                echo "'$argv[1]' cannot be extracted via ex"
                return 1
        end
    else
        echo "'$argv[1]' is not a valid file"
        return 1
    end
end

# Interactive process kill via fzf
function fkill --description "Fuzzy-find and kill a process"
    if not type -q fzf
        echo "fzf is required for fkill"
        return 1
    end
    set -l pid (ps -ef | sed 1d | fzf -m | awk '{print $2}')
    if test -n "$pid"
        echo $pid | xargs kill -9
        echo "Terminated PID(s): $pid"
    end
end

# Quick git add, commit with message, and push
function git-sync --description "Git add, commit, and push in one command"
    if test (count $argv) -eq 0
        echo "Usage: git-sync <commit message>"
        return 1
    end
    git add -A
    git commit -m (string join ' ' -- $argv)
    git push
end

# Undo last git commit safely preserving working files
function gundo --description "Undo last commit keeping changes in workspace"
    git reset --soft HEAD~1
    echo "Undid last commit. Changes are staged."
end

# Interactive AUR / Pacman search with fzf preview
function aur-search --description "Search Arch & AUR packages with interactive fzf preview"
    if not type -q fzf
        echo "fzf not found. Install fzf to use aur-search."
        return 1
    end

    if type -q yay
        set -l packages (yay -Slq | fzf --multi --preview 'yay -Sii {1}' --preview-window=down:75%)
        test (count $packages) -gt 0; and yay -S $packages
    else if type -q paru
        set -l packages (paru -Slq | fzf --multi --preview 'paru -Si {1}' --preview-window=down:75%)
        test (count $packages) -gt 0; and paru -S $packages
    else
        echo "AUR helper (yay/paru) not found."
        return 1
    end
end

# Package manager backend detector
function __dotfiles_pkg_backend
    if type -q yay
        echo yay
    else if type -q paru
        echo paru
    else if type -q pacman
        echo pacman
    else if type -q apt-get
        echo apt-get
    else if type -q dnf
        echo dnf
    else if type -q zypper
        echo zypper
    else if type -q emerge
        echo emerge
    end
end

# Universal System Upgrade
function up --description "Universal system package upgrade"
    set -l backend (__dotfiles_pkg_backend)
    switch $backend
        case yay paru
            command $backend -Syu
        case pacman
            sudo pacman -Syu
        case apt-get
            sudo apt-get update; and sudo apt-get upgrade -y
        case dnf
            sudo dnf upgrade --refresh -y
        case zypper
            sudo zypper refresh; and sudo zypper update -y
        case emerge
            sudo emerge --ask --verbose --update --deep --newuse @world
        case '*'
            echo "No supported package manager found."
            return 1
    end
end

# Universal Package Removal
function un --description "Universal package remove with orphans clean"
    if test (count $argv) -eq 0
        echo "Usage: un <package> [package ...]"
        return 1
    end

    set -l backend (__dotfiles_pkg_backend)
    switch $backend
        case yay paru
            command $backend -Rns $argv
        case pacman
            sudo pacman -Rns $argv
        case apt-get
            sudo apt-get remove --autoremove $argv
        case dnf
            sudo dnf remove -y $argv
        case zypper
            sudo zypper remove -y $argv
        case emerge
            sudo emerge --ask --depclean $argv
        case '*'
            echo "No supported package manager found."
            return 1
    end
end

# Universal Package Search
function pa --description "Universal package search"
    if test (count $argv) -eq 0
        echo "Usage: pa <search-term> [search-term ...]"
        return 1
    end

    set -l backend (__dotfiles_pkg_backend)
    switch $backend
        case yay paru pacman
            command $backend -Ss $argv
        case apt-get
            apt-cache search $argv
        case dnf
            dnf search $argv
        case zypper
            zypper search $argv
        case emerge
            emerge --search $argv
        case '*'
            echo "No supported package manager found."
            return 1
    end
end

# Universal Package Cache Clean
function pc --description "Clean package manager cache"
    set -l backend (__dotfiles_pkg_backend)
    switch $backend
        case yay paru pacman
            sudo pacman -Sc
        case apt-get
            sudo apt-get clean
        case dnf
            sudo dnf clean all
        case zypper
            sudo zypper clean --all
        case emerge
            eclean-dist --deep
        case '*'
            echo "No supported package manager found."
            return 1
    end
end

# Universal Remove Orphan Dependencies
function po --description "Remove unneeded orphan packages"
    set -l backend (__dotfiles_pkg_backend)
    switch $backend
        case yay paru
            set -l orphans (command $backend -Qtdq)
            test -n "$orphans"; and command $backend -Rns $orphans
        case pacman
            set -l orphans (pacman -Qtdq)
            test -n "$orphans"; and sudo pacman -Rns $orphans
        case apt-get
            sudo apt-get autoremove -y
        case dnf
            sudo dnf autoremove -y
        case zypper
            sudo zypper packages --orphaned
        case emerge
            sudo emerge --ask --depclean
        case '*'
            echo "No supported package manager found."
            return 1
    end
end
