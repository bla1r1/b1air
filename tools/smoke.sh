#!/usr/bin/env bash
#
# Minimal smoke tests for the b1air desktop.
#
# Not a test suite — a short list of things that have actually broken here,
# each cheap enough to run before every commit:
#
#   qml-syntax      A QML syntax error takes the entire shell down, and the
#                   symptom is a chain of "Type X unavailable" for files that
#                   are fine. It happened twice during this work; once it went
#                   unnoticed for several commits because the changes after it
#                   were all daemon-side.
#   singletons      A Services/*.qml with `pragma Singleton` that is missing
#                   from qmldir loads as an ordinary type: every reference to
#                   it silently reads undefined.
#   settings-schema Settings.set() with a key the schema does not declare warns
#                   once on stderr and does nothing. Half the settings pages had
#                   controls like that.
#   window-copies   Each app window lives in exactly one place. Five of them
#                   used to exist twice, and which copy shipped was decided by
#                   the order of two lines in install.sh — so a fix could land
#                   in the copy nobody runs, which happened.
#   ipc-targets     A toggle: command naming a widget WindowRegistry does not
#                   know opens nothing at all.
#   i18n            Every translation in src/shell/qml/Ui/i18n/*.json parses
#                   and keeps the %1, %2… of its English key: one that drops a
#                   placeholder shows text with a hole in it. Strings with no
#                   translation yet are listed, not failed — a new English
#                   string must not block a commit.
#   daemon-cli      The read-only verbs still answer.
#   shell-boot      The shell actually starts. Only when there is a Wayland
#                   session to start it in; skipped otherwise.
#
# And one that is deliberately NOT in the default run:
#
#   vendor-updates  Asks each vendored library's upstream whether there is a
#                   newer release than the one in src/third_party. It reaches
#                   the network, which everything above refuses to do — this
#                   runs before every commit and must stay fast and offline —
#                   so it has to be asked for by name:
#
#                       tools/smoke.sh vendor-updates
#
#                   Worth running now and then, and worth running deliberately
#                   for libvterm, which parses untrusted input and no longer
#                   gets the distribution's security updates.
#
# Usage: tools/smoke.sh [check ...]     (default: all)
# Exit status is the number of failed checks.

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
QML_DIRS=("$REPO/src/shell/qml" "$REPO/src/apps")

QMLLINT="$(command -v qmllint || echo /usr/lib/qt6/bin/qmllint)"

pass_count=0
fail_count=0
skip_count=0

pass() { printf '  \033[32mok\033[0m   %s\n' "$1"; pass_count=$((pass_count + 1)); }
fail() { printf '  \033[31mFAIL\033[0m %s\n' "$1"; fail_count=$((fail_count + 1)); }
skip() { printf '  \033[33mskip\033[0m %s\n' "$1"; skip_count=$((skip_count + 1)); }
head_() { printf '\n\033[1m%s\033[0m\n' "$1"; }

