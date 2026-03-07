import 'package:bitsdojo_window/bitsdojo_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutterbird/features/browser/components/browser_window.dart';
import 'package:flutterbird/features/browser/components/tab_bar.dart';

class BrowserWindowScreen extends ConsumerWidget {
  final int viewId;
  const BrowserWindowScreen({super.key, required this.viewId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Column(
        children: [
          SizedBox(
            height: 45,
            child: MoveWindow(child: BrowserTabBar(viewId: viewId)),
          ),
          Expanded(child: BrowserWindow(viewId: viewId)),
        ],
      ),
    );
  }
}
