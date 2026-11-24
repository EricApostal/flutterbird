import 'api.dart';
import 'browser_bridge.dart';
import 'tabs_api.dart';

/// `browser.windows`. The browser has one window, and this describes it.
class WindowsApi extends ApiNamespace {
  @override
  String get name => 'windows';

  @override
  Future<Object?> call(ApiCall call) async {
    switch (call.method) {
      case 'get':
      case 'getCurrent':
      case 'getLastFocused':
        return _window(
          call,
          populate: _populate(call.arg(call.method == 'get' ? 1 : 0)),
        );
      case 'getAll':
        return [_window(call, populate: _populate(call.arg(0)))];
      case 'create':
        final properties = call.arg(0);
        final url = properties is Map ? properties['url'] : null;
        await call.host.browser?.createTab(url: url is String ? url : null);
        return _window(call, populate: false);
      case 'update':
        return _window(call, populate: false);
      case 'remove':
        return null;
      default:
        throw ApiException('windows.${call.method} is not supported');
    }
  }

  bool _populate(Object? info) => info is Map && info['populate'] == true;

  Map<String, Object?> _window(ApiCall call, {required bool populate}) {
    final tabs = call.host.browser?.tabs ?? const <BrowserTab>[];
    return {
      'id': 1,
      'focused': true,
      'incognito': false,
      'alwaysOnTop': false,
      'type': 'normal',
      'state': 'normal',
      'left': 0,
      'top': 0,
      'width': 1280,
      'height': 800,
      if (populate)
        'tabs': [for (final tab in tabs) TabsApi.present(call.extension, tab)],
    };
  }
}
