# b1air-bg — the desktop background. One layer-shell surface per screen,
# showing the picture chosen for that screen, or for the workspace on it, and
# crossfading when that changes.
#
# Plain wayland-client, no Qt: the picture is decoded straight into a shared
# memory buffer at the size of the screen, handed to the compositor, and let
# go. At rest this process holds no picture at all — the compositor has it —
# which is the same footprint as swaybg, with the per-workspace pictures and
# the crossfade swaybg does not have. The crossfade is the compositor's too
# (wp_alpha_modifier_v1): the new picture is laid over the old one and its
# opacity stepped, so neither picture is blended here.
pkg_check_modules(WAYLAND_CLIENT REQUIRED IMPORTED_TARGET wayland-client)
pkg_check_modules(WAYLAND_PROTOCOLS REQUIRED wayland-protocols>=1.35)
pkg_get_variable(WAYLAND_PROTOCOLS_DIR wayland-protocols pkgdatadir)
find_program(WAYLAND_SCANNER wayland-scanner REQUIRED)

set(BG_PROTOCOLS
    ${CMAKE_CURRENT_SOURCE_DIR}/protocol/wlr-layer-shell-unstable-v1.xml
    ${WAYLAND_PROTOCOLS_DIR}/stable/xdg-shell/xdg-shell.xml
    ${WAYLAND_PROTOCOLS_DIR}/stable/viewporter/viewporter.xml
    ${WAYLAND_PROTOCOLS_DIR}/staging/fractional-scale/fractional-scale-v1.xml
    ${WAYLAND_PROTOCOLS_DIR}/staging/single-pixel-buffer/single-pixel-buffer-v1.xml
    ${WAYLAND_PROTOCOLS_DIR}/staging/alpha-modifier/alpha-modifier-v1.xml
)
set(BG_PROTOCOL_SOURCES)
set(BG_PROTOCOL_DIR ${CMAKE_CURRENT_BINARY_DIR}/protocol)
file(MAKE_DIRECTORY ${BG_PROTOCOL_DIR})
foreach(xml ${BG_PROTOCOLS})
    get_filename_component(name ${xml} NAME_WE)
    add_custom_command(
        OUTPUT ${BG_PROTOCOL_DIR}/${name}-client-protocol.h ${BG_PROTOCOL_DIR}/${name}-protocol.c
        COMMAND ${WAYLAND_SCANNER} client-header ${xml} ${BG_PROTOCOL_DIR}/${name}-client-protocol.h
        COMMAND ${WAYLAND_SCANNER} private-code ${xml} ${BG_PROTOCOL_DIR}/${name}-protocol.c
        DEPENDS ${xml}
        VERBATIM)
    list(APPEND BG_PROTOCOL_SOURCES
        ${BG_PROTOCOL_DIR}/${name}-client-protocol.h ${BG_PROTOCOL_DIR}/${name}-protocol.c)
endforeach()

add_executable(b1air-bg
    main.cpp
    image.cpp
    sway_ipc.cpp
    wallpaper_config.cpp
    ${BG_PROTOCOL_SOURCES}
)
target_include_directories(b1air-bg PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${BG_PROTOCOL_DIR})
target_include_directories(b1air-bg SYSTEM PRIVATE
    ${PROJECT_SOURCE_DIR}/third_party)
target_link_libraries(b1air-bg PRIVATE PkgConfig::WAYLAND_CLIENT m)
# WebP where the library is there; JPEG, PNG and the rest come from stb_image.
pkg_check_modules(WEBP IMPORTED_TARGET libwebp)
if(WEBP_FOUND)
    target_link_libraries(b1air-bg PRIVATE PkgConfig::WEBP)
    target_compile_definitions(b1air-bg PRIVATE B1AIR_HAVE_WEBP)
endif()
b1air_warnings(b1air-bg)
# stb_image is not warning-clean under -Wextra; its one translation unit is
# held to less.
set_source_files_properties(image.cpp PROPERTIES COMPILE_OPTIONS "-Wno-unused-function;-Wno-missing-field-initializers")
install(TARGETS b1air-bg RUNTIME DESTINATION bin)
