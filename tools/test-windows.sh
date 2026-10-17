#!/usr/bin/env bash
# =============================================================================
# tools/test-windows.sh — src/scripts/b1air-windows, without Wine or a network.
#
# A stand-in umu-run takes the place of Proton: given an installer it leaves
# what one would (a program under Program Files, Start menu shortcuts, one of
# them an uninstaller), and it writes down every call with the environment it
# was given. Everything else is the real script, in a throwaway home: reading
# the .exe (a real one: Python's launcher from the uv cache or pip, when there
# is one), the shortcuts, the Launchpad entries, the options, the theme, a
# crash and its second try, the umu database, removing.
#
#   tools/test-windows.sh
# =============================================================================
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
BW="$REPO/src/scripts/b1air-windows"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
export HOME="$T/home" XDG_DATA_HOME="$T/home/.local/share" XDG_CONFIG_HOME="$T/home/.config" XDG_CACHE_HOME="$T/home/.cache"
mkdir -p "$HOME" "$T/bin" "$XDG_CACHE_HOME/b1air"
unset LANG LC_MESSAGES
PASS=0 FAILED=0
ok()   { echo "ok   $1"; PASS=$((PASS + 1)); }
fail() { echo "FAIL $1${2:+: $2}"; FAILED=$((FAILED + 1)); }

# A real PE with an icon and version information, where there is one.
EXE="$(find "$HOME/../.." /root/.cache /usr/lib/python3* -xdev -name 'w64.exe' -path '*distlib*' 2>/dev/null | head -1)"
[[ -n "$EXE" ]] || EXE="$(find / -xdev -name 'w64.exe' -path '*distlib*' 2>/dev/null | head -1)"
[[ -n "$EXE" ]] || { echo "test-windows: no distlib w64.exe to read (pip or uv brings one)" >&2; exit 2; }

# ── The stand-ins ────────────────────────────────────────────────────────────
cat > "$T/mklnk.py" <<'EOF'
# mklnk.py OUT TARGET [ARGS] [unicode]: a minimal shell link to TARGET.
import struct, sys
out, target = sys.argv[1], sys.argv[2]
args = sys.argv[3] if len(sys.argv) > 3 else ""
wide = len(sys.argv) > 4
flags = 0x02 | (0x20 if args else 0) | (0x80 if wide else 0)
header = struct.pack("<I16sIIQQQIIIHHII", 0x4C, b"\x01\x14\x02\0\0\0\0\0\xc0\0\0\0\0\0\0F", flags, 0x20, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0)
if wide:
    base = target.encode("utf-16-le") + b"\0\0"; suffix = b"\0\0"
    hsize = 0x24
    body_off = hsize
    info = struct.pack("<IIIIIIIII", 0, hsize, 1, 0, 0, 0, 0, body_off, body_off + len(base)) + base + suffix
else:
    base = target.encode("cp1252") + b"\0"; suffix = b"\0"
    hsize = 0x1C
    info = struct.pack("<IIIIIII", 0, hsize, 1, 0, hsize, 0, hsize + len(base)) + base + suffix
info = struct.pack("<I", len(info)) + info[4:]
strings = b""
if args:
    enc = args.encode("utf-16-le") if wide else args.encode("cp1252")
    strings += struct.pack("<H", len(args)) + enc
open(out, "wb").write(header[:0x4C] + info + strings)
EOF

cat > "$T/bin/umu-run" <<EOF
#!/usr/bin/env bash
# Every call, with what it was given.
{ printf 'CALL'; printf ' %q' "\$@"; echo
  for v in WINEPREFIX GAMEID STORE PROTONPATH PROTON_USE_WINED3D PROTON_ENABLE_WAYLAND MANGOHUD WINE_FULLSCREEN_FSR WINEDLLOVERRIDES; do
      echo "  \$v=\${!v-}"; done; } >> "$T/calls"
p="\$WINEPREFIX"
case "\$(basename -- "\$1")" in
  regedit|winetricks|wineboot|winecfg) exit 0 ;;
  FooSetup.exe)
    mkdir -p "\$p/drive_c/Program Files/Foo" "\$p/drive_c/ProgramData/Microsoft/Windows/Start Menu/Programs/Foo" \
             "\$p/drive_c/users/steamuser/Desktop"
    cp "$EXE" "\$p/drive_c/Program Files/Foo/Foo.exe"
    cp "$EXE" "\$p/drive_c/Program Files/Foo/unins000.exe"
    python3 "$T/mklnk.py" "\$p/drive_c/ProgramData/Microsoft/Windows/Start Menu/Programs/Foo/Foo.lnk" 'C:\\Program Files\\Foo\\Foo.exe' '-fast'
    python3 "$T/mklnk.py" "\$p/drive_c/ProgramData/Microsoft/Windows/Start Menu/Programs/Foo/Uninstall Foo.lnk" 'C:\\Program Files\\Foo\\unins000.exe'
    python3 "$T/mklnk.py" "\$p/drive_c/users/steamuser/Desktop/Foo.lnk" 'C:\\PROGRAM FILES\\foo\\foo.EXE' '' unicode
    exit 0 ;;
  BarSetup.exe)
    mkdir -p "\$p/drive_c/Program Files (x86)/Bar"
    cp "$EXE" "\$p/drive_c/Program Files (x86)/Bar/Bar.exe"
    exit 0 ;;
  Crash.exe) [[ -n "\${PROTON_USE_WINED3D-}" ]] && exit 0; exit 5 ;;
