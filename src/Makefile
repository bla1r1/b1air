# A thin front end to the CMake build in src/CMakeLists.txt, which builds
# every program of the suite into build/bin. What stays here is what CMake's
# own install does not know: where this desktop puts its QML, desktop entries,
# icons and cursor theme, and the paths it rewrites into them.
#
# The daemon, polkit agent and secret service used to be compiled here by
# hand, the latter two a second time by the shell's CMakeLists — two copies of
# each binary, built with different flags, and whichever `make install` copied
# last was the one that ran.

BUILD ?= build
JOBS ?= $(shell nproc 2>/dev/null || echo 4)
TARGET_CONTROLLER = ../tools/controller

# Where the suite is installed.
#
# PREFIX is the binary directory and DATADIR the data root — desktop entries,
# icons, the QML the apps search. Defaults are the per-user paths, so
# a developer's `make install` never needs root and never touches a system
# directory. install.sh passes the system ones:
#
#     make install PREFIX=/usr/local/bin DATADIR=/usr/share \
#         QMLDIR=/usr/share/b1air-shell/qml COMPATDIR=/usr/share/b1air-shell/qs-compat
#
# The apps were the only part of the suite that could not be installed for
# everyone: b1air-daemon and b1air-shell already went to /usr/local/bin, while
# b1air-files, -term, -git and the rest stayed in one user's home, so a second
# account on the same machine had a desktop whose applications were missing.
PREFIX ?= $(HOME)/.local/bin
DATADIR ?= $(HOME)/.local/share
QMLDIR ?= $(HOME)/.config/b1air-shell
CONFDIR ?= $(HOME)/.config
# Where b1air-settings looks for the Quickshell stand-in (compat/qs_compat.cpp,
# moduleDir): ~/.local/share/b1air-qs-compat, then /usr/share/b1air-shell/
# qs-compat. A system install has to pass the second; DATADIR/b1air-qs-compat
# under /usr/share is a directory nothing reads.
COMPATDIR ?= $(DATADIR)/b1air-qs-compat
# A staging root for packaging (packaging/arch/b1air/PKGBUILD): every file
# lands under it, while the paths written into the files — Exec= lines, the
# podsync wrapper — stay the real ones. Empty for a direct install. Set, it
# also skips what belongs to the live system and not to a package: the
# caches (pacman's hooks refresh them), the user's environment.d, reloading
# a running shell.
DESTDIR ?=

all: suite controller

# Configured once; after that CMake re-runs itself when a CMakeLists changes.
$(BUILD)/CMakeCache.txt:
	cmake -S . -B $(BUILD)

# Run as `make -jN`, the build shares make's own job slots (the leading +
# hands them down) instead of asking for its own -j, which made the inner
# make warn "-jN forced in submake: resetting jobserver mode".
suite: $(BUILD)/CMakeCache.txt
	+cmake --build $(BUILD) $(if $(findstring jobserver,$(MAKEFLAGS)),,-j$(JOBS))

controller: $(TARGET_CONTROLLER)

$(TARGET_CONTROLLER): ../tools/controller.cpp
	$(CXX) -std=c++20 -O2 -Wall -Wextra $< -o $@

# Old target names, still used by scripts and muscle memory.
daemon apps shell daemon-target shell-target: suite

