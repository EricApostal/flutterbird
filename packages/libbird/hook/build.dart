import 'dart:io';

import 'package:code_assets/code_assets.dart';
import 'package:hooks/hooks.dart';

void _checkShellResponse(ProcessResult result) {
  if (result.exitCode != 0) {
    throw Exception(
      'Process failed with exit code ${result.exitCode}\nSTDOUT: ${result.stdout}\nSTDERR: ${result.stderr}',
    );
  }
}

void main(List<String> args) async {
  await build(args, (input, output) async {
    final packageRoot = input.packageRoot.toFilePath();
    final ladybirdRoot = "${packageRoot}third_party/ladybird";
    final cppRoot = "${packageRoot}cpp";
    final cppBuildRoot = "$cppRoot/build";
    final binariesRoot = "$cppBuildRoot/LadybirdBundle/binaries";
    final macosResourcesRoot = "${packageRoot}macos/LadybirdResources";

    _checkShellResponse(
      await Process.run(
        'python3',
        ['Meta/ladybird.py', 'build'],
        workingDirectory: ladybirdRoot,
        runInShell: true,
      ),
    );

    await Directory(cppBuildRoot).create();

    _checkShellResponse(
      await Process.run(
        'cmake',
        ['..'],
        workingDirectory: cppBuildRoot,
        runInShell: true,
      ),
    );

    _checkShellResponse(
      await Process.run(
        'cmake',
        ['--build', '.'],
        workingDirectory: cppBuildRoot,
        runInShell: true,
      ),
    );

    final binaries = Directory(binariesRoot);
    await Directory(macosResourcesRoot).create();
    final binariesList = binaries.listSync();
    for (FileSystemEntity binary in binariesList) {
      await File(
        binary.path,
      ).copy("$macosResourcesRoot/${binary.path.split("/").last}");
    }
  });
}