esac
exit 0
EOF
# notify-send: an action is asked for, "safe" is picked.
cat > "$T/bin/notify-send" <<EOF
#!/usr/bin/env bash
echo "NOTIFY \$*" >> "$T/notes"
for a in "\$@"; do [[ "\$a" == --action=safe=* ]] && { echo safe; exit 0; }; done
exit 0
EOF
chmod +x "$T/bin/"*
export PATH="$T/bin:$PATH"
calls() { cat "$T/calls" 2>/dev/null; }

# The umu database, as fetched: Foo is a game it knows.
printf 'TITLE,STORE,CODENAME,UMU_ID,COMMON ACRONYM (Optional),NOTE (Optional)\nFoo,none,foo,umu-424242,,\nSimple Launcher,none,simple,umu-777,,\n' \
    > "$XDG_CACHE_HOME/b1air/umu-database.csv"
mkdir -p "$XDG_CONFIG_HOME/b1air"
echo '{"ground": "#ffffff", "text": "#111111", "primary": "#3366ff"}' > "$XDG_CONFIG_HOME/b1air/theme.json"

# ── Reading a .exe ───────────────────────────────────────────────────────────
cp "$EXE" "$T/FooSetup.exe"; cp "$EXE" "$T/BarSetup.exe"; cp "$EXE" "$T/Crash.exe"; cp "$EXE" "$T/Tool.exe"
cp "$EXE" "$T/BazSetup.exe"
info="$("$BW" inspect "$T/FooSetup.exe")"
python3 -c 'import json,sys; i=json.loads(sys.argv[1]); assert i["installer"] and i["name"] == "Simple Launcher" and i["icon"]' "$info" \
    && ok "inspect: name from the version info, an installer by its name, the icon" || fail "inspect" "$info"
python3 -c 'import json,sys; r=json.loads(sys.argv[1])["recommended"]; assert r["bottle"]=="default" and r["runner"]=="GE-Proton" and r["reason"]=="known" and r["gameid"]=="umu-777"' "$info" \
    && ok "inspect: recommends the shared bottle and GE-Proton, and knows the title" || fail "recommendation" "$info"
icon="$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["icon"])' "$info")"
[[ "$(head -c 8 "$icon" | od -An -c | tr -d ' ')" == '211PNG\r\n032\n' ]] && ok "inspect: the icon is a PNG" || fail "icon is not a PNG"
"$BW" inspect "$T/Tool.exe" | grep -q '"installer": false' && ok "inspect: a program is not an installer" || fail "Tool.exe an installer"
"$BW" bottles | python3 -c 'import json,sys; b=json.load(sys.stdin); assert b[0]["shared"] and b[0]["id"]=="default"' \
    && ok "bottles: the shared one offered before it exists" || fail "bottles before" "$("$BW" bottles)"

# ── Installing into the shared bottle ────────────────────────────────────────
SHARED="$XDG_DATA_HOME/b1air/windows/_bottles/default"
out="$("$BW" install "$T/FooSetup.exe" --name Foo)"
echo "$out" | grep -q '"event": "done"' && ok "install: done" || fail "install" "$out"
grep -q "WINEPREFIX=$SHARED/prefix" "$T/calls" && ok "install: into the shared bottle" || fail "not the shared bottle" "$(calls)"
desk="$XDG_DATA_HOME/applications/b1air-win-foo-1.desktop"
[[ -f "$desk" ]] && ok "install: a Launchpad entry" || fail "no desktop entry" "$(ls "$XDG_DATA_HOME/applications" 2>/dev/null)"
grep -q '^Exec=b1air-windows run foo 1$' "$desk" && grep -q '^StartupWMClass=foo.exe$' "$desk" && grep -q '^Icon=/.*icon-1.png$' "$desk" \
    && ok "install: Exec, the window class and its own icon" || fail "desktop entry" "$(cat "$desk")"
[[ ! -e "$XDG_DATA_HOME/applications/b1air-win-foo-2.desktop" ]] \
    && ok "install: the uninstaller and the same program's second shortcut left out" || fail "too many entries"
