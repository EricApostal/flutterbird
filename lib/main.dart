import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutterbird/features/router/controller.dart';
import 'package:flutterbird/features/theme/base.dart';
import 'package:go_transitions/go_transitions.dart';
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
    final pageTransition = const PageTransitionsTheme(
      builders: {
        TargetPlatform.fuchsia: GoTransitions.none,
        TargetPlatform.iOS: GoTransitions.none,
        TargetPlatform.linux: GoTransitions.none,
        TargetPlatform.macOS: GoTransitions.none,
        TargetPlatform.windows: GoTransitions.none,
      },
    );

    return MaterialApp.router(
      routerConfig: routerController,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        pageTransitionsTheme: pageTransition,
        colorScheme: ColorScheme.fromSeed(
          brightness: Brightness.dark,
          seedColor: const Color.fromARGB(255, 35, 174, 255),
        ),
        textTheme: getBaseTextTheme(ThemeData.dark().textTheme),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      theme: ThemeData(
        pageTransitionsTheme: pageTransition,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color.fromARGB(255, 35, 141, 255),
        ),
        textTheme: getBaseTextTheme(ThemeData.light().textTheme),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      builder: (context, child) {
        return PopScope(canPop: false, child: child ?? const SizedBox.shrink());
      },
    );
  }
}
