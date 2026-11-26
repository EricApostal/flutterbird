import 'package:bird_core/bird_core.dart';
import 'package:rubisco_browser/features/windows/window_system.dart';
import 'package:window_manager/window_manager.dart';

/// The single window of a desktop that does not have several here yet (Linux
/// and Windows), through `package:window_manager`.
class SingleWindowSystem extends WindowSystem with WindowListener {
  SingleWindowSystem() {
    windowManager.addListener(this);
  }

  final Map<int, List<void Function(bool)>> _fullscreenListeners = {};
  bool _isFullscreen = false;

  @override
  bool get supportsMultipleWindows => false;

  @override
  bool isKeyWindow(int windowId) => true;

  @override
  void startWindowDrag(int windowId) => windowManager.startDragging();

  @override
  void toggleMaximize(int windowId) async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
  }

  @override
  bool isFullscreen(int windowId) => _isFullscreen;

  @override
  Future<void> setFullscreen(int windowId, bool fullscreen) =>
      windowManager.setFullScreen(fullscreen);

  @override
  void Function() addFullscreenListener(
    int windowId,
    void Function(bool isFullscreen) listener,
  ) {
    final listeners = _fullscreenListeners.putIfAbsent(windowId, () => []);
    listeners.add(listener);
    return () => listeners.remove(listener);
  }

  void _report(bool fullscreen) {
    _isFullscreen = fullscreen;
    for (final listeners in _fullscreenListeners.values) {
      for (final listener in listeners.toList()) {
        listener(fullscreen);
      }
    }
  }

  @override
  void onWindowEnterFullScreen() => _report(true);

  @override
  void onWindowLeaveFullScreen() => _report(false);

  @override
  int? windowAt(ScreenPoint point, Set<int> ignoring) => null;
}
