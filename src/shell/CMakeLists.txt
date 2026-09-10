cmake_minimum_required(VERSION 3.20)
# Kept in sync by hand with src/daemon/version.hpp's kVersion — that header is
# the single source of truth the running binaries actually report; this is
# just so packaging/build metadata (cmake --version output, etc.) agrees.
project(b1air-shell VERSION 0.1.0 LANGUAGES CXX C)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)
# AUTOUIC and AUTORCC are off: this project has no .ui and no .qrc file, and
# each of them adds a scan of every source on every build for nothing.
set(CMAKE_AUTOUIC OFF)
set(CMAKE_AUTORCC OFF)

# CMAKE_<LANG>_COMPILER_LAUNCHER rather than the RULE_LAUNCH_COMPILE global
# property this replaces: that property is honoured only by the Makefile
# generator, so configuring with Ninja — or anything else — silently lost the
# cache.
find_program(CCACHE_PROGRAM ccache)
if(CCACHE_PROGRAM)
    set(CMAKE_C_COMPILER_LAUNCHER "${CCACHE_PROGRAM}")
    set(CMAKE_CXX_COMPILER_LAUNCHER "${CCACHE_PROGRAM}")
endif()

find_package(Qt6 REQUIRED COMPONENTS Core Gui Qml QmlModels Quick WaylandClient DBus Network)
find_package(LayerShellQt REQUIRED)
find_package(Threads REQUIRED)
find_package(PkgConfig REQUIRED)
pkg_check_modules(POLKIT_AGENT REQUIRED IMPORTED_TARGET polkit-agent-1)
pkg_check_modules(LIBARCHIVE REQUIRED IMPORTED_TARGET libarchive)
# Through pkg-config rather than a bare `crypto` link name: the flags come from
# the installed OpenSSL, and a machine without the headers fails at configure
# with a name to search for instead of at the link step. See src/Makefile for
# why this one library is not vendored the way SQLite is.
pkg_check_modules(LIBCRYPTO REQUIRED IMPORTED_TARGET libcrypto)

set(SOURCES
    main.cpp
    b1air_bridge.cpp
    dbus_adaptor.cpp
    ../daemon/daemon_dbus.cpp
    ../daemon/sway_ipc.cpp
    ../daemon/system_control.cpp
    ../daemon/user_manager.cpp
    ../daemon/focustime_db.cpp
    ../daemon/settings_manager.cpp
    ../daemon/session_manager.cpp
    ../daemon/secret_store.cpp
)

# SQLite compiled in from third_party rather than linked against the system
# libsqlite3, so the binaries carry their own copy. Built once as an OBJECT
# library and reused: the amalgamation is 9.5 MB of C and two targets need it.
#
# Its own flags on purpose — the amalgamation is not warning-clean under the
# -Wall -Wextra this project holds its own code to, and upstream's warnings are
# not ours to audit on every build.
add_library(b1air-sqlite OBJECT ${CMAKE_CURRENT_SOURCE_DIR}/../third_party/sqlite/sqlite3.c)
target_include_directories(b1air-sqlite PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/../third_party
    ${CMAKE_CURRENT_SOURCE_DIR}/../third_party/sqlite)
target_compile_options(b1air-sqlite PRIVATE -w)
target_compile_definitions(b1air-sqlite PRIVATE
    SQLITE_THREADSAFE=1
    SQLITE_OMIT_LOAD_EXTENSION=1
    SQLITE_DQS=0
    SQLITE_DEFAULT_MEMSTATUS=0
    SQLITE_LIKE_DOESNT_MATCH_BLOBS
    SQLITE_MAX_EXPR_DEPTH=0
)

add_executable(b1air-shell ${SOURCES} $<TARGET_OBJECTS:b1air-sqlite>)

target_include_directories(b1air-shell PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/..
    ${CMAKE_CURRENT_SOURCE_DIR}/../daemon
    ${CMAKE_CURRENT_SOURCE_DIR}/../third_party
    ${CMAKE_CURRENT_SOURCE_DIR}/../third_party/sqlite
)

target_link_libraries(b1air-shell PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
    Qt6::WaylandClient
    Qt6::DBus
    LayerShellQt::Interface
    Threads::Threads
    systemd
    PkgConfig::LIBCRYPTO
)

