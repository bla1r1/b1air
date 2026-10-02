# Roadmap

Status:

- `[x]`: completed.
- `[ ]`: not implemented.
- `[/]`: partly built — what exists and what is missing is written beside it.
- `[~]`: **dropped** — decided against, with the reason beside it. Kept in the
  file rather than deleted so the same idea does not come back as a new one.
- `initial` / `partial` / `deferred`: as before.

`b1nix` is a primary target of this Desktop Environment: each subsystem is built
to run standalone without systemd dependencies (supporting seatd, runit, and
native b1nix userspace).

## How to read the done column

It is mostly right. It was audited in September 2026 by checking, for every
completed milestone, that the keybinding exists in `conf.d/keybinds.conf`, that
the `b1air-daemon` verb exists in `main.cpp`, and that whatever external program
the verb shells out to is in the installer's package list. Those three held for
M1 through M3 and for most of M4.

What it does **not** tell you is whether a feature does anything once pressed.
That is a different question, and the answer has repeatedly been no: settings
pages that stored values nothing read, six daemon functions that parsed sway's
pretty-printed JSON by substring and so matched nothing, a privilege dialog that
could not build, a clipboard that recorded nothing. Treat `[x]` as "it was
built", never as "it works".

The open column was audited the other way in October 2026: for every `[ ]`,
whether the tree already does it. Nine did, in whole or in part — built as
part of something else and never ticked. They are marked below with what
exists. The same pass found `Super+G` launching `github-desktop`, which no
package list installs, while the suite's own Git client sat unbound; it runs
`b1air-git` now.

### Corrections

- **Waybar is not part of this project.** It is not in the installer's package
  list and the bar has been `shell/qml/TopBar.qml` for a long time. M0's "Waybar
  indicators" and M4's "Privacy Dots in Waybar" describe a component that does
  not exist, and M9 plans another one. References to it also survive in
  `settings_manager.cpp`, `system_control.cpp`, `settings.json`,
  `update-dotfiles.sh` and a comment in `TopBar.qml`; those want removing.
- **M4's Timeshift snapshot** is marked done. `timeshift` is not installed —
  `snapper` is — and until recently that code reported "Restore Point Created"
  whichever of them was missing. It reports honestly now, but the line promises
  more than exists.
- **M5's "Remote Desktop quick-toggle tile (`Super+C`)"** is unbuilt and the
  shortcut it names is already the Control Center.

## What is next

In order. These are the ones worth building, and the reason is written down so
that a future reader can disagree with the reason rather than guess at it.

1. **The shell in Russian** (M15) — the shell is in Ukrainian now
   (`i18n/uk.json`, every string); `ru.json` covers the apps only, and the
   shell's strings are left to translate there.
2. **swayfx on a pinned wlroots** — the installer builds swayfx against a
   wlroots bundled as a meson subproject when the distribution's does not
   match, so the desktop stops depending on which wlroots a distribution
   happens to ship.
3. **Caps Lock as Escape or Control** (M8) — one line of `xkb_options`, and
   the Keyboard page already writes them.
4. **Content search in Spotlight** (M9) — `rg` behind a prefix.
5. **Accessibility: colour filters and a large-text preset** (M13) — kept on
   purpose, see "What was cut".

Built since the last version of this list, in October 2026: dock/undock
display profiles, external monitor brightness, the drop-down terminal,
quiet hours, trash auto-purge and archive compression, the remote session
indicator and tile, four-finger gestures, per-screen wallpaper, a light
theme, tabs and batch rename in Files, CI, and the apps in Russian. Each is
ticked below with where it lives. Two real bugs surfaced on the way and are
fixed: WayVNC had never started (its config had no username), and the
"remembered" monitor layout lived in a tmpfs that every logout emptied.

The Waybar remnants that used to head this list are gone: five
`pkill -RTMIN+N waybar` calls signalling a process this desktop does not run,
and a `ddc waybar` verb named after it. The two `app_id == "waybar"` filters
stay — they keep a bar out of the window switcher, and are still right for
anyone who runs one.
A roadmap whose done column disagrees with the tree is worse than no roadmap,
because it is the one people make decisions from.

## What was cut, and why

Dropped items are marked `[~]` in their milestone below. The reasoning, in one
place:

