# b1air-text — minimal text and config editor. Network for the local socket
# a second start hands its files to the first window through (main.cpp).
b1air_add_app(text SOURCES main.cpp backend.cpp backend.hpp
    LIBS Qt6::Network)
