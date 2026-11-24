/// What a context is: the kind decides who it may message.
enum ExtensionContextKind {
  /// A content script's isolated world in a web page.
  contentScript,

  /// A page of the extension itself: its background page, popup or options.
  extensionPage,
}

/// One extension's world in one document.
class ExtensionContext {
  const ExtensionContext({
    required this.contextId,
    required this.viewId,
    required this.extensionUuid,
    required this.url,
    required this.isTopLevel,
  });

  /// Unique across processes for as long as the context exists.
  final int contextId;

  /// The tab the document is in, or null when the app does not know it.
  final int? viewId;
  final String extensionUuid;
  final String url;
  final bool isTopLevel;

  ExtensionContextKind get kind => url.startsWith('moz-extension:')
      ? ExtensionContextKind.extensionPage
      : ExtensionContextKind.contentScript;
}

class TransportMessage {
  const TransportMessage(this.contextId, this.payload);

  final int contextId;
  final String payload;
}

/// The channel between the browser and the extension worlds that run in web
/// content processes. The engine's is a thin wrapper over its C API; a test
/// can supply its own.
abstract class ExtensionTransport {
  Stream<ExtensionContext> get contextCreated;
  Stream<int> get contextDestroyed;
  Stream<TransportMessage> get messages;

  /// Replaces the state every process holds (see EngineStateBuilder).
  void setState(String json);

  /// Sends [payload] to a context. False when it is gone.
  bool send(int contextId, String payload);
}
