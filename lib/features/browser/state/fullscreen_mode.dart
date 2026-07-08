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
    print('[Fullscreen] syncFromEngine isFullscreen=$isFullscreen (was $state)');
    if (state == isFullscreen) return;
    state = isFullscreen;
    _activeController = isFullscreen ? controller : null;
    await _applyPlatformFullscreen(isFullscreen);
  }

  // UI-initiated exit (our overlay button, a platform back gesture). Unlike
  // [syncFromEngine], this restores the app's own chrome/window immediately
  // instead of waiting for the engine to confirm the page actually left
  // fullscreen — Ladybird's own native frontends do the same (see Qt's
  // FullscreenMode::exit, which always restores the browser window and only
  // *additionally* asks the page to exit fullscreen as a best-effort side
  // effect). This matters because the DOM Fullscreen API's confirmation
  // round-trip can be slow or, if it never lands, would otherwise leave the
  // whole app stuck looking fullscreen with no way out.
  Future<void> exitFromUi() async {
    print('[Fullscreen] exitFromUi (state=$state)');
    final controller = _activeController;
    _activeController = null;
    controller?.requestExitFullscreen();
    if (!state) return;
    state = false;
    await _applyPlatformFullscreen(false);
  }

  Future<void> _applyPlatformFullscreen(bool enabled) async {
    print('[Fullscreen] _applyPlatformFullscreen enabled=$enabled');
    if (_isDesktopPlatform) {
      await windowManager.setFullScreen(enabled);
      print(
        '[Fullscreen] windowManager.setFullScreen($enabled) completed; '
        'isFullScreen=${await windowManager.isFullScreen()}',
      );
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
    print('[Fullscreen] onWindowLeaveFullScreen (state=$state)');
    if (!state) return;
    state = false;
    final controller = _activeController;
    _activeController = null;
    controller?.requestExitFullscreen();
  }

  @override
  void onWindowEnterFullScreen() {
    print('[Fullscreen] onWindowEnterFullScreen');
    state = true;
  }
}
