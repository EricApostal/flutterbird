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

set(LADYBIRD_ANDROID_ASSETS_DIR "${CMAKE_CURRENT_BINARY_DIR}/generated_ladybird_assets")
set(LADYBIRD_ANDROID_ASSETS_OUTPUT_PATH_OVERRIDE "${LADYBIRD_ANDROID_ASSETS_DIR}/ladybird-assets.zip")
set(LADYBIRD_MIRRORED_GENERATED_FILES "")

function(link_ladybird_generated_file relative_path)
    get_filename_component(relative_directory "${relative_path}" DIRECTORY)
    set(source_path "${LADYBIRD_BINARY_DIR}/${relative_path}")
    set(destination_path "${CMAKE_CURRENT_BINARY_DIR}/${relative_path}")

    # Previous builds may leave stale symlinks in place; remove them so Ninja
    # owns the mirrored output lifecycle.
    if (IS_SYMLINK "${destination_path}")
        file(REMOVE "${destination_path}")
    endif()

    add_custom_command(
        OUTPUT "${destination_path}"
        COMMAND "${CMAKE_COMMAND}" -E make_directory "${CMAKE_CURRENT_BINARY_DIR}/${relative_directory}"
        COMMAND "${CMAKE_COMMAND}" -E copy_if_different "${source_path}" "${destination_path}"
        DEPENDS "${source_path}"
        VERBATIM
    )
    set_source_files_properties("${destination_path}" PROPERTIES GENERATED TRUE)

    list(APPEND LADYBIRD_MIRRORED_GENERATED_FILES "${destination_path}")
    set(LADYBIRD_MIRRORED_GENERATED_FILES "${LADYBIRD_MIRRORED_GENERATED_FILES}" PARENT_SCOPE)
endfunction()

# Ladybird assumes its generated headers are reachable from the build root.
# When built as a subdirectory under libbird, expose the Ladybird sub-build
# roots before add_subdirectory() so targets like AK can see generated headers
# such as AK/Debug.h and AK/Backtrace.h.
include_directories(
    "${CMAKE_CURRENT_BINARY_DIR}"
    "${CMAKE_CURRENT_BINARY_DIR}/Libraries"
    "${CMAKE_CURRENT_BINARY_DIR}/Services"
    "${LADYBIRD_BINARY_DIR}"
    "${LADYBIRD_BINARY_DIR}/Libraries"
    "${LADYBIRD_BINARY_DIR}/Services"
)

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

# AGP injects output directories for JNI packaging. Preserve these before
# including Ladybird because upstream CMake can override global output dirs.
set(AGP_LIBRARY_OUTPUT_DIRECTORY "${CMAKE_LIBRARY_OUTPUT_DIRECTORY}")
set(AGP_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_RUNTIME_OUTPUT_DIRECTORY}")

set(PLUGIN_NAME "ladybird_plugin")

add_library(${PLUGIN_NAME} SHARED
    src/main/cpp/ladybird_plugin_jni.cpp
)

file(MAKE_DIRECTORY "${LADYBIRD_ANDROID_ASSETS_DIR}")

add_subdirectory("${LADYBIRD_DIR}" "${LADYBIRD_BINARY_DIR}")

# Ladybird's subproject build still has a few generated-source paths rooted at
# ${CMAKE_BINARY_DIR}. Mirror those paths into the wrapper build root so the
# vendored targets can compile without patching upstream CMake files.
foreach(generated_file IN ITEMS
    "Libraries/LibWeb/WebGL/GLFunctions.h"
    "Libraries/LibWeb/WebGL/GLFunctions.cpp"
    "Libraries/LibWeb/WebGL/WebGLCommands.h"
    "Libraries/LibWeb/WebGL/WebGLCommands.cpp"
    "Libraries/LibWeb/WebGL/WebGLContextProxy.h"
    "Libraries/LibWeb/WebGL/WebGLContextProxy.cpp"
)
    link_ladybird_generated_file("${generated_file}")
endforeach()

