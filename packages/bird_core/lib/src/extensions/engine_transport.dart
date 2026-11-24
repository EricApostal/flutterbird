import 'package:bird_extensions/bird_extensions.dart';
import 'package:ladybird/ladybird.dart';

/// Carries the extension channel over the engine's C API.
class EngineExtensionTransport implements ExtensionTransport {
  EngineExtensionTransport(this._bridge);

  final ExtensionEngineBridge _bridge;

  @override
  Stream<ExtensionContext> get contextCreated => _bridge.contextCreated.map(
    (info) => ExtensionContext(
      contextId: info.contextId,
      viewId: info.viewId,
      extensionUuid: info.extensionUuid,
      url: info.url,
      isTopLevel: info.isTopLevel,
    ),
  );

  @override
  Stream<int> get contextDestroyed => _bridge.contextDestroyed;

  @override
  Stream<TransportMessage> get messages => _bridge.messages.map(
    (message) => TransportMessage(message.contextId, message.payload),
  );

  @override
  void setState(String json) => _bridge.setState(json);

  @override
  bool send(int contextId, String payload) => _bridge.send(contextId, payload);
}
