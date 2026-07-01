cmake_minimum_required(VERSION 3.25)

set(VCPKG_INSTALLED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/ladybird/vcpkg_installed" CACHE PATH "" FORCE)
set(CMAKE_TOOLCHAIN_FILE "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/ladybird/Build/vcpkg/scripts/buildsystems/vcpkg.cmake" CACHE PATH "")
if (CMAKE_OSX_SYSROOT MATCHES "[iI][pP]hone[sS]imulator")
    set(VCPKG_TARGET_TRIPLET "arm64-ios-simulator" CACHE STRING "" FORCE)
else()
    set(VCPKG_TARGET_TRIPLET "arm64-ios" CACHE STRING "" FORCE)
endif()
set(VCPKG_MANIFEST_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/ladybird" CACHE PATH "" FORCE)
set(VCPKG_MANIFEST_INSTALL ON CACHE BOOL "" FORCE)
set(VCPKG_OVERLAY_PORTS "${CMAKE_CURRENT_SOURCE_DIR}/../third_party/ladybird/Meta/CMake/vcpkg/overlay-ports" CACHE STRING "")
set(VCPKG_OVERLAY_TRIPLETS "${CMAKE_CURRENT_SOURCE_DIR}/vcpkg-overlay-triplets" CACHE STRING "")

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

set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE BOTH)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY BOTH)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE BOTH)

# We never run `cmake --install` for the iOS build (artifacts are copied into the bundle via the
# POST_BUILD custom command below instead), and on a real-device build Ladybird's own
# UI/cmake/InstallRules.cmake fails configure because its install(TARGETS ${ladybird_helper_processes})
# call has no BUNDLE DESTINATION, which Xcode's device toolchain requires for MACOSX_BUNDLE
# executable targets (the simulator toolchain doesn't enforce this, which is why this only broke
# device builds). Skip install-rule processing entirely so neither platform hits it.
set(CMAKE_SKIP_INSTALL_RULES ON)

# Apple prohibits runtime code generation/JIT on iOS for third-party apps (no dynamic codesigning
# entitlement), so LibWasm's Cranelift-based WebAssembly JIT can never run there; its fault-recovery
# signal handler also assumes Linux's mcontext layout in its non-macOS branch, which doesn't match
# iOS's (identical to macOS's, since both are Darwin). Fall back to the interpreter-only stub path.
set(ENABLE_CRANELIFT_JIT OFF CACHE BOOL "" FORCE)

# LibJS's AsmInterpreter generates aarch64 assembly (asmint_aarch64.S) that uses the FJCVTZS
# instruction (ARMv8.3-A's "jsconv" extension), which the default arm64-apple-ios target CPU
# baseline doesn't enable (unlike macOS, where every Apple Silicon Mac supports it). Our
# iphoneos-version-min is 17.4, whose minimum-supported hardware (A12+) all supports ARMv8.3-A,
# so it's safe to just raise the assembler's target ISA to match.
set(CMAKE_ASM_FLAGS "${CMAKE_ASM_FLAGS} -march=armv8.3-a" CACHE STRING "" FORCE)

# __IOS__ is not a standard Apple SDK macro (unlike __APPLE__/__MACH__); AK/Platform.h uses it
# to define AK_OS_IOS, which most of Ladybird's platform-conditional code (#if defined(AK_OS_IOS))
# depends on to pick iOS-appropriate APIs over macOS-only ones (bootstrap.h, sys/disk.h,
# mach_vm.h, IOSurface/IOSurface.h vs IOSurfaceRef.h, ...). Must be defined globally, before
# add_subdirectory(LADYBIRD_DIR), so Ladybird's own libraries see it too -- not just our "engine"
# target.
add_compile_definitions(__IOS__=1)

# Must run before add_subdirectory(LADYBIRD_DIR): CMake's find_package()-created IMPORTED
# targets (OpenSSL::Crypto, OpenSSL::SSL) are only visible in the calling scope and in
# subdirectories added afterward. Ladybird's own subdirectories (LibCrypto, LibTLS,
# RequestServer, ...) link against these targets directly without calling find_package
# themselves, so if this runs after add_subdirectory those targets are undefined for them.
find_package(OpenSSL REQUIRED)

