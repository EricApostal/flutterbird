set(VCPKG_TARGET_ARCHITECTURE arm64)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE static)
set(VCPKG_CMAKE_SYSTEM_NAME iOS)
set(VCPKG_OSX_SYSROOT iphonesimulator)
set(VCPKG_OSX_DEPLOYMENT_TARGET 17.4)
set(VCPKG_MAKE_CONFIGURE_OPTIONS "--build=x86_64-apple-darwin")

# See arm64-ios.cmake for why this is needed: CMake's iOS platform support
# implicitly enables MACOSX_BUNDLE for executable targets under
# CMAKE_SYSTEM_NAME=iOS, which breaks vcpkg ports whose CLI tool executables
# only declare a RUNTIME install destination.
list(APPEND VCPKG_CMAKE_CONFIGURE_OPTIONS "-DCMAKE_MACOSX_BUNDLE=OFF")
