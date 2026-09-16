# b1air-settings — the shell's Settings pages, hosted without quickshell. The
# pages are the shell's own QML; src/compat stands in for the Quickshell types
# they import, so this app needs neither quickshell nor the shell running.
b1air_add_app(settings
    SOURCES main.cpp
            ${PROJECT_SOURCE_DIR}/compat/qs_compat.cpp
            ${PROJECT_SOURCE_DIR}/compat/qs_compat.hpp
            ${PROJECT_SOURCE_DIR}/compat/qs_services.cpp
            ${PROJECT_SOURCE_DIR}/compat/qs_services.hpp
    LIBS Qt6::DBus)
target_include_directories(b1air-settings PRIVATE ${PROJECT_SOURCE_DIR}/compat)
