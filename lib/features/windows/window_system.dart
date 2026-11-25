import 'package:bird_core/bird_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// What the browser needs from the windows it is shown in.
///
/// macOS gives every browser window a window of its own (see
/// `macos/mac_window_system.dart`). Other desktops have the one window they
/// always had, and a phone has no windows to speak of. Everything above this
/// works the same on all three, and asks [supportsMultipleWindows] before
/// offering what only the first can do.
///
/// Coordinates are those of `package:bird_window`: global, in logical points,
/// y down.
abstract class WindowSystem {
  bool get supportsMultipleWindows;

  /// Whether [windowId] is the one the keyboard is going to.
  bool isKeyWindow(int windowId);

  final KeyClaims _keyClaims = KeyClaims();

  /// Whether [windowId] is to act on a keyboard shortcut. Every window's
  /// keyboard handler hears every [event]; this says yes to one of them, once.
  bool claimShortcut(int windowId, Object event) =>
      _keyClaims.claim(event, isKeyWindow: () => isKeyWindow(windowId));

  /// Brings a window to the front and gives it the keyboard.
  void raise(int windowId) {}

  void setTitle(int windowId, String title) {}

  /// Moves the window with the mouse drag that is in progress.
  void startWindowDrag(int windowId) {}

  /// What double clicking a title bar does.
  void toggleMaximize(int windowId) {}

  bool isFullscreen(int windowId) => false;

  /// Asks for a window to go into or out of full screen. It takes a while:
  /// the listeners are told when it is done.
  Future<void> setFullscreen(int windowId, bool fullscreen) async {}

  /// Calls [listener] each time [windowId] has finished entering or leaving
  /// full screen. Returns what stops it.
  void Function() addFullscreenListener(
    int windowId,
    void Function(bool isFullscreen) listener,
  ) => () {};

  // ------------------------------------------------------------ where windows are

  ScreenRect? frameOf(int windowId) => null;

  /// Where the top left of what Flutter draws in a window is on screen.
  ScreenPoint contentOriginOf(int windowId) => ScreenPoint.zero;

  /// The usable area of the screen at [point].
  ScreenRect visibleScreenAt(ScreenPoint point) =>
      const ScreenRect(-100000, -100000, 200000, 200000);

  /// Where a window that is about to be added to the session should appear.
  void prepareWindow(int windowId, ScreenRect frame) {}

  void moveWindow(int windowId, ScreenPoint topLeft) {}

  /// Hides a window while keeping it alive.
  void setParked(int windowId, bool parked) {}

  /// The frontmost of the app's windows at [point], leaving out [ignoring], or
  /// null if there is none or another app's window is in front there.
  int? windowAt(ScreenPoint point, Set<int> ignoring);

  /// Where the mouse is, wherever it is, or null on a platform that only hears
  /// of it through the events of the window it is in.
  ScreenPoint? cursorPosition() => null;

  /// Whether the primary mouse button is down. Only asked where
  /// [cursorPosition] answers.
  bool primaryButtonDown() => false;
}

/// A phone, where the app is the screen.
class NoWindowSystem extends WindowSystem {
  @override
  bool get supportsMultipleWindows => false;

  @override
  bool isKeyWindow(int windowId) => true;

  @override
  int? windowAt(ScreenPoint point, Set<int> ignoring) => null;
}

final windowSystemProvider = Provider<WindowSystem>(
  (ref) => throw StateError('main() has to provide the window system'),
);
