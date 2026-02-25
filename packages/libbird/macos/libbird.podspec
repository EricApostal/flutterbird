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
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++2b'
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

        # 2. Package Artifacts into the Host App Bundle
        # Because this script runs in the Pod context, we find the host .app dynamically
        APP_BUNDLE=$(find "$BUILT_PRODUCTS_DIR" -maxdepth 1 -name "*.app" -print -quit)

        if [ -z "$APP_BUNDLE" ]; then
            echo "❌ ERROR: Could not find host .app bundle in $BUILT_PRODUCTS_DIR"
            exit 1
        fi

        APP_CONTENTS="${LADYBIRD_SRC}/Build/release/bin/Ladybird.app/Contents"
        echo "Packaging artifacts into host app: $APP_BUNDLE"

        # A. Dynamic Libraries (GN expects them in Contents/lib)
        mkdir -p "$APP_BUNDLE/Contents/lib"
        cp -R "$APP_CONTENTS/lib/"* "$APP_BUNDLE/Contents/lib/"

        # B. Helpers (GN expects them in MacOS alongside the main executable)
        cp "$APP_CONTENTS/MacOS/WebContent" "$APP_BUNDLE/Contents/MacOS/"
        cp "$APP_CONTENTS/MacOS/RequestServer" "$APP_BUNDLE/Contents/MacOS/"
        cp "$APP_CONTENTS/MacOS/ImageDecoder" "$APP_BUNDLE/Contents/MacOS/"
        cp "$APP_CONTENTS/MacOS/WebWorker" "$APP_BUNDLE/Contents/MacOS/"

        # C. Resources (Fonts, Themes, Inspector CSS)
        mkdir -p "$APP_BUNDLE/Contents/Resources"
        cp -R "$APP_CONTENTS/Resources/"* "$APP_BUNDLE/Contents/Resources/"

        echo "✅ SUCCESS: Ladybird artifacts bundled."
        echo "--- LADYBIRD COCOAPODS BUILD END ---"
      '
    }
  ]
end