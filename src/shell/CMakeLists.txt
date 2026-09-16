# b1air-shell — the desktop: top bar, launcher, popups, lock screen. Hosts the
# QML under qml/ in Quickshell and serves the daemon's D-Bus interface.
add_executable(b1air-shell
    main.cpp
    b1air_bridge.cpp
    dbus_adaptor.cpp
)
set_target_properties(b1air-shell PROPERTIES AUTOMOC ON)
target_include_directories(b1air-shell PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}
    ${PROJECT_SOURCE_DIR}/common)
target_link_libraries(b1air-shell PRIVATE
    b1air-core
    Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick Qt6::WaylandClient Qt6::DBus
    LayerShellQt::Interface
)
install(TARGETS b1air-shell RUNTIME DESTINATION bin)
