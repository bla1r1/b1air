pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// =============================================================================
// Sound Effects & Desktop Audio Feedback Service
// =============================================================================

Singleton {
    id: root

    /**
     * Play a freedesktop sound-theme event by name.
     *
     * Its four callers passed `SoundEffects.action` — a property this
     * singleton does not have — so every one of them handed in undefined,
     * failed the allow-list check below and played nothing. They were then
     * changed to pass the literal name "action", which is not an event in the
     * freedesktop sound naming spec and so has no file in any sound theme:
     * still silence, now with a plausible-looking call. They were four buttons
     * on one settings page, in a suite where no other button makes a noise, so
     * they are gone.
     *
     * The volume tick and the screenshot shutter are played by the daemon,
     * because that is where the volume keys and the capture actually run.
     * What is left for the shell is the device chime, which is only observable
     * from here.
     */
    function _play(soundName) {
        // The daemon finds the file in the sound theme and plays it with
        // pw-play (it was canberra-gtk-play, from GTK 3's libcanberra).
        Quickshell.execDetached(["b1air-daemon", "sound", soundName]);
    }

    /**
     * "Peripheral & Device Connect Chime" in Sound settings.
     *
     * The setting has existed since the page was written and nothing read it —
     * `soundDeviceFeedback` appeared in the schema, in the toggle, and nowhere
     * else. Services/Audio now calls this when a PipeWire sink or source turns
     * up, which is what a headset, a USB interface, a dock or a Bluetooth
     * audio device does when it connects.
     */
    function playDeviceConnected() {
        if (Settings.soundDeviceFeedback === false)
            return;
        root._play("device-added");
    }
}
