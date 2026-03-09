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

if (ANDROID)
    set(LADYBIRD_OUT_DIR "${LADYBIRD_DIR}/Build/android-${ANDROID_ABI}")
    
    set(CACHE_DIR "$ENV{LADYBIRD_CACHE_DIR}")
    if (NOT CACHE_DIR OR CACHE_DIR STREQUAL "")
        set(CACHE_DIR "${LADYBIRD_DIR}/Build/caches")
    endif()

    # 1. Build Lagom Tools for host
    execute_process(
        COMMAND bash "${LADYBIRD_DIR}/UI/Android/BuildLagomTools.sh"
        WORKING_DIRECTORY "${LADYBIRD_DIR}/UI/Android"
        RESULT_VARIABLE lagom_res
        ENVIRONMENT
            "BUILD_DIR=${LADYBIRD_DIR}/Build"
            "CACHE_DIR=${CACHE_DIR}"
            "PATH=$ENV{PATH}"
    )
    if(NOT lagom_res EQUAL 0)
        message(FATAL_ERROR "BuildLagomTools.sh failed on Android cross-compile")
    endif()

    # 2. Configure for Android natively
    execute_process(
        COMMAND ${CMAKE_COMMAND} -B "${LADYBIRD_OUT_DIR}" -S "${LADYBIRD_DIR}"
            -GNinja
            -DCMAKE_BUILD_TYPE=Release
            -DCMAKE_MAKE_PROGRAM=ninja
            -DANDROID_NDK=${ANDROID_NDK}
            -DANDROID_ABI=${ANDROID_ABI}
            -DANDROID_PLATFORM=${ANDROID_PLATFORM}
            -DANDROID_STL=c++_shared
            -DVCPKG_TARGET_ANDROID=ON
            -DLagomTools_DIR=${LADYBIRD_DIR}/Build/lagom-tools-install/share/LagomTools
            -DLADYBIRD_CACHE_DIR=${CACHE_DIR}
            -DVCPKG_ROOT=${LADYBIRD_DIR}/Build/vcpkg
        WORKING_DIRECTORY "${LADYBIRD_DIR}"
        RESULT_VARIABLE config_res
    )
    if(NOT config_res EQUAL 0)
        message(FATAL_ERROR "Ladybird CMake configure failed for Android ABI: ${ANDROID_ABI}")
    endif()

    # 3. Build Ladybird libraries using ninja
    execute_process(
        COMMAND ninja -C "${LADYBIRD_OUT_DIR}"
        WORKING_DIRECTORY "${LADYBIRD_DIR}"
        RESULT_VARIABLE build_res
    )
    if(NOT build_res EQUAL 0)
        message(FATAL_ERROR "Ladybird Ninja build failed for Android ABI: ${ANDROID_ABI}")
    endif()
else()
    set(LADYBIRD_OUT_DIR "${LADYBIRD_DIR}/Build/release")
    execute_process(
        COMMAND ${CMAKE_COMMAND} -E env "CC=${CMAKE_C_COMPILER}" "CXX=${CMAKE_CXX_COMPILER}" "PYTHONPATH=${LADYBIRD_DIR}" python3 "Meta/ladybird.py" build
        WORKING_DIRECTORY "${LADYBIRD_DIR}"
    )
endif()

if (APPLE)
    set(VCPKG_TRIPLET "arm64-osx-dynamic")
elseif(ANDROID)
    set(VCPKG_TRIPLET "arm64-android")
else()
    set(VCPKG_TRIPLET "x64-linux-dynamic")
endif()

add_library(engine SHARED engine.cpp)

target_include_directories(engine PRIVATE
    ${LADYBIRD_DIR}
    ${LADYBIRD_DIR}/Libraries
    ${LADYBIRD_DIR}/Userland/Libraries
    ${LADYBIRD_DIR}/Services
    ${LADYBIRD_OUT_DIR}
    ${LADYBIRD_OUT_DIR}/Lagom
    ${LADYBIRD_OUT_DIR}/Lagom/Libraries
    ${LADYBIRD_OUT_DIR}/Lagom/Services
    ${LADYBIRD_OUT_DIR}/vcpkg_installed/${VCPKG_TRIPLET}/include
)

if (EXISTS "${LADYBIRD_OUT_DIR}/lib64")
    file(COPY "${LADYBIRD_OUT_DIR}/lib64/" DESTINATION "${CMAKE_CURRENT_BINARY_DIR}")
endif()
if (EXISTS "${LADYBIRD_OUT_DIR}/lib")
    file(COPY "${LADYBIRD_OUT_DIR}/lib/" DESTINATION "${CMAKE_CURRENT_BINARY_DIR}")
endif()
if (EXISTS "${LADYBIRD_OUT_DIR}/vcpkg_installed/${VCPKG_TRIPLET}/lib")
    file(GLOB VCPKG_LIBS "${LADYBIRD_OUT_DIR}/vcpkg_installed/${VCPKG_TRIPLET}/lib/*")
    list(FILTER VCPKG_LIBS EXCLUDE REGEX "libz\.so")
    list(FILTER VCPKG_LIBS EXCLUDE REGEX "libharfbuzz\.so")
    file(COPY ${VCPKG_LIBS} DESTINATION "${CMAKE_CURRENT_BINARY_DIR}")
endif()

target_link_directories(engine PRIVATE 
    ${LADYBIRD_OUT_DIR}/lib
    ${LADYBIRD_OUT_DIR}/lib64
    ${LADYBIRD_OUT_DIR}/vcpkg_installed/${VCPKG_TRIPLET}/lib
)

file(GLOB LADYBIRD_LIBS_SO
    "${LADYBIRD_OUT_DIR}/lib64/liblagom-*.so"
    "${LADYBIRD_OUT_DIR}/lib/liblagom-*.so"
)

target_link_libraries(engine PRIVATE
    ${LADYBIRD_LIBS_SO}
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

        COMMAND ${CMAKE_COMMAND} -E copy_directory "${LADYBIRD_OUT_DIR}/lib" "${BUNDLE_DIR}/libraries"

        COMMAND ${CMAKE_COMMAND} -E copy "${LADYBIRD_OUT_DIR}/bin/Ladybird.app/Contents/MacOS/WebContent" "${BUNDLE_DIR}/binaries/"
        COMMAND ${CMAKE_COMMAND} -E copy "${LADYBIRD_OUT_DIR}/bin/Ladybird.app/Contents/MacOS/RequestServer" "${BUNDLE_DIR}/binaries/"
        COMMAND ${CMAKE_COMMAND} -E copy "${LADYBIRD_OUT_DIR}/bin/Ladybird.app/Contents/MacOS/ImageDecoder" "${BUNDLE_DIR}/binaries/"
        COMMAND ${CMAKE_COMMAND} -E copy "${LADYBIRD_OUT_DIR}/bin/Ladybird.app/Contents/MacOS/WebWorker" "${BUNDLE_DIR}/binaries/"
        COMMAND ${CMAKE_COMMAND} -E copy "${LADYBIRD_OUT_DIR}/bin/Ladybird.app/Contents/MacOS/Ladybird" "${BUNDLE_DIR}/binaries/"

        COMMAND ${CMAKE_COMMAND} -E copy_directory "${LADYBIRD_DIR}/Base/res" "${BUNDLE_DIR}/res"
    )
else()
    set_target_properties(engine PROPERTIES
        PREFIX "lib"
        SUFFIX ".so"
        INSTALL_RPATH "$ORIGIN/../lib"
    )
endif()
