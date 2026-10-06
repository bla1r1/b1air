import QtQuick
import "../Ui"

// Every page of Settings: its id, icon, name, one line on what it holds, and
// the words it is found by. One list for the Settings rail and for Spotlight,
// which finds a page by these and opens it ("wifi" -> Network & Wi-Fi).
QtObject {
    readonly property var list: [
        { isHeader: true, label: I18n.tr("CONNECTIONS") },
        { id: "network",     icon: "\u{f0928}", label: I18n.tr("Network & Wi-Fi"), desc: I18n.tr("Wi-Fi, wired connections and VPNs"),  color: Design.lavender, tags: "wifi internet connection ethernet ssid ip address vpn network" },
        { id: "bluetooth",   icon: "\u{f00af}", label: I18n.tr("Bluetooth"), desc: I18n.tr("Pair and connect headphones, mice, keyboards and controllers"),        color: Design.mauve,    tags: "bluetooth bt pair devices headset connect mouse keyboard controller" },
        { id: "remote",      icon: "\u{f0379}", label: I18n.tr("Remote Desktop"), desc: I18n.tr("Let another computer see or control this one"),   color: Design.blue,     tags: "remote desktop vnc rdp ssh anydesk screen sharing wayvnc" },
        { isHeader: true, label: I18n.tr("DEVICES") },
        { id: "monitors",    icon: "\u{f0379}", label: I18n.tr("Displays"), desc: I18n.tr("Resolution, refresh rate, scaling, brightness and arrangement of your screens"),         color: Design.sapphire, tags: "display resolution refresh rate scaling monitor screen mirror hdr brightness backlight ddc" },
        { id: "audio",       icon: "\u{f057e}", label: I18n.tr("Sound & Volume"), desc: I18n.tr("Output and input devices, volumes and per-app levels"),   color: Design.teal,     tags: "sound volume sink source mic microphone devices wireplumber equalizer audio output input" },
        { id: "power",       icon: "\u{f0084}", label: I18n.tr("Power & Battery"), desc: I18n.tr("Power profile, battery charging and when the screen sleeps"),  color: Design.green,    tags: "battery sleep suspend hibernate timeout charge energy power lid button profile" },
        { id: "keyboard",    icon: "\u{f030c}", label: I18n.tr("Keyboard"), desc: I18n.tr("Input layouts and switching between them"),         color: Design.peach,    tags: "keyboard layout switch xkb input sources alt shift caps" },
        { id: "input",       icon: "\u{f0523}", label: I18n.tr("Mouse & Touchpad"), desc: I18n.tr("Pointer speed, scrolling and touchpad gestures"), color: Design.peach,    tags: "mouse touchpad sensitivity scroll tap acceleration natural pointer click magic apple gestures swipe" },
        { isHeader: true, label: I18n.tr("PERSONALIZATION") },
        { id: "appearance",  icon: "\u{f0765}", label: I18n.tr("Appearance"), desc: I18n.tr("The theme, the accent colour, and how other apps follow them"),       color: Design.mauve,    tags: "theme themes palette colours colors breeze adwaita dark light accent color gtk qt apps import export create custom wallpaper" },
        { id: "wallpaper",   icon: "\u{f02ca}", label: I18n.tr("Wallpaper"), desc: I18n.tr("The picture behind your windows and on the login screen"),        color: Design.pink,     tags: "background wallpaper pictures desktop image slideshow photos" },
        { id: "bar",         icon: "\u{f07e}",  label: I18n.tr("Top Bar"), desc: I18n.tr("What the bar and the Control Center show, the clock, and the weather"), color: Design.blue,     tags: "weather temperature forecast city control center tiles cards top bar panel modules widgets islands tray weather media stats icons workspaces clock 24 hour monitors show hide" },
        { id: "windows",     icon: "\u{f0379}", label: I18n.tr("Windows"), desc: I18n.tr("Tiling, gaps, borders, effects, unfocused windows and workspaces"),    color: Design.sapphire, tags: "gaps border padding tiling sway layout inner outer smart borders smart gaps autotiling dwindle split hyprland spiral blur shadows corners rounded effects dim inactive opacity transparency unfocused special workspace scratchpad overview expose" },
        { id: "animations",  icon: "\u{f0e1e}", label: I18n.tr("Animations"), desc: I18n.tr("How windows and workspaces move, and how fast"), color: Design.mauve, tags: "animation animations motion slide fade popin duration speed swipe hyprland" },
        { id: "nightlight",  icon: "\u{f0599}", label: I18n.tr("Night Light"), desc: I18n.tr("Warmer screen colours at night, and how warm"),      color: Design.yellow,   tags: "night light blue light temperature schedule eye protect" },
        { isHeader: true, label: I18n.tr("APPS") },
        { id: "defaultapps", icon: "\u{f0ac}",  label: I18n.tr("Default Apps"), desc: I18n.tr("Which app opens links, folders, text and media"),     color: Design.teal,     tags: "default applications browser terminal file manager editor mime types" },
        { id: "startup",     icon: "\u{f0459}", label: I18n.tr("Startup Apps"), desc: I18n.tr("Apps that start when you log in"),     color: Design.yellow,   tags: "startup autostart boot launch apps systemd login" },
        { id: "notifications", icon: "\u{f009a}", label: I18n.tr("Notifications"), desc: I18n.tr("Which apps may show banners and sounds, and quiet hours"), color: Design.teal, tags: "notifications banners popups sounds apps filters dnd do not disturb quiet hours night silence" },
        { id: "capture",     icon: "\u{f016d}", label: I18n.tr("Screenshots"), desc: I18n.tr("Where screenshots and recordings go, and how they are taken"),      color: Design.pink,     tags: "screenshot capture grim slurp record screen area video gif" },
        { id: "gamemode",    icon: "\u{f11b}",  label: I18n.tr("Game Mode"), desc: I18n.tr("One switch for less latency and fewer effects while playing"),        color: Design.red,      tags: "game mode performance vr fstrim process priority latency boost" },
        { isHeader: true, label: I18n.tr("TIME & FOCUS") },
        { id: "focus",       icon: "\u{f051e}", label: I18n.tr("Screen Time & Focus"), desc: I18n.tr("Screen time today, focus and break intervals, reminders"),color: Design.teal,     tags: "screen time timer focus pomodoro analytics breaks reminders eye care dnd" },
        { isHeader: true, label: I18n.tr("SYSTEM") },
        { id: "region",      icon: "\u{f05ca}", label: I18n.tr("Language & Region"), desc: I18n.tr("The interface language, the system's language, and the formats of dates and numbers"), color: Design.blue, tags: "language interface translation locale lang system region formats date time number currency units measurement" },
        { id: "user",        icon: "\u{f007}",  label: I18n.tr("User Profile"), desc: I18n.tr("Your name, picture and login shell"),     color: Design.mauve,    tags: "user profile avatar name username password account hostname fingerprint fprint" },
        { id: "lock",        icon: "\u{f033e}", label: I18n.tr("Lock & Login"), desc: I18n.tr("When the screen locks, the fingerprint, and the login screen"), color: Design.blue, tags: "lock screen login sddm greeter fingerprint fprint unlock session password sleep" },
        { id: "privacy",     icon: "\u{f0483}", label: I18n.tr("Privacy"), desc: I18n.tr("Screen time, clipboard history, trash and locations: what is kept, and wiping it"), color: Design.green, tags: "privacy screen time history clipboard trash delete forget location camera microphone record" },
        { id: "shortcuts",   icon: "\u{f11c}",  label: I18n.tr("Shortcuts"), desc: I18n.tr("Every key binding, and changing them"),        color: Design.sapphire, tags: "shortcuts keybinds keys hotkeys sway bindings commands remap change rebind" },
        { id: "updates",     icon: "\u{f06b0}", label: I18n.tr("Updates"), desc: I18n.tr("Updates for this desktop and the system packages"), color: Design.green, tags: "updates update upgrade packages pacman apt dnf zypper kernel dotfiles git pull" },
        { id: "maintenance", icon: "\u{f0187}", label: I18n.tr("Storage & Backup"), desc: I18n.tr("Backups, cleanup, restore points, vaults, and resetting the desktop"),      color: Design.green,    tags: "maintenance clean disk cache logs cleanup packages pacman apt dnf zypper trim system" },
        { id: "about",       icon: "\u{f035b}", label: I18n.tr("About System"), desc: I18n.tr("This computer, this desktop, and the services behind it"),     color: Design.mauve,    tags: "about system version kernel arch sway quickshell specs hardware cpu ram" }
    ]
}
