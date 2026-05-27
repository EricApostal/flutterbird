import 'dart:io';

import 'package:bird_core/bird_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutterbird/features/browser/components/browser_window.dart';
import 'package:flutterbird/features/browser/components/tab_bar.dart';
import 'package:go_router/go_router.dart';

class BrowserWindowScreen extends ConsumerStatefulWidget {
  final int viewId;
  const BrowserWindowScreen({super.key, required this.viewId});

  @override
  ConsumerState<BrowserWindowScreen> createState() =>
      _BrowserWindowScreenState();
}

class _BrowserWindowScreenState extends ConsumerState<BrowserWindowScreen> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    super.dispose();
  }

  bool _isPrimaryShortcutModifierPressed() {
    final pressed = HardwareKeyboard.instance.logicalKeysPressed;
    final hasControl =
        pressed.contains(LogicalKeyboardKey.controlLeft) ||
        pressed.contains(LogicalKeyboardKey.controlRight);
    final hasMeta =
        pressed.contains(LogicalKeyboardKey.metaLeft) ||
        pressed.contains(LogicalKeyboardKey.metaRight);
    return hasControl || hasMeta;
  }

  void _openNewTab() {
    final controller = ref.read(browserTabControllerProvider.notifier).add();
    context.go('/browser/tab/${controller.viewId}');
  }

  void _closeCurrentTab() {
    final tabs = ref.read(browserTabControllerProvider);
    if (tabs.isEmpty) return;

    final currentIndex = tabs.indexWhere((tab) => tab.viewId == widget.viewId);
    if (currentIndex < 0) return;

    if (tabs.length == 1) {
      exit(0);
    }

    final destinationIndex = currentIndex == 0 ? 1 : currentIndex - 1;
    context.go('/browser/tab/${tabs[destinationIndex].viewId}');
    ref.read(browserTabControllerProvider.notifier).remove(widget.viewId);
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (!_isPrimaryShortcutModifierPressed()) return false;

    if (event.logicalKey == LogicalKeyboardKey.keyT) {
      _openNewTab();
      return true;
    }

    if (event.logicalKey == LogicalKeyboardKey.keyW) {
      _closeCurrentTab();
      return true;
    }

    return false;
  }

  @override
  Widget build(BuildContext context) {
    final viewId = widget.viewId;

    return Scaffold(
      body: Column(
        children: [
          BrowserTabBar(currentViewId: viewId),
          Expanded(child: BrowserWindow(viewId: viewId)),
        ],
      ),
      // body: Center(child: Text("bruh")),
    );
  }
}
