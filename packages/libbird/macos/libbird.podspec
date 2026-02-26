#
# libbird.podspec
#

plugin_root = File.expand_path('..', __dir__)
ladybird_build_dir = File.join(plugin_root, 'third_party', 'ladybird', 'Build')

found_library_paths = ['$(inherited)']
if Dir.exist?(ladybird_build_dir)
  Dir.glob("#{ladybird_build_dir}/**/*.{a,dylib}").each do |file|
    dir_path = File.dirname(file)
    rel_dir = dir_path.sub(plugin_root, '${PODS_TARGET_SRCROOT}/..')
    found_library_paths << "\"#{rel_dir}\""
  end
end
found_library_paths.uniq!

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

  # 1. Package the Dylibs to be automatically copied to Contents/Resources
  s.prepare_command = <<-CMD
    mkdir -p Bundled
    
    # Copy all Dylibs (including vcpkg ones) from the build directory
    find ../third_party/ladybird/Build -name "*.dylib" -exec cp {} Bundled/ \\;
    
    # Make dylibs relocatable by updating their internal IDs
    for f in Bundled/*.dylib; do
      bn=$(basename "$f")
      chmod +w "$f"
      install_name_tool -id "@rpath/$bn" "$f" || true
    done
  CMD

  # This tells CocoaPods to put the contents of Bundled/ into the app's Resources folder
  s.resources = ['Bundled/*']

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++2b',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'OTHER_CPLUSPLUSFLAGS' => '-fobjc-arc -Wno-deprecated-anon-enum-enum-conversion',
    
    'VALID_ARCHS' => 'arm64',
    'EXCLUDED_ARCHS[sdk=macosx*]' => 'x86_64',

    'LIBRARY_SEARCH_PATHS' => found_library_paths.join(' '),
    
    'LD_RUNPATH_SEARCH_PATHS' => [
      '$(inherited)',
      '@executable_path/../Resources', 
      '@loader_path/../../Resources' 
    ].join(' '),
    
    'OTHER_LDFLAGS' => [
      '$(inherited)',
      '-framework Cocoa -framework Metal -framework QuartzCore -framework UniformTypeIdentifiers',
      
      '-Wl,-force_load,"${PODS_TARGET_SRCROOT}/../third_party/ladybird/Build/release/lib/libladybird_impl.a"',
      
      '-Wl,-rpath,@loader_path/../Resources',
      
      '-llagom-webview', '-llagom-web', '-llagom-requests', 
      '-llagom-js', '-llagom-gfx', '-llagom-ipc', '-llagom-url', 
      '-llagom-filesystem', '-llagom-crypto', '-llagom-database',
      '-llagom-core', '-llagom-coreminimal', '-llagom-ak', 
      '-llagom-unicode', '-llagom-main',
      '-lskia', '-lsqlite3', '-lssl', '-lcrypto', '-lz'
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

  # 2. Force the Executables into Contents/MacOS post-compile
  s.script_phases = [
    {
      :name => 'Copy Ladybird Executables to MacOS Bundle',
      :execution_position => :after_compile,
      :script => <<-CMD
        echo "Copying Ladybird executables to host app MacOS directory..."
        
        # Dynamically find the .app bundle, avoiding hardcoded names
        APP_PATH=$(find "${BUILT_PRODUCTS_DIR}" -maxdepth 1 -name "*.app" | head -n 1)
        
        if [ -z "$APP_PATH" ]; then
           echo "Warning: No .app bundle found in ${BUILT_PRODUCTS_DIR}. Executables not copied."
           exit 0
        fi
        
        DEST_DIR="${APP_PATH}/Contents/MacOS"
        mkdir -p "${DEST_DIR}"
        
        LADYBIRD_BIN_DIR="${PODS_TARGET_SRCROOT}/../third_party/ladybird/Build/release/bin/Ladybird.app/Contents/MacOS"
        
        # Copy the helpers into the app's MacOS directory
        cp -af "${LADYBIRD_BIN_DIR}/RequestServer" "${DEST_DIR}/" || true
        cp -af "${LADYBIRD_BIN_DIR}/ImageDecoder" "${DEST_DIR}/" || true
        cp -af "${LADYBIRD_BIN_DIR}/WebContent" "${DEST_DIR}/" || true
        cp -af "${LADYBIRD_BIN_DIR}/WebWorker" "${DEST_DIR}/" || true

        # Point helpers to the dylibs in Contents/Resources
        for helper in RequestServer ImageDecoder WebContent WebWorker; do
          if [ -f "${DEST_DIR}/$helper" ]; then
            chmod +w "${DEST_DIR}/$helper"
            install_name_tool -add_rpath "@executable_path/../Resources" "${DEST_DIR}/$helper" 2>/dev/null || true
          fi
        done
      CMD
    }
  ]
end