# Where the wallpapers come from

Every picture here is b1air's own: drawn by
[`tools/make-wallpapers.py`](../tools/make-wallpapers.py) from fixed seeds —
skies with clouds, ranges of hills in haze, snow peaks, forests in fog, the sea
and lakes, soft gradients and waves. Nothing of anyone else's goes into them:
no photograph, no painting, no stock image.

## Licence

**GPL-2.0-only**, as the rest of the project (`LICENSE`). The script is their
source — the preferred form for changing them — so anyone given a picture can
draw it again, or draw it differently:

    tools/make-wallpapers.py              # into .wallpapers/, 3840x2160
    tools/make-wallpapers.py /tmp/w --size 2560x1600
    tools/make-wallpapers.py --only Sky/clouds-day

Each file also says so itself, in its EXIF (Artist: b1air; Copyright: the
licence and where the source is). The login screen's fallback picture,
`usr/share/sddm/themes/b1air/backgrounds/default.jpg`, is `Sky/clouds-day`
drawn smaller, under the same terms.

## Adding one

A picture comes in from the script, or with a line in this file naming who
made it and a licence that lets the project carry it. Without that line it is
not added.
