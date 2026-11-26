import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../engine_state.dart';
import '../extension_registry.dart';
import '../manifest.dart';
import 'api.dart';
import 'browser_bridge.dart';
import 'event_registry.dart';
import 'extension_transport.dart';
import 'port_hub.dart';
import 'runtime_api.dart';

/// Runs the browser's side of every extension: it keeps the web content
/// processes told which content scripts to run, runs the extensions'
/// background pages, answers the API calls the extensions make, and delivers
/// events, messages and ports to them.
class ExtensionHost {
  ExtensionHost({
    required this.registry,
    required this.transport,
    required this.stateBuilder,
    required Iterable<ApiNamespace> apis,
    this.browser,
    this.trace,
  }) {
    for (final api in [RuntimeApi(), ...apis]) {
      _apis[api.name] = api;
    }
  }

  final ExtensionRegistry registry;
  final ExtensionTransport transport;
  final EngineStateBuilder stateBuilder;

  /// The browser's tabs and where to run background pages. Null in a host
  /// that has no browser around it, such as in a test of one API.
  final BrowserBridge? browser;

  /// Where a line goes for everything that passes between the host and an
  /// extension's contexts, for working out why an extension does not work.
  final void Function(String line)? trace;

  void _trace(String Function() line) {
    final sink = trace;
    if (sink != null) sink('[extensions] ${line()}');
  }

  /// Lets an API add a line to the trace, for what it does that no call shows.
  void note(String Function() line) => _trace(line);

  // Calls that are only the plumbing of other calls, or that happen hundreds
  // of times a minute in an extension that blocks requests, say nothing a
  // reader needs; what remains is what an extension asked for and what failed.
  static bool _isQuiet(String ns, String method) =>
      ns == 'bird' && (method == 'respond' || method == 'documentEvent');

  static String _brief(Object? value, [int limit = 240]) {
    final text = value is String ? value : jsonEncode(value);
    return text.length <= limit ? text : '${text.substring(0, limit)}...';
  }

  final StreamController<ExtensionContentSize> _contentSizes =
      StreamController<ExtensionContentSize>.broadcast();

  /// How much room the content of an extension's top-level page takes, each
  /// time it changes. A popup is sized from this.
  Stream<ExtensionContentSize> get contentSizes => _contentSizes.stream;

  final Map<String, ApiNamespace> _apis = {};
  final Map<int, ExtensionContext> _contexts = {};
  final Map<int, _Dispatch> _dispatches = {};
  final EventRegistry events = EventRegistry();
  final PortHub ports = PortHub();
  final List<StreamSubscription<Object?>> _subscriptions = [];
  final Map<String, Manifest?> _manifests = {};
  final Set<String> _backgroundPages = {};
  Future<void> _stateQueue = Future<void>.value();
  int _nextToken = 1;

  /// The contexts that currently exist.
  Iterable<ExtensionContext> get contexts => _contexts.values;

  Iterable<ExtensionContext> contextsOf(String extensionUuid) => _contexts
      .values
      .where((context) => context.extensionUuid == extensionUuid);

  ExtensionContext? context(int contextId) => _contexts[contextId];

  T? api<T extends ApiNamespace>(String name) {
    final found = _apis[name];
    return found is T ? found : null;
  }

  /// The id a frame is known by to extensions: 0 for a tab's top frame, and
  /// something unique for any other.
  int frameIdOf(ExtensionContext context) =>
      context.isTopLevel ? 0 : context.contextId;

  /// Starts serving: gives the processes the current state, starts the
  /// background pages, and keeps both current as extensions are installed,
  /// updated, enabled and removed.
  Future<void> start() async {
    for (final api in _apis.values) {
      api.attach(this);
    }

    _subscriptions
      ..add(transport.contextCreated.listen(_onContextCreated))
      ..add(transport.contextDestroyed.listen(_onContextDestroyed))
      ..add(transport.messages.listen(_onMessage))
      ..add(registry.changes.listen(_onRegistryChanged));

    await pushState();
    await syncBackgroundPages();
  }

  Future<void> dispose() async {
    await _contentSizes.close();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    for (final api in _apis.values) {
      api.detach();
    }
    await _stateQueue;
  }

