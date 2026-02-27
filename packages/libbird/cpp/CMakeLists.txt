cmake_minimum_required(VERSION 3.10)
project(LadybirdEngineWrapper)

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(engine SHARED engine.cpp)

set(LADYBIRD_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/ladybird")

target_include_directories(engine PRIVATE
    ${LADYBIRD_DIR}/UI/AppKit
    ${LADYBIRD_DIR}
    ${LADYBIRD_DIR}/Libraries
    ${LADYBIRD_DIR}/Userland/Libraries
    ${LADYBIRD_DIR}/Services
    ${LADYBIRD_DIR}/Build/release
    ${LADYBIRD_DIR}/Build/release/Lagom
    ${LADYBIRD_DIR}/Build/release/Lagom/Libraries
    ${LADYBIRD_DIR}/Build/release/Lagom/Services
    ${LADYBIRD_DIR}/Build/release/vcpkg_installed/arm64-osx-dynamic/include
)

target_link_directories(engine PRIVATE 
    ${LADYBIRD_DIR}/Build/release/lib
    ${LADYBIRD_DIR}/Build/release/vcpkg_installed/arm64-osx-dynamic/lib
)

target_link_libraries(engine PRIVATE
    lagom-webview
    lagom-web
    lagom-requests
    lagom-js
    lagom-gfx
    lagom-ipc
    lagom-url
    lagom-filesystem
    lagom-crypto
    lagom-database
    lagom-core
    lagom-coreminimal
    lagom-ak
    lagom-unicode
    lagom-main
    skia
    sqlite3
    ssl
    crypto
    z
)

set_target_properties(engine PROPERTIES
    PREFIX "lib"
    SUFFIX ".dylib"
)