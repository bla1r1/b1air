#!/usr/bin/env bash
#
# Design system conformance and metric tracker for b1air.
#
# Measures:
#   - Design.s(<number>) literal usages (0 in the shell, src/shell/qml; the apps still have theirs)
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

qml_files = glob.glob(os.path.join(shell_dir, "**/*.qml"), recursive=True) + \
            glob.glob(os.path.join(apps_dir, "**/*.qml"), recursive=True)

s_lit_total = 0
s_lit_ui = 0
s_lit_settings = 0
s_lit_shell = 0
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
    s_matches = re.findall(r"\bDesign\.s\(\s*\d+\s*\)", clean_text)
    if s_matches:
        count = len(s_matches)
        s_lit_total += count
        if path.startswith(ui_dir):
            s_lit_ui += count
        if path.startswith(settings_dir):
            s_lit_settings += count
        if path.startswith(shell_dir_only):
            s_lit_shell += count

    # 2. Hex colors outside whitelist
    if fname not in HEX_WHITELIST:
        hex_matches = re.findall(r"#[0-9a-fA-F]{3,8}\b", clean_text)
        if hex_matches:
            for h in hex_matches:
                hex_colors.append((rel, h))

    # 3. Gradients
    grad_matches = re.findall(r"\bGradient\s*\{", clean_text)
    gradients += len(grad_matches)

    # 4. Bold font weights
    bold_matches = re.findall(r"weight:\s*Design\.weight\.bold\b", clean_text)
    bolds += len(bold_matches)

print("=== Design System Metrics ===")
print(f"Design.s(<literal>) total:   {s_lit_total}")
print(f"Design.s(<literal>) in Ui/:  {s_lit_ui}")
print(f"... in settings/:            {s_lit_settings}")
print(f"... in the shell (all):       {s_lit_shell}")
print(f"Hex colors outside themes:   {len(hex_colors)}")
print(f"Gradient declarations:       {gradients}")
print(f"Design.weight.bold usages:   {bolds}")
print("=============================")

# Criteria checks: these fail. The legacy parts were removed in one go;
# anything using them again would bring the second look back with it.
LEGACY_TYPES = ("Card", "Toggle", "Dropdown", "FormRow", "Pill", "ActionButton",
                "ButtonRow", "BarButton", "BarGroup")
LEGACY_TOKENS = r"\bDesign\.(base|mantle|crust|subtext[01]|surface[012]|overlay[012])\b" \
                r"|\bDesign\.size\.(field|ctl|action|iconBtn)\b"
failures = []
if s_lit_ui > 0:
    failures.append(f"{s_lit_ui} Design.s(<literal>) in Ui/: use the scales in Design.qml")
if s_lit_shell > 0:
    failures.append(f"{s_lit_shell} Design.s(<literal>) in src/shell/qml: use the scales in Design.qml")
for path in qml_files:
    rel = os.path.relpath(path, repo)
    text = re.sub(r"//.*$", "", open(path, encoding="utf-8").read(), flags=re.M)
    for t in LEGACY_TYPES:
        if re.search(r"(^|[^A-Za-z.])" + t + r"\s*\{", text):
            failures.append(f"{rel}: uses the removed {t}")
    for m in set(re.findall(LEGACY_TOKENS, text)):
        failures.append(f"{rel}: uses a removed Design alias")
for f in failures:
    print("FAIL " + f)
sys.exit(1 if failures else 0)
PY
