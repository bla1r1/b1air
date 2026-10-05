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
# PREFIX is the binary directory and DESTDIR the data root under it — desktop
# entries, icons, the QML the apps search. Defaults are the per-user paths, so
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
	mkdir -p $(PREFIX)
	# Whatever CMake built, so a new app needs no edit here.
	install -m 755 $(BUILD)/bin/b1air-* $(PREFIX)/
	mkdir -p $(QMLDIR)
	rsync -a shell/qml/ $(QMLDIR)/
	# Gone from the tree, native now: the lock screen (b1air-lock) and the
	# screenshot overlay (b1air-shot).
	rm -f $(QMLDIR)/Lock.qml $(QMLDIR)/ScreenshotOverlay.qml
	# The app windows live beside their backends under apps/, and the search
	# path expects every window in one directory — so they are copied in here
	# rather than kept as a second copy in the shell tree. Overwriting, not
	# `cp -n`: a stale file in this directory shadows the installed one for
	# ever, because it is searched before /usr/share/b1air-shell/qml.
	find apps -mindepth 2 -maxdepth 2 -name '*Window.qml' \
		-exec install -m 644 {} $(QMLDIR)/ \;
	# The plugin-free Quickshell module tree the standalone apps import ahead of
	# the real one. Deliberately not under .config/b1air-shell: the `quickshell`
	# process searches there, and it must keep finding the real module.
	mkdir -p $(COMPATDIR)
	rsync -a compat/qml/ $(COMPATDIR)/
	# Desktop entries, with the binary's full path. They said `Exec=b1air-term`
	# and relied on ~/.local/bin being on PATH, which is true inside the sway
	# session and false in KDE or GNOME — where the apps did not start from the
	# menu at all. environment.d fixes PATH for systemd-started sessions; the
	# full path fixes it for everything else.
	mkdir -p $(DATADIR)/applications
	for f in apps/*/b1air-*.desktop; do \
		sed -e 's|^Exec=b1air-|Exec=$(PREFIX)/b1air-|' -e 's|^TryExec=b1air-|TryExec=$(PREFIX)/b1air-|' \
			"$$f" > $(DATADIR)/applications/$$(basename "$$f"); \
	done
	-update-desktop-database $(DATADIR)/applications >/dev/null 2>&1
	# Each app's icon, from its own directory: into the icon theme for the
	# entries' Icon=b1air-<app>, and beside the QML for the launcher and the
	# taskbar, which load them by file.
	mkdir -p $(DATADIR)/icons/hicolor/scalable/apps $(QMLDIR)/icons/apps
	install -m 644 apps/*/b1air-*.svg $(DATADIR)/icons/hicolor/scalable/apps/
	install -m 644 apps/*/b1air-*.svg $(QMLDIR)/icons/apps/
	-gtk-update-icon-cache -q -t -f $(DATADIR)/icons/hicolor >/dev/null 2>&1
	# The lock screens' fingerprint PAM file (pam/), read from here rather
	# than /etc/pam.d.
	mkdir -p $(DATADIR)/b1air/pam
	install -m 644 pam/b1air-fingerprint $(DATADIR)/b1air/pam/
	install -m 755 pam/b1air-empty-password $(DATADIR)/b1air/pam/
	# The cursor theme, built from src/cursors by src/cursors/build.py. cp -a so
	# the seventy-odd alias names stay symlinks to the fifteen drawings.
	rm -rf $(DATADIR)/icons/b1air-cursors
	cp -a ../.local/share/icons/b1air-cursors $(DATADIR)/icons/
	# The B1air.Daemon QML module goes on Qt's import path, which only root can
	# write. A per-user install leaves it to install.sh, which asks for sudo.
	@qt_qml="$$(cat $(BUILD)/qt-qml-dir 2>/dev/null)"; \
	if [ -n "$$qt_qml" ] && [ -w "$$qt_qml" ]; then \
		cp -r $(BUILD)/qml/B1air "$$qt_qml/" && echo "B1air.Daemon -> $$qt_qml"; \
	fi
	mkdir -p $(CONFDIR)/environment.d
	install -m 644 ../.config/environment.d/10-b1air-local-bin.conf $(CONFDIR)/environment.d/
	# A running shell keeps its old singletons while pages load the new files;
	# reload it so both are the installed version.
	-for p in $$(pgrep -u $$(id -u) -f "^quickshell -p $(QMLDIR)/Main.qml$$"); do \
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
