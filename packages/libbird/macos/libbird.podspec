#
# libbird.podspec
#

plugin_root = File.expand_path('..', __dir__)
ladybird_build_dir = File.join(plugin_root, 'third_party', 'ladybird', 'Build')

# puts "Preparing libbird resources and building C++ engine..."
# system(<<-'CMD')
#   cd "${PODS_TARGET_SRCROOT:-.}"
  
#   rm -rf Classes/cpp_generated
  
#   cd ../cpp
#   mkdir -p build
#   cd build
#   cmake -DCMAKE_BUILD_TYPE=Release ..
#   make -j$(sysctl -n hw.ncpu)
# CMD

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
    ].join(' '),
  }
end