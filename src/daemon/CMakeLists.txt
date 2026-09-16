# The non-Qt side of the suite.
#
# b1air-core is everything the daemon, the polkit agent and the shell have in
# common, compiled once. It used to be compiled three times: by the Makefile
# for b1air-daemon, by the Makefile again for its own b1air-polkit-agent, and
# by the shell's CMakeLists for b1air-shell and a second polkit agent.
add_library(b1air-core STATIC
    daemon_dbus.cpp
    focustime_db.cpp
    secret_store.cpp
    session_manager.cpp
    settings_manager.cpp
    sway_ipc.cpp
    system_control.cpp
    user_manager.cpp
)
target_include_directories(b1air-core PUBLIC
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${PROJECT_SOURCE_DIR}/third_party)
target_link_libraries(b1air-core PUBLIC
    b1air-sqlite Threads::Threads systemd PkgConfig::LIBCRYPTO)
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