- **Anything that reimplements a good existing tool.** The Wine/Proton prefix
  manager, the in-game FPS overlay, the checksum calculator and the disk
  treemap are Steam, MangoHud, `sha256sum` and `ncdu`. A desktop environment
  that ships its own worse copy of each has bought a maintenance burden and
  sold nothing.
- **Graphical front ends to files where a mistake breaks the boot.** The
  environment-variable editor and the system services manager.
- **Security theatre.** USB Guard and captive-portal detection are real
  measures in a fleet and a ritual on one personal laptop.
- **Novelty.** Mechanical keyboard sound simulation, song lyrics.
- **Overlap with what already exists.** The "Glance Layer canvas widgets" are
  the Control Center and calendar panels, which are now arrangeable and
  resizable in place.

Accessibility is not novelty and stays: the colour-blindness shaders and the
large-text preset in M13 are kept.

## M0: Core Foundation and Session Management

- [x] Implement compiled C++20 `b1air-daemon` multi-call binary with direct syscall and IPC dispatch.
- [x] Implement direct Sway IPC UNIX domain socket client (`sway_ipc.cpp`) for sub-millisecond workspace tracking.
- [x] Implement SQLite3 FocusTime analytics engine (`focustime_db.cpp`) with prepared statements.
- [x] Implement POSIX & PAM User Manager (`user_manager.cpp`) for SDDM avatar and display name synchronization.
- [x] Implement dynamic `.desktop` application scanner and autostart picker.
- [x] Implement Sway scratchpad window minimization system (`b1air-daemon window {minimize|restore|list|open}`).
- [x] Implement init-agnostic session supervisor with power fallbacks for `b1nix` (runit, seatd, elogind, systemd).
- [x] Implement FreeDesktop session suite (`b1air.desktop`, `b1air-session`, `b1air-portals.conf`).
- [x] Implement Quickshell Settings App with 15+ configuration pages.
- [x] Implement Quickshell Control Center, Spotlight Launcher, Lock Screen, and SDDM Greeter.
- [x] Implement Quickshell Polkit agent dialog, Desktop Notification toasts, and OSD volume/mic overlays.
- [x] Implement Quickshell Visual `Alt + Tab` Window Switcher and Screen Color Picker (`Super+Shift+C`).
- [x] Implement native Emoji Picker popup (`Super+.`) and Caffeine stay-awake mode.
- [x] Implement desktop audio feedback service (`SoundEffects.qml`) and Waybar indicators.

## M1: Productivity, Clipboard Intelligence, and Data Workflow

- [x] Add QuickLook instant file preview overlay for images, PDF, Markdown, code, and archives on `Space`.
- [x] Add Screen OCR text grabber (`Super+Shift+O`) via `slurp`, `grim`, and `tesseract`.
- [x] Add Drag & Drop shelf (floating file stash) for batch file staging and transfer.
- [x] Add QR code generator and screen scanner (`Super+Shift+Q`) via `qrencode` and `zbarimg`.
- [x] Add Smart Spotlight inline converters for currencies, units, and world timezones.
- [x] Add pinned snippets and permanent templates tab in Clipboard Manager (`Super+V`).

## M2: Advanced Window Management and Screen Assistants

- [x] Add FancyZones visual snapping grid assistant (`Super+Z`) for 1/3, 2/3, 2x2, and Ultrawide layouts.
- [x] Add universal Picture-in-Picture (PiP) pinned mini-view mode (`Super+P`).
- [x] Add cursor Shake-to-Find pulse locator for large 4K and multi-monitor setups.
- [x] Add Screen Ruler and Pixel Inspector (`Super+Shift+M`) for UI design measurements.
- [x] Add smooth hardware-accelerated Screen Magnifier (`Super+Alt++` / `Super+Alt+-`).
- [x] Add Force Quit target crosshair (`Super+Escape`) for terminating unresponsive processes.

## M3: Audio Subsystem, Recording, and Multimedia Ecosystem

- [x] Add per-application volume sliders and stream mixer in Control Center via PipeWire / WirePlumber.
- [x] Add AI microphone noise suppression toggle in Control Center via RNNoise / PipeWire filter-chain.
- [x] Add fast audio output switcher shortcut (`Super+Shift+A`) with graphical OSD confirmation.
- [x] Add Screen-to-GIF recording tool with automatic optimization and clipboard copy.
- [x] Add quick voice dictation and audio memo (`Super+Shift+V`) via local `whisper.cpp`.

