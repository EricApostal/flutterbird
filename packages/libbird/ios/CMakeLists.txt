cmake_minimum_required(VERSION 3.25)

set(CMAKE_TOOLCHAIN_FILE "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/ladybird/Build/vcpkg/scripts/buildsystems/vcpkg.cmake" CACHE PATH "")
set(VCPKG_TARGET_TRIPLET "arm64-ios" CACHE STRING "")
set(VCPKG_MANIFEST_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/ladybird" CACHE PATH "" FORCE)
if (NOT DEFINED VCPKG_MANIFEST_INSTALL)
    set(VCPKG_MANIFEST_INSTALL ON CACHE BOOL "" FORCE)
endif()
set(VCPKG_OVERLAY_PORTS "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/ladybird/Meta/CMake/vcpkg/overlay-ports" CACHE STRING "")

project(ladybird_ios LANGUAGES CXX)

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

set(CMAKE_SYSTEM_PROCESSOR "arm64")
add_subdirectory("${LADYBIRD_DIR}" "${LADYBIRD_BINARY_DIR}")

set(LADYBIRD_MIRRORED_GENERATED_FILES "")
function(link_ladybird_generated_file relative_path)
    get_filename_component(relative_directory "${relative_path}" DIRECTORY)
    set(source_path "${LADYBIRD_BINARY_DIR}/${relative_path}")
    set(destination_path "${CMAKE_CURRENT_BINARY_DIR}/${relative_path}")
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

include_directories(
    "${CMAKE_CURRENT_BINARY_DIR}"
    "${CMAKE_CURRENT_BINARY_DIR}/Libraries"
    "${CMAKE_CURRENT_BINARY_DIR}/Services"
    "${LADYBIRD_BINARY_DIR}"
    "${LADYBIRD_BINARY_DIR}/Libraries"
    "${LADYBIRD_BINARY_DIR}/Services"
)

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

add_custom_target(ladybird_generated_file_mirrors DEPENDS ${LADYBIRD_MIRRORED_GENERATED_FILES})
foreach(mirror_consumer_target IN ITEMS compositorservice webcontentservice webworkerservice)
    if (TARGET ${mirror_consumer_target})
        add_dependencies(${mirror_consumer_target} ladybird_generated_file_mirrors)
    endif()
endforeach()

add_library(engine SHARED
    "${CMAKE_CURRENT_SOURCE_DIR}/../cpp/engine.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/../cpp/platform/view_backend.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/../cpp/platform/macos_view_backend.cpp"
)

if (CMAKE_CXX_COMPILER_ID MATCHES "Clang")
    target_compile_options(engine PRIVATE -Wno-unqualified-std-cast-call -Wno-user-defined-literals)
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
    "-framework CoreFoundation"
    "-framework CoreVideo"
    "-framework IOSurface"
    "-framework Metal"
    "-framework Foundation"
    "-framework BrowserEngineKit"
    "-framework CoreText"
    "-framework CoreGraphics"
)

set_target_properties(engine PROPERTIES
    CXX_STANDARD 23
    CXX_STANDARD_REQUIRED ON
    PREFIX "lib"
    SUFFIX ".dylib"
    BUILD_WITH_INSTALL_RPATH TRUE
    INSTALL_RPATH "@loader_path/ladybird_libs"
    INSTALL_NAME_DIR "@rpath"
)

add_custom_command(TARGET engine PRE_LINK
    COMMAND bash "${CMAKE_CURRENT_SOURCE_DIR}/../cpp/patch_rust_alloc.sh"
    WORKING_DIRECTORY "${CMAKE_CURRENT_BINARY_DIR}"
)

set(BUNDLE_DIR "${CMAKE_BINARY_DIR}/LadybirdBundle")
add_custom_command(TARGET engine POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E make_directory "${BUNDLE_DIR}/libraries"
    COMMAND ${CMAKE_COMMAND} -E copy "$<TARGET_FILE:engine>" "${BUNDLE_DIR}/"
    COMMAND ${CMAKE_COMMAND} -E copy_directory "${LADYBIRD_DIR}/Base/res" "${BUNDLE_DIR}/res"
    COMMAND ${CMAKE_COMMAND} -E copy_directory "${LADYBIRD_BINARY_DIR}/lib" "${BUNDLE_DIR}/libraries"
)
