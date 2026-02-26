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
  s.description      = 'A Flutter plugin to provide a portable Ladybird browser interface.'
  s.homepage         = 'https://ladybird.org'
  s.license          = { :type => 'BSD', :file => '../LICENSE' }
  s.author           = { 'Ladybird Team' => 'contact@ladybird.org' }
  s.source           = { :git => 'https://github.com/LadybirdBrowser/ladybird.git', :tag => s.version.to_s }

  s.source_files     = 'Classes/**/*'
  s.public_header_files = 'Classes/**/*.h'
  
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '11.0'
  s.swift_version = '5.0'

  s.frameworks = 'Cocoa', 'Metal', 'QuartzCore', 'UniformTypeIdentifiers'

s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++2b',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'OTHER_CPLUSPLUSFLAGS' => '-fobjc-arc -Wno-deprecated-anon-enum-enum-conversion',
    
    'LIBRARY_SEARCH_PATHS' => found_library_paths.join(' '),
    
    'OTHER_LDFLAGS' => [
      '$(inherited)',
      '-framework Cocoa -framework Metal -framework QuartzCore -framework UniformTypeIdentifiers',
      
        # hmmm
      '-Wl,-force_load,"${PODS_TARGET_SRCROOT}/../third_party/ladybird/Build/release/lib/libladybird_impl.a"',
      
      '-llagom-webview',
      '-llagom-web',
      '-llagom-requests',
      '-llagom-js',
      '-llagom-gfx',
      '-llagom-ipc',
      
      '-llagom-core',
      '-llagom-coreminimal',
      '-llagom-ak',
      '-llagom-unicode',
      '-llagom-url',
      '-llagom-filesystem',
      '-llagom-crypto',
      '-llagom-database',
      '-llagom-main',
      
      '-llagom-core',
      '-llagom-ak',
      
      '-lskia',
      '-lsqlite3',
      '-lssl',
      '-lcrypto',
      '-lz'
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
end