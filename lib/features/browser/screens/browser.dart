import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutterbird/features/browser/components/browser_window.dart';
import 'package:flutterbird/features/browser/components/tab_bar.dart';

class BrowserWindowScreen extends ConsumerStatefulWidget {
  const BrowserWindowScreen({super.key});

  @override
  ConsumerState<ConsumerStatefulWidget> createState() => _BrowserWindowState();
}

class _BrowserWindowState extends ConsumerState<BrowserWindowScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Flexible(child: SizedBox(child: BrowserTabBar(), height: 50)),
          Expanded(child: BrowserWindow()),
        ],
      ),
    );
  }
}