# Not dependent on `suite`: install.sh and the updater build as the user and
# install with sudo, and a build step here would run as root and leave
# root-owned files in build/ for the next ordinary build to trip over.
install:
	@test -x $(BUILD)/bin/b1air-daemon || { echo "Nothing built yet: run make first." >&2; exit 1; }
	mkdir -p $(DESTDIR)$(PREFIX)
	# Whatever CMake built, so a new app needs no edit here.
	install -m 755 $(BUILD)/bin/b1air-* $(DESTDIR)$(PREFIX)/
	# The handlers Files opens Windows programs and downloaded packages with,
	# and Spotlight's software search (scripts/: shell, so nothing to build).
	install -m 755 scripts/b1air-run-windows scripts/b1air-windows scripts/b1air-install-package scripts/b1air-software \
		scripts/b1air-gamemode-hook $(DESTDIR)$(PREFIX)/
	mkdir -p $(DESTDIR)$(QMLDIR)
	# -rlpt, not -a: run as root, -a kept the checkout's owner, and the
	# system QML tree every account loads — the polkit dialog among it —
	# belonged to whoever had cloned the repository. The polkit agent will
	# not show a dialog it does not trust (not root's), so it showed none.
	rsync -rlpt shell/qml/ $(DESTDIR)$(QMLDIR)/
	# Gone from the tree, native now: the lock screen (b1air-lock) and the
	# screenshot overlay (b1air-shot).
	rm -f $(DESTDIR)$(QMLDIR)/Lock.qml $(DESTDIR)$(QMLDIR)/ScreenshotOverlay.qml
	# The app windows (and their parts, named after the app: FilesDevicePane)
	# live beside their backends under apps/, and the search
	# path expects every window in one directory — so they are copied in here
	# rather than kept as a second copy in the shell tree. Overwriting, not
	# `cp -n`: a stale file in this directory shadows the installed one for
	# ever, because it is searched before /usr/share/b1air-shell/qml.
	find apps -mindepth 2 -maxdepth 2 -name '*.qml' \
		-exec install -m 644 {} $(DESTDIR)$(QMLDIR)/ \;
	# The plugin-free Quickshell module tree the standalone apps import ahead of
	# the real one. Deliberately not under .config/b1air-shell: the `quickshell`
	# process searches there, and it must keep finding the real module.
	mkdir -p $(DESTDIR)$(COMPATDIR)
	rsync -rlpt compat/qml/ $(DESTDIR)$(COMPATDIR)/
	# What an earlier -a install left owned by a user. System trees only: a
	# `sudo make install` into someone's home must not hand it to root.
	@if [ "$$(id -u)" = 0 ]; then for d in $(DESTDIR)$(QMLDIR) $(DESTDIR)$(COMPATDIR); do \
		case "$$d" in /usr/*) chown -R root:root "$$d" ;; esac; done; fi
	# Desktop entries, with the binary's full path. They said `Exec=b1air-term`
	# and relied on ~/.local/bin being on PATH, which is true inside the sway
	# session and false in KDE or GNOME — where the apps did not start from the
	# menu at all. environment.d fixes PATH for systemd-started sessions; the
	# full path fixes it for everything else.
	mkdir -p $(DESTDIR)$(DATADIR)/applications
	for f in apps/*/b1air-*.desktop scripts/b1air-*.desktop; do \
		sed -e 's|^Exec=b1air-|Exec=$(PREFIX)/b1air-|' -e 's|^TryExec=b1air-|TryExec=$(PREFIX)/b1air-|' \
			"$$f" > $(DESTDIR)$(DATADIR)/applications/$$(basename "$$f"); \
	done
	-[ -n "$(DESTDIR)" ] || update-desktop-database $(DATADIR)/applications >/dev/null 2>&1
	# Each app's icon, from its own directory: into the icon theme for the
	# entries' Icon=b1air-<app>, and beside the QML for the launcher and the
	# taskbar, which load them by file.
	mkdir -p $(DESTDIR)$(DATADIR)/icons/hicolor/scalable/apps $(DESTDIR)$(QMLDIR)/icons/apps
	install -m 644 apps/*/b1air-*.svg $(DESTDIR)$(DATADIR)/icons/hicolor/scalable/apps/
	install -m 644 apps/*/b1air-*.svg $(DESTDIR)$(QMLDIR)/icons/apps/
	-[ -n "$(DESTDIR)" ] || gtk-update-icon-cache -q -t -f $(DATADIR)/icons/hicolor >/dev/null 2>&1
	# The lock screens' fingerprint PAM file (pam/), read from here rather
	# than /etc/pam.d.
	mkdir -p $(DESTDIR)$(DATADIR)/b1air/pam
	install -m 644 pam/b1air-fingerprint $(DESTDIR)$(DATADIR)/b1air/pam/
	install -m 755 pam/b1air-empty-password $(DESTDIR)$(DATADIR)/b1air/pam/
	# The cursor theme, built from src/cursors by src/cursors/build.py. cp -a so
	# the seventy-odd alias names stay symlinks to the fifteen drawings.
	# The icon font (tools/build-symbols.py builds it).
	mkdir -p $(DESTDIR)$(DATADIR)/fonts/b1air
	install -m 644 ../.local/share/fonts/b1air-symbols.ttf $(DESTDIR)$(DATADIR)/fonts/b1air/
	-[ -n "$(DESTDIR)" ] || fc-cache -f $(DATADIR)/fonts/b1air >/dev/null 2>&1
	rm -rf $(DESTDIR)$(DATADIR)/icons/b1air-cursors
	cp -a ../.local/share/icons/b1air-cursors $(DESTDIR)$(DATADIR)/icons/
	# The B1air.Daemon QML module goes on Qt's import path, which only root can
	# write. A per-user install leaves it to install.sh, which asks for sudo.
	# A package stages it like everything else.
	@qt_qml="$$(cat $(BUILD)/qt-qml-dir 2>/dev/null)"; \
	if [ -n "$$qt_qml" ] && [ -n "$(DESTDIR)" ]; then \
		mkdir -p "$(DESTDIR)$$qt_qml" && cp -r $(BUILD)/qml/B1air "$(DESTDIR)$$qt_qml/"; \
	elif [ -n "$$qt_qml" ] && [ -w "$$qt_qml" ]; then \
		cp -r $(BUILD)/qml/B1air "$$qt_qml/" && echo "B1air.Daemon -> $$qt_qml"; \
	fi
	# podsync (../third_party/podsync, a submodule): the iPod engine Files
	# drives through b1air-podsync. Python, so it is copied rather than built;
	# the wrapper names where, as the desktop entries name the binaries.
	@if [ -f ../third_party/podsync/podsync/cli.py ]; then \
		rm -rf $(DESTDIR)$(DATADIR)/b1air/podsync && mkdir -p $(DESTDIR)$(DATADIR)/b1air/podsync && \
		rsync -rlpt --exclude __pycache__ ../third_party/podsync/podsync $(DESTDIR)$(DATADIR)/b1air/podsync/ && \
		printf '#!/bin/sh\n# podsync, installed by b1air (src/Makefile)\nPYTHONPATH=%s/b1air/podsync$${PYTHONPATH:+:$$PYTHONPATH} exec python3 -m podsync "$$@"\n' \
			'$(DATADIR)' > $(DESTDIR)$(PREFIX)/b1air-podsync && chmod 755 $(DESTDIR)$(PREFIX)/b1air-podsync && \
		echo "podsync -> $(DESTDIR)$(DATADIR)/b1air/podsync"; \
	else echo "third_party/podsync is empty (git submodule update --init): no iPod support." >&2; fi
	# A system package does not need it: its binaries are in /usr/bin.
	@[ -n "$(DESTDIR)" ] || { mkdir -p $(CONFDIR)/environment.d && \
		install -m 644 ../.config/environment.d/10-b1air-local-bin.conf $(CONFDIR)/environment.d/; }
	# A running shell keeps its old singletons while pages load the new files;
	# reload it so both are the installed version.
	-[ -n "$(DESTDIR)" ] || for p in $$(pgrep -u $$(id -u) -f "^quickshell -p $(QMLDIR)/Main.qml$$"); do \
		quickshell ipc --pid $$p call main forceReload >/dev/null 2>&1; done

# The static checks run anywhere; shell-boot needs a Wayland session and skips
# itself without one.
smoke: suite
	../tools/smoke.sh

clean:
	rm -rf $(BUILD) $(TARGET_CONTROLLER)
	# What the hand-written daemon build and the old per-shell CMake tree left.
	rm -rf shell/build b1air-daemon b1air-polkit-agent b1air-secret-service \
		daemon/*.o daemon/*.d third_party/sqlite/sqlite3.o

.PHONY: all suite controller daemon apps shell daemon-target shell-target install smoke clean
