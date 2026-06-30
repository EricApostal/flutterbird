set(VCPKG_TARGET_ARCHITECTURE arm64)
set(VCPKG_CRT_LINKAGE dynamic)
set(VCPKG_LIBRARY_LINKAGE static)

set(VCPKG_CMAKE_SYSTEM_NAME Darwin)
set(VCPKG_OSX_ARCHITECTURES arm64)
# Explicitly pin to the macOS SDK so that when Xcode sets SDKROOT to the iOS
# simulator SDK (during an arm64-ios-simulator build), the host-native tools
# built under this triplet (e.g. pkgconf, gperf) are still compiled against
# the macOS SDK and can actually execute on the build machine.
set(VCPKG_OSX_SYSROOT macosx)