## M4: Privacy, Security, and System Health Maintenance

- [x] Add live privacy dots for active microphone and camera access. Not in
      Waybar, which this desktop does not run — in the native bar's system
      island, shown only while a device is actually in use.
- [x] Add Disk Sweeper and cache cleaner module in Settings for pacman, orphan packages, and thumbnails.
- [x] Add automatic Btrfs and Timeshift pre-update restore point snapshot integration.
- [x] Add Encrypted Vaults GUI manager for mounting password-protected folders.

## M5: Device Ecosystem, Cross-Platform Synchronization, and Remote Desktop

- [ ] Add Phone Link integration (KDE Connect / b1Connect) for battery, SMS, clipboard, and ring-my-phone.
- [ ] Add LocalSend / QuickDrop wireless peer-to-peer file transfer in local Wi-Fi networks.
- [x] Add native WayVNC Remote Desktop control in `b1air-daemon` (`b1air-daemon remote {start|stop|status|toggle}`) with TLS and password auth.
- [x] Add Remote Desktop quick-toggle tile in Control Center with active client connection count badge.
      Hidden without wayvnc; red with the viewer count while someone watches.
- [x] Add Remote Desktop & Screen Sharing section in Settings App (`Super+Shift+S`) with port configuration, password management, and prompt-free permissions.
- [x] Add an active remote session indicator to the bar's system island, with a 1-click disconnect.
      Beside the microphone and camera dots: blue while listening, red while
      watched; a click stops the server. Viewers are counted from /proc/net/tcp.
- [x] Add headless sidecar display generator (`b1air-daemon sidecar create`) for using iPad / Android tablets as low-latency wireless secondary monitors via WayVNC.
- [x] Add direct compositor input injection via `wlr-virtual-pointer-v1`, `uinput`, and `virtual-keyboard-v1` to eliminate portal permission prompts.

## M6: Desktop Widgets, Personalization, and Smart UI

- [/] Add desktop Sticky Notes and scratchpad memos with Markdown formatting.
      **Built:** `b1air-notes`, Markdown with a live preview, tags and an
      Obsidian vault. **Missing:** notes on the desktop itself, and a key —
      `Super+Shift+N` is the notification centre.
- [~] Add desktop Glance Layer canvas widgets (`Super+G`) for clocks, weather, and circular hardware dials.
      **Cut:** The Control Center and calendar panels are this, and are now arrangeable in place.
- [x] Add visual GUI Keyboard Shortcuts editor in Settings for modifying keybindings without text editing.
      Keyboard → Desktop shortcuts: rebinding writes `unbindsym` for the old
      key as well as the new `bindsym`, so it replaces rather than adds.
- [ ] Add dynamic solar day/night auto-theming engine for sunrise/sunset wallpaper and palette switching.
- [ ] Add live rolling hardware sensor and temperature telemetry graph overlay.

## M7: Display, Multi-Monitor, and Color Calibration

- [x] Add fractional scaling GUI control in Display Settings (1.25x, 1.5x, 1.75x) — a stepper in 0.25 steps.
- [x] Add Display Profile automatic switching on dock/undock events for HDMI/Type-C displays.
      A layout per set of screens, keyed by make/model/serial, applied by the
      session daemon on sway's output events; Settings → Displays lists them.
- [x] Add external monitor hardware brightness control via DDC/CI in Control Center slider.
      In the Control Center's Battery & Power view and on Settings → Displays.
- [ ] Add ICC/ICM color profile calibration importer in Display Settings.
- [x] Add distinct per-workspace and per-monitor wallpaper assignment engine.
      Per screen (`wallpaper set <file> <output>`), following the monitor to
      any connector, and per workspace (`wallpaper set <file> --workspace
      <name>`), both from Settings → Wallpaper. Drawn by `b1air-bg`
      (`src/bg`), which replaces swaybg: plain wayland-client, one layer-shell
      surface per screen, the picture decoded at the screen's size straight
      into the buffer the compositor gets and then let go, and the crossfade
      done by the compositor (alpha-modifier). About 0.4–0.7 MB of its own
      memory against swaybg's 1.5.
