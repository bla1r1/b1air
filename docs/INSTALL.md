# Installing b1air

### Supported distributions

| Family | Versions | Quickshell | Compositor |
| :--- | :--- | :--- | :--- |
| **Arch** (EndeavourOS, Manjaro, CachyOS, …) | rolling | official repo | swayFX built from source |
| **Debian / Ubuntu** (Mint, Pop!_OS, …) | Debian 13+, Ubuntu 25.04+ | built from source | swayFX built from source |
| **Fedora** (Nobara, …) | 40+ | COPR `errornointernet/quickshell`, else source | swayFX built from source |
| **openSUSE** *(experimental)* | Tumbleweed / Slowroll | repo if present, else source | swayFX built from source |

There is one compositor: ours. A sway or swayfx package already installed
(the distribution's or the AUR's) is removed once ours is built, so the login
screen does not offer two Sway sessions — `B1AIR_SWAYFX_FROM_SOURCE=0` takes
the packaged swayFX instead (the AUR's on Arch), `B1AIR_KEEP_DISTRO_SWAY=1`
keeps a packaged one beside ours. Should the build fail, plain sway is
installed so there is a desktop, and the next install.sh run tries again.
`tools/check-packages.sh`, run in CI for every family, checks that every name
in `packages/` exists in that family's repositories.

Where swayFX is built from source (`tools/build-swayfx.sh`), it is built the
way the sway fork scroll ships: swayFX 0.6 with its own copies of wlroots
0.20.2 and scenefx 0.5 in its `subprojects/`, installed to `/usr/local` with
the two libraries in a private `/usr/local/lib/b1air-swayfx`. Whatever wlroots
the distribution has (Ubuntu 26.04: 0.19) is not used and not touched. The
versions are pinned in the script and move together; wlroots is fetched from
gitlab.freedesktop.org at install time. Our own changes are patch series on
top (`src/swayfx/`), among them a fallback that lets swayFX start without a
GPU, on a software renderer without effects, rather than not start at all.

The family is detected from `/etc/os-release`; derivatives are matched through
`ID_LIKE`, and `--distro arch|debian|fedora|opensuse` overrides it. The desktop
needs **Qt 6.6 or newer**, which is why Debian 12 and Ubuntu 24.04 (Qt 6.4) are
not supported — the installer checks this before installing anything.

On plain sway (no swayFX) there is no blur, no rounded corners and no shadows;
the installer comments those swayFX-only lines out of your deployed
`~/.config/sway/conf.d`, so sway starts without config errors. Everything else
works the same.

Package lists live in [`packages/`](packages) — one file per family, `?name`
marks a package that may not exist on every release and is skipped if absent.

Remote access is disabled and bound to localhost by default. For the background
VM preview workflow only, explicitly start the session with `B1AIR_DEV_MODE=1`;
this enables LAN binding and development-only prompt-free screencasting.

### Option 1: One-Line Installer

The bootstrap script refuses to run an unpinned checkout, so pass the commit
you have reviewed:

```bash
DOTFILES_COMMIT=<40-character commit hash> \
  bash <(curl -fsSL https://raw.githubusercontent.com/bla1r1/DotsFiles/main/bootstrap.sh)
```

### Option 2: Manual Clone

```bash
git clone --recurse-submodules https://github.com/bla1r1/DotsFiles.git ~/DotsFiles
cd ~/DotsFiles
./install.sh
```

For an interactive menu:

```bash
./install-ui.sh
```

#### Editions

Each edition is the one before it plus what it adds
([packages/editions](packages/editions/README.md)):

| Edition | What it is |
|---|---|
| `minimal` | The desktop and its apps, nothing more |
| `default` | minimal + Windows programs (Proton through umu-launcher, in the Launchpad; Wine and Bottles too), `.deb` on Arch (debtap), software search in Spotlight (Flatpak), containers (Distrobox), VPN (OpenVPN, WireGuard, Tailscale) and a firewall |
| `gaming` | default + Steam, Heroic, ProtonUp-Qt, MangoHud, GameMode, gamescope and the 32-bit graphics drivers |

```bash
./install.sh --edition gaming
```

The installer's menu (`./install-ui.sh`) asks. Another edition is a directory
in `packages/editions/` naming the one it adds to and listing its packages.

#### Flags
```bash
# Deploy dotfiles and compile C++ tools without reinstalling packages
./install.sh --skip-packages

# Arch: no AUR (plain sway). Others: no downloads from upstream releases
# (JetBrainsMono Nerd Font, starship, eza)
./install.sh --no-aur

# Force the distribution family when detection gets it wrong
./install.sh --distro debian

# Preview actions without changing the system
./install.sh --dry-run
```

Environment variables: `QUICKSHELL_REF` (tag built from source, default
`v0.3.1`), `B1AIR_QUICKSHELL_FROM_SOURCE=1` (build Quickshell even where a
package exists), `B1AIR_SWAYFX_FROM_SOURCE=1` (build swayFX with its own
wlroots even where a package exists), `SWAYFX_REF` / `SCENEFX_REF` /
`WLROOTS_REF` and the matching `*_REPO` (other versions or mirrors for that
build), `B1AIR_SKIP_QT_CHECK=1` (skip the Qt version check).

An interrupted install resumes where it stopped; `--restart` starts over.

#### Other accounts

Install once, as one user; every account on the machine can then pick the
b1air session at the login screen. The defaults go to `/usr/share/b1air`
(configuration, wallpapers, cursors), and the session copies them into an
account at its first login — nothing it already has is overwritten. After
an update, the shipped files are brought up to date at the next login (the
replaced ones are kept in `~/.dotfiles-backup-<date>`); what was chosen in
Settings is left alone.

What only root can give another account — the `input` group (Magic Mouse
gestures, remote control), the `power` group (battery charge limit) and fish
as its shell:

```bash
./install.sh --add-user anna
```
