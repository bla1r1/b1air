#!/usr/bin/env bash
#
# Design system conformance and metric tracker for b1air.
#
# Measures:
#   - Design.s(<number>) literal usages (0 in the shell and the apps)
#   - Gradients and hex colours in the apps (0)
#   - Hex color literals outside palette files
#   - Gradient usages
#   - Font weight bold usages (should be restricted to display hero numbers)
#

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 - "$REPO" <<'PY'
import os, re, sys, glob

repo = sys.argv[1]
shell_dir = os.path.join(repo, "src/shell/qml")
apps_dir = os.path.join(repo, "src/apps")
ui_dir = os.path.join(repo, "src/shell/qml/Ui")
settings_dir = os.path.join(repo, "src/shell/qml/settings")
shell_dir_only = os.path.join(repo, "src/shell/qml")
apps_only = os.path.join(repo, "src/apps")

qml_files = glob.glob(os.path.join(shell_dir, "**/*.qml"), recursive=True) + \
            glob.glob(os.path.join(apps_dir, "**/*.qml"), recursive=True)

s_lit_total = 0
s_lit_ui = 0
s_lit_settings = 0
s_lit_shell = 0
s_lit_apps = 0
apps_hex = []
apps_grad = 0
hex_colors = []
gradients = 0
bolds = 0

# Whitelisted files for hex colors: theme definitions and palette files
HEX_WHITELIST = {
    "Design.qml", "Theme.qml", "ThemeColors.qml"
}

for path in qml_files:
    fname = os.path.basename(path)
    rel = os.path.relpath(path, repo)
    try:
        text = open(path, encoding="utf-8").read()
    except Exception:
        continue

    # Strip comments to prevent false positives in comments
    clean_text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    clean_text = re.sub(r"//.*$", "", clean_text, flags=re.M)

    # 1. Design.s(<number>)
    # A number as the whole argument, or leading an expression
    # ("Design.s(30 + 30 * n)"): both are sizes that bypass the scales.
    s_matches = re.findall(r"\bDesign\.s\(\s*-?\s*\d", clean_text)
    if s_matches:
        count = len(s_matches)
        s_lit_total += count
        if path.startswith(ui_dir):
            s_lit_ui += count
        if path.startswith(settings_dir):
            s_lit_settings += count
        if path.startswith(shell_dir_only):
            s_lit_shell += count
        if path.startswith(apps_only):
            s_lit_apps += count

    # 2. Hex colors outside whitelist
    if fname not in HEX_WHITELIST:
        hex_matches = re.findall(r"#[0-9a-fA-F]{3,8}\b", clean_text)
        if hex_matches:
            for h in hex_matches:
                hex_colors.append((rel, h))

    # 3. Gradients
    grad_matches = re.findall(r"\bGradient\s*\{", clean_text)
    gradients += len(grad_matches)
    if path.startswith(apps_only):
        apps_grad += len(grad_matches)
        apps_hex += [(rel, h) for h in re.findall(r"#[0-9a-fA-F]{3,8}\b", clean_text)]

    # 4. Bold font weights
    bold_matches = re.findall(r"weight:\s*Design\.weight\.bold\b", clean_text)
    bolds += len(bold_matches)

print("=== Design System Metrics ===")
print(f"Design.s(<literal>) total:   {s_lit_total}")
print(f"Design.s(<literal>) in Ui/:  {s_lit_ui}")
print(f"... in settings/:            {s_lit_settings}")
print(f"... in the shell (all):       {s_lit_shell}")
print(f"... in the apps:              {s_lit_apps}")
print(f"Hex colors outside themes:   {len(hex_colors)}")
print(f"Gradient declarations:       {gradients}")
print(f"Design.weight.bold usages:   {bolds}")
print("=============================")

# Criteria checks: these fail. The legacy parts were removed in one go;
# anything using them again would bring the second look back with it.
LEGACY_TYPES = ("Card", "Toggle", "Dropdown", "FormRow", "Pill", "ActionButton",
                "ButtonRow", "BarButton", "BarGroup")
LEGACY_TOKENS = r"\bDesign\.(base|mantle|crust|subtext[01]|surface[012]|overlay[012])\b" \
                r"|\bDesign\.size\.(field|ctl|action|iconBtn)\b" \
                r"|\bDesign\.(glassHover|glassActive|selection)\b"  # the state* names
failures = []
if s_lit_ui > 0:
    failures.append(f"{s_lit_ui} Design.s(<literal>) in Ui/: use the scales in Design.qml")
if s_lit_shell > 0:
    failures.append(f"{s_lit_shell} Design.s(<literal>) in src/shell/qml: use the scales in Design.qml")
if s_lit_apps > 0:
    failures.append(f"{s_lit_apps} Design.s(<literal>) in src/apps: use the scales in Design.qml")
if apps_grad > 0:
    failures.append(f"{apps_grad} Gradient in src/apps: flat fills, as everywhere")
for rel, h in apps_hex:
    failures.append(f"{rel}: colour {h}: use a Design role")
for path in qml_files:
    rel = os.path.relpath(path, repo)
    text = re.sub(r"//.*$", "", open(path, encoding="utf-8").read(), flags=re.M)
    for t in LEGACY_TYPES:
        if re.search(r"(^|[^A-Za-z.])" + t + r"\s*\{", text):
            failures.append(f"{rel}: uses the removed {t}")
    for m in set(re.findall(LEGACY_TOKENS, text)):
        failures.append(f"{rel}: uses a removed Design alias")