- [x] Add per-monitor top bar content. The bar itself was already on every
      screen — `Main.qml` instantiates it through `Variants` over
      `Quickshell.screens`, fixed after a two-monitor desktop turned out to
      have a bar on one of them — but nothing in `TopBar.qml` read
      `topBar.screen`, so two or three monitors got two or three *identical*
      bars: the same tray, the same clock, and the same workspace strip with
      the same pill lit, because `focused` is global to the session rather
      than to an output. One bar carries the weather, the media title, the
      tray and the CPU island now; the others keep their workspaces, the clock
      and the system controls — volume and power should not need a trip to
      another screen, which is where the first sketch of this had them. The
      strip shows the workspaces on its own output, the unused numbers are
      offered by the main bar alone, and a pill lights only where the focus
      actually is. Which screen is the main one is on the Native Top Bar
      settings page, in a card that is absent when there is only one.
- [x] Add virtual headless display creation for tablet sidecar streaming.
      The same item as M5's `sidecar create`, over WayVNC rather than
      Moonlight/Sunshine; Settings → Remote Desktop → Create Display.

## M8: Advanced Input, Touchpad Gestures, and Keyboard Physics

- [/] Add 1:1 smooth multi-touch touchpad gestures (3-finger workspace switch, 4-finger overview/pinch).
      **Built:** three fingers between workspaces; four up for the Launchpad,
      down to close it, sideways to carry the window along (Settings → Mouse &
      Touchpad). **Missing:** 1:1 tracking — sway's gestures fire on
      completion, they do not follow the fingers.
- [x] Add mouse acceleration profile switcher (Flat raw sensor input vs Adaptive curve).
- [x] Add per-device scroll direction configuration (Natural scrolling for touchpad, standard for mouse wheel).
      Natural scrolling is set on `type:touchpad` only, so a mouse wheel keeps
      its own direction.
- [ ] Add 1-click CapsLock re-mapping to Escape/Control in Keyboard Settings.
- [x] Add a Caps Lock indicator to the bar, read from the kernel's own lock LED
      — sway's IPC does not report lock state and no protocol carries it.
- [ ] Add responsive on-screen virtual touch keyboard (OSK) for touchscreen devices.

## M9: Developer, Terminal, and Power-User Workflow

- [x] Add drop-down sliding Quake terminal (`Super+~`) persistent across all workspaces.
      `b1air-term --dropdown`, kept in the scratchpad so it keeps its tabs.
- [ ] Add global file content search (Ripgrep integration in Spotlight via `find:` / `grep:` prefix).
- [ ] Add open network ports and listening process inspector in Settings with 1-click process kill.
- [ ] Add Git repository status in Spotlight. (The Waybar half is moot; the
      suite has its own Git client, `b1air-git`, on `Super+G`.)
- [~] Add Environment Variables (`PATH`, `EDITOR`, `XDG_*`) GUI editor in Settings.
      **Cut:** A GUI over a file where a typo breaks the login.
- [~] Add System Services manager (systemd/runit/b1nix) in Settings Maintenance.
      **Cut:** Same, with more at stake.

## M10: Gaming, Graphics, and Low-Latency Performance

- [~] Add Variable Refresh Rate (VRR / G-Sync / FreeSync) toggle per output in Display Settings.
      **Cut:** One line of sway output config; a GUI for it is not the gap.
- [~] Add direct scanout compositor bypass for fullscreen games to achieve 0ms compositor overhead.
      **Cut:** A compositor concern, and swayfx's, not this daemon's.
- [~] Add in-game telemetry HUD overlay (`Super+Shift+F`) displaying FPS, frametimes, GPU/CPU load, and temps.
      **Cut:** MangoHud exists and is one line in a launch command.
- [~] Add connected gamepad controller battery level indicator in Waybar (DualSense, Xbox, 8BitDo).
      **Cut:** The bar is not where a controller battery is looked at.
- [~] Add Wine and Proton bottle prefix manager in App Launcher for running Windows executables.
      **Cut:** Steam and Lutris do this, and better.

## M11: File Management, Storage Analytics, and Archive Suite

