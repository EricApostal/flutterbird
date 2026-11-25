import 'dart:async';

import 'api.dart';
import 'browser_bridge.dart';
import 'extension_host.dart';
import 'tabs_api.dart';

/// `browser.windows`, over the browser's own windows.
class WindowsApi extends ApiNamespace {
  StreamSubscription<WindowEvent>? _subscription;

  @override
  String get name => 'windows';

  @override
  void attach(ExtensionHost host) {
    _subscription = host.browser?.windowEvents.listen((event) {
      switch (event) {
        case WindowCreated(:final window):
          host.emitToAll('windows.onCreated', (_) => [window.toJson()]);
        case WindowRemoved(:final windowId):
          host.emitToAll('windows.onRemoved', (_) => [windowId]);
        case WindowFocusChanged(:final windowId):
          host.emitToAll('windows.onFocusChanged', (_) => [windowId]);
      }
    });
  }

  @override
  void detach() {
    unawaited(_subscription?.cancel());
    _subscription = null;
  }

  @override
  Future<Object?> call(ApiCall call) async {
    final browser = call.host.browser;
    if (browser == null) throw ApiException('Windows are not available');

    switch (call.method) {
      case 'get':
        return _present(
          call,
          browser,
          _require(call, browser, call.arg(0)),
          populate: _populate(call.arg(1)),
        );
      case 'getCurrent':
        return _present(
          call,
          browser,
          _require(call, browser, TabsApi.currentWindowOf(call, browser)),
          populate: _populate(call.arg(0)),
        );
      case 'getLastFocused':
        return _present(
          call,
          browser,
          _require(call, browser, browser.currentWindowId),
          populate: _populate(call.arg(0)),
        );
      case 'getAll':
        return [
          for (final window in browser.windows)
            _present(call, browser, window, populate: _populate(call.arg(0))),
        ];
      case 'create':
        return _create(call, browser);
      case 'update':
        final window = _require(call, browser, call.arg(0));
        final properties = call.arg(1);
        if (properties is Map && properties['focused'] == true) {
          await browser.focusWindow(window.id);
        }
        return _present(
          call,
          browser,
          _require(call, browser, window.id),
          populate: false,
        );
      case 'remove':
        await browser.closeWindow(_require(call, browser, call.arg(0)).id);
        return null;
      default:
        throw ApiException('windows.${call.method} is not supported');
    }
  }

  Future<Object?> _create(ApiCall call, BrowserBridge browser) async {
    final argument = call.arg(0);
    final properties = argument is Map ? argument : const {};
    final url = properties['url'];
    final urls = [
      for (final entry in url is List ? url : [url])
        if (entry is String) entry,
    ];
    int? size(String key) {
      final value = properties[key];
      return value is num ? value.round() : null;
    }

    final id = await browser.createWindow(
      url: urls.isEmpty ? null : urls.first,
      // The kinds of window with no tab strip.
      popup: const {
        'popup',
        'panel',
        'detached_panel',
      }.contains(properties['type']),
      width: size('width'),
      height: size('height'),
    );
    for (final extra in urls.skip(1)) {
      await browser.createTab(url: extra, active: false, windowId: id);
    }
    return _present(call, browser, _require(call, browser, id), populate: true);
  }

  BrowserWindowInfo _require(ApiCall call, BrowserBridge browser, Object? id) {
    // WINDOW_ID_CURRENT.
    final wanted = id == -2 ? TabsApi.currentWindowOf(call, browser) : id;
    for (final window in browser.windows) {
      if (window.id == wanted) return window;
    }
    throw ApiException('Invalid window ID: $id');
  }

  bool _populate(Object? info) => info is Map && info['populate'] == true;

  Map<String, Object?> _present(
    ApiCall call,
    BrowserBridge browser,
    BrowserWindowInfo window, {
    required bool populate,
  }) => {
    ...window.toJson(),
    if (populate)
      'tabs': [
        for (final tab in browser.tabs)
          if (tab.windowId == window.id) TabsApi.present(call.extension, tab),
      ],
  };
}