# ── qml-syntax ───────────────────────────────────────────────────────────────
check_qml_syntax() {
    head_ "qml-syntax"
    if [[ ! -x "$QMLLINT" ]]; then
        skip "qmllint not found; install qt6-declarative"
        return
    fi

    local files=()
    local d
    for d in "${QML_DIRS[@]}"; do
        [[ -d "$d" ]] || continue
        while IFS= read -r f; do files+=("$f"); done < <(find "$d" -name '*.qml' | sort)
    done

    # Only the [syntax] category fails the run. qmllint's other checks are
    # advice — unused imports, shadowed properties — and there are hundreds of
    # them; a smoke test that cries wolf is one nobody runs.
    local out bad=0
    out="$("$QMLLINT" "${files[@]}" 2>&1 | grep -F '[syntax]')"
    if [[ -n "$out" ]]; then
        printf '%s\n' "$out" | sed 's/^/      /'
        bad=1
    fi
    # Two declarations of the same property in one object is not a syntax
    # error to qmllint — it reports nothing and the component fails to build at
    # runtime instead. It happened while rewriting the Launchpad: an old
    # `filteredApps` survived beside its replacement, every check here passed,
    # and the only thing that would have caught it was starting the shell.
    if ! python3 - "${files[@]}" <<'PY_DUPES'; then bad=1; fi
import re, sys, os

problems = []
for path in sys.argv[1:]:
    text = open(path, encoding="utf-8").read()
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    text = re.sub(r"//.*$", "", text, flags=re.M)

    # Brace depth, not indentation: two sibling objects at the same depth are
    # allowed to declare the same name, and Design.qml has several that do —
    # `sm` is a radius in one scale component and a spacing in the next.
    # Each `{` opens an object with an identity of its own, and a duplicate is
    # only a duplicate inside one of them.
    lines = text.splitlines()
    stack = [0]
    next_id = 1
    seen = {}
    assigned = {}
    depth_of_binding = 0
    for line in lines:
        m = re.match(r"^\s*(?:readonly\s+|default\s+)?property\s+[\w.<>]+\s+(\w+)\b", line)
        if m:
            key = (stack[-1], m.group(1))
            if key in seen:
                problems.append(f"{os.path.relpath(path)}: `{m.group(1)}` is declared twice in the same object")
            seen[key] = True

        # The same *assignment* twice in one object is the other half of this,
        # and the half that actually took the shell down: "Property value set
        # multiple times" is not a parse error, so qmllint reports nothing and
        # the component fails to build at runtime. A script that added an
        # anchor to rows that already had one produced six of them at once.
        #
        # Only plain `name: value` on one line, and only outside a binding
        # block, so a JS object literal or a multi-line binding cannot look
        # like an assignment.
        a = re.match(r"^\s*([a-z_][\w.]*)\s*:\s*\S", line)
        if a and not line.rstrip().endswith("{") and depth_of_binding == 0:
            name = a.group(1)
            if name not in ("property", "signal", "function", "import"):
                key = (stack[-1], "=" + name)
                if key in assigned:
                    problems.append(
                        f"{os.path.relpath(path)}: `{name}` is set twice in the same object")
                assigned[key] = True
        # Strings are stripped so a brace inside one cannot move the depth.
        bare = re.sub(r'"[^"]*"', "", re.sub(r"'[^']*'", "", line))
        for ch in bare:
            if ch == "{":
                stack.append(next_id)
                next_id += 1
            elif ch == "}" and len(stack) > 1:
                stack.pop()

for p in sorted(set(problems)):
    print("      " + p)
sys.exit(1 if problems else 0)
PY_DUPES

    if (( bad )); then
        fail "${#files[@]} QML files, problems above"
    else
        pass "${#files[@]} QML files parse, no duplicate properties"
    fi
}

# ── singletons ───────────────────────────────────────────────────────────────
check_singletons() {
    head_ "singletons"
    python3 - "$REPO" <<'PY'
import os, re, sys
repo = sys.argv[1]
svc = os.path.join(repo, "src/shell/qml/Services")
qmldir = os.path.join(svc, "qmldir")

registered = {}
for line in open(qmldir, encoding="utf-8"):
    parts = line.split()
    if len(parts) == 4 and parts[0] == "singleton":
        registered[parts[1]] = parts[3]
    elif len(parts) == 3 and parts[0] != "module":
        registered[parts[0]] = parts[2]

problems = []
for name in sorted(os.listdir(svc)):
    if not name.endswith(".qml"):
        continue
    text = open(os.path.join(svc, name), encoding="utf-8").read()
    is_singleton = text.lstrip().startswith("pragma Singleton")
    base = name[:-4]
    if is_singleton and base not in registered:
        problems.append(f"{name} declares `pragma Singleton` but is not in qmldir")
    if base in registered and registered[base] != name:
        problems.append(f"qmldir maps {base} to {registered[base]}, expected {name}")

for base, file in sorted(registered.items()):
    if not os.path.exists(os.path.join(svc, file)):
        problems.append(f"qmldir registers {base} -> {file}, which does not exist")

for p in problems:
    print("      " + p)
sys.exit(1 if problems else 0)
PY
    # shellcheck disable=SC2181
    if [[ $? -eq 0 ]]; then pass "Services/qmldir matches the files on disk"
    else fail "Services/qmldir is out of step with the files"; fi
}