"$BW" list | python3 -c 'import json,sys; a=json.load(sys.stdin)[0]; assert a["gameid"]=="umu-424242" and a["launchers"][0]["args"]=="-fast" and a["uninstaller"] and a["bottle"]=="default"' \
    && ok "install: the umu database's id, the shortcut's arguments, its uninstaller" || fail "list" "$("$BW" list)"
grep -q 'CALL regedit /S Z:' "$T/calls" && ok "install: the desktop's colours applied first" || fail "no regedit" "$(calls)"
grep -q 'WINEDLLOVERRIDES=winemenubuilder.exe=d' "$T/calls" && ok "install: Wine's own menu entries off" || fail "winemenubuilder"

# A second program in the same bottle: only what it brought is its.
out="$("$BW" install "$T/BarSetup.exe" --name Bar)"
echo "$out" | grep -q '"event": "choose"' && echo "$out" | grep -q 'Bar.exe' && ! echo "$out" | grep -q 'Foo.exe' \
    && ok "shared bottle: the second install sees its own files, not the first's" || fail "choose" "$out"
"$BW" pick bar "$(echo "$out" | python3 -c 'import json,sys; print([json.loads(l) for l in sys.stdin if "choose" in l][0]["candidates"][0])')" >/dev/null
[[ -f "$XDG_DATA_HOME/applications/b1air-win-bar-1.desktop" ]] && ok "pick: an entry for it" || fail "pick"
: > "$T/calls"; "$BW" install "$T/BarSetup.exe" --name Bar2 --runner UMU-Proton >/dev/null
grep -q 'PROTONPATH=GE-Proton' "$T/calls" && ok "an existing bottle keeps its Proton" || fail "runner changed on an existing bottle" "$(calls | grep PROTONPATH)"

# ── A bottle of its own, with another Proton ─────────────────────────────────
: > "$T/calls"
out="$("$BW" install "$T/BazSetup.exe" --name Baz --new-bottle "Baz Game" --runner UMU-Proton)"
grep -q 'WINEPREFIX=.*_bottles/baz-game/prefix' "$T/calls" && grep -q 'PROTONPATH=UMU-Proton' "$T/calls" \
    && ok "a new bottle, with the Proton asked for" || fail "new bottle" "$(calls | grep -E 'WINEPREFIX|PROTONPATH')"
"$BW" bottles | python3 -c '
import json,sys
b={x["id"]: x for x in json.load(sys.stdin)}
assert b["default"]["shared"] and {a["slug"] for a in b["default"]["apps"]} >= {"foo", "bar"}
assert b["baz-game"]["runner"]=="UMU-Proton" and b["baz-game"]["name"]=="Baz Game"' \
    && ok "bottles: each with its Proton and programs" || fail "bottles" "$("$BW" bottles)"
"$BW" bottle-set baz-game runner GE-Proton && "$BW" bottles | grep -q '"runner": "GE-Proton", "deps": \[\], "shared": false, "made": true' \
    && ok "bottle-set: another Proton" || fail "bottle-set"

# ── Running, with options ────────────────────────────────────────────────────
: > "$T/calls"
"$BW" run foo 1 extra
grep -q "CALL .*Foo.exe -fast extra" "$T/calls" && grep -q 'PROTONPATH=GE-Proton' "$T/calls" && grep -q 'GAMEID=umu-424242' "$T/calls" \
    && ok "run: the program, its arguments, GE-Proton and its game id" || fail "run" "$(calls)"
grep -q 'CALL regedit' "$T/calls" && fail "theme applied again, unchanged" || ok "run: an unchanged theme is not applied again"
"$BW" set foo dxvk off && "$BW" set foo wayland on && "$BW" set foo mangohud on
: > "$T/calls"; "$BW" run foo
grep -q 'PROTON_USE_WINED3D=1' "$T/calls" && grep -q 'PROTON_ENABLE_WAYLAND=1' "$T/calls" && grep -q 'MANGOHUD=1' "$T/calls" \
    && ok "set: DXVK off, Wayland and MangoHud on reach Proton" || fail "options" "$(calls)"
: > "$T/calls"; "$BW" run bar
grep -q 'PROTON_USE_WINED3D=1' "$T/calls" && fail "an option leaked to another program in the bottle" || ok "options are the program's, not the bottle's"
"$BW" set foo nonsense on 2>/dev/null && fail "set took nonsense" || ok "set refuses an unknown option"
"$BW" set foo game on && grep -q '^Categories=Game;' "$desk" && ok "set game: in the Launchpad's Games" || fail "game category"
echo '{"ground": "#101010", "text": "#eeeeee"}' > "$XDG_CONFIG_HOME/b1air/theme.json"
: > "$T/calls"; "$BW" run foo
grep -q 'CALL regedit' "$T/calls" && ok "run: a new theme is applied" || fail "theme change not applied"
reg="$SHARED/theme.reg"
iconv -f UTF-16 -t UTF-8 "$reg" 2>/dev/null | grep -q '"AppsUseLightTheme"=dword:00000000' \
    && iconv -f UTF-16 -t UTF-8 "$reg" | grep -q '"Window"=' && ok "theme: dark colours, dark mode for programs" || fail "theme.reg" "$(iconv -f UTF-16 -t UTF-8 "$reg" 2>&1 | head -5)"

