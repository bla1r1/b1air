# b1air-files — file manager and gallery; libarchive for browsing archives.
b1air_add_app(files SOURCES main.cpp backend.cpp backend.hpp dir_model.cpp dir_model.hpp LIBS PkgConfig::LIBARCHIVE)