add_custom_target(ladybird_generated_file_mirrors
    DEPENDS ${LADYBIRD_MIRRORED_GENERATED_FILES}
)

foreach(mirror_consumer_target IN ITEMS compositorservice webcontentservice webworkerservice)
    if (TARGET ${mirror_consumer_target})
        add_dependencies(${mirror_consumer_target} ladybird_generated_file_mirrors)
    endif()
endforeach()

# TODO: This is a workaround for a bug in ladybird. This is actually handled,
# but android is not included in that check
if (ANDROID AND NOT BUILD_SHARED_LIBS)
    foreach(helper_process IN ITEMS Compositor ImageDecoder RequestServer WebContent WebWorker)
        if (TARGET ${helper_process})
            target_link_options(${helper_process} PRIVATE LINKER:--allow-multiple-definition)
        endif()
    endforeach()

    if (TARGET ladybird)
        target_link_options(ladybird PRIVATE LINKER:--allow-multiple-definition)
    endif()
endif()

add_library(engine SHARED
    "${CMAKE_CURRENT_SOURCE_DIR}/../cpp/engine.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/../cpp/platform/view_backend.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/../cpp/platform/linux_view_backend.cpp"
)

if (CMAKE_CXX_COMPILER_ID MATCHES "Clang")
    target_compile_options(engine PRIVATE
        -Wno-unqualified-std-cast-call
        -Wno-user-defined-literals
    )
endif()

target_include_directories(engine PRIVATE
    "${LADYBIRD_DIR}"
    "${LADYBIRD_DIR}/Libraries"
    "${LADYBIRD_DIR}/Userland/Libraries"
    "${LADYBIRD_DIR}/Services"
    "${CMAKE_CURRENT_BINARY_DIR}"
    "${CMAKE_CURRENT_BINARY_DIR}/Libraries"
    "${CMAKE_CURRENT_BINARY_DIR}/Services"
    "${LADYBIRD_BINARY_DIR}"
    "${LADYBIRD_BINARY_DIR}/Libraries"
    "${LADYBIRD_BINARY_DIR}/Services"
    "${LADYBIRD_BINARY_DIR}/Lagom"
    "${LADYBIRD_BINARY_DIR}/Lagom/Libraries"
    "${LADYBIRD_BINARY_DIR}/Lagom/Services"
)

target_include_directories(${PLUGIN_NAME} PRIVATE
    "${CMAKE_CURRENT_SOURCE_DIR}/../cpp"
)

find_package(OpenSSL REQUIRED)

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

if (ANDROID AND NOT BUILD_SHARED_LIBS)
    target_link_options(engine PRIVATE LINKER:--allow-multiple-definition)
endif()


target_link_libraries(${PLUGIN_NAME} PRIVATE engine log android)

if (AGP_LIBRARY_OUTPUT_DIRECTORY)
    set_target_properties(${PLUGIN_NAME} PROPERTIES
        LIBRARY_OUTPUT_DIRECTORY "${AGP_LIBRARY_OUTPUT_DIRECTORY}"
    )
    set_target_properties(engine PROPERTIES
        LIBRARY_OUTPUT_DIRECTORY "${AGP_LIBRARY_OUTPUT_DIRECTORY}"
    )
endif()

if (AGP_RUNTIME_OUTPUT_DIRECTORY)
    set_target_properties(${PLUGIN_NAME} PROPERTIES
        RUNTIME_OUTPUT_DIRECTORY "${AGP_RUNTIME_OUTPUT_DIRECTORY}"
    )
    set_target_properties(engine PROPERTIES
        RUNTIME_OUTPUT_DIRECTORY "${AGP_RUNTIME_OUTPUT_DIRECTORY}"
    )
endif()

# Standard C++2b is required by Ladybird
set_target_properties(${PLUGIN_NAME} PROPERTIES
    CXX_STANDARD 23
    CXX_STANDARD_REQUIRED ON
)

set_target_properties(engine PROPERTIES
    CXX_STANDARD 23
    CXX_STANDARD_REQUIRED ON
)
