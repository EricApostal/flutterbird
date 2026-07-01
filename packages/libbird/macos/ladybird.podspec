#
# ladybird.podspec
#
# Build strategy mirrors the Linux CMakeLists.txt:
#   - A before_compile script phase drives cmake in packages/libbird/cpp/build
#     (cpp/CMakeLists.txt runs ensure_ladybird_source.sh, builds Ladybird via
#     python3 Meta/ladybird.py, and produces LadybirdBundle/)
#   - An after_compile script phase deploys the bundle into the app.
#
# LadybirdBundle layout (produced by cpp/CMakeLists.txt on Apple):
#   LadybirdBundle/
#     libengine.dylib          (RPATH: @loader_path/ladybird_libs)
#     libraries/               all Ladybird dylibs from Build/release/lib
#     binaries/                WebContent, RequestServer, ImageDecoder, WebWorker, Ladybird
#     res/                     Ladybird Base/res resources

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

  s.platform     = :osx, '12.0'
  s.swift_version = '5.0'
  s.dependency 'FlutterMacOS'

  s.frameworks = 'Cocoa', 'CoreFoundation', 'CoreVideo', 'Foundation',
                 'IOSurface', 'Metal', 'QuartzCore', 'UniformTypeIdentifiers'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE'           => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++2b',
    'CLANG_CXX_LIBRARY'        => 'libc++',
    'OTHER_CPLUSPLUSFLAGS'     => '-fobjc-arc -Wno-deprecated-anon-enum-enum-conversion',

    'VALID_ARCHS'                    => 'arm64',
    'EXCLUDED_ARCHS[sdk=macosx*]'    => 'x86_64',

    # libengine.dylib lives in LadybirdBundle/ after the cmake build.
    'LIBRARY_SEARCH_PATHS' => [
      '$(inherited)',
      '"${PODS_TARGET_SRCROOT}/../cpp/build/LadybirdBundle"'
    ].join(' '),

    # At runtime the engine is deployed to Contents/Resources/; helpers
    # in Contents/MacOS/ also need to reach Contents/Resources/ladybird_libs/.
    'LD_RUNPATH_SEARCH_PATHS' => [
      '$(inherited)',
      '@executable_path/../Resources',
      '@loader_path/../../Resources'
    ].join(' '),

    # Only link to -lengine; it already pulls in all lagom + skia deps.
    'OTHER_LDFLAGS' => [
      '$(inherited)',
      '-framework Cocoa -framework Metal -framework QuartzCore -framework UniformTypeIdentifiers',
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
      '"${PODS_TARGET_SRCROOT}/../third_party/ladybird/Build/release/vcpkg_installed/arm64-osx-dynamic/include"'
    ].join(' ')
  }

  s.script_phases = [
    # ── Phase 1: build engine (mirrors Linux add_subdirectory(../cpp)) ──────
    {
      :name               => 'Build Ladybird Engine',
      :execution_position => :before_compile,
      :script             => <<~SCRIPT
        set -e
        CPP_DIR="${PODS_TARGET_SRCROOT}/../cpp"
        mkdir -p "${CPP_DIR}/build"
        cd "${CPP_DIR}/build"
        cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=arm64 ..
        make -j$(sysctl -n hw.ncpu)
      SCRIPT
    },

    # ── Phase 2: deploy bundle into the app ────────────────────────────────
    {
      :name               => 'Deploy Ladybird Bundle into App',
      :execution_position => :after_compile,
      :script             => <<~SCRIPT
        set -e
        BUNDLE_DIR="${PODS_TARGET_SRCROOT}/../cpp/build/LadybirdBundle"

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
        DEST_BIN_DIR="${APP_PATH}/Contents/MacOS"
        DEST_RES_DIR="${APP_PATH}/Contents/Resources"

        mkdir -p "${DEST_BIN_DIR}"
        mkdir -p "${DEST_RES_DIR}/ladybird_libs"

        # Engine dylib — engine's RPATH is @loader_path/ladybird_libs, so
        # ladybird_libs/ must sit next to libengine.dylib in Resources/.
        cp -af "${BUNDLE_DIR}/libengine.dylib" "${DEST_RES_DIR}/" || true
        cp -af "${BUNDLE_DIR}/libraries/." "${DEST_RES_DIR}/ladybird_libs/" || true

        # Helper processes (WebContent, RequestServer, ImageDecoder, etc.)
        for helper in "${BUNDLE_DIR}/binaries/"*; do
          [ -f "$helper" ] || continue
          DEST_HELPER="${DEST_BIN_DIR}/$(basename "$helper")"
          cp -af "$helper" "${DEST_BIN_DIR}/"
          chmod +w "${DEST_HELPER}"
          
          # The following was added by claude. I am pretty sure it's not useful, and
          # was a different bug with ladybird itself. However, this does work, so idk
          # Ladybird's own build (Meta/CMake/lagom_install_options.cmake) bakes in
          # a raw absolute rpath pointing at its vcpkg build-tree lib dir, so that
          # running its binaries directly from the build tree works out of the
          # box for upstream dev workflows. Once we copy these binaries into our
          # own sandboxed app bundle, dyld still tries that raw dev-tree path
          # first (it's listed before the rpath we add below), and the sandbox
          # correctly denies reading outside the bundle -- killing the process
          # before it ever falls through to the working, bundled copy. Strip any
          # rpath pointing into the local checkout before adding the real one.
          otool -l "${DEST_HELPER}" | awk '/cmd LC_RPATH/{getline; getline; print $2}' | while read -r existing_rpath; do
            case "$existing_rpath" in
              */third_party/ladybird/Build/*)
                install_name_tool -delete_rpath "$existing_rpath" "${DEST_HELPER}" 2>/dev/null || true
                ;;
            esac
          done

          install_name_tool -add_rpath "@executable_path/../Resources/ladybird_libs" \
            "${DEST_HELPER}" 2>/dev/null || true
        done

        # Ladybird data resources (Base/res)
        if [ -d "${BUNDLE_DIR}/res" ]; then
          cp -af "${BUNDLE_DIR}/res" "${DEST_RES_DIR}/"
        fi
      SCRIPT
    }
  ]
end