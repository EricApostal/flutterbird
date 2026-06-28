require 'xcodeproj'

project = Xcodeproj::Project.open('Runner.xcodeproj')
app_target = project.targets.find { |t| t.name == 'Runner' }

extensions = {
  'WebContent' => 'com.apple.browserengine.webcontent',
  'RequestServer' => 'com.apple.browserengine.networking',
  'Compositor' => 'com.apple.browserengine.rendering',
  'ImageDecoder' => 'com.apple.browserengine.webcontent',
  'WebWorker' => 'com.apple.browserengine.webcontent'
}

ext_group = project.main_group.find_subpath('LadybirdExtensions', true)

# Remove the old 'Embed Ladybird Extensions' phase if it exists
old_phase = app_target.copy_files_build_phases.find { |p| p.name == 'Embed Ladybird Extensions' }
if old_phase
  app_target.build_phases.delete(old_phase)
end

extensions.each do |name, point_id|
  target = project.targets.find { |t| t.name == name }
  
  unless target
    target = project.new_target(:app_extension, name, :ios, '15.0')
  end
  
  # Generate a proper Info.plist with the NSExtension dictionary
  plist_path = "Runner/#{name}-Info.plist"
  plist_content = <<~PLIST
  <?xml version="1.0" encoding="UTF-8"?>
  <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
  <plist version="1.0">
  <dict>
      <key>CFBundleIdentifier</key>
      <string>$(PRODUCT_BUNDLE_IDENTIFIER)</string>
      <key>CFBundleName</key>
      <string>$(PRODUCT_NAME)</string>
      <key>CFBundleExecutable</key>
      <string>$(EXECUTABLE_NAME)</string>
      <key>CFBundlePackageType</key>
      <string>XPC!</string>
      <key>CFBundleShortVersionString</key>
      <string>1.0</string>
      <key>CFBundleVersion</key>
      <string>1</string>
      <key>NSExtension</key>
      <dict>
          <key>NSExtensionPointIdentifier</key>
          <string>#{point_id}</string>
          <key>NSExtensionPrincipalClass</key>
          <string>LadybirdXPCListenerDelegate</string>
      </dict>
  </dict>
  </plist>
  PLIST
  File.write("Runner/#{name}-Info.plist", plist_content)

  # Configure build settings
  target.build_configurations.each do |config|
    config.build_settings['PRODUCT_NAME'] = name
    config.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = "app.rubisco.flutterbird.#{name}"
    config.build_settings['INFOPLIST_FILE'] = plist_path
    config.build_settings['GENERATE_INFOPLIST_FILE'] = 'NO'
    config.build_settings['CODE_SIGN_STYLE'] = 'Automatic'
    config.build_settings['SWIFT_VERSION'] = '5.0'
    config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '15.0'
    
    runner_config = app_target.build_configurations.find { |c| c.name == config.name }
    config.build_settings['DEVELOPMENT_TEAM'] = runner_config.build_settings['DEVELOPMENT_TEAM'] if runner_config
  end
  
  # Add a dummy swift file so it compiles
  File.write("Runner/#{name}Dummy.swift", "import Foundation\n@objc(LadybirdXPCListenerDelegate) class LadybirdXPCListenerDelegate: NSObject {}\n")
  file = ext_group.find_file_by_path("Runner/#{name}Dummy.swift") || ext_group.new_file("Runner/#{name}Dummy.swift")
  target.add_file_references([file])
  
  # Remove the old script phase from the extension targets if it exists
  script_phase = target.build_phases.find { |p| p.respond_to?(:name) && p.name == "Inject CMake Binary" }
  target.build_phases.delete(script_phase) if script_phase
  
  app_target.add_dependency(target) unless app_target.dependencies.any? { |d| d.target == target }
end

# Ensure Runner embeds the extensions via its 'Embed App Extensions' phase
embed_phase = app_target.copy_files_build_phases.find { |p| p.name == 'Embed App Extensions' }
unless embed_phase
  embed_phase = project.new(Xcodeproj::Project::Object::PBXCopyFilesBuildPhase)
  embed_phase.name = 'Embed App Extensions'
  embed_phase.dst_subfolder_spec = "13" # PlugIns
  app_target.build_phases << embed_phase
end

extensions.keys.each do |name|
  target = project.targets.find { |t| t.name == name }
  file_ref = target.product_reference
  unless embed_phase.files_references.include?(file_ref)
    build_file = embed_phase.add_file_reference(file_ref)
    build_file.settings = { "ATTRIBUTES" => ["CodeSignOnCopy", "RemoveHeadersOnCopy"] }
  end
