cmake_minimum_required(VERSION 3.10)
project(LadybirdEngineWrapper)

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_library(engine SHARED engine.cpp)

set(LADYBIRD_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/ladybird")

target_include_directories(engine PRIVATE
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
    lagom-js
    lagom-requests
    
    lagom-url
    lagom-ipc
    lagom-core
    lagom-ak
    lagom-coreminimal
    
    lagom-gfx
    skia

    "-framework CoreFoundation"
    "-framework CoreVideo"
    "-framework IOSurface"
    "-framework Metal"
    "-framework Foundation"
)

set_target_properties(engine PROPERTIES
    PREFIX "lib"
    SUFFIX ".dylib"
    BUILD_WITH_INSTALL_RPATH TRUE
    INSTALL_NAME_DIR "@rpath"
)

add_custom_command(TARGET engine POST_BUILD
    COMMAND mkdir -p "${CMAKE_CURRENT_SOURCE_DIR}/../macos/Bundled"
    COMMAND bash -c "find '${LADYBIRD_DIR}/Build/release' -name '*.dylib' -exec cp {} '${CMAKE_CURRENT_SOURCE_DIR}/../macos/Bundled/' \\;"
    COMMAND cp "$<TARGET_FILE:engine>" "${CMAKE_CURRENT_SOURCE_DIR}/../macos/Bundled/"
    COMMAND bash -c "for f in '${CMAKE_CURRENT_SOURCE_DIR}/../macos/Bundled/'*.dylib; do if [ -f \"$$f\" ]; then bn=$$(basename \"$$f\"); chmod +w \"$$f\"; install_name_tool -id \"@rpath/$$bn\" \"$$f\" || true; fi; done"
)