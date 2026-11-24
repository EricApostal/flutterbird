import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:bird_extensions/bird_extensions.dart';

/// True when a `node` is on the path to run worlds with.
final bool hasNode = () {
  try {
    return Process.runSync('node', ['--version']).exitCode == 0;
  } on ProcessException {
    return false;
  }
}();

/// One extension world, running the real shim in a Node process.
class NodeWorld {
  NodeWorld._(this._process);

  final Process _process;
  final StreamController<String> _sent = StreamController<String>.broadcast();
  final List<String> logs = [];
  final List<String> phases = [];
  final Map<int, Completer<Object?>> _running = {};
  final Completer<void> _ready = Completer<void>();
  int _nextRun = 1;

  /// Strings the world sent to the browser.
  Stream<String> get sent => _sent.stream;

  /// Starts a world for [extension] out of the engine state [state], the same
  /// pieces the engine runs: the shim and that extension's `init`.
  static Future<NodeWorld> start({
    required Map<String, Object?> state,
    required String extensionUuid,
    String? initOverride,
    bool isPage = false,
  }) async {
    final extensions = (state['extensions']! as List)
        .cast<Map<String, Object?>>();
    final entry = extensions.firstWhere((e) => e['uuid'] == extensionUuid);

    final process = await Process.start('node', [
      'test/support/world_process.js',
    ]);
    final world = NodeWorld._(process);

    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(world._onLine);
    process.stderr.transform(utf8.decoder).listen(world.logs.add);

    process.stdin.writeln(
      jsonEncode({
        'cmd': 'init',
        'init': initOverride ?? entry['init'],
        'shim': state['shim'],
        'page': isPage,
      }),
    );
    await world._ready.future.timeout(const Duration(seconds: 10));
    return world;
  }

  void _onLine(String line) {
    final message = jsonDecode(line) as Map<String, Object?>;

    if (message['ready'] == true) {
      _ready.complete();
    } else if (message['send'] case final String text) {
      _sent.add(text);
    } else if (message['phase'] case final String phase) {
      phases.add(phase);
    } else if (message['log'] case final String log) {
      logs.add(log);
    } else if (message['ran'] case final int id) {
      final completer = _running.remove(id);
      if (message.containsKey('error')) {
        completer?.completeError(StateError('${message['error']}'));
      } else {
        completer?.complete(message['value']);
      }
    }
  }

  /// Evaluates [code] in the world, waiting for a promise it returns.
  Future<Object?> run(String code) {
    final id = _nextRun++;
    final completer = Completer<Object?>();
    _running[id] = completer;
    _process.stdin.writeln(jsonEncode({'cmd': 'run', 'id': id, 'code': code}));
    return completer.future.timeout(const Duration(seconds: 10));
  }

  /// Hands the world a string from the browser.
  void deliver(String payload) {
    _process.stdin.writeln(jsonEncode({'cmd': 'deliver', 'payload': payload}));
  }

  Future<void> close() async {
    await _process.stdin.close();
    _process.kill();
    await _sent.close();
  }
}

/// A transport whose contexts are [NodeWorld]s.
class WorldTransport implements ExtensionTransport {
  final StreamController<ExtensionContext> _created =
      StreamController<ExtensionContext>.broadcast();
  final StreamController<int> _destroyed = StreamController<int>.broadcast();
  final StreamController<TransportMessage> _messages =
      StreamController<TransportMessage>.broadcast();
  final Map<int, NodeWorld> _worlds = {};

  /// Every state the host gave the processes, oldest first.
  final List<String> states = [];

  /// Everything the host sent to each context, oldest first.
  final Map<int, List<String>> delivered = {};

  /// Makes the host see [payload] as if the context had sent it.
  void inject(int contextId, String payload) =>
      _messages.add(TransportMessage(contextId, payload));

  @override
  Stream<ExtensionContext> get contextCreated => _created.stream;

  @override
  Stream<int> get contextDestroyed => _destroyed.stream;

  @override
  Stream<TransportMessage> get messages => _messages.stream;

  @override
  void setState(String json) => states.add(json);

  @override
  bool send(int contextId, String payload) {
    (delivered[contextId] ??= []).add(payload);
    final world = _worlds[contextId];
    if (world == null) return false;
    world.deliver(payload);
    return true;
  }

  /// Makes [world] the world of [context], as the engine does when a document
  /// gets a content script.
  Future<void> attach(ExtensionContext context, NodeWorld world) async {
    _worlds[context.contextId] = world;
    world.sent.listen(
      (payload) => _messages.add(TransportMessage(context.contextId, payload)),
    );
    _created.add(context);
    await Future<void>.delayed(Duration.zero);
  }

  Future<void> destroy(int contextId) async {
    _worlds.remove(contextId);
    _destroyed.add(contextId);
    await Future<void>.delayed(Duration.zero);
  }
}
