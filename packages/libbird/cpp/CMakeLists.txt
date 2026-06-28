cmake_minimum_required(VERSION 3.10)
project(LadybirdEngineWrapper)

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)


set(LADYBIRD_VERSION_FILE "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/ladybird.version")
set(LADYBIRD_BOOTSTRAP_SCRIPT "${CMAKE_CURRENT_SOURCE_DIR}/../tool/ensure_ladybird_source.sh")
set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS
    "${LADYBIRD_VERSION_FILE}"
    "${LADYBIRD_BOOTSTRAP_SCRIPT}"
)

set(LADYBIRD_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/ladybird")

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

if (ANDROID)
    message(FATAL_ERROR "Android builds moved to packages/libbird/android/CMakeLists.txt")
elseif (IOS)
    message(FATAL_ERROR "iOS builds moved to packages/libbird/ios/CMakeLists.txt")
else()
    set(LADYBIRD_OUT_DIR "${LADYBIRD_DIR}/Build/release")
    set(_ladybird_build_env
        "CC=${CMAKE_C_COMPILER}"
        "CXX=${CMAKE_CXX_COMPILER}"
        "PYTHONPATH=${LADYBIRD_DIR}"
    )

    # I'm pretty sure this is useless
    if (APPLE)
        list(APPEND _ladybird_build_env "VCPKG_MAX_CONCURRENCY=1")
    endif()

    execute_process(
        COMMAND ${CMAKE_COMMAND} -E env ${_ladybird_build_env} python3 "Meta/ladybird.py" build
        WORKING_DIRECTORY "${LADYBIRD_DIR}"
        RESULT_VARIABLE LADYBIRD_BUILD_RESULT
        OUTPUT_VARIABLE LADYBIRD_BUILD_STDOUT
        ERROR_VARIABLE LADYBIRD_BUILD_STDERR
    )

    if (NOT LADYBIRD_BUILD_RESULT EQUAL 0)
        message(FATAL_ERROR "Failed to build Ladybird.\n${LADYBIRD_BUILD_STDOUT}\n${LADYBIRD_BUILD_STDERR}")
    endif()
endif()

set(LADYBIRD_USE_VULKAN_DMABUF_IMAGES OFF)
set(LADYBIRD_CACHE_FILE "${LADYBIRD_OUT_DIR}/CMakeCache.txt")
if (EXISTS "${LADYBIRD_CACHE_FILE}")
    file(STRINGS "${LADYBIRD_CACHE_FILE}" _ladybird_dmabuf_cache_line REGEX "^USE_VULKAN_DMABUF_IMAGES:BOOL=(ON|OFF)$")
    if (_ladybird_dmabuf_cache_line MATCHES "^USE_VULKAN_DMABUF_IMAGES:BOOL=ON$")
        set(LADYBIRD_USE_VULKAN_DMABUF_IMAGES ON)
    endif()
endif()

if (APPLE)
    set(VCPKG_TRIPLET "arm64-osx-dynamic")
elseif (ANDROID)
    set(VCPKG_TRIPLET "arm64-android")
else()
    set(VCPKG_TRIPLET "x64-linux-dynamic")
endif()

add_library(engine SHARED
    engine.cpp
    platform/view_backend.cpp
    platform/linux_view_backend.cpp
    platform/macos_view_backend.cpp
)

# The Ladybird headers intentionally use unqualified std casts and literal
# suffixes that trigger strict Clang warnings; keep engine builds resilient
# when dmabuf paths pull in those headers.
if (CMAKE_CXX_COMPILER_ID MATCHES "Clang")
    target_compile_options(engine PRIVATE
        -Wno-unqualified-std-cast-call
        -Wno-user-defined-literals
    )
endif()

if (LADYBIRD_USE_VULKAN_DMABUF_IMAGES)
    target_compile_definitions(engine PRIVATE USE_VULKAN_DMABUF_IMAGES=1)
endif()

target_include_directories(engine PRIVATE
    ${LADYBIRD_DIR}
    ${LADYBIRD_DIR}/Libraries
    ${LADYBIRD_DIR}/Userland/Libraries
    ${LADYBIRD_DIR}/Services
    ${LADYBIRD_OUT_DIR}
    ${LADYBIRD_OUT_DIR}/Libraries
    ${LADYBIRD_OUT_DIR}/Services
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
        COMMAND ${CMAKE_COMMAND} -E copy_directory "${LADYBIRD_OUT_DIR}/vcpkg_installed/${VCPKG_TRIPLET}/lib" "${BUNDLE_DIR}/libraries"

        COMMAND ${CMAKE_COMMAND} -E copy "${LADYBIRD_OUT_DIR}/bin/Ladybird.app/Contents/MacOS/WebContent" "${BUNDLE_DIR}/binaries/"
        COMMAND ${CMAKE_COMMAND} -E copy "${LADYBIRD_OUT_DIR}/bin/Ladybird.app/Contents/MacOS/RequestServer" "${BUNDLE_DIR}/binaries/"
        COMMAND ${CMAKE_COMMAND} -E copy "${LADYBIRD_OUT_DIR}/bin/Ladybird.app/Contents/MacOS/ImageDecoder" "${BUNDLE_DIR}/binaries/"
        COMMAND ${CMAKE_COMMAND} -E copy "${LADYBIRD_OUT_DIR}/bin/Ladybird.app/Contents/MacOS/WebWorker" "${BUNDLE_DIR}/binaries/"
        COMMAND ${CMAKE_COMMAND} -E copy "${LADYBIRD_OUT_DIR}/bin/Ladybird.app/Contents/MacOS/Compositor" "${BUNDLE_DIR}/binaries/"
        COMMAND ${CMAKE_COMMAND} -E copy "${LADYBIRD_OUT_DIR}/bin/Ladybird.app/Contents/MacOS/Ladybird" "${BUNDLE_DIR}/binaries/"

        COMMAND ${CMAKE_COMMAND} -E copy_directory "${LADYBIRD_DIR}/Base/res" "${BUNDLE_DIR}/res"
    )
else()
    set_target_properties(engine PROPERTIES
        PREFIX "lib"
        SUFFIX ".so"
        BUILD_WITH_INSTALL_RPATH TRUE
        INSTALL_RPATH "$ORIGIN"
    )
endif()
