#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint libbird.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'libbird'
  s.version          = '0.0.1'
  s.summary          = 'Flutter plugin to provide a portable Ladybird interface.'
  s.description      = <<-DESC
Flutter plugin to provide a portable Ladybird interface.
                       DESC
  s.homepage         = 'http://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Your Company' => 'email@example.com' }

  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  
  s.dependency 'FlutterMacOS'

  # Bumped to 11.0 as UniformTypeIdentifiers framework requires macOS 11+
  s.platform = :osx, '11.0'
  s.swift_version = '5.0'

  # 1. Copy the libraries from third_party into a local directory inside macos/
  s.prepare_command = <<-CMD
    mkdir -p .ladybird_build_libs
    cp -R ../third_party/ladybird/Build/release/lib/*.a .ladybird_build_libs/ 2>/dev/null || true
  CMD

  # 2. Glob the locally copied files
  s.vendored_libraries = '.ladybird_build_libs/**/*.a'

  s.frameworks = 'Cocoa', 'Metal', 'QuartzCore', 'UniformTypeIdentifiers'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++2b',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'OTHER_CPLUSPLUSFLAGS' => '-fobjc-arc -Wno-deprecated-anon-enum-enum-conversion',
    'OTHER_LDFLAGS' => '-framework Cocoa -framework Metal -framework QuartzCore -framework UniformTypeIdentifiers',
    
    # Ensure headers can be found when you write your C++ bridge
    'HEADER_SEARCH_PATHS' => '"${PODS_TARGET_SRCROOT}/../third_party/ladybird" "${PODS_TARGET_SRCROOT}/../third_party/ladybird/Build/release"'
  }
end