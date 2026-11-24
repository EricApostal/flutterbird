/// A `runtime.Port` between one context and the contexts it connected to.
class PortRecord {
  PortRecord({
    required this.id,
    required this.name,
    required this.opener,
    required Iterable<int> peers,
  }) : peers = peers.toSet();

  final String id;
  final String name;

  /// The context that called `connect`.
  final int opener;

  /// The contexts that were handed the other end.
  final Set<int> peers;
}

/// Where a port message goes and what a closing port leaves behind.
class PortHub {
  final Map<String, PortRecord> _ports = {};

  PortRecord open({
    required String id,
    required String name,
    required int opener,
    required Iterable<int> peers,
  }) {
    final record = PortRecord(id: id, name: name, opener: opener, peers: peers);
    _ports[id] = record;
    return record;
  }

  PortRecord? operator [](String id) => _ports[id];

  /// The contexts a message that [from] posts on [portId] is for: the peers
  /// when the opener posts it, the opener when a peer does. Empty when [from]
  /// is not on the port.
  Iterable<int> destinations(String portId, int from) {
    final record = _ports[portId];
    if (record == null) return const [];
    if (from == record.opener) return record.peers.toList();
    if (record.peers.contains(from)) return [record.opener];
    return const [];
  }

  /// [from] closes its end. Returns the contexts to tell, and forgets the
  /// port. A peer leaving while others remain only removes that peer.
  Iterable<int> close(String portId, int from) {
    final record = _ports[portId];
    if (record == null) return const [];

    if (from == record.opener) {
      _ports.remove(portId);
      return record.peers.toList();
    }
    if (!record.peers.remove(from)) return const [];
    if (record.peers.isEmpty) {
      _ports.remove(portId);
      return [record.opener];
    }
    return const [];
  }

  /// A context is gone: every port it was on is closed. Returns, for each, the
  /// port and the contexts to tell.
  Map<String, Iterable<int>> dropContext(int contextId) {
    final affected = <String, Iterable<int>>{};
    for (final id in _ports.keys.toList()) {
      final record = _ports[id]!;
      if (record.opener != contextId && !record.peers.contains(contextId)) {
        continue;
      }
      affected[id] = close(id, contextId);
    }
    return affected;
  }
}
