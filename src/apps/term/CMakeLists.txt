# b1air-term — terminal emulator.
#
# libvterm compiled in from third_party rather than linked against the system
# package, the same treatment SQLite gets: it was the last thing the terminal
# could not start without. Its own flags — upstream is not warning-clean under
# -Wall -Wextra.
set(VTERM ${PROJECT_SOURCE_DIR}/third_party/libvterm)
add_library(b1air-vterm STATIC
    ${VTERM}/src/encoding.c
    ${VTERM}/src/keyboard.c
    ${VTERM}/src/mouse.c
    ${VTERM}/src/parser.c
    ${VTERM}/src/pen.c
    ${VTERM}/src/screen.c
    ${VTERM}/src/state.c
    ${VTERM}/src/unicode.c
    ${VTERM}/src/vterm.c
)
target_include_directories(b1air-vterm SYSTEM PUBLIC ${VTERM}/include)
target_include_directories(b1air-vterm PRIVATE ${VTERM}/src)
target_compile_options(b1air-vterm PRIVATE -w)

b1air_add_app(term
    SOURCES main.cpp terminal_item.cpp terminal_item.hpp
    LIBS b1air-vterm util)
