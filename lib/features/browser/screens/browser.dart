import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:bird_core/bird_core.dart';
import 'package:flutterbird/features/browser/components/browser_window.dart';
import 'package:flutterbird/features/browser/components/tab_bar.dart';

class BrowserWindowScreen extends ConsumerWidget {
  final int windowId;
  final int? routedViewId;

  const BrowserWindowScreen({
    super.key,
    required this.windowId,
    this.routedViewId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final window = ref.watch(browserWindowStateProvider(windowId));
    if (window == null || window.tabIds.isEmpty) {
      return const Scaffold(
        body: Center(child: Text('No tabs in this window')),
      );
    }

    final targetViewId =
        routedViewId ?? window.activeViewId ?? window.tabIds.first;
    final resolvedViewId = window.tabIds.contains(targetViewId)
        ? targetViewId
        : window.tabIds.first;

    return Scaffold(
      body: Column(
        children: [
          BrowserTabBar(windowId: windowId, currentViewId: resolvedViewId),
          Expanded(child: BrowserWindow(viewId: resolvedViewId)),
        ],
      ),
    );
  }
}
