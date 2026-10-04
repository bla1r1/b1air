# b1air-lock — the lock screen when the shell's own (Lock.qml) cannot run, in
# place of swaylock. Plain wayland-client with ext-session-lock-v1 (protocol/,
# from wayland-protocols, MIT), cairo to draw, xkbcommon for the keys, PAM to
# check the password; b1air-bg's decoder for the wallpaper and b1air-core for
# which wallpaper and which language.
pkg_check_modules(LOCK_DEPS REQUIRED IMPORTED_TARGET wayland-client cairo xkbcommon)
# PAM by its library and header, not pkg-config: Debian's pam.pc requires
# audit.pc, which only libaudit-dev has.
find_library(PAM_LIBRARY pam REQUIRED)
find_path(PAM_INCLUDE_DIR security/pam_appl.h REQUIRED)
# pam_start_confdir (Linux-PAM 1.4): the fingerprint conversation reads the
# suite's own PAM file. Without it, b1air-lock takes the password only.
include(CheckSymbolExists)
set(CMAKE_REQUIRED_LIBRARIES ${PAM_LIBRARY})
set(CMAKE_REQUIRED_INCLUDES ${PAM_INCLUDE_DIR})
check_symbol_exists(pam_start_confdir "security/pam_appl.h" B1AIR_HAVE_PAM_CONFDIR)
unset(CMAKE_REQUIRED_LIBRARIES)
unset(CMAKE_REQUIRED_INCLUDES)
find_program(LOCK_WAYLAND_SCANNER wayland-scanner REQUIRED)

set(LOCK_XML ${CMAKE_CURRENT_SOURCE_DIR}/protocol/ext-session-lock-v1.xml)
set(LOCK_GEN ${CMAKE_CURRENT_BINARY_DIR}/protocol)
file(MAKE_DIRECTORY ${LOCK_GEN})
add_custom_command(
    OUTPUT ${LOCK_GEN}/ext-session-lock-v1-client-protocol.h
           ${LOCK_GEN}/ext-session-lock-v1-protocol.c
    COMMAND ${LOCK_WAYLAND_SCANNER} client-header ${LOCK_XML} ${LOCK_GEN}/ext-session-lock-v1-client-protocol.h
    COMMAND ${LOCK_WAYLAND_SCANNER} private-code ${LOCK_XML} ${LOCK_GEN}/ext-session-lock-v1-protocol.c
    DEPENDS ${LOCK_XML}
    VERBATIM)

add_executable(b1air-lock
    main.cpp
    ${PROJECT_SOURCE_DIR}/bg/image.cpp
    ${LOCK_GEN}/ext-session-lock-v1-client-protocol.h
    ${LOCK_GEN}/ext-session-lock-v1-protocol.c)
target_include_directories(b1air-lock PRIVATE ${LOCK_GEN} ${PROJECT_SOURCE_DIR}/bg ${PAM_INCLUDE_DIR})
target_include_directories(b1air-lock SYSTEM PRIVATE ${PROJECT_SOURCE_DIR}/third_party)
target_link_libraries(b1air-lock PRIVATE b1air-core PkgConfig::LOCK_DEPS ${PAM_LIBRARY} m)
pkg_check_modules(LOCK_WEBP IMPORTED_TARGET libwebp)
if(LOCK_WEBP_FOUND)
    target_link_libraries(b1air-lock PRIVATE PkgConfig::LOCK_WEBP)
    target_compile_definitions(b1air-lock PRIVATE B1AIR_HAVE_WEBP)
endif()
if(B1AIR_HAVE_PAM_CONFDIR)
    target_compile_definitions(b1air-lock PRIVATE B1AIR_HAVE_PAM_CONFDIR)
endif()
b1air_warnings(b1air-lock)
# As in bg/: stb_image is not warning-clean under -Wextra.
set_source_files_properties(${PROJECT_SOURCE_DIR}/bg/image.cpp TARGET_DIRECTORY b1air-lock
    PROPERTIES COMPILE_OPTIONS "-Wno-unused-function;-Wno-missing-field-initializers")
install(TARGETS b1air-lock RUNTIME DESTINATION bin)
