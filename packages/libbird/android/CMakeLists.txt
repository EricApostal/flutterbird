cmake_minimum_required(VERSION 3.25)

set(LADYBIRD_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/ladybird")
set(LADYBIRD_BINARY_DIR "${CMAKE_CURRENT_BINARY_DIR}/ladybird_build")

# Ladybird's AndroidExtras.cmake derives the asset destination from CMAKE_SOURCE_DIR.
# In this wrapper build, that resolves to packages/libbird/android, so ensure the
# expected path exists for its copy-assets custom target.
file(MAKE_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/UI/Android/src/main/assets")

if (VCPKG_TARGET_ANDROID)
    # CMAKE_SOURCE_DIR points to this plugin, so vcpkg would otherwise miss
    # Ladybird's manifest and stay in classic mode.
    set(VCPKG_MANIFEST_DIR "${LADYBIRD_DIR}" CACHE PATH "vcpkg manifest root" FORCE)
    set(VCPKG_MANIFEST_MODE ON CACHE BOOL "Use vcpkg manifest mode" FORCE)
    set(VCPKG_MANIFEST_INSTALL ON CACHE BOOL "Install manifest dependencies" FORCE)

    # Keep toolchain handling equivalent to Ladybird's top-level CMake.
    include("${LADYBIRD_DIR}/UI/Android/vcpkg_android.cmake")
endif()

project(ladybird_plugin LANGUAGES CXX)

set(PLUGIN_NAME "ladybird_plugin")

# The flutter tooling requires at least one cpp file in the plugin
# We can just put a dummy here, or since FFI, we can avoid standard Flutter plugin registration.
# But gradle expects to build a target with PLUGIN_NAME.
add_library(${PLUGIN_NAME} SHARED
    dummy.cpp
    "${CMAKE_CURRENT_SOURCE_DIR}/../cpp/engine.cpp"
)

add_library(ladybird_jni SHARED
    jni_bridge.cpp
)

add_subdirectory("${LADYBIRD_DIR}" "${LADYBIRD_BINARY_DIR}")

find_package(OpenSSL REQUIRED)

target_include_directories(${PLUGIN_NAME} PRIVATE
    "${LADYBIRD_DIR}"
    "${LADYBIRD_DIR}/Libraries"
    "${LADYBIRD_DIR}/Userland/Libraries"
    "${LADYBIRD_DIR}/Services"
    "${LADYBIRD_BINARY_DIR}"
    "${LADYBIRD_BINARY_DIR}/Lagom"
    "${LADYBIRD_BINARY_DIR}/Lagom/Libraries"
    "${LADYBIRD_BINARY_DIR}/Lagom/Services"
)

target_link_libraries(${PLUGIN_NAME} PRIVATE
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
    webcontentservice
    requestserverservice
    imagedecoderservice
)

target_link_libraries(ladybird_jni PRIVATE
    log
    android
)

add_dependencies(${PLUGIN_NAME} ladybird)

# Standard C++2b is required by Ladybird
set_target_properties(${PLUGIN_NAME} PROPERTIES
    CXX_STANDARD 23
    CXX_STANDARD_REQUIRED ON
)

