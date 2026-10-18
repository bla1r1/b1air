# Editions

Each edition is the one it names in `parent` plus what its own lists add:

    minimal   packages/<family>.txt, packages/arch-aur.txt — the desktop itself
    default   minimal + Windows programs, software search, containers, VPN, firewall
    gaming    default + Steam, Heroic, MangoHud, GameMode, 32-bit graphics drivers

`install.sh --edition <name>` installs one (default: `default`); the installer's
menu offers them all. The choice is kept in `/etc/b1air/edition`, and
`update-dotfiles.sh` keeps that edition's packages installed.

Changing it later: **Settings → Updates → Edition**, or
`update-dotfiles.sh --edition <name>`. Going to a larger edition installs what
it adds; going to a smaller one removes nothing. A machine installed before
there were editions is asked which one at its next update (with `--yes`, or
with no one at the terminal: `default`).

## A new edition

Make a directory here named after it, with:

| file | what |
|---|---|
| `parent` | the edition it adds to, one word |
| `description` | one line, shown in the installer's menu |
| `arch.txt`, `debian.txt`, `fedora.txt`, `opensuse.txt` | the packages it adds, as in `packages/<family>.txt` (`?name` = optional) |
| `arch-aur.txt` | what it adds from the AUR |
| `flatpak.txt` | Flathub apps: `<app id> [command]`, skipped where `command` already exists |

Any of the lists may be left out. Nothing else changes: the installer finds it.
