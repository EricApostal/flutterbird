import 'dart:convert';
import 'dart:io';

import 'package:bird_extensions/bird_extensions.dart';

import 'engine.dart';
import 'server.dart';
import 'session.dart';
import 'suites.dart';

/// What an extension visibly does to the probe page, by its add-on ID.
const _effects = {
  'uBlock0@raymondhill.net': [
    'ad-script-by-path-blocked',
    'ad-server-blocked',
    'ad-slot-hidden',
  ],
  'addon@darkreader.org': ['page-darkened'],
};

/// Lines an extension context logs when something of its own went wrong.
final _failure = RegExp(
  r'context (\d+) (unhandled rejection|uncaught|error)[: ] ?(.*)',
);

/// Runs each unpacked extension in [directory] by itself, in a profile of its
/// own: it has to start its background page, open its popup, and visit a page
/// without any of its scripts throwing.
///
/// Only the extensions' code is read, never what they have stored.
Future<void> realExtensions(
  Stage stage,
  TestServer server,
  Directory work,
  Directory directory,
  Results results,
) async {
  final folders = [
    await for (final entry in directory.list())
      if (entry is Directory &&
          await File('${entry.path}/manifest.json').exists())
        entry,
  ]..sort((a, b) => a.path.compareTo(b.path));

  for (final (index, folder) in folders.indexed) {
    final own = await Directory('${work.path}/real-$index').create();
    final session = await Session.start(stage, own);
    server.reports.clear();
    server.requests.clear();
    var name = folder.path.split('/').last;
    try {
      final extension = await session.install(folder);
      name = extension.name;
      await _one(session, server, own, extension, results);
    } on Object catch (error) {
      results.add('$name: runs', false, '$error');
    }
    if (session.engine.crashed.isCompleted) {
      results.add('$name: engine-stayed-up', false, 'the engine exited');
    }
    await session.close();
  }
}

Future<void> _one(
  Session session,
  TestServer server,
  Directory work,
  InstalledExtension extension,
  Results results,
) async {
  final name = extension.name;
  final manifest = (await session.host.manifestOf(extension))!;

  Iterable<String> contextsOf(String path) => session.lines.where(
    (line) =>
        line.contains(' created (') &&
        line.contains('${extension.origin}$path'),
  );

  Future<bool> until(bool Function() done, Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (!done() && DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
    return done();
  }

  final background = ExtensionHost.backgroundPageUrl(extension, manifest);
  if (background != null) {
    final path = background.substring(extension.origin.length);
    final started = await until(
      () => contextsOf(path).isNotEmpty,
      const Duration(seconds: 30),
    );
    results.add('$name: background starts', started, 'no context appeared');
  }
  // Time to read what it ships with: filter lists and the like.
  await Future<void>.delayed(const Duration(seconds: 20));

  await session.browser.createTab(url: '${server.origin}/page/probe');
  final effects = _effects[extension.id] ?? const <String>[];
  if (effects.isNotEmpty) {
    await server.waitFor([for (final e in effects) 'probe:$e']);
    for (final effect in effects) {
      final report = server.reports['probe:$effect'];
      results.add(
        '$name: $effect',
        report?.ok ?? false,
        report?.detail ?? 'never reported',
      );
    }
    if (effects.contains('ad-script-by-path-blocked') &&
        server.requests.any((path) => path.contains('adsbygoogle'))) {
      results.add('$name: ad request never sent', false, 'the server got it');
    }
  }
  await Future<void>.delayed(const Duration(seconds: 6));

  final popup = manifest.action?.defaultPopup;
  if (popup != null) {
    final url = popup.startsWith('/') ? popup : '/$popup';
    await session.browser.createTab(url: '${extension.origin}$url');
    final opened = await until(
      () => contextsOf(url.split('?').first).isNotEmpty,
      const Duration(seconds: 15),
    );
    results.add('$name: popup opens', opened, 'no context appeared');
    await Future<void>.delayed(const Duration(seconds: 8));
  }

  // What went wrong inside any of its contexts, and scripts of it that threw
  // as the engine ran them.
  final errors = <String>{
    for (final line in session.lines)
      if (_failure.firstMatch(line) case final match?)
        '${match[2]}: ${match[3]}',
  };
  final log = const LineSplitter().convert(
    utf8.decode(
      await File('${work.path}/engine.log').readAsBytes(),
      allowMalformed: true,
    ),
  );
  for (final line in log) {
    final at = line.indexOf('ExtensionRuntime: ');
    if (at >= 0 && line.contains(' threw: ')) errors.add(line.substring(at));
    final unhandled = line.indexOf('Unhandled JavaScript exception');
    if (unhandled >= 0) errors.add(line.substring(unhandled));
  }
  results.add(
    '$name: no script errors',
    errors.isEmpty,
    '${errors.length}: ${errors.take(6).join(" | ")}',
  );
}
