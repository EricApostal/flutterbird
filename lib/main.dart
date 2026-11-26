import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bird_core/bird_core.dart';
import 'package:rubisco_browser/features/devtools/browser_devtools.dart';
import 'package:rubisco_browser/features/downloads/downloads_bootstrap.dart';
import 'package:rubisco_browser/features/extensions/app_browser_bridge.dart';
import 'package:rubisco_browser/features/router/controller.dart';
import 'package:rubisco_browser/features/theme/app_theme.dart';
import 'package:rubisco_browser/features/windows/browser_shell.dart';
import 'package:rubisco_browser/features/windows/legacy_window_system.dart';
import 'package:rubisco_browser/features/windows/macos/mac_devtools_windows.dart';
import 'package:rubisco_browser/features/windows/macos/mac_window_system.dart';
import 'package:rubisco_browser/features/windows/macos/multi_window_app.dart';
import 'package:rubisco_browser/features/windows/window_scope.dart';
import 'package:rubisco_browser/features/windows/window_system.dart';
import 'package:window_manager/window_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDownloads();

  // macOS gives each browser window a window of its own. Elsewhere the app is
  // one window, or the screen.
  if (Platform.isMacOS) {
    _runMultiWindow();
  } else {
    await _runSingleWindow();
  }
}

ProviderContainer _createContainer(WindowSystem windows) => ProviderContainer(
  overrides: [
    windowSystemProvider.overrideWithValue(windows),
    // Extensions run in the app's tabs and run their background pages
    // in views of their own.
    browserBridgeProvider.overrideWith((ref) => AppBrowserBridge(ref)),
  ],
);

void _runMultiWindow() {
  if (!windowingIsAvailable) {
    // The macOS runner makes no window of its own, so there is nothing to show
    // this in but the log.
    throw UnsupportedError(
      'Rubisco Browser needs Flutter\'s windowing feature on macOS. Use the master '
      'channel (puro flutter ...) with `flutter: config: enable-windowing: '
      'true` in pubspec.yaml.',
    );
  }

  final windows = MacWindowSystem();
  final container = _createContainer(windows);

  // The shell first: it listens for what pages do to tabs, and making its
  // first tab is what starts the engine.
  final shell = container.read(browserShellProvider);
  windows.onCloseRequested = shell.closeWindow;
  windows.pictureInPicture.onReturnToTab = (tabId) {
    shell.showTab(tabId);
    final window = shell.session.windowOfTab(tabId);
    if (window != null) windows.raise(window.id);
  };
  windows.start(container);

  // Extensions run for the life of the app, whichever windows come and go. The
  // provider is only built once.
  container.read(extensionServiceProvider);

  // From the start, so that pages offer "Inspect" before the tools are opened.
  final devTools = MacDevToolsWindows(container.read(devToolsProvider)!);

  runWidget(
    UncontrolledProviderScope(
      container: container,
      child: MultiWindowApp(system: windows, devTools: devTools),
    ),
  );
}

Future<void> _runSingleWindow() async {
  final isDesktop = Platform.isLinux || Platform.isWindows;

  if (isDesktop) {
    await windowManager.ensureInitialized();
    const initialSize = Size(800, 600);
    const windowOptions = WindowOptions(
      minimumSize: initialSize,
      size: initialSize,
      center: true,
      titleBarStyle: TitleBarStyle.hidden,
      // Keep real native caption buttons when titlebar is hidden.
      windowButtonVisibility: true,
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.setMovable(false);
      await windowManager.show();
      await windowManager.focus();
    });
  }

  final container = _createContainer(
    isDesktop ? SingleWindowSystem() : NoWindowSystem(),
  );

  runApp(
    UncontrolledProviderScope(container: container, child: const MainApp()),
  );
}

/// The app where it is one window: its tabs are routes.
class MainApp extends ConsumerStatefulWidget {
  const MainApp({super.key});

  @override
  ConsumerState<MainApp> createState() => _MainAppState();
}

class _MainAppState extends ConsumerState<MainApp> {
  late final int _windowId;

  @override
  void initState() {
    super.initState();
    // The shell starts listening to tabs, and makes the first one.
    final shell = ref.read(browserShellProvider);
    // From the start, so that pages offer "Inspect" before the tools are opened.
    ref.read(devToolsProvider);
    _windowId = ref.read(browserSessionProvider).windows.first.id;
    // Not while widgets are being built, when providers cannot change.
    WidgetsBinding.instance.addPostFrameCallback((_) => shell.keepOnlyWindow());
  }

  @override
  Widget build(BuildContext context) {
    return BrowserWindowScope(
      windowId: _windowId,
      child: MaterialApp.router(
        routerConfig: routerController,
        themeMode: ThemeMode.dark,
        darkTheme: birdDarkTheme(),
        theme: birdLightTheme(),
        builder: (context, child) {
          return PopScope(
            canPop: false,
            child: child ?? const SizedBox.shrink(),
          );
        },
      ),
    );
  }
}
