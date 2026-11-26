import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../protocol/devtools_connection.dart';
import '../protocol/json.dart';
import '../protocol/rdp_client.dart';
import '../protocol/rdp_transport.dart';
import 'accessibility_controller.dart';
import 'application_controller.dart';
import 'console_controller.dart';
import 'debugger_controller.dart';
import 'inspector_controller.dart';
import 'network_controller.dart';
import 'performance_controller.dart';
import 'remote_value.dart';
import 'settings.dart';
import 'storage_controller.dart';
import 'style_editor_controller.dart';
import 'tool_controller.dart';

/// The actors of one document of the inspected tab.
class DevToolsTarget {
  const DevToolsTarget({
    required this.actor,
    required this.url,
    required this.title,
    required this.consoleActor,
    required this.inspectorActor,
    required this.threadActor,
    required this.styleSheetsActor,
    required this.accessibilityActor,
    required this.cssPropertiesActor,
  });

  factory DevToolsTarget.parse(Map<String, Object?> form) => DevToolsTarget(
    actor: form.str('actor'),
    url: form.str('url'),
    title: form.str('title'),
    consoleActor: form.str('consoleActor'),
    inspectorActor: form.str('inspectorActor'),
    threadActor: form.str('threadActor'),
    styleSheetsActor: form.str('styleSheetsActor'),
    accessibilityActor: form.str('accessibilityActor'),
    cssPropertiesActor: form.str('cssPropertiesActor'),
  );

  final String actor;
  final String url;
  final String title;
  final String consoleActor;
  final String inspectorActor;
  final String threadActor;
  final String styleSheetsActor;
  final String accessibilityActor;
  final String cssPropertiesActor;
}

/// How an evaluation in the page ended.
class EvaluationOutcome {
  const EvaluationOutcome({required this.value, this.threw = false});
  final RemoteValue value;
  final bool threw;
}

class PageScriptError implements Exception {
  const PageScriptError(this.message);
  final String message;
  @override
  String toString() => message;
}

enum SessionState { connecting, ready, failed, closed }

/// Developer tools attached to one tab.
class ToolboxSession extends ChangeNotifier {
  ToolboxSession({
    required this.connection,
    required this.browserId,
    required this.settings,
  }) {
    console = ConsoleController(this);
    network = NetworkController(this);
    inspector = InspectorController(this);
    debugger = DebuggerController(this);
    styleEditor = StyleEditorController(this);
    storage = StorageController(this);
    accessibility = AccessibilityController(this);
    performance = PerformanceController(this);
    application = ApplicationController(this);
    controllers = [
      // The console and network monitor hear of a navigation before the rest.
      console,
      network,
      inspector,
      debugger,
      styleEditor,
      storage,
      accessibility,
      performance,
      application,
    ];
    connection.done.then((_) {
      if (_disposed) return;
      _setState(SessionState.closed);
    });
  }

  static const List<String> _watchedResources = [
    'console-message',
    'error-message',
    'network-event',
    'document-event',
    'cookies',
    'local-storage',
    'session-storage',
    'indexed-db',
    'source',
    'thread-state',
    'stylesheet',
  ];

  final DevToolsConnection connection;

  /// The number the browser knows the inspected tab by.
  final int browserId;
  final DevToolsSettings settings;

  late final ConsoleController console;
  late final NetworkController network;
  late final InspectorController inspector;
  late final DebuggerController debugger;
  late final StyleEditorController styleEditor;
  late final StorageController storage;
  late final AccessibilityController accessibility;
  late final PerformanceController performance;
  late final ApplicationController application;
  late final List<ToolController> controllers;

  SessionState state = SessionState.connecting;
  String failure = '';

  DevToolsTarget? target;
  String? watcherActor;
  String? breakpointListActor;
  String? threadConfigurationActor;
  String url = '';
  String title = '';

  /// The names of the CSS properties the engine knows, with whether each is
  /// inherited.
  Map<String, bool> cssProperties = const {};

  /// Set by the toolbox: shows a tool, as when the debugger pauses.
  void Function(String panel)? onSelectTool;

  /// Set by the host: opens an address in a new tab.
  void Function(String url)? onOpenLink;

  /// Set by the host: saves [contents] where the user chooses.
  Future<void> Function(String suggestedName, List<int> bytes)? onSaveFile;

  final List<void Function()> _disposers = [];
  final List<void Function()> _targetDisposers = [];
  final Map<String, Completer<RdpPacket>> _evaluations = {};
  // Results that arrived before the request's answer said whose they are.
  final Map<String, RdpPacket> _earlyResults = {};
  // The engine keeps one result callback per page, so a second evaluation
  // would take the first one's answer. Outside the debugger they take turns.
  Future<void> _lastTurn = Future<void>.value();
  Completer<void>? _turn;
  bool _disposed = false;

