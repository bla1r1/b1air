# b1air-fido-uhid — the one root process of the phone passkey: it makes the
# FIDO HID device b1air-passkey answers as (main.cpp says why it is apart).
# libsystemd for whose session is active.
add_executable(b1air-fido-uhid main.cpp)
target_link_libraries(b1air-fido-uhid PRIVATE systemd)
b1air_warnings(b1air-fido-uhid)
