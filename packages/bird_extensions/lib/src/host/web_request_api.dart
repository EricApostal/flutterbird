import 'dart:async';
import 'dart:convert';

import '../extension_registry.dart';
import '../match_pattern.dart';
import 'api.dart';
import 'extension_host.dart';
import 'extension_transport.dart';

/// What an extension answers a blocking webRequest event with.
class RequestVerdict {
  const RequestVerdict({
    this.cancel = false,
    this.redirectUrl,
    this.requestHeaders,
    this.responseHeaders,
  });

  final bool cancel;
  final String? redirectUrl;
  final List<Map<String, Object?>>? requestHeaders;
  final List<Map<String, Object?>>? responseHeaders;

  bool get changesAnything =>
      cancel ||
      redirectUrl != null ||
      requestHeaders != null ||
      responseHeaders != null;

  static const RequestVerdict allow = RequestVerdict();

  factory RequestVerdict.fromJson(Object? json) {
    if (json is! Map) return allow;

    List<Map<String, Object?>>? headers(Object? value) => value is List
        ? [
            for (final header in value)
              if (header is Map) header.cast<String, Object?>(),
          ]
        : null;

    return RequestVerdict(
      cancel: json['cancel'] == true,
      redirectUrl: json['redirectUrl'] is String
          ? json['redirectUrl'] as String
          : null,
      requestHeaders: headers(json['requestHeaders']),
      responseHeaders: headers(json['responseHeaders']),
    );
  }
}

/// `browser.webRequest`: the extensions' view of the network.
///
/// This is the browser's half. The network layer tells it about each request
/// through [dispatch] and [observe], and it asks the extensions that listen,
/// then answers with what to do. The listeners are tracked so that the
/// network layer only intercepts requests when an extension wants them.
class WebRequestApi extends ApiNamespace implements EventObserver {
  final StreamController<void> _interest = StreamController<void>.broadcast();
  ExtensionHost? _host;

  @override
  String get name => 'webRequest';

  @override
  String? get requiredPermission => 'webRequest';

  /// The events a blocking listener can answer.
  static const Set<String> blockingEvents = {
    'webRequest.onBeforeRequest',
    'webRequest.onBeforeSendHeaders',
    'webRequest.onHeadersReceived',
    'webRequest.onAuthRequired',
  };

  static const Set<String> _allEvents = {
    ...blockingEvents,
    'webRequest.onSendHeaders',
    'webRequest.onBeforeRedirect',
    'webRequest.onResponseStarted',
    'webRequest.onCompleted',
    'webRequest.onErrorOccurred',
  };

  /// Fires when an extension starts or stops listening to a webRequest event.
  Stream<void> get interestChanged => _interest.stream;

  @override
  void attach(ExtensionHost host) => _host = host;

  /// Whether any extension listens to [event].
  bool isWanted(String event) =>
      (_host?.events.contextsFor(event) ?? const <int>[]).isNotEmpty;

  /// Whether any extension asked to block with [event].
  bool wantsToBlock(String event) {
    final host = _host;
    if (host == null) return false;
    return host.events
        .contextsFor(event)
        .any(
          (contextId) =>
              host.events.argumentSetsOf(event, contextId).any(_isBlocking),
        );
  }

  static bool _isBlocking(List<Object?>? arguments) {
    final spec = arguments != null && arguments.length > 1
        ? arguments[1]
        : null;
    return spec is List && spec.contains('blocking');
  }

  @override
  void listenerAdded(
    ExtensionHost host,
    ExtensionContext context,
    String event,
    List<Object?> arguments,
  ) {
    if (_allEvents.contains(event)) _interest.add(null);
  }

  @override
  void listenerRemoved(
    ExtensionHost host,
    ExtensionContext context,
    String event,
  ) {
    if (_allEvents.contains(event)) _interest.add(null);
  }

  @override
  Future<Object?> call(ApiCall call) async {
    switch (call.method) {
      case 'handlerBehaviorChanged':
        return null;
      case 'filterResponseData':
        throw ApiException(
          'webRequest.filterResponseData is not supported yet',
        );
      case 'getSecurityInfo':
        throw ApiException('webRequest.getSecurityInfo is not supported yet');
      default:
        throw ApiException('webRequest.${call.method} is not supported');
    }
  }

