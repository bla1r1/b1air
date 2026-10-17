# b1air-term — terminal emulator.
#
# libvterm, the terminal state machine, is the distribution's package: it
# parses whatever a program in the terminal prints, so it is the library
# here most in need of the distribution's security fixes.
pkg_check_modules(VTERM REQUIRED IMPORTED_TARGET vterm>=0.3)

b1air_add_app(term
    SOURCES main.cpp terminal_item.cpp terminal_item.hpp
    LIBS PkgConfig::VTERM util)