  bool get isReady => state == SessionState.ready;

  void selectTool(String panel) => onSelectTool?.call(panel);

  Future<void> start() async {
    _setState(SessionState.connecting);
    try {
      var tab = await connection.tab(browserId);
      if (tab == null) {
        // The tab may not be listed until its first document exists.
        await Future<void>.delayed(const Duration(milliseconds: 500));
        tab = await connection.tab(browserId);
      }
      if (_disposed) return;
      if (tab == null) {
        throw StateError('The engine has no tab number $browserId.');
      }
      url = tab.url;
      title = tab.title;

      final watcher = (await connection.request(
        tab.actor,
        'getWatcher',
      )).str('actor');
      watcherActor = watcher;
      _disposers.add(connection.listen(watcher, _onWatcherPacket));

      breakpointListActor = (await connection.request(
        watcher,
        'getBreakpointListActor',
      )).str('breakpointList');
      threadConfigurationActor = (await connection.request(
        watcher,
        'getThreadConfigurationActor',
      )).obj('configuration').str('actor');
      await debugger.applyConfiguration();

      await connection.request(watcher, 'watchTargets', {
        'targetType': 'frame',
      });
      await connection.request(watcher, 'watchResources', {
        'resourceTypes': _watchedResources,
      });
      await debugger.restoreBreakpoints();
      if (_disposed) return;
      _setState(SessionState.ready);
    } catch (error, stack) {
      if (_disposed) return;
      debugPrint('DevTools could not attach: $error\n$stack');
      failure = '$error';
      _setState(SessionState.failed);
    }
  }

  void _setState(SessionState next) {
    state = next;
    if (!_disposed) notifyListeners();
  }

  void _onWatcherPacket(RdpPacket packet) {
    switch (packet['type']) {
      case 'target-available-form':
        _onTarget(DevToolsTarget.parse(packet.obj('target')));
      case 'target-destroyed-form':
        if (packet.obj('target').str('actor') == target?.actor) {
          _dropTarget();
        }
      default:
        _onTargetPacket(packet);
    }
  }

  void _onTarget(DevToolsTarget next) {
    _dropTarget(quiet: true);
    target = next;
    url = next.url;
    title = next.title;
    _targetDisposers
      ..add(connection.listen(next.actor, _onTargetPacket))
      ..add(connection.listen(next.consoleActor, _onConsolePacket));
    for (final controller in controllers) {
      controller.onTargetAvailable(next);
    }
    // Asking for the frames is what releases the document events of a load.
    connection.notify(next.actor, 'listFrames');
    if (cssProperties.isEmpty) _loadCssDatabase(next.cssPropertiesActor);
    notifyListeners();
  }

  void _dropTarget({bool quiet = false}) {
    if (target == null) return;
    for (final dispose in _targetDisposers) {
      dispose();
    }
    _targetDisposers.clear();
    target = null;
    for (final waiting in _evaluations.values) {
      if (!waiting.isCompleted) {
        waiting.completeError(const PageScriptError('The page navigated'));
      }
    }
    _evaluations.clear();
    _earlyResults.clear();
    for (final controller in controllers) {
      controller.onTargetDestroyed();
    }
    if (!quiet) notifyListeners();
  }

  Future<void> _loadCssDatabase(String actor) async {
    try {
      final response = await connection.request(actor, 'getCSSDatabase');
      cssProperties = {
        for (final entry in response.obj('properties').entries)
          entry.key:
              entry.value is Map<String, Object?> &&
              (entry.value! as Map<String, Object?>).flag('isInherited'),
      };
    } on RdpError {
      // Completion of property names does without.
    }
  }

  void _onTargetPacket(RdpPacket packet) {
    final type = packet['type'];
    if (type == 'resources-available-array') {
      _forEachResource(packet, (resourceType, resources) {
        if (resourceType == 'document-event') {
          resources.forEach(_onDocumentEvent);
          return;
        }
        if (resourceType == 'error-message') _giveUpTurnSoon();
        for (final controller in controllers) {
          controller.onResources(resourceType, resources);
        }
      });
    } else if (type == 'resources-updated-array') {
      _forEachResource(packet, (resourceType, updates) {
        for (final controller in controllers) {
          controller.onResourceUpdates(resourceType, updates);
        }
      });
    }
  }

  void _forEachResource(
    RdpPacket packet,
    void Function(String type, List<Map<String, Object?>> resources) visit,
  ) {
    for (final entry in packet.list('array')) {
      if (entry is! List<Object?> || entry.length != 2) continue;
      final type = entry[0];
      final resources = entry[1];
      if (type is! String || resources is! List<Object?>) continue;
      visit(type, [
        for (final resource in resources)
          if (resource is Map<String, Object?>) resource,
      ]);
    }
  }