# A state's colour comes from Design's ladder (stateHover, statePressed,
# stateSelectedSoft/Selected/Strong, accentLine), never mixed by hand: that
# is how a selection came in fifteen strengths of the accent. A tint of the
# text or the accent in a colour that changes with hover, press or choice
# is one of those.
STATE_WORDS = r"containsMouse|hovered|pressed|selected|isCurrent|checked|dropTarget|highlight|isHighlighted"
HAND_TINT = r"Design\.tint\(Design\.(accent|text|danger),\s*0?\.\d+\)"
for path in qml_files:
    if path.endswith("/Ui/Design.qml"):
        continue
    rel = os.path.relpath(path, repo)
    for n, line in enumerate(open(path, encoding="utf-8"), 1):
        code = line.split("//", 1)[0]
        # A colour line, or the next line of a colour's ternary.
        if re.search(r"(^|[{;])\s*((border\.)?color\s*:|[?:]\s)", code) and re.search(STATE_WORDS, code) \
                and re.search(HAND_TINT, code):
            failures.append(f"{rel}:{n}: a state's colour mixed by hand: use Design.state*")

# Other desktops' palettes, typed in before the theme carried one: Catppuccin
# Mocha's and Tokyo Night's own colours, found as late as the daemon's
# weather and music. A colour comes from the theme, or a role of it.
FOREIGN = re.compile(r"#(cdd6f4|cba6f7|f9e2af|74c7ec|bac2de|313244|89b4fa|f38ba8|1e1e2e|a6e3a1|fab387"
                     r"|1a1b26|7aa2f7|c0caf5|bb9af7|24283b|9ece6a|f7768e)\b", re.I)
for top in ("src", "usr", ".config", "tools"):
    for path in glob.glob(os.path.join(repo, top, "**/*"), recursive=True):
        if not os.path.isfile(path) or "/build" in path or not path.endswith(
                (".qml", ".cpp", ".hpp", ".conf", ".sh", ".json", ".css", ".ini", ".js")):
            continue
        if path.endswith("check-design.sh"):
            continue
        for n, line in enumerate(open(path, encoding="utf-8", errors="replace"), 1):
            if FOREIGN.search(line):
                failures.append(f"{os.path.relpath(path, repo)}:{n}: another desktop's palette colour")

# The corner rule is an attached type from the B1air.Daemon plugin: a file
# that reads Shape without importing it gets a ReferenceError at run time,
# which no syntax check sees.
for path in qml_files:
    text = re.sub(r"//.*$", "", open(path, encoding="utf-8").read(), flags=re.M)
    if re.search(r"\bShape\.(radius|inset|inner|minimum)\b", text) and "import B1air.Daemon" not in text:
        failures.append(f"{os.path.relpath(path, repo)}: reads Shape without `import B1air.Daemon`")

# Nothing an app or the shell shows is drawn with QML's own primitives: a
# shape is Ui/Surface or Ui/Box, text is Label or Icon, the pointer
# PointerArea or a control, a picture Picture, typing TextLine or TextBox,
# a canvas Drawing, an effect Effect, scrolling Scroller, a film VideoView,
# an app's icon AppIcon. Layouts, lists, loaders and animations — what lays
# out and moves, drawing nothing — are QML's. Ui/ is where the primitives
# live, built into the elements above.
PRIMITIVES = ("Rectangle", "Text", "MouseArea", "Image", "AnimatedImage", "BorderImage", "TextInput",
              "TextEdit", "TextArea", "Canvas", "MultiEffect", "ShaderEffect", "ShaderEffectSource",
              "ScrollView", "VideoOutput", "IconImage", "TextField", "ComboBox", "SpinBox")
# Qt Quick Controls' own, reached past Ui's of the same name (C.Button).
CONTROLS = ("Button", "CheckBox", "Switch", "Slider", "Label", "Menu", "MenuItem", "ToolButton",
            "RadioButton", "ProgressBar", "BusyIndicator", "Popup", "Dialog", "TabBar", "TabButton")
PRIM_RE = re.compile(r"(^|[\s:;{\[,])(?:\w+\.)?(" + "|".join(PRIMITIVES) + r")\s*\{"
                     r"|(^|[\s:;{\[,])(?:C|QQC|Controls|T)\.(" + "|".join(CONTROLS) + r")\s*\{")
for path in qml_files:
    if "/Ui/" in path:
        continue
    text = re.sub(r"//.*$", "", open(path, encoding="utf-8").read(), flags=re.M)
    for m in PRIM_RE.finditer(text):
        name = m.group(2) or m.group(4)
        line = text.count("\n", 0, m.start()) + 1
        failures.append(f"{os.path.relpath(path, repo)}:{line}: {name} drawn directly: use Ui's element")

# Text drawn outside the design system: a bare Text picks its own family,
# size and colour, where Ui/Label takes a text style (Design.font, with its
# tracking and line height). What is left is old work; the count may only
# go down — lower RAW_TEXT_MAX with it when a screen moves to Label.
RAW_TEXT_MAX = 0
raw_text = 0
for path in qml_files:
    if "/Ui/" in path:
        continue
    text = re.sub(r"//.*$", "", open(path, encoding="utf-8").read(), flags=re.M)
    raw_text += len(re.findall(r"^\s*Text\s*\{", text, flags=re.M))
print(f"Bare Text outside Ui/:        {raw_text} (at most {RAW_TEXT_MAX})")
if raw_text > RAW_TEXT_MAX:
    failures.append(f"{raw_text} bare Text outside Ui/ (at most {RAW_TEXT_MAX}): use Ui/Label")

for f in failures:
    print("FAIL " + f)
sys.exit(1 if failures else 0)
PY
