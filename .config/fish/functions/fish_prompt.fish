function fish_prompt --description 'Write out the prompt'
    set -l last_pipestatus $pipestatus
    set -l normal (set_color normal)

    # If starship is installed, let it handle the prompt
    if type -q starship
        return
    end

    # The terminal's own colours, by name, so the prompt follows the theme
    # (see starship.toml).
    set -l color_cwd (set_color --bold cyan)
    set -l color_git (set_color --bold magenta)
    set -l color_arrow (set_color --bold blue)
    set -l color_error (set_color --bold red)

    # Git branch
    set -l git_info ""
    if command -v git >/dev/null 2>&1
        set -l branch (command git symbolic-ref --short HEAD 2>/dev/null; or command git rev-parse --short HEAD 2>/dev/null)
        if test -n "$branch"
            set git_info " on $color_git$branch$normal"
        end
    end

    # Status arrow color
    set -l arrow_color $color_arrow
    for status_code in $last_pipestatus
        if test $status_code -ne 0
            set arrow_color $color_error
            break
        end
    end

    echo -n -s $color_arrow "󰣇 " $color_cwd (prompt_pwd) $normal $git_info "\n" $arrow_color "❯ " $normal
end
