# `b1air-daemon` from the command line

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
b1air-daemon lock                  # Lock screen immediately (b1air-lock); --wait blocks until opened
b1air-daemon fingerprint status    # The reader and the saved fingers (JSON)
b1air-daemon fingerprint login on  # Fingerprint at the login screen (as root: edits /etc/pam.d/sddm only)
b1air-daemon game-mode toggle      # Switch between power-save and low-latency mode
```
