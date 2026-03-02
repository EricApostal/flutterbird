import 'package:flutter/material.dart';
import 'package:libbird/libbird.dart';

void main() {
  runApp(const MainApp());
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> {
  final _controller = LadybirdController();
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: LadybirdView(controller: _controller),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            _controller.navigate("https://www.google.com");
          },
        ),
      ),
    );
  }
}
