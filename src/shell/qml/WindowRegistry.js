.pragma library

// The scale everything on this desktop is measured in.
//
// It used to look at the width alone, against a 1920 reference. That reads a
// 2560x1080 ultrawide as a third larger than 1080p and sizes the bar, the
// popups and every panel accordingly — but the screen is exactly as tall as a
// 1080p one, so the desktop got taller chrome and less room for windows on the
// display that has the least of it. Any wide-and-short screen had the same
// problem: 3440x1440 came out at 1.34 when its height says 1.33.
//
// Both dimensions now, against 1920x1080, and the smaller of the two wins —
// the limiting dimension is the one that decides how much fits. On a screen
// with 16:9 proportions this changes nothing at all, which is most of them;
// the numbers only move where the aspect ratio is unusual, which is exactly
// where the old answer was wrong.
function getScale(mw, userScale, mh) {
    if (mw <= 0) return 1.0;

    let r = mw / 1920.0;
    // `mh` is optional so the older two-argument callers keep working; without
    // it the ratio is the width's, as before.
    if (mh !== undefined && mh > 0)
        r = Math.min(r, mh / 1080.0);

    let baseScale = 1.0;
    if (r <= 1.0) {
        baseScale = Math.max(0.35, Math.pow(r, 0.85));
    } else {
        baseScale = Math.pow(r, 0.5);
    }

    return baseScale * (userScale !== undefined ? userScale : 1.0);
}

function s(val, scale) {
    return Math.round(val * scale);
}