# Also must run before add_subdirectory(LADYBIRD_DIR): the old-style include_directories()
# command has the same scope-visibility rule as target_include_directories(), so Ladybird's own
# libraries (e.g. AK, which #includes its own CMake-generated AK/Debug.h and AK/Backtrace.h out
# of LADYBIRD_BINARY_DIR) need this in scope before their subdirectories are processed.
include_directories(
    "${CMAKE_CURRENT_BINARY_DIR}"
    "${CMAKE_CURRENT_BINARY_DIR}/Libraries"
    "${CMAKE_CURRENT_BINARY_DIR}/Services"
    "${LADYBIRD_BINARY_DIR}"
    "${LADYBIRD_BINARY_DIR}/Libraries"
    "${LADYBIRD_BINARY_DIR}/Services"
)

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
    "-framework CoreText"
    "-framework CoreGraphics"
)

# --- Single-process iOS ------------------------------------------------------------------
# There is no BrowserEngineKit entitlement available to us, so WebContent/RequestServer/
# ImageDecoder/Compositor/WebWorker no longer run as separate processes on iOS. Instead each
# one runs on its own thread inside this same engine dylib (see
# WebView::spawn_browser_engine_process in LibWebView/ProcessIOS.mm).
#
# Each service already builds a static library containing everything except its main.cpp
# (webcontentservice, requestserverservice, ...), produced by the existing, untouched
# Services/*/CMakeLists.txt. We link engine against those directly, and additionally compile
# each service's main.cpp straight into engine, renaming its `ladybird_main` entry point per
# service (via a per-source COMPILE_DEFINITIONS) so the five compiled-in mains don't collide.
# LibWebView/ProcessIOS.mm declares and calls these renamed entry points by name.
set(IOS_SINGLE_PROCESS_SERVICE_MAINS
    "${LADYBIRD_DIR}/Services/WebContent/main.cpp"
    "${LADYBIRD_DIR}/Services/RequestServer/main.cpp"
    "${LADYBIRD_DIR}/Services/ImageDecoder/main.cpp"
    "${LADYBIRD_DIR}/Services/Compositor/main.cpp"
    "${LADYBIRD_DIR}/Services/WebWorker/main.cpp"
)
set_source_files_properties("${LADYBIRD_DIR}/Services/WebContent/main.cpp" PROPERTIES COMPILE_DEFINITIONS "ladybird_main=webcontent_service_main")
set_source_files_properties("${LADYBIRD_DIR}/Services/RequestServer/main.cpp" PROPERTIES COMPILE_DEFINITIONS "ladybird_main=request_server_service_main")
set_source_files_properties("${LADYBIRD_DIR}/Services/ImageDecoder/main.cpp" PROPERTIES COMPILE_DEFINITIONS "ladybird_main=image_decoder_service_main")
set_source_files_properties("${LADYBIRD_DIR}/Services/Compositor/main.cpp" PROPERTIES COMPILE_DEFINITIONS "ladybird_main=compositor_service_main")
set_source_files_properties("${LADYBIRD_DIR}/Services/WebWorker/main.cpp" PROPERTIES COMPILE_DEFINITIONS "ladybird_main=webworker_service_main")

target_sources(engine PRIVATE
    ${IOS_SINGLE_PROCESS_SERVICE_MAINS}
    # apply_sandbox() definitions referenced by the mains above (all no-ops on iOS already).
    # RequestServer's sandbox shim is already compiled into requestserverservice.
    "${LADYBIRD_DIR}/Services/RendererSandboxMacOS.cpp"
    "${LADYBIRD_DIR}/Services/ImageDecoder/SandboxMacOS.cpp"
    "${LADYBIRD_DIR}/Services/Compositor/SandboxMacOS.cpp"
)

target_link_libraries(engine PRIVATE
    webcontentservice
    requestserverservice
    imagedecoderservice
    compositorservice
    webworkerservice
    LibSandbox
)
# -----------------------------------------------------------------------------------------

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
