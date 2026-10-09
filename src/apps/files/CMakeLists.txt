# b1air-files — file manager and gallery; libarchive for browsing archives.
b1air_add_app(files SOURCES main.cpp backend.cpp backend.hpp dir_model.cpp dir_model.hpp devices.cpp devices.hpp tags.cpp tags.hpp ${PROJECT_SOURCE_DIR}/common/thumbs.cpp ${PROJECT_SOURCE_DIR}/common/thumbs.hpp LIBS PkgConfig::LIBARCHIVE b1air-thumbs-deps)
