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

  s.platform = :osx, '11.0'
  s.swift_version = '5.0'

  s.vendored_libraries = '../third_party/ladybird/Build/release/lib/**/*.a'

  s.frameworks = 'Cocoa', 'Metal', 'QuartzCore', 'UniformTypeIdentifiers'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++2b',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'OTHER_CPLUSPLUSFLAGS' => '-fobjc-arc -Wno-deprecated-anon-enum-enum-conversion',
    'OTHER_LDFLAGS' => '-framework Cocoa -framework Metal -framework QuartzCore -framework UniformTypeIdentifiers',
    'HEADER_SEARCH_PATHS' => '$(inherited) "${PODS_TARGET_SRCROOT}/../third_party/ladybird" "${PODS_TARGET_SRCROOT}/../third_party/ladybird/Build/release" "${PODS_TARGET_SRCROOT}/../third_party/ladybird/Services"'
  }
end
