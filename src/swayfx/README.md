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
| 0005 | `special_workspace toggle\|show\|hide` | Hyprland's special workspace: one of its own, named `special`, called up over the current workspace (which stays in view, dimmed) and put away again. `move container to workspace special` sends a window there; next/prev and the swipe pass it by. Mod+S / Mod+Ctrl+Shift+S, bound by the daemon where the command exists. |
| 0006 | `window_animation popin [<percent>]\|fade\|slide\|none` | How windows open and close, as Hyprland's `animation = windows`: swayfx's own grow-from-80% (popin, now with its size), a fade in place, a slide in from the nearest edge of the workspace and out by it, or none. Default popin, as swayfx had it. |
| 0007 | `overview toggle\|show\|hide` | Every workspace of the focused screen side by side, live and scaled down (scenefx 0002): the current one shrinks from the full screen into its place. A click, or the arrows and Enter, goes to one; Escape or a click beside them leaves. Floating windows and the special workspace are left out while it is up. Mod+O, bound by the daemon where the command exists. `overview_swipe <fingers>`: a swipe up brings it in following the fingers, down takes it away; four fingers, set by the daemon. |

Hyprland's `togglesplit` needs no patch: it is sway's own `layout toggle
split`, bound to Mod+J.

`tools/test-swayfx.sh` starts the built swayfx headless (no screen, no GPU)
and checks each of these over IPC; CI runs it on every push, on every
distribution family the installer supports.

And two patches to scenefx, in `../scenefx/patches/`, applied to the copy in
swayfx's `subprojects/`:

| Patch | What it does |
|---|---|
| scenefx 0001 | Without GLES2 (no GPU, a VM without 3D, a broken driver) swayfx starts anyway, on wlroots' software renderer, instead of not starting at all. Windows, tiling, opacity and the workspace animations all work; blur, shadows and rounded corners are left out. `WLR_RENDERER=pixman` asks for it outright, which is what the session sets in a VM. |
| scenefx 0002 | `wlr_scene_tree_set_scale()`: a tree drawn scaled about its own origin, with everything in it, for the overview. The scale is kept beside the tree, not in it, so the struct keeps the layout wlroots' own code expects of it. |

The first is the spare for when something is broken: a login into a working,
if plainer, desktop, from which the driver can be fixed. scroll and plain
sway do the same; swayfx did not, because scenefx's renderer is GLES2 only.

None of the swayfx patches changes anything until its command is given. The session daemon
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

A patch adding a command puts it in its table in `sway/commands.c` in
alphabetical order: sway finds commands by binary search, and one out of
order makes the commands after it unknown (0004 once did that to
`workspace_auto_back_and_forth`; the test now checks it).

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

A scenefx patch is written the same way, in a clone of scenefx at the pinned
release (`--branch 0.5`), into `../scenefx/patches`.

## Licence

swayfx, sway, scenefx and wlroots are MIT-licensed. The patches here change
MIT code; keep the MIT notices in the files they touch. Code taken from
scroll (also MIT, a sway fork) keeps its copyright line.
