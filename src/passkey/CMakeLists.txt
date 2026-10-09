# b1air-passkey — the phone as a security key (src/main.rs says how). Rust,
# because the caBLE (hybrid) transport it rests on is libwebauthn, the
# library credentialsd uses; Cargo builds it into the same build/bin as the
# rest, so `make install` picks it up with them.
#
# Optional: without cargo, or with a Rust older than libwebauthn needs, the
# rest of the suite builds and this one is left out with a note.
find_program(CARGO_PROGRAM cargo)
find_program(RUSTC_PROGRAM rustc)
set(B1AIR_PASSKEY_RUST_MIN 1.88)
if(CARGO_PROGRAM AND RUSTC_PROGRAM)
    execute_process(COMMAND ${RUSTC_PROGRAM} --version OUTPUT_VARIABLE _rustc_out OUTPUT_STRIP_TRAILING_WHITESPACE)
    string(REGEX MATCH "[0-9]+\\.[0-9]+" _rustc_version "${_rustc_out}")
endif()
if(NOT CARGO_PROGRAM OR NOT _rustc_version OR _rustc_version VERSION_LESS B1AIR_PASSKEY_RUST_MIN)
    message(STATUS "b1air-passkey: skipped (needs cargo and Rust ${B1AIR_PASSKEY_RUST_MIN}+, found '${_rustc_version}')")
    return()
endif()

set(_target_dir ${CMAKE_BINARY_DIR}/cargo)
file(GLOB _sources CONFIGURE_DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/src/*.rs)
add_custom_command(
    OUTPUT ${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/b1air-passkey
    COMMAND ${CARGO_PROGRAM} build --release --locked --quiet
            --manifest-path ${CMAKE_CURRENT_SOURCE_DIR}/Cargo.toml
            --target-dir ${_target_dir}
    COMMAND ${CMAKE_COMMAND} -E copy ${_target_dir}/release/b1air-passkey ${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/b1air-passkey
    DEPENDS ${_sources} ${CMAKE_CURRENT_SOURCE_DIR}/Cargo.toml ${CMAKE_CURRENT_SOURCE_DIR}/Cargo.lock
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
    USES_TERMINAL
    COMMENT "Building b1air-passkey with cargo")
add_custom_target(b1air-passkey ALL DEPENDS ${CMAKE_RUNTIME_OUTPUT_DIRECTORY}/b1air-passkey)
