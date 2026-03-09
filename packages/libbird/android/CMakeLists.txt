cmake_minimum_required(VERSION 3.10)

project(ladybird_plugin LANGUAGES CXX)

set(PLUGIN_NAME "ladybird_plugin")
set(LADYBIRD_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/ladybird")
set(LADYBIRD_ANDROID_OUT_DIR "${LADYBIRD_DIR}/Build/android-${ANDROID_ABI}")

set(LADYBIRD_CACHE_DIR "$ENV{LADYBIRD_CACHE_DIR}")
if (NOT LADYBIRD_CACHE_DIR OR LADYBIRD_CACHE_DIR STREQUAL "")
    set(LADYBIRD_CACHE_DIR "${LADYBIRD_DIR}/Build/caches")
endif()

set(LADYBIRD_VCPKG_ROOT "${LADYBIRD_DIR}/Build/vcpkg")

execute_process(
    COMMAND git submodule update --init --recursive "third_party/ladybird"
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/.."
)

# Build Lagom host tools the same way Ladybird's Android project does.
execute_process(
    COMMAND "${CMAKE_COMMAND}" -E env
        "BUILD_DIR=${LADYBIRD_DIR}/Build"
        "CACHE_DIR=${LADYBIRD_CACHE_DIR}"
        "PATH=$ENV{PATH}"
        "CC="
        "CXX="
        "CFLAGS="
        "CXXFLAGS="
        "LDFLAGS="
        "CMAKE_TOOLCHAIN_FILE="
        bash "${LADYBIRD_DIR}/UI/Android/BuildLagomTools.sh"
    WORKING_DIRECTORY "${LADYBIRD_DIR}/UI/Android"
    RESULT_VARIABLE LADYBIRD_LAGOM_TOOLS_RESULT
)
if (NOT LADYBIRD_LAGOM_TOOLS_RESULT EQUAL 0)
    message(FATAL_ERROR "BuildLagomTools.sh failed for Android")
endif()

set(LADYBIRD_ANDROID_CMAKE_ARGS
    -GNinja
    -DCMAKE_BUILD_TYPE=Release
    -DANDROID_NDK=${ANDROID_NDK}
    -DANDROID_ABI=${ANDROID_ABI}
    -DANDROID_PLATFORM=${ANDROID_PLATFORM}
    -DANDROID_STL=${ANDROID_STL}
    -DLagomTools_DIR=${LADYBIRD_DIR}/Build/lagom-tools-install/share/LagomTools
    -DLADYBIRD_CACHE_DIR=${LADYBIRD_CACHE_DIR}
    -DVCPKG_ROOT=${LADYBIRD_VCPKG_ROOT}
    -DVCPKG_TARGET_ANDROID=ON
)

if (CMAKE_MAKE_PROGRAM)
    list(APPEND LADYBIRD_ANDROID_CMAKE_ARGS -DCMAKE_MAKE_PROGRAM=${CMAKE_MAKE_PROGRAM})
endif()

execute_process(
    COMMAND "${CMAKE_COMMAND}" -B "${LADYBIRD_ANDROID_OUT_DIR}" -S "${LADYBIRD_DIR}" ${LADYBIRD_ANDROID_CMAKE_ARGS}
    WORKING_DIRECTORY "${LADYBIRD_DIR}"
    RESULT_VARIABLE LADYBIRD_ANDROID_CONFIGURE_RESULT
)
if (NOT LADYBIRD_ANDROID_CONFIGURE_RESULT EQUAL 0)
    message(FATAL_ERROR "Ladybird CMake configure failed for Android ABI ${ANDROID_ABI}")
endif()

execute_process(
    COMMAND "${CMAKE_COMMAND}" --build "${LADYBIRD_ANDROID_OUT_DIR}" --target ladybird WebContent RequestServer ImageDecoder WebWorker
    WORKING_DIRECTORY "${LADYBIRD_DIR}"
    RESULT_VARIABLE LADYBIRD_ANDROID_BUILD_RESULT
)
if (NOT LADYBIRD_ANDROID_BUILD_RESULT EQUAL 0)
    message(FATAL_ERROR "Ladybird Android build failed for ABI ${ANDROID_ABI}")
endif()

# The flutter tooling requires at least one cpp file in the plugin
# We can just put a dummy here, or since FFI, we can avoid standard Flutter plugin registration.
# But gradle expects to build a target with PLUGIN_NAME.
add_library(${PLUGIN_NAME} SHARED
    dummy.cpp
)

add_library(engine SHARED "${CMAKE_CURRENT_SOURCE_DIR}/../cpp/engine.cpp")

target_include_directories(engine PRIVATE
    "${LADYBIRD_DIR}"
    "${LADYBIRD_DIR}/Libraries"
    "${LADYBIRD_DIR}/Userland/Libraries"
    "${LADYBIRD_DIR}/Services"
    "${LADYBIRD_ANDROID_OUT_DIR}"
    "${LADYBIRD_ANDROID_OUT_DIR}/Lagom"
    "${LADYBIRD_ANDROID_OUT_DIR}/Lagom/Libraries"
    "${LADYBIRD_ANDROID_OUT_DIR}/Lagom/Services"
    "${LADYBIRD_ANDROID_OUT_DIR}/vcpkg_installed/arm64-android/include"
)

target_link_directories(engine PRIVATE
    "${LADYBIRD_ANDROID_OUT_DIR}/lib"
    "${LADYBIRD_ANDROID_OUT_DIR}/lib64"
    "${LADYBIRD_ANDROID_OUT_DIR}/vcpkg_installed/arm64-android/lib"
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
    log
    android
    jnigraphics
)

if (EXISTS "${LADYBIRD_ANDROID_OUT_DIR}/lib")
    file(COPY "${LADYBIRD_ANDROID_OUT_DIR}/lib/" DESTINATION "${CMAKE_CURRENT_BINARY_DIR}")
endif()
if (EXISTS "${LADYBIRD_ANDROID_OUT_DIR}/lib64")
    file(COPY "${LADYBIRD_ANDROID_OUT_DIR}/lib64/" DESTINATION "${CMAKE_CURRENT_BINARY_DIR}")
endif()

target_link_libraries(${PLUGIN_NAME} PRIVATE engine log android jnigraphics)

# Standard C++2b is required by Ladybird
set_target_properties(${PLUGIN_NAME} PROPERTIES
    CXX_STANDARD 23
    CXX_STANDARD_REQUIRED ON
)