  /// Rebuilds the state and gives it to the processes. Calls are run one at a
  /// time, in order, so the last state built is the last one sent.
  Future<void> pushState() {
    final next = _stateQueue.then((_) async {
      transport.setState(await stateBuilder.build());
    });
    _stateQueue = next.catchError((Object _) {});
    return next;
  }

  void _onRegistryChanged(RegistryChange change) {
    if (change.kind == RegistryChangeKind.removed) {
      _manifests.remove(change.extension.uuid);
      for (final api in _apis.values) {
        unawaited(api.extensionRemoved(change.extension));
      }
    } else {
      _manifests.remove(change.extension.uuid);
    }
    // The processes have to know of an extension before its background page
    // loads, or its files are refused to the page that asks for them.
    unawaited(pushState().then((_) => syncBackgroundPages(changed: change)));
  }

  // ------------------------------------------------------------ background pages

  /// The manifest of [extension], read from where it is installed.
  Future<Manifest?> manifestOf(InstalledExtension extension) async {
    if (_manifests.containsKey(extension.uuid)) {
      return _manifests[extension.uuid];
    }
    Manifest? manifest;
    try {
      final file = File(
        '${registry.directoryFor(extension).path}/manifest.json',
      );
      manifest = Manifest.parseBytes(await file.readAsBytes()).manifest;
    } on Object {
      manifest = null;
    }
    return _manifests[extension.uuid] = manifest;
  }

  /// The URL of the page [manifest] runs in the background, if it has one.
  static String? backgroundPageUrl(
    InstalledExtension extension,
    Manifest manifest,
  ) {
    final background = manifest.background;
    if (background == null || !background.isRunnable) return null;
    final page = background.page ?? '_generated_background_page.html';
    return '${extension.origin}/$page';
  }

  /// Restarts [extension]: its background page loads again, as when the
  /// extension calls `runtime.reload`.
  Future<void> reloadExtension(InstalledExtension extension) async {
    final bridge = browser;
    if (bridge == null) return;
    _manifests.remove(extension.uuid);
    if (_backgroundPages.remove(extension.uuid)) {
      await bridge.stopBackgroundPage(extension);
    }
    await syncBackgroundPages();
  }

  /// Makes the running background pages the ones that should be: one for
  /// each enabled extension that has one. A changed extension is restarted.
  Future<void> syncBackgroundPages({RegistryChange? changed}) async {
    final bridge = browser;
    if (bridge == null) return;

    final wanted = <String, (InstalledExtension, String)>{};
    for (final extension in registry.extensions) {
      if (!extension.enabled || extension.type != ExtensionType.extension) {
        continue;
      }
      final manifest = await manifestOf(extension);
      if (manifest == null) continue;
      final url = backgroundPageUrl(extension, manifest);
      if (url != null) wanted[extension.uuid] = (extension, url);
    }

    final restart = changed?.kind == RegistryChangeKind.updated
        ? changed!.extension.uuid
        : null;

    for (final uuid in _backgroundPages.toList()) {
      if (!wanted.containsKey(uuid) || uuid == restart) {
        _backgroundPages.remove(uuid);
        final extension = registry.byUuid(uuid) ?? changed?.extension;
        if (extension != null && extension.uuid == uuid) {
          await bridge.stopBackgroundPage(extension);
        }
      }
    }

    for (final entry in wanted.entries) {
      if (_backgroundPages.add(entry.key)) {
        await bridge.startBackgroundPage(entry.value.$1, entry.value.$2);
      }
    }
  }

  // ------------------------------------------------------------ contexts

  void _onContextCreated(ExtensionContext context) {
    _contexts[context.contextId] = context;
    _trace(
      () =>
          'context ${context.contextId} created (${context.kind.name}, '
          'view ${context.viewId}) ${context.url}',
    );
    for (final observer in _apis.values.whereType<ContextObserver>()) {
      observer.contextCreated(this, context);
    }
  }

  void _onContextDestroyed(int contextId) {
    final context = _contexts.remove(contextId);
    _trace(() => 'context $contextId destroyed');
    events.dropContext(contextId);

    // Whoever was asked to answer from here never will.
    for (final dispatch in _dispatches.values.toList()) {
      dispatch.noAnswerFrom(contextId);
    }
    _dispatches.removeWhere((_, dispatch) => dispatch.isFinished);

    // A port the context was on is closed, and its other end told.
    for (final entry in ports.dropContext(contextId).entries) {
      for (final other in entry.value) {
        dispatchEvent(other, 'bird.portDisconnect', [entry.key]);
      }
    }

    if (context == null) return;
    for (final observer in _apis.values.whereType<ContextObserver>()) {
      observer.contextDestroyed(this, context);
    }
  }

