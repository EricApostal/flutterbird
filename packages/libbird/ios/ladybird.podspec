#
# ladybird.podspec (iOS)
#
# Build strategy mirrors the macOS script, but cross-compiles for iOS:
#   - A before_compile script phase drives cmake in packages/libbird/cpp/build_ios
#   - An after_compile script phase deploys the bundle into the app.
#

plugin_root = File.expand_path('..', __dir__)

Pod::Spec.new do |s|
  s.name             = 'ladybird'
  s.version          = '0.0.1'
  s.summary          = 'Ladybird interface for Flutter.'
  s.homepage         = 'https://github.com/EricApostal/flutterbird'
  s.license          = { :type => 'BSD', :file => '../LICENSE' }
  s.author           = { 'Eric Apostal' => 'eric@rubiscoapp.com' }
  s.source           = { :git => 'https://github.com/EricApostal/flutterbird.git', :tag => s.version.to_s }

  s.source_files        = 'Classes/**/*'
  s.public_header_files = 'Classes/**/*.h'

  s.platform     = :ios, '17.4'
  s.swift_version = '5.0'
  s.dependency 'Flutter'

  s.frameworks = 'CoreFoundation', 'CoreVideo', 'Foundation',
                 'IOSurface', 'Metal', 'QuartzCore', 'UniformTypeIdentifiers'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE'           => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++2b',
    'CLANG_CXX_LIBRARY'        => 'libc++',
    'OTHER_CPLUSPLUSFLAGS'     => '-fobjc-arc -Wno-deprecated-anon-enum-enum-conversion',

    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386 x86_64',

    # libengine.dylib lives in LadybirdBundle/ after the cmake build.
    'LIBRARY_SEARCH_PATHS' => [
      '$(inherited)',
      '"${PODS_TARGET_SRCROOT}/../cpp/build_$(PLATFORM_NAME)/LadybirdBundle"'
    ].join(' '),

    # At runtime the engine is deployed to Frameworks/; helpers
    # need to reach Frameworks/ladybird_libs/.
    'LD_RUNPATH_SEARCH_PATHS' => [
      '$(inherited)',
      '@executable_path/Frameworks',
      '@loader_path/Frameworks'
    ].join(' '),

    # Only link to -lengine; it already pulls in all lagom + skia deps.
    'OTHER_LDFLAGS' => [
      '$(inherited)',
      '-framework Metal -framework QuartzCore -framework UniformTypeIdentifiers',
      '-lengine'
    ].join(' '),

    'HEADER_SEARCH_PATHS' => [
      '$(inherited)',
      '"${PODS_TARGET_SRCROOT}/../third_party/ladybird/UI/AppKit"',
      '"${PODS_TARGET_SRCROOT}/../third_party/ladybird"',
      '"${PODS_TARGET_SRCROOT}/../third_party/ladybird/Libraries"',
      '"${PODS_TARGET_SRCROOT}/../third_party/ladybird/Services"',
      '"${PODS_TARGET_SRCROOT}/../third_party/ladybird/Build/release"',
      '"${PODS_TARGET_SRCROOT}/../third_party/ladybird/Build/release/Lagom"',
      '"${PODS_TARGET_SRCROOT}/../third_party/ladybird/Build/release/Lagom/Libraries"',
      '"${PODS_TARGET_SRCROOT}/../third_party/ladybird/Build/release/Lagom/Services"',
      '"${PODS_TARGET_SRCROOT}/../third_party/ladybird/Build/release/vcpkg_installed/arm64-ios-dynamic/include"'
    ].join(' ')
  }

  s.script_phases = [
    # ── Phase 1: build engine ──────
    {
      :name               => 'Build Ladybird Engine (iOS)',
      :execution_position => :before_compile,
      :script             => <<~SCRIPT
        set -e
        CPP_DIR="${PODS_TARGET_SRCROOT}/../cpp"
        PLATFORM=${PLATFORM_NAME:-iphoneos}
        BUILD_DIR_NAME="build_${PLATFORM}"
        mkdir -p "${CPP_DIR}/${BUILD_DIR_NAME}"
        cd "${CPP_DIR}/${BUILD_DIR_NAME}"
        
        # Xcode sets SDKROOT to the iOS simulator SDK, which leaks into
        # vcpkg's cmake-get-vars for host-native tools (arm64-osx) and causes
        # them to be compiled against the simulator SDK instead of macOS.
        unset CFLAGS CXXFLAGS LDFLAGS CC CXX CPP SDKROOT IPHONEOS_DEPLOYMENT_TARGET
        
        if [ "$PLATFORM" = "iphonesimulator" ]; then
            TRIPLET="arm64-ios-simulator"
        else
            TRIPLET="arm64-ios"
        fi

        # Wipe the arm64-osx cmake-get-vars cache so vcpkg recomputes compiler
        # flags against the macOS SDK (not the iOS simulator SDK that Xcode has
        # in SDKROOT when building for iphonesimulator).
        VCPKG_BUILDTREES="${PODS_TARGET_SRCROOT}/../third_party/ladybird/Build/vcpkg/buildtrees"
        if [ -d "${VCPKG_BUILDTREES}" ]; then
          find "${VCPKG_BUILDTREES}" -name "cmake-get-vars_C_CXX-arm64-osx*.cmake.log" -delete
        fi

        # Cross compile for iOS
        cmake -G Ninja -DCMAKE_BUILD_TYPE=Release \\
              -DCMAKE_SYSTEM_NAME=iOS \\
              -DCMAKE_OSX_ARCHITECTURES="arm64" \\
              -DCMAKE_OSX_SYSROOT=${PLATFORM} \\
              -DCMAKE_OSX_DEPLOYMENT_TARGET=17.4 \\
              -DVCPKG_MANIFEST_INSTALL=OFF \\
              -DVCPKG_INSTALLED_DIR="${PODS_TARGET_SRCROOT}/../third_party/ladybird/vcpkg_installed" \\
              -DVCPKG_TARGET_TRIPLET="${TRIPLET}" \\
              -DVCPKG_OVERLAY_TRIPLETS="${PODS_TARGET_SRCROOT}/vcpkg-overlay-triplets" \\
              "${PODS_TARGET_SRCROOT}"
              
        # Single-process iOS: WebContent/RequestServer/Compositor/ImageDecoder/WebWorker are
        # compiled directly into libengine.dylib (see packages/libbird/ios/CMakeLists.txt) and
        # run as threads inside the host app instead of as separate processes/extensions, so we
        # no longer need to build their standalone executables here.
        ninja engine -j$(sysctl -n hw.ncpu)
      SCRIPT
    },

    # ── Phase 2: deploy bundle into the app ────────────────────────────────
    {
      :name               => 'Deploy Ladybird Bundle into iOS App',
      :execution_position => :after_compile,
      :script             => <<~SCRIPT
        PLATFORM=${PLATFORM_NAME:-iphoneos}
        BUNDLE_DIR="${PODS_TARGET_SRCROOT}/../cpp/build_${PLATFORM}/LadybirdBundle"

        APP_BUILD_DIR=$(dirname "${BUILT_PRODUCTS_DIR}")
        APP_NAME_FILE="${PODS_ROOT}/../Flutter/ephemeral/.app_filename"

        if [ -f "$APP_NAME_FILE" ]; then
          APP_NAME=$(cat "$APP_NAME_FILE")
        else
          EXISTING_APP=$(ls -1d "${APP_BUILD_DIR}"/*.app 2>/dev/null | head -n 1)
          if [ -n "$EXISTING_APP" ]; then
            APP_NAME=$(basename "$EXISTING_APP")
          else
            APP_NAME="Runner.app"
          fi
        fi

        APP_PATH="${APP_BUILD_DIR}/${APP_NAME}"
        DEST_FWK_DIR="${APP_PATH}/Frameworks"
        DEST_RES_DIR="${APP_PATH}"

        mkdir -p "${DEST_FWK_DIR}/ladybird_libs"

        # Engine dylib
        cp -af "${BUNDLE_DIR}/libengine.dylib" "${DEST_FWK_DIR}/" || true
        cp -af "${BUNDLE_DIR}/libraries/." "${DEST_FWK_DIR}/ladybird_libs/" || true

        TRIPLET="arm64-ios"
        if [ "${PLATFORM}" = "iphonesimulator" ]; then
            TRIPLET="arm64-ios-simulator"
        fi
        VCPKG_LIB_DIR="${PODS_TARGET_SRCROOT}/../third_party/ladybird/vcpkg_installed/${TRIPLET}/lib"
        if [ -d "$VCPKG_LIB_DIR" ]; then
            cp -af "$VCPKG_LIB_DIR/"*.dylib "${DEST_FWK_DIR}/ladybird_libs/" || true
        fi
        
        for dylib in "${DEST_FWK_DIR}/ladybird_libs/"*.dylib; do
            if [ -f "$dylib" ]; then
                base=$(basename "$dylib")
                install_name_tool -id "@rpath/$base" "$dylib" || true
                
                OLD_PATH=$(otool -L "${DEST_FWK_DIR}/libengine.dylib" | grep "$base" | awk '{print $1}' || true)
                for path in $OLD_PATH; do
                    install_name_tool -change "$path" "@loader_path/ladybird_libs/$base" "${DEST_FWK_DIR}/libengine.dylib" || true
                done
                
                for other_dylib in "${DEST_FWK_DIR}/ladybird_libs/"*.dylib; do
                    if [ -f "$other_dylib" ] && [ "$other_dylib" != "$dylib" ]; then
                        OLD_DEP_PATH=$(otool -L "$other_dylib" | grep "$base" | awk '{print $1}' || true)
                        for path in $OLD_DEP_PATH; do
                            install_name_tool -change "$path" "@loader_path/$base" "$other_dylib" || true
                        done
                    fi
                done
            fi
        done

        # Ladybird data resources (Base/res)
        if [ -d "${BUNDLE_DIR}/res" ]; then
            cp -af "${BUNDLE_DIR}/res" "${DEST_RES_DIR}/"
        fi

        # Single-process iOS: WebContent/RequestServer/Compositor/ImageDecoder/WebWorker run as
        # threads inside libengine.dylib (see LibWebView/ProcessIOS.mm). There are no separate
        # App Extension binaries to sign or embed in PlugIns/ anymore.
      SCRIPT
    }
  ]
end