# ── imports ──────────────────────────────────────────────────────────────────
#
# qmllint parses QML without resolving types, so a file that uses a type it
# never imported passes every syntax check and then fails at runtime — as a
# whole shell, because one unresolvable type takes the root component down.
# This has happened twice: Notifications.qml using Process without
# `import Quickshell.Io`, and Main.qml using Daemon without `import
# B1air.Daemon`. Both times the shell was deployed before anyone noticed.
#
# The check is deliberately narrow: only names that can come from exactly one
# module, matched only where they are used as a type or a singleton, so it
# reports something real or nothing at all.
check_imports() {
    head_ "imports"
    python3 - "$REPO" <<'PY_IMPORTS'
import os, re, sys
repo = sys.argv[1]

# name -> the one module that provides it
PROVIDERS = {
    "Process": "Quickshell.Io",
    "FileView": "Quickshell.Io",
    "StdioCollector": "Quickshell.Io",
    "SplitParser": "Quickshell.Io",
    "JsonAdapter": "Quickshell.Io",
    "IpcHandler": "Quickshell.Io",
    "Socket": "Quickshell.Io",
    "Daemon": "B1air.Daemon",
    "PanelWindow": "Quickshell",
    "Variants": "Quickshell",
    "Quickshell": "Quickshell",
    "WlrLayershell": "Quickshell.Wayland",
    "WlrLayer": "Quickshell.Wayland",
    "UPower": "Quickshell.Services.UPower",
    "UPowerDeviceState": "Quickshell.Services.UPower",
    "Pipewire": "Quickshell.Services.Pipewire",
    "PwObjectTracker": "Quickshell.Services.Pipewire",
    "Mpris": "Quickshell.Services.Mpris",
    "NotificationServer": "Quickshell.Services.Notifications",
    "Bluetooth": "Quickshell.Bluetooth",
    "Networking": "Quickshell.Networking",
}

roots = [os.path.join(repo, "src/shell/qml"), os.path.join(repo, "src/apps")]
problems = []

for root in roots:
    for dirpath, _, files in os.walk(root):
        for name in files:
            if not name.endswith(".qml"):
                continue
            path = os.path.join(dirpath, name)
            text = open(path, encoding="utf-8").read()

            imported = set(re.findall(r"^\s*import\s+([\w.]+)", text, re.M))
            body = re.sub(r"^\s*import\s+.*$", "", text, flags=re.M)
            # Comments and string literals are not uses.
            body = re.sub(r"/\*.*?\*/", "", body, flags=re.S)
            body = re.sub(r"//.*$", "", body, flags=re.M)
            body = re.sub(r'"[^"\n]*"', '""', body)
            body = re.sub(r"'[^'\n]*'", "''", body)

            for sym, module in PROVIDERS.items():
                # `Foo {` declares one; `Foo.bar` reads a singleton.
                if not re.search(r"(?<![\w.])" + sym + r"\s*\{", body) and \
                   not re.search(r"(?<![\w.])" + sym + r"\.", body):
                    continue
                if module in imported:
                    continue
                # A local file of that name is its own provider.
                if os.path.exists(os.path.join(dirpath, sym + ".qml")):
                    continue
                rel = os.path.relpath(path, repo)
                problems.append(f"{rel}: uses {sym} without `import {module}`")

for p in sorted(set(problems)):
    print("      " + p)
sys.exit(1 if problems else 0)
PY_IMPORTS
    # shellcheck disable=SC2181
    if [[ $? -eq 0 ]]; then pass "every QML file imports what it uses"
    else fail "a QML file uses a type it never imported"; fi
}

