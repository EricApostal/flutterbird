import 'dart:io';

import 'package:hooks/hooks.dart';

Future<void> main(List<String> args) async {
  await build(args, (input, output) async {
    final packageRoot = Directory.fromUri(input.packageRoot);
    final bootstrapScript =
        File('${packageRoot.path}/tool/ensure_ladybird_source.sh');
    final versionFile = File('${packageRoot.path}/third_party/ladybird.version');

    output.dependencies.addAll([
      bootstrapScript.uri,
      versionFile.uri,
    ]);

    final result = await Process.run(
      'bash',
      [bootstrapScript.path],
      workingDirectory: packageRoot.path,
    );

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