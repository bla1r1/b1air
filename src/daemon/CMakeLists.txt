# The non-Qt side of the suite.
#
# b1air-core is everything the daemon, the polkit agent and the shell have in
# common, compiled once. It used to be compiled three times: by the Makefile
# for b1air-daemon, by the Makefile again for its own b1air-polkit-agent, and
# by the shell's CMakeLists for b1air-shell and a second polkit agent.
# The idle thread (idle.cpp) talks to the compositor over ext-idle-notify-v1;
# protocol/ holds its description, from wayland-protocols (MIT).
pkg_check_modules(CORE_WAYLAND REQUIRED IMPORTED_TARGET wayland-client)
find_program(CORE_WAYLAND_SCANNER wayland-scanner REQUIRED)
set(IDLE_XML ${CMAKE_CURRENT_SOURCE_DIR}/protocol/ext-idle-notify-v1.xml)
set(IDLE_GEN ${CMAKE_CURRENT_BINARY_DIR}/protocol)
file(MAKE_DIRECTORY ${IDLE_GEN})
add_custom_command(
    OUTPUT ${IDLE_GEN}/ext-idle-notify-v1-client-protocol.h
           ${IDLE_GEN}/ext-idle-notify-v1-protocol.c
    COMMAND ${CORE_WAYLAND_SCANNER} client-header ${IDLE_XML} ${IDLE_GEN}/ext-idle-notify-v1-client-protocol.h
    COMMAND ${CORE_WAYLAND_SCANNER} private-code ${IDLE_XML} ${IDLE_GEN}/ext-idle-notify-v1-protocol.c
    DEPENDS ${IDLE_XML}
    VERBATIM)

add_library(b1air-core STATIC
    ${IDLE_GEN}/ext-idle-notify-v1-client-protocol.h
    ${IDLE_GEN}/ext-idle-notify-v1-protocol.c
    idle.cpp
    fingerprint.cpp
    file_index.cpp
    backlight.cpp
    daemon_dbus.cpp
    focustime_db.cpp
    magic_mouse.cpp
    notify.cpp
    secret_store.cpp
    session_manager.cpp
    settings_manager.cpp
    sway_ipc.cpp
    system_control.cpp
    user_manager.cpp
)
target_include_directories(b1air-core PRIVATE ${IDLE_GEN})
target_include_directories(b1air-core PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${PROJECT_SOURCE_DIR}/common
    ${PROJECT_SOURCE_DIR}/third_party)
target_link_libraries(b1air-core PUBLIC
    b1air-sqlite Threads::Threads systemd PkgConfig::LIBCRYPTO PkgConfig::CORE_WAYLAND)
b1air_warnings(b1air-core)

add_executable(b1air-daemon main.cpp)
target_link_libraries(b1air-daemon PRIVATE b1air-core)
b1air_warnings(b1air-daemon)

# The polkit agent, its own process with its own lifecycle; the prompt it
# raises is drawn by the shell.
add_executable(b1air-polkit-agent polkit_agent_main.cpp)
target_link_libraries(b1air-polkit-agent PRIVATE b1air-core PkgConfig::POLKIT_AGENT)
b1air_warnings(b1air-polkit-agent)

# org.freedesktop.secrets. Needs only the store, not the rest of the core.
add_executable(b1air-secret-service secret_service_main.cpp secret_store.cpp)
target_include_directories(b1air-secret-service PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR} ${PROJECT_SOURCE_DIR}/third_party)
target_link_libraries(b1air-secret-service PRIVATE PkgConfig::LIBCRYPTO)
b1air_warnings(b1air-secret-service)

install(TARGETS b1air-daemon b1air-polkit-agent b1air-secret-service RUNTIME DESTINATION bin)
