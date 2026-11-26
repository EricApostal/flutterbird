import 'dart:async';
import 'dart:collection';

import 'rdp_transport.dart';

/// An actor said no.
class RdpError implements Exception {
  const RdpError(this.actor, this.error, [this.message = '']);

  final String actor;

  /// The protocol's name for what went wrong, such as `unknownActor`.
  final String error;
  final String message;

  bool get isUnknownActor => error == 'unknownActor';
  bool get isTimeout => error == 'timeout';
  bool get isClosed => error == 'connectionClosed';

  @override
  String toString() => 'RdpError($actor, $error: $message)';
}

class _Pending {
  _Pending(this.actor, this.type);
  final String actor;
  final String type;
  final Completer<RdpPacket> completer = Completer<RdpPacket>();
  Timer? timer;
}

/// Speaks to the actors of a DevTools server.
///
/// The protocol numbers nothing: an actor answers its requests in the order it
/// got them, and anything else it sends is an event. Events are told apart by
/// their `type`, as an actor's answers either have none or have one that no
/// event uses.
class RdpClient {
  RdpClient(this._channel) {
    _channel.packets.listen(
      _onPacket,
      onError: (Object _) => _onClosed(),
      onDone: _onClosed,
    );
  }

  static Future<RdpClient> connect(String host, int port) async =>
      RdpClient(await RdpSocketChannel.connect(host, port));

  static const Duration defaultTimeout = Duration(seconds: 15);

  static const Set<String> _eventTypes = {
    'tabListChanged',
    'target-available-form',
    'target-destroyed-form',
    'frameUpdate',
    'resources-available-array',
    'resources-updated-array',
    'resources-destroyed-array',
    'evaluationResult',
    'inspectObject',
    'newMutations',
    'root-available',
    'root-destroyed',
    'pickerNodeHovered',
    'pickerNodePicked',
    'pickerNodePreviewed',
    'pickerNodeCanceled',
    'storesUpdate',
    'storesCleared',
    'init',
    'canBeDisabledChange',
  };

  static final RegExp _unknownActor = RegExp(r"^Unknown actor: '(.*)'$");

  final RdpChannel _channel;
  final Map<String, Queue<_Pending>> _pending = {};
  final StreamController<RdpPacket> _events =
      StreamController<RdpPacket>.broadcast(sync: true);
  final Completer<RdpPacket> _greeting = Completer<RdpPacket>();
  final Completer<void> _done = Completer<void>();

  /// What the server says unprompted, in the order it says it.
  Stream<RdpPacket> get events => _events.stream;

  /// What the root actor says of itself when a client arrives.
  Future<RdpPacket> get greeting => _greeting.future;

  /// Completes when the connection is gone, whichever end closed it.
  Future<void> get done => _done.future;

  bool get isClosed => _done.isCompleted;

  /// Sends [type] to [actor] and returns its answer. Fails with an [RdpError].
  Future<RdpPacket> request(
    String actor,
    String type, [
    Map<String, Object?> parameters = const {},
    Duration timeout = defaultTimeout,
  ]) {
    if (isClosed) {
      return Future.error(RdpError(actor, 'connectionClosed'));
    }
    final pending = _Pending(actor, type);
    _pending.putIfAbsent(actor, Queue<_Pending>.new).add(pending);
    // A request that has timed out keeps its place in the queue: should the
    // answer come after all, it must not be taken for the next request's.
    pending.timer = Timer(timeout, () {
      if (!pending.completer.isCompleted) {
        pending.completer.completeError(
          RdpError(actor, 'timeout', 'No answer to $type'),
        );
      }
    });
    _channel.send({'to': actor, 'type': type, ...parameters});
    return pending.completer.future;
  }

  /// A request whose answer, and failure, do not matter.
  void notify(
    String actor,
    String type, [
    Map<String, Object?> parameters = const {},
  ]) {
    request(actor, type, parameters).ignore();
  }

  void _onPacket(RdpPacket packet) {
    final from = packet['from'];
    if (from is! String) return;

    if (!_greeting.isCompleted &&
        from == 'root' &&
        packet['applicationType'] != null) {
      _greeting.complete(packet);
      return;
    }

    // The root actor answers for actors that do not exist (any more).
    if (from == 'root' && packet['error'] == 'unknownActor') {
      final message = packet['message'];
      final match = message is String
          ? _unknownActor.firstMatch(message)
          : null;
      if (match != null) {
        final missing = match.group(1)!;
        if (_takePending(missing) case final pending?) {
          _fail(pending, 'unknownActor', message as String);
          return;
        }
      }
    }

    final type = packet['type'];
    if (type is String && _eventTypes.contains(type)) {
      _events.add(packet);
      return;
    }

    final pending = _takePending(from);
    if (pending == null) {
      _events.add(packet);
      return;
    }
    final error = packet['error'];
    // A page error is a resource, not a failed request, so only a string says
    // that the request failed.
    if (error is String) {
      _fail(pending, error, packet['message']?.toString() ?? '');
    } else {
      pending.timer?.cancel();
      if (!pending.completer.isCompleted) pending.completer.complete(packet);
    }
  }

  _Pending? _takePending(String actor) {
    final queue = _pending[actor];
    if (queue == null || queue.isEmpty) return null;
    final pending = queue.removeFirst();
    if (queue.isEmpty) _pending.remove(actor);
    return pending;
  }

  void _fail(_Pending pending, String error, String message) {
    pending.timer?.cancel();
    if (!pending.completer.isCompleted) {
      pending.completer.completeError(RdpError(pending.actor, error, message));
    }
  }

  void _onClosed() {
    if (_done.isCompleted) return;
    _done.complete();
    final waiting = [for (final queue in _pending.values) ...queue];
    _pending.clear();
    for (final pending in waiting) {
      _fail(pending, 'connectionClosed', 'The connection closed');
    }
    if (!_greeting.isCompleted) {
      _greeting.future.ignore();
      _greeting.completeError(const RdpError('root', 'connectionClosed'));
    }
    unawaited(_events.close());
  }

  Future<void> close() async {
    await _channel.close();
    _onClosed();
  }
}