# ── settings-schema ──────────────────────────────────────────────────────────
check_settings_schema() {
    head_ "settings-schema"
    python3 - "$REPO" <<'PY'
import os, re, sys
repo = sys.argv[1]
schema_path = os.path.join(repo, "src/shell/qml/Services/Settings.qml")
schema = open(schema_path, encoding="utf-8").read()

aliases  = set(re.findall(r'readonly property alias (\w+)\s*:', schema))
declared = set(re.findall(r'^\s+property (?:bool|int|real|string|var) (\w+)', schema, re.M))
defaults = set(re.findall(r'^\s+(\w+)\s*:', schema, re.M))

problems = []

# Every alias must have something behind it and a default to fall back on.
for key in sorted(aliases):
    if key not in declared:
        problems.append(f"Settings.{key} is aliased but `data` declares no such property")
    if key not in defaults:
        problems.append(f"Settings.{key} has no entry in the defaults object")

# Every key written anywhere must be one the schema knows.
written = set()
for root, dirs, files in os.walk(os.path.join(repo, "src")):
    if "third_party" in root or "build" in root:
        continue
    for f in files:
        if not f.endswith((".qml", ".cpp", ".hpp")):
            continue
        path = os.path.join(root, f)
        if path == schema_path:
            continue
        text = open(path, encoding="utf-8", errors="replace").read()
        for line in text.splitlines():
            # A comment is not a call site. The first run of this check flagged
            # AboutSettingsSection for a key it names only in a note explaining
            # that the key does not exist.
            code = line.split("//", 1)[0].split("*", 1)[0]
            for pattern in (r'Settings\.set\(\s*"(\w+)"', r'set_json_value\(\s*"(\w+)"'):
                for m in re.finditer(pattern, code):
                    written.add((m.group(1), os.path.relpath(path, repo)))

for key, where in sorted(written):
    if key not in aliases:
        problems.append(f'{where} writes "{key}", which the schema does not declare')

for p in problems:
    print("      " + p)
print(f"      {len(aliases)} settings declared, {len(written)} write sites checked")
sys.exit(1 if problems else 0)
PY
    if [[ $? -eq 0 ]]; then pass "every setting written is declared, and every alias has a default"
    else fail "settings schema and its callers disagree"; fi
}

# ── window-copies ────────────────────────────────────────────────────────────
check_window_copies() {
    head_ "window-copies"
    python3 - "$REPO" <<'PY'
import glob, os, sys
repo = sys.argv[1]

# Each app window lives in exactly one place: beside its backend, under
# src/apps/<app>/. Five of the seven used to exist under src/shell/qml as well,
# and which of the two duplicates actually shipped was decided by the order of
# two lines in install.sh. This check used to compare the pairs for drift; now
# it makes sure the pairs cannot come back.
problems = []
app_windows = sorted(glob.glob(os.path.join(repo, "src/apps/*/*Window.qml")))
for path in app_windows:
    twin = os.path.join(repo, "src/shell/qml", os.path.basename(path))
    if os.path.exists(twin):
        problems.append(f"{os.path.basename(path)} exists in both src/apps and src/shell/qml")

stray = sorted(glob.glob(os.path.join(repo, "src/shell/qml/*Window.qml")))
for path in stray:
    if not any(os.path.basename(path) == os.path.basename(a) for a in app_windows):
        problems.append(f"src/shell/qml/{os.path.basename(path)} is an app window in the shell tree")

for p in problems:
    print("      " + p)
print(f"      {len(app_windows)} app windows, one copy each")
sys.exit(1 if problems else 0)
PY
    if [[ $? -eq 0 ]]; then pass "every app window has exactly one copy"
    else fail "an app window exists twice"; fi
}

# ── ipc-targets ──────────────────────────────────────────────────────────────
check_ipc_targets() {
    head_ "ipc-targets"
    python3 - "$REPO" <<'PY'
import os, re, sys
repo = sys.argv[1]
registry = open(os.path.join(repo, "src/shell/qml/WindowRegistry.js"), encoding="utf-8").read()
known = set(re.findall(r'"([a-z]+)":\s*\{\s*w:', registry))

problems = []
targets = set()
for root, dirs, files in os.walk(os.path.join(repo, "src/shell")):
    if "build" in root:
        continue
    for f in files:
        if not f.endswith((".qml", ".js")):
            continue
        path = os.path.join(root, f)
        text = open(path, encoding="utf-8", errors="replace").read()
        for m in re.finditer(r'"toggle:([a-z]*):', text):
            if m.group(1):
                targets.add((m.group(1), os.path.relpath(path, repo)))

for name, where in sorted(targets):
    if name not in known:
        problems.append(f'{where} opens "{name}", which WindowRegistry does not define')

for p in problems:
    print("      " + p)
print(f"      {len(known)} widgets registered, {len(targets)} toggle targets checked")
sys.exit(1 if problems else 0)
PY
    if [[ $? -eq 0 ]]; then pass "every toggle target exists in WindowRegistry"
    else fail "a toggle command names a widget that does not exist"; fi
}

