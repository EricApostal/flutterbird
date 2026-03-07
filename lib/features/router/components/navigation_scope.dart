import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter/material.dart';
import 'package:flutterbird/features/browser/components/tab_bar.dart';

class NavigationScope extends StatelessWidget {
  final Widget child;
  const NavigationScope({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          SizedBox(height: 45, child: MoveWindow(child: BrowserTabBar())),
          Expanded(child: child),
        ],
      ),
    );
  }
}