- [x] Add batch file renamer with numbering, find & replace and case transformation.
      In Files: F2 on several items, with a preview and one-step undo.
- [~] Add interactive disk space sunburst / treemap visualizer in Settings.
      **Cut:** `ncdu` and `baobab`.
- [~] Add file checksum hash calculator and clipboard verifier (MD5, SHA256).
      **Cut:** `sha256sum` and `sha256sum -c`.
- [x] Add native archive compression and extraction for `.zip`, `.tar.gz`, `.tar.zst`, and `.7z`.
      Both in Files through libarchive: extraction refuses entries that would
      escape the target folder; "Compress…" writes any of the four.
- [x] Add scheduled Trash auto-purge (>30 days) and 1-click deleted file restore.
      Restore in Files' Trash view; the purge at login and when Files opens.

## M12: Network, VPN, Firewall, and Security Hardening

- [ ] Add 1-click WireGuard and OpenVPN quick tiles in Control Center with ping and killswitch telemetry.
- [~] Add automatic Captive Portal browser login popup detection for public Wi-Fi networks.
      **Cut:** The browser already does this.
- [ ] Add 1-click Wi-Fi Hotspot sharing in Network Settings.
- [ ] Add graphical Firewall (UFW / nftables) status monitor and port management in Security Settings.
- [~] Add USB Guard protection preventing unauthorized HID keyboard injection when locked.
      **Cut:** A fleet measure; on one laptop it is a ritual.

## M13: Wellness, Ergonomics, and Accessibility

- [/] Add 20-20-20 eye strain break reminder notification and subtle screen dim.
      **Built:** an hourly break reminder after continuous use, in the daemon,
      switched in Settings → Screen Time. **Missing:** the 20-minute cadence
      and the dim.
- [ ] Add accessibility color blindness shaders (Protanopia, Deuteranopia, Tritanopia) and Grayscale digital detox mode.
- [ ] Add high contrast and large text 130% accessibility scaling preset.
- [~] Add typing mechanical keyboard sound feedback simulation toggle.
      **Cut:** Novelty.

## M14: Notification Intelligence and Focus Ecosystem

- [/] Add scheduled Do Not Disturb / Focus Hours automation (e.g. night hours or calendar meetings).
      **Built:** quiet hours, a daily range (Settings → Screen Time & DND).
      **Missing:** calendar meetings.
- [/] Add granular per-application notification priority rules and channel filtering.
      **Built:** a per-app on/off for banners and sounds (Settings → Screen
      Time). **Missing:** priorities and channels.
- [ ] Add 7-day searchable notification history archive.
- [~] Add synchronized LRC song lyrics display in the expanded media player.
      **Cut:** Novelty.

## M15: The application suite

Separate programs, one design system: each app is its own binary and process,
built from the shared `Ui` module (toolbar capsules, sidebar, status bar,
menus, dialogs, buttons and fields), so a change to a control changes it
everywhere.

- [x] Files (`b1air-files`): own directory model, trash with restore, undo,
      drag and drop, volumes, Open With, details panel, archive extraction.
- [x] Git (`b1air-git`): changes, history, branches, commit and undo, in
      GitHub Desktop's layout.
- [x] Text (`b1air-text`), View (`b1air-view`), Notes (`b1air-notes`),
      Monitor (`b1air-monitor`), Camera (`b1air-camera`), Term (`b1air-term`).
- [x] One look across the suite and Settings: same toolbar, sidebar, status
      bar, button and field; contrast guarded against WCAG ratios whatever
      the palette.
- [x] A light theme: Catppuccin Latte, with the contrast guard taught that a
      light card sits lighter than its panel, and the terminal's colours.
- [/] Translation. `Ui/I18n` with JSON per language (qsTr cannot reach the
      shell, which runs inside quickshell), plural forms included; the
      smoke test checks every translation keeps its placeholders.
      **Built:** the apps in Russian; the apps and the whole shell in
      Ukrainian, with the language picked in Settings → Keyboard.
      **Missing:** the shell in Russian.
- [x] A CI job that builds the suite and runs `tools/smoke.sh` on every push
      (.github/workflows/build.yml, Ubuntu 26.04).
- [x] Files: compress to archive, batch rename (M11), and tabs.

