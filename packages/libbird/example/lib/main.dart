import 'package:flutter/material.dart';
import 'package:libbird_example/browser.dart';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      themeMode: .dark,
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Color.fromARGB(255, 18, 34, 127),
          brightness: .dark,
        ),
      ),
      theme: ThemeData.dark(),
      home: BrowserWindow(),
    );
  }
}
