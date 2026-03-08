cmake_minimum_required(VERSION 3.10)
project(LadybirdEngineWrapper)

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)


set(LADYBIRD_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/ladybird")

execute_process(
    COMMAND git submodule update --init --recursive "third_party/ladybird"
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/.."
)

execute_process(
    COMMAND ${CMAKE_COMMAND} -E env "PYTHONPATH=${LADYBIRD_DIR}" python3 "Meta/ladybird.py" build
    WORKING_DIRECTORY "${LADYBIRD_DIR}"
)

add_library(engine SHARED engine.cpp)

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
    lagom-gfx
    skia
)

if (APPLE)
    target_link_libraries(engine PRIVATE
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
        INSTALL_RPATH "@loader_path/ladybird_libs"
        INSTALL_NAME_DIR "@rpath"
    )

    set(BUNDLE_DIR "${CMAKE_BINARY_DIR}/LadybirdBundle")

    add_custom_command(TARGET engine POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E make_directory "${BUNDLE_DIR}/libraries"
        COMMAND ${CMAKE_COMMAND} -E make_directory "${BUNDLE_DIR}/binaries"
        
        COMMAND ${CMAKE_COMMAND} -E copy "$<TARGET_FILE:engine>" "${BUNDLE_DIR}/"

        COMMAND ${CMAKE_COMMAND} -E copy_directory "${LADYBIRD_DIR}/Build/release/lib" "${BUNDLE_DIR}/libraries"

        COMMAND ${CMAKE_COMMAND} -E copy "${LADYBIRD_DIR}/Build/release/bin/Ladybird.app/Contents/MacOS/WebContent" "${BUNDLE_DIR}/binaries/"
        COMMAND ${CMAKE_COMMAND} -E copy "${LADYBIRD_DIR}/Build/release/bin/Ladybird.app/Contents/MacOS/RequestServer" "${BUNDLE_DIR}/binaries/"
        COMMAND ${CMAKE_COMMAND} -E copy "${LADYBIRD_DIR}/Build/release/bin/Ladybird.app/Contents/MacOS/ImageDecoder" "${BUNDLE_DIR}/binaries/"
        COMMAND ${CMAKE_COMMAND} -E copy "${LADYBIRD_DIR}/Build/release/bin/Ladybird.app/Contents/MacOS/WebWorker" "${BUNDLE_DIR}/binaries/"
        COMMAND ${CMAKE_COMMAND} -E copy "${LADYBIRD_DIR}/Build/release/bin/Ladybird.app/Contents/MacOS/Ladybird" "${BUNDLE_DIR}/binaries/"

        COMMAND ${CMAKE_COMMAND} -E copy_directory "${LADYBIRD_DIR}/Base/res" "${BUNDLE_DIR}/res"
    )
else()
    set_target_properties(engine PROPERTIES
        PREFIX "lib"
        SUFFIX ".so"
        BUILD_WITH_INSTALL_RPATH TRUE
        INSTALL_RPATH "$ORIGIN/../lib"
    )
endif()
