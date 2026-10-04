# b1air-gamma — night light over wlr-gamma-control, in place of wlsunset.
# Plain wayland-client, as b1air-clip is. protocol/ holds the protocol's
# description, from wlroots, under the permission notice inside it.
pkg_check_modules(GAMMA_WAYLAND REQUIRED IMPORTED_TARGET wayland-client)
find_program(GAMMA_WAYLAND_SCANNER wayland-scanner REQUIRED)

set(GAMMA_XML ${CMAKE_CURRENT_SOURCE_DIR}/protocol/wlr-gamma-control-unstable-v1.xml)
set(GAMMA_GEN ${CMAKE_CURRENT_BINARY_DIR}/protocol)
file(MAKE_DIRECTORY ${GAMMA_GEN})
add_custom_command(
    OUTPUT ${GAMMA_GEN}/wlr-gamma-control-unstable-v1-client-protocol.h
           ${GAMMA_GEN}/wlr-gamma-control-unstable-v1-protocol.c
    COMMAND ${GAMMA_WAYLAND_SCANNER} client-header ${GAMMA_XML} ${GAMMA_GEN}/wlr-gamma-control-unstable-v1-client-protocol.h
    COMMAND ${GAMMA_WAYLAND_SCANNER} private-code ${GAMMA_XML} ${GAMMA_GEN}/wlr-gamma-control-unstable-v1-protocol.c
    DEPENDS ${GAMMA_XML}
    VERBATIM)

add_executable(b1air-gamma
    main.cpp
    ${GAMMA_GEN}/wlr-gamma-control-unstable-v1-client-protocol.h
    ${GAMMA_GEN}/wlr-gamma-control-unstable-v1-protocol.c)
target_include_directories(b1air-gamma PRIVATE ${GAMMA_GEN})
target_link_libraries(b1air-gamma PRIVATE PkgConfig::GAMMA_WAYLAND)
b1air_warnings(b1air-gamma)
install(TARGETS b1air-gamma RUNTIME DESTINATION bin)
