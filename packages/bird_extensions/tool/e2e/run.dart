/// End-to-end tests of extension support, in the real engine.
///
/// The unit tests stand a fake in for the engine, so they pass however the
/// engine behaves. These run the engine of an app that has already been built,
/// headlessly and in a throwaway profile, with the same extension host the app
/// assembles, and check what actually happens in pages.
///
///     dart run tool/e2e/run.dart [options]
///
///     --app <built .app>       the app whose engine is tested
///     --engine-build <dir>     take the engine's libraries and helpers from a
///                              Ladybird build, such as one just made with ninja
///     --extensions <dir>       also run each unpacked extension in <dir>
///     --only-extensions        skip the conformance extension
///     --keep                   keep the logs of a run that passed
///
/// Nothing is built but the small program that hosts the engine. Run it after
/// building the app, from packages/bird_extensions.
library;

import 'dart:io';

import 'lib/engine.dart';
import 'lib/real_extensions.dart';
import 'lib/server.dart';
import 'lib/suites.dart';

Future<void> main(List<String> arguments) async {
  String? option(String name) {
    final at = arguments.indexOf(name);
    return at >= 0 && at + 1 < arguments.length ? arguments[at + 1] : null;
  }

  final here = File.fromUri(Platform.script).parent;
  final repository = here.parent.parent.parent.parent;
  final app = Directory(
    option('--app') ??
        '${repository.path}/build/macos/Build/Products/Release/Rubisco Browser.app',
  );
  final work = await Directory.systemTemp.createTemp('bird-e2e-');
  stdout.writeln('app:  ${app.path}\nwork: ${work.path}');

  final server = await TestServer.start(Directory('${here.path}/pages'));
  final results = Results();
  try {
    final stage = await Stage.prepare(
      app,
      work,
      engineBuild: switch (option('--engine-build')) {
        final path? => Directory(path),
        null => null,
      },
    );
    if (!arguments.contains('--only-extensions')) {
      await conformance(stage, server, work, here, results);
    }
    if (option('--extensions') case final path?) {
      await realExtensions(stage, server, work, Directory(path), results);
    }
  } finally {
    await server.close();
  }

  results.print_();
  if (arguments.contains('--keep') || results.failed > 0) {
    stdout.writeln('\nLogs are in ${work.path}');
    await Directory('${work.path}/Stage.app').delete(recursive: true);
  } else {
    await work.delete(recursive: true);
  }
  exit(results.failed == 0 ? 0 : 1);
}
