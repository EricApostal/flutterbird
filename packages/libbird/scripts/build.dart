// scripts/build.dart
import 'dart:io';
import 'package:path/path.dart' as path;

void main(List<String> args) async {
  final pluginRoot = Directory.current.path;
  final cppDir = path.join(pluginRoot, 'cpp');
  final buildDir = path.join(cppDir, 'build');
  final ladybirdDir = path.join(pluginRoot, 'third_party', 'ladybird');
  final releaseDir = path.join(ladybirdDir, 'Build', 'release');

  final macosStagingDir = path.join(
    pluginRoot,
    'macos',
    'Sources',
    'libbird',
    'LadybirdBundle',
  );
  final frameworksDir = path.join(pluginRoot, 'macos', 'Frameworks');
  final stagingDylibDir = path.join(frameworksDir, 'Staging');

  // Clean old artifacts to prevent conflicts
  if (await Directory(stagingDylibDir).exists()) {
    await Directory(stagingDylibDir).delete(recursive: true);
  }
  if (await Directory(macosStagingDir).exists()) {
    await Directory(macosStagingDir).delete(recursive: true);
  }

  await Directory(buildDir).create(recursive: true);
  await Directory(macosStagingDir).create(recursive: true);
  await Directory(stagingDylibDir).create(recursive: true);

  print('Building Ladybird Engine C++ Wrapper...');
  final cmakeRes = await Process.run('cmake', [
    '-DCMAKE_BUILD_TYPE=Release',
    '..',
  ], workingDirectory: buildDir);
  if (cmakeRes.exitCode != 0)
    throw Exception('CMake failed: ${cmakeRes.stderr}');

  final cpuCount = Platform.numberOfProcessors.toString();
  final makeRes = await Process.run('make', [
    '-j',
    cpuCount,
  ], workingDirectory: buildDir);
  if (makeRes.exitCode != 0) throw Exception('Make failed: ${makeRes.stderr}');

  print('Staging LadybirdEngine framework...');
  final engineFrameworkSource = Directory(
    path.join(buildDir, 'LadybirdEngine.framework'),
  );
  final engineFrameworkStaged = Directory(
    path.join(stagingDylibDir, 'LadybirdEngine.framework'),
  );

  if (!await engineFrameworkSource.exists()) {
    throw Exception('LadybirdEngine.framework not found! Did CMake build it?');
  }
  await Process.run('cp', [
    '-a',
    engineFrameworkSource.path,
    engineFrameworkStaged.path,
  ]);

  print('Generating LadybirdEngine.xcframework...');
  // The actual binary lives inside Versions/Current/ inside the framework
  final engineBinaryPath = path.join(
    engineFrameworkStaged.path,
    'Versions',
    'Current',
    'LadybirdEngine',
  );
  await Process.run('install_name_tool', [
    '-add_rpath',
    '@executable_path/../Resources/LadybirdBundle',
    engineBinaryPath,
  ]);
  await Process.run('install_name_tool', [
    '-add_rpath',
    '@loader_path/../Resources/LadybirdBundle',
    engineBinaryPath,
  ]);

  final xcframeworkPath = path.join(
    frameworksDir,
    'LadybirdEngine.xcframework',
  );
  if (await Directory(xcframeworkPath).exists()) {
    await Directory(xcframeworkPath).delete(recursive: true);
  }

  final xcbuildRes = await Process.run('xcodebuild', [
    '-create-xcframework',
    '-framework',
    engineFrameworkStaged.path,
    '-output',
    xcframeworkPath,
  ]);
  if (xcbuildRes.exitCode != 0)
    throw Exception(
      'XCFramework creation failed: ${xcbuildRes.stderr}\n${xcbuildRes.stdout}',
    );

  print('Injecting Headers and Modules into LadybirdEngine.framework...');
  // Without Headers/ and Modules/ CocoaPods cannot generate a module map.
  final xcFwVersionsPath = path.join(
    xcframeworkPath,
    'macos-arm64',
    'LadybirdEngine.framework',
    'Versions',
    'A',
  );
  final engineHeaderSrc = path.join(pluginRoot, 'macos', 'Classes', 'engine.h');
  final headersDir = Directory(path.join(xcFwVersionsPath, 'Headers'));
  final modulesDir = Directory(path.join(xcFwVersionsPath, 'Modules'));
  await headersDir.create(recursive: true);
  await modulesDir.create(recursive: true);
  await File(engineHeaderSrc).copy(path.join(headersDir.path, 'engine.h'));
  await File(path.join(modulesDir.path, 'module.modulemap')).writeAsString(
    'framework module LadybirdEngine {\n'
    '  umbrella header "engine.h"\n'
    '  export *\n'
    '  module * { export * }\n'
    '}\n',
  );
  // Top-level symlinks so Xcode / CocoaPods can find the dirs directly
  final fwTopLevel = path.join(
    xcframeworkPath,
    'macos-arm64',
    'LadybirdEngine.framework',
  );
  await Process.run('ln', [
    '-sfn',
    'Versions/A/Headers',
    path.join(fwTopLevel, 'Headers'),
  ]);
  await Process.run('ln', [
    '-sfn',
    'Versions/A/Modules',
    path.join(fwTopLevel, 'Modules'),
  ]);

  print('Bundling Ladybird resources and dependencies...');
  final releaseDirObj = Directory(releaseDir);
  if (await releaseDirObj.exists()) {
    await for (final entity in releaseDirObj.list(recursive: true)) {
      if (entity is File && entity.path.endsWith('.dylib')) {
        final dest = path.join(macosStagingDir, path.basename(entity.path));
        await entity.copy(dest);
        await Process.run('chmod', ['+w', dest]);
        await Process.run('install_name_tool', [
          '-id',
          '@rpath/${path.basename(entity.path)}',
          dest,
        ]);
      }
    }
  }

  // Copy Ladybird executables and resources to the bundle
  final appDir = Directory(path.join(releaseDir, 'bin', 'Ladybird.app'));
  if (await appDir.exists()) {
    final macosContents = Directory(
      path.join(appDir.path, 'Contents', 'MacOS'),
    );
    final resContents = Directory(
      path.join(appDir.path, 'Contents', 'Resources'),
    );

    if (await macosContents.exists()) {
      await Process.run('cp', [
        '-a',
        '${macosContents.path}/.',
        macosStagingDir,
      ]);
    }
    if (await resContents.exists()) {
      await Process.run('cp', ['-a', '${resContents.path}/.', macosStagingDir]);
    }

    final stagedEntities = await Directory(macosStagingDir).list().toList();
    for (final entity in stagedEntities) {
      if (entity is File &&
          !entity.path.endsWith('.dylib') &&
          !entity.path.contains('.')) {
        await Process.run('chmod', ['+w', entity.path]);
        await Process.run('install_name_tool', [
          '-add_rpath',
          '@executable_path',
          entity.path,
        ]);
        await Process.run('install_name_tool', [
          '-add_rpath',
          '@executable_path/../Resources',
          entity.path,
        ]);
      }
    }
  }

  print('Build hooks completed successfully!');
}
