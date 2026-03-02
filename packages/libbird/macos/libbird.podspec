#
# libbird.podspec
#

plugin_root = File.expand_path('..', __dir__)
ladybird_build_dir = File.join(plugin_root, 'third_party', 'ladybird', 'Build')

puts "Preparing libbird resources and building C++ engine..."
system(<<-'CMD')
  cd "${PODS_TARGET_SRCROOT:-.}"
  
  rm -rf Classes/cpp_generated
  
  cd ../cpp
  mkdir -p build
  cd build
  cmake -DCMAKE_BUILD_TYPE=Release ..
  make -j$(sysctl -n hw.ncpu)
CMD

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

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++2b',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'OTHER_CPLUSPLUSFLAGS' => '-fobjc-arc -Wno-deprecated-anon-enum-enum-conversion',
    
    'VALID_ARCHS' => 'arm64',
    'EXCLUDED_ARCHS[sdk=macosx*]' => 'x86_64',

    'LIBRARY_SEARCH_PATHS' => [
      '$(inherited)',
      '"${PODS_TARGET_SRCROOT}/Bundled"'
    ].join(' '),
    
    'LD_RUNPATH_SEARCH_PATHS' => [
      '$(inherited)',
      '@executable_path/../Resources', 
      '@loader_path/../../Resources' 
    ].join(' '),
    
    'OTHER_LDFLAGS' => [
      '$(inherited)',
      '-framework Cocoa -framework Metal -framework QuartzCore -framework UniformTypeIdentifiers',
      '-Wl,-rpath,@loader_path/../Resources',
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
    {
      :name => 'Copy Ladybird Executables and Resources to MacOS Bundle',
      :execution_position => :after_compile,
      :script => <<-CMD
        APP_BUILD_DIR=$(dirname "${BUILT_PRODUCTS_DIR}")
        APP_NAME_FILE="${PODS_ROOT}/../Flutter/ephemeral/.app_filename"
        
        if [ ! -f "$APP_NAME_FILE" ]; then
          echo "Warning: Flutter ephemeral app_filename not found. Skipping executable copy."
          exit 0
        fi
        
        APP_NAME=$(cat "$APP_NAME_FILE")
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
end