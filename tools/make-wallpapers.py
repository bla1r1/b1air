#!/usr/bin/env python3
"""make-wallpapers.py — b1air's wallpapers, drawn rather than collected.

    tools/make-wallpapers.py [OUTDIR] [--size WxH] [--only NAME...]

Every picture in .wallpapers/ but the public-domain painting in Art/ comes
from this script: skies with clouds, ranges of hills in haze, forests in
fog, the sea and lakes, and soft gradients. Each is drawn from a fixed seed,
so running it again gives the same files, at any size (default 3840x2160).
Nothing in it is anyone else's; the pictures are the project's, under its
licence, GPL-2.0-only — this script being their source — and each file says
so in its EXIF (Artist, Copyright).

Needs python3 with numpy and Pillow.
"""
import argparse
import math
import os
import sys

import numpy as np
from PIL import Image

# ── Noise ────────────────────────────────────────────────────────────────────
#
# Smooth noise is random numbers on a coarse grid, drawn up with a bicubic
# filter; fractal noise is several of those, each twice as fine and half as
# strong. Plain, fast, and enough for clouds, ridges and water.


def grid_noise(rng, w, h, cells_x, cells_y):
    small = rng.random((max(2, cells_y), max(2, cells_x))).astype(np.float32)
    img = Image.fromarray(small, mode="F").resize((w, h), Image.BICUBIC)
    return np.asarray(img, dtype=np.float32)


def fbm(rng, w, h, cells, octaves=5, gain=0.5, stretch=1.0):
    """Fractal noise in 0..1; `stretch` > 1 draws it out sideways."""
    total = np.zeros((h, w), np.float32)
    amp, norm = 1.0, 0.0
    cx, cy = cells, max(2, int(cells * stretch * h / w))
    for _ in range(octaves):
        total += amp * grid_noise(rng, w, h, cx + 1, cy + 1)
        norm += amp
        amp *= gain
        cx, cy = cx * 2, cy * 2
    return total / norm


def ridge_line(rng, w, points, octaves=6, sharp=True):
    """A skyline in 0..1 along x: fractal 1-D noise, ridged for peaks."""
    x = np.linspace(0, 1, w, dtype=np.float32)
    total = np.zeros(w, np.float32)
    amp, norm, n = 1.0, 0.0, points
    for _ in range(octaves):
        knots = rng.random(n + 1).astype(np.float32)
        xs = np.linspace(0, 1, n + 1)
        # cosine interpolation between knots
        t = x * n
        i = np.minimum(t.astype(int), n - 1)
        f = (1 - np.cos((t - i) * math.pi)) / 2
        v = knots[i] * (1 - f) + knots[i + 1] * f
        if sharp:
            v = 1 - np.abs(v * 2 - 1)
        total += amp * v
        norm += amp
        amp *= 0.48
        n *= 2
    return total / norm


# ── Colour ───────────────────────────────────────────────────────────────────


def rgb(hexstr):
    hexstr = hexstr.lstrip("#")
    return np.array([int(hexstr[i:i + 2], 16) for i in (0, 2, 4)], np.float32) / 255.0


def mix(a, b, t):
    t = np.asarray(t, np.float32)
    return a * (1 - t[..., None]) + b * t[..., None] if t.ndim else a * (1 - t) + b * t


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def vertical(h, w, stops):
    """A gradient down the picture through (position, colour) stops."""
    y = np.linspace(0, 1, h, dtype=np.float32)
    out = np.zeros((h, 3), np.float32)
    pos = [p for p, _ in stops]
    for c in range(3):
        out[:, c] = np.interp(y, pos, [col[c] for _, col in stops])
    return np.repeat(out[:, None, :], w, axis=1)


def glow(w, h, cx, cy, radius, power=2.0):
    """1 at (cx, cy), falling off over `radius` (fractions of the width)."""
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    d = np.hypot(x / w - cx, (y / w) - cy * h / w) / radius
    return np.exp(-d ** power)


def over(img, colour, alpha):
    a = np.clip(alpha, 0, 1)[..., None]
    return img * (1 - a) + colour * a


