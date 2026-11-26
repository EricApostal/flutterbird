// Flutter's windowing API is experimental and only exported from `src/`. This
// file and multi_window_app.dart are the only ones that use it, so that it is
// all there is to change when Flutter changes it.
// ignore_for_file: implementation_imports, invalid_use_of_internal_member

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show AppExitType, ViewFocusEvent, ViewFocusState;

import 'package:bird_core/bird_core.dart';
import 'package:bird_window/bird_window.dart';
import 'package:flutter/services.dart';
import 'package:flutter/src/foundation/_features.dart' show isWindowingEnabled;
import 'package:flutter/src/widgets/_window.dart';
import 'package:flutter/src/widgets/_window_macos.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rubisco_browser/features/windows/macos/mac_picture_in_picture.dart';
import 'package:rubisco_browser/features/windows/window_system.dart';

/// One browser window: Flutter's window and the `NSWindow` under it.
class MacBrowserWindow {
  MacBrowserWindow._(this.id, this.kind, this.controller, this.native);

  final int id;
  final BrowserWindowKind kind;
  final WindowController controller;
  final MacWindow native;
  late final MacFullScreenObserver _fullScreen;
  String? _title;
}

/// A real window for each window of the session, all of them equals.
///
/// The app has no window of its own: the macOS runner starts the engine with
/// none (see `AppDelegate.swift`), and this makes and destroys them as the
/// session changes. The app quits when the session has none left, whichever
/// went last.
class MacWindowSystem extends WindowSystem
    with ChangeNotifier, WidgetsBindingObserver {
  /// Called when the user asks to close a window, with its close button.
  late void Function(int windowId) onCloseRequested;

  /// The floating windows of Picture-in-Picture videos. They are not windows
  /// of the session: they hold no tabs, and none of them keeps the app running.
  late final MacPictureInPicture pictureInPicture = MacPictureInPicture(
    ownerFrame: (tabId) {
      final window = _session.windowOfTab(tabId);
      return window == null ? null : frameOf(window.id);
    },
  );

  ProviderContainer? _container;
  final Map<int, MacBrowserWindow> _windows = {};
  final Map<int, ScreenRect> _prepared = {};
  final Map<int, List<void Function(bool)>> _fullscreenListeners = {};
  bool _syncing = false;
  bool _syncAgain = false;
  bool _quitting = false;

  /// The windows to render, in the order they were made.
  List<MacBrowserWindow> get windows => List.unmodifiable(_windows.values);

  /// Makes the session's windows, and follows it from then on.
  void start(ProviderContainer container) {
    _container = container;
    WidgetsBinding.instance.addObserver(this);
    container.listen<BrowserSession>(browserSessionProvider, (_, _) => _sync());
    _sync();
    pictureInPicture.start();
  }

  BrowserSession get _session => _container!.read(browserSessionProvider);

  // ------------------------------------------------------------ following the session

  void _sync() {
    // Making a window calls into the engine, which can come back with events
    // that change the session before the window is done being made.
    if (_syncing) {
      _syncAgain = true;
      return;
    }
    _syncing = true;
    var changed = false;
    try {
      do {
        _syncAgain = false;
        final session = _session;

        for (final id in _windows.keys.toList()) {
          if (session.window(id) != null) continue;
          _retire(_windows.remove(id)!);
          changed = true;
        }
        for (final model in session.windows) {
          if (_windows.containsKey(model.id)) continue;
          _windows[model.id] = _create(model);
          changed = true;
        }
      } while (_syncAgain);
    } finally {
      _syncing = false;
    }

    if (changed) {
      notifyListeners();
      WidgetsBinding.instance.scheduleFrame();
    }
    if (_session.isEmpty) _quit();
  }

  ScreenRect _defaultFrame(BrowserWindowModel model) {
    final focused = _session.focusOrder
        .map((id) => _windows[id])
        .nonNulls
        .firstOrNull;
    final screen =
        focused?.native.visibleScreenFrame ??
        MacDesktop.screens().firstOrNull?.visibleFrame ??
        const ScreenRect(0, 0, 1440, 900);
    if (focused == null) return WindowPlacement.centered(screen);
    return WindowPlacement.cascaded(focused.native.frame, screen);
  }

  MacBrowserWindow _create(BrowserWindowModel model) {
    final wanted = _prepared.remove(model.id) ?? _defaultFrame(model);
    final isPopup = model.isPopup;

    // A popup keeps its title bar, which is outside what Flutter draws in.
    final titleBar = isPopup ? 28.0 : 0.0;
    final minimum = isPopup
        ? WindowPlacement.minimumPopupSize
        : WindowPlacement.minimumSize;
    final contentSize = Size(
      math.max(wanted.width, minimum.width),
      math.max(wanted.height - titleBar, minimum.height),
    );

    final controller = WindowController(
      size: contentSize,
      constraints: BoxConstraints(
        minWidth: minimum.width,
        minHeight: minimum.height,
      ),
      title: 'Rubisco Browser',
      delegate: _MacWindowDelegate(this, model.id),
    );
    final native = MacWindow(
      (controller as WindowControllerMacOS).windowHandle,
    );

    // The window shows itself once Flutter has drawn into it, so it is placed
    // and dressed before anyone sees it.
    if (!isPopup) native.useHiddenTitleBar();
    native.frame = ScreenRect(
      wanted.left,
      wanted.top,
      contentSize.width,
      contentSize.height + titleBar,
    );

    final window = MacBrowserWindow._(model.id, model.kind, controller, native);
    window._fullScreen = MacFullScreenObserver(
      native.handle,
      (fullscreen) => _reportFullscreen(model.id, fullscreen),
    );
    return window;
  }

  /// Takes a window off screen at once, and destroys it once Flutter has
  /// stopped drawing into it.
  void _retire(MacBrowserWindow window) {
    _fullscreenListeners.remove(window.id);
    window._fullScreen.dispose();
    // A full screen window is left for destroying to close: ordering it out
    // first can leave its space behind, empty.
    if (!window.controller.isDestroyed && !window.native.isFullScreen) {
      window.native.orderOut();
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      // Not from inside the frame, and not at once: a window that closes as a
      // drag ends still has the mouse going up to hear about.
      Timer(const Duration(milliseconds: 150), () {
        window.controller.destroy();
        window.controller.dispose();
      });
    });
  }

  void _quit() {
    if (_quitting) return;
    _quitting = true;
    unawaited(ServicesBinding.instance.exitApplication(AppExitType.required));
  }

  // The platform destroyed a window without being asked to.
  void _destroyedByPlatform(int windowId) {
    if (!_windows.containsKey(windowId) || _quitting) return;
    onCloseRequested(windowId);
  }

  // ------------------------------------------------------------ focus

  @override
  void didChangeViewFocus(ViewFocusEvent event) {
    if (event.state != ViewFocusState.focused) return;
    for (final window in _windows.values) {
      if (window.controller.isDestroyed) continue;
      if (window.controller.rootView.viewId != event.viewId) continue;
      final session = _session;
      _container!
          .read(browserSessionProvider.notifier)
          .commit(session.focusWindow(window.id));
      return;
    }
  }

  // ------------------------------------------------------------ WindowSystem

  /// The window, making it first if the session has it and this does not yet.
  MacBrowserWindow? _window(int windowId) {
    if (!_windows.containsKey(windowId) && _session.window(windowId) != null) {
      _sync();
    }
    final window = _windows[windowId];
    return window == null || window.controller.isDestroyed ? null : window;
  }

  @override
  bool get supportsMultipleWindows => true;

  @override
  bool isKeyWindow(int windowId) => _window(windowId)?.native.isKey ?? false;

  @override
  void raise(int windowId) {
    final native = _window(windowId)?.native;
    // A new window brings itself forward when it first draws. Doing it sooner
    // would show it empty.
    if (native != null && native.isVisible) native.makeKeyAndOrderFront();
  }

  @override
  void setTitle(int windowId, String title) {
    final window = _window(windowId);
    if (window == null || window._title == title) return;
    window._title = title;
    window.controller.setTitle(title);
  }

  @override
  void startWindowDrag(int windowId) => _window(windowId)?.native.startDrag();

  @override
  void toggleMaximize(int windowId) => _window(windowId)?.native.zoom();

  @override
  bool isFullscreen(int windowId) =>
      _window(windowId)?.native.isFullScreen ?? false;

  @override
  Future<void> setFullscreen(int windowId, bool fullscreen) async {
    final window = _window(windowId);
    if (window == null) return;
    if (window.native.isFullScreen == fullscreen) {
      // Nothing is going to change, so nothing is going to say it did.
      scheduleMicrotask(() => _reportFullscreen(windowId, fullscreen));
      return;
    }
    window.controller.setFullscreen(fullscreen);
  }

  @override
  void Function() addFullscreenListener(
    int windowId,
    void Function(bool isFullscreen) listener,
  ) {
    final listeners = _fullscreenListeners.putIfAbsent(windowId, () => []);
    listeners.add(listener);
    return () => listeners.remove(listener);
  }

  void _reportFullscreen(int windowId, bool fullscreen) {
    for (final listener in _fullscreenListeners[windowId]?.toList() ?? []) {
      listener(fullscreen);
    }
  }

  @override
  ScreenRect? frameOf(int windowId) => _window(windowId)?.native.frame;

  @override
  ScreenPoint contentOriginOf(int windowId) =>
      _window(windowId)?.native.contentRect.topLeft ?? ScreenPoint.zero;

  @override
  ScreenRect visibleScreenAt(ScreenPoint point) =>
      MacDesktop.visibleFrameAt(point);

  @override
  void prepareWindow(int windowId, ScreenRect frame) {
    _prepared[windowId] = frame;
  }

  @override
  void moveWindow(int windowId, ScreenPoint topLeft) =>
      _window(windowId)?.native.moveTo(topLeft);

  @override
  void setParked(int windowId, bool parked) =>
      _window(windowId)?.native.setParked(parked);

  @override
  int? windowAt(ScreenPoint point, Set<int> ignoring) {
    var below = 0;
    // Each round looks under the window found by the last one.
    for (var i = 0; i < 16; i++) {
      final number = MacDesktop.windowNumberAt(point, below: below);
      if (number <= 0) return null;
      final id = _idOfNumber(number);
      // Another app's window is in the way.
      if (id == null) return null;
      if (!ignoring.contains(id)) return id;
      below = number;
    }
    return null;
  }

  /// Which window has the window server's [number]. Asked each time: a window
  /// has none to speak of until it has been on screen.
  int? _idOfNumber(int number) {
    for (final window in _windows.values) {
      if (window.controller.isDestroyed) continue;
      if (window.native.windowNumber == number) return window.id;
    }
    return null;
  }

  @override
  ScreenPoint cursorPosition() => MacDesktop.cursorPosition();

  @override
  bool primaryButtonDown() => MacDesktop.primaryButtonDown();
}

class _MacWindowDelegate with WindowControllerDelegate {
  _MacWindowDelegate(this._system, this._windowId);

  final MacWindowSystem _system;
  final int _windowId;

  // The default destroys the window on the spot. The session decides instead,
  // and the window goes when it leaves the session.
  @override
  void onWindowCloseRequested(WindowController controller) =>
      _system.onCloseRequested(_windowId);

  @override
  void onWindowDestroyed() => _system._destroyedByPlatform(_windowId);
}

/// Whether this build can make windows. It cannot without Flutter's windowing
/// feature, which `pubspec.yaml` turns on and the master channel provides.
bool get windowingIsAvailable => isWindowingEnabled;
