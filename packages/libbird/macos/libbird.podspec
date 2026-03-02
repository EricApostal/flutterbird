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

  s.frameworks = 'AppKit', 'CoreAudio', 'Metal', 'QuartzCore', 'UniformTypeIdentifiers'

  s.vendored_frameworks = 'Frameworks/LadybirdEngine.xcframework'
  s.resources = ['Sources/libbird/LadybirdBundle/*']

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++2b',
    'CLANG_CXX_LIBRARY' => 'libc++',
    'OTHER_CPLUSPLUSFLAGS' => '-fobjc-arc -Wno-deprecated-anon-enum-enum-conversion',
    'OTHER_LDFLAGS' => '-w',
    
    'VALID_ARCHS' => 'arm64',
    'EXCLUDED_ARCHS[sdk=macosx*]' => 'x86_64',
    
    'LD_RUNPATH_SEARCH_PATHS' => [
      '$(inherited)',
      '@executable_path/../Frameworks',
      '@loader_path/Frameworks',
      '@executable_path/../Resources',
      '@loader_path/../Resources'
    ].join(' '),

    'HEADER_SEARCH_PATHS' => [
      '$(inherited)',
      '"${PODS_TARGET_SRCROOT}/../third_party/ladybird/UI/AppKit"',
      '"${PODS_TARGET_SRCROOT}/../third_party/ladybird"'
    ].join(' ')
  }
end