function getLayout(name, mx, my, mw, mh, userScale, barAtBottom) {
    let scale = getScale(mw, userScale, mh);

    // Popups that hang off the bar have to hang off whichever edge it is on.
    // Every one of them hard-coded 58px from the top, so moving the bar to the
    // bottom — which Settings offers — would have left them floating against
    // the opposite edge from the thing they belong to.
    const barEdge = barAtBottom ? s(12, scale) : s(58, scale);

    let base = {
        // One surface with pages. The four entries it replaces stay below so an
        // existing binding still opens the right page rather than breaking.
        // Top-right, under the bar — a Control Center is a corner panel, not a
        // window. 380x560 against the old 1120x780: it holds tiles, and detail
        // opens in the popup that already exists for it.
        // 700, not 580: the tile grid, the two sliders, the weather card and
        // the media card add up to roughly 690px, so at 580 the last card was
        // always half-cut against the bottom edge. It still scrolls when a
        // screen cannot spare the height.
        "control":       { w: s(390, scale), h: s(700, scale), rx: mw - s(410, scale), ry: barEdge, comp: "control/ControlCenter.qml" },
        "notifications": { w: s(390, scale), h: s(700, scale), rx: mw - s(410, scale), ry: barEdge, comp: "control/ControlCenter.qml" },
        "wifi":          { w: s(390, scale), h: s(700, scale), rx: mw - s(410, scale), ry: barEdge, comp: "control/ControlCenter.qml" },
        "bluetooth": { w: s(390, scale), h: s(700, scale), rx: mw - s(410, scale), ry: barEdge, comp: "control/ControlCenter.qml" },
        "sound":     { w: s(390, scale), h: s(700, scale), rx: mw - s(410, scale), ry: barEdge, comp: "control/ControlCenter.qml" },
        "power":     { w: s(390, scale), h: s(700, scale), rx: mw - s(410, scale), ry: barEdge, comp: "control/ControlCenter.qml" },
        "battery":   { w: s(390, scale), h: s(700, scale), rx: mw - s(410, scale), ry: barEdge, comp: "control/ControlCenter.qml" },
        "volume":    { w: s(390, scale), h: s(700, scale), rx: mw - s(410, scale), ry: barEdge, comp: "control/ControlCenter.qml" },
        "network":   { w: s(390, scale), h: s(700, scale), rx: mw - s(410, scale), ry: barEdge, comp: "control/ControlCenter.qml" },
        "calendar":  { w: s(860, scale), h: s(480, scale), rx: Math.floor((mw/2)-(s(860, scale)/2)), ry: barAtBottom ? s(28, scale) : s(75, scale), comp: "calendar/CalendarPopup.qml" },
        // 760: the cover block, the transport row, the ten EQ bands and the preset
        // buttons need about 730px, and at 620 the preset row was sliced in half
        // against the bottom edge with nothing on screen offering to scroll.
        // Centred like every other popup. It was pinned to the left edge at
        // x = 12, so the one window in the shell that opens in the corner was
        // the music player, with no reason for it.
        "music":     { w: s(700, scale), h: s(760, scale), rx: Math.floor((mw/2)-(s(700, scale)/2)), ry: barEdge, comp: "music/MusicPopup.qml" },
        "audioFull":  { w: s(980, scale), h: s(720, scale), rx: Math.floor((mw/2)-(s(980, scale)/2)), ry: barAtBottom ? s(24, scale) : s(70, scale), comp: "settings/SettingsApp.qml" },
        "powerFull":  { w: s(980, scale), h: s(720, scale), rx: Math.floor((mw/2)-(s(980, scale)/2)), ry: barAtBottom ? s(24, scale) : s(70, scale), comp: "settings/SettingsApp.qml" },
        "netFull":    { w: s(980, scale), h: s(720, scale), rx: Math.floor((mw/2)-(s(980, scale)/2)), ry: barAtBottom ? s(24, scale) : s(70, scale), comp: "settings/SettingsApp.qml" },
        "appearance": { w: s(980, scale), h: s(720, scale), rx: Math.floor((mw/2)-(s(980, scale)/2)), ry: barAtBottom ? s(24, scale) : s(70, scale), comp: "settings/SettingsApp.qml" },
        "nightlight": { w: s(980, scale), h: s(720, scale), rx: Math.floor((mw/2)-(s(980, scale)/2)), ry: barAtBottom ? s(24, scale) : s(70, scale), comp: "settings/SettingsApp.qml" },
        "input":      { w: s(980, scale), h: s(720, scale), rx: Math.floor((mw/2)-(s(980, scale)/2)), ry: barAtBottom ? s(24, scale) : s(70, scale), comp: "settings/SettingsApp.qml" },
        "wallpaper":     { w: s(980, scale), h: s(720, scale), rx: Math.floor((mw/2)-(s(980, scale)/2)), ry: barAtBottom ? s(24, scale) : s(70, scale), comp: "settings/SettingsApp.qml" },
        "clipboard":     { w: s(620, scale), h: s(520, scale), rx: Math.floor((mw/2)-(s(620, scale)/2)), ry: Math.floor((mh/2)-(s(520, scale)/2)), comp: "clipboard/ClipboardPopup.qml" },
        "mediaFull":     { w: s(700, scale), h: s(760, scale), rx: s(12, scale), ry: barEdge, comp: "music/MusicPopup.qml" },
        "stewart":   { w: s(800, scale), h: s(600, scale), rx: Math.floor((mw/2)-(s(800, scale)/2)), ry: Math.floor((mh/2)-(s(600, scale)/2)), comp: "stewart/stewart.qml" },
        "monitors":  { w: s(980, scale), h: s(720, scale), rx: Math.floor((mw/2)-(s(980, scale)/2)), ry: barAtBottom ? s(24, scale) : s(70, scale), comp: "settings/SettingsApp.qml" },
        "focustime": { w: s(900, scale), h: s(720, scale), rx: Math.floor((mw/2)-(s(900, scale)/2)), ry: Math.floor((mh/2)-(s(720, scale)/2)), comp: "focustime/FocusTimePopup.qml" },
        "guide":     { w: s(980, scale), h: s(720, scale), rx: Math.floor((mw/2)-(s(980, scale)/2)), ry: barAtBottom ? s(24, scale) : s(70, scale), comp: "settings/SettingsApp.qml" },
        "pollkit":   { w: s(520, scale), h: s(400, scale), rx: Math.floor((mw/2)-(s(520, scale)/2)), ry: Math.floor((mh/2)-(s(400, scale)/2)), comp: "pollkit/UpdaterPopup.qml" },
        "session":   { w: s(680, scale), h: s(280, scale), rx: Math.floor((mw/2)-(s(680, scale)/2)), ry: Math.floor((mh/2)-(s(280, scale)/2)), comp: "session/SessionMenu.qml" },
        "keyboard":  { w: s(250, scale), h: s(170, scale), rx: mw - s(330, scale), ry: barEdge, comp: "keyboard/KeyboardPopup.qml" },
        "spotlight": { w: s(660, scale), h: s(460, scale), rx: Math.floor((mw/2)-(s(660, scale)/2)), ry: Math.floor((mh/2)-(s(460, scale)/2)), comp: "launcher/SpotlightLauncher.qml" },
        "launchpad": { w: s(980, scale), h: s(640, scale), rx: Math.floor((mw/2)-(s(980, scale)/2)), ry: Math.floor((mh/2)-(s(640, scale)/2)), comp: "launcher/Launchpad.qml" },
        "launcher":  { w: s(980, scale), h: s(640, scale), rx: Math.floor((mw/2)-(s(980, scale)/2)), ry: Math.floor((mh/2)-(s(640, scale)/2)), comp: "launcher/Launchpad.qml" },
        "menu":      { w: s(980, scale), h: s(640, scale), rx: Math.floor((mw/2)-(s(980, scale)/2)), ry: Math.floor((mh/2)-(s(640, scale)/2)), comp: "launcher/Launchpad.qml" },
        "emoji":     { w: s(480, scale), h: s(440, scale), rx: Math.floor((mw/2)-(s(480, scale)/2)), ry: Math.floor((mh/2)-(s(440, scale)/2)), comp: "emoji/EmojiPickerPopup.qml" },
        "settings":  { w: s(980, scale), h: s(720, scale), rx: Math.floor((mw/2)-(s(980, scale)/2)), ry: barAtBottom ? s(24, scale) : s(70, scale), comp: "settings/SettingsApp.qml" },
        "zones":     { w: s(760, scale), h: s(520, scale), rx: Math.floor((mw/2)-(s(760, scale)/2)), ry: Math.floor((mh/2)-(s(520, scale)/2)), comp: "zones/FancyZonesOverlay.qml" },
        "ruler":     { w: s(820, scale), h: s(580, scale), rx: Math.floor((mw/2)-(s(820, scale)/2)), ry: Math.floor((mh/2)-(s(580, scale)/2)), comp: "ruler/ScreenRulerOverlay.qml" },
        "shelf":     { w: s(640, scale), h: s(480, scale), rx: mw - s(660, scale), ry: mh - s(510, scale), comp: "shelf/DropShelf.qml" },
        "quicklook": { w: s(780, scale), h: s(560, scale), rx: Math.floor((mw/2)-(s(780, scale)/2)), ry: Math.floor((mh/2)-(s(560, scale)/2)), comp: "quicklook/QuickLookPopup.qml" },
        "hidden":    { w: 1, h: 1, rx: -5000 - mx, ry: -5000 - my, comp: "" } 
    };

    if (!base[name]) return null;
    
    let t = base[name];
    t.x = mx + t.rx;
    t.y = my + t.ry;
    
    return t;
}

// Nothing calls this any more — the toasts size themselves from Design — but
// it takes the height for the same reason getLayout does, so that reviving it
// cannot quietly reintroduce the width-only scale.
function getPopupLayout(mw, userScale, mh) {
    let scale = getScale(mw, userScale, mh);
    return {
        w: s(350, scale),
        marginTop: s(70, scale),
        marginRight: s(20, scale),
        spacing: s(12, scale),
        radius: s(14, scale),
        padding: s(12, scale)
    };
}
