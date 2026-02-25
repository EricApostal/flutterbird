#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint libbird.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'libbird'
  s.version          = '0.0.1'
  s.summary          = 'Ladybird embedding for Flutter.'
  s.description      = <<-DESC
Ladybird embedding for Flutter.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }
  s.source           = { :path => '.' }
  
  # Ensure CocoaPods grabs your Swift files
  s.source_files     = 'libbird/Sources/libbird/**/*.swift'
  s.resource_bundles = {'libbird_privacy' => ['libbird/Sources/libbird/PrivacyInfo.xcprivacy']}
  s.dependency 'FlutterMacOS'

  s.platform = :osx, '11.0'

  # 1. Wire up the headers, dynamic libraries, and C++23 requirements
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'HEADER_SEARCH_PATHS' => '"${PODS_TARGET_SRCROOT}/../third_party/ladybird" "${PODS_TARGET_SRCROOT}/../third_party/ladybird/Build/release"',
    'LIBRARY_SEARCH_PATHS' => '"${PODS_TARGET_SRCROOT}/../third_party/ladybird/Build/release/lib"',
    
    # We link against the dynamic libraries GN generates
    'OTHER_LDFLAGS' => '-framework Cocoa -framework Metal -framework QuartzCore -framework UniformTypeIdentifiers -llagom-web -llagom-js -llagom-core -llagom-gfx -llagom-ipc',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++2b',
    'LD_RUNPATH_SEARCH_PATHS' => '$(inherited) @executable_path/../Frameworks/libbird.framework/Resources/Ladybird.app/Contents/lib'
  }

  # 2. The Build and Package Script Phase
  s.script_phases = [
    {
      :name => 'Build Ladybird & Bundle Artifacts',
      :execution_position => :after_compile,
      :script => '
        set -e
        echo "--- LADYBIRD COCOAPODS BUILD START ---"

        # PODS_TARGET_SRCROOT points to the macos directory of this plugin
        PLUGIN_ROOT="${PODS_TARGET_SRCROOT}/.."
        LADYBIRD_SRC="${PLUGIN_ROOT}/third_party/ladybird"

        # 1. Build Ladybird Engine
        echo "Building Ladybird in ${LADYBIRD_SRC}..."
        cd "$LADYBIRD_SRC"
        ./Meta/ladybird.py build
        cd -

        # 2. Package Artifacts into the Plugin Framework
        FRAMEWORK_DIR="${TARGET_BUILD_DIR}/${WRAPPER_NAME}"
        echo "Packaging Ladybird.app into framework: $FRAMEWORK_DIR"

        if [ -d "$FRAMEWORK_DIR" ]; then
            mkdir -p "$FRAMEWORK_DIR/Resources"
            # We copy the entire Ladybird.app so internal rpaths between executables/dylibs remain valid
            # Use -L to dereference symlinks (e.g., Contents/lib to the build output lib dir)
            rsync -aL --delete "${LADYBIRD_SRC}/Build/release/bin/Ladybird.app" "$FRAMEWORK_DIR/Resources/"
            
            # Point libbird.framework directly to the bundled dylibs via @loader_path
            LIB_BIN="$FRAMEWORK_DIR/$WRAPPER_NAME"
            if [ -f "$LIB_BIN" ]; then
                echo "Remapping dynamic library paths for $LIB_BIN"
                install_name_tool -change "@rpath/liblagom-core.0.dylib" "@loader_path/Resources/Ladybird.app/Contents/lib/liblagom-core.0.dylib" "$LIB_BIN" || true
                install_name_tool -change "@rpath/liblagom-gfx.0.dylib" "@loader_path/Resources/Ladybird.app/Contents/lib/liblagom-gfx.0.dylib" "$LIB_BIN" || true
                install_name_tool -change "@rpath/liblagom-ipc.0.dylib" "@loader_path/Resources/Ladybird.app/Contents/lib/liblagom-ipc.0.dylib" "$LIB_BIN" || true
                install_name_tool -change "@rpath/liblagom-js.0.dylib" "@loader_path/Resources/Ladybird.app/Contents/lib/liblagom-js.0.dylib" "$LIB_BIN" || true
                install_name_tool -change "@rpath/liblagom-web.0.dylib" "@loader_path/Resources/Ladybird.app/Contents/lib/liblagom-web.0.dylib" "$LIB_BIN" || true
            fi
            
            echo "✅ SUCCESS: Ladybird artifacts bundled into framework."
        else
            echo "❌ ERROR: Framework directory not found at $FRAMEWORK_DIR"
            exit 1
        fi
        echo "--- LADYBIRD COCOAPODS BUILD END ---"
      '
    }
  ]
end