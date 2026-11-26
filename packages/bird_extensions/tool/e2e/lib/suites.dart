import 'dart:convert';
import 'dart:io';

import 'engine.dart';
import 'server.dart';
import 'session.dart';

class Results {
  final List<(String, bool, String)> all = [];

  void add(String name, bool ok, [String detail = '']) =>
      all.add((name, ok, detail));

  int get failed => all.where((result) => !result.$2).length;

  void print_() {
    stdout.writeln();
    for (final (name, ok, detail) in all) {
      stdout.writeln(
        '${ok ? "pass" : "FAIL"}  $name${ok ? "" : "  — $detail"}',
      );
    }
    stdout.writeln('\n${all.length - failed} passed, $failed failed');
  }
}

const _contentChecks = [
  'start-root',
  'start-before-dom',
  'start-append',
  'start-observer',
  'start-domcontentloaded',
  'start-message',
  'start-storage',
  'start-import',
  'start-fetch-own-file',
  'idle-message-async-reply',
  'idle-port',
  'idle-tabs-send-message',
  'idle-tabs-execute-script',
  'idle-tabs-insert-css',
  'idle-wrapped-js-object',
  'idle-isolated',
  'idle-i18n',
  'inject-script-src',
  'inject-inner-html',
  'inject-shadow-iframe',
  'start-before-page-scripts',
  'start-css-applies',
  'content-script-css',
  'main-world-script',
  'isolated-from-page',
  'injected-script-ran-in-page',
  'page-receives-content-events',
  'frame-same-origin',
  'frame-cross-origin',
  'start-fetch-private-file',
  'idle-eval',
  'idle-reach-into-frame',
  'idle-who-am-i',
  'frame-about-blank',
  'page-cannot-read-private-files',
];

const _networkChecks = [
  'webrequest-blocks-parser-script',
  'webrequest-blocks-fetch',
  'webrequest-blocks-xhr',
  'webrequest-blocks-dynamic-script',
  'webrequest-blocks-image',
  'webrequest-redirects',
  'webrequest-adds-request-header',
  'inline-script-injection-runs',
];

Future<void> _expect(
  TestServer server,
  Results results,
  List<String> names, {
  Duration timeout = const Duration(seconds: 30),
}) async {
  await server.waitFor(names, timeout: timeout);
  for (final name in names) {
    final report = server.reports[name];
    results.add(name, report?.ok ?? false, report?.detail ?? 'never reported');
  }
}

Future<void> _copy(Directory from, Directory to) async {
  await to.create(recursive: true);
  await for (final entry in from.list()) {
    final name = entry.uri.pathSegments.lastWhere((s) => s.isNotEmpty);
    if (entry is Directory) {
      await _copy(entry, Directory('${to.path}/$name'));
    } else if (entry is File) {
      await entry.copy('${to.path}/$name');
    }
  }
}

/// A test extension that tries what real ones rely on.
Future<void> conformance(
  Stage stage,
  TestServer server,
  Directory work,
  Directory here,
  Results results,
) async {
  final source = Directory('${work.path}/conformance-source');
  await _copy(Directory('${here.path}/extensions/conformance'), source);
  await File(
    '${source.path}/config.json',
  ).writeAsString(jsonEncode({'server': server.origin}));

  var session = await Session.start(stage, work);

  // Installed while the browser runs, as a user installs one.
  final extension = await session.install(source);
  await _expect(server, results, ['background-loaded']);
  await _expect(server, results, ['idb-first-run-wrote']);

  Future<void> open(String url) async {
    await session.browser.createTab(url: url);
  }

  await open('${server.origin}/page/main');
  await _expect(server, results, [
    for (final check in [..._contentChecks, ..._networkChecks]) 'main:$check',
    'main:screen-size-reported',
  ]);
  for (final blocked in server.requests.where((p) => p.contains('blocked'))) {
    results.add('webrequest-never-sent $blocked', false, 'the server got it');
  }

  await open('${server.origin}/page/strict');
  await _expect(server, results, [
    for (final check in _contentChecks) 'strict:$check',
    'strict:page-eval-still-blocked',
    'strict:page-trusted-types-still-enforced',
  ]);

  await open('${server.origin}/page/response-headers');
  await _expect(server, results, ['headers:response-header-added']);

  await open('${extension.origin}/popup.html');
  await _expect(server, results, [
    'popup-message',
    'popup-port',
    'popup-replace-state',
    'popup-tabs-query',
    'popup-in-a-tab-has-sender-tab',
  ]);

  await _noteErrors(session, results);
  await session.close();

  // The browser is quit and started again on the same profile.
  server.reports.remove('background-loaded');
  session = await Session.start(stage, work);
  await _expect(server, results, ['background-loaded', 'idb-survived-restart']);
  await session.close();
}

/// An engine that crashed fails the run whatever the checks said.
Future<void> _noteErrors(Session session, Results results) async {
  if (session.engine.crashed.isCompleted) {
    results.add('engine-stayed-up', false, 'the engine exited');
  }
}
