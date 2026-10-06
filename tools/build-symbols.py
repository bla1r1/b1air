#!/usr/bin/env python3
"""build-symbols.py — the desktop's icon font, "b1air Symbols".

The interface draws its icons as glyphs of JetBrainsMono Nerd Font Mono, by
codepoint ("\\u{f05a9}" is Wi-Fi) — a few hundred of them across the shell
and the apps, from half a dozen icon sets of different weights and sizes.
This builds a font with the same codepoints and the same advances, in which
each of those glyphs is redrawn with the Lucide icon of the same meaning:
one 2px stroke on one grid, the way a desktop's own symbol set is drawn.
Design.font.icon names it, so not one call site changes; a codepoint with no
Lucide match keeps its Nerd Font glyph.

    tools/build-symbols.py NERD.ttf LUCIDE.ttf LUCIDE-INFO.json GLYPHNAMES.json OUT.ttf

NERD.ttf          JetBrainsMonoNerdFontMono-Regular.ttf (ttf-jetbrains-mono-nerd)
LUCIDE.ttf/.json  lucide-static's font/lucide.ttf and font/info.json (ISC)
GLYPHNAMES.json   nerd-fonts' glyphnames.json: codepoint -> name
OUT.ttf           .local/share/fonts/b1air-symbols.ttf

Which codepoints: every one the source uses (\\u{…} escapes and literal
private-use characters in src/ and the SDDM theme), plus ASCII so a stray
digit beside an icon still renders. The name of each comes from
glyphnames.json ("md-wifi_strength_2"); its Lucide icon is the same name
("wifi") or the entry in SYNONYMS below.

Needs fontTools (pip install fonttools).
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

from fontTools.pens.transformPen import TransformPen
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.subset import Options, Subsetter
from fontTools.ttLib import TTFont

REPO = Path(__file__).resolve().parent.parent

# Nerd Font names whose Lucide icon is called something else.
SYNONYMS = {
    "pl-branch": "git-branch", "fa-magnifying_glass": "search", "fa-table_cells_large": "layout-grid",
    "fa-close": "x", "fa-trash_can": "trash-2", "fa-arrows_rotate": "refresh-cw", "fa-backward_step": "skip-back",
    "fa-forward_step": "skip-forward", "fa-remove_sign": "circle-x", "fa-eye_slash": "eye-off",
    "fa-arrows_h": "move-horizontal", "fa-cogs": "settings", "fa-arrow_right_from_bracket": "log-out",
    "fa-arrows_alt": "move", "fa-floppy_disk": "save", "fa-dashboard": "gauge", "fa-cloud_arrow_up": "cloud-upload",
    "fa-desktop": "monitor", "fa-question": "circle-help", "fa-microphone": "mic", "fa-microphone_slash": "mic-off",
    "fa-file_lines": "file-text", "fa-file_pdf": "file-text", "fa-file_archive_o": "file-archive",
    "fa-eye_dropper": "pipette", "fa-temperature_half": "thermometer",
    "oct-alert": "triangle-alert", "oct-diff_added": "diff", "oct-diff_removed": "square-minus",
    "oct-diff_modified": "square-dot", "oct-diff_renamed": "square-arrow-right",
    "md-account_circle": "circle-user", "md-alarm_multiple": "alarm-clock", "md-alert": "triangle-alert",
    "md-apps": "layout-grid", "md-arrow_down_bold_circle_outline": "circle-arrow-down",
    "md-arrow_down_drop_circle_outline": "circle-chevron-down",
    "md-battery_10": "battery-low", "md-battery_20": "battery-low", "md-battery_30": "battery-low",
    "md-battery_40": "battery-medium", "md-battery_50": "battery-medium", "md-battery_60": "battery-medium",
    "md-battery_70": "battery-full", "md-battery_80": "battery-full", "md-battery_90": "battery-full",
    "md-battery_alert": "battery-warning", "md-battery_outline": "battery",
    "md-bell_sleep": "bell-off", "md-bluetooth_audio": "bluetooth-connected", "md-brightness_6": "sun-medium",
    "md-brightness_7": "sun", "md-camera_iris": "aperture", "md-cart": "shopping-cart", "md-cellphone": "smartphone",
    "md-clipboard_outline": "clipboard", "md-clock_outline": "clock", "md-close": "x", "md-code_braces": "braces",
    "md-code_greater_than_or_equal": "scan", "md-comment_remove_outline": "message-square-x",
    "md-console": "square-terminal", "md-content_copy": "copy", "md-content_cut": "scissors",
    "md-content_paste": "clipboard-paste", "md-content_save": "save", "md-cursor_default_outline": "mouse-pointer-2",
    "md-desktop_mac": "monitor", "md-dots_vertical": "ellipsis-vertical", "md-drag": "grip-vertical",
    "md-ethernet": "ethernet-port", "md-file_document": "file-text", "md-file_outline": "file",
    "md-file_pdf_box": "file-text", "md-file_word": "file-type", "md-flash": "zap", "md-folder_outline": "folder",
    "md-format_list_bulleted": "list", "md-fullscreen_exit": "minimize", "md-git": "git-branch",
    "md-harddisk": "hard-drive", "md-help": "circle-help", "md-information": "info", "md-information_outline": "info",
    "md-lan": "network", "md-link_variant": "link", "md-magnify": "search", "md-map_marker": "map-pin",
    "md-memory": "memory-stick", "md-microphone": "mic", "md-microphone_off": "mic-off", "md-new_box": "badge-plus",
    "md-package_variant_closed": "package", "md-panorama": "image", "md-qrcode": "qr-code", "md-record": "circle-dot",
    "md-refresh": "refresh-cw", "md-replay": "rotate-ccw", "md-rotate_right": "rotate-cw", "md-security": "shield",
    "md-select_all": "square-dashed", "md-skip_next": "skip-forward", "md-skip_previous": "skip-back",
    "md-sleep": "moon", "md-speaker_off": "volume-x", "md-stop": "square", "md-swap_horizontal": "arrow-left-right",
    "md-sync": "refresh-cw", "md-timer_outline": "timer", "md-timer_off_outline": "timer-off",
    "md-timetable": "calendar-clock", "md-tooltip": "message-square", "md-vector_arrange_above": "layers",
    "md-view_grid": "layout-grid", "md-volume_high": "volume-2", "md-volume_low": "volume", "md-volume_medium": "volume-1",
    "md-weather_cloudy": "cloud", "md-weather_hail": "cloud-hail", "md-weather_lightning": "cloud-lightning",
    "md-weather_night": "moon", "md-weather_partly_cloudy": "cloud-sun", "md-weather_rainy": "cloud-rain",
    "md-weather_snowy": "cloud-snow", "md-weather_sunny": "sun", "md-weather_windy": "wind",
    "md-window_close": "x", "md-window_minimize": "minus", "md-wrap": "wrap-text", "md-zip_box": "file-archive",
    "md-translate": "languages", "md-delete_forever": "trash-2", "md-tune": "sliders-horizontal",
    "md-power_plug": "plug", "md-update": "refresh-ccw", "md-restart": "rotate-cw",
    "md-source_commit": "git-commit-horizontal", "md-volume_mute": "volume-x", "md-loading": "loader-circle",
    "md-home_alert": "house", "md-wifi_strength_1": "wifi-low", "md-wifi_strength_2": "wifi-low",
    "md-wifi_strength_3": "wifi", "md-wifi_strength_4": "wifi", "md-wifi_strength_off_outline": "wifi-off",
    "md-wifi_strength_outline": "wifi-zero", "md-pin_outline": "pin", "md-share_outline": "share",
    "md-trash_can": "trash-2", "md-trash_can_outline": "trash-2", "md-caps_lock": "arrow-big-up-dash",
    "md-application_settings": "app-window", "md-flag_remove": "flag-off", "md-folder_plus_outline": "folder-plus",
    "md-checkbox_multiple_outline": "list-checks", "md-playlist_music": "list-music", "md-check_bold": "check",
    "md-picture_in_picture_top_right": "picture-in-picture-2", "md-rectangle": "rectangle-horizontal",
    "md-auto_fix": "wand-sparkles", "md-chart_bar": "chart-column", "md-application": "app-window",
    "md-flip_horizontal": "flip-horizontal-2", "md-shield_lock": "lock-keyhole", "md-backup_restore": "database-backup",
    "md-theme_light_dark": "sun-moon",
    "md-account": "user", "md-speedometer": "gauge", "md-scale_balance": "scale",
    "md-gamepad_square": "gamepad-2",
    "md-view_column": "columns-3", "md-view_carousel": "gallery-horizontal",
}

# Lucide draws on a 1000-unit square from the baseline up, with a margin of
# 1/12 all round. A Nerd Font Mono icon's ink fills one 600-unit cell centred
# on y = 360 (md-wifi: 0..600, 109..611). At 0.72 Lucide's ink is that cell
# wide — at 0.6 the icons came out a fifth smaller than the ones they replace
# — and its 2-unit stroke lands at about 1.3 px at the 13 px of a body icon.
# (md-code_greater_than_or_equal is the source's "screen frame" glyph: the
# screenshot tile, the capture page, screen sharing — hence "scan".)
SCALE = 0.72
X_OFFSET = (600 - 1000 * SCALE) / 2
Y_OFFSET = 360 - 1000 * SCALE / 2


def used_codepoints() -> set[int]:
    found: set[int] = set()
    sources = [p for ext in ("qml", "js", "cpp", "hpp") for p in (REPO / "src").rglob(f"*.{ext}")
               if "third_party" not in p.parts and "build" not in p.parts]
    sources += list((REPO / "usr/share/sddm/themes/b1air").rglob("*.qml"))
    for path in sources:
        text = path.read_text(encoding="utf-8", errors="ignore")
        for hexcode in re.findall(r"\\u\{([0-9a-fA-F]{4,6})\}", text):
            if int(hexcode, 16) >= 0xE000:
                found.add(int(hexcode, 16))
        for ch in text:
            o = ord(ch)
            if 0xE000 <= o <= 0xF8FF or 0xF0000 <= o <= 0x10FFFF:
                found.add(o)
    return found


def main(argv: list[str]) -> int:
    if len(argv) != 6:
        print(__doc__)
        return 2
    nerd_path, lucide_path, info_path, names_path, out_path = argv[1:]
    nerd = TTFont(nerd_path)
    lucide = TTFont(lucide_path)
    info = json.loads(Path(info_path).read_text())
    lucide_cp = {name: int(v["encodedCode"].lstrip("\\"), 16) for name, v in info.items()}

    names: dict[int, str] = {}
    for name, v in json.loads(Path(names_path).read_text()).items():
        if isinstance(v, dict) and "code" in v:
            names.setdefault(int(v["code"], 16), name)

    used = used_codepoints()
    nerd_cmap = nerd.getBestCmap()
    lucide_cmap = lucide.getBestCmap()
    lucide_glyphs = lucide.getGlyphSet()
    glyf = nerd["glyf"]

    replaced, kept = [], []
    for cp in sorted(used):
        glyph_name = nerd_cmap.get(cp)
        nerd_name = names.get(cp, "")
        base = nerd_name.split("-", 1)[1].replace("_", "-") if "-" in nerd_name else nerd_name
        target = SYNONYMS.get(nerd_name) or (base if base in lucide_cp else None)
        if not glyph_name or not target or lucide_cp.get(target) not in lucide_cmap:
            kept.append(f"{cp:x} {nerd_name or '?'}")
            continue
        pen = TTGlyphPen(None)
        lucide_glyphs[lucide_cmap[lucide_cp[target]]].draw(
            TransformPen(pen, (SCALE, 0, 0, SCALE, X_OFFSET, Y_OFFSET)))
        new = pen.glyph()
        new.recalcBounds(glyf)
        glyf[glyph_name] = new
        replaced.append(f"{cp:x} {nerd_name} -> {target}")

    # Only what is used, and ASCII.
    keep = used | set(range(0x20, 0x7F))
    options = Options()
    options.hinting = False
    options.layout_features = []
    options.name_IDs = ["*"]
    subsetter = Subsetter(options)
    subsetter.populate(unicodes=sorted(keep))
    subsetter.subset(nerd)

    family = "b1air Symbols"
    for record in nerd["name"].names:
        if record.nameID in (1, 16):
            record.string = family
        elif record.nameID in (4,):
            record.string = family + " Regular"
        elif record.nameID == 6:
            record.string = "b1airSymbols-Regular"
        elif record.nameID in (2, 17):
            record.string = "Regular"
    nerd.save(out_path)
    print(f"{len(replaced)} redrawn from Lucide, {len(kept)} kept from Nerd Font -> {out_path}")
    for line in kept:
        print("  kept", line)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