  // ------------------------------------------------------------ calls

  void _onMessage(TransportMessage message) {
    final context = _contexts[message.contextId];
    if (context == null) return;

    final Object? decoded;
    try {
      decoded = jsonDecode(message.payload);
    } on FormatException {
      return;
    }
    if (decoded is! Map) return;

    final id = decoded['id'];
    final ns = decoded['ns'];
    final method = decoded['method'];
    final args = decoded['args'];
    if (id is! int || ns is! String || method is! String) return;

    if (!_isQuiet(ns, method)) {
      _trace(
        () => 'context ${context.contextId} -> $ns.$method ${_brief(args)}',
      );
    }
    unawaited(
      _handleCall(context, id, ns, method, args is List ? args : const []),
    );
  }

  Future<void> _handleCall(
    ExtensionContext context,
    int id,
    String ns,
    String method,
    List<Object?> args,
  ) async {
    try {
      final extension = registry.byUuid(context.extensionUuid);
      if (extension == null || !extension.enabled) {
        throw ApiException('The extension is not available');
      }

      final Object? result;
      if (ns == 'bird') {
        result = _internalCall(context, method, args);
      } else if (ns == 'events') {
        result = _eventCall(context, method, args);
      } else {
        final api = _apis[ns];
        if (api == null) throw ApiException('$ns.$method is not supported');

        final needed = api.requiredPermission;
        if (needed != null && !extension.grantedPermissions.contains(needed)) {
          throw ApiException('The "$needed" permission is required to use $ns');
        }

        result = await api.call(
          ApiCall(
            host: this,
            context: context,
            extension: extension,
            method: method,
            args: args,
          ),
        );
      }

      _reply(context.contextId, id, result: result);
    } on ApiException catch (error) {
      _reply(context.contextId, id, error: error.message);
    } on Object catch (error) {
      _reply(context.contextId, id, error: 'Internal error: $error');
    }
  }

  void _reply(int contextId, int id, {Object? result, String? error}) {
    // A reply that carries nothing went well, and a call that did not is the
    // one worth a line.
    if (error != null) {
      _trace(() => 'context $contextId <- reply $id ERROR $error');
    }
    transport.send(
      contextId,
      jsonEncode({
        'reply': id,
        if (error != null) 'error': {'message': error} else 'result': ?result,
      }),
    );
  }

  /// Calls the shim makes about itself rather than about an API.
  Object? _internalCall(
    ExtensionContext context,
    String method,
    List<Object?> args,
  ) {
    Object? at(int index) => index < args.length ? args[index] : null;

    switch (method) {
      case 'respond':
        final token = at(0);
        final body = at(1);
        // Whether an answer was given is told by what was asked, not here.
        if (body is Map && body['error'] != null) {
          _trace(
            () =>
                'context ${context.contextId} answered #$token ${_brief(body)}',
          );
        }
        if (token is int && body is Map) {
          _dispatches[token]?.answer(
            context.contextId,
            body.cast<String, Object?>(),
          );
          _dispatches.removeWhere((_, dispatch) => dispatch.isFinished);
        }
        return null;

      case 'log':
        _trace(
          () => 'context ${context.contextId} ${at(0)}: ${_brief(at(1), 800)}',
        );
        return null;

      case 'contentSize':
        final width = at(0);
        final height = at(1);
        if (width is num && height is num) {
          _contentSizes.add(
            ExtensionContentSize(context, width.toDouble(), height.toDouble()),
          );
        }
        return null;

      case 'portPost':
        final portId = at(0);
        if (portId is! String) return null;
        for (final destination in ports.destinations(
          portId,
          context.contextId,
        )) {
          dispatchEvent(destination, 'bird.portMessage', [portId, at(1)]);
        }
        return null;

      case 'portDisconnect':
        final portId = at(0);
        if (portId is! String) return null;
        for (final other in ports.close(portId, context.contextId)) {
          dispatchEvent(other, 'bird.portDisconnect', [portId]);
        }
        return null;

      case 'documentEvent':
        final name = at(0);
        if (name is String) {
          for (final observer in _apis.values.whereType<ContextObserver>()) {
            observer.documentEvent(this, context, name);
          }
        }
        return null;

      default:
        throw ApiException('bird.$method is not supported');
    }
  }

