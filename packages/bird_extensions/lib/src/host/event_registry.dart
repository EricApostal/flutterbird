/// Which contexts have a listener for which event, and with what arguments.
///
/// A context's shim tells the browser when its first listener for an event
/// arrives and when its last leaves (see `createEvent` in the shim), so the
/// browser only does work for events someone is listening to.
class EventRegistry {
  final Map<String, Map<int, List<Object?>>> _listeners = {};

  /// Records that [contextId] listens for [event]. [arguments] are what
  /// followed the listener in `addListener`, such as a webRequest filter.
  void add(String event, int contextId, List<Object?> arguments) {
    (_listeners[event] ??= {})[contextId] = arguments;
  }

  void remove(String event, int contextId) {
    final contexts = _listeners[event];
    contexts?.remove(contextId);
    if (contexts != null && contexts.isEmpty) _listeners.remove(event);
  }

  /// Forgets everything about a context that is gone.
  void dropContext(int contextId) {
    for (final contexts in _listeners.values) {
      contexts.remove(contextId);
    }
    _listeners.removeWhere((_, contexts) => contexts.isEmpty);
  }

  bool isListening(int contextId, String event) =>
      _listeners[event]?.containsKey(contextId) ?? false;

  /// The contexts listening for [event].
  Iterable<int> contextsFor(String event) =>
      (_listeners[event]?.keys ?? const <int>[]).toList();

  /// What [contextId] passed after the listener for [event], if it listens.
  List<Object?>? argumentsOf(String event, int contextId) =>
      _listeners[event]?[contextId];
}
