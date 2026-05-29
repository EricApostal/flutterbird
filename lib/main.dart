import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutterbird/features/router/controller.dart';
import 'package:go_transitions/go_transitions.dart';
import 'package:window_manager/window_manager.dart';

import 'package:flutter/src/widgets/_window.dart';

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

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  @override
  Widget build(BuildContext context) {
    final pageTransition = const PageTransitionsTheme(
      builders: {
        // TargetPlatform.android: GoTransitions.material,
        TargetPlatform.fuchsia: GoTransitions.none,
        TargetPlatform.iOS: GoTransitions.none,
        TargetPlatform.linux: GoTransitions.none,
        TargetPlatform.macOS: GoTransitions.none,
        TargetPlatform.windows: GoTransitions.none,
      },
    );

    return MaterialApp.router(
      routerConfig: routerController,
      builder: (context, child) {
        return PopScope(canPop: false, child: child ?? const SizedBox.shrink());
      },
      themeMode: .dark,

      darkTheme: ThemeData(
        pageTransitionsTheme: pageTransition,
        colorScheme: .fromSeed(
          brightness: .dark,
          seedColor: Color.fromARGB(255, 35, 174, 255),
        ),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      theme: ThemeData(
        pageTransitionsTheme: pageTransition,
        colorScheme: .fromSeed(seedColor: Color.fromARGB(255, 35, 141, 255)),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}
