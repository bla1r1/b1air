# Our changes to swayfx

`tools/build-swayfx.sh` builds swayfx at a pinned release with its own
wlroots and scenefx (see the script). Everything we change in swayfx itself
lives here, as a patch series in `patches/`, applied in name order onto that
release before it is built.

A series rather than a fork repository: every change is a file in this repo,
reviewed with the rest of the desktop, and moving to a new swayfx release is
re-applying the series and fixing what no longer fits, instead of merging a
long-lived branch.

## What the series adds

| Patch | Command | What it does |
|---|---|---|
| 0001 | `autotile enable\|disable\|toggle` | Each new tiled window halves the one it opens next to along its longer side — Hyprland's dwindle. |
| 0002 | `inactive_opacity <0..1>` | Every window but the focused one drawn at that opacity. |
| 0003 | `workspace_animation fade\|slide` | Switching workspaces slides them sideways instead of fading. |
| 0004 | `workspace_swipe off\|<fingers> [invert]` | A sideways touchpad swipe moves the workspace with the fingers, its neighbour in beside it; letting go switches or slides back. |

None of them changes anything until its command is given. The session daemon
gives them over IPC (`SettingsManager::apply_compositor_extras`) at login, on
every settings change and after every reload — never from the config file, so
a sway without these patches is not stopped by an unknown command. When the
compositor takes `autotile`, the daemon's own tiling thread stands down.

### Trying the swipe without a touchpad

```sh
swaymsg workspace_animation slide; swaymsg workspace_swipe 3
swaymsg debug_workspace_swipe begin 3
for i in $(seq 1 30); do swaymsg debug_workspace_swipe update -20; sleep 0.02; done
swaymsg debug_workspace_swipe end      # or: cancel
```

## Writing a patch

```sh
git clone --branch 0.6 https://github.com/WillPower3309/swayfx
cd swayfx
git am ../DotsFiles/src/swayfx/patches/*.patch     # the series so far
# … change, build, test …
git commit -a
git format-patch -1 -o ../DotsFiles/src/swayfx/patches --start-number <next>
```

Name them `NNNN-short-description.patch`; the number is the order. Each one
should build and run on its own on top of the ones before it.

## Licence

swayfx, sway, scenefx and wlroots are MIT-licensed. The patches here change
MIT code; keep the MIT notices in the files they touch. Code taken from
scroll (also MIT, a sway fork) keeps its copyright line.
