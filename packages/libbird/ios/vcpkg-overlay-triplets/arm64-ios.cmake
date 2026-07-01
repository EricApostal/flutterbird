set(VCPKG_TARGET_ARCHITECTURE arm64)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE static)
set(VCPKG_CMAKE_SYSTEM_NAME iOS)
set(VCPKG_OSX_DEPLOYMENT_TARGET 17.4)
set(VCPKG_MAKE_CONFIGURE_OPTIONS "--build=x86_64-apple-darwin")

# CMake's iOS platform support defaults MACOSX_BUNDLE to ON for executable targets when
# CMAKE_SYSTEM_NAME=iOS and the SDK is the device SDK (iphoneos) -- unlike the simulator SDK,
# which doesn't enforce this. Several vcpkg ports (e.g. libwebp's img2webp/webpmux CLI tools)
# install() their executables with only a RUNTIME destination, which is valid for a plain CLI
# tool but fails CMake's validation once MACOSX_BUNDLE is implicitly true. We don't need these
# helper executables to be real iOS app bundles, so force the bundle requirement off.
list(APPEND VCPKG_CMAKE_CONFIGURE_OPTIONS "-DCMAKE_MACOSX_BUNDLE=OFF")
