cd /Users/eric/Documents/development/projects/flutterbird/packages/libbird/android

/Users/eric/Library/Android/sdk/cmake/3.22.1/bin/cmake \
  -H/Users/eric/Documents/development/projects/flutterbird/packages/libbird/android \
  -DCMAKE_SYSTEM_NAME=Android \
  -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
  -DCMAKE_SYSTEM_VERSION=30 \
  -DANDROID_PLATFORM=android-30 \
  -DANDROID_ABI=arm64-v8a \
  -DCMAKE_ANDROID_ARCH_ABI=arm64-v8a \
  -DANDROID_NDK=/Users/eric/Library/Android/sdk/ndk/27.0.12077973 \
  -DCMAKE_ANDROID_NDK=/Users/eric/Library/Android/sdk/ndk/27.0.12077973 \
  -DCMAKE_TOOLCHAIN_FILE=/Users/eric/Library/Android/sdk/ndk/27.0.12077973/build/cmake/android.toolchain.cmake \
  -DCMAKE_MAKE_PROGRAM=/Users/eric/Library/Android/sdk/cmake/3.22.1/bin/ninja \
  "-DCMAKE_CXX_FLAGS=-std=c++2b -frtti -fexceptions -D__ANDROID_API__=30 -D__GCC_DESTRUCTIVE_SIZE=64 -Wno-invalid-constexpr" \
  -DCMAKE_LIBRARY_OUTPUT_DIRECTORY=/Users/eric/Documents/development/projects/flutterbird/build/ladybird/intermediates/cxx/RelWithDebInfo/656l5o1b/obj/arm64-v8a \
  -DCMAKE_RUNTIME_OUTPUT_DIRECTORY=/Users/eric/Documents/development/projects/flutterbird/build/ladybird/intermediates/cxx/RelWithDebInfo/656l5o1b/obj/arm64-v8a \
  -DCMAKE_BUILD_TYPE=RelWithDebInfo \
  -B/Users/eric/Documents/development/projects/flutterbird/packages/libbird/android/.cxx/RelWithDebInfo/656l5o1b/arm64-v8a \
  -GNinja \
  -DANDROID_STL=c++_shared