  Object? _eventCall(
    ExtensionContext context,
    String method,
    List<Object?> args,
  ) {
    final event = args.isNotEmpty ? args[0] : null;
    if (event is! String) {
      throw ApiException('events.$method needs an event name');
    }

    switch (method) {
      case 'addListener':
        final rest = args.length > 1 && args[1] is List
            ? args[1]! as List<Object?>
            : const <Object?>[];
        events.add(event, context.contextId, rest);
        for (final observer in _apis.values.whereType<EventObserver>()) {
          observer.listenerAdded(this, context, event, rest);
        }
        return null;
      case 'removeListener':
        final rest = args.length > 1 && args[1] is List
            ? args[1]! as List<Object?>
            : null;
        events.remove(event, context.contextId, rest);
        for (final observer in _apis.values.whereType<EventObserver>()) {
          observer.listenerRemoved(this, context, event);
        }
        return null;
      default:
        throw ApiException('events.$method is not supported');
    }
  }

  // ------------------------------------------------------------ events

  /// Sends an event to one context.
  bool dispatchEvent(int contextId, String event, List<Object?> args) {
    return transport.send(
      contextId,
      jsonEncode({'event': event, 'args': args}),
    );
  }

  /// The contexts of [extensionUuid] that listen for [event].
  Iterable<ExtensionContext> listeners(String extensionUuid, String event) {
    return [
      for (final id in events.contextsFor(event))
        if (_contexts[id] case final context?
            when context.extensionUuid == extensionUuid)
          context,
    ];
  }

  /// Sends an event to every context of an extension that listens for it.
  void emit(
    String extensionUuid,
    String event,
    List<Object?> args, {
    int? except,
  }) {
    final payload = jsonEncode({'event': event, 'args': args});
    for (final context in listeners(extensionUuid, event).toList()) {
      if (context.contextId != except) {
        transport.send(context.contextId, payload);
      }
    }
  }

  /// Sends an event to the listeners of every extension, with arguments that
  /// can differ by extension.
  void emitToAll(
    String event,
    List<Object?> Function(InstalledExtension) argumentsFor,
  ) {
    for (final extension in registry.extensions) {
      if (!extension.enabled) continue;
      final targets = listeners(extension.uuid, event).toList();
      if (targets.isEmpty) continue;

      final payload = jsonEncode({
        'event': event,
        'args': argumentsFor(extension),
      });
      for (final context in targets) {
        transport.send(context.contextId, payload);
      }
    }
  }

  /// Delivers a message to [targets] as `runtime.onMessage` and returns what
  /// the first one to answer answers. It completes with null when every
  /// target had nothing to say, and fails when a target's listener failed.
  Future<Object?> deliverMessage(
    Iterable<ExtensionContext> targets,
    Object? message,
    Map<String, Object?> sender,
  ) {
    final token = _nextToken++;
    final dispatch = _Dispatch(targets.map((target) => target.contextId));
    _dispatches[token] = dispatch;
    _trace(
      () =>
          'runtime.onMessage #$token to '
          '${targets.map((target) => target.contextId).toList()}: '
          '${_brief(message)}',
    );

    final payload = jsonEncode({
      'event': 'runtime.onMessage',
      'args': [message, sender],
      'token': token,
    });
    for (final target in targets.toList()) {
      if (!transport.send(target.contextId, payload)) {
        dispatch.noAnswerFrom(target.contextId);
      }
    }

    if (dispatch.isFinished) _dispatches.remove(token);
    if (trace != null) {
      dispatch.completer.future.then(
        (answer) => _trace(
          () =>
              'runtime.onMessage #$token '
              '${answer == null ? 'was not answered' : 'was answered: ${_brief(answer)}'}',
        ),
        onError: (Object error) =>
            _trace(() => 'runtime.onMessage #$token failed: $error'),
      );
    }
    return dispatch.completer.future;
  }