  // ------------------------------------------------------------ the network's side

  /// Whether a listener's filter lets [details] through.
  bool _passes(Object? filter, Map<String, Object?> details) {
    if (filter is! Map) return true;

    final urls = filter['urls'];
    if (urls is List) {
      final patterns = MatchPatternSet.parse(urls.whereType<String>());
      if (!patterns.matchesString('${details['url']}')) return false;
    }
    final types = filter['types'];
    if (types is List && !types.contains(details['type'])) return false;
    final tabId = filter['tabId'];
    if (tabId is int && tabId != details['tabId']) return false;
    return true;
  }

  /// An extension may only see requests to hosts it was granted.
  bool _mayObserve(InstalledExtension extension, Map<String, Object?> details) {
    final url = Uri.tryParse('${details['url']}');
    if (url == null) return false;
    return extension.grantedOrigins.any(
      (origin) => MatchPattern.tryParse(origin)?.matches(url) ?? false,
    );
  }

  Iterable<(InstalledExtension, List<ExtensionContext>)> _interested(
    String event,
    Map<String, Object?> details, {
    required bool blocking,
  }) sync* {
    final host = _host;
    if (host == null) return;

    for (final extension in host.registry.extensions) {
      if (!extension.enabled ||
          !extension.grantedPermissions.contains('webRequest')) {
        continue;
      }
      if (!_mayObserve(extension, details)) continue;

      // A context is asked when any one of its listeners wants the request.
      final contexts = [
        for (final context in host.listeners(extension.uuid, event))
          if (host.events
              .argumentSetsOf(event, context.contextId)
              .any(
                (arguments) =>
                    _passes(arguments.firstOrNull, details) &&
                    (!blocking || _isBlocking(arguments)),
              ))
            context,
      ];
      if (contexts.isNotEmpty) yield (extension, contexts);
    }
  }

  /// Asks the extensions that block with [event] what to do with a request.
  /// The first extension to cancel or redirect decides; header changes from
  /// the others are applied in order.
  Future<RequestVerdict> dispatch(
    String event,
    Map<String, Object?> details,
  ) async {
    final host = _host;
    if (host == null || !blockingEvents.contains(event)) {
      return RequestVerdict.allow;
    }

    RequestVerdict? merged;
    for (final (_, contexts) in _interested(
      event,
      details,
      blocking: true,
    ).toList()) {
      final answer = await host.askListeners(contexts, event, [details]);
      final verdict = RequestVerdict.fromJson(answer);
      if (verdict.cancel || verdict.redirectUrl != null) return verdict;
      if (verdict.changesAnything) merged = verdict;
    }
    return merged ?? RequestVerdict.allow;
  }

  /// Asks the extensions what to do with a request about to be sent, and
  /// answers as the network layer wants it: JSON with any of `cancel`,
  /// `redirectUrl` and `requestHeaders`, or `{}` to let it go ahead.
  Future<String> intercept(Map<String, Object?> details) async {
    final request = {
      ...details,
      'timeStamp': DateTime.now().millisecondsSinceEpoch.toDouble(),
      'processId': -1,
    };

    final first = await dispatch('webRequest.onBeforeRequest', request);
    if (first.cancel) return jsonEncode({'cancel': true});
    if (first.redirectUrl != null) {
      return jsonEncode({'redirectUrl': first.redirectUrl});
    }

    // The request is held once for both events: this layer cannot yet ask
    // about the headers the network will add, so listeners see none.
    if (!isWanted('webRequest.onBeforeSendHeaders')) return '{}';
    final second = await dispatch('webRequest.onBeforeSendHeaders', {
      ...request,
      'requestHeaders': const <Object?>[],
    });
    if (second.cancel) return jsonEncode({'cancel': true});
    return jsonEncode({
      'redirectUrl': ?second.redirectUrl,
      'requestHeaders': ?second.requestHeaders,
    });
  }

  /// Tells the extensions that listen to [event] about a request, with no
  /// answer wanted.
  void observe(String event, Map<String, Object?> details) {
    final host = _host;
    if (host == null) return;

    for (final (_, contexts) in _interested(
      event,
      details,
      blocking: false,
    ).toList()) {
      for (final context in contexts) {
        host.dispatchEvent(context.contextId, event, [details]);
      }
    }
  }
}
