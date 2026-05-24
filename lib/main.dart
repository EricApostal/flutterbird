import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutterbird/features/browser/components/window_anchor.dart';
import 'package:flutterbird/features/router/controller.dart';
import 'package:window_manager/window_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
    await windowManager.ensureInitialized();

    const windowOptions = WindowOptions(
      size: Size(1200, 820),
      minimumSize: Size(900, 650),
      titleBarStyle: TitleBarStyle.hidden,
    );

    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.setAsFrameless();
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
    return MaterialApp.router(
      routerConfig: routerController,
      builder: (context, child) {
        return BrowserWindowAnchor(child: child ?? const SizedBox.shrink());
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