  /// Asks every context in [targets] to answer [event], and collects what each
  /// one answers: the values of those that handled it, in no particular order.
  /// Fails if one reported an error.
  Future<List<Object?>> askContexts(
    Iterable<ExtensionContext> targets,
    String event,
    List<Object?> args,
  ) {
    final token = _nextToken++;
    final dispatch = _Dispatch(
      targets.map((target) => target.contextId),
      collectAll: true,
    );
    _dispatches[token] = dispatch;

    final payload = jsonEncode({'event': event, 'args': args, 'token': token});
    for (final target in targets.toList()) {
      if (!transport.send(target.contextId, payload)) {
        dispatch.noAnswerFrom(target.contextId);
      }
    }

    if (dispatch.isFinished) _dispatches.remove(token);
    return dispatch.completer.future.then(
      (value) => (value as List?)?.cast<Object?>() ?? const [],
    );
  }

  /// Asks the listeners of a blocking event for its verdict: the first
  /// listener to answer. Completes with null when none had one. [timeout]
  /// bounds the wait, because the request is held while it runs.
  Future<Object?> askListeners(
    Iterable<ExtensionContext> targets,
    String event,
    List<Object?> args, {
    Duration timeout = const Duration(seconds: 5),
  }) {
    final token = _nextToken++;
    final dispatch = _Dispatch(targets.map((target) => target.contextId));
    _dispatches[token] = dispatch;

    final payload = jsonEncode({'event': event, 'args': args, 'token': token});
    for (final target in targets.toList()) {
      if (!transport.send(target.contextId, payload)) {
        dispatch.noAnswerFrom(target.contextId);
      }
    }
    if (dispatch.isFinished) _dispatches.remove(token);

    return dispatch.completer.future.timeout(
      timeout,
      onTimeout: () {
        _dispatches.remove(token);
        return null;
      },
    );
  }

  // ------------------------------------------------------------ ports

  /// Opens a port from [opener] to [targets] and tells them.
  void openPort({
    required String portId,
    required String name,
    required ExtensionContext opener,
    required Iterable<ExtensionContext> targets,
    required Map<String, Object?> sender,
  }) {
    final peers = targets.toList();
    ports.open(
      id: portId,
      name: name,
      opener: opener.contextId,
      peers: peers.map((peer) => peer.contextId),
    );
    for (final peer in peers) {
      dispatchEvent(peer.contextId, 'runtime.onConnect', [
        {'portId': portId, 'name': name, 'sender': sender},
      ]);
    }
  }
}

/// An API that wants to know when an extension starts or stops listening to an
/// event, as webRequest does so that it only intercepts what someone wants.
abstract interface class EventObserver {
  void listenerAdded(
    ExtensionHost host,
    ExtensionContext context,
    String event,
    List<Object?> arguments,
  );

  void listenerRemoved(
    ExtensionHost host,
    ExtensionContext context,
    String event,
  );
}

/// One message waiting on the contexts it was delivered to.
class _Dispatch {
  _Dispatch(Iterable<int> contexts, {this.collectAll = false})
    : _awaiting = contexts.toSet() {
    if (_awaiting.isEmpty) completer.complete(collectAll ? <Object?>[] : null);
  }

  final Set<int> _awaiting;
  final bool collectAll;
  final List<Object?> _collected = [];
  final Completer<Object?> completer = Completer<Object?>();

  bool get isFinished => completer.isCompleted;

  void answer(int contextId, Map<String, Object?> body) {
    // Only a context the message was delivered to may answer it. Tokens are
    // small numbers, so without this any context could answer for another.
    if (isFinished || !_awaiting.contains(contextId)) return;

    final error = body['error'];
    if (body['handled'] == true) {
      if (error is Map) {
        completer.completeError(ApiException('${error['message']}'));
        return;
      }
      if (collectAll) {
        _collected.add(body['value']);
      } else {
        completer.complete(body['value']);
        return;
      }
    }
    noAnswerFrom(contextId);
  }

  void noAnswerFrom(int contextId) {
    if (isFinished) return;
    _awaiting.remove(contextId);
    if (_awaiting.isEmpty) completer.complete(collectAll ? _collected : null);
  }
}

/// The size of the content of a page of an extension, as it laid itself out.
class ExtensionContentSize {
  const ExtensionContentSize(this.context, this.width, this.height);

  final ExtensionContext context;
  final double width;
  final double height;
}
