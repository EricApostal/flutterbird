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
                 'IOSurface', 'Metal', 'QuartzCore', 'UniformTypeIdentifiers', 'BrowserEngineKit'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE'           => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++2b',
    'CLANG_CXX_LIBRARY'        => 'libc++',
    'OTHER_CPLUSPLUSFLAGS'     => '-fobjc-arc -Wno-deprecated-anon-enum-enum-conversion',

    'VALID_ARCHS'                    => 'arm64',

    # libengine.dylib lives in LadybirdBundle/ after the cmake build.
    'LIBRARY_SEARCH_PATHS' => [
      '$(inherited)',
      '"${PODS_TARGET_SRCROOT}/../cpp/build_ios/LadybirdBundle"'
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
      '-framework Metal -framework QuartzCore -framework UniformTypeIdentifiers -framework BrowserEngineKit',
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
        mkdir -p "${CPP_DIR}/build_ios"
        cd "${CPP_DIR}/build_ios"
        
        unset CFLAGS CXXFLAGS LDFLAGS CC CXX CPP
        
        # Cross compile for iOS
        cmake -G Ninja -DCMAKE_BUILD_TYPE=Release \\
              -DCMAKE_SYSTEM_NAME=iOS \\
              -DCMAKE_OSX_ARCHITECTURES=arm64 \\
              -DCMAKE_OSX_SYSROOT=iphoneos \\
              -DCMAKE_OSX_DEPLOYMENT_TARGET=17.4 \\
              -DVCPKG_MANIFEST_INSTALL=OFF \\
              "${PODS_TARGET_SRCROOT}"
              
        ninja engine WebContent RequestServer Compositor ImageDecoder WebWorker -j$(sysctl -n hw.ncpu)
      SCRIPT
    },

    # ── Phase 2: deploy bundle into the app ────────────────────────────────
    {
      :name               => 'Deploy Ladybird Bundle into iOS App',
      :execution_position => :after_compile,
      :script             => <<~SCRIPT
        set -e
        BUNDLE_DIR="${PODS_TARGET_SRCROOT}/../cpp/build_ios/LadybirdBundle"

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

        # Ladybird data resources (Base/res)
        if [ -d "${BUNDLE_DIR}/res" ]; then
          cp -af "${BUNDLE_DIR}/res" "${DEST_RES_DIR}/"
        fi
        
        # NOTE: App Extension binaries (WebContent, RequestServer, etc.) 
        # MUST be compiled as Xcode App Extension targets and bundled inside PlugIns/.
        # We do not copy them manually here since Xcode must sign them with correct entitlements.
      SCRIPT
    }
  ]
end
