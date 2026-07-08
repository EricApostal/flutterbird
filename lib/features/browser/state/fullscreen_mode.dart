import 'dart:io';

import 'package:flutter/services.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:window_manager/window_manager.dart';

part 'fullscreen_mode.g.dart';

bool get _isDesktopPlatform =>
    Platform.isMacOS || Platform.isLinux || Platform.isWindows;

bool get _isMobilePlatform => Platform.isAndroid || Platform.isIOS;

@Riverpod(keepAlive: true)
class BrowserFullscreenModeController extends _$BrowserFullscreenModeController
    with WindowListener {
  @override
  bool build() {
    if (_isDesktopPlatform) {
      windowManager.addListener(this);
      ref.onDispose(() => windowManager.removeListener(this));
    }
    return false;
  }

  Future<void> toggle() => state ? exit() : enter();

  Future<void> enter() async {
    if (state) return;
    state = true;
    await _applyPlatformFullscreen(true);
  }

  Future<void> exit() async {
    if (!state) return;
    state = false;
    await _applyPlatformFullscreen(false);
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
    }
  }

  // Keeps state in sync when fullscreen is toggled by the OS itself
  // (e.g. the macOS green traffic-light button or a system shortcut).
  @override
  void onWindowEnterFullScreen() => state = true;

  @override
  void onWindowLeaveFullScreen() => state = false;
}
