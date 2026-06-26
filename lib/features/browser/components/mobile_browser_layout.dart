import 'package:bird_core/bird_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutterbird/features/browser/components/browser_window.dart';
import 'package:flutterbird/features/browser/components/mobile_omnibox_bar.dart';

class MobileBrowserLayout extends ConsumerWidget {
  final int viewId;

  const MobileBrowserLayout({super.key, required this.viewId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentTabController = ref.watch(browserTabProvider(viewId));

    if (currentTabController == null) {
      return const SizedBox.shrink();
    }

    return Scaffold(
      body: Column(
        children: [
          MobileOmniboxBar(currentTabController: currentTabController),
          Expanded(child: BrowserWindow(viewId: viewId)),
        ],
      ),
    );
  }
}
