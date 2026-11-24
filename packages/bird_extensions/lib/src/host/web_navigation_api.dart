import 'api.dart';
import 'extension_host.dart';
import 'extension_transport.dart';

/// `browser.webNavigation`, reported from the documents extensions can see.
///
/// The engine tells the browser when a document of an extension's content
/// script starts, and the shim reports when it has parsed and loaded, so
/// navigations are known exactly where an extension has a content script on
/// the page. That is every page for an extension that runs everywhere, as
/// uBlock Origin does, and no page for one that does not.
class WebNavigationApi extends ApiNamespace implements ContextObserver {
  /// tab id -> frame id -> the document last reported there.
  final Map<int, Map<int, _Frame>> _frames = {};

  @override
  String get name => 'webNavigation';

  @override
  String? get requiredPermission => 'webNavigation';

  Map<String, Object?> _details(ExtensionHost host, ExtensionContext context) {
    final frameId = host.frameIdOf(context);
    return {
      'tabId': context.viewId,
      'frameId': frameId,
      'parentFrameId': context.isTopLevel ? -1 : 0,
      'url': context.url,
      'timeStamp': DateTime.now().millisecondsSinceEpoch.toDouble(),
      'processId': -1,
    };
  }

  @override
  void contextCreated(ExtensionHost host, ExtensionContext context) {
    final tabId = context.viewId;
    if (tabId == null || context.kind != ExtensionContextKind.contentScript) {
      return;
    }

    (_frames[tabId] ??= {})[host.frameIdOf(context)] = _Frame(context);

    final details = _details(host, context);
    host.emit(context.extensionUuid, 'webNavigation.onBeforeNavigate', [
      details,
    ]);
    host.emit(context.extensionUuid, 'webNavigation.onCommitted', [
      {
        ...details,
        'transitionType': 'link',
        'transitionQualifiers': const <String>[],
      },
    ]);
  }

  @override
  void contextDestroyed(ExtensionHost host, ExtensionContext context) {
    final tabId = context.viewId;
    if (tabId == null) return;
    final frames = _frames[tabId];
    frames?.remove(host.frameIdOf(context));
    if (frames != null && frames.isEmpty) _frames.remove(tabId);
  }

  @override
  void documentEvent(
    ExtensionHost host,
    ExtensionContext context,
    String name,
  ) {
    if (context.viewId == null ||
        context.kind != ExtensionContextKind.contentScript) {
      return;
    }

    final event = switch (name) {
      'DOMContentLoaded' => 'webNavigation.onDOMContentLoaded',
      'load' => 'webNavigation.onCompleted',
      _ => null,
    };
    if (event != null) {
      host.emit(context.extensionUuid, event, [_details(host, context)]);
    }
  }

  @override
  Future<Object?> call(ApiCall call) async {
    switch (call.method) {
      case 'getAllFrames':
        final details = call.arg(0);
        final tabId = details is Map ? details['tabId'] : null;
        final frames = _framesOf(call, tabId);
        return [
          for (final frame in frames) _frameJson(call.host, frame.context),
        ];
      case 'getFrame':
        final details = call.arg(0);
        if (details is! Map) {
          throw ApiException('webNavigation.getFrame needs details');
        }
        for (final frame in _framesOf(call, details['tabId'])) {
          if (call.host.frameIdOf(frame.context) == details['frameId']) {
            return _frameJson(call.host, frame.context);
          }
        }
        return null;
      default:
        throw ApiException('webNavigation.${call.method} is not supported');
    }
  }

  Iterable<_Frame> _framesOf(ApiCall call, Object? tabId) {
    if (tabId is! int) throw ApiException('webNavigation needs a tabId');
    return (_frames[tabId]?.values ?? const <_Frame>[]).where(
      (frame) => frame.context.extensionUuid == call.extension.uuid,
    );
  }

  Map<String, Object?> _frameJson(
    ExtensionHost host,
    ExtensionContext context,
  ) => {
    'frameId': host.frameIdOf(context),
    'parentFrameId': context.isTopLevel ? -1 : 0,
    'url': context.url,
    'errorOccurred': false,
    'processId': -1,
  };
}

class _Frame {
  _Frame(this.context);

  final ExtensionContext context;
}
