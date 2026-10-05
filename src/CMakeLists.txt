cmake_minimum_required(VERSION 3.20)
# The whole suite, one configure, one build tree (src/build).
#
#   daemon/      b1air-daemon, b1air-polkit-agent, b1air-secret-service and
#                the b1air-core library they and the shell share
#   shell/       b1air-shell, the Qt Quick desktop
#   qmlplugin/   B1air.Daemon, the QML module the shell's QML imports
#   apps/<app>/  one directory per application: its sources, its window QML,
#                its desktop entry and its icon. Each is its own program and
#                its own process — nothing here links one app into another.
#   common/      headers more than one program includes
#   compat/      the Quickshell stand-in the standalone Settings app hosts
#
# Kept in sync by hand with src/daemon/version.hpp's kVersion — that header is
# what the running binaries report.
project(b1air VERSION 0.2.1 LANGUAGES CXX C)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
# AUTOUIC and AUTORCC are off: there is no .ui and no .qrc file anywhere, and
# each adds a scan of every source on every build for nothing.
set(CMAKE_AUTOUIC OFF)
set(CMAKE_AUTORCC OFF)

# The old per-directory build had no build type at all, which in CMake means
# no -O flag: every Qt program of the suite shipped unoptimised, while only the
# daemon (built by hand in the Makefile with -O3) was not.
if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE Release CACHE STRING "Build type" FORCE)
endif()

# Every binary in one directory, so `make install` and the smoke test find
# them without knowing which subdirectory built which.
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)

# CMAKE_<LANG>_COMPILER_LAUNCHER rather than the RULE_LAUNCH_COMPILE property:
# that one is honoured only by the Makefile generator.
find_program(CCACHE_PROGRAM ccache)
if(CCACHE_PROGRAM)
    set(CMAKE_C_COMPILER_LAUNCHER "${CCACHE_PROGRAM}")
    set(CMAKE_CXX_COMPILER_LAUNCHER "${CCACHE_PROGRAM}")
endif()

find_package(Qt6 REQUIRED COMPONENTS Core Gui Qml QmlModels Quick WaylandClient DBus Network Multimedia)
find_package(LayerShellQt REQUIRED)
find_package(Threads REQUIRED)
find_package(PkgConfig REQUIRED)
pkg_check_modules(POLKIT_AGENT REQUIRED IMPORTED_TARGET polkit-agent-1)
pkg_check_modules(LIBARCHIVE REQUIRED IMPORTED_TARGET libarchive)
# libcrypto is the one library the suite links rather than vendors: the secret
# store encrypts with AES-256-GCM, and a hand-rolled replacement would be a
# security regression. Through pkg-config, so a machine without the headers
# fails at configure with a name to search for.
pkg_check_modules(LIBCRYPTO REQUIRED IMPORTED_TARGET libcrypto)

list(APPEND CMAKE_MODULE_PATH ${CMAKE_CURRENT_SOURCE_DIR}/cmake)
include(B1airApp)

# ── Vendored C libraries ─────────────────────────────────────────────────────
# Their own flags on purpose — upstream is not warning-clean under the
# -Wall -Wextra this project holds its own code to.

# SQLite, compiled in rather than linked against the system libsqlite3. Public
# domain, and the amalgamation is what upstream publishes for exactly this.
add_library(b1air-sqlite STATIC third_party/sqlite/sqlite3.c)
target_include_directories(b1air-sqlite SYSTEM PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}/third_party/sqlite)
target_compile_options(b1air-sqlite PRIVATE -w)
target_compile_definitions(b1air-sqlite PRIVATE
    SQLITE_THREADSAFE=1
    SQLITE_OMIT_LOAD_EXTENSION=1
    SQLITE_DQS=0
    SQLITE_DEFAULT_MEMSTATUS=0
    SQLITE_LIKE_DOESNT_MATCH_BLOBS
    SQLITE_MAX_EXPR_DEPTH=0
)
target_link_libraries(b1air-sqlite PUBLIC Threads::Threads m)

add_subdirectory(daemon)
add_subdirectory(qmlplugin)
add_subdirectory(shell)
add_subdirectory(apps)
add_subdirectory(bg)
add_subdirectory(clip)
add_subdirectory(gamma)
add_subdirectory(lock)
add_subdirectory(shot)
