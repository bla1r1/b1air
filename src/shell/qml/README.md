# Quickshell Architecture & Directory Layout

This directory contains the unified Wayland native desktop shell for the DotsFiles configuration, powered by [Quickshell](https://outfoxxed.me/quickshell/).

---

## 🏛️ Layered Architecture Overview

```text
┌────────────────────────────────────────────────────────────────────────┐
│                        SHELL LAYER & IPC ROUTER                        │
│             Main.qml • WindowRegistry.js • Screenshot                  │
└───────────────────────────────────┬────────────────────────────────────┘
                                    │
        ┌───────────────────────────┴───────────────────────────┐
        ▼                                                       ▼
┌───────────────────────────────┐               ┌───────────────────────────────┐
│     VIEWS & POPUPS LAYER      │               │       FULL SETTINGS APP       │
│ • ControlCenter  • Calendar   │               │ • SettingsApp.qml             │
│ • Clipboard      • Music      │               │ • 15 modular category sections│
│ • FocusTime      • Toasts     │               │   (Network, Sound, About...)  │
└───────────────┬───────────────┘               └───────────────┬───────────────┘
                │                                               │
                └───────────────────────┬───────────────────────┘
                                        ▼
┌────────────────────────────────────────────────────────────────────────┐
│                        DESIGN SYSTEM LAYER (Ui/)                       │
│  Design tokens • PopupShell • Cards • Buttons • Sliders • Toggles...   │
└───────────────────────────────────────┬────────────────────────────────┘
                                        │
                                        ▼
┌────────────────────────────────────────────────────────────────────────┐
│                         SERVICES LAYER (Services/)                     │
│  Audio (PipeWire) • Network (NM) • Notifications • Clipboard • Power   │
└────────────────────────────────────────────────────────────────────────┘
```

---

## 📂 Directory Layout & Responsibilities

### 1. Root Orchestrators
- **`Main.qml`**: Central window manager process. Listens to Sway IPC commands, manages smooth layer morphing animations, and loads widgets dynamically.
- **`WindowRegistry.js`**: Declarative routing table defining exact geometry, scaling factors, screen alignment, and target QML components.

---

### 2. Design System (`Ui/`)
Exported via `Ui/qmldir` for atomic, consistent UI across all widgets.
- **`Design.qml`**: Semantic tokens for colors, typography, border radii, spacing, and animation easing.
- **`PopupShell.qml`**: Base container with window chrome, backdrop blur, and enter/exit transitions.
- **`Card.qml` / `Tile.qml`**: Structured content grouping cards and interactive grid tiles.
- **`Button.qml` / `ActionButton.qml` / `IconButton.qml`**: Unified button hierarchy.
- **`Toggle.qml` / `Switch.qml`**: Binary toggle controls.
- **`Slider.qml` / `Stepper.qml`**: Continuous and stepped value adjusters.
- **`Field.qml` / `Label.qml` / `SectionLabel.qml`**: Text inputs, labels, and mono section captions.
- **`Pill.qml` / `Badge.qml` / `DeviceRow.qml` / `EmptyState.qml`**: Layout helpers and state indicators.

---

### 3. Core Services (`Services/`)
Global singletons managing D-Bus protocols, daemons, and system integration.
- **`Audio.qml`**: PipeWire integration (sinks, sources, per-application stream volumes).
- **`Network.qml`**: NetworkManager D-Bus (Wi-Fi scan, connection states, Ethernet IPv4/DHCP).
- **`Notifications.qml`**: Native `org.freedesktop.Notifications` server with DND and history.
- **`Clipboard.qml`**: Wayland clipboard listener (`b1air-clip watch`), auto-typing detection, search, and persistence.
- **`Power.qml`**: UPower battery monitoring, system uptime, and power state actions.
- **`Media.qml`**: MPRIS2 player controller (playback, metadata, volume).
- **`Monitors.qml`**: Display outputs, modes, scaling, and positioning.
- **`Settings.qml`**: Persistent key-value storage (`~/.config/sway/settings.json`).

---

### 4. Control Center (`control/`)
Fast access menu positioned at the top-right under the Waybar:
- **`ControlCenter.qml`**: Master panel with dynamic tile grid (Wi-Fi, Bluetooth, Focus, Night Light, Power), volume & brightness sliders, mini media player, and power buttons.
- **`WifiMiniView.qml`**: Quick Wi-Fi connection with inline password prompt.
- **`BluetoothMiniView.qml`**: Device pairing and connect/disconnect.
- **`SoundMiniView.qml`**: Output device selector.
- **`NotificationsMiniView.qml`**: Notification history list with DND toggle.
- **`PowerMiniView.qml`**: Quick session actions (Lock, Sleep, Reboot, Power Off).

---

### 5. Settings App (`settings/`)
Desktop settings suite (`$mod+shift+s`):
- **`SettingsApp.qml`**: Master window with category rail navigation.
- **`components/`**: 15 modular category sub-views:
  - `AppearanceSettingsSection.qml`: Themes, dark mode, and accents.
  - `MonitorSettingsSection.qml`: Resolution, refresh rate, and display layout.
  - `NightLightSettingsSection.qml`: Warm temperature schedule and manual toggle.
  - `NetworkSettingsSection.qml`: Ethernet IPv4 configuration (Static / DHCP).
  - `BluetoothSettingsSection.qml`: Paired device management.
  - `AudioSettingsSection.qml`: Per-app volume mixer and audio profiles.
  - `PowerSettingsSection.qml`: Sleep timeouts, idle lock, and battery saver.
  - `FocusSettingsSection.qml`: Screen time tracking, Pomodoro intervals, daily goals.
  - `InputSettingsSection.qml`: Mouse sensitivity, touchpad gestures, natural scrolling.
  - `KeyboardSettingsSection.qml`: Keyboard layouts and live shortcut rebinding.
  - `WallpaperSettingsSection.qml`: Wallpaper gallery with live preview.
  - `StartupSettingsSection.qml`: Autostart application manager.
  - `WeatherSettingsSection.qml`: Weather provider, city, and units.
  - `AboutSettingsSection.qml`: System specifications, service health, and diagnostics.

---

### 6. Popups & Overlays
- **`clipboard/ClipboardPopup.qml`**: Clipboard history popup (`$mod+v`).
- **`notifications/NotificationToasts.qml`**: Top-right desktop toast notifications.
- **`calendar/CalendarPopup.qml`**: Monthly calendar, agenda, and weather.
- **`music/MusicPopup.qml`**: Expanded music player with 10-band equalizer.
- **`focustime/FocusTimePopup.qml`**: Pomodoro productivity timer (`$mod+shift+t`).
- **`updater/UpdaterPopup.qml`**: System & dotfiles package update status.
