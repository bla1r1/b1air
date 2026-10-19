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
| 0008 | — | No compiler warning against newer libinput: the scroll-method switch in `ipc-json.c` gets a default case (libinput 1.31 added a circular scroll sway does not name; it is reported as "unknown", as before). |
| 0009 | `layer_effects <ns> blur_ignore_alpha <0..1>` | `blur_ignore_transparent` with a threshold (scenefx 0003): what is at most that opaque gets no blur behind it. The shell's full-screen `qs-master` layer draws each popup panel's soft shadow itself (Ui/PanelShadow, never over 40% opaque) and the daemon sets 0.4, so the blur stays under the panel and not in a halo round it. And `layer_effects` with a list that does not parse is refused, keeping the rule that was there — it said success and had already deleted it. |
| 0010 | `floating_snap <px>\|off`, `snap <zone>\|restore` | A floating window dragged to within that many pixels of the left or right edge snaps to that half of the screen, near a corner of the edge to a quarter, to the top edge to all of it, with a preview while it is held there (not the bottom edge: the dock is there). Dragged away it gets its size back. `snap` does it from a key or over IPC; the zones are where tiled windows would be, gaps and all. The daemon sets 12 px (Settings → Windows); get_tree reports `snapped`. |
| 0011 | — | In the overview a window can be taken by the mouse to another workspace: pressed on it in one workspace's cell and let go in another's, it goes there (as `move container to workspace`), and the overview stays to show it land. A pane its size follows the cursor, and the workspace it would go to is outlined. A click without moving still goes to that workspace, and it is now the release that does it. |
| 0012 | `minimize_target <x> <y> <w> <h>\|none` | A window sent to the scratchpad — minimized (`b1air-daemon window minimize`) — shrinks into its target and fades, a copy of what it showed holding its buffers; shown again it grows back out of the same place. The Dock sets each window's target to its app's icon; without one it is the bottom of the output. With `animation_duration_ms` and a `window_animation` other than none. get_tree reports `minimize_target`. |
| 0013 | `zoom <factor>\|in\|out\|reset\|toggle` | The screen magnified round the cursor, 1 (off) to 10 times, following it as it moves (scenefx 0004); `in`/`out` go by a quarter, changes are animated. What is under the cursor is drawn where it is, so clicks go where they look as if they go, and placing windows and popups does not see the zoom. Mod+Ctrl+scroll and Mod+Ctrl+0, bound by the daemon where the command exists; get_tree reports `zoom` on the root. Only the screen the cursor is on is magnified, and the zoom goes with the cursor to another one; get_tree's `zoom_output` names it. |
| 0014 | — | `bindsym --to-code` takes a shortcut's key from us, not from the keyboard's first layout: with a Cyrillic layout first, Mod+Q and the rest were bound to nothing, and us had to be kept first in the list — an English layout in the switcher nobody chose. Now the layouts are the user's, in their order, and every shortcut is on its US key in each of them. `get_version` reports `b1air_keys_from_us`; b1air-daemon puts us first only on a sway without it. |

Hyprland's `togglesplit` needs no patch: it is sway's own `layout toggle
split`, bound to Mod+J.

`tools/test-swayfx.sh` starts the built swayfx headless (no screen, no GPU)
and checks each of these over IPC; CI runs it on every push, on every
distribution family the installer supports.

And four patches to scenefx, in `../scenefx/patches/`, applied to the copy in
swayfx's `subprojects/`:

| Patch | What it does |
|---|---|
| scenefx 0001 | Without GLES2 (no GPU, a VM without 3D, a broken driver) swayfx starts anyway, on wlroots' software renderer, instead of not starting at all. Windows, tiling, opacity and the workspace animations all work; blur, shadows and rounded corners are left out. `WLR_RENDERER=pixman` asks for it outright, which is what the session sets in a VM. |
| scenefx 0002 | `wlr_scene_tree_set_scale()`: a tree drawn scaled about its own origin, with everything in it, for the overview. The scale is kept beside the tree, not in it, so the struct keeps the layout wlroots' own code expects of it. |
| scenefx 0003 | `wlr_scene_blur_set_transparency_threshold()`: with a transparency mask, a pixel at or below this alpha counts as transparent (0, the default, is the old `alpha == 0`). |
| scenefx 0004 | `wlr_scene_set_zoom()`: the scene drawn magnified about a point on one output (the box given), for the magnifier; the other outputs are drawn as usual. Drawing and `wlr_scene_node_at()` see it; `wlr_scene_node_coords()` and node positions do not. |

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