# Separate user-session Polkit agent process. The graphical prompt remains in
# QML, while the long-running agent has an independent lifecycle.
add_executable(b1air-polkit-agent
    ../daemon/polkit_agent_main.cpp
    ../daemon/system_control.cpp
    ../daemon/sway_ipc.cpp
    ../daemon/focustime_db.cpp
    ../daemon/user_manager.cpp
    ../daemon/settings_manager.cpp
    ../daemon/secret_store.cpp
    $<TARGET_OBJECTS:b1air-sqlite>
)
target_include_directories(b1air-polkit-agent PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/../daemon
    ${CMAKE_CURRENT_SOURCE_DIR}/../third_party
    ${CMAKE_CURRENT_SOURCE_DIR}/../third_party/sqlite
)
target_link_libraries(b1air-polkit-agent PRIVATE Threads::Threads systemd PkgConfig::LIBCRYPTO PkgConfig::POLKIT_AGENT)

add_executable(b1air-secret-service
    ../daemon/secret_service_main.cpp
    ../daemon/secret_store.cpp
)
target_include_directories(b1air-secret-service PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/../daemon)
target_link_libraries(b1air-secret-service PRIVATE PkgConfig::LIBCRYPTO)

# ── b1air-files (Native File Manager & Gallery) ──────────────────────────────
add_executable(b1air-files
    ../apps/files/main.cpp
    ../apps/files/backend.cpp
    ../apps/files/backend.hpp
)

target_include_directories(b1air-files PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/../apps/files
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/..
)

target_link_libraries(b1air-files PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
    Qt6::WaylandClient
    Threads::Threads
    PkgConfig::LIBARCHIVE
)

# ── b1air-monitor (Native Activity Monitor & Task Manager) ───────────────────
add_executable(b1air-monitor
    ../apps/monitor/main.cpp
    ../apps/monitor/backend.cpp
    ../apps/monitor/backend.hpp
)

target_include_directories(b1air-monitor PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/../apps/monitor
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/..
)

target_link_libraries(b1air-monitor PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
    Qt6::WaylandClient
    Threads::Threads
)

# ── b1air-text (Native Minimal Text & Config Editor) ─────────────────────────
add_executable(b1air-text
    ../apps/text/main.cpp
    ../apps/text/backend.cpp
    ../apps/text/backend.hpp
)

target_include_directories(b1air-text PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/../apps/text
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/..
)

target_link_libraries(b1air-text PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
    Qt6::WaylandClient
    Threads::Threads
)

# ── b1air-settings (the desktop's settings panel, hosted without quickshell) ──
qt_wrap_cpp(B1AIR_SETTINGS_MOC ../compat/qs_compat.hpp ../compat/qs_services.hpp)
add_executable(b1air-settings
    ../apps/settings/main.cpp
    ../compat/qs_compat.cpp
    ../compat/qs_services.cpp
    ${B1AIR_SETTINGS_MOC}
)
target_include_directories(b1air-settings PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/../apps/settings
    ${CMAKE_CURRENT_SOURCE_DIR}/../compat
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/..
)
target_link_libraries(b1air-settings PRIVATE
    Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick Qt6::WaylandClient Qt6::DBus Threads::Threads)

# ── b1air-term (Native Terminal Emulator) ────────────────────────────────────
#
# libvterm compiled in from third_party rather than linked against the system
# package, the same treatment SQLite gets above and for the same reason: it was
# the last thing the terminal could not start without. Nine C files, and its own
# flags — upstream is not warning-clean under this project's -Wall -Wextra.
add_library(b1air-vterm OBJECT
    ${CMAKE_CURRENT_SOURCE_DIR}/../third_party/libvterm/src/encoding.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../third_party/libvterm/src/keyboard.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../third_party/libvterm/src/mouse.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../third_party/libvterm/src/parser.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../third_party/libvterm/src/pen.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../third_party/libvterm/src/screen.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../third_party/libvterm/src/state.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../third_party/libvterm/src/unicode.c
    ${CMAKE_CURRENT_SOURCE_DIR}/../third_party/libvterm/src/vterm.c
)
target_include_directories(b1air-vterm PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/../third_party/libvterm/include
    ${CMAKE_CURRENT_SOURCE_DIR}/../third_party/libvterm/src)
target_compile_options(b1air-vterm PRIVATE -w)

qt_wrap_cpp(B1AIR_TERM_MOC ../apps/term/terminal_item.hpp)
add_executable(b1air-term
    ../apps/term/main.cpp
    ../apps/term/terminal_item.cpp
    ../apps/term/terminal_item.hpp
    ${B1AIR_TERM_MOC}
    $<TARGET_OBJECTS:b1air-vterm>
)

