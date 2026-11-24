import 'api.dart';
import 'extension_host.dart';
import 'extension_transport.dart';

/// `browser.runtime`, the parts that need the browser: messaging and ports.
class RuntimeApi extends ApiNamespace {
  @override
  String get name => 'runtime';

  @override
  String? get requiredPermission => null;

  @override
  Future<Object?> call(ApiCall call) async {
    switch (call.method) {
      case 'sendMessage':
        return _sendMessage(call);
      case 'connect':
        return _connect(call);
      case 'openOptionsPage':
        return _openOptionsPage(call);
      case 'reload':
        await call.host.reloadExtension(call.extension);
        return null;
      default:
        throw ApiException('runtime.${call.method} is not supported');
    }
  }

  /// What an extension page that is sent a message or a connection learns
  /// about who sent it.
  static Map<String, Object?> senderFor(ExtensionHost host, ApiCall call) {
    final context = call.context;
    return {
      'id': call.extension.id,
      'url': context.url,
      if (context.kind == ExtensionContextKind.contentScript &&
          context.viewId != null)
        'tab':
            host.browser?.tab(context.viewId!)?.toJson(includeIdentity: true) ??
            {'id': context.viewId, 'url': context.url},
      'frameId': host.frameIdOf(context),
    };
  }

  /// The extension pages other than [sender] that listen for [event].
  static List<ExtensionContext> _pageListeners(ApiCall call, String event) {
    return call.host
        .listeners(call.extension.uuid, event)
        .where(
          (context) =>
              context.contextId != call.context.contextId &&
              context.kind == ExtensionContextKind.extensionPage,
        )
        .toList();
  }

  Future<Object?> _sendMessage(ApiCall call) {
    // A content script talks to the extension's own pages, which is where its
    // background code lives. A page talks to its other pages. Reaching a
    // content script takes tabs.sendMessage, which names the tab.
    final targets = _pageListeners(call, 'runtime.onMessage');
    if (targets.isEmpty) {
      throw ApiException(
        'Could not establish connection. Receiving end does not exist.',
      );
    }
    return call.host.deliverMessage(
      targets,
      call.arg(0),
      senderFor(call.host, call),
    );
  }

  Object? _connect(ApiCall call) {
    final portId = call.arg(0);
    final portName = call.arg(1);
    if (portId is! String) {
      throw ApiException('runtime.connect needs a port id');
    }

    final targets = _pageListeners(call, 'runtime.onConnect');
    if (targets.isEmpty) {
      throw ApiException(
        'Could not establish connection. Receiving end does not exist.',
      );
    }

    call.host.openPort(
      portId: portId,
      name: portName is String ? portName : '',
      opener: call.context,
      targets: targets,
      sender: senderFor(call.host, call),
    );
    return null;
  }

  Future<Object?> _openOptionsPage(ApiCall call) async {
    final browser = call.host.browser;
    final manifest = await call.host.manifestOf(call.extension);
    final options = manifest?.options;
    if (browser == null || options == null) {
      throw ApiException('This extension has no options page');
    }
    await browser.createTab(url: '${call.extension.origin}/${options.page}');
    return null;
  }
}