end

# Add a script phase to the Runner target to inject the CMake binaries and re-sign
resign_phase = app_target.build_phases.find { |p| p.respond_to?(:name) && p.name == "Inject and Resign Ladybird Extensions" }
unless resign_phase
  resign_phase = project.new(Xcodeproj::Project::Object::PBXShellScriptBuildPhase)
  resign_phase.name = "Inject and Resign Ladybird Extensions"
  app_target.build_phases << resign_phase
end

# This script runs on the Runner app, replacing the dummy binaries with the real ones and re-signing them.
# It uses $EXPANDED_CODE_SIGN_IDENTITY provided by Xcode.
script = <<~SCRIPT
set -e
# Copy the compiled CMake binaries into the embedded .appex bundles
cp "${PROJECT_DIR}/../packages/libbird/cpp/build_ios/ladybird_build/bin/WebContent" "${BUILT_PRODUCTS_DIR}/${PLUGINS_FOLDER_PATH}/WebContent.appex/WebContent" || true
cp "${PROJECT_DIR}/../packages/libbird/cpp/build_ios/ladybird_build/bin/RequestServer" "${BUILT_PRODUCTS_DIR}/${PLUGINS_FOLDER_PATH}/RequestServer.appex/RequestServer" || true
cp "${PROJECT_DIR}/../packages/libbird/cpp/build_ios/ladybird_build/bin/Compositor" "${BUILT_PRODUCTS_DIR}/${PLUGINS_FOLDER_PATH}/Compositor.appex/Compositor" || true
cp "${PROJECT_DIR}/../packages/libbird/cpp/build_ios/ladybird_build/bin/ImageDecoder" "${BUILT_PRODUCTS_DIR}/${PLUGINS_FOLDER_PATH}/ImageDecoder.appex/ImageDecoder" || true
cp "${PROJECT_DIR}/../packages/libbird/cpp/build_ios/ladybird_build/bin/WebWorker" "${BUILT_PRODUCTS_DIR}/${PLUGINS_FOLDER_PATH}/WebWorker.appex/WebWorker" || true

# Re-sign the .appex bundles so iOS accepts them after binary replacement
if [ -n "${EXPANDED_CODE_SIGN_IDENTITY}" ]; then
  codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY}" --timestamp=none "${BUILT_PRODUCTS_DIR}/${PLUGINS_FOLDER_PATH}/WebContent.appex" || true
  codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY}" --timestamp=none "${BUILT_PRODUCTS_DIR}/${PLUGINS_FOLDER_PATH}/RequestServer.appex" || true
  codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY}" --timestamp=none "${BUILT_PRODUCTS_DIR}/${PLUGINS_FOLDER_PATH}/Compositor.appex" || true
  codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY}" --timestamp=none "${BUILT_PRODUCTS_DIR}/${PLUGINS_FOLDER_PATH}/ImageDecoder.appex" || true
  codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY}" --timestamp=none "${BUILT_PRODUCTS_DIR}/${PLUGINS_FOLDER_PATH}/WebWorker.appex" || true
  
  # Find and sign ALL .dylib files injected by Ladybird (like libengine.dylib, liblagom-webview.0.dylib, etc.)
  find "${BUILT_PRODUCTS_DIR}/${FRAMEWORKS_FOLDER_PATH}" -name "*.dylib" -exec codesign --force --sign "${EXPANDED_CODE_SIGN_IDENTITY}" --timestamp=none {} \\; || true
fi
SCRIPT

resign_phase.shell_script = script

# Ensure these phases run BEFORE 'Thin Binary' and '[CP] Embed Pods Frameworks' to avoid dependency cycles.
app_target.build_phases.delete(embed_phase)
app_target.build_phases.delete(resign_phase)

thin_binary_index = app_target.build_phases.index { |p| p.respond_to?(:name) && p.name == 'Thin Binary' }
if thin_binary_index
  app_target.build_phases.insert(thin_binary_index, embed_phase)
  app_target.build_phases.insert(thin_binary_index + 1, resign_phase)
else
  app_target.build_phases << embed_phase
  app_target.build_phases << resign_phase
end

project.save
puts "Successfully generated Xcode targets for all 5 BrowserEngineKit extensions and configured resigning!"
