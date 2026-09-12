#!/usr/bin/env python3
"""Build the b1air cursor theme from the SVGs in this directory.

    python3 src/cursors/build.py            # writes .local/share/icons/b1air-cursors

Each SVG is drawn on a 32x32 canvas; `HOTSPOTS` says where on that canvas the
pointer's point is. The Xcursor files are written here directly (the format is
a header, a table of contents and ARGB images) because xcursorgen is not
installed on this desktop. Needs rsvg-convert and ImageMagick's `magick`.
Edit an SVG and run this again; `make -C src install` installs the result.
"""
import os, struct, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(ROOT, ".local/share/icons/b1air-cursors")
SIZES = [24, 32, 48, 64]

HOTSPOTS = {  # on the 32x32 canvas
    "default": (5, 3), "pointer": (13, 3), "text": (16, 16), "crosshair": (16, 16),
    "wait": (16, 16), "progress": (5, 3), "not-allowed": (16, 16), "grab": (16, 14),
    "grabbing": (16, 16), "move": (16, 16), "ns-resize": (16, 16), "ew-resize": (16, 16),
    "nwse-resize": (16, 16), "nesw-resize": (16, 16), "help": (5, 3),
}

# Every name applications ask for, pointed at one of the drawings above.
ALIASES = {
    "default": ["left_ptr", "arrow", "top_left_arrow", "context-menu", "copy", "alias",
                "dnd-ask", "dnd-move", "dnd-link", "dnd-copy", "dnd-none", "no-drop",
                "zoom-in", "zoom-out", "vertical-text"],
    "pointer": ["hand1", "hand2", "pointing_hand"],
    "text": ["xterm", "ibeam"],
    "crosshair": ["cross", "tcross", "cross_reverse", "diamond_cross", "cell"],
    "wait": ["watch"],
    "progress": ["left_ptr_watch", "half-busy"],
    "not-allowed": ["X_cursor", "forbidden", "crossed_circle", "circle"],
    "grab": ["openhand"],
    "grabbing": ["closedhand", "dnd-none-grab"],
    "move": ["fleur", "all-scroll", "all-resize", "size_all"],
    "ns-resize": ["n-resize", "s-resize", "row-resize", "sb_v_double_arrow", "v_double_arrow",
                  "top_side", "bottom_side", "size_ver", "split_v"],
    "ew-resize": ["e-resize", "w-resize", "col-resize", "sb_h_double_arrow", "h_double_arrow",
                  "left_side", "right_side", "size_hor", "split_h"],
    "nwse-resize": ["nw-resize", "se-resize", "top_left_corner", "bottom_right_corner",
                    "bd_double_arrow", "size_fdiag"],
    "nesw-resize": ["ne-resize", "sw-resize", "top_right_corner", "bottom_left_corner",
                    "fd_double_arrow", "size_bdiag"],
    "help": ["question_arrow", "whats_this", "left_ptr_help"],
}

def image(svg, size):
    png = subprocess.run(["rsvg-convert", "-w", str(size), "-h", str(size), svg],
                         check=True, capture_output=True).stdout
    raw = subprocess.run(["magick", "png:-", "-depth", "8", "RGBA:-"], input=png,
                         check=True, capture_output=True).stdout
    px = []
    for i in range(0, len(raw), 4):
        r, g, b, a = raw[i:i + 4]
        # Xcursor pixels are premultiplied ARGB.
        px.append((a << 24) | ((r * a // 255) << 16) | ((g * a // 255) << 8) | (b * a // 255))
    return px

def xcursor(name):
    svg = os.path.join(HERE, name + ".svg")
    hx, hy = HOTSPOTS[name]
    chunks = []
    for s in SIZES:
        px = image(svg, s)
        head = struct.pack("<9I", 36, 0xFFFD0002, s, 1, s, s,
                           round(hx * s / 32), round(hy * s / 32), 0)
        chunks.append((s, head + struct.pack("<%dI" % len(px), *px)))
    ntoc = len(chunks)
    pos = 16 + ntoc * 12
    toc, body = b"", b""
    for s, data in chunks:
        toc += struct.pack("<3I", 0xFFFD0002, s, pos + len(body))
        body += data
    return b"Xcur" + struct.pack("<3I", 16, 0x10000, ntoc) + toc + body

def main():
    cur = os.path.join(OUT, "cursors")
    os.makedirs(cur, exist_ok=True)
    for f in os.listdir(cur):
        os.unlink(os.path.join(cur, f))
    for name in HOTSPOTS:
        with open(os.path.join(cur, name), "wb") as f:
            f.write(xcursor(name))
        for alias in ALIASES.get(name, []):
            os.symlink(name, os.path.join(cur, alias))
    with open(os.path.join(OUT, "index.theme"), "w") as f:
        f.write("[Icon Theme]\nName=b1air\nComment=b1air desktop cursors (src/cursors)\n"
                "Inherits=Adwaita\n")
    print("wrote", len(HOTSPOTS), "cursors and", sum(map(len, ALIASES.values())), "aliases to", OUT)

if __name__ == "__main__":
    sys.exit(main())