# ── daemon-cli ───────────────────────────────────────────────────────────────
check_daemon_cli() {
    head_ "daemon-cli"
    local bin="$REPO/src/build/bin/b1air-daemon"
    if [[ ! -x "$bin" ]]; then
        skip "src/build/bin/b1air-daemon not built (run: make -C src)"
        return
    fi

    local bad=0
    # Read-only verbs only: nothing here changes the running session.
    if ! "$bin" --version >/dev/null 2>&1; then
        printf '      %s\n' "--version failed"; bad=1
    fi
    if ! "$bin" stats >/dev/null 2>&1; then
        printf '      %s\n' "stats failed"; bad=1
    fi
    if ! "$bin" stats 2>/dev/null | python3 -c 'import json,sys; json.load(sys.stdin)' 2>/dev/null; then
        printf '      %s\n' "stats did not print valid JSON"; bad=1
    fi
    if (( bad )); then fail "the daemon's read-only verbs"
    else pass "--version and stats answer, stats is valid JSON"; fi
}

# ── shell-boot ───────────────────────────────────────────────────────────────
check_shell_boot() {
    head_ "shell-boot"
    if [[ -z "${WAYLAND_DISPLAY:-}" ]]; then
        skip "no WAYLAND_DISPLAY; nothing to start the shell in"
        return
    fi
    if ! command -v quickshell >/dev/null 2>&1; then
        skip "quickshell not installed"
        return
    fi

    local log
    log="$(mktemp)"
    quickshell -p "$REPO/src/shell/qml/Main.qml" >"$log" 2>&1 &
    local pid=$!
    sleep 8

    local bad=0
    if ! kill -0 "$pid" 2>/dev/null; then
        printf '      %s\n' "the shell exited within 8 seconds"; bad=1
    fi
    # PipeWire is not this project's problem and is absent on headless test
    # machines; everything else at ERROR is.
    if grep -a "ERROR" "$log" | grep -av "pipewire" | head -5 | grep -q .; then
        grep -a "ERROR" "$log" | grep -av "pipewire" | head -5 | sed 's/^/      /'
        bad=1
    fi
    kill "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    rm -f "$log"

    if (( bad )); then fail "the shell did not start cleanly"
    else pass "the shell starts and stays up with no errors"; fi
}

# ── vendor-updates ───────────────────────────────────────────────────────────
check_vendor_updates() {
    head_ "vendor-updates"
    python3 - "$REPO" <<'PY_VENDOR'
import json, os, re, sys, urllib.error, urllib.request

repo = sys.argv[1]

# The pinned version is read from each library's own README, which is where it
# is already recorded and has to be updated by hand anyway — one source of
# truth rather than a second list that can drift from it. How to ask upstream
# is the checker's business, so it lives here.
SOURCES = {
    "sqlite": (
        "https://sqlite.org/download.html",
        # The page carries a machine-readable manifest in a comment:
        #   PRODUCT,3.53.4,2026/sqlite-amalgamation-3530400.zip,...
        lambda t: max(re.findall(r"PRODUCT,([0-9.]+),[^,]*amalgamation", t),
                      key=_key, default=None),
    ),
    "nlohmann": (
        "https://api.github.com/repos/nlohmann/json/releases/latest",
        lambda t: json.loads(t).get("tag_name", "").lstrip("v") or None,
    ),
    "libvterm": (
        "https://www.leonerd.org.uk/code/libvterm/",
        lambda t: max(re.findall(r"libvterm-([0-9.]+)\.tar\.gz", t),
                      key=_key, default=None),
    ),
}


def _key(v):
    return [int(p) for p in v.split(".") if p.isdigit()]


def pinned(name):
    path = os.path.join(repo, "src/third_party", name, "README.md")
    try:
        m = re.search(r"^\* Version: \*\*([0-9.]+)\*\*", open(path, encoding="utf-8").read(),
                      re.M)
    except OSError:
        return None
    return m.group(1) if m else None


behind, unknown, current = [], [], []
for name, (url, extract) in sorted(SOURCES.items()):
    have = pinned(name)
    if not have:
        unknown.append(f"{name}: no `* Version: **x.y.z**` line in its README")
        continue
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "b1air-smoke"})
        with urllib.request.urlopen(req, timeout=15) as r:
            latest = extract(r.read().decode("utf-8", "replace"))
    except (urllib.error.URLError, OSError, ValueError, json.JSONDecodeError) as e:
        unknown.append(f"{name}: could not ask upstream ({type(e).__name__})")
        continue

    if not latest:
        unknown.append(f"{name}: upstream page did not name a version")
    elif _key(latest) > _key(have):
        behind.append(f"{name}: carrying {have}, upstream has {latest}")
    else:
        current.append(f"{name} {have}")

