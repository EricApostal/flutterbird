import 'dart:async';
import 'dart:io';

import 'package:bird_extensions/bird_extensions.dart';

import 'browser.dart';
import 'engine.dart';

/// One run of the disposable browser: the engine, the extension host as the app
/// assembles it, and tabs. Closing and starting another with the same home is
/// restarting the browser.
class Session {
  Session._(this.engine, this.browser, this.host, this.installer, this.parts);

  final Engine engine;
  final HeadlessBrowser browser;
  final ExtensionHost host;
  final ExtensionInstaller installer;
  final ExtensionRuntimeParts parts;
  final List<StreamSubscription<Object?>> _subscriptions = [];

  static Future<Session> start(Stage stage, Directory work) async {
    final engine = await Engine.start(
      stage,
      Directory('${work.path}/home'),
      File('${work.path}/engine.log'),
    );
    final root = Directory('${work.path}/extensions');
    final registry = await ExtensionRegistry.open(root);
    final parts = ExtensionRuntimeParts(root: root, registry: registry);
    final browser = HeadlessBrowser(engine);
    final trace = <String>[];
    final traceFile = File(
      '${work.path}/trace.log',
    ).openWrite(mode: FileMode.append);
    final host = ExtensionHost(
      registry: registry,
      transport: engine,
      browser: browser,
      trace: (line) {
        trace.add(line);
        traceFile.writeln(line);
      },
      stateBuilder: parts.stateBuilder('mac'),
      apis: parts.apis,
    );
    final installer = ExtensionInstaller(
      registry: registry,
      amo: AmoClient(IoHttpFetcher(userAgent: 'RubiscoTests')),
    );
    final session = Session._(engine, browser, host, installer, parts);
    session.lines = trace;

    session._subscriptions.add(
      parts.webRequest.interestChanged.listen((_) {
        unawaited(host.pushState());
      }),
    );
    session._subscriptions.add(
      engine.intercepts.listen((held) async {
        engine.answerIntercept(
          held.request,
          await parts.intercept(held.details, held.view < 0 ? null : held.view),
        );
      }),
    );
    await host.start();
    engine.startIntercepting();
    return session;
  }

  /// What the host traced, and the errors of extension contexts.
  late final List<String> lines;

  Future<InstalledExtension> install(Directory directory) async {
    final result = await installer.installFromDirectory(
      directory,
      onPrompt: (_) async => true,
    );
    return result.extension;
  }

  Future<void> close() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await host.dispose();
    await engine.stop();
    await browser.dispose();
    await parts.registry.dispose();
  }
}