  void _onDocumentEvent(Map<String, Object?> event) {
    switch (event.str('name')) {
      case 'will-navigate':
        final destination = event.str('newURI');
        url = destination;
        for (final controller in controllers) {
          controller.onWillNavigate(destination);
        }
        notifyListeners();
      case 'dom-interactive':
        title = event.str('title', title);
        notifyListeners();
      case 'dom-complete':
        for (final controller in controllers) {
          controller.onDocumentComplete();
        }
    }
  }

  void _onConsolePacket(RdpPacket packet) {
    if (packet['type'] == 'evaluationResult') {
      final id = packet.str('resultID');
      final waiting = _evaluations.remove(id);
      if (waiting != null) {
        if (!waiting.isCompleted) waiting.complete(packet);
      } else {
        _earlyResults[id] = packet;
        if (_earlyResults.length > 32) {
          _earlyResults.remove(_earlyResults.keys.first);
        }
      }
    } else if (packet['type'] == 'inspectObject') {
      final reference = packet.obj('objectActor').mapOrNull(
        'contentDomReference',
      );
      if (reference != null) {
        selectTool('inspector');
        inspector.selectContentDomReference(reference);
      }
    }
  }

  // Script that throws is never answered; its error is the sign to move on.
  void _giveUpTurnSoon() {
    final turn = _turn;
    if (turn == null) return;
    Timer(const Duration(milliseconds: 300), () {
      if (!turn.isCompleted) turn.complete();
    });
  }

  /// Evaluates [source] in the page, or in the paused frame [frameActor].
  ///
  /// The engine answers nothing for script that throws outside the debugger:
  /// the error reaches the console as any page error does. Such a call ends in
  /// a [TimeoutException] once [timeout] passes.
  Future<EvaluationOutcome> evaluate(
    String source, {
    String? frameActor,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    if (frameActor != null) return _evaluateNow(source, frameActor, timeout);
    final before = _lastTurn;
    final turn = Completer<void>();
    _lastTurn = turn.future;
    await before;
    _turn = turn;
    try {
      return await _evaluateNow(source, null, timeout);
    } finally {
      if (!turn.isCompleted) turn.complete();
    }
  }

  Future<EvaluationOutcome> _evaluateNow(
    String source,
    String? frameActor,
    Duration timeout,
  ) async {
    final console = target?.consoleActor;
    if (console == null) throw const PageScriptError('No page to run in');
    final accepted = await connection.request(console, 'evaluateJSAsync', {
      'text': source,
      'frameActor': ?frameActor,
    });
    final id = accepted.str('resultID');
    var result = _earlyResults.remove(id);
    if (result == null) {
      final completer = Completer<RdpPacket>();
      _evaluations[id] = completer;
      try {
        result = await completer.future.timeout(timeout);
      } finally {
        _evaluations.remove(id);
      }
    }
    final threw = result.flag('hasException');
    return EvaluationOutcome(
      value: RemoteValue.parse(result[threw ? 'exception' : 'result']),
      threw: threw,
    );
  }

  /// Runs [functionBody] in the page for the tools' own use and returns what it
  /// returns, by way of JSON. Nothing shows in the console.
  Future<Object?> runInPage(
    String functionBody, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final outcome = await evaluate(
      '(() => { try { return JSON.stringify({ ok: (() => {\n$functionBody\n})() }); } '
      'catch (error) { return JSON.stringify({ error: String(error) }); } })()',
      timeout: timeout,
    );
    if (outcome.threw || !outcome.value.isString) {
      throw const PageScriptError('The page gave no answer');
    }
    final decoded = jsonDecode(outcome.value.value! as String);
    if (decoded is! Map<String, Object?>) {
      throw const PageScriptError('The page gave no answer');
    }
    if (decoded['error'] case final String error) throw PageScriptError(error);
    return decoded['ok'];
  }

  /// Navigates or reloads the inspected tab.
  void reload({bool bypassCache = false}) {
    final actor = target?.actor;
    if (actor == null) return;
    connection.notify(actor, 'reload', {
      'options': {'force': bypassCache},
    });
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    // Leaving the page as it was found.
    inspector.release();
    debugger.release();
    for (final dispose in [..._targetDisposers, ..._disposers]) {
      dispose();
    }
    final watcher = watcherActor;
    final actor = target?.actor;
    if (actor != null && !connection.isClosed) {
      connection.notify(actor, 'detach');
    }
    if (watcher != null) _disposers.clear();
    for (final controller in controllers) {
      controller.dispose();
    }
    super.dispose();
  }
}
