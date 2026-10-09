# b1air-view — pictures shown, films and music played, in one window.
b1air_add_app(view SOURCES main.cpp view_backend.cpp view_backend.hpp
    ${PROJECT_SOURCE_DIR}/common/thumbs.cpp ${PROJECT_SOURCE_DIR}/common/thumbs.hpp
    LIBS Qt6::Multimedia b1air-thumbs-deps)