def finish(img, rng):
    """A trace of grain, so long gradients do not band."""
    img = img + (rng.random(img.shape[:2], dtype=np.float32)[..., None] - 0.5) / 255.0 * 1.5
    return Image.fromarray((np.clip(img, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB")


# ── Skies ────────────────────────────────────────────────────────────────────


def sky(w, h, rng, top, horizon, cloud_lit, cloud_shade, cover, sun=None, stars=False):
    img = vertical(h, w, [(0, top), (1, horizon)])
    if sun is not None:
        sx, sy, scol = sun
        img = over(img, scol, 0.55 * glow(w, h, sx, sy, 0.45, 1.4))
        img = over(img, scol, 0.9 * glow(w, h, sx, sy, 0.05, 2.0))
    if stars:
        n = rng.random((h, w), dtype=np.float32)
        s = smoothstep(0.9993, 1.0, n) * smoothstep(1.0, 0.35, np.linspace(0, 1, h))[:, None]
        img = over(img, rgb("#ffffff"), s)
    # Clouds: fractal noise drawn out sideways, flatter and denser toward the
    # horizon, lit from above (the noise a little higher up, subtracted).
    yy = np.linspace(0, 1, h, dtype=np.float32)[:, None]
    n = fbm(rng, w, h, 3, 7, 0.52, stretch=2.2)
    thr = 0.62 - cover * 0.35
    density = smoothstep(thr, thr + 0.22, n) * (0.45 + 0.55 * yy)
    # Lit on top, in shade underneath: compare with the noise a little lower.
    shift = max(1, h // 60)
    lit = np.clip((n - np.roll(n, -shift, axis=0)) * 14 + 0.55, 0, 1)
    colour = mix(cloud_shade, cloud_lit, lit)
    return over(img, colour, density * 0.95)


# ── Land ─────────────────────────────────────────────────────────────────────


def ranges(img, rng, layers, far, near, haze, top=0.45, bottom=0.92, height=0.22,
           points=3, trees=False, mist=0.55, snow=None):
    """Ranges of hills, far to near: each one lower and darker, with haze
    rising off its foot."""
    h, w = img.shape[:2]
    yy = np.arange(h, dtype=np.float32)[:, None]
    for i in range(layers):
        t = i / max(1, layers - 1)                    # 0 far … 1 near
        base = (top + (bottom - top) * t) * h
        amp = height * h * (0.6 + 0.6 * t)
        line = ridge_line(rng, w, points + i, sharp=not trees)
        crest = base - line * amp
        if trees:
            crest = crest - tree_line(rng, w, (0.010 + 0.030 * t) * h, 50 + int(140 * (1 - t)))
        colour = mix(far, near, t ** 0.8)
        inside = smoothstep(crest[None, :] - 1.0, crest[None, :] + 1.0, yy)
        # Haze pooling at the foot of every range: level across, so it reads
        # as mist in the valley, not as streaks down each slope.
        fog = mist * (1 - t * 0.8) * smoothstep(base - 0.7 * amp, base + 0.06 * h, yy)
        layer = mix(colour, haze, np.broadcast_to(fog * 0.65, (h, w)))
        if snow is not None:   # white on the tops
            # Deeper on the high peaks, none on the low saddles, ragged.
            rag = ridge_line(rng, w, 120, octaves=4, sharp=False)
            high = smoothstep(0.45, 0.95, (base - crest) / amp)
            line_y = crest + amp * 0.32 * high * (0.55 + 0.9 * rag)
            cap = smoothstep(line_y[None, :] + 0.0015 * h, line_y[None, :] - 0.0015 * h, yy)
            layer = mix(layer, snow, cap * (1 - 0.35 * t))
        img = img * (1 - inside[..., None]) + layer * inside[..., None]
    return img


def tree_line(rng, w, size, count):
    """Spruce tops along a skyline: narrow triangles, uneven heights."""
    x = np.arange(w, dtype=np.float32)
    out = np.zeros(w, np.float32)
    for _ in range(count * 3):
        cx = rng.random() * w
        hgt = size * (0.5 + rng.random())
        half = hgt * (0.18 + 0.08 * rng.random())
        out = np.maximum(out, hgt - np.abs(x - cx) * hgt / half)
    return out


def water(img, rng, horizon, deep, shallow, sky_ref=0.35, sun_x=None, sun_col=None, mirror=False):
    """Water below `horizon`: its colour, a share of the sky, and ripples; the
    land above mirrored when `mirror` is set."""
    h, w = img.shape[:2]
    hy = int(horizon * h)
    rows = h - hy
    t = np.linspace(0, 1, rows, dtype=np.float32)[:, None]
    base = mix(np.broadcast_to(shallow, (rows, w, 3)), np.broadcast_to(deep, (rows, w, 3)),
               np.broadcast_to(t, (rows, w)))
    src = img[max(0, hy - rows):hy][::-1] if mirror else img[hy - 1:hy].repeat(rows, 0)
    if src.shape[0] < rows:
        src = np.concatenate([src, np.repeat(src[-1:], rows - src.shape[0], 0)], 0)
    # Ripples: a sideways wobble of the reflection, and streaks of light.
    rip = fbm(rng, w, rows, 40, 4, 0.5, stretch=14.0)
    off = ((rip - 0.5) * (8 + 60 * t)).astype(int)
    cols = np.clip(np.arange(w)[None, :] + off, 0, w - 1)
    refl = src[np.arange(rows)[:, None], cols]
    out = mix(base, refl, np.broadcast_to(sky_ref + 0.35 * (1 - t), (rows, w)))
    streak = smoothstep(0.55, 0.85, fbm(rng, w, rows, 60, 3, 0.5, stretch=30.0))
    out = over(out, rgb("#ffffff"), streak * 0.06 * (1 - t))
    if sun_x is not None:
        y, x = np.mgrid[0:rows, 0:w].astype(np.float32)
        col = np.exp(-((x / w - sun_x) / (0.02 + 0.10 * y / rows)) ** 2)
        out = over(out, sun_col, col * smoothstep(0.35, 0.75, rip) * 0.85)
    img = img.copy()
    img[hy:] = out
    # A soft line where the water meets the shore.
    img[hy:hy + max(1, h // 400)] *= 0.92
    return img


# ── Abstract ─────────────────────────────────────────────────────────────────


def blobs(w, h, rng, ground, colours, softness=0.55):
    """Soft colour fields, the way the shell's glass sees a wallpaper."""
    img = np.broadcast_to(ground, (h, w, 3)).copy()
    for col in colours:
        cx, cy = rng.random() * 1.2 - 0.1, rng.random() * 1.2 - 0.1
        r = softness * (0.5 + rng.random() * 0.6)
        img = over(img, col, 0.85 * glow(w, h, cx, cy * h / w * w / h, r, 2.0))
    warp = fbm(rng, w, h, 2, 3, 0.5)
    return img * (0.94 + 0.12 * warp[..., None])


def ribbons(w, h, rng, ground, colours, light=False):
    """Bands that flow across, each a shade, with a sheen along its edge."""
    img = np.broadcast_to(ground, (h, w, 3)).copy()
    x = np.linspace(0, 1, w, dtype=np.float32)
    yy = np.linspace(0, 1, h, dtype=np.float32)[:, None]
    n = len(colours)
    for i, col in enumerate(colours):
        phase = rng.random() * 6.28
        y0 = 0.25 + 0.6 * i / n
        edge = (y0 + 0.10 * np.sin(x * 3.1 + phase) + 0.05 * np.sin(x * 7.3 + phase * 1.7)
                + 0.025 * np.sin(x * 13.0 + phase * 0.3))
        inside = smoothstep(edge - 0.002, edge + 0.002, yy)
        depth = np.clip((yy - edge) / 0.25, 0, 1)
        shade = mix(col, col * (1.12 if light else 0.62), depth)
        img = img * (1 - inside[..., None]) + shade * inside[..., None]
        sheen = np.exp(-((yy - edge) / 0.006) ** 2)
        img = over(img, rgb("#ffffff"), sheen * (0.35 if light else 0.18))
    return img


# ── The set ──────────────────────────────────────────────────────────────────

def make(name, w, h):
    seed = sum(map(ord, name)) * 7919
    rng = np.random.default_rng(seed)
    c = rgb

    if name == "Sky/clouds-day":
        img = sky(w, h, rng, c("#3f7fd0"), c("#b9d6f2"), c("#ffffff"), c("#a9bdd6"), 0.42)
    elif name == "Sky/clouds-dusk":
        img = sky(w, h, rng, c("#2c3a74"), c("#f2a26b"), c("#ffd2a8"), c("#7a5b86"), 0.40,
                  sun=(0.68, 0.86, c("#ffcf8a")))
    elif name == "Sky/clouds-night":
        img = sky(w, h, rng, c("#060a1c"), c("#1d2a52"), c("#6f7fa8"), c("#141c38"), 0.30, stars=True)

    elif name == "Mountains/blue-ranges":
        img = vertical(h, w, [(0, c("#8fb4dc")), (0.55, c("#e3edf6")), (1, c("#e3edf6"))])
        img = ranges(img, rng, 6, c("#a9c0da"), c("#1d3352"), c("#e8f0f7"), top=0.40, bottom=0.86)
    elif name == "Mountains/dawn-ranges":
        img = vertical(h, w, [(0, c("#3b4f8f")), (0.45, c("#e8a0a0")), (0.62, c("#ffd9a8")), (1, c("#ffd9a8"))])
        img = over(img, c("#fff1c9"), 0.8 * glow(w, h, 0.32, 0.50, 0.12, 1.6))
        img = ranges(img, rng, 6, c("#d9a4b0"), c("#2a2140"), c("#f6c9b8"), top=0.46, bottom=0.88)
    elif name == "Mountains/dusk-ranges":
        img = vertical(h, w, [(0, c("#1d1b48")), (0.40, c("#7a3f78")), (0.60, c("#f08a5d")), (1, c("#f08a5d"))])
        img = over(img, c("#ffcf7a"), 0.9 * glow(w, h, 0.62, 0.55, 0.10, 1.6))
        img = ranges(img, rng, 7, c("#c46a78"), c("#160f26"), c("#f2a07e"), top=0.44, bottom=0.90)
    elif name == "Mountains/night-ranges":
        img = sky(w, h, rng, c("#050817"), c("#22305e"), c("#5a6890"), c("#141b36"), 0.12, stars=True)
        img = over(img, c("#e9eefc"), glow(w, h, 0.78, 0.18, 0.012, 2.4))
        img = over(img, c("#9fb2e8"), 0.25 * glow(w, h, 0.78, 0.18, 0.12, 1.5))
        img = ranges(img, rng, 6, c("#2c3b6a"), c("#05070f"), c("#3a4a7c"), top=0.50, bottom=0.90, mist=0.35)
    elif name == "Mountains/snow-peaks":
        img = vertical(h, w, [(0, c("#5c9ad8")), (0.6, c("#d4e6f5")), (1, c("#d4e6f5"))])
        img = ranges(img, rng, 3, c("#b9c9dc"), c("#6d84a2"), c("#e6eef7"), top=0.44, bottom=0.64,
                     height=0.34, points=2, mist=0.35, snow=c("#f7fafd"))
        img = ranges(img, rng, 3, c("#5f7894"), c("#1f2c3a"), c("#c9d8e6"), top=0.70, bottom=0.92,
                     height=0.12, trees=True, mist=0.5)
    elif name == "Mountains/misty-valley":
        img = vertical(h, w, [(0, c("#c7d1d6")), (1, c("#eef1f2"))])
        img = ranges(img, rng, 8, c("#c2ccd0"), c("#2f3d3a"), c("#f2f4f4"), top=0.30, bottom=0.92,
                     height=0.16, mist=0.85)

    elif name == "Forest/fog-forest":
        img = vertical(h, w, [(0, c("#9fb3b0")), (1, c("#dfe7e3"))])
        img = ranges(img, rng, 6, c("#a6b8b2"), c("#0f2420"), c("#e4ece8"), top=0.40, bottom=0.95,
                     height=0.10, trees=True, mist=0.9)
    elif name == "Forest/morning-pines":
        img = vertical(h, w, [(0, c("#f4c9a0")), (0.6, c("#fbe7cf")), (1, c("#fbe7cf"))])
        img = over(img, c("#fff6dc"), 0.9 * glow(w, h, 0.25, 0.42, 0.14, 1.5))
        img = ranges(img, rng, 6, c("#d9b8a0"), c("#1c2a26"), c("#fbe3cc"), top=0.42, bottom=0.95,
                     height=0.11, trees=True, mist=0.8)
    elif name == "Forest/night-pines":
        img = sky(w, h, rng, c("#03060f"), c("#122340"), c("#3c5070"), c("#0b1424"), 0.10, stars=True)
        img = ranges(img, rng, 5, c("#1c3048"), c("#020406"), c("#20364f"), top=0.50, bottom=0.95,
                     height=0.10, trees=True, mist=0.4)

    elif name == "Water/calm-sea":
        img = sky(w, h, rng, c("#4a86cf"), c("#d6e6f3"), c("#ffffff"), c("#b3c6dc"), 0.30)
        img = water(img, rng, 0.62, c("#123e66"), c("#4f86b5"), sky_ref=0.30)
    elif name == "Water/sunset-sea":
        img = sky(w, h, rng, c("#2d2a6b"), c("#ffad6b"), c("#ffd0a0"), c("#8a5a7a"), 0.30,
                  sun=(0.5, 0.60, c("#ffd58a")))
        img = water(img, rng, 0.62, c("#1c1838"), c("#7a4a6a"), sky_ref=0.45, sun_x=0.5,
                    sun_col=c("#ffd08a"))
    elif name == "Water/mountain-lake":
        img = vertical(h, w, [(0, c("#6fa3d6")), (0.5, c("#dce9f4")), (1, c("#dce9f4"))])
        img = ranges(img, rng, 5, c("#a8bdd2"), c("#1d3340"), c("#e4eef6"), top=0.28, bottom=0.55,
                     height=0.18, mist=0.5)
        img = water(img, rng, 0.58, c("#0f2c3c"), c("#3d6b86"), sky_ref=0.25, mirror=True)
    elif name == "Water/blue-hour-lake":
        img = vertical(h, w, [(0, c("#141d44")), (0.55, c("#5d6fa8")), (1, c("#5d6fa8"))])
        img = ranges(img, rng, 4, c("#4b5a8a"), c("#0a0f22"), c("#6a7bb0"), top=0.36, bottom=0.56,
                     height=0.12, trees=True, mist=0.5)
        img = water(img, rng, 0.58, c("#070b1c"), c("#2b3866"), sky_ref=0.35, mirror=True)

    elif name == "Abstract/air-blue":
        img = blobs(w, h, rng, c("#dfe9f6"), [c("#8ec5ff"), c("#c7b8ff"), c("#a5f0e6"), c("#ffffff")])
    elif name == "Abstract/air-dawn":
        img = blobs(w, h, rng, c("#fbe6dc"), [c("#ffb59a"), c("#ffd7a1"), c("#d9b8ff"), c("#ffffff")])
    elif name == "Abstract/air-mint":
        img = blobs(w, h, rng, c("#e2f4ee"), [c("#9be3c8"), c("#b8e0ff"), c("#e9f7b0"), c("#ffffff")])
    elif name == "Abstract/air-night":
        img = blobs(w, h, rng, c("#0b1024"), [c("#2b3ea8"), c("#6a2fa0"), c("#0f6f8f"), c("#1a1f4a")])
    elif name == "Abstract/air-ember":
        img = blobs(w, h, rng, c("#160c14"), [c("#a8324a"), c("#d9772b"), c("#5a1f6e"), c("#2a0f1c")])
    elif name == "Abstract/waves-light":
        img = ribbons(w, h, rng, c("#eef3fa"), [c("#cfe0f5"), c("#a9c8ee"), c("#7fa9e3"), c("#5a8bd6")], light=True)
    elif name == "Abstract/waves-dark":
        img = ribbons(w, h, rng, c("#0c1020"), [c("#1d2850"), c("#2c3a7a"), c("#4250a8"), c("#6a5ad0")])
    elif name == "Abstract/waves-sunset":
        img = ribbons(w, h, rng, c("#2a1838"), [c("#5a2a5e"), c("#a2406a"), c("#e0705a"), c("#f6b26b")])
    else:
        raise SystemExit(f"no such wallpaper: {name}")
    return finish(img, rng)


NAMES = [
    "Sky/clouds-day", "Sky/clouds-dusk", "Sky/clouds-night",
    "Mountains/blue-ranges", "Mountains/dawn-ranges", "Mountains/dusk-ranges",
    "Mountains/night-ranges", "Mountains/snow-peaks", "Mountains/misty-valley",
    "Forest/fog-forest", "Forest/morning-pines", "Forest/night-pines",
    "Water/calm-sea", "Water/sunset-sea", "Water/mountain-lake", "Water/blue-hour-lake",
    "Abstract/air-blue", "Abstract/air-dawn", "Abstract/air-mint", "Abstract/air-night",
    "Abstract/air-ember", "Abstract/waves-light", "Abstract/waves-dark", "Abstract/waves-sunset",
]


def licence_exif(name):
    """Who made it and under what terms, in the file itself."""
    exif = Image.Exif()
    exif[0x013B] = "b1air"                                   # Artist
    exif[0x8298] = ("b1air contributors. GPL-2.0-only; the source is "
                    "tools/make-wallpapers.py in https://github.com/bla1r1/b1air")  # Copyright
    exif[0x010E] = f"b1air wallpaper {name}"                 # ImageDescription
    exif[0x0131] = "tools/make-wallpapers.py"                # Software
    return exif.tobytes()


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("outdir", nargs="?", default=os.path.join(os.path.dirname(__file__), "..", ".wallpapers"))
    ap.add_argument("--size", default="3840x2160")
    ap.add_argument("--only", nargs="*")
    a = ap.parse_args()
    w, h = map(int, a.size.lower().split("x"))
    for name in a.only or NAMES:
        path = os.path.join(a.outdir, name + ".jpg")
        os.makedirs(os.path.dirname(path), exist_ok=True)
        make(name, w, h).save(path, quality=90, optimize=True, progressive=True, subsampling=0,
                              exif=licence_exif(name))
        print(path)


if __name__ == "__main__":
    sys.exit(main())
