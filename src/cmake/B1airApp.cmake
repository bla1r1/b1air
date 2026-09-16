# b1air_add_app(<name> SOURCES <files...> [LIBS <targets...>])
#
# One application of the suite: builds b1air-<name> from the sources in the
# calling directory, the way every app is built — Qt Quick on Wayland, moc on,
# the shared headers in src/common on the include path. Anything beyond that
# (Multimedia, libarchive, a vendored library) goes in LIBS.
#
# The window (<Name>Window.qml), desktop entry (b1air-<name>.desktop) and icon
# (b1air-<name>.svg) sit beside the sources; `make install` picks them up from
# there, so adding an app is adding a directory and one add_subdirectory line.
function(b1air_add_app name)
    cmake_parse_arguments(ARG "" "" "SOURCES;LIBS" ${ARGN})
    set(target b1air-${name})
    add_executable(${target} ${ARG_SOURCES})
    set_target_properties(${target} PROPERTIES AUTOMOC ON)
    target_include_directories(${target} PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}
        ${PROJECT_SOURCE_DIR}/common)
    target_link_libraries(${target} PRIVATE
        Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick Qt6::WaylandClient
        Threads::Threads
        ${ARG_LIBS})
    install(TARGETS ${target} RUNTIME DESTINATION bin)
endfunction()

# The warning level the daemon side has always been built at.
function(b1air_warnings target)
    target_compile_options(${target} PRIVATE -Wall -Wextra)
endfunction()
