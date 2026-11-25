import 'dart:convert';

/// Which contexts have a listener for which event, and with what arguments.
///
/// A context's shim tells the browser when its first listener for an event
/// arrives and when its last leaves (see `createEvent` in the shim), so the
/// browser only does work for events someone is listening to.
class EventRegistry {
  // Every listener a context has for an event, each with what followed it.
  final Map<String, Map<int, List<List<Object?>>>> _listeners = {};

  /// Records that [contextId] listens for [event]. [arguments] are what
  /// followed the listener in `addListener`, such as a webRequest filter.
  void add(String event, int contextId, List<Object?> arguments) {
    ((_listeners[event] ??= {})[contextId] ??= []).add(arguments);
  }

  /// Forgets one listener of [contextId] for [event]: the one that was added
  /// with [arguments], or the last one when they are not given.
  void remove(String event, int contextId, [List<Object?>? arguments]) {
    final contexts = _listeners[event];
    final sets = contexts?[contextId];
    if (contexts == null || sets == null) return;

    if (arguments == null) {
      sets.removeLast();
    } else {
      final wanted = jsonEncode(arguments);
      final index = sets.indexWhere((set) => jsonEncode(set) == wanted);
      if (index >= 0) sets.removeAt(index);
    }

    if (sets.isEmpty) contexts.remove(contextId);
    if (contexts.isEmpty) _listeners.remove(event);
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

  /// What each of [contextId]'s listeners for [event] passed after the
  /// listener, in the order they were added.
  List<List<Object?>> argumentSetsOf(String event, int contextId) =>
      _listeners[event]?[contextId] ?? const [];
}