target_include_directories(b1air-term PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/../third_party/libvterm/include
    ${CMAKE_CURRENT_SOURCE_DIR}/../apps/term
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/..
)

target_link_libraries(b1air-term PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
    Qt6::WaylandClient
    Threads::Threads
    util
)

# ── b1air-view (Native Lightweight Image & Media Viewer) ──────────────────────
add_executable(b1air-view
    ../apps/view/main.cpp
    ../apps/view/view_backend.cpp
    ../apps/view/view_backend.hpp
)

target_include_directories(b1air-view PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/../apps/view
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/..
)

target_link_libraries(b1air-view PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
    Qt6::WaylandClient
    Threads::Threads
)

# ── b1air-notes (Native Markdown Scratchpad with Obsidian & Notion Sync) ──────
add_executable(b1air-notes
    ../apps/notes/main.cpp
    ../apps/notes/notes_backend.cpp
    ../apps/notes/notes_backend.hpp
)

target_include_directories(b1air-notes PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/../apps/notes
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/..
)

target_link_libraries(b1air-notes PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
    Qt6::WaylandClient
    Qt6::Network
    Threads::Threads
)

# ── b1air-git (Native Visual Git & Diff Tool) ─────────────────────────────────
add_executable(b1air-git
    ../apps/git/main.cpp
    ../apps/git/git_backend.cpp
    ../apps/git/git_backend.hpp
)

target_include_directories(b1air-git PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/../apps/git
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${CMAKE_CURRENT_SOURCE_DIR}/..
)

target_link_libraries(b1air-git PRIVATE
    Qt6::Core
    Qt6::Gui
    Qt6::Qml
    Qt6::Quick
    Qt6::WaylandClient
    Threads::Threads
)

install(TARGETS b1air-shell b1air-polkit-agent b1air-secret-service b1air-files b1air-monitor b1air-text b1air-settings b1air-term b1air-view b1air-notes b1air-git DESTINATION /usr/local/bin)
install(DIRECTORY qml/ DESTINATION /usr/local/share/b1air-shell/qml)
# The plugin-free module tree the standalone apps import ahead of the real
# Quickshell. Never installed where the shell searches.
install(DIRECTORY ../compat/qml/ DESTINATION /usr/local/share/b1air-shell/qs-compat)

# ── B1air.Daemon QML module ──────────────────────────────────────────────────
# Exposes the running daemon's D-Bus interface to QML, so the shell can call it
# without spawning `b1air-daemon <verb>` and discarding the exit code.
#
# A hand-written extension plugin rather than qt_add_qml_module: that produces
# a module meant to be linked into the consuming executable, which is exactly
# why quickshell cannot lend its own types to other programs. quickshell hosts
# our QML, so this has to be loadable from disk by an engine we do not build.
add_library(b1air-daemon-qml MODULE
    ../qmlplugin/plugin.cpp
    ../qmlplugin/b1airdaemon.cpp
    ../qmlplugin/b1airdaemon.hpp
)

set_target_properties(b1air-daemon-qml PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/qml/B1air/Daemon
    PREFIX "lib"
)

target_include_directories(b1air-daemon-qml PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/../qmlplugin)
target_link_libraries(b1air-daemon-qml PRIVATE Qt6::Core Qt6::Qml Qt6::DBus)

add_custom_command(TARGET b1air-daemon-qml POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
            ${CMAKE_CURRENT_SOURCE_DIR}/../qmlplugin/qmldir
            ${CMAKE_CURRENT_BINARY_DIR}/qml/B1air/Daemon/qmldir)

# Into the system QML path so quickshell finds it with no environment changes.
# Ask Qt where that is rather than guessing: /usr/local is not on the default
# import path, so installing there would build a module nothing can import.
if(NOT B1AIR_QML_INSTALL_DIR)
    get_target_property(_b1air_qmake Qt6::qmake IMPORTED_LOCATION)
    if(_b1air_qmake)
        execute_process(COMMAND "${_b1air_qmake}" -query QT_INSTALL_QML
                        OUTPUT_VARIABLE B1AIR_QML_INSTALL_DIR
                        OUTPUT_STRIP_TRAILING_WHITESPACE
                        ERROR_QUIET)
    endif()
endif()
if(NOT B1AIR_QML_INSTALL_DIR)
    set(B1AIR_QML_INSTALL_DIR "/usr/lib/qt6/qml")
endif()
message(STATUS "B1air.Daemon QML module -> ${B1AIR_QML_INSTALL_DIR}")

install(DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/qml/B1air
        DESTINATION "${B1AIR_QML_INSTALL_DIR}")