for line in behind:
    print("      " + line)
for line in unknown:
    print("      " + line)
if current:
    print("      current: " + ", ".join(current))

# Being behind is news, not a failure: it is a decision for whoever reads it,
# and a build that stops because someone else made a release is a build that
# gets ignored. Not being able to ask at all is not news either — this check is
# expected to be run without a network sometimes.
sys.exit(0)
PY_VENDOR
    # shellcheck disable=SC2181
    if [[ $? -eq 0 ]]; then pass "asked upstream about every vendored library"
    else fail "could not check the vendored libraries"; fi
}

check_i18n() {
    head_ "i18n"
    python3 - "$REPO" <<'PY_I18N'
import glob, json, os, re, sys
repo = sys.argv[1]
sources = glob.glob(os.path.join(repo, "src/apps/*/*.qml")) + glob.glob(os.path.join(repo, "src/shell/qml/**/*.qml"), recursive=True)
lit = r'"((?:[^"\\]|\\.)*)"'
used = set()
for f in sources:
    text = open(f, encoding="utf-8").read()
    for m in re.finditer(r'I18n\.tr\(\s*' + lit, text): used.add(m.group(1))
    for m in re.finditer(r'I18n\.trn\(\s*' + lit + r'\s*,\s*' + lit, text): used.add(m.group(2))
ph = lambda s: sorted(set(re.findall(r'%\d', s)))
problems, missing = [], {}
for path in sorted(glob.glob(os.path.join(repo, "src/shell/qml/Ui/i18n/*.json"))):
    lang = os.path.basename(path)[:-5]
    try:
        d = json.load(open(path, encoding="utf-8"))
    except ValueError as e:
        problems.append(f"{lang}.json does not parse: {e}"); continue
    for key, val in d.items():
        for form in (val if isinstance(val, list) else [val]):
            if not isinstance(form, str) or ph(form) != ph(key):
                problems.append(f"{lang}: {key!r} -> {form!r} changes the placeholders")
    missing[lang] = sorted(k for k in used if k not in d and re.search(r'[a-z]', k) and not k.startswith("Ctrl"))
for p in problems: print("      " + p)
for lang, keys in missing.items():
    if keys:
        print(f"      {lang}: {len(keys)} string(s) not translated yet")
        for k in keys[:10]: print("        " + k)
sys.exit(1 if problems else 0)
PY_I18N
    # shellcheck disable=SC2181
    if [[ $? -eq 0 ]]; then pass "translations parse and keep their placeholders"
    else fail "a translation is broken"; fi
}

# ── driver ───────────────────────────────────────────────────────────────────
ALL=(qml_syntax singletons imports settings_schema window_copies ipc_targets i18n daemon_cli shell_boot)

# Runnable by name, absent from the default run: it needs the network.
EXTRA=(vendor_updates)

to_run=()
if (( $# == 0 )); then
    to_run=("${ALL[@]}")
else
    for arg in "$@"; do to_run+=("${arg//-/_}"); done
fi

for c in "${to_run[@]}"; do
    if declare -F "check_$c" >/dev/null; then
        "check_$c"
    else
        printf '\nunknown check: %s (have: %s, plus %s)\n' "$c" "${ALL[*]}" "${EXTRA[*]}"
        fail_count=$((fail_count + 1))
    fi
done

printf '\n%d passed, %d failed, %d skipped\n' "$pass_count" "$fail_count" "$skip_count"
exit "$fail_count"
