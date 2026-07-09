import 'package:bird_core/bird_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutterbird/features/browser/components/mobile_omnibox_bar.dart';
import 'package:flutterbird/features/browser/components/tab_swipe_back_stack.dart';
import 'package:flutterbird/features/browser/state/fullscreen_mode.dart';

class MobileBrowserLayout extends ConsumerWidget {
  final int viewId;

  const MobileBrowserLayout({super.key, required this.viewId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentTabController = ref.watch(browserTabProvider(viewId));
    final isFullscreen = ref.watch(browserFullscreenModeControllerProvider);

    if (currentTabController == null) {
      return const SizedBox.shrink();
    }

    return Scaffold(
      body: Column(
        children: [
          if (!isFullscreen)
            MobileOmniboxBar(currentTabController: currentTabController),
          Expanded(child: TabSwipeBackStack(viewId: viewId)),
        ],
      ),
    );
  }
}
