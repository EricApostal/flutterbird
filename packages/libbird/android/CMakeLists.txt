cmake_minimum_required(VERSION 3.25)

set(LADYBIRD_VERSION_FILE "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/ladybird.version")
set(LADYBIRD_BOOTSTRAP_SCRIPT "${CMAKE_CURRENT_SOURCE_DIR}/../tool/ensure_ladybird_source.sh")
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
    "${LADYBIRD_VERSION_FILE}"
    "${LADYBIRD_BOOTSTRAP_SCRIPT}"
)

execute_process(
    COMMAND bash "${LADYBIRD_BOOTSTRAP_SCRIPT}"
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/.."
    RESULT_VARIABLE LADYBIRD_BOOTSTRAP_RESULT
    OUTPUT_VARIABLE LADYBIRD_BOOTSTRAP_STDOUT
    ERROR_VARIABLE LADYBIRD_BOOTSTRAP_STDERR
)

if (NOT LADYBIRD_BOOTSTRAP_RESULT EQUAL 0)
    message(FATAL_ERROR "Failed to prepare Ladybird checkout.\n${LADYBIRD_BOOTSTRAP_STDOUT}\n${LADYBIRD_BOOTSTRAP_STDERR}")
endif()

set(LADYBIRD_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/ladybird")
set(LADYBIRD_BINARY_DIR "${CMAKE_CURRENT_BINARY_DIR}/ladybird_build")

if (VCPKG_TARGET_ANDROID)
    # Keep toolchain handling equivalent to Ladybird's top-level CMake.
    # This wrapper CMake lives outside the Ladybird root, so explicitly point
    # vcpkg manifest mode at Ladybird's vcpkg.json.
    set(VCPKG_MANIFEST_DIR "${LADYBIRD_DIR}" CACHE PATH "" FORCE)
    set(VCPKG_MANIFEST_INSTALL ON CACHE BOOL "" FORCE)
    include("${LADYBIRD_DIR}/UI/Android/vcpkg_android.cmake")
endif()

set(ENV{PKG_CONFIG_PATH} "/usr/local/lib/pkgconfig:$ENV{PKG_CONFIG_PATH}")
set(CMAKE_PREFIX_PATH "/usr/local" ${CMAKE_PREFIX_PATH})
set(ICU_ROOT "/usr/local")

project(ladybird_plugin LANGUAGES CXX)

set(PLUGIN_NAME "ladybird_plugin")

# The flutter tooling requires at least one cpp file in the plugin
# We can just put a dummy here, or since FFI, we can avoid standard Flutter plugin registration.
# But gradle expects to build a target with PLUGIN_NAME.
add_library(${PLUGIN_NAME} SHARED
    dummy.cpp
)

add_subdirectory("${LADYBIRD_DIR}" "${LADYBIRD_BINARY_DIR}")

add_library(engine SHARED "${CMAKE_CURRENT_SOURCE_DIR}/../cpp/engine.cpp")

target_include_directories(engine PRIVATE
    "${LADYBIRD_DIR}"
    "${LADYBIRD_DIR}/Libraries"
    "${LADYBIRD_DIR}/Userland/Libraries"
    "${LADYBIRD_DIR}/Services"
    "${LADYBIRD_BINARY_DIR}"
    "${LADYBIRD_BINARY_DIR}/Libraries"
    "${LADYBIRD_BINARY_DIR}/Services"
    "${LADYBIRD_BINARY_DIR}/Lagom"
    "${LADYBIRD_BINARY_DIR}/Lagom/Libraries"
    "${LADYBIRD_BINARY_DIR}/Lagom/Services"
)

target_link_libraries(engine PRIVATE
    AK
    LibCore
    LibFileSystem
    LibGfx
    LibImageDecoderClient
    LibIPC
    LibJS
    LibMain
    LibWeb
    LibWebView
    LibRequests
    LibURL
    OpenSSL::Crypto
    OpenSSL::SSL
    log
    android
    jnigraphics
)

add_dependencies(engine ladybird)

target_link_libraries(${PLUGIN_NAME} PRIVATE engine log android jnigraphics)

# Standard C++2b is required by Ladybird
set_target_properties(${PLUGIN_NAME} PROPERTIES
    CXX_STANDARD 23
    CXX_STANDARD_REQUIRED ON
)

