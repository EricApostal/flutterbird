// ignore_for_file: invalid_use_of_internal_member

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutterbird/features/router/controller.dart';
import 'package:window_manager/window_manager.dart' as wm;

import 'package:flutter/src/widgets/_window.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final isDesktop = Platform.isMacOS || Platform.isLinux || Platform.isWindows;

  if (isDesktop) {
    await wm.windowManager.ensureInitialized();
    final usesCustomTitlebar = Platform.isMacOS || Platform.isWindows;
    const initialSize = Size(800, 600);
    final windowOptions = wm.WindowOptions(
      minimumSize: initialSize,
      size: initialSize,
      center: true,
      titleBarStyle: usesCustomTitlebar
          ? wm.TitleBarStyle.hidden
          : wm.TitleBarStyle.normal,
      // Keep real native caption buttons when titlebar is hidden.
      windowButtonVisibility: usesCustomTitlebar,
    );

    await wm.windowManager.waitUntilReadyToShow(windowOptions, () async {
      if (usesCustomTitlebar) {
        await wm.windowManager.setMovable(false);
      }
      await wm.windowManager.show();
      await wm.windowManager.focus();
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
    return MaterialApp.router(
      routerConfig: routerController,
      builder: (context, child) {
        final content = PopScope(
          canPop: false,
          child: child ?? const SizedBox.shrink(),
        );

        if (Platform.isLinux) {
          return WindowManager(child: content);
        }

        return content;
      },
      themeMode: .dark,
      darkTheme: ThemeData(
        colorScheme: .fromSeed(
          brightness: .dark,
          seedColor: Color.fromARGB(255, 35, 174, 255),
        ),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      theme: ThemeData(
        colorScheme: .fromSeed(seedColor: Color.fromARGB(255, 35, 141, 255)),
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
    );
  }
}
