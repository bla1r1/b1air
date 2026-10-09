# B1air.Daemon — exposes the running daemon's D-Bus interface to QML, so the
# shell calls it instead of spawning `b1air-daemon <verb>` and discarding the
# exit code.
#
# A hand-written extension plugin rather than qt_add_qml_module: that produces
# a module meant to be linked into the consuming executable, and the engine
# that loads this one is quickshell's, which we do not build.
add_library(b1air-daemon-qml MODULE plugin.cpp b1airdaemon.cpp b1airdaemon.hpp
    sway_client.cpp sway_client.hpp sys_util.cpp sys_util.hpp
    ${PROJECT_SOURCE_DIR}/common/thumbs.cpp ${PROJECT_SOURCE_DIR}/common/thumbs.hpp)
target_include_directories(b1air-daemon-qml PRIVATE ${PROJECT_SOURCE_DIR}/common)
set_target_properties(b1air-daemon-qml PROPERTIES
    AUTOMOC ON
    LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/qml/B1air/Daemon
    PREFIX "lib")
target_link_libraries(b1air-daemon-qml PRIVATE Qt6::Core Qt6::Gui Qt6::Qml Qt6::Quick Qt6::DBus Qt6::Network b1air-thumbs-deps)
add_custom_command(TARGET b1air-daemon-qml POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
            ${CMAKE_CURRENT_SOURCE_DIR}/qmldir
            ${CMAKE_BINARY_DIR}/qml/B1air/Daemon/qmldir)

# Into Qt's own QML directory, so quickshell finds it with no environment
# changes. Asked of Qt rather than guessed: /usr/local is not on the default
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
# For `make install`, which is not CMake's install and has to know too.
file(WRITE ${CMAKE_BINARY_DIR}/qt-qml-dir "${B1AIR_QML_INSTALL_DIR}\n")

install(DIRECTORY ${CMAKE_BINARY_DIR}/qml/B1air DESTINATION "${B1AIR_QML_INSTALL_DIR}")
