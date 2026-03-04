#
# libbird.podspec
#

Pod::Spec.new do |s|
  s.name             = 'libbird'
  s.version          = '0.0.1'
  s.summary          = 'Ladybird interface for Flutter.'
  s.homepage         = 'https://ladybird.org'
  s.license          = { :type => 'BSD', :file => '../LICENSE' }
  s.author           = { 'Ladybird Team' => 'contact@ladybird.org' }
  s.source           = { :git => 'https://github.com/LadybirdBrowser/ladybird.git', :tag => s.version.to_s }

  s.source_files     = 'Classes/**/*'
  s.public_header_files = 'Classes/**/*.h'
  
  s.platform = :osx, '11.0'
  s.swift_version = '5.0'
  s.dependency 'FlutterMacOS'

  s.frameworks = 'Cocoa', 'Metal', 'QuartzCore', 'UniformTypeIdentifiers'

  s.resources = ['Bundled/*']
  
  s.preserve_paths = 'LadybirdResources/*'

  s.script_phases = [
    {
      :name => 'Copy Ladybird Executables and Resources to MacOS Bundle',
      :execution_position => :after_compile,
      :script => <<-CMD
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
        mkdir -p "${DEST_RES_DIR}"
        
        LADYBIRD_APP_DIR="${PODS_TARGET_SRCROOT}/../third_party/ladybird/Build/release/bin/Ladybird.app"
        
        cp -af "${LADYBIRD_APP_DIR}/Contents/MacOS/"* "${DEST_BIN_DIR}/" || true
        cp -af "${LADYBIRD_APP_DIR}/Contents/Resources/"* "${DEST_RES_DIR}/" || true

        for helper in "${DEST_BIN_DIR}"/*; do
          if [ -f "$helper" ] && [ ! -L "$helper" ]; then
            chmod +w "$helper"
            install_name_tool -add_rpath "@executable_path/../Resources" "$helper" 2>/dev/null || true
          fi
        done
      CMD
    }
  ]

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++2b',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'OTHER_CPLUSPLUSFLAGS' => '-fobjc-arc -Wno-deprecated-anon-enum-enum-conversion',
    
    'VALID_ARCHS' => 'arm64',
    'EXCLUDED_ARCHS[sdk=macosx*]' => 'x86_64',

    'LIBRARY_SEARCH_PATHS' => [
      '$(inherited)',
    ].join(' '),
  }
end