# `?=` assigns only when a variable is *undefined*, and make defines both CC and
# CXX itself, so `CXX ?= ccache g++` never took effect: every C++ file in this
# project has been compiled without the cache. Measured before the fix —
# deleting daemon/system_control.o and rebuilding it took 20 seconds, twice in a
# row, with ccache reporting no calls at all.
#
# `$(origin ...) = default` is the test that distinguishes make's own default
# from something the user set; an explicit command-line CC=/CXX= still wins.
ifeq ($(origin CXX),default)
CXX = ccache g++
endif
ifeq ($(origin CC),default)
CC = ccache gcc
endif
# -Ithird_party puts the vendored nlohmann/json.hpp ahead of the system one,
# so the build no longer needs a distribution package for a single header.
CXXFLAGS = -std=c++20 -O3 -Wall -Wextra -pthread -Idaemon -Ithird_party -Ithird_party/sqlite

# libcrypto through pkg-config rather than a bare -lcrypto.
#
# It is the one library this suite genuinely cannot vendor: the secret store
# encrypts with AES-256-GCM, and a hand-rolled replacement for that would be a
# security regression, not an independence win. SQLite is compiled in from
# third_party for exactly the opposite reason — it is self-contained, public
# domain, and upstream publishes the amalgamation for this.
#
# pkg-config at least makes it a declared dependency: the flags come from the
# installed OpenSSL instead of being guessed, and a machine without the headers
# fails here with a name to search for rather than at the link step.
#
# STATIC_CRYPTO=1 links libcrypto.a instead, for a distribution that ships one.
# Arch does not — its openssl package has only the shared objects — so this is
# an option, not the default.
CRYPTO_CFLAGS ?= $(shell pkg-config --cflags libcrypto 2>/dev/null)
ifeq ($(STATIC_CRYPTO),1)
CRYPTO_LIBS ?= -l:libcrypto.a $(shell pkg-config --libs --static libcrypto 2>/dev/null | sed 's/-lcrypto//')
else
CRYPTO_LIBS ?= $(shell pkg-config --libs libcrypto 2>/dev/null || echo -lcrypto)
endif

LDFLAGS = -lsystemd $(CRYPTO_LIBS)

# SQLite is compiled in from third_party/sqlite rather than linked against the
# system libsqlite3, so b1air-daemon carries its own copy and does not depend on
# whatever version the distribution happens to ship. The amalgamation is what
# upstream publishes for exactly this, and it is public domain.
#
# Built as C with its own flags: the amalgamation is not warning-clean under the
# -Wall -Wextra we hold our own code to, and there is no value in auditing
# upstream's warnings on every build.
SQLITE_OBJ = third_party/sqlite/sqlite3.o
SQLITE_CFLAGS = -O2 -w -DSQLITE_THREADSAFE=1 -DSQLITE_OMIT_LOAD_EXTENSION=1 \
                -DSQLITE_DQS=0 -DSQLITE_DEFAULT_MEMSTATUS=0 \
                -DSQLITE_LIKE_DOESNT_MATCH_BLOBS -DSQLITE_MAX_EXPR_DEPTH=0
POLKIT_CFLAGS ?= $(shell pkg-config --cflags polkit-agent-1 2>/dev/null)
POLKIT_LIBS ?= $(shell pkg-config --libs polkit-agent-1 2>/dev/null)

TARGET_DAEMON = b1air-daemon
TARGET_SHELL = shell/build/b1air-shell
TARGET_POLKIT = b1air-polkit-agent
TARGET_SECRET = b1air-secret-service
TARGET_CONTROLLER = ../tools/controller
# Where the suite is installed.
#
# PREFIX is the binary directory and DESTDIR the data root under it — desktop
# entries, icons, the QML the apps search. Defaults are the per-user paths, so
# a developer's `make install` never needs root and never touches a system
# directory. install.sh passes the system ones:
#
#     make install PREFIX=/usr/local/bin DATADIR=/usr/share QMLDIR=/usr/share/b1air-shell/qml
#
# The apps were the only part of the suite that could not be installed for
# everyone: b1air-daemon and b1air-shell already went to /usr/local/bin, while
# b1air-files, -term, -git and the rest stayed in one user's home, so a second
# account on the same machine had a desktop whose applications were missing.
PREFIX ?= $(HOME)/.local/bin
DATADIR ?= $(HOME)/.local/share
QMLDIR ?= $(HOME)/.config/b1air-shell
CONFDIR ?= $(HOME)/.config

DAEMON_SRCS = daemon/main.cpp daemon/daemon_dbus.cpp daemon/sway_ipc.cpp daemon/focustime_db.cpp daemon/user_manager.cpp daemon/system_control.cpp daemon/settings_manager.cpp daemon/session_manager.cpp daemon/secret_store.cpp
DAEMON_OBJS = $(DAEMON_SRCS:.cpp=.o)
POLKIT_SRCS = daemon/polkit_agent_main.cpp daemon/system_control.cpp daemon/sway_ipc.cpp daemon/focustime_db.cpp daemon/user_manager.cpp daemon/settings_manager.cpp daemon/secret_store.cpp
POLKIT_OBJS = $(POLKIT_SRCS:.cpp=.o)
SECRET_SRCS = daemon/secret_service_main.cpp daemon/secret_store.cpp
SECRET_OBJS = $(SECRET_SRCS:.cpp=.o)

all: daemon-target polkit-target secret-target shell-target controller

daemon-target: $(TARGET_DAEMON)

polkit-target: $(TARGET_POLKIT)

secret-target: $(TARGET_SECRET)

$(TARGET_DAEMON): $(DAEMON_OBJS) $(SQLITE_OBJ)
	$(CXX) $(CXXFLAGS) -o $@ $^ $(LDFLAGS)

$(TARGET_POLKIT): $(POLKIT_OBJS) $(SQLITE_OBJ)
	$(CXX) $(CXXFLAGS) $(POLKIT_CFLAGS) -o $@ $^ $(LDFLAGS) $(POLKIT_LIBS)

$(TARGET_SECRET): $(SECRET_OBJS)
	$(CXX) $(CXXFLAGS) -o $@ $^ $(CRYPTO_LIBS)

$(SQLITE_OBJ): third_party/sqlite/sqlite3.c
	$(CC) $(SQLITE_CFLAGS) -c $< -o $@

# -MMD -MP writes a .d file beside each object listing the headers it included,
# and the -include below feeds those back to make. Without them a header change
# rebuilt nothing: editing proc_util.hpp or system_control.hpp left every object
# that includes it untouched, make reported success, and the binary that came
# out was the old one. That is not a theoretical hazard — it happened during
# this work, and the only symptom was a fix that appeared not to work.
daemon/%.o: daemon/%.cpp
	$(CXX) $(CXXFLAGS) $(CRYPTO_CFLAGS) -MMD -MP $(if $(filter daemon/polkit_agent_main.cpp,$<),$(POLKIT_CFLAGS),) -c $< -o $@

-include $(DAEMON_OBJS:.o=.d) $(POLKIT_OBJS:.o=.d) $(SECRET_OBJS:.o=.d)

shell-target:
	cmake -B shell/build shell
	cmake --build shell/build -j$$(nproc 2>/dev/null || echo 4)

controller: $(TARGET_CONTROLLER)

$(TARGET_CONTROLLER): ../tools/controller.cpp
	$(CXX) -std=c++20 -O2 -Wall -Wextra $< -o $@

daemon: daemon-target
apps: shell-target
shell: shell-target

install: daemon-target polkit-target secret-target shell-target
	mkdir -p $(PREFIX)
	# ponytail: install whatever cmake built, so new apps need no edit here
	for f in shell/build/b1air-*; do test -x "$$f" && install -m 755 "$$f" $(PREFIX)/ || true; done
	install -m 755 $(TARGET_DAEMON) $(PREFIX)/$(TARGET_DAEMON)
	install -m 755 $(TARGET_POLKIT) $(PREFIX)/$(TARGET_POLKIT)
	install -m 755 $(TARGET_SECRET) $(PREFIX)/$(TARGET_SECRET)
	mkdir -p $(QMLDIR)
	rsync -a shell/qml/ $(QMLDIR)/
	# The app windows live beside their backends under apps/, and the search
	# path expects every window in one directory — so they are copied in here
	# rather than kept as a second copy in the shell tree. Overwriting, not
	# `cp -n`: a stale file in this directory shadows the installed one for
	# ever, because it is searched before /usr/share/b1air-shell/qml.
	find apps -maxdepth 2 -name '*Window.qml' \
		-exec install -m 644 {} $(QMLDIR)/ \;
	# The plugin-free Quickshell module tree the standalone apps import ahead of
	# the real one. Deliberately not under .config/b1air-shell: the `quickshell`
	# process searches there, and it must keep finding the real module.
	mkdir -p $(DATADIR)/b1air-qs-compat
	rsync -a compat/qml/ $(DATADIR)/b1air-qs-compat/
	# Desktop entries, with the binary's full path. They said `Exec=b1air-term`
	# and relied on ~/.local/bin being on PATH, which is true inside the sway
	# session and false in KDE or GNOME — where the apps did not start from the
	# menu at all. environment.d fixes PATH for systemd-started sessions; the
	# full path fixes it for everything else.
	mkdir -p $(DATADIR)/applications
	for f in ../.local/share/applications/b1air-*.desktop; do \
		sed -e 's|^Exec=b1air-|Exec=$(PREFIX)/b1air-|' -e 's|^TryExec=b1air-|TryExec=$(PREFIX)/b1air-|' \
			"$$f" > $(DATADIR)/applications/$$(basename "$$f"); \
	done
	-update-desktop-database $(DATADIR)/applications >/dev/null 2>&1
	# The suite's own icons, looked up by the entries' Icon=b1air-<app>. An SVG
	# dropped in with the same name replaces one at the next install.
	mkdir -p $(DATADIR)/icons/hicolor/scalable/apps
	install -m 644 ../.local/share/icons/hicolor/scalable/apps/b1air-*.svg \
		$(DATADIR)/icons/hicolor/scalable/apps/
	-gtk-update-icon-cache -q -t -f $(DATADIR)/icons/hicolor >/dev/null 2>&1
	# The cursor theme, built from src/cursors by src/cursors/build.py. cp -a so
	# the seventy-odd alias names stay symlinks to the fifteen drawings.
	rm -rf $(DATADIR)/icons/b1air-cursors
	cp -a ../.local/share/icons/b1air-cursors $(DATADIR)/icons/
	mkdir -p $(CONFDIR)/environment.d
	install -m 644 ../.config/environment.d/10-b1air-local-bin.conf $(CONFDIR)/environment.d/

# The static checks run anywhere; shell-boot needs a Wayland session and skips
# itself without one.
smoke: daemon-target
	../tools/smoke.sh

clean:
	rm -f $(DAEMON_OBJS) $(SQLITE_OBJ) $(POLKIT_OBJS) $(SECRET_OBJS) $(TARGET_DAEMON) $(TARGET_POLKIT) $(TARGET_SECRET) $(TARGET_CONTROLLER)
	rm -f $(DAEMON_OBJS:.o=.d) $(POLKIT_OBJS:.o=.d) $(SECRET_OBJS:.o=.d)
	rm -rf shell/build

.PHONY: all daemon-target polkit-target secret-target shell-target controller daemon apps shell install smoke clean
