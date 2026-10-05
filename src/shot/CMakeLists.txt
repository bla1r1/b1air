# b1air-shot — choosing a region to capture, record or read QR codes from, in
# place of ScreenshotOverlay.qml (a Quickshell process per press of Print).
# wayland-client with wlr-layer-shell, cairo, xkbcommon; b1air-core for the
# settings, the palette, the translations and the QR scan.
pkg_check_modules(SHOT_DEPS REQUIRED IMPORTED_TARGET wayland-client wayland-cursor cairo xkbcommon)
find_program(SHOT_WAYLAND_SCANNER wayland-scanner REQUIRED)

set(SHOT_XML ${PROJECT_SOURCE_DIR}/bg/protocol/wlr-layer-shell-unstable-v1.xml)
set(SHOT_GEN ${CMAKE_CURRENT_BINARY_DIR}/protocol)
file(MAKE_DIRECTORY ${SHOT_GEN})
add_custom_command(
    OUTPUT ${SHOT_GEN}/wlr-layer-shell-unstable-v1-client-protocol.h
           ${SHOT_GEN}/wlr-layer-shell-unstable-v1-protocol.c
    COMMAND ${SHOT_WAYLAND_SCANNER} client-header ${SHOT_XML} ${SHOT_GEN}/wlr-layer-shell-unstable-v1-client-protocol.h
    COMMAND ${SHOT_WAYLAND_SCANNER} private-code ${SHOT_XML} ${SHOT_GEN}/wlr-layer-shell-unstable-v1-protocol.c
    DEPENDS ${SHOT_XML}
    VERBATIM)
# The layer-shell header refers to xdg_popup; its interface comes from xdg-shell.
pkg_get_variable(SHOT_PROTOCOLS_DIR wayland-protocols pkgdatadir)
set(SHOT_XDG ${SHOT_PROTOCOLS_DIR}/stable/xdg-shell/xdg-shell.xml)
add_custom_command(
    OUTPUT ${SHOT_GEN}/xdg-shell-client-protocol.h ${SHOT_GEN}/xdg-shell-protocol.c
    COMMAND ${SHOT_WAYLAND_SCANNER} client-header ${SHOT_XDG} ${SHOT_GEN}/xdg-shell-client-protocol.h
    COMMAND ${SHOT_WAYLAND_SCANNER} private-code ${SHOT_XDG} ${SHOT_GEN}/xdg-shell-protocol.c
    DEPENDS ${SHOT_XDG}
    VERBATIM)

add_executable(b1air-shot
    main.cpp
    ${SHOT_GEN}/wlr-layer-shell-unstable-v1-client-protocol.h
    ${SHOT_GEN}/wlr-layer-shell-unstable-v1-protocol.c
    ${SHOT_GEN}/xdg-shell-client-protocol.h
    ${SHOT_GEN}/xdg-shell-protocol.c)
target_include_directories(b1air-shot PRIVATE ${SHOT_GEN} ${PROJECT_SOURCE_DIR}/common)
target_include_directories(b1air-shot SYSTEM PRIVATE ${PROJECT_SOURCE_DIR}/third_party)
target_link_libraries(b1air-shot PRIVATE b1air-core PkgConfig::SHOT_DEPS m)
b1air_warnings(b1air-shot)
install(TARGETS b1air-shot RUNTIME DESTINATION bin)
