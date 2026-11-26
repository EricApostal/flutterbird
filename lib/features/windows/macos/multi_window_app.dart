// See mac_window_system.dart about the experimental API.
// ignore_for_file: implementation_imports, invalid_use_of_internal_member

import 'package:flutter/material.dart';
import 'package:flutter/src/widgets/_window.dart';
import 'package:rubisco_browser/features/theme/app_theme.dart';
import 'package:rubisco_browser/features/windows/desktop_window_home.dart';
import 'package:rubisco_browser/features/windows/macos/mac_picture_in_picture.dart';
import 'package:rubisco_browser/features/windows/macos/mac_window_system.dart';
import 'package:rubisco_browser/features/windows/window_scope.dart';

/// The root of the macOS app: not a window itself, but every window there is.
class MultiWindowApp extends StatelessWidget {
  const MultiWindowApp({required this.system, super.key});

  final MacWindowSystem system;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([system, system.pictureInPicture]),
      builder: (context, _) => ViewCollection(
        views: [
          for (final window in system.windows)
            Window(
              key: ValueKey(window.id),
              controller: window.controller,
              child: _BrowserWindowApp(windowId: window.id),
            ),
          for (final window in system.pictureInPicture.windows)
            Window(
              key: ValueKey('pip-${window.viewId}'),
              controller: window.controller,
              child: MaterialApp(
                debugShowCheckedModeBanner: false,
                theme: birdDarkTheme(),
                home: PictureInPictureView(window: window),
              ),
            ),
        ],
      ),
    );
  }
}

/// What one window holds. Each has a navigator and overlays of its own, so a
/// menu or a dialog opens in the window it was asked for in.
class _BrowserWindowApp extends StatelessWidget {
  const _BrowserWindowApp({required this.windowId});

  final int windowId;

  @override
  Widget build(BuildContext context) {
    return BrowserWindowScope(
      windowId: windowId,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        themeMode: ThemeMode.dark,
        darkTheme: birdDarkTheme(),
        theme: birdLightTheme(),
        home: const DesktopWindowHome(),
      ),
    );
  }
}