# ── A program with no installer, a run once, a crash ─────────────────────────
"$BW" add "$T/Tool.exe" --name Tool >/dev/null
grep -q "^Exec=b1air-windows run tool 1$" "$XDG_DATA_HOME/applications/b1air-win-tool-1.desktop" 2>/dev/null \
    && ok "add: an entry for a program as it is" || fail "add"
: > "$T/calls"; "$BW" once "$T/Tool.exe"
grep -q "WINEPREFIX=$SHARED/prefix" "$T/calls" && ok "once: in the shared bottle" || fail "once" "$(calls)"
[[ -z "$(ls "$XDG_DATA_HOME/applications" | grep -i tool-2)" ]] && ok "once: no entry" || fail "once made an entry"
: > "$T/calls"; "$BW" once "$T/Crash.exe"; code=$?
[[ $code -eq 0 ]] && [[ "$(grep -c '^CALL .*Crash.exe' "$T/calls")" -eq 2 ]] && grep -q 'NOTIFY.*--action=safe' "$T/notes" \
    && ok "crash: said so, and the second try with safe settings worked" || fail "crash" "code $code; $(calls | grep CALL)"

# ── Components, the runtime, removing ────────────────────────────────────────
: > "$T/calls"; "$BW" deps default vcrun2022 corefonts
grep -q 'CALL winetricks -q vcrun2022 corefonts' "$T/calls" && "$BW" bottles | grep -q '"vcrun2022"' \
    && ok "deps: into the bottle, through winetricks" || fail "deps" "$(calls)"
"$BW" deps default 'x;rm -rf /' 2>/dev/null; grep -q 'rm -rf' "$T/calls" && fail "deps passed a bad verb" || ok "deps: only plain verbs"
"$BW" runtime | python3 -c 'import json,sys; r=json.load(sys.stdin); assert r["umu"].endswith("umu-run") and r["recommended"]=="GE-Proton"' \
    && ok "runtime: umu found" || fail "runtime" "$("$BW" runtime)"
: > "$T/calls"; "$BW" remove foo
grep -q 'CALL .*unins000.exe' "$T/calls" && [[ ! -e "$XDG_DATA_HOME/b1air/windows/foo" && ! -e "$desk" && -d "$SHARED/prefix" ]] \
    && ok "remove from the shared bottle: its uninstaller, its entries; the bottle stays" || fail "remove shared" "$(calls | grep CALL)"
"$BW" remove baz
[[ ! -e "$XDG_DATA_HOME/b1air/windows/_bottles/baz-game" ]] && ok "remove: alone in its bottle, the bottle goes too" || fail "own bottle stayed"
"$BW" bottle-remove default
[[ ! -e "$SHARED" && -z "$(ls "$XDG_DATA_HOME/applications" | grep b1air-win-bar)" ]] \
    && ok "bottle-remove: the bottle and its programs" || fail "bottle-remove" "$(ls "$XDG_DATA_HOME/applications")"

# ── A program from before bottles ────────────────────────────────────────────
OLD="$XDG_DATA_HOME/b1air/windows/old"
mkdir -p "$OLD/prefix/drive_c/Old"; cp "$EXE" "$OLD/prefix/drive_c/Old/Old.exe"
printf '{"slug": "old", "name": "Old", "kind": "installed", "options": {"runner": "UMU-Proton"}, "launchers": [{"id": "1", "name": "Old", "exe": "%s", "args": "", "icon": ""}], "deps": ["corefonts"]}' \
    "$OLD/prefix/drive_c/Old/Old.exe" > "$OLD/app.json"
"$BW" list | python3 -c '
import json,sys,os
a=json.load(sys.stdin)[0]
assert a["bottle"]=="old" and "/_bottles/old/prefix/drive_c/Old/Old.exe" in a["launchers"][0]["exe"]
assert os.path.exists(a["launchers"][0]["exe"])' \
    && "$BW" bottles | grep -q '"runner": "UMU-Proton", "deps": \["corefonts"\]' \
    && ok "migrated: its prefix a bottle of its own, Proton and components kept" || fail "migration" "$("$BW" list; "$BW" bottles)"

"$BW" run '../etc' 2>/dev/null && fail "run took a path" || ok "a slug is never a path"
"$BW" 2>/dev/null; [[ $? -eq 2 ]] && ok "no command: the usage" || fail "usage"

echo "test-windows: $PASS passed, $FAILED failed"
[[ $FAILED -eq 0 ]]
