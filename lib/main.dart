import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutterbird/features/frontend/abstraction/frontend_layer.dart';
import 'package:flutterbird/features/router/controller.dart';
import 'package:window_manager/window_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final isDesktop = Platform.isMacOS || Platform.isLinux || Platform.isWindows;

  if (isDesktop) {
    await windowManager.ensureInitialized();
    final usesCustomTitlebar = Platform.isMacOS || Platform.isWindows;
    const initialSize = Size(800, 600);
    final windowOptions = WindowOptions(
      minimumSize: initialSize,
      size: initialSize,
      center: true,
      titleBarStyle: usesCustomTitlebar
          ? TitleBarStyle.hidden
          : TitleBarStyle.normal,
      // Keep real native caption buttons when titlebar is hidden.
      windowButtonVisibility: usesCustomTitlebar,
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      if (usesCustomTitlebar) {
        await windowManager.setMovable(false);
      }
      await windowManager.show();
      await windowManager.focus();
    });
  }

  runApp(ProviderScope(child: const MainApp()));
}

class MainApp extends StatelessWidget {
  const MainApp({super.key});

  @override
  Widget build(BuildContext context) {
    final frontend = resolveFrontendLayer();

    return frontend.buildApp(
      routerConfig: routerController,
      appBuilder: (context, child) {
        return FrontendScope(
          layer: frontend,
          child: PopScope(
            canPop: false,
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
    );
  }
}
