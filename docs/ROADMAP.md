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

1. **Dock/undock display profiles** (M7) — this is a ThinkPad that meets
   external monitors, and today every plug-in means a trip to Settings.
   Fractional scaling, the other half of the old item, is built.
2. **External monitor brightness** (M7) — the daemon already speaks DDC/CI
   (`ddcutil` detect, get and set are in `system_control.cpp`, used for idle
   dimming); what is missing is a slider. Cheapest item on the list.
3. **Drop-down terminal** (M9) — small, and used every day. `b1air-term`
   exists; this is a scratchpad rule and a key.
4. **Scheduled Do Not Disturb** (M14) — the focus timer it belongs to is built.
5. **Trash auto-purge and archive compression** (M11) — the Files app now owns
   the trash (move, restore, empty) and extracts archives through libarchive;
   both halves are small additions to code that exists.
6. **Remote session indicator and Control Center tile** (M5) — the WayVNC
   backend is done; this is the missing front.
7. **Four-finger overview gesture** (M8) — three-finger workspace swipe is
   built; the overview is what is left.
8. **Per-workspace and per-monitor wallpaper** (M7) — cheap and visible.

The keyboard shortcut editor that was sixth here is built: Keyboard →
Desktop shortcuts rebinds a key in place, unbinding the old one.

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
- [ ] Add Remote Desktop quick-toggle tile in Control Center with active client connection count badge.
- [x] Add Remote Desktop & Screen Sharing section in Settings App (`Super+Shift+S`) with port configuration, password management, and prompt-free permissions.
- [ ] Add an active remote session indicator to the bar's system island, with a 1-click disconnect.
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
- [ ] Add Display Profile automatic switching on dock/undock events for HDMI/Type-C displays.
- [/] Add external monitor hardware brightness control via DDC/CI in Control Center slider.
      **Built:** the daemon's DDC/CI detect, read and write, used today to dim
      external screens on idle. **Missing:** the slider.
- [ ] Add ICC/ICM color profile calibration importer in Display Settings.
- [ ] Add distinct per-workspace and per-monitor wallpaper assignment engine.
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
      **Built:** three-finger swipe between workspaces, with a direction
      switch, as `bindgesture` (Settings → Mouse & Touchpad). **Missing:**
      four-finger overview, and 1:1 tracking — sway's gestures fire on
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

- [ ] Add drop-down sliding Quake terminal (`F12` / `Super+~`) persistent across all workspaces.
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

- [ ] Add batch file renamer utility (`Super+Shift+R`) with regex, numbering, and case transformation.
- [~] Add interactive disk space sunburst / treemap visualizer in Settings.
      **Cut:** `ncdu` and `baobab`.
- [~] Add file checksum hash calculator and clipboard verifier (MD5, SHA256).
      **Cut:** `sha256sum` and `sha256sum -c`.
- [/] Add native archive compression and extraction for `.zip`, `.tar.gz`, `.tar.zst`, and `.7z`.
      **Built:** extraction in Files through libarchive — double-click an
      archive, refusing entries that would escape the target folder.
      **Missing:** compression.
- [/] Add scheduled Trash auto-purge (>30 days) and 1-click deleted file restore.
      **Built:** restore, in Files' Trash view, to the original place.
      **Missing:** the purge.

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

- [ ] Add scheduled Do Not Disturb / Focus Hours automation (e.g. night hours or calendar meetings).
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
- [ ] A light theme. Both built-in themes are dark, and the contrast guard has
      only ever been looked at against dark surfaces.
- [ ] Translation. No string goes through `qsTr`; the desktop is English-only.
- [ ] A CI job that builds the suite and runs `tools/smoke.sh` on every push.
      There is none, and the smoke test is what caught the daemon failing on a
      fresh account.
- [ ] Files: compress to archive, batch rename (M11), and tabs.

