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
//
// Architecture mirrors Ladybird's own Qt frontend exactly: engine.confirm_
// fullscreen_state() (Qt: view().set_is_fullscreen()) is called from exactly
// one place — the real OS window-state-change confirmation
// (onWindowEnterFullScreen/onWindowLeaveFullScreen here; Qt's
// changeEvent(QEvent::WindowStateChange)) — never eagerly from the "please
// enter/exit" request handlers. Confirming eagerly races the viewport
// updates Flutter's own window-resize handling sends as a side effect of
// that same transition; whichever reaches the engine last wins, and losing
// that race is what silently (and permanently, since it desyncs the
// engine's internal fullscreen flag) broke fullscreen after one cycle.
@Riverpod(keepAlive: true)
class BrowserFullscreenModeController extends _$BrowserFullscreenModeController
    with WindowListener {
  // The tab whose fullscreen request is currently active. Set as soon as we
  // start a transition, but only *cleared* once that transition is actually
  // confirmed (by the OS, on desktop) — see onWindowEnterFullScreen/
  // onWindowLeaveFullScreen.
  LadybirdController? _activeController;

  // Set right before we ask the OS to leave fullscreen on the user's behalf
  // (our overlay button, a back gesture), so the leave-fullscreen
  // confirmation knows it should *also* tell the page to exit. Left false
  // when the page already initiated the exit itself (we're just reacting to
  // its request), since telling it to exit again would be redundant —
  // mirrors Qt's FullscreenMode::exit(ExitInitiatedBy).
  bool _exitInitiatedByUi = false;

  @override
  bool build() {
    if (_isDesktopPlatform) {
      windowManager.addListener(this);
      ref.onDispose(() => windowManager.removeListener(this));
    }
    return false;
  }

  // The page asked to enter/exit fullscreen. Only *initiates* our own
  // platform-level transition here. On desktop, confirming back to the
  // engine happens from onWindowEnterFullScreen/onWindowLeaveFullScreen once
  // the OS genuinely confirms the transition. Mobile has no separate
  // OS-level window-state-change signal to wait for, so it confirms directly
  // once our own await completes.
  Future<void> syncFromEngine(
    LadybirdController controller,
    bool isFullscreen,
  ) async {
    print('[Fullscreen] syncFromEngine isFullscreen=$isFullscreen (was $state)');
    if (state == isFullscreen) return;
    state = isFullscreen;
    if (isFullscreen) {
      _activeController = controller;
    }
    _exitInitiatedByUi = false;
    await _applyPlatformFullscreen(isFullscreen);

    if (_isMobilePlatform) {
      if (isFullscreen) {
        controller.confirmFullscreenState(true);
      } else {
        _activeController = null;
        controller.confirmFullscreenState(false);
      }
    }
  }

  // UI-initiated exit (our overlay button, a platform back gesture).
  Future<void> exitFromUi() async {
    print('[Fullscreen] exitFromUi (state=$state)');
    final controller = _activeController;
    if (!state) {
      controller?.requestExitFullscreen();
      return;
    }

    state = false;
    _exitInitiatedByUi = true;
    await _applyPlatformFullscreen(false);

    if (_isMobilePlatform) {
      _activeController = null;
      _exitInitiatedByUi = false;
      controller?.confirmFullscreenState(false);
      controller?.requestExitFullscreen();
    }
    // Desktop: onWindowLeaveFullScreen() does the confirm + request once the
    // OS genuinely confirms the window left fullscreen.
  }

  Future<void> _applyPlatformFullscreen(bool enabled) async {
    print('[Fullscreen] _applyPlatformFullscreen enabled=$enabled');
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

  // The OS confirmed the window actually entered fullscreen — whether that
  // was because the page asked (syncFromEngine) or anything else. This is
  // the single point that tells the engine the transition genuinely
  // happened, mirroring Qt's changeEvent(QEvent::WindowStateChange).
  @override
  void onWindowEnterFullScreen() {
    print('[Fullscreen] onWindowEnterFullScreen (activeController=${_activeController != null})');
    state = true;
    _activeController?.confirmFullscreenState(true);
  }

  // The OS confirmed the window actually left fullscreen — whether that was
  // the page exiting (syncFromEngine), our own button/back gesture
  // (exitFromUi), or the OS itself (e.g. macOS's green traffic-light
  // button). Single point that confirms the settled state to the engine.
  @override
  void onWindowLeaveFullScreen() {
    print(
      '[Fullscreen] onWindowLeaveFullScreen (activeController='
      '${_activeController != null}, initiatedByUi=$_exitInitiatedByUi)',
    );
    state = false;
    final controller = _activeController;
    _activeController = null;
    final initiatedByUi = _exitInitiatedByUi;
    _exitInitiatedByUi = false;

    if (controller == null) return;
    controller.confirmFullscreenState(false);
    if (initiatedByUi) {
      controller.requestExitFullscreen();
    }
  }
}
