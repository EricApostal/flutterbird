import 'dart:async';

import 'json.dart';
import 'rdp_client.dart';
import 'rdp_transport.dart';

/// A tab, as the server knows it.
class DevToolsTabInfo {
  const DevToolsTabInfo({
    required this.actor,
    required this.browserId,
    required this.title,
    required this.url,
  });

  factory DevToolsTabInfo.parse(Map<String, Object?> json) => DevToolsTabInfo(
    actor: json.str('actor'),
    browserId: json.integer('browserId'),
    title: json.str('title'),
    url: json.str('url'),
  );

  final String actor;
  final int browserId;
  final String title;
  final String url;
}

/// The one connection to the DevTools server. The server takes a single client,
/// so every open toolbox shares this.
class DevToolsConnection {
  DevToolsConnection._(this.client) {
    client.events.listen(_dispatch);
  }

  /// For a server that is already listening on this machine.
  static Future<DevToolsConnection> open(int port) async {
    final client = await RdpClient.connect('127.0.0.1', port);
    return attach(client);
  }

  static Future<DevToolsConnection> attach(RdpClient client) async {
    final connection = DevToolsConnection._(client);
    try {
      await client.greeting.timeout(const Duration(seconds: 5));
      await client.request('root', 'getRoot');
    } catch (_) {
      await client.close();
      rethrow;
    }
    return connection;
  }

  /// Opens a connection over [channel], for tests.
  static Future<DevToolsConnection> over(RdpChannel channel) =>
      attach(RdpClient(channel));

  final RdpClient client;
  final Map<String, void Function(RdpPacket)> _handlers = {};

  Future<void> get done => client.done;
  bool get isClosed => client.isClosed;

  Future<RdpPacket> request(
    String actor,
    String type, [
    Map<String, Object?> parameters = const {},
    Duration timeout = RdpClient.defaultTimeout,
  ]) => client.request(actor, type, parameters, timeout);

  void notify(
    String actor,
    String type, [
    Map<String, Object?> parameters = const {},
  ]) => client.notify(actor, type, parameters);

  /// Sends the events of [actor] to [handler], until the returned function is
  /// called.
  void Function() listen(String actor, void Function(RdpPacket) handler) {
    _handlers[actor] = handler;
    return () {
      if (_handlers[actor] == handler) _handlers.remove(actor);
    };
  }

  void _dispatch(RdpPacket packet) {
    final from = packet['from'];
    if (from is String) _handlers[from]?.call(packet);
  }

  /// The tab the browser numbers [browserId], or null if it has none.
  Future<DevToolsTabInfo?> tab(int browserId) async {
    final response = await request('root', 'getTab', {'browserId': browserId});
    final tab = response.mapOrNull('tab');
    return tab == null ? null : DevToolsTabInfo.parse(tab);
  }

  Future<List<DevToolsTabInfo>> listTabs() async {
    final response = await request('root', 'listTabs');
    return response.maps('tabs').map(DevToolsTabInfo.parse).toList();
  }

  Future<void> close() => client.close();
}
