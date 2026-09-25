# b1air Desktop Environment

<div align="center">

![b1air Desktop Environment](https://raw.githubusercontent.com/bla1r1/DotsFiles/main/.wallpapers/tokyo-night.jpg)

**A keyboard-driven Wayland desktop for Linux — Arch, Debian/Ubuntu, Fedora and openSUSE.**  
*Built with SwayFX, Qt6/QML, a native C++20 core daemon, and Tokyo Night styling.*

[![Arch Linux](https://img.shields.io/badge/Arch_Linux-Ready-1793d1?style=flat-square&logo=archlinux&logoColor=white)](https://archlinux.org)
[![Debian / Ubuntu](https://img.shields.io/badge/Debian_13+_/_Ubuntu_25.04+-Supported-a81d33?style=flat-square&logo=debian&logoColor=white)](https://debian.org)
[![Fedora](https://img.shields.io/badge/Fedora_40+-Supported-51a2da?style=flat-square&logo=fedora&logoColor=white)](https://fedoraproject.org)
[![openSUSE](https://img.shields.io/badge/openSUSE_Tumbleweed-Experimental-73ba25?style=flat-square&logo=opensuse&logoColor=white)](https://www.opensuse.org)
[![Compositor: SwayFX](https://img.shields.io/badge/SwayFX-0.6-005577?style=flat-square&logo=wayland&logoColor=white)](https://github.com/WillPower3309/swayfx)
[![UI: Qt6 / QML](https://img.shields.io/badge/Shell-Qt6_QML-41cd52?style=flat-square&logo=qt&logoColor=white)](https://qt.io)
[![Core: C++20](https://img.shields.io/badge/Daemon-C++20-00599c?style=flat-square&logo=c%2B%2B&logoColor=white)](https://isocpp.org)
[![Theme: Tokyo Night](https://img.shields.io/badge/Palette-Tokyo_Night-7aa2f7?style=flat-square)](https://github.com/folke/tokyonight.nvim)
[![License: GPL v2.0](https://img.shields.io/badge/License-GPL_v2.0-blue?style=flat-square)](LICENSE)

</div>

---

## Overview

b1air is a unified desktop setup for Linux designed around keyboard efficiency, low latency, and a consistent dark theme across all applications.

Key components:
* **Compositor**: SwayFX with hardware-accelerated rounded corners, soft shadows, and selective blur. Window chrome, the greeter and the Qt/Kvantum application theme use Tokyo Night (`#1a1b26`); the Qt6/QML shell and the native apps share one design system built on a Catppuccin Mocha palette (`Ui/Design.qml`).
* **Core Daemon (`b1air-daemon`)**: A single compiled C++20 binary that manages window autotiling, focus tracking (SQLite3), audio and microphone controls (PipeWire via `wpctl`), PAM user profiles, and power management without shell script overhead.
* **Desktop Shell**: Lightweight Qt6/QML overlays providing an application launcher, clipboard history, control center, emoji picker, and a visual Alt+Tab window switcher.
* **Remote Access**: Built-in headless WayVNC support and unattended screencasting configuration for AnyDesk, RustDesk, and OBS with persistent uinput permissions.

---

## Architecture

### Spotlight Launcher (`Super + Space`)
Fuzzy application search, clipboard history, and inline math calculations in a single centered overlay.

### Settings & Control Center (`Super + I` / `Super + C`)
Graphical desktop configuration:
* Wallpaper selection with a live preview grid. (Deriving the shell accent from the wallpaper is not implemented — `Design._applyPalette()` is the seam it will plug into, and nothing calls it yet.)
* Audio sink selector and per-stream volume controls.
* Focus time and screen usage analytics stored in SQLite.
* Toggles for Night Light, Game Mode (disables blur and pins performance governor), and Remote Desktop.

### SDDM Greeter
Matches the desktop Tokyo Night theme with digital clock, user avatar synchronization, session selection, and virtual keyboard support.

---

## Installation

### Supported distributions

| Family | Versions | Quickshell | Compositor |
| :--- | :--- | :--- | :--- |
| **Arch** (EndeavourOS, Manjaro, CachyOS, …) | rolling | official repo | swayFX (AUR), or sway with `--no-aur` |
| **Debian / Ubuntu** (Mint, Pop!_OS, …) | Debian 13+, Ubuntu 25.04+ | built from source | swayFX, built from source with its own wlroots |
| **Fedora** (Nobara, …) | 40+ | COPR `errornointernet/quickshell`, else source | swayFX |
| **openSUSE** *(experimental)* | Tumbleweed / Slowroll | repo if present, else source | swayFX if present, else built from source |

Where swayFX is built from source (`tools/build-swayfx.sh`), it is built the
way the sway fork scroll ships: swayFX 0.6 with its own copies of wlroots
0.20.2 and scenefx 0.5 in its `subprojects/`, installed to `/usr/local` with
the two libraries in a private `/usr/local/lib/b1air-swayfx`. Whatever wlroots
the distribution has (Ubuntu 26.04: 0.19) is not used and not touched. The
versions are pinned in the script and move together; wlroots is fetched from
gitlab.freedesktop.org at install time.

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
git clone https://github.com/bla1r1/DotsFiles.git ~/DotsFiles
cd ~/DotsFiles
./install.sh
```

For an interactive menu:

```bash
./install-ui.sh
```

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

---

## Keybindings

| Shortcut | Action | Target |
| :--- | :--- | :--- |
| `Super + T` | Open Terminal | b1air-term |
| `Super + Space` | Application Grid | Launchpad |
| `Super + K` / `Super + /` | Application Launcher | Spotlight |
| `Super + E` | File Manager | b1air-files |
| `Super + Shift + S` | Settings Hub | Settings App |
| `Super + C` | Control Center | Quick Toggles |
| `Super + V` | Clipboard History | Clipboard Manager |
| `Super + .` | Emoji Picker | Emoji Popup |
| `Alt + Tab` | Window Switcher | Visual Switcher |
| `Super + Shift + C` | Color Picker | Screen Eyedropper |
| `Super + Shift + T` | Screen Time Analytics | FocusTime |
| `Super + Shift + G` | Toggle Game Mode | b1air-daemon |
| `Super + Q` | Close Window | Sway |
| `Super + Ctrl + Space` | Toggle Floating | Sway |
| `Super + -` / `Super + Shift + -` | Minimize / Restore Window | b1air-daemon |
| `Print` | Region Screenshot | grim + slurp |
| `Super + Print` | Full Screen Screenshot | b1air-daemon |
| `Super + Shift + Print` | Focused Window Screenshot | b1air-daemon |
| `Ctrl + Alt + L` | Lock Screen | Lockscreen |
| `Super + Shift + E` | Session Menu | Power Menu |

---

## CLI Reference: `b1air-daemon`

`b1air-daemon` provides direct command-line access to desktop subsystems:

```bash
# Screen time statistics
b1air-daemon stats                 # Show today's app usage summary
b1air-daemon stats 2026-08-26      # Query specific date

# Hardware controls
b1air-daemon volume up 5           # Volume +5% (wpctl / PipeWire)
b1air-daemon volume down 5         # Volume -5%
b1air-daemon volume mute           # Toggle audio mute
b1air-daemon mic toggle            # Toggle microphone mute
b1air-daemon brightness up 5       # Screen brightness +5%
b1air-daemon color-picker          # Eyedropper hex to clipboard

# Remote Desktop & Screencast
b1air-secret-service set vnc-password  # Set encrypted WayVNC password (stdin recommended)
b1air-daemon remote start-stdin 5900  # Start authenticated TLS WayVNC; password via stdin
b1air-daemon remote stop           # Stop WayVNC
b1air-daemon remote status         # JSON status of remote service
b1air-daemon remote prompt-free on # Enable unattended screencasting

# Session Management
b1air-daemon lock                  # Lock screen immediately
b1air-daemon game-mode toggle      # Switch between power-save and low-latency mode
```

---

## Repository Structure

```text
DotsFiles/
├── .config/                   # User configurations (SwayFX, Fish, Kvantum, GTK/Qt, portals)
│   ├── fish/                  # Fish shell with Tokyo Night theme
│   ├── sway/                  # SwayFX compositor keybinds, rules, look & feel
│   ├── systemd/               # Systemd user services for the b1air session
│   └── xdg-desktop-portal-wlr # Unattended screencast configuration
├── .local/share/icons/        # The b1air cursor theme (built from src/cursors)
├── .wallpapers/               # Wallpapers offered in Settings
├── src/                       # Compiled C++20 desktop suite & Qt6 shell
│   ├── CMakeLists.txt         # One build for the whole suite, into src/build
│   ├── Makefile               # `make` builds, `make install` installs
│   ├── cmake/B1airApp.cmake   # b1air_add_app(): how every app is built
│   ├── daemon/                # b1air-core library; b1air-daemon, polkit agent, secret service
│   ├── shell/                 # b1air-shell: Qt6/QML desktop (TopBar, launcher, popups, Settings)
│   ├── apps/<app>/            # One program each: sources, <App>Window.qml, .desktop, icon
│   │                          #   camera files git monitor notes settings term text view
│   ├── common/                # Headers shared by several programs (QML search path)
│   ├── qmlplugin/             # B1air.Daemon QML module
│   ├── compat/                # Quickshell stand-in that lets b1air-settings run on its own
│   ├── cursors/               # Sources of the b1air cursor theme
│   └── third_party/           # Vendored SQLite, nlohmann/json, libvterm
├── usr/                       # System session files
│   ├── bin/b1air-session      # Wayland session launch wrapper
│   └── share/                 # SDDM greeter, wayland-sessions, and portal configs
├── etc/                       # System-wide configurations (SDDM, udev rules, tiny-dfr)
├── lib/distro.sh              # Distribution detection & package-manager layer
├── packages/                  # Package lists per distribution family
├── tools/                     # Development utilities (smoke tests, controller)
├── docs/ROADMAP.md            # Milestone roadmap & feature specs
├── bootstrap.sh               # One-line remote installer
├── install.sh                 # Installation engine (Arch, Debian/Ubuntu, Fedora, openSUSE)
├── install-ui.sh              # Interactive Whiptail TUI installer
├── update-dotfiles.sh         # Environment updater & config sync manager
├── LICENSE                    # GNU General Public License v2.0
└── README.md
```

---

## Roadmap

See [`docs/ROADMAP.md`](docs/ROADMAP.md). It opens with what is next and in
what order, what was dropped and why, and the corrections from an audit of the
completed milestones — the `[x]` marks say a thing was built, never that it
works.

---

## License

This project is licensed under the **GNU General Public License v2.0 only** (`GPL-2.0-only`).  
See [LICENSE](LICENSE) for the full text.
