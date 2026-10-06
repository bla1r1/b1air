# One directory per application, each built into its own program. They share
# build helpers (cmake/B1airApp.cmake) and a header (common/qml_search.hpp),
# never code that runs: an app that hangs or crashes takes nothing else down.
add_subdirectory(camera)
add_subdirectory(files)
add_subdirectory(git)
add_subdirectory(monitor)
add_subdirectory(settings)
add_subdirectory(term)
add_subdirectory(text)
add_subdirectory(view)
