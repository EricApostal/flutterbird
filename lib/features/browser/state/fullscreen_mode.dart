import 'dart:io';

import 'package:flutter/services.dart';
import 'package:ladybird/ladybird.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:window_manager/window_manager.dart';

part 'fullscreen_mode.g.dart';

bool get _isDesktopPlatform =>
    Platform.isMacOS || Platform.isLinux || Platform.isWindows;

bool get _isMobilePlatform => Platform.isAndroid || Platform.isIOS;

// Reflects whether the page currently occupying the screen is showing a DOM
// Fullscreen API element (e.g. a <video>'s native fullscreen button, or
// `element.requestFullscreen()`). This is never toggled by the user directly
// — it only ever mirrors what the engine reports via
// LadybirdController.onFullscreenChange, so the DOM's fullscreen state and
// the app's chrome/window state can't drift apart.
@Riverpod(keepAlive: true)
class BrowserFullscreenModeController extends _$BrowserFullscreenModeController
    with WindowListener {
  // The tab whose fullscreen request is currently active, so a
  // platform-initiated exit (OS window control, Android back gesture) can
  // tell the engine to exit DOM fullscreen too, keeping both sides in sync.
  LadybirdController? _activeController;

  @override
  bool build() {
    if (_isDesktopPlatform) {
      windowManager.addListener(this);
      ref.onDispose(() => windowManager.removeListener(this));
    }
    return false;
  }

  Future<void> syncFromEngine(
    LadybirdController controller,
    bool isFullscreen,
  ) async {
    if (state == isFullscreen) return;
    state = isFullscreen;
    _activeController = isFullscreen ? controller : null;
    await _applyPlatformFullscreen(isFullscreen);
  }

  Future<void> _applyPlatformFullscreen(bool enabled) async {
    if (_isDesktopPlatform) {
      await windowManager.setFullScreen(enabled);
      return;
    }

    if (_isMobilePlatform) {
      await SystemChrome.setEnabledSystemUIMode(
        enabled ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      );
      // Mirrors how native mobile video players rotate into landscape when
      // going fullscreen (e.g. YouTube) and free up rotation again on exit.
      await SystemChrome.setPreferredOrientations(
        enabled
            ? const [
                DeviceOrientation.landscapeLeft,
                DeviceOrientation.landscapeRight,
              ]
            : const [],
      );
    }
  }

  // The window left fullscreen through the OS itself (e.g. the macOS green
  // traffic-light button, a system shortcut) rather than the page exiting.
  // Tell the engine so `document.fullscreenElement` etc. stay truthful.
  @override
  void onWindowLeaveFullScreen() {
    if (!state) return;
    state = false;
    final controller = _activeController;
    _activeController = null;
    controller?.requestExitFullscreen();
  }

  @override
  void onWindowEnterFullScreen() => state = true;
}
