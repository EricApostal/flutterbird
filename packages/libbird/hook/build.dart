import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

// The platform name tool/libbird_native.sh knows a build by, or null for one it
// has no prebuilt copy for.
String? _nativePlatform(BuildInput input) {
  try {
    if (!input.config.buildCodeAssets) return null;
    final code = input.config.code;
    final os = code.targetOS.name;
    final architecture = code.targetArchitecture.name;
    if (os == 'macos' && architecture == 'arm64') return 'macos-arm64';
    if (os == 'android' && architecture == 'arm64') return 'android-arm64-v8a';
  } catch (_) {
    // The build does not say what it is for; compiling is the safe reading.
  }
  return null;
}

Future<void> main(List<String> args) async {
  await build(args, (input, output) async {
    final packageRoot = Directory.fromUri(input.packageRoot);
    final bootstrapScript = File(
      '${packageRoot.path}/tool/ensure_ladybird_source.sh',
    );
    final nativeScript = File('${packageRoot.path}/tool/libbird_native.sh');
    final versionFile = File(
      '${packageRoot.path}/third_party/ladybird.version',
    );

    output.dependencies.addAll([
      bootstrapScript.uri,
      nativeScript.uri,
      versionFile.uri,
    ]);

    // With a prebuilt copy there is nothing to compile, so there is no need for
    // the Ladybird checkout either: skip cloning it. The platform builds fetch
    // the copy themselves (see tool/libbird_native.sh).
    final platform = _nativePlatform(input);
    final modeResult = await Process.run('bash', [
      nativeScript.path,
      'mode',
      ?platform,
    ], workingDirectory: packageRoot.path);
    stderr.write(modeResult.stderr);
    if (modeResult.exitCode != 0) {
      throw ProcessException(
        'bash',
        [nativeScript.path, 'mode'],
        'Could not decide between a prebuilt and a local native build.',
        modeResult.exitCode,
      );
    }
    if (modeResult.stdout.toString().trim() == 'prebuilt') {
      stdout.writeln(
        'libbird: using the prebuilt native copy; not preparing the Ladybird '
        'checkout.',
      );
      return;
    }

    final result = await Process.run('bash', [
      bootstrapScript.path,
    ], workingDirectory: packageRoot.path);

    stdout.write(result.stdout);
    stderr.write(result.stderr);

    if (result.exitCode != 0) {
      throw ProcessException(
        'bash',
        [bootstrapScript.path],
        'Failed to prepare the Ladybird checkout.',
        result.exitCode,
      );
    }
  });
}
