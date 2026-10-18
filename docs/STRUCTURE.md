# Where things are in the repository

```text
DotsFiles/
├── .config/                   # User configurations (SwayFX, Fish, Kvantum, GTK/Qt, portals)
│   ├── fish/                  # Fish shell: prompt, aliases, greeting
│   ├── sway/                  # SwayFX compositor keybinds, rules, look & feel
│   ├── systemd/               # Systemd user services for the b1air session
│   └── xdg-desktop-portal-wlr # Unattended screencast configuration
├── .local/share/icons/        # The b1air cursor theme (built from src/cursors)
├── .wallpapers/<Category>/    # Wallpapers offered in Settings, a folder per category
├── src/                       # Compiled C++20 desktop suite & Qt6 shell
│   ├── CMakeLists.txt         # One build for the whole suite, into src/build
│   ├── Makefile               # `make` builds, `make install` installs
│   ├── cmake/B1airApp.cmake   # b1air_add_app(): how every app is built
│   ├── daemon/                # b1air-core library; b1air-daemon, polkit agent, secret service
│   ├── shell/                 # b1air-shell: Qt6/QML desktop (TopBar, launcher, popups, Settings)
│   ├── apps/<app>/            # One program each: sources, <App>Window.qml, .desktop, icon
│   │                          #   camera files git monitor settings term text view
│   ├── common/                # Headers shared by several programs (QML search path)
│   ├── qmlplugin/             # B1air.Daemon QML module
│   ├── bg/                    # b1air-bg: the wallpaper, per screen and per workspace
│   ├── clip/                  # b1air-clip: copy, paste and watch the clipboard (no wl-clipboard)
│   ├── gamma/                 # b1air-gamma: night light, fixed or by hours or sunset/sunrise
│   ├── lock/                  # b1air-lock: the lock screen (no swaylock)
│   ├── shot/                  # b1air-shot: the Print overlay — region, record, QR
│   ├── pam/                   # Fingerprint PAM file for the lock screens; the login screen's helper
│   ├── compat/                # Quickshell stand-in that lets b1air-settings run on its own
│   └── cursors/               # Sources of the b1air cursor theme
├── usr/                       # System session files
│   ├── bin/b1air-session      # Wayland session launch wrapper
│   └── share/                 # SDDM greeter, wayland-sessions, and portal configs
├── etc/                       # System-wide configurations (SDDM, udev rules, tiny-dfr)
├── lib/                       # Shared by the scripts: distro.sh (distribution, packages),
│                              #   fingerprint.sh (reader drivers), wallpapers.sh
├── packages/                  # Package lists per distribution family
├── tools/                     # Development utilities (smoke tests, controller)
├── docs/                      # ROADMAP.md (milestones), screenshots/
├── bootstrap.sh               # One-line remote installer
├── install.sh                 # Installation engine (Arch, Debian/Ubuntu, Fedora, openSUSE)
├── install-ui.sh              # Interactive Whiptail TUI installer
├── update-dotfiles.sh         # Environment updater & config sync manager
├── LICENSE                    # GNU General Public License v2.0
└── README.md
```
