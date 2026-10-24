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
    lagom-webcommon
    lagom-web
    # LibJS is folded into LibWeb now (Libraries/CMakeLists.txt:
    # LIBJS_FOLDED_INTO_LIBWEB), so there is no lagom-js to link.
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
    set(BUNDLE_STAMP "${CMAKE_BINARY_DIR}/LadybirdBundle.stamp")

    # The engine's own copy rides on its link, but everything else in the bundle
    # comes out of the Ladybird build tree: hashing it means a rebuilt Ladybird
    # (a new pinned revision, an upstream change) reaches the app even when no
    # line of engine.cpp moved and the engine therefore never relinks.
    file(GLOB LADYBIRD_BUNDLE_INPUTS
        "${LADYBIRD_OUT_DIR}/lib/*"
        "${LADYBIRD_OUT_DIR}/vcpkg_installed/${VCPKG_TRIPLET}/lib/*"
        "${LADYBIRD_OUT_DIR}/bin/Ladybird.app/Contents/MacOS/*"
        "${LADYBIRD_DIR}/Base/res/*"
    )

    add_custom_command(
        OUTPUT "${BUNDLE_STAMP}"
        COMMAND ${CMAKE_COMMAND} -E make_directory "${BUNDLE_DIR}/libraries"
        COMMAND ${CMAKE_COMMAND} -E make_directory "${BUNDLE_DIR}/binaries"
        COMMAND ${CMAKE_COMMAND} -E copy_directory "${LADYBIRD_OUT_DIR}/lib" "${BUNDLE_DIR}/libraries"
        COMMAND ${CMAKE_COMMAND} -E copy_directory "${LADYBIRD_OUT_DIR}/vcpkg_installed/${VCPKG_TRIPLET}/lib" "${BUNDLE_DIR}/libraries"
        # Every executable Ladybird puts in its own bundle's MacOS directory is a
        # helper the UI process may spawn (WebContent, RequestServer, ImageDecoder,
        # WebWorker, Compositor, AudioServer, MediaServer, VideoDecoderServer,
        # ProcessReaper, ...) plus the ladybird binary itself. Copying the whole
        # directory keeps up with upstream gaining or renaming helpers, which
        # enumerating them here silently did not.
        COMMAND ${CMAKE_COMMAND} -E copy_directory "${LADYBIRD_OUT_DIR}/bin/Ladybird.app/Contents/MacOS" "${BUNDLE_DIR}/binaries"
        COMMAND ${CMAKE_COMMAND} -E copy_directory "${LADYBIRD_DIR}/Base/res" "${BUNDLE_DIR}/res"
        COMMAND ${CMAKE_COMMAND} -E touch "${BUNDLE_STAMP}"
        DEPENDS ${LADYBIRD_BUNDLE_INPUTS}
        COMMENT "Refreshing LadybirdBundle from the Ladybird build tree"
    )

    add_custom_target(ladybird_bundle ALL DEPENDS "${BUNDLE_STAMP}")
    add_dependencies(ladybird_bundle engine)

    add_custom_command(TARGET engine POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E make_directory "${BUNDLE_DIR}"
        COMMAND ${CMAKE_COMMAND} -E copy "$<TARGET_FILE:engine>" "${BUNDLE_DIR}/"
    )
else()
    set_target_properties(engine PROPERTIES
        PREFIX "lib"
        SUFFIX ".so"
        BUILD_WITH_INSTALL_RPATH TRUE
        INSTALL_RPATH "$ORIGIN"
    )
endif()
