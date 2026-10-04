# b1air-clip — reads, watches and sets the clipboard over wlr-data-control,
# in place of wl-clipboard (wl-copy, wl-paste). Plain wayland-client, as
# b1air-bg is. protocol/ holds the protocol's description, from wlroots (MIT).
pkg_check_modules(CLIP_WAYLAND REQUIRED IMPORTED_TARGET wayland-client)
find_program(CLIP_WAYLAND_SCANNER wayland-scanner REQUIRED)

set(CLIP_XML ${CMAKE_CURRENT_SOURCE_DIR}/protocol/wlr-data-control-unstable-v1.xml)
set(CLIP_GEN ${CMAKE_CURRENT_BINARY_DIR}/protocol)
file(MAKE_DIRECTORY ${CLIP_GEN})
add_custom_command(
    OUTPUT ${CLIP_GEN}/wlr-data-control-unstable-v1-client-protocol.h
           ${CLIP_GEN}/wlr-data-control-unstable-v1-protocol.c
    COMMAND ${CLIP_WAYLAND_SCANNER} client-header ${CLIP_XML} ${CLIP_GEN}/wlr-data-control-unstable-v1-client-protocol.h
    COMMAND ${CLIP_WAYLAND_SCANNER} private-code ${CLIP_XML} ${CLIP_GEN}/wlr-data-control-unstable-v1-protocol.c
    DEPENDS ${CLIP_XML}
    VERBATIM)

add_executable(b1air-clip
    main.cpp
    ${CLIP_GEN}/wlr-data-control-unstable-v1-client-protocol.h
    ${CLIP_GEN}/wlr-data-control-unstable-v1-protocol.c)
target_include_directories(b1air-clip PRIVATE ${CLIP_GEN})
target_link_libraries(b1air-clip PRIVATE PkgConfig::CLIP_WAYLAND)
b1air_warnings(b1air-clip)
install(TARGETS b1air-clip RUNTIME DESTINATION bin